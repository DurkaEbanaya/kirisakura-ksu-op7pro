# Changelog

## v2.2 (2026-06-26)

### Added
- **tetherctrl-builtin.patch** — complete diff of 4 kernel source files for the built-in hotspot fix
- **`CONFIG_BUILD_ARM64_UNCOMPRESSED_KERNEL=y`** documented as critical boot fix (was already in config but not documented)

### Changed — IPv6 NAT now built-in (`=y`), no modules needed
- `CONFIG_NF_NAT_IPV6=m` → `=y` (built-in)
- `CONFIG_NF_NAT_MASQUERADE_IPV6=m` → `=y` (built-in)
- `CONFIG_IP6_NF_NAT=m` → `=y` (built-in)
- `CONFIG_IP6_NF_TARGET_MASQUERADE=m` → `=y` (built-in)

### Fixed — three root causes, all resolved at kernel level

1. **IPv6 NAT built-in crash → Makefile link order** (`net/ipv6/netfilter/Makefile`)
   - `ip6table_nat.o` was linked BEFORE `nf_nat_ipv6.o`/`nf_nat_masquerade_ipv6.o`
   - Reordered to match IPv4's link order — dependencies first, consumers after
   - `CONFIG_NF_NAT_IPV6=y` now works without crashdump

2. **tetherctrl chains pre-created in kernel initial table** (3 files)
   - `net/ipv6/netfilter/ip6table_nat.c` — `tetherctrl_nat_POSTROUTING` chain + JUMP from POSTROUTING hook
   - `net/ipv6/netfilter/ip6table_filter.c` — `tetherctrl_FORWARD` + `tetherctrl_counters` chains + JUMP from FORWARD hook
   - `net/ipv4/netfilter/iptable_filter.c` — `tetherctrl_counters` chain (critical: IPv4 was the missing piece)
   - Chains exist from kernel boot, before any userspace process runs
   - No `post-fs-data.sh`, no `iptables -N`, no `insmod`

3. **`CONFIG_BUILD_ARM64_UNCOMPRESSED_KERNEL=y`** — boot image must be uncompressed
   - Without this, kernel builds as GZIP-compressed `Image.gz` and bootloops on OnePlus 7 Pro
   - The boot partition expects a raw `Image`, not `Image.gz`

### Removed
- **KSU module `ipv6nat`** — completely eliminated
  - v2.1 required a KSU module with `post-fs-data.sh` to load `.ko` modules and create iptables chains
  - v2.2 does everything in the kernel — zero modules, zero userspace scripts
  - `modules/ipv6nat/` directory removed from repo

### Known limitations
- VPNHide hides VPN at native/kernel level only — Java API level (`ConnectivityManager.hasTransport(VPN)`) requires LSPosed or Zygisk
- `tetherctrl-builtin.patch` uses byte-offset pointer arithmetic (not array indexing) because `ip6t_error` is larger than `ip6t_standard` — mixed types in a contiguous buffer require manual offset management

---

## v2.1 (2026-06-25)

### Added
- **Built-in VPNHide** (`CONFIG_VPNHIDE=y`) — VPN interface hiding compiled directly into kernel
  - 11 direct hooks in netfilter/ioctl/netlink source files (no kprobes)
  - Hides `tun0`, `wg0`, `ppp0`, and other VPN interfaces from target apps at native level
  - Target UIDs managed via `/proc/vpnhide_targets`
  - Debug logging via `/proc/vpnhide_debug`
  - KSU module `vpnhide_kmod` for boot-time UID resolution from package names
  - Compatible with [VPN Hide app](https://github.com/okhsunrog/vpnhide) for GUI management
- **IPv6 NAT support** as loadable modules (`CONFIG_NF_NAT_IPV6=m`, `CONFIG_IP6_NF_NAT=m`, `CONFIG_NF_NAT_MASQUERADE_IPV6=m`, `CONFIG_IP6_NF_TARGET_MASQUERADE=m`)
- **WiFi Hotspot/Tethering fix** — KSU module `ipv6nat` with `post-fs-data.sh`
  - Loads IPv6 NAT modules at boot before netd starts
  - Pre-creates `tetherctrl_counters` and related chains in both `iptables` and `ip6tables`
- **HOTSPOT-FIX.md** — full diagnosis and fix documentation

### Fixed
- WiFi hotspot starts then immediately dies (NAT setup fails with `EREMOTEIO`)
- `ip6tables-restore` crashes at boot because `nat` table doesn't exist
- `iptables-restore` dies when `tetherctrl_counters` chain doesn't exist (Android 11 netd bug)

### Changed
- `kernel.config`: added `CONFIG_VPNHIDE=y`, `CONFIG_NF_NAT_IPV6=m`, `CONFIG_NF_NAT_MASQUERADE_IPV6=m`, `CONFIG_IP6_NF_NAT=m`, `CONFIG_IP6_NF_TARGET_MASQUERADE=m`
- README updated with v2.1 features, VPNHide documentation, hotspot fix summary

### Known limitations (v2.1 — superseded by v2.2)
- ~~`CONFIG_NF_NAT_IPV6=y` (built-in) crashes kernel on Qualcomm SDM855 arm64 4.14 — must use modules (`=m`)~~ — **Fixed in v2.2: Makefile link order was the root cause**
- VPNHide hides VPN at native/kernel level only — Java API level (`ConnectivityManager.hasTransport(VPN)`) requires LSPosed or Zygisk
- ~~IPv6 NAT modules + tetherctrl chain pre-creation require KSU module — not purely kernel-level~~ — **Fixed in v2.2: fully kernel-level, no KSU module**

---

## v2.0 (2026-06-25)

### Added
- **161 security patches** from linux-4.14.244–4.14.336 (93 stable releases)
  - 11 CVEs: CVE-2017-6074, CVE-2018-1000204, CVE-2020-16119, CVE-2021-20317, CVE-2021-3573, CVE-2022-0435, CVE-2022-2586, CVE-2022-2588, CVE-2023-31436, CVE-2023-3772, CVE-2023-1989
  - ~150 additional bug fixes across net, mm, kernel, security, fs, block, crypto, drivers
  - Binder security patch (manual resolve with OnePlus OP_FREEZER + 4.14 SELinux API)
  - 22 patches skipped due to Qualcomm/OnePlus code conflicts
- **SECURITY-PATCHES.md** — full patch changelog with CVEs and subsystems
- **security-patches-shas.txt** — 161 SHA-1 hashes of cherry-picked commits
- **build.sh** — full automated Docker-based build script (Clang 14, LLD 14, GCC 11)

### Fixed
- `scripts/gcc-wrapper.py` — Python 2 → Python 3
- 78 Makefile/Kbuild files — `-Werror` → `-Wno-error` for GCC 11 / Clang 14 compatibility
- `security/selinux/hooks.c` — `selinux_state __rticdata` relocation overflow
- `drivers/platform/msm/ipa/ipa_v3/ipa_hw_stats.c` — `copy_from_user` size guard
- `techpack/audio/soc/` — broken symlinks → real file copies
- `drivers/oneplus/oneplus_healthinfo/oneplus_healthinfo.c` — missing declaration
- `drivers/soc/qcom/event_timer.c` — CVE-2021-20317 struct member change
- `init/Kconfig` — `KALLSYMS_BASE_RELATIVE` overflow with large kernel image
- `stock_defconfig` — WiFi driver built-in, `MODULE_SIG_FORCE` disabled, ZRAM fixes

---

## v1.0 (2026-06-24)

### Added
- Kirisakura 4.14.243 kernel base (`freak07/Kirisakura_OP7Pro_A11`)
- KernelSU-Next v3.1.0-legacy (version 33024) with 7 manual hooks
- FOD fingerprint working (stock OOS display path preserved)
- WiFi (qcacld-3.0) built-in
- SELinux Enforcing
- Boot image for OnePlus 7 Pro GM1910 OOS 11
- `manual-hooks.patch` — 7 KSU-Next hook diffs
