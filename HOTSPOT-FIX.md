# WiFi Hotspot / Tethering Fix

This document describes the diagnosis and fix for WiFi hotspot/tethering on the Kirisakura 4.14.243 kernel with OnePlus 7 Pro (OOS 11).

## Symptom

WiFi hotspot starts (AP appears on other devices, `hostapd` runs), then **immediately dies** within ~1 second. The hotspot toggle in Settings flips back to off. No error is shown to the user.

## Root causes

Three independent problems combined to break tethering:

### 1. IPv6 NAT support missing from kernel

**Config:** `# CONFIG_NF_NAT_IPV6 is not set` — the `ip6tables -t nat` table did not exist in the kernel.

**Effect on Android 11:**
- `netd` (Network Daemon) starts `ip6tables-restore` as a persistent child process at boot
- `ip6tables-restore` tries to initialize the nat table → **table does not exist** → process crashes immediately
- `netd`'s `IptablesRestoreController` keeps a persistent pipe to `ip6tables-restore` — once the process dies, the pipe is broken
- All subsequent `ip6tables` operations through the pipe return `EREMOTEIO (code 121)` — "Remote I/O error"
- This also corrupts the `iptables-restore` (IPv4) pipe because netd's restore controller manages both

### 2. IptablesRestoreController tetherctrl chain bug in Android 11 netd

**The bug:** Android 11's `IptablesRestoreController` sends commands through the `iptables-restore` pipe using a hybrid format:
```
*filter
-nvx -L tetherctrl_counters
COMMIT
```

This mixes `iptables-restore` table syntax (`*filter`, `COMMIT`) with `iptables` command syntax (`-nvx -L tetherctrl_counters`). The `iptables-restore` binary does not understand `-nvx -L` — it interprets it as a rule specification, which is invalid.

**When it fails:** If the `tetherctrl_counters` chain does not exist when this command is sent, `iptables-restore` fails with `line 2 failed` and **exits with code 1** (status=256). The process dies. Netd does not restart it.

**Cascade effect:** Once `iptables-restore` dies, the tethering sequence fails:
```
E/TetherController: Error setting forward rules
E/Tethering: [wlan0] ERROR Exception enabling NAT: No such device (code 19)
E/Tethering: [wlan0] ERROR Exception in ipfwdRemoveInterfaceForward: No such file or directory (code 2)
OBSERVED iface=wlan0 state=1 error=8
Canceling WiFi tethering request
```

### 3. IPv6 NAT built-in (`=y`) crash — Makefile link order

Initial attempt to set `CONFIG_NF_NAT_IPV6=y` (built-in) caused kernel crashdump. Investigation revealed this was **not** a code bug but a **Makefile link order** problem.

**Root cause:** In `net/ipv6/netfilter/Makefile`, `ip6table_nat.o` was linked **before** `nf_nat_ipv6.o` and `nf_nat_masquerade_ipv6.o`. The `ip6table_nat` init code calls functions from `nf_nat_ipv6` during `register_pernet_subsys()`, but those symbols weren't yet initialized at link time. This caused a crash during early kernel init.

**Fix:** Reordered `Makefile` to match the IPv4 link order — `nf_nat_ipv6.o` and `nf_nat_masquerade_ipv6.o` are now linked **before** `ip6table_nat.o`. This is the same order used by `net/ipv4/netfilter/Makefile` for IPv4 NAT, which works correctly.

## Fix — v2.2 (fully kernel-level)

All three problems are fixed entirely in the kernel. **No KSU module, no userspace script, no `insmod` required.**

### Part 1: IPv6 NAT built-in (`=y`) + Makefile link order fix

```
CONFIG_NF_NAT_IPV6=y
CONFIG_NF_NAT_MASQUERADE_IPV6=y
CONFIG_IP6_NF_NAT=y
CONFIG_IP6_NF_TARGET_MASQUERADE=y
```

**Makefile fix** (`net/ipv6/netfilter/Makefile`):
```makefile
# Before (broken): ip6table_nat.o linked BEFORE its dependencies
obj-$(CONFIG_IP6_NF_NAT) += ip6table_nat.o
obj-$(CONFIG_NF_NAT_IPV6) += nf_nat_ipv6.o
...

# After (fixed): dependencies linked FIRST, matching IPv4 order
obj-$(CONFIG_NF_NAT_IPV6) += nf_nat_ipv6.o
obj-$(CONFIG_NF_NAT_MASQUERADE_IPV6) += nf_nat_masquerade_ipv6.o
obj-$(CONFIG_IP6_NF_NAT) += ip6table_nat.o
...
```

### Part 2: tetherctrl chains pre-created in kernel initial table structure

The key insight: user-defined chains in iptables/ip6tables are stored as `ip6t_error` entries with the `errorname` field set to the chain name. By embedding these entries directly in the kernel's initial table `replace` structure, the chains exist from the moment the table is registered — before any userspace process runs.

**Three files modified:**

#### `net/ipv6/netfilter/ip6table_nat.c`

Custom `ip6table_nat_table_init()` builds a `struct ip6t_replace` with:
- `POSTROUTING` hook entry → JUMP to `tetherctrl_nat_POSTROUTING` (positive verdict = byte offset)
- Separate `POSTROUTING` underflow entry → ACCEPT (negative verdict)
- `tetherctrl_nat_POSTROUTING` chain head (`ip6t_error` entry with errorname)
- `tetherctrl_nat_POSTROUTING` return → ACCEPT
- `ERROR` entry

#### `net/ipv6/netfilter/ip6table_filter.c`

Custom `ip6table_filter_table_init()` builds a `struct ip6t_replace` with:
- `INPUT` hook → ACCEPT
- `FORWARD` hook → JUMP to `tetherctrl_FORWARD` (positive verdict = byte offset)
- `FORWARD` underflow → ACCEPT (separate entry, required by `check_underflow()`)
- `OUTPUT` hook → ACCEPT
- `tetherctrl_FORWARD` chain head + return
- `tetherctrl_counters` chain head + return
- `ERROR` entry

#### `net/ipv4/netfilter/iptable_filter.c`

Custom `iptable_filter_table_init()` builds a `struct ipt_replace` with:
- `INPUT`, `FORWARD`, `OUTPUT` hooks → standard ACCEPT/DROP
- `tetherctrl_counters` chain head + return
- `ERROR` entry

This was the **critical missing piece** — Android 11 netd's `TetherController::setForwardRules()` sends `iptables-restore` commands that use `-g tetherctrl_counters` (goto). Without the chain pre-existing in the IPv4 filter table, `iptables-restore` fails with `goto 'tetherctrl_counters' is not a chain` and the entire tethering sequence aborts.

### Implementation details

**Byte-offset pointer arithmetic:** The `ip6t_error` struct is larger than `ip6t_standard` (it has an extra `errorname` field). Mixed-type arrays can't use array indexing, so entries are placed at computed byte offsets within a flat buffer. Jump verdicts are positive integers representing the byte offset of the target entry from the start of the entries data.

**`check_underflow()` requirement:** Kernel's `check_underflow()` validates that underflow entries (the fallback for a hook when all rules miss) have **negative** verdicts (ACCEPT/DROP/RETURN). Hook entries that JUMP to a user chain have **positive** verdicts (byte offset). Therefore, hooks that jump must have a **separate** underflow entry with a negative verdict.

**`IPT_STANDARD_INIT` / `IP6T_STANDARD_INIT` macro:** The macro already applies `-verdict - 1`, so callers must pass `NF_ACCEPT` (not `-NF_ACCEPT - 1`). Passing `-NF_ACCEPT - 1` causes double-negation → verdict = 1 (jump to byte offset 1) → garbage → table registration fails silently.

## Verification

After fix, hotspot starts and stays up — no KSU module, no userspace script:

```
$ dumpsys tethering | grep -E "TETHERED|error="
OBSERVED iface=wlan0 state=2 error=0
OBSERVED LinkProperties update iface=wlan0 state=TETHERED lp={...192.168.59.54/24...}

$ cat /proc/sys/net/ipv4/ip_forward
1

$ iptables -t nat -L tetherctrl_nat_POSTROUTING
Chain tetherctrl_nat_POSTROUTING (1 references)
MASQUERADE  all  --  anywhere  anywhere

$ ip6tables -t nat -L tetherctrl_nat_POSTROUTING
Chain tetherctrl_nat_POSTROUTING (1 references)

$ iptables -L tetherctrl_counters
Chain tetherctrl_counters (2 references)
RETURN  all  --  wlan0  rmnet_data2  anywhere  anywhere
RETURN  all  --  rmnet_data2  wlan0  anywhere  anywhere

$ ip6tables -L tetherctrl_counters
Chain tetherctrl_counters (1 references)
RETURN  all      wlan0  rmnet_data2  anywhere  anywhere
RETURN  all      rmnet_data2  wlan0   anywhere  anywhere

$ lsmod
Module                  Size  Used by
(empty — everything built-in)

$ logcat | grep hostapd
hostapd: wlan0: AP-STA-CONNECTED fe:dd:f1:e0:44:be
hostapd: wlan0: STA fe:dd:f1:e0:44:be WPA: pairwise key handshake completed
```

## Evolution

| Version | IPv6 NAT | tetherctrl chains | KSU module needed |
|---|---|---|---|
| v2.0 | Not supported | Not present | N/A (hotspot broken) |
| v2.1 | Loadable modules (`=m`) | Created by KSU `post-fs-data.sh` | Yes (`ipv6nat`) |
| **v2.2** | **Built-in (`=y`)** | **Pre-created in kernel initial table** | **No** |

## Patch file

See `tetherctrl-builtin.patch` for the complete diff of all 4 modified files:
- `net/ipv4/netfilter/iptable_filter.c` — IPv4 filter: pre-create `tetherctrl_counters`
- `net/ipv6/netfilter/ip6table_filter.c` — IPv6 filter: pre-create `tetherctrl_FORWARD` + `tetherctrl_counters`
- `net/ipv6/netfilter/ip6table_nat.c` — IPv6 nat: pre-create `tetherctrl_nat_POSTROUTING` + jump from POSTROUTING
- `net/ipv6/netfilter/Makefile` — link order fix (dependencies before consumers)
