# KSU Modules

These KernelSU Next modules are optional companions for the kernel.

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

## vpn-tether — VPN Sharing + Concurrent WiFi AP

Shares VPN tunnel with tethered devices without dropping WiFi connection. Creates a concurrent AP interface (`wlan_ap0`) while WiFi stays connected as STA. One-button VPN grant per device via WebUI.

**Features:**
- Concurrent WiFi AP — WiFi stays connected while sharing
- Per-device VPN grant — route specific device's traffic through VPN tunnel
- Provider DNS — works in whitelist-restricted networks (no 8.8.8.8)
- USB/BT tether support — grant VPN for USB/Bluetooth tethered devices
- WebUI with Fluent Design — manage everything from KernelSU Next Manager

**Install:** Flash `vpn-tether-v1.0.zip` in KSU Next Manager

See [vpn-tether/README.md](vpn-tether/README.md) for details.

> **Note:** The `ipv6nat` module from v2.1 is **no longer needed** as of v2.2. IPv6 NAT and all tetherctrl chains are now built directly into the kernel — no userspace module required for hotspot/tethering.
