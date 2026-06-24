# Kirisakura-KSU-Next — OnePlus 7 Pro (guacamole)

Custom kernel **Kirisakura 4.14.243** with **KernelSU-Next v3.1.0-legacy** (version 33024) for OnePlus 7 Pro on stock OxygenOS 11 (`GM1910_21_220617`, Android 11).

**Working:** Root (KSU Next) · FOD fingerprint · WiFi · Bluetooth · SELinux Enforcing

---

## Why this kernel

The stock OnePlus 7 Pro kernel (4.14.190) works fine, but there was no KSU-Next integration that preserved FOD. LineageOS-derived kernels break the fingerprint display pipeline (see [Root cause](#fod-root-cause) below). This kernel uses [Kirisakura](https://github.com/freak07/Kirisakura_OP7Pro_A11) — built directly from OnePlus OSS sources for Android 11 — which keeps the stock FOD display path intact while adding 53 linux-stable sublevels, EAS scheduler backports, and other improvements.

## What's in this kernel

| Feature | Value |
|---|---|
| Kernel base | Kirisakura 4.14.243 (`freak07/Kirisakura_OP7Pro_A11`, branch `master_stock_caf_linux-upstream_vdso32_sched_final_2`) |
| Defconfig | `stock_defconfig` (pure OnePlus stock, no CFI/LTO/SCS) |
| KernelSU-Next | v3.1.0-legacy, version 33024, manual hooks |
| FOD | Stock OOS path preserved — no `fod_property`, no `dimlayer_hbm` boolean, original `fppressed_index` plane-alpha handling |
| Wi-Fi (qcacld-3.0) | Built-in (`CONFIG_QCA_CLD_WLAN=y`) — no external module needed |
| MODULE_SIG_FORCE | Disabled — allows loading unsigned modules |
| SELinux | Enforcing (stock) — `selinux_state` moved from `__rticdata` to regular `.bss` |
| Boot header | v2 (A/B, standard AOSP) |
| Toolchain | Clang 14, LLD 14, GNU cross GCC 11 |

## Manual hooks (7 hooks in 7 files)

KernelSU-Next v3.1.0-legacy uses manual hooks (not kprobes) on kernels < 5.10:

| # | File | Function | Hook |
|---|---|---|---|
| 1 | `fs/exec.c` | `do_execveat_common()` | `ksu_handle_execveat()` |
| 2 | `fs/open.c` | `SYSCALL_DEFINE3(faccessat)` | `ksu_handle_faccessat()` |
| 3 | `fs/read_write.c` | `vfs_read()` | `ksu_handle_vfs_read()` |
| 4 | `fs/stat.c` | `SYSCALL_DEFINE4(newfstatat)` | `ksu_handle_stat()` |
| 5 | `kernel/reboot.c` | `SYSCALL_DEFINE4(reboot)` | `ksu_handle_sys_reboot()` |
| 6 | `kernel/sys.c` | `SYSCALL_DEFINE3(setresuid)` | `ksu_handle_setresuid()` |
| 7 | `drivers/input/input.c` | `input_handle_event()` | `ksu_handle_input_handle_event()` |

See `manual-hooks.patch` for the exact diff.

## Build fixes applied

| # | File | Problem | Fix |
|---|---|---|---|
| 1 | `scripts/gcc-wrapper.py` | Python 2 syntax (`print >> sys.stderr`) on Python 3 system | Rewritten for Python 3 |
| 2 | 78 Makefile/Kbuild files | `-Werror` triggers on GCC 11 / Clang 14 with 2019-era Qualcomm code | Relaxed `-Werror` → `-Wno-error` globally |
| 3 | `security/selinux/hooks.c` | `selinux_state __rticdata` causes `R_AARCH64_ADR_PREL_PG_HI21` relocation overflow | Removed `__rticdata` attribute (moves to regular `.bss`) |
| 4 | `drivers/platform/msm/ipa/ipa_v3/ipa_hw_stats.c` | `copy_from_user` without size guard at line 2072 — GCC 11 `__bad_copy_to` error | Added `min_t(size_t, count, sizeof(dbg_buff))` guard |
| 5 | `techpack/audio/soc/core.h`, `pinctrl-utils.h`, `include/soc/internal.h` | Broken symlinks (target files don't exist in tree) | Replaced with real file copies from `drivers/pinctrl/` and `drivers/base/regmap/` |
| 6 | `drivers/oneplus/oneplus_healthinfo/oneplus_healthinfo.c` | Missing `static struct timer_list task_load_info_timer` declaration — used in code but not declared | Added declaration |
| 7 | `arch/arm64/configs/stock_defconfig` | `CONFIG_QCA_CLD_WLAN` not set — WiFi driver not built | Enabled `CONFIG_QCA_CLD_WLAN=y` (built-in) |
| 8 | `arch/arm64/configs/stock_defconfig` | `CONFIG_MODULE_SIG_FORCE=y` — blocks unsigned modules | Disabled |
| 9 | `arch/arm64/configs/stock_defconfig` | ZRAM code uses `ac_time` field without `CONFIG_ZRAM_MEMORY_TRACKING` ifdef guard | Enabled `ZRAM_MEMORY_TRACKING`, `ZRAM_WRITEBACK`, `ZRAM_DEDUP` |

## FOD root cause

Previous attempt used LineageOS `android_kernel_oneplus_sm8150` (lineage-18.1) as kernel base. It booted, KSU worked, but FOD was broken: `GF_ERROR_PREPROCESS_FAILED errno=1011`, `OpFodDimControl: don't enable HBM due to no one registering fp`.

**Root cause:** LineageOS modified the SDE display driver in 3 files:

- `sde_plane.c` (+19/-19): Added `FOD_PRESSED_LAYER_ZORDER` intercept + `fod_property` + `zpos_max=INT_MAX` (stock has `zpos_max=255`)
- `sde_crtc.c` (+15/-40): Replaced detailed `fp_index`/`fppressed_index`/`aod_index` plane-alpha manipulation with `oneplus_dimlayer_hbm_enable` boolean shortcut
- `sde_drm.h` (+5): Added `#define FOD_PRESSED_LAYER_ZORDER 0x20000000u`

The Goodix driver was **byte-identical** between LineageOS and stock — the display pipeline change was the sole cause. Kirisakura keeps the stock OnePlus display path (no `fod_property`, no `dimlayer_hbm` boolean, original `fppressed_index` handling), so FOD works.

## Files

| File | Description |
|---|---|
| `manual-hooks.patch` | 7 KSU-Next manual hooks (git diff) |
| `kernel.config` | Final `.config` used for the build |
| `build.sh` | Full automated build script (Docker-based, Clang 14) |

Prebuilt boot image and manager APK are in [Releases](../../releases).

## Install

```bash
# Download from Releases
# - kirisakura-ksu-boot.img.xz    (flashable boot image)
# - KernelSU-Next-manager-v3.1.0.apk.xz  (manager app)

# Decompress
xz -d kirisakura-ksu-boot.img.xz
xz -d KernelSU-Next-manager-v3.1.0.apk.xz

# Flash kernel to active slot
adb reboot bootloader
fastboot flash boot_b kirisakura-ksu-boot.img    # active slot is _b on OOS 11
fastboot reboot

# Install manager
adb install KernelSU-Next-manager-v3.1.0.apk

# Reboot to activate KSU
adb reboot
```

## Verify

```bash
adb shell "su -c 'id'"
# uid=0(root) gid=0(root) groups=0(root) context=u:r:su:s0

adb shell "uname -r"
# 4.14.243-perf

adb shell "su -c '/data/adb/ksud --version'"
# ksud 3.1.0

adb shell "ip addr show wlan0"
# state UP, inet <your-ip>

adb shell "su -c 'getenforce'"
# Enforcing

adb shell "dumpsys fingerprint"
# {"service":"Fingerprint Manager","prints":[{"id":0,"count":1,...}]}
```

## Build from source

```bash
# Prerequisites: Docker (native on Linux, Colima on macOS)
# macOS: colima start --arch x86_64 --cpu 8 --memory 16 --disk 100

cd kirisakura-ksu-op7pro
bash build.sh

# After build, pack boot.img using magiskboot:
#   1. Obtain stock OOS11 boot.img (from OTA payload-dumper-go)
#   2. magiskboot unpack stock-boot.img
#   3. cp Image kernel
#   4. magiskboot repack stock-boot.img kirisakura-ksu-boot.img
```

## Device info

| | Value |
|---|---|
| Device | OnePlus 7 Pro (guacamole) |
| Model | GM1910 |
| SoC | Snapdragon 855 (SM8150) |
| Android | 11 (OxygenOS 11) |
| Build | GM1910_21_220617 |
| Stock kernel | 4.14.190-perf+ |
| This kernel | 4.14.243-perf (Kirisakura, +53 sublevels) |
| Boot slot | A/B, active `_b` |
| Boot header | v2 |
| Boot size | 96 MB (100663296 bytes) |

## KernelSU-Next version

Version: `30000 + git_commit_count + 119 = 30000 + 2905 + 119 = 33024`

Manager app must match: **KernelSU-Next v3.1.0 (33024)**. Manager v3.2.0+ will show "version too low".

---

## CRITICAL: A/B slot safety

### NEVER flash boot.img to the inactive slot and switch active slot

On A/B devices, each slot is a **complete OS copy** — `boot`, `system`, `vendor`, `product`, `dtbo` are all slot-specific. The inactive slot may have a **different OS version** (e.g. Android 10 from before the OOS 11 OTA update).

**The mistake that bricked the device (learned the hard way):**

1. Slot `_b` had working OOS 11 + KSU boot (active, bootable).
2. Stock boot.img was flashed to `boot_a` to "test fingerprint on stock kernel".
3. `fastboot --set-active=a` was run.
4. Device entered crashdump loop and required EDL/MSM recovery.

**Why it bricked:** Slot `_a` still had **old Android 10** system/vendor partitions. Flashing an OOS 11 boot.img to `boot_a` created a fatal mismatch: Android 11 kernel boot → Android 10 userspace = crashdump.

### Rules

| Rule | Explanation |
|---|---|
| **Do NOT** `fastboot --set-active=a` (or `b`) without confirming the target slot has matching system+vendor+boot | Active slot switch boots the **entire slot**, not just boot. If system/vendor on that slot are from a different OS version, the device will crashdump loop. |
| **Do NOT** flash only `boot_a` (or `boot_b`) on the inactive slot to "test" | The inactive slot may have incompatible system/vendor from a previous OS version. boot.img alone is useless without matching system/vendor. |
| **Do NOT** assume both slots have the same OS version after an OTA | OTA updates the inactive slot first, then switches. The old slot may retain the previous OS version indefinitely. |
| **Do NOT** test stock vs custom kernel by switching slots | Slot switching is not a "safe rollback". It boots the entire slot, including potentially stale system/vendor. |
| **DO** check active slot before flashing: `fastboot getvar current-slot` | Flash to the **active** slot only. |
| **DO** back up current boot before flashing | `adb shell su -c 'dd if=/dev/block/bootdevice/by-name/boot_$slot of=/sdcard/boot-backup.img'` |

### Safe way to test stock vs custom kernel

1. **Stay on the same active slot.**
2. Back up current boot:
   ```bash
   adb shell su -c 'dd if=/dev/block/bootdevice/by-name/boot_b of=/sdcard/boot-backup.img'
   ```
3. Flash custom boot:
   ```bash
   fastboot flash boot_b kirisakura-ksu-boot.img
   ```
4. To revert:
   ```bash
   fastboot flash boot_b boot-backup.img
   ```
5. **Never** `--set-active` to the other slot just to test a kernel.

### If you need to use the other slot

Copy **ALL** partitions from the working slot first:
```bash
# From TWRP or rooted shell, dd each partition from active slot to inactive slot:
dd if=/dev/block/bootdevice/by-name/system_b of=/dev/block/bootdevice/by-name/system_a
dd if=/dev/block/bootdevice/by-name/vendor_b of=/dev/block/bootdevice/by-name/vendor_a
dd if=/dev/block/bootdevice/by-name/boot_b   of=/dev/block/bootdevice/by-name/boot_a
dd if=/dev/block/bootdevice/by-name/dtbo_b   of=/dev/block/bootdevice/by-name/dtbo_a
# Only THEN is it safe to --set-active=a
```

### If already bricked (crashdump / EDL 9008 loop)

- Recovery requires **EDL 9008** mode + signed Qualcomm firehose loader (`prog_firehose_ddr.elf`).
- Firehose loader can be extracted from OnePlus MSM package `.ops` file using [oppo_decrypt](https://github.com/bkerler/oppo_decrypt): `python3 opscrypto.py decrypt <file>.ops`
- `edl.py setactiveslot b` **should** work but may hang on Sahara handshake due to stale device state.
- **Last resort:** full flash via `MsmDownloadTool V4.0.exe` from the MSM package. This reflashes **everything** (system, vendor, boot, userdata) and may **downgrade** the OS to the package version. Use only if slot switching via EDL fails.

---

## Credits

- [KernelSU-Next](https://github.com/rifsxd/KernelSU-Next) (rifsxd) — root solution
- [Kirisakura](https://github.com/freak07/Kirisakura_OP7Pro_A11) (freak07) — kernel base, OOS-based with linux-stable + EAS backports
- [OnePlusOSS](https://github.com/OnePlusOSS/android_kernel_oneplus_sm8150) — original kernel source
