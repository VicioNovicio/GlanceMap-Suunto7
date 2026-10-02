$ErrorActionPreference = "Stop"

# ---- Configuración ----
$Adb = "C:\Users\XXXXX\AppData\Local\Android\Sdk\platform-tools\adb.exe"
$Device = "192.168.1.128:5555"
$Package = "com.glancemap.glancemapwearos"
$Source = "C:\Users\XXXXX\Downloads\Spain-Portugal_oam.osm.map"
$RemoteName = "Spain-Portugal_oam.osm.map"
$RemoteTemp = "/sdcard/Download/glancemap-part.bin"
$ChunkFile = "C:\Users\XXXXX\Downloads\glancemap-part.bin"

# 256 MiB por bloque: 9 bloques aprox. para este mapa
$ChunkSize = 256MB
$BufferSize = 4MB
$MaxPushRetries = 3

function Run-Adb {
    param([Parameter(ValueFromRemainingArguments=$true)][string[]]$Args)
    $output = & $Adb @Args 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "ADB devolvió error ($LASTEXITCODE):`n$($output -join "`n")"
    }
    return $output
}

function Get-RemotePrivateSize {
    $line = (Run-Adb -s $Device shell "run-as $Package ls -l app_maps/$RemoteName") | Select-Object -Last 1
    $parts = ($line -split '\s+') | Where-Object { $_ -ne "" }
    if ($parts.Count -lt 5) {
        throw "No pude interpretar el tamaño remoto: $line"
    }
    return [int64]$parts[4]
}

if (-not (Test-Path $Adb)) {
    throw "No encuentro adb.exe en: $Adb"
}
if (-not (Test-Path $Source)) {
    throw "No encuentro el mapa en: $Source"
}

$sourceInfo = Get-Item $Source
$SourceSize = [int64]$sourceInfo.Length
Write-Host "Mapa origen: $Source"
Write-Host "Tamaño: $SourceSize bytes"
Write-Host "Calculando SHA-256 del mapa original..."
$SourceHash = (Get-FileHash -Algorithm SHA256 $Source).Hash.ToLower()
Write-Host "SHA-256 PC: $SourceHash"
Write-Host ""

# Confirmar conexión y que run-as funciona
Run-Adb -s $Device get-state | Out-Null
$runAsTest = Run-Adb -s $Device shell "run-as $Package pwd"
Write-Host "run-as OK: $($runAsTest | Select-Object -Last 1)"

# Cerrar GlanceMap y empezar desde cero
Write-Host "Preparando carpeta privada..."
Run-Adb -s $Device shell "am force-stop $Package" | Out-Null
Run-Adb -s $Device shell "run-as $Package mkdir -p app_maps" | Out-Null
Run-Adb -s $Device shell "run-as $Package rm -f app_maps/$RemoteName" | Out-Null
Run-Adb -s $Device shell "rm -f $RemoteTemp" | Out-Null

$src = [System.IO.File]::OpenRead($Source)
$buffer = New-Object byte[] $BufferSize
$transferred = [int64]0
$part = 0

try {
    while ($transferred -lt $SourceSize) {
        $part++
        $remaining = $SourceSize - $transferred
        $thisChunk = [Math]::Min([int64]$ChunkSize, $remaining)

        Write-Host ""
        Write-Host "=== BLOQUE $part | offset $transferred | $thisChunk bytes ==="

        # Crear el bloque local sin cargar 256 MiB completos en RAM
        $dst = [System.IO.File]::Create($ChunkFile)
        try {
            $written = [int64]0
            while ($written -lt $thisChunk) {
                $want = [int][Math]::Min([int64]$buffer.Length, $thisChunk - $written)
                $read = $src.Read($buffer, 0, $want)
                if ($read -le 0) {
                    throw "Fin inesperado del archivo origen."
                }
                $dst.Write($buffer, 0, $read)
                $written += $read
            }
        }
        finally {
            $dst.Dispose()
        }

        $localChunkSize = (Get-Item $ChunkFile).Length
        if ($localChunkSize -ne $thisChunk) {
            throw "Tamaño incorrecto del bloque local: $localChunkSize; esperado: $thisChunk"
        }

        $localHash = (Get-FileHash -Algorithm SHA256 $ChunkFile).Hash.ToLower()
        Write-Host "SHA-256 bloque PC: $localHash"

        # Push + verificación SHA-256. Reintenta hasta 3 veces.
        $verified = $false
        for ($attempt = 1; $attempt -le $MaxPushRetries; $attempt++) {
            Write-Host "Enviando bloque al Suunto (intento $attempt/$MaxPushRetries)..."
            Run-Adb -s $Device shell "rm -f $RemoteTemp" | Out-Null

            # No redirigimos stderr con 2>&1: adb escribe el progreso ahí y
            # Windows PowerShell 5.1 puede convertirlo erróneamente en NativeCommandError.
            & $Adb -s $Device push $ChunkFile $RemoteTemp
            $pushExit = $LASTEXITCODE
            if ($pushExit -ne 0) {
                Write-Warning "adb push falló con código $pushExit."
                continue
            }

            $remoteHashLine = (Run-Adb -s $Device shell "toybox sha256sum $RemoteTemp") | Select-Object -Last 1
            $remoteHash = (($remoteHashLine -split '\s+')[0]).ToLower()
            Write-Host "SHA-256 bloque Suunto: $remoteHash"

            if ($remoteHash -eq $localHash) {
                $verified = $true
                break
            }

            Write-Warning "HASH NO COINCIDE. Se repetirá el envío de este bloque."
        }

        if (-not $verified) {
            throw "No se pudo transferir el bloque $part sin errores después de $MaxPushRetries intentos."
        }

        # Solo después de verificar el bloque, incorporarlo al mapa privado.
        Write-Host "Bloque verificado. Incorporándolo al mapa..."
        Run-Adb -s $Device shell "cat $RemoteTemp | run-as $Package sh -c 'cat >> app_maps/$RemoteName'" | Out-Null

        $transferred += $thisChunk
        $remotePrivateSize = Get-RemotePrivateSize
        Write-Host "Tamaño acumulado en Suunto: $remotePrivateSize / $SourceSize"

        if ($remotePrivateSize -ne $transferred) {
            throw "ERROR DE TAMAÑO tras el bloque $part. Suunto=$remotePrivateSize; esperado=$transferred"
        }

        Run-Adb -s $Device shell "rm -f $RemoteTemp" | Out-Null
    }
}
finally {
    $src.Dispose()
    if (Test-Path $ChunkFile) {
        Remove-Item $ChunkFile -Force
    }
}

Write-Host ""
Write-Host "Transferencia por bloques terminada."
$FinalSize = Get-RemotePrivateSize
if ($FinalSize -ne $SourceSize) {
    throw "Tamaño final incorrecto. Suunto=$FinalSize; PC=$SourceSize"
}

Write-Host "Tamaño final correcto: $FinalSize bytes"
Write-Host "Calculando SHA-256 COMPLETO en el Suunto (puede tardar varios minutos)..."

$remoteFullHashLine = (Run-Adb -s $Device shell "run-as $Package cat app_maps/$RemoteName | toybox sha256sum") | Select-Object -Last 1
$RemoteHash = (($remoteFullHashLine -split '\s+')[0]).ToLower()

Write-Host "SHA-256 PC:     $SourceHash"
Write-Host "SHA-256 Suunto: $RemoteHash"

if ($RemoteHash -ne $SourceHash) {
    throw "ERROR: el SHA-256 final NO coincide. No abras GlanceMap."
}

Write-Host ""
Write-Host "=============================================="
Write-Host "OK: MAPA COPIADO ÍNTEGRO Y VERIFICADO SHA-256"
Write-Host "=============================================="
