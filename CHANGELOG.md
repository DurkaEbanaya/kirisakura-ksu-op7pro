# Changelog

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

### Known limitations
- `CONFIG_NF_NAT_IPV6=y` (built-in) crashes kernel on Qualcomm SDM855 arm64 4.14 — must use modules (`=m`)
- VPNHide hides VPN at native/kernel level only — Java API level (`ConnectivityManager.hasTransport(VPN)`) requires LSPosed or Zygisk
- IPv6 NAT modules + tetherctrl chain pre-creation require KSU module — not purely kernel-level

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
