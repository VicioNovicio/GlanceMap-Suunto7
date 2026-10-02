# GlanceMap for Suunto 7 / Wear OS 2 (API 28)

Unofficial compatibility build of **GlanceMap** for the **Suunto 7** and other Wear OS 2 / Android 9 (API 28) devices.

This fork keeps the current GlanceMap codebase while adding the compatibility changes needed to run on Android 9 / API 28.

## Tested hardware

- **Suunto 7**
- Wear OS 2
- Android 9 / API 28

## Tested on a physical Suunto 7

The following have been tested successfully:

- App launch
- Offline OpenAndroMaps rendering
- GPS positioning
- Zoom and pan
- Spain–Portugal offline map
- Routing / standard elevation data included with the downloaded map package
- Offline POIs
- Companion app detection / Wear OS Data Layer communication
- Offline operation after map installation

### Startup performance observed

- Debug build: approximately **30–40 seconds** until fully usable
- Optimized benchmark build: approximately **5 seconds**

The optimized benchmark build is therefore the recommended build for normal use on the Suunto 7.

---

# Downloads

For the watch:

```text
GlanceMap-Suunto7-v1-benchmark.apk
```

For the Android phone:

```text
GlanceMap-Companion-v1.apk
```

A debug APK may also be provided for development and diagnostics.

---

# Signing

The Wear OS benchmark APK, Wear OS debug APK and Companion APK in this fork use the same persistent signing identity.

This allows:

- Wear OS Data Layer communication between the watch and Companion app
- Installing future updates over an existing build signed with the same key
- Using `adb install -r` without deleting app data, maps or settings

If another GlanceMap build signed with a different key is already installed, Android will reject the update. In that situation the old version must be uninstalled first.

> **Warning:** uninstalling GlanceMap deletes its private application data, including maps stored inside the app.

Never publish or commit the keystore, passwords or GitHub signing secrets.

---

# Installing on the Suunto 7

## 1. Enable developer options

On the watch:

1. Open **Settings**
2. Open **System → About**
3. Tap the build number repeatedly until Developer Options are enabled
4. Open **Developer options**
5. Enable **ADB debugging**
6. Enable **Debug over Wi-Fi**

The watch will show an address similar to:

```text
192.168.1.128:5555
```

The IP address can change after reconnecting to Wi-Fi.

The PC and watch must be on the same network.

## 2. Connect with ADB

From the Android SDK `platform-tools` directory:

```powershell
.\adb.exe connect 192.168.1.128:5555
```

Check the connection:

```powershell
.\adb.exe devices
```

If an emulator is connected at the same time, always include the physical watch address:

```text
-s 192.168.1.128:5555
```

## 3. Install the optimized build

```powershell
.\adb.exe -s 192.168.1.128:5555 install "GlanceMap-Suunto7-v1-benchmark.apk"
```

To update an existing build signed with the same key:

```powershell
.\adb.exe -s 192.168.1.128:5555 install -r "GlanceMap-Suunto7-v1-benchmark.apk"
```

---

# Maps

GlanceMap can download supported maps directly on the watch. Maps can also be transferred using the Companion app.

On the tested Suunto 7, the Spain–Portugal package includes the map plus the standard routing/elevation data offered by GlanceMap.

Check free storage before installing a large region:

```powershell
.\adb.exe -s 192.168.1.128:5555 shell df -h /data
```

## Important workaround for a blank/white map

During testing on the physical Suunto 7, there was a case where a map downloaded directly on the watch, or transferred through the Companion workflow, was recognized by GlanceMap but the map view remained **completely white**.

The same OpenAndroMaps file, transferred from the PC into GlanceMap's private `app_maps` directory with the verified ADB chunk-transfer script below, **rendered correctly**.

Therefore, if:

- the map appears installed/selected,
- GPS positioning works,
- but the map area remains white,

use:

```text
transfer_map_verified_v2.ps1
```

to transfer the `.map` file from the PC.

This is a **tested workaround on the Suunto 7**. It does not prove that every blank-map case has the same cause.

---

# Verified ADB map transfer script

The recommended script is:

```text
transfer_map_verified_v2.ps1
```

This is the version that was tested successfully on the physical Suunto 7.

Unlike a simple `adb push`, it:

- transfers the map in **256 MiB blocks**
- reads/writes each block using a **4 MiB buffer**
- calculates the **SHA-256 of the original map**
- calculates and verifies the **SHA-256 of every transferred block**
- retries a failed block up to **3 times**
- checks the accumulated destination size after every block
- verifies the **complete SHA-256 of the final map on the watch**
- stops GlanceMap before replacing the map
- removes temporary transfer files

This also avoids needing enough storage for two complete copies of a multi-gigabyte map at the same time.

## Requirements

The installed build must allow:

```powershell
run-as com.glancemap.glancemapwearos
```

Test it with:

```powershell
.\adb.exe -s 192.168.1.128:5555 shell run-as com.glancemap.glancemapwearos pwd
```

If Android returns:

```text
run-as: package not debuggable: com.glancemap.glancemapwearos
```

that build cannot use this private-directory transfer method.

The tested Suunto 7 build used for this workaround allowed `run-as`.

## Configure the script

Open:

```text
transfer_map_verified_v2.ps1
```

and edit the configuration section at the top.

Example:

```powershell
$Adb = "C:\Users\YOURNAME\AppData\Local\Android\Sdk\platform-tools\adb.exe"
$Device = "192.168.1.128:5555"
$Package = "com.glancemap.glancemapwearos"
$Source = "C:\Users\YOURNAME\Downloads\Spain-Portugal_oam.osm.map"
$RemoteName = "Spain-Portugal_oam.osm.map"
$RemoteTemp = "/sdcard/Download/glancemap-part.bin"
$ChunkFile = "C:\Users\YOURNAME\Downloads\glancemap-part.bin"
```

Change at least:

- `$Adb` if your Android SDK is elsewhere
- `$Device` to the current watch IP
- `$Source` to the `.map` file on your PC
- `$RemoteName` if the map filename is different
- `$ChunkFile` if you want the temporary PC block somewhere else

## Run the script

Open PowerShell in the folder containing the script and run:

```powershell
.\transfer_map_verified_v2.ps1
```

The script will:

1. verify ADB connectivity
2. verify `run-as`
3. stop GlanceMap
4. create `app_maps`
5. remove any previous file with the same destination name
6. split and transfer the map in verified blocks
7. append each verified block into the private map file
8. check the accumulated file size
9. calculate the complete SHA-256 on the watch
10. compare it with the original PC file

A successful transfer ends with:

```text
==============================================
OK: MAPA COPIADO ÍNTEGRO Y VERIFICADO SHA-256
==============================================
```

Only after that should GlanceMap be opened.

## Create `app_maps` manually

Normally the verified script creates the folder itself.

If you need to create it manually:

```powershell
.\adb.exe -s 192.168.1.128:5555 shell "run-as com.glancemap.glancemapwearos mkdir -p app_maps"
```

## Check the installed map

```powershell
.\adb.exe -s 192.168.1.128:5555 shell "run-as com.glancemap.glancemapwearos ls -lh app_maps"
```

Note: some old Android/Wear OS command-line utilities may display incorrect negative byte counts for files larger than 2 GiB because of 32-bit integer overflow. The verified script avoids relying on that as its final integrity check and performs SHA-256 verification.

---

# POIs

POI packages can be downloaded directly from GlanceMap on the watch.

For example, the Spain–Portugal POI ZIP is separate from the `.map` file.

POIs provide offline POI lookup/search and are independent of the visual map.

---

# GPX

GPX files are route/track files.

They are independent of the base map and can be added only when needed.

---

# Companion app

Install:

```text
GlanceMap-Companion-v1.apk
```

on the Android phone.

The Companion APK in this fork is signed with the same identity as the Wear OS APK, allowing Wear OS Data Layer communication.

If another Companion build signed with a different key is already installed on the phone, it may need to be uninstalled before installing this one.

---

# Updating without losing maps

When the currently installed APK and the new APK use the same signing key, use:

```powershell
.\adb.exe -s 192.168.1.128:5555 install -r "GlanceMap-Suunto7-v1-benchmark.apk"
```

Do **not** uninstall first unless necessary.

Uninstalling deletes the app's private maps and settings.

---

# Troubleshooting

## ADB no longer connects

The watch IP may have changed.

Check:

**Developer options → Debug over Wi-Fi**

Then reconnect using the new address:

```powershell
.\adb.exe connect NEW_IP:5555
```

## Map is installed but the screen is white

First check:

1. The correct map is selected in GlanceMap
2. GPS has obtained a valid position inside the map coverage
3. The map download/transfer completed
4. There is enough storage
5. The map is present in `app_maps`

For a build that supports `run-as`:

```powershell
.\adb.exe -s WATCH_IP:5555 shell "run-as com.glancemap.glancemapwearos ls -lh app_maps"
```

If the map was downloaded on the watch or transferred using Companion and still remains white, use the tested:

```text
transfer_map_verified_v2.ps1
```

workflow described above. On the tested Suunto 7, transferring the same map from the PC with this script fixed the white-map condition and the map rendered normally.

## Check available storage

```powershell
.\adb.exe -s WATCH_IP:5555 shell df -h /data
```

---

# API 28 compatibility changes

This fork includes compatibility work for Android 9 / API 28, including:

- API 28-compatible location handling
- compatibility guards/fallbacks for newer Android tracing APIs
- Suunto 7 / Wear OS 2 build configuration
- optimized benchmark build for substantially faster startup on the tested Suunto 7

---

# Upstream project

This is an unofficial compatibility fork of GlanceMap.

Original project:

https://github.com/GlanceMap/GlanceMap

Refer to the upstream project for the original application, documentation and license.

This fork is not an official Suunto release and is not affiliated with Suunto.
