# RVT-Replace YouTube Overlay Crash — Diagnosis & Fix

## Summary

Using a KSU overlay module (`rvt-replace`) to systemlessly replace YouTube with a patched APK causes `system_server` crash → soft reboot when any Settings page calls `getInstalledModules()`. The root cause is a signature mismatch between the overlay APK and the package manager's expected signature, which breaks `ModuleInfoProvider` in `system_server`.

This document is intended for colleagues working on KSU overlay modules or systemless APK replacement.

---

## Environment

- **Device:** OnePlus 7 Pro (guacamole), GM1910, OOS 11 `GM1910_21_220617`
- **Kernel:** Kirisakura 4.14.243 with KSU Next v3.1.0-legacy
- **Mount system:** Custom shell-based metamodule (`meta-kirisakura`) using `mount -t overlay`
- **YouTube:** Patched APK v20.40.45 (181 MB), signed with a different key than Google's
- **rvt-replace module:** KSU module that places patched APKs in `system/india/app/YouTube/` → overlay mounts on `/system/product/app`

---

## Symptom

Opening any of the following triggers an immediate soft reboot:

1. **Developer Settings** — `com.android.settings/.Settings$DevelopmentSettingsDashboardActivity`
2. **App info** in Integrity Checker (`gr.nikolasspyr.integritycheck`)
3. **Any Settings page** that calls `getInstalledModules()` or `getModuleInfo()`

The crash is not in the Settings process itself — it's in `system_server`, which takes down the entire framework.

---

## Crash log

```
E AndroidRuntime: FATAL EXCEPTION: main
E AndroidRuntime: Process: system_server, PID: 1760
E AndroidRuntime: java.lang.IllegalStateException: Call to getModuleInfo before metadata loaded
E AndroidRuntime:     at com.android.server.pm.ModuleInfoProvider.getModuleInfo(ModuleInfoProvider.java:??)
E AndroidRuntime:     at com.android.server.pm.ModuleInfoProvider.getInstalledModules(ModuleInfoProvider.java:??)
E AndroidRuntime:     at android.os.IPackageManager$Stub.onTransact(IPackageManager.java:??)
E AndroidRuntime:     at com.android.server.SystemServer.onTransact(SystemServer.java:??)
```

After `system_server` crashes, `ActivityManager` restarts it, but the same crash recurs → bootloop or soft reboot.

---

## Root cause

### How the overlay works

The OnePlus 7 Pro has vendor overlays from factory:

```
overlay /system/product/app  overlay  ro,context=u:object_r:system_file:s0,
  lowerdir=/system/india/app:/product/app
```

The `rvt-replace` KSU module places a patched YouTube APK at:

```
/data/adb/modules/rvt-replace/system/india/app/YouTube/YouTube.apk
```

The `meta-kirisakura` metamodule stacks another overlay on top:

```
mount -t overlay KSU -o ro,context=u:object_r:system_file:s0,
  lowerdir=/data/adb/modules/rvt-replace/system/india/app/YouTube:/system/india/app:/product/app
  /system/product/app
```

Result: `/system/product/app/YouTube/YouTube.apk` resolves to the patched APK.

### Why it crashes

1. `PackageManagerService` (PMS) scans `/system/product/app/YouTube/YouTube.apk` at boot
2. PMS reads the APK's signature — it's the **patcher's key**, not Google's key
3. PMS registers YouTube with the wrong signature in `PackageParser`
4. When `getInstalledModules()` is called, `ModuleInfoProvider` iterates all packages
5. For YouTube, it tries to load `ModuleInfo` from the APK's metadata
6. The signature mismatch causes the metadata loading to fail
7. `ModuleInfoProvider` throws `IllegalStateException: Call to getModuleInfo before metadata loaded`
8. This exception propagates to `system_server` → crash → soft reboot

### Why `pm install` works but overlay doesn't

When YouTube is installed via `pm install`:
- PMS treats it as a **user-installed package** (not a system app)
- PMS stores the signature in `/data/system/packages.xml`
- `ModuleInfoProvider` skips user-installed packages — only system packages trigger `getModuleInfo`
- No crash

When YouTube is in the overlay:
- PMS treats it as a **system app** (it's in `/system/product/app/`)
- PMS expects system apps to have valid module metadata
- The signature mismatch breaks metadata loading
- `ModuleInfoProvider` crashes

---

## Fix

### Immediate fix

1. **Disable rvt-replace module:**
   ```bash
   adb shell "su -c 'touch /data/adb/modules/rvt-replace/disable'"
   ```

2. **Install patched YouTube via `pm install`:**
   ```bash
   adb install --no-incremental YouTube_v20.40.45_patched.apk
   ```

3. **Reboot**

### Why `--no-incremental` is required

Incremental installation (`adb install` without `--no-incremental`) uses incremental APK delivery. The APK is not fully present on device — only blocks that are read are fetched. LSPosed and other Zygisk modules cannot see the full APK at boot time, causing them to skip the app. Always use `--no-incremental` for patched APKs.

---

## Key takeaways for module developers

1. **Do NOT use overlayfs to replace system apps with differently-signed APKs.** The package manager treats overlay-mounted APKs as system apps and expects valid signatures/metadata. A signature mismatch breaks `ModuleInfoProvider` → `system_server` crash.

2. **Use `pm install` for patched APKs.** User-installed packages are not subject to `ModuleInfoProvider` checks. The patched APK replaces the system app without touching the overlay.

3. **If you must use overlayfs for APK replacement**, ensure the replacement APK has the **same signature** as the original. This is usually impossible for Google apps (you don't have Google's signing key).

4. **The crash affects any code path that calls `getInstalledModules()` or `getModuleInfo()`** — not just Settings. Any app or system component that queries installed modules will trigger the crash.

5. **`pm clear com.android.settings` does NOT fix this.** The crash is in `system_server`, not in Settings. Clearing Settings data only resets the activity component enabled state (see OemFix issue).

6. **The crash may be masked by other crashes.** In our case, the `OemUnlockPreferenceController` NPE crash (see [LSPOSED-AND-INTEGRITY.md Part 6](LSPOSED-AND-INTEGRITY.md)) happened first, masking this crash. Only after fixing the OemUnlock crash did the `ModuleInfoProvider` crash become visible.

---

## Related: mitm-cert overlay conflict

A related issue was found with the `mitm-cert` module. The module's `post-fs-data.sh` created a tmpfs bind-mount on `/system/etc/security/cacerts` BEFORE the metamodule overlay mounted on the same path. Both tmpfs and overlay mounted on the same path caused:

```
EACCES (Permission denied) reading CA certs
DirectoryCertificateSrc: Failed to read certificate from 1e8e7201.0
SSL handshake failure in apps
```

**Fix:** Remove the module's own `post-fs-data.sh` when using the metamodule system. The metamodule handles the overlay mount — modules must NOT have their own mount scripts for paths that the overlay covers.

```bash
adb shell "su -c 'rm /data/adb/modules/mitm-cert/post-fs-data.sh'"
```

---

## Related: meta-overlayfs v1.3.1 does NOT work on kernel 4.14

The official KSU Next meta-overlayfs module (v1.3.1, Rust binary) fails on kernel 4.14:

```
fsopen() → ENOSYS (function not implemented)
mount() fallback → ENOSYS
```

Kernel 4.14 does not implement the new mount API (`fsopen()`/`fspick()`/`move_mount()`). The fallback `mount()` syscall also returns `ENOSYS` for the specific parameters used.

**Solution:** A custom shell-based metamodule (`meta-kirisakura`) that uses `mount -t overlay` directly:

```bash
mount -t overlay KSU -o ro,context=u:object_r:system_file:s0,\
  lowerdir=/data/adb/modules/<id>/system/<path>:/system/<path> \
  /system/<path>
```

This works on kernel 4.14 because it uses the traditional `mount()` syscall with the `overlay` filesystem type, not the new mount API.

**Critical:** The SELinux context `u:object_r:system_file:s0` must be specified. Without it, overlay files get wrong SELinux labels and `/system/bin/sh` becomes inaccessible (`Permission denied`).

Source: [`meta-kirisakura/metamount.sh`](modules/meta-kirisakura/metamount.sh) — ~200 lines of shell script.
