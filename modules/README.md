# KSU Modules

These KernelSU Next modules are optional companions for the kernel.

## boot-props — Boot Props Persistence

Persistently sets bootloader status props for Play Integrity. Works around an IntegrityBox `resetprop_if_diff` bug that skips non-existent props.

**Required for:** Play Integrity DEVICE pass after reboot (without manual `resetprop`)

**What it does:**
1. At `post-fs-data` (before any app starts), sets:
   - `ro.boot.verifiedbootstate = green`
   - `ro.boot.flash.locked = 1`
   - `ro.boot.vbmeta.device_state = locked`
   - `vendor.boot.verifiedbootstate = green`
   - `vendor.boot.vbmeta.device_state = locked`
   - `sys.oem_unlock_allowed = 0`
   - `ro.oem_unlock_supported = 0`
2. Uses `resetprop -n` (can create non-existent props)
3. As a side effect, also prevents the `OemUnlockPreferenceController` crash (see [LSPOSED-AND-INTEGRITY.md Part 6](../LSPOSED-AND-INTEGRITY.md#part-6-oemfix--developer-settings-crash-fix))

**Install:**
```bash
adb shell "su -c 'mkdir -p /data/adb/modules/boot-props'"
adb push module.prop /data/local/tmp/
adb push post-fs-data.sh /data/local/tmp/
adb shell "su -c 'cp /data/local/tmp/module.prop /data/adb/modules/boot-props/'"
adb shell "su -c 'cp /data/local/tmp/post-fs-data.sh /data/adb/modules/boot-props/'"
adb shell "su -c 'chmod 755 /data/adb/modules/boot-props/post-fs-data.sh'"
adb shell "su -c 'chmod 644 /data/adb/modules/boot-props/module.prop'"
adb reboot
```

**Verify:**
```bash
adb shell "getprop ro.boot.verifiedbootstate"   # green
adb shell "getprop ro.boot.flash.locked"        # 1
adb shell "getprop ro.boot.vbmeta.device_state" # locked
```

## oemfix — Developer Settings Crash Fix (LSPosed)

Fixes `OemUnlockPreferenceController` NPE crash in Developer Settings on OOS 11.

**Required for:** Opening Developer Settings without crash (safety net — boot-props module prevents the crash at boot time)

**What it does:**
- Hooks `updateState()` and `isOemUnlockedAllowed()` in `OemUnlockPreferenceController`
- If `mOemLockManager` is null, skips the call instead of crashing
- 12.8 KB APK, built without Gradle

**Build:**
```bash
cd modules/oemfix
./build.sh
adb install --no-incremental build/oemfix-signed.apk
```

**Configure in LSPosed:**
- Scope: `com.android.settings` (user 0)
- Enable module in LSPosed manager
- Reboot (or kill zygote) for LSPosed to reload

See [LSPOSED-AND-INTEGRITY.md Part 6](../LSPOSED-AND-INTEGRITY.md#part-6-oemfix--developer-settings-crash-fix) for root cause analysis.

## meta-kirisakura — Shell-based OverlayFS MetaModule

Custom metamodule for KSU Next v3.1.0 on kernel 4.14. The official `meta-overlayfs` v1.3.1 (Rust binary) fails on kernel 4.14 because `fsopen()` is unavailable (ENOSYS).

**What it does:**
- Parses `/proc/mounts` to build vendor overlay map (e.g., `/system/india/app → /system/product/app`)
- Mounts overlayfs for all enabled KSU modules with `system/` directories
- Uses `mount -t overlay KSU -o ro,context=u:object_r:system_file:s0,lowerdir=...`
- Resolves deep module paths to vendor overlay mount points
- Groups multiple modules targeting the same path

**Why it exists:**
- KSU Next v3.1.0 replaced built-in overlayfs with the metamodule system
- Official `meta-overlayfs` uses `fsopen()` (new mount API) — unavailable on kernel 4.14
- This shell-based alternative uses traditional `mount()` syscall — works on 4.14

**Critical:** SELinux context `u:object_r:system_file:s0` must be specified. Without it, overlay files get wrong labels and `/system/bin/sh` becomes inaccessible.

**Install:**
```bash
adb shell "su -c 'mkdir -p /data/adb/modules/meta-kirisakura'"
adb push module.prop /data/local/tmp/
adb push metamount.sh /data/local/tmp/
adb push metauninstall.sh /data/local/tmp/
adb push service.sh /data/local/tmp/
adb shell "su -c 'cp /data/local/tmp/{module.prop,metamount.sh,metauninstall.sh,service.sh} /data/adb/modules/meta-kirisakura/'"
adb shell "su -c 'chmod 755 /data/adb/modules/meta-kirisakura/*.sh'"
adb shell "su -c 'ln -sf /data/adb/modules/meta-kirisakura /data/adb/metamodule'"
adb reboot
```

## vpnhide-kmod — VPNHide Built-in Management

Manages target app UIDs for the built-in VPNHide kernel hooks (`CONFIG_VPNHIDE=y`).

**Required for:** VPN interface hiding from selected apps

**What it does:**
1. At boot, verifies `/proc/vpnhide_targets` exists (kernel built-in is active)
2. Resolves package names from `targets.txt` to UIDs via `pm list packages -U`
3. Writes UIDs to `/proc/vpnhide_targets`
4. Writes load status to `/data/adb/vpnhide_kmod/load_status` for app diagnostics

**Install:**
```bash
adb push vpnhide-builtin-module.zip /data/local/tmp/
adb shell "su -c 'ksud module install /data/local/tmp/vpnhide-builtin-module.zip'"
adb reboot
```

**Configure targets:**
- Install the [VPN Hide app](https://github.com/okhsunrog/vpnhide) for GUI management, or
- Edit `/data/adb/vpnhide_kmod/targets.txt` (one package name per line), then reboot

## vpn-tether — Moved to separate repo

VPN Tether is now a standalone project, independent of this kernel:

**Repo:** [DurkaEbanaya/vpn-tether](https://github.com/DurkaEbanaya/vpn-tether)

It works on any device with KernelSU — not specific to Kirisakura kernel.

> **Note:** The `ipv6nat` module from v2.1 is **no longer needed** as of v2.2. IPv6 NAT and all tetherctrl chains are now built directly into the kernel — no userspace module required for hotspot/tethering.
