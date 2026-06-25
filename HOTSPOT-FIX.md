# WiFi Hotspot / Tethering Fix

This document describes the diagnosis and fix for WiFi hotspot/tethering on the Kirisakura 4.14.243 kernel with OnePlus 7 Pro (OOS 11).

## Symptom

WiFi hotspot starts (AP appears on other devices, `hostapd` runs), then **immediately dies** within ~1 second. The hotspot toggle in Settings flips back to off. No error is shown to the user.

## Root causes

Two independent problems combined to break tethering:

### 1. IPv6 NAT support missing from kernel

**Config:** `# CONFIG_NF_NAT_IPV6 is not set` — the `ip6tables -t nat` table did not exist in the kernel.

**Effect on Android 11:**
- `netd` (Network Daemon) starts `ip6tables-restore` as a persistent child process at boot
- `ip6tables-restore` tries to initialize the nat table → **table does not exist** → process crashes immediately
- `netd`'s `IptablesRestoreController` keeps a persistent pipe to `ip6tables-restore` — once the process dies, the pipe is broken
- All subsequent `ip6tables` operations through the pipe return `EREMOTEIO (code 121)` — "Remote I/O error"
- This also corrupts the `iptables-restore` (IPv4) pipe because netd's restore controller manages both

**Evidence from device:**
```
$ ip6tables -t nat -L
ip6tables v1.8.4 (legacy): can't initialize ip6tables table `nat': Table does not exist (do you need to insmod?)
```

### 2. IptablesRestoreController tetherctrl chain bug in Android 11 netd

**The bug:** Android 11's `IptablesRestoreController` sends commands through the `iptables-restore` pipe using a hybrid format:
```
*filter
-nvx -L tetherctrl_counters
COMMIT
```

This mixes `iptables-restore` table syntax (`*filter`, `COMMIT`) with `iptables` command syntax (`-nvx -L tetherctrl_counters`). The `iptables-restore` binary does not understand `-nvx -L` — it interprets it as a rule specification, which is invalid.

**When it fails:** If the `tetherctrl_counters` chain does not exist when this command is sent, `iptables-restore` fails with `line 2 failed` and **exits with code 1** (status=256). The process dies. Netd does not restart it.

**Evidence from logcat:**
```
W IptablesRestoreController: iptables-restore process 11021 terminated status=256
E IptablesRestoreController: ------- COMMAND -------
E IptablesRestoreController: *filter
E IptablesRestoreController: -nvx -L tetherctrl_counters
E IptablesRestoreController: COMMIT
E IptablesRestoreController: -------  ERROR -------
E IptablesRestoreController: iptables-restore: line 2 failed
```

**Cascade effect:** Once `iptables-restore` dies, the tethering sequence fails:
```
[wlan0] ERROR Exception enabling NAT: android.os.ServiceSpecificException: Remote I/O error (code 121)
[wlan0] ERROR Exception in ipfwdRemoveInterfaceForward: No such file or directory (code 2)
OBSERVED iface=wlan0 state=1 error=8
Canceling WiFi tethering request
```

The same happens for `ip6tables-restore` — netd sends the same `-nvx -L tetherctrl_counters` command through the IPv6 pipe.

## Fix

### Part 1: Enable IPv6 NAT as kernel modules

Added to `kirisakura_defconfig` / `.config`:
```
CONFIG_NF_NAT_IPV6=m
CONFIG_NF_NAT_MASQUERADE_IPV6=m
CONFIG_IP6_NF_NAT=m
CONFIG_IP6_NF_TARGET_MASQUERADE=m
```

Built as **modules** (`=m`), not built-in (`=y`).

**Why not `=y` (built-in)?**

`CONFIG_NF_NAT_IPV6=y` causes kernel crashdump on Qualcomm SDM855 (SM8150) arm64 4.14.243. Two separate boot attempts both resulted in crashdump mode requiring fastboot recovery.

The crash occurs during `module_init` → `nf_nat_l3proto_ipv6_init()` → `nf_nat_l3proto_register()` or `ip6table_nat_init()` → `register_pernet_subsys()`. The exact root cause is unknown — it may be a conflict between netfilter hook registration and Qualcomm's custom network stack during early kernel init.

Building as modules (`=m`) avoids the issue: the init code runs later via `insmod` after the system is fully booted, when the network stack is stable.

### Part 2: KSU module for boot-time setup

A KernelSU module (`ipv6nat`) runs `post-fs-data.sh` at boot, **before netd starts**:

```bash
#!/system/bin/sh
MODDIR="/data/adb/modules/ipv6nat"

# 1. Load IPv6 NAT modules (dependency order)
insmod "$MODDIR/modules/nf_nat_ipv6.ko"
insmod "$MODDIR/modules/nf_nat_masquerade_ipv6.ko"
insmod "$MODDIR/modules/ip6table_nat.ko"
insmod "$MODDIR/modules/ip6t_MASQUERADE.ko"

# 2. Pre-create tetherctrl chains in BOTH iptables and ip6tables
for BIN in iptables ip6tables; do
    $BIN -N tetherctrl_counters 2>/dev/null
    $BIN -N tetherctrl_FORWARD 2>/dev/null
    $BIN -t nat -N tetherctrl_nat_POSTROUTING 2>/dev/null
    $BIN -C FORWARD -j tetherctrl_FORWARD 2>/dev/null || $BIN -A FORWARD -j tetherctrl_FORWARD
    $BIN -t nat -C POSTROUTING -j tetherctrl_nat_POSTROUTING 2>/dev/null || $BIN -t nat -A POSTROUTING -j tetherctrl_nat_POSTROUTING
done
```

**Step 1** ensures the `ip6tables -t nat` table exists before netd tries to start `ip6tables-restore`.

**Step 2** ensures the `tetherctrl_counters` chain exists in both IPv4 and IPv6 iptables before netd sends the `-nvx -L tetherctrl_counters` command through the restore pipes. With the chain pre-existing, `iptables-restore` succeeds (returns the chain contents) instead of crashing.

## Verification

After fix, hotspot starts and stays up:

```
$ dumpsys tethering | grep -E "TETHERED|error="
OBSERVED iface=wlan0 state=2 error=0
OBSERVED LinkProperties update iface=wlan0 state=TETHERED lp={...192.168.15.40/24...}

$ cat /proc/sys/net/ipv4/ip_forward
1

$ iptables -t nat -L tetherctrl_nat_POSTROUTING
Chain tetherctrl_nat_POSTROUTING (1 references)
MASQUERADE  all  --  anywhere  anywhere

$ logcat | grep hostapd
hostapd: wlan0: AP-STA-CONNECTED fe:dd:f1:e0:44:be
hostapd: wlan0: STA fe:dd:f1:e0:44:be WPA: pairwise key handshake completed
```

## Module structure

```
ipv6nat-boot-module.zip
├── module.prop
├── post-fs-data.sh          # loads modules + creates chains at boot
└── modules/
    ├── nf_nat_ipv6.ko        # 704 KB
    ├── nf_nat_masquerade_ipv6.ko  # 369 KB
    ├── ip6table_nat.ko       # 351 KB
    └── ip6t_MASQUERADE.ko    # 340 KB
```

## Why not fix this entirely in the kernel?

| Component | In kernel? | Why |
|---|---|---|
| IPv6 NAT code | Yes | `CONFIG_NF_NAT_IPV6=m` — kernel provides the code |
| Module loading | No | `insmod` is a userspace operation |
| `tetherctrl_counters` chain | No | User-defined chains are created by userspace (`iptables -N`) |
| `iptables-restore` pipe management | No | Netd (userspace daemon) manages the pipe |

The kernel provides the netfilter framework, but chain creation and module loading are userspace operations. The KSU module bridges this gap at boot time.

## Future improvement

If the `CONFIG_NF_NAT_IPV6=y` crashdump root cause is found and fixed, the modules could be built-in and the `insmod` step removed. The tetherctrl chain pre-creation would still be needed (it's a netd bug, not a kernel issue).
