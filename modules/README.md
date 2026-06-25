# KSU Modules

These KernelSU Next modules are required alongside the kernel for full functionality.

## ipv6nat — IPv6 NAT Support + Hotspot Fix

Loads IPv6 NAT kernel modules and pre-creates tetherctrl iptables chains at boot.

**Required for:** WiFi Hotspot / Tethering

**What it does:**
1. Loads `nf_nat_ipv6.ko`, `nf_nat_masquerade_ipv6.ko`, `ip6table_nat.ko`, `ip6t_MASQUERADE.ko` before netd starts
2. Creates `tetherctrl_counters`, `tetherctrl_FORWARD`, `tetherctrl_nat_POSTROUTING` chains in both `iptables` and `ip6tables`

**Why:** See [HOTSPOT-FIX.md](../HOTSPOT-FIX.md) for full explanation.

**Install:**
```bash
adb push ipv6nat-boot-module.zip /data/local/tmp/
adb shell "su -c 'ksud module install /data/local/tmp/ipv6nat-boot-module.zip'"
adb reboot
```

Note: The `.ko` module files are not in this repo (excluded by .gitignore). They are built from the kernel source and packaged into the zip. Download the prebuilt zip from [Releases](../../releases).

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
