# Kirisakura-KSU-Next — OnePlus 7 Pro (guacamole)

Custom kernel **Kirisakura 4.14.243** with **KernelSU-Next v3.1.0-legacy** (version 33024), **161 security patches** from linux-4.14.244–4.14.336, **built-in VPNHide**, and **fully kernel-level WiFi hotspot fix** for OnePlus 7 Pro on stock OxygenOS 11 (`GM1910_21_220617`, Android 11).

**Working:** Root (KSU Next) · FOD fingerprint · WiFi · Bluetooth · SELinux Enforcing · WiFi Hotspot/Tethering (no module needed) · VPN interface hiding (kernel + Java) · Play Integrity (BASIC + DEVICE) · Developer Settings (OemFix) · Boot props persistence

See [LSPOSED-AND-INTEGRITY.md](LSPOSED-AND-INTEGRITY.md) for the LSPosed Java hooks setup, Play Integrity bypass, OemFix Developer Settings crash fix, and boot props persistence guide.

See [RVT-REPLACE-ISSUE.md](RVT-REPLACE-ISSUE.md) for the YouTube overlay crash diagnosis — why systemless APK replacement via overlayfs breaks `ModuleInfoProvider` in `system_server`.

See [modules/README.md](modules/README.md) for KSU module installation guides (boot-props, oemfix, meta-kirisakura, vpnhide-kmod).

---

## What's new in v2.2

### WiFi Hotspot / Tethering — fully kernel-level, no KSU module

v2.1 required a KSU module (`ipv6nat`) with `post-fs-data.sh` to load `.ko` modules and create iptables chains at boot. **v2.2 eliminates the module entirely** — everything is now in the kernel:

| What | v2.1 | v2.2 |
|---|---|---|
| IPv6 NAT | Loadable modules (`=m`) + `insmod` via KSU | **Built-in (`=y`)** — no `insmod` |
| tetherctrl chains | Created by `post-fs-data.sh` (`iptables -N`) | **Pre-created in kernel initial table** — exist from boot |
| KSU module required | Yes (`ipv6nat`) | **No** |
| `.ko` files needed | 4 files (~1.7 MB) | **0** |
| `lsmod` after boot | 4 modules | **Empty** |

**Three root causes fixed at kernel level:**

1. **IPv6 NAT Makefile link order** (`net/ipv6/netfilter/Makefile`) — `ip6table_nat.o` was linked before its dependencies (`nf_nat_ipv6.o`, `nf_nat_masquerade_ipv6.o`). Reordered to match IPv4's link order. `CONFIG_NF_NAT_IPV6=y` now works without crashdump.

2. **tetherctrl chains in initial table** (3 source files) — user-defined chains are `ip6t_error`/`ipt_error` entries with `errorname` set to the chain name. By embedding them in the kernel's initial `replace` structure, chains exist from the moment the table is registered — before any userspace process runs. Jump entries use byte-offset verdicts (positive integers) to point at the chain head.

3. **IPv4 `tetherctrl_counters`** (`net/ipv4/netfilter/iptable_filter.c`) — the critical missing piece. Android 11 netd's `TetherController::setForwardRules()` sends `iptables-restore` commands with `-g tetherctrl_counters` (goto). Without the chain in the IPv4 filter table, `iptables-restore` fails with `goto 'tetherctrl_counters' is not a chain` and the entire tethering sequence aborts.

See [HOTSPOT-FIX.md](HOTSPOT-FIX.md) for the full diagnosis and `tetherctrl-builtin.patch` for the complete diff.

### CRITICAL: Boot image must be uncompressed (`CONFIG_BUILD_ARM64_UNCOMPRESSED_KERNEL=y`)

The OnePlus 7 Pro boot partition expects a **raw uncompressed `Image`**, not a GZIP-compressed `Image.gz`. Without `CONFIG_BUILD_ARM64_UNCOMPRESSED_KERNEL=y`:

- The kernel builds as `arch/arm64/boot/Image.gz` (GZIP-compressed)
- `magiskboot repack` packs it into the boot image
- The bootloader cannot decompress it → **bootloop** (device vibrates, shows OnePlus logo, reboots)
- No error message, no crashdump — just an infinite reboot loop

**Always verify** `CONFIG_BUILD_ARM64_UNCOMPRESSED_KERNEL=y` is set in your defconfig before building. The boot image should contain a raw `Image` (~55 MB for this kernel), not `Image.gz` (~20 MB).

```
# Correct (v2.2):
KERNEL_FMT      [raw]
KERNEL_SZ       [54974480]    # ~55 MB — uncompressed

# Wrong (bootloop):
KERNEL_FMT      [gzip]
KERNEL_SZ       [19478892]    # ~19 MB — compressed, will bootloop
```

---

## What's new in v2.1 (superseded by v2.2)

> **v2.1 used loadable modules (`=m`) and a KSU module for hotspot. v2.2 replaces this with a fully kernel-level solution — see above.**

### Built-in VPNHide (CONFIG_VPNHIDE=y)

VPN interface hiding compiled directly into the kernel — no kprobes, no loadable modules, no LSPosed required for native-level hiding. 11 direct hooks in netfilter/ioctl/netlink filter VPN interfaces (`tun0`, `wg0`, `ppp0`, etc.) from target apps at the kernel level.

**What's hidden from target apps:**
- `ioctl(SIOCGIFFLAGS)` → returns `ENODEV` for VPN interfaces
- `ioctl(SIOCGIFCONF)` → VPN entries removed from interface list
- `getifaddrs()` → VPN interfaces absent
- `NetworkInterface.getNetworkInterfaces()` → VPN absent (JNI calls ioctl)
- netlink `RTM_GETLINK` / `RTM_GETROUTE` → VPN interfaces/routes skipped
- `/proc/net/route` → VPN routes removed
- `/proc/net/ipv6_route` → VPN IPv6 routes removed
- `ip addr` / `ip link` / `ip route` → VPN absent (netlink filtered)

**What's NOT hidden (requires LSPosed/Zygisk):**
- `ConnectivityManager.hasTransport(TRANSPORT_VPN)` — Java API, not kernel-level
- `ConnectivityManager.getLinkProperties().getInterfaceName()` — Java API
- `getActiveNetworkInfo().getType() == TYPE_VPN` — Java API

Install the [VPN Hide app](https://github.com/okhsunrog/vpnhide) for GUI management of target apps and diagnostics.

### WiFi Hotspot / Tethering fix (v2.1 approach — superseded by v2.2)

> **This section describes the v2.1 approach. v2.2 fixes everything in the kernel — see [What's new in v2.2](#whats-new-in-v22).**

The stock Kirisakura kernel config had `CONFIG_NF_NAT_IPV6=n` — IPv6 NAT support was completely absent. This broke WiFi hotspot/tethering on Android 11:

1. **`ip6tables -t nat` table did not exist** — `ip6tables-restore` process crashed at netd startup trying to initialize the nat table
2. **`iptables-restore` pipe corrupted** — once `ip6tables-restore` died, netd's `IptablesRestoreController` lost its persistent pipe connection. All subsequent iptables operations (including IPv4 NAT) returned `EREMOTEIO (code 121)`
3. **Hotspot started then immediately died** — hostapd created the AP, Android set `state=TETHERED`, but NAT setup failed → `error=8` → tethering cancelled

**Fix (two parts):**

| Part | Solution | Why |
|---|---|---|
| IPv6 NAT kernel support | `CONFIG_NF_NAT_IPV6=m`, `CONFIG_NF_NAT_MASQUERADE_IPV6=m`, `CONFIG_IP6_NF_NAT=m`, `CONFIG_IP6_NF_TARGET_MASQUERADE=m` (loadable modules) | Built-in (`=y`) crashes the kernel on Qualcomm arm64 4.14 during `nf_nat_l3proto_ipv6_init()`. Modules load fine at boot via KSU. |
| tetherctrl chain pre-creation | KSU module `post-fs-data.sh` creates `tetherctrl_counters`, `tetherctrl_FORWARD`, `tetherctrl_nat_POSTROUTING` chains in both `iptables` and `ip6tables` before netd starts | Android 11 netd sends `-nvx -L tetherctrl_counters` via `iptables-restore` pipe. If the chain doesn't exist, `iptables-restore` exits with error and dies. Netd doesn't restart it → all tethering NAT setup fails. |

**Why built-in IPv6 NAT "crashed" in v2.1 (now fixed in v2.2):**

The v2.1 crash was **not** a code bug — it was a **Makefile link order** problem. In `net/ipv6/netfilter/Makefile`, `ip6table_nat.o` was linked before its dependencies (`nf_nat_ipv6.o`, `nf_nat_masquerade_ipv6.o`). Reordering to match IPv4's link order fixed it. See [HOTSPOT-FIX.md](HOTSPOT-FIX.md) for details.

See [HOTSPOT-FIX.md](HOTSPOT-FIX.md) for the full diagnosis process.

---

## What's new in v2.0

**161 security patches** cherry-picked from linux-4.14.y stable (v4.14.244 → v4.14.336, EOL January 2024). The stock Kirisakura kernel stopped at 4.14.243 — this release backports 93 subsequent stable releases covering:

- **11 CVEs** explicitly tagged in commit messages (CVE-2017-6074, CVE-2018-1000204, CVE-2020-16119, CVE-2021-20317, CVE-2021-3573, CVE-2022-0435, CVE-2022-2586, CVE-2022-2588, CVE-2023-31436, CVE-2023-3772, CVE-2023-1989)
- **~150 additional bug fixes** for use-after-free, out-of-bounds, race conditions, null pointer dereferences, memory leaks, and integer overflows across net, mm, kernel, security, fs, block, crypto, and drivers
- **Binder security patch** (manually resolved with OnePlus OP_FREEZER code + 4.14 SELinux API)
- 22 patches skipped due to code conflicts with Qualcomm/OnePlus custom code

See [SECURITY-PATCHES.md](SECURITY-PATCHES.md) for the full list.

## Why this kernel

The stock OnePlus 7 Pro kernel (4.14.190) works fine, but there was no KSU-Next integration that preserved FOD. LineageOS-derived kernels break the fingerprint display pipeline (see [Root cause](#fod-root-cause) below). This kernel uses [Kirisakura](https://github.com/freak07/Kirisakura_OP7Pro_A11) — built directly from OnePlus OSS sources for Android 11 — which keeps the stock FOD display path intact while adding 53 linux-stable sublevels, EAS scheduler backports, and other improvements.

## What's in this kernel

| Feature | Value |
|---|---|
| Kernel base | Kirisakura 4.14.243 (`freak07/Kirisakura_OP7Pro_A11`, branch `master_stock_caf_linux-upstream_vdso32_sched_final_2`) |
| Security patches | 161 commits from linux-4.14.244–4.14.336 (v2.0) |
| Defconfig | `stock_defconfig` (pure OnePlus stock, no CFI/LTO/SCS) |
| KernelSU-Next | v3.1.0-legacy, version 33024, manual hooks |
| VPNHide | Built-in (`CONFIG_VPNHIDE=y`) — 11 kernel hooks, no kprobes |
| IPv6 NAT | **Built-in (`CONFIG_NF_NAT_IPV6=y`)** — required for hotspot, no modules |
| FOD | Stock OOS path preserved — no `fod_property`, no `dimlayer_hbm` boolean, original `fppressed_index` plane-alpha handling |
| Wi-Fi (qcacld-3.0) | Built-in (`CONFIG_QCA_CLD_WLAN=y`) — no external module needed |
| WiFi Hotspot | **Working without any KSU module** — tetherctrl chains pre-created in kernel initial table |
| Boot image format | **Uncompressed** (`CONFIG_BUILD_ARM64_UNCOMPRESSED_KERNEL=y`) — raw `Image`, not GZIP |
| MODULE_SIG_FORCE | Disabled — allows loading unsigned modules |
| SELinux | Enforcing (stock) — `selinux_state` moved from `__rticdata` to regular `.bss` |
| KALLSYMS | Absolute mode (`KALLSYMS_BASE_RELATIVE` disabled — kernel image too large for relative mode with security patches + WiFi built-in) |
| Boot header | v2 (A/B, standard AOSP) |
| Toolchain | Clang 14, LLD 14, GNU cross GCC 11 |

## Manual hooks (7 KSU hooks + 11 VPNHide hooks)

### KSU-Next manual hooks (7 hooks in 7 files)

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

### VPNHide built-in hooks (11 hooks in 11 files)

Direct `#ifdef CONFIG_VPNHIDE` hooks in kernel source — zero overhead when disabled, no kprobes needed:

| # | File | Function | What it filters |
|---|---|---|---|
| 1 | `net/core/dev_ioctl.c` | `dev_ioctl()` | SIOCGIFFLAGS → returns `-ENODEV` for VPN ifr_name |
| 2 | `net/socket.c` | `sock_ioctl()` | SIOCGIFCONF — VPN entries compacted out of userspace ifreq array |
| 3 | `net/core/rtnetlink.c` | `rtnl_fill_ifinfo()` | RTM_NEWLINK — skip VPN netdev in netlink responses |
| 4 | `net/ipv6/addrconf.c` | `inet6_fill_ifaddr()` | IPv6 addr on VPN dev — skip in netlink RTM_GETADDR |
| 5 | `net/ipv4/devinet.c` | `inet_fill_ifaddr()` | IPv4 addr on VPN dev — skip in netlink RTM_GETADDR |
| 6 | `net/ipv4/fib_trie.c` | `fib_route_seq_show()` | `/proc/net/route` — skip VPN fib routes |
| 7 | `net/ipv6/ip6_fib.c` | `ipv6_route_seq_show()` | `/proc/net/ipv6_route` — skip VPN IPv6 routes |
| 8 | `net/ipv4/fib_semantics.c` | `fib_dump_info()` | RTM_GETROUTE IPv4 — skip VPN nexthop |
| 9 | `net/ipv6/route.c` | `rt6_fill_node()` | RTM_GETROUTE IPv6 — skip VPN dst.dev |
| 10 | `net/core/fib_rules.c` | `fib_nl_fill_rule()` | Policy routing rules — skip VPN iifname/oifname + UID-targeted rules |
| 11 | `net/ipv4/route.c` | `rt_fill_info()` | `ip route get` — skip VPN dst.dev (bonus: static func, not hookable by kretprobe) |

**VPN interface detection** — matches by name prefix: `tun*`, `tap*`, `wg*`, `ppp*`, `ipsec*`, `xfrm*`, `utun*`, `l2tp*`, `gre*`, `*vpn*`, `if[0-9]+`.

**Target management:**
- Write UIDs to `/proc/vpnhide_targets` (one per line, root only)
- Toggle debug logging via `/proc/vpnhide_debug` (`0`/`1`)
- KSU module `vpnhide_kmod` auto-resolves package names → UIDs at boot from `targets.txt`

## Build fixes applied

| # | File | Problem | Fix |
|---|---|---|---|
| 1 | `scripts/gcc-wrapper.py` | Python 2 syntax on Python 3 system | Rewritten for Python 3 |
| 2 | 78 Makefile/Kbuild files | `-Werror` triggers on GCC 11 / Clang 14 with 2019-era Qualcomm code | Relaxed `-Werror` → `-Wno-error` globally |
| 3 | `security/selinux/hooks.c` | `selinux_state __rticdata` relocation overflow | Removed `__rticdata` attribute |
| 4 | `drivers/platform/msm/ipa/ipa_v3/ipa_hw_stats.c` | `copy_from_user` without size guard | Added `min_t(size_t, count, sizeof(dbg_buff))` guard |
| 5 | `techpack/audio/soc/` | Broken symlinks | Replaced with real file copies |
| 6 | `drivers/oneplus/oneplus_healthinfo/oneplus_healthinfo.c` | Missing `task_load_info_timer` declaration | Added declaration |
| 7 | `drivers/soc/qcom/event_timer.c` | CVE-2021-20317 changed `struct timerqueue_head` members | Updated init from `.head = RB_ROOT` to `.rb_root = RB_ROOT_CACHED` |
| 8 | `init/Kconfig` | `KALLSYMS_BASE_RELATIVE` overflows with larger kernel image | Disabled (default `n`) |
| 9 | `arch/arm64/configs/stock_defconfig` | WiFi driver not built | Enabled `CONFIG_QCA_CLD_WLAN=y` (built-in) |
| 10 | `arch/arm64/configs/stock_defconfig` | `CONFIG_MODULE_SIG_FORCE=y` blocks unsigned modules | Disabled |
| 11 | `arch/arm64/configs/stock_defconfig` | ZRAM code uses `ac_time` without ifdef guard | Enabled `ZRAM_MEMORY_TRACKING`, `ZRAM_WRITEBACK`, `ZRAM_DEDUP` |
| 12 | `drivers/vpnhide/vpnhide.c` | `tolower` undefined in kernel context | Added `#include <linux/ctype.h>` |

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
| `tetherctrl-builtin.patch` | 4-file diff: built-in IPv6 NAT + tetherctrl chains in kernel initial tables |
| `kernel.config` | Final `.config` used for the build (includes `CONFIG_VPNHIDE=y`, IPv6 NAT `=y`, `CONFIG_BUILD_ARM64_UNCOMPRESSED_KERNEL=y`) |
| `build.sh` | Full automated build script (Docker-based, Clang 14) |
| `security-patches-shas.txt` | 161 SHA-1 hashes of cherry-picked commits |
| `SECURITY-PATCHES.md` | Full changelog of security patches with CVEs and subsystems |
| `HOTSPOT-FIX.md` | WiFi hotspot/tethering fix — full diagnosis and solution (v2.2 kernel-level) |
| `LSPOSED-AND-INTEGRITY.md` | LSPosed Java hooks for VPNHide + Play Integrity bypass (TrickyStore + IntegrityBox) |
| `CHANGELOG.md` | Version history |

Prebuilt boot image and manager APK are in [Releases](../../releases).

## Install

### Prerequisites

- OnePlus 7 Pro on OOS 11 (`GM1910_21_220617`)
- Active slot `_b` (check: `fastboot getvar current-slot`)
- Unlocked bootloader
- ADB + fastboot on PC

### Flash kernel

```bash
# Download from Releases:
# - kirisakura-v2.2-boot.img.xz          (v2.2 boot image — all features built-in)
# - KernelSU-Next-manager-v3.1.0.apk.xz   (manager app)
# - vpnhide-builtin-module.zip            (KSU module for VPNHide target management)

# Decompress boot image
xz -d kirisakura-v2.2-boot.img.xz

# Flash kernel to active slot
adb reboot bootloader
fastboot flash boot_b kirisakura-v2.2-boot.img
fastboot reboot

# Install manager
adb install KernelSU-Next-manager-v3.1.0.apk

# Install VPNHide management module (optional — only for VPNHide target management)
adb push vpnhide-builtin-module.zip /data/local/tmp/
adb shell "su -c 'ksud module install /data/local/tmp/vpnhide-builtin-module.zip'"
adb reboot
```

> **Note:** As of v2.2, **no KSU module is needed for hotspot/tethering**. IPv6 NAT and all tetherctrl chains are built directly into the kernel. The only optional KSU module is `vpnhide-builtin-module.zip` for managing VPNHide target app UIDs.

### Configure VPNHide

After reboot, install the [VPN Hide app](https://github.com/okhsunrog/vpnhide) for GUI management, or use shell:

```bash
# Find target app UID
adb shell "pm list packages -U | grep <package_name>"

# Write UID to kernel
adb shell "su -c 'echo <uid> > /proc/vpnhide_targets'"

# Or add package name to targets file (persists across reboots)
adb shell "su -c 'echo <package_name> >> /data/adb/vpnhide_kmod/targets.txt'"

# Enable debug logging
adb shell "su -c 'echo 1 > /proc/vpnhide_debug'"

# Check status
adb shell "su -c 'cat /proc/vpnhide_targets'"
adb shell "su -c 'cat /data/adb/vpnhide_kmod/load_status'"
```

## Verify

```bash
# Root
adb shell "su -c 'id'"
# uid=0(root) gid=0(root) groups=0(root) context=u:r:su:s0

# Kernel
adb shell "uname -r"
# 4.14.243-perf

# KSU
adb shell "su -c '/data/adb/ksud --version'"
# ksud 3.1.0

# SELinux
adb shell "su -c 'getenforce'"
# Enforcing

# WiFi
adb shell "ip addr show wlan0"
# state UP, inet <your-ip>

# VPNHide
adb shell "su -c 'cat /proc/vpnhide_targets'"
# (lists target UIDs)

# IPv6 NAT (built-in, no modules)
adb shell "su -c 'lsmod'"
# (empty — everything is built-in)

adb shell "su -c 'ip6tables -t nat -L'"
# Chain POSTROUTING (policy ACCEPT)
# tetherctrl_nat_POSTROUTING  all  anywhere  anywhere

# Fingerprint
adb shell "dumpsys fingerprint"
# {"service":"Fingerprint Manager","prints":[{"id":0,"count":1,...}]}

# Hotspot (turn on, then check)
adb shell "su -c 'cat /proc/sys/net/ipv4/ip_forward'"
# 1 (when hotspot is on)
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
#   4. magiskboot repack stock-boot.img kirisakura-vpnhide-ipv6nat-boot.img
```

The build script automatically:
1. Clones Kirisakura kernel source
2. Clones linux-stable 4.14.y and cherry-picks 161 security patches
3. Integrates KernelSU-Next v3.1.0-legacy
4. Applies manual hooks + 12 build fixes
5. Builds with Clang 14 + LLD 14

**Note:** The build script builds the kernel only. VPNHide driver source and IPv6 NAT module packaging are done separately. See `HOTSPOT-FIX.md` for details.

## Device info

| | Value |
|---|---|
| Device | OnePlus 7 Pro (guacamole) |
| Model | GM1910 |
| SoC | Snapdragon 855 (SM8150) |
| Android | 11 (OxygenOS 11) |
| Build | GM1910_21_220617 |
| Stock kernel | 4.14.190-perf+ |
| This kernel | 4.14.243-perf (Kirisakura, +53 sublevels, +161 security patches, +VPNHide) |
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
   fastboot flash boot_b kirisakura-vpnhide-ipv6nat-boot.img
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
- [linux-stable](https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git) — security patches (4.14.244–4.14.336)
- [vpnhide](https://github.com/okhsunrog/vpnhide) (okhsunrog) — VPN interface hiding concept and original kmod implementation
