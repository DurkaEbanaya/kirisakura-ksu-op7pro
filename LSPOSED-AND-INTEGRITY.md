# LSPosed Java Hooks, Play Integrity Bypass, Ozon Fix & DNS Configuration

This document covers post-install configurations for the Kirisakura-KSU-Next kernel on OnePlus 7 Pro (OOS 11):

1. **Enabling LSPosed Java hooks for VPNHide** — completing the two-level VPN hiding architecture
2. **Bypassing Play Integrity** — passing BASIC and DEVICE integrity checks with unlocked bootloader
3. **Ozon "No Connection" fix** — TrustMeAlready LSPosed module breaking SSL in Ozon
4. **DNS / Private DNS configuration** — Tele2 DNS servers do not support DoT
5. **verifiedbootstate & resetprop_if_diff bug** — IntegrityBox prop spoofing bug on OnePlus 7 Pro

Both are userspace-only — no kernel changes required. The kernel already provides the foundation: built-in VPNHide (`CONFIG_VPNHIDE=y`) for native-level hiding, and KSU-Next for root.

---

## Part 1: LSPosed Java Hooks for VPNHide

### Why two levels are needed

The kernel-level VPNHide (`CONFIG_VPNHIDE=y`) hides VPN interfaces from 11 native syscall paths — `ioctl`, `getifaddrs`, netlink, `/proc/net/route`, etc. However, Java APIs bypass these syscalls entirely:

| Java API | What it checks | Kernel-level hidden? |
|---|---|---|
| `ConnectivityManager.hasTransport(TRANSPORT_VPN)` | NetworkCapabilities transport bit 4 | No — Java API in system_server |
| `ConnectivityManager.getNetworkCapabilities()` | VpnTransportInfo presence | No — Java API |
| `NetworkInfo.getType() == TYPE_VPN` | Network type enum | No — Java API |
| `LinkProperties.getInterfaceName()` | Active network interface name | No — Java API |

Apps like banking software and streaming services use these Java APIs to detect VPN. Without LSPosed hooks, they see the VPN even though the kernel hides it at native level.

### Architecture

```
┌─────────────────────────────────────────────────────────┐
│  Target app (e.g. Tinkoff)                              │
│                                                         │
│  Java API: ConnectivityManager.hasTransport(TRANSPORT_VPN)
│       │                                                 │
│       ▼                                                 │
│  system_server (PID ~1000)                              │
│       │                                                 │
│  ┌─── LSPosed hook ───────────────────────────────┐    │
│  │  HookEntry.java loaded into system_server:      │    │
│  │  • NetworkCapabilities.writeToParcel() → strip  │    │
│  │    TRANSPORT_VPN (bit 4)                        │    │
│  │  • NetworkInfo.writeToParcel() → set type=WiFi  │    │
│  │  • LinkProperties.writeToParcel() → strip VPN   │    │
│  │    interface name                               │    │
│  │  • Sets NET_CAPABILITY_NOT_VPN (bit 15)         │    │
│  └──────────────────────────────────────────────────┘   │
│       │                                                 │
│       ▼  Modified response                              │
│  App sees: no VPN transport, no VpnTransportInfo        │
│                                                         │
│  Native syscall: getifaddrs(), ioctl(SIOCGIFCONF)       │
│       │                                                 │
│       ▼                                                 │
│  ┌─── Kernel VPNHide (CONFIG_VPNHIDE=y) ──────────┐    │
│  │  11 hooks in netfilter/ioctl/netlink:           │    │
│  │  • tun0/wg0/ppp0 absent from interface lists    │    │
│  │  • /proc/net/route entries removed              │    │
│  │  • netlink RTM_GETLINK/RTM_GETROUTE filtered    │    │
│  └──────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────┘
```

### Prerequisites

| Component | Version | Purpose |
|---|---|---|
| ReZygisk | v1.0.0 (515) | Zygisk implementation (KSU-Next compatible) |
| zygisk_lsposed | v1.9.2 (7024) | LSPosed framework via Zygisk |
| VPN Hide app | v0.7.1+ | Xposed module (`xposedmodule=true`, `xposedminversion=93`) |
| vpnhide_kmod | v0.7.1-builtin | KSU module — resolves package names to UIDs at boot |

### The problem: LSPosed does not auto-register modules

LSPosed is a framework — it loads modules, but **does not automatically enable them**. After installing the VPN Hide app, it must be manually registered in LSPosed:

1. Open LSPosed Manager
2. Find "VPN Hide" in the module list
3. Enable the toggle
4. Set scope to "System Framework" (`android` / `system`)
5. Reboot

**If LSPosed Manager UI doesn't show the module** (common on KSU-Next + ReZygisk setups), you can register it manually via the LSPosed database.

### Manual registration via LSPosed database

> Use this method only if LSPosed Manager UI doesn't list VPN Hide as an available module.

**LSPosed DB path:** `/data/adb/lspd/config/modules_config.db` (SQLite, with `-wal` and `-shm` sidecar files)

**DB schema:**

```sql
-- modules table: registered Xposed modules
CREATE TABLE modules (
    mid INTEGER PRIMARY KEY AUTOINCREMENT,
    module_pkg_name TEXT,
    apk_path TEXT,
    enabled INTEGER  -- 1 = enabled, 0 = disabled
);

-- scope table: which app processes the module hooks into
CREATE TABLE scope (
    mid INTEGER,
    app_pkg_name TEXT,  -- "system" = system_server, or a package name
    user_id INTEGER     -- 0 = main user
);
```

**Step 1: Find VPN Hide APK path on device**

```bash
adb shell "su -c 'pm path dev.okhsunrog.vpnhide'"
# Output: package:/data/app/~~<random>/dev.okhsunrog.vpnhide-<random>/base.apk
```

**Step 2: Pull the LSPosed database (with WAL + SHM)**

```bash
adb shell "su -c 'cp /data/adb/lspd/config/modules_config.db /data/local/tmp/lspd.db'"
adb shell "su -c 'cp /data/adb/lspd/config/modules_config.db-wal /data/local/tmp/lspd.db-wal'"
adb shell "su -c 'cp /data/adb/lspd/config/modules_config.db-shm /data/local/tmp/lspd.db-shm'"
adb shell "su -c 'chmod 666 /data/local/tmp/lspd.db*'"
adb pull /data/local/tmp/lspd.db /tmp/
adb pull /data/local/tmp/lspd.db-wal /tmp/
adb pull /data/local/tmp/lspd.db-shm /tmp/
```

**Step 3: Edit the database locally** (requires `sqlite3` on host — not available on device)

```bash
sqlite3 /tmp/lspd.db

-- Check existing modules
SELECT * FROM modules;

-- Insert VPN Hide as enabled module
INSERT INTO modules (module_pkg_name, apk_path, enabled)
VALUES ('dev.okhsunrog.vpnhide',
        '/data/app/~~<random>/dev.okhsunrog.vpnhide-<random>/base.apk',
        1);

-- Get the mid (auto-incremented)
SELECT mid FROM modules WHERE module_pkg_name = 'dev.okhsunrog.vpnhide';
-- Example: mid = 2

-- Set scope: system_server (system), user 0
INSERT INTO scope (mid, app_pkg_name, user_id)
VALUES (2, 'system', 0);

-- Verify
SELECT * FROM modules;
SELECT * FROM scope;

.quit
```

**Step 4: Push the database back**

```bash
adb push /tmp/lspd.db /data/local/tmp/lspd.db
adb shell "su -c 'cp /data/local/tmp/lspd.db /data/adb/lspd/config/modules_config.db'"
adb shell "su -c 'chown root:root /data/adb/lspd/config/modules_config.db'"
adb shell "su -c 'chmod 600 /data/adb/lspd/config/modules_config.db'"

# If WAL/SHM were modified, push those too:
adb push /tmp/lspd.db-wal /data/local/tmp/lspd.db-wal
adb shell "su -c 'cp /data/local/tmp/lspd.db-wal /data/adb/lspd/config/modules_config.db-wal'"
adb shell "su -c 'chown root:root /data/adb/lspd/config/modules_config.db-wal; chmod 600 /data/adb/lspd/config/modules_config.db-wal'"

# Delete SHM so SQLite rebuilds it from WAL on next open
adb shell "su -c 'rm -f /data/adb/lspd/config/modules_config.db-shm'"
```

**Step 5: Reboot**

```bash
adb reboot
```

### Verifying LSPosed hooks are active

After reboot, check these indicators:

```bash
# 1. Hook status file — presence means hooks loaded into system_server
adb shell "su -c 'cat /data/system/vpnhide_hook_active'"
# Expected output:
# version=0.7.1
# boot_id=<matches getprop ro.boot.boot_id>
# timestamp=<unix time>

# 2. LSPosed verbose log — confirms module loaded
adb shell "su -c 'cat /data/adb/lspd/log/verbose_*.log'" | grep -i vpnhide
# Expected:
# Loading legacy module dev.okhsunrog.vpnhide
# Loading class dev.okhsunrog.vpnhide.HookEntry

# 3. LSPosed modules log
adb shell "su -c 'cat /data/adb/lspd/log/modules_*.log'" | grep -i vpnhide
```

### Enabling debug logging for LSPosed hooks

VPNHide's `HookEntry` uses `XposedBridge.log()` — output goes to LSPosed log files, **not** logcat:

```bash
# Enable debug logging
adb shell "su -c 'echo 1 > /data/system/vpnhide_debug_logging'"

# Read LSPosed logs (hooks log here, not in logcat)
adb shell "su -c 'cat /data/adb/lspd/log/verbose_*.log'" | grep -i "vpnhide\|STRIPPED\|VPN"

# Disable debug logging
adb shell "su -c 'echo 0 > /data/system/vpnhide_debug_logging'"
```

### How VPNHide Java hooks work

VPNHide's `HookEntry.java` (Xposed entry point, loaded into `system_server`):

| Hook target | What it does |
|---|---|
| `NetworkCapabilities.writeToParcel()` | Strips `TRANSPORT_VPN` (bit 4), removes `VpnTransportInfo`, sets `NET_CAPABILITY_NOT_VPN` (bit 15) |
| `NetworkInfo.writeToParcel()` | Changes type from `TYPE_VPN` to `TYPE_WIFI` |
| `LinkProperties.writeToParcel()` | Removes VPN interface name from interface list |

The hooks only apply to target UIDs (apps you've selected in VPN Hide app). The UID list is synchronized between kernel and LSPosed:

| File | Used by | Format |
|---|---|---|
| `/proc/vpnhide_targets` | Kernel hooks | One UID per line |
| `/data/system/vpnhide_uids.txt` | LSPosed hooks | One UID per line |
| `/data/adb/vpnhide_kmod/targets.txt` | KSU module (source) | One package name per line |

The `vpnhide_kmod` KSU module's `service.sh` runs at boot and:
1. Reads package names from `/data/adb/vpnhide_kmod/targets.txt`
2. Resolves each to a UID via `pm` / `dumpsys`
3. Writes UIDs to `/proc/vpnhide_targets` (kernel) and `/data/system/vpnhide_uids.txt` (LSPosed)

### What LSPosed hooks add vs kernel-only

| Detection method | Kernel VPNHide | + LSPosed hooks |
|---|---|---|
| `getifaddrs()` / `ioctl(SIOCGIFCONF)` | Hidden | Hidden |
| `/proc/net/route` / netlink | Hidden | Hidden |
| `ConnectivityManager.hasTransport(TRANSPORT_VPN)` | **Not hidden** | **Hidden** |
| `ConnectivityManager.getNetworkCapabilities()` | **Not hidden** | **Hidden** |
| `NetworkInfo.getType() == TYPE_VPN` | **Not hidden** | **Hidden** |
| `LinkProperties.getInterfaceName()` | **Not hidden** | **Hidden** |

---

## Part 2: Play Integrity Bypass

### Background

Google Play Integrity API replaced SafetyNet in 2023. It has three levels:

| Level | What it checks | Typical use |
|---|---|---|
| **BASIC** | App not tampered, basic device integrity | Most apps |
| **DEVICE** | Bootloader locked, verified boot, attestation | Banking, Google Pay |
| **STRONG** | Hardware key attestation with valid keybox | Rare (some enterprise/gov) |

With an **unlocked bootloader**, the device fails DEVICE and STRONG by default:
- `ro.boot.verifiedbootstate` = `unlocked` (should be `green` or empty)
- `ro.boot.flash.locked` = empty (should be `1` or `locked`)
- `ro.boot.vbmeta.device_state` = `unlocked` (should be `locked`)
- TEE (Qualcomm QSEE) is broken — hardware key attestation cannot sign with the original key

### Solution: TrickyStore + IntegrityBox

Two modules work together:

| Module | Version | Role |
|---|---|---|
| **TrickyStore** | v1.4.1 (245) | Zygisk module — intercepts keystore attestation, modifies certificate chain |
| **IntegrityBox** | v37 (37000) | KSU module — prop spoofing, keybox management, WebUI dashboard |

**Why this combination:**
- The original PlayIntegrityFix (chiteroman) is **dead** — all repositories (PlayIntegrityFix, FrameworkPatch, BootloaderSpoofer) return 404, deleted by author
- TrickyStore attacks the **attestation pipeline** itself (keystore injection), not prop spoofing — fundamentally harder for Google to break server-side
- IntegrityBox handles prop spoofing + keybox lifecycle management + automatic `target.txt` updates

### How TrickyStore works

```
┌──────────────────────────────────────────────────────────┐
│  App requests KeyAttestation                             │
│       │                                                  │
│       ▼                                                  │
│  Keystore daemon (system process)                        │
│       │                                                  │
│  ┌─── TrickyStore Zygisk injection ──────────────┐      │
│  │  Intercept keystore attestation call           │      │
│  │                                                │      │
│  │  Mode selection (auto):                        │      │
│  │  • Leaf hack: modify leaf certificate          │      │
│  │    - bootloader_state → locked                 │      │
│  │    - security_level → TrustedEnvironment       │      │
│  │    - root_of_trust → non-software              │      │
│  │  • Generate mode (TEE broken, our case):       │      │
│  │    - Generate new certificate chain            │      │
│  │    - Sign with keybox.xml private key          │      │
│  │    - Embed spoofed attestation values          │      │
│  └────────────────────────────────────────────────┘      │
│       │                                                  │
│       ▼  Modified certificate chain                      │
│  Google servers verify: device looks locked, certified   │
│  Result: DEVICE ✅, STRONG ❌ (public keybox revoked — see keybox table below)          │
└──────────────────────────────────────────────────────────┘
```

**TEE status:** `teeBroken=true` on this device (unlocked bootloader breaks Qualcomm QSEE). TrickyStore automatically falls back to **generate mode** — it creates a new certificate chain signed by the keybox.xml private key, with spoofed attestation values (bootloader locked, verified boot green, security level TrustedEnvironment).

### How IntegrityBox works

IntegrityBox (module ID: `playintegrityfix`) handles everything TrickyStore doesn't:

| Feature | What it does |
|---|---|
| Prop spoofing | `ro.boot.flash.locked` → `1`, `ro.boot.verifiedbootstate` → `green`, `ro.boot.vbmeta.device_state` → `locked` |

> **OnePlus 7 Pro caveat:** `ro.boot.verifiedbootstate` does not exist in kernel bootargs on this device. IntegrityBox's `resetprop_if_diff` function has a bug that skips setting non-existent props (see [Part 5](#part-5-verifiedbootstate--resetprop_if_diff-bug) below). Props must be set manually via `resetprop -n` after each boot.
| Security patch spoofing | `ro.build.version.security_patch` and `ro.vendor.build.security_patch` → recent date |
| Build tag spoofing | Removes `debug` / `test-keys` tags |
| SELinux spoofing | Reports `enforcing` even if permissive |
| Keybox management | WebUI indicator: green = valid STRONG, yellow = DEVICE only, red = revoked |
| target.txt management | Auto-maintains TrickyStore's target list |
| Play Store "Device not certified" fix | Clears GMS vending cache |

### Installation

#### Step 1: Install TrickyStore

```bash
# Download TrickyStore v1.4.1 from GitHub releases
# https://github.com/5ec1cff/TrickyStore/releases/tag/1.4.1
# SHA256: 2f5e73fcba0e4e43b6e96b38f333cbe394873e3a81cf8fe1b831c2fbd6c46ea9

# Install via KSU Next Manager (UI: Install from storage → select ZIP)
# Or via adb:
adb push TrickyStore.zip /data/local/tmp/
adb shell "su -c 'ksud module install /data/local/tmp/TrickyStore.zip'"
```

#### Step 2: Install IntegrityBox

```bash
# Download IntegrityBox from GitHub releases
# https://github.com/MeowDump/Integrity-Box/releases

# Install via KSU Next Manager or adb:
adb push IntegrityBox.zip /data/local/tmp/
adb shell "su -c 'ksud module install /data/local/tmp/IntegrityBox.zip'"
```

#### Step 3: Reboot

```bash
adb reboot
```

#### Step 4: Verify

```bash
# Check both modules are enabled
adb shell "su -c 'ls /data/adb/modules/'"
# Should include: tricky_store, playintegrityfix

# Check TrickyStore config
adb shell "su -c 'cat /data/adb/tricky_store/tee_status'"
# teeBroken=true (expected on unlocked bootloader)

adb shell "su -c 'cat /data/adb/tricky_store/target.txt'"
# com.android.vending
# com.google.android.gms
# (and possibly others)

adb shell "su -c 'cat /data/adb/tricky_store/security_patch.txt'"
# all=2026-06-01 (or similar recent date)

# Check spoofed props
adb shell "su -c 'getprop ro.boot.flash.locked'"
# locked

adb shell "su -c 'getprop ro.boot.verifiedbootstate'"
# green (if IntegrityBox set it, or manually via resetprop -n)
# If empty, set manually:
# adb shell "su -c '/data/adb/ksu/bin/resetprop -n ro.boot.verifiedbootstate green'"

adb shell "su -c 'getprop ro.boot.vbmeta.device_state'"
# locked (if IntegrityBox set it, or manually via resetprop -n)

adb shell "su -c 'getprop ro.build.version.security_patch'"
# 2026-06-01 (spoofed)
```

#### Step 5: Test with Play Integrity checker

Install any Play Integrity checker app (e.g. `gr.nikolasspyr.integritycheck`) and run it:

| Check | Expected result |
|---|---|
| MEETS BASIC INTEGRITY | PASS |
| MEETS DEVICE INTEGRITY | PASS |
| MEETS STRONG INTEGRITY | FAIL (public keybox revoked for STRONG; DEVICE passes) |

### Keybox management (for STRONG integrity)

**STRONG integrity requires a valid, unrevoked `keybox.xml`** at `/data/adb/tricky_store/keybox.xml`.

The keybox is a hardware attestation key leaked from a real device. Google can revoke it server-side at any time. TrickyStore README states: *"For more than DEVICE integrity, put an unrevoked hardware keybox.xml"*.

**Keybox types and current status (as of 2026-06-30):**

| Keybox name | DeviceID | DEVICE | STRONG | Status |
|---|---|---|---|---|
| Community Keybox | `Community Keybox` | ✅ → ❌ | ❌ | Fully revoked by Google |
| Device Integrity | `Device Integrity` | ✅ | ❌ | Works for DEVICE only — root cert serial `f92009e853b6b045` flagged for STRONG |
| Private keybox | (varies) | ✅ | ✅ | Extremely rare — extracted from real Pixel devices, not publicly available |

**How to update keybox (IntegrityBox `key.sh` script):**

IntegrityBox includes a `key.sh` script that downloads a fresh keybox from the MeowDump GitHub repository:

```bash
# Method 1: Via IntegrityBox WebUI → BeastMode → "Update Keybox"
# This runs key.sh which downloads from MeowDump/MeowDump/Megatron

# Method 2: Via adb (manual)
adb shell "su -c 'sh /data/adb/modules/playintegrityfix/webroot/common_scripts/key.sh'"
```

The `Megatron` file on GitHub is encoded (base64 ×10 → hex → ROT13). The `key.sh` script handles decoding automatically. To decode manually on a host machine:

```bash
curl -fsSL "https://raw.githubusercontent.com/MeowDump/MeowDump/refs/heads/main/Megatron" -o megatron_raw
# base64 decode 10x (remove newlines each time)
# hex decode with xxd -r -p
# ROT13 decode with tr 'A-Za-z' 'N-ZA-Mn-za-m'
# Result: valid keybox.xml (~17KB)
```

**When keybox is revoked:**

1. Run `key.sh` (via WebUI BeastMode or adb) to fetch the latest keybox
2. Or manually replace `/data/adb/tricky_store/keybox.xml` with a new keybox
3. Kill and restart the TrickyStore daemon:
   ```bash
   adb shell "su -c 'kill $(ps -A | grep TrickyStore | awk \"{print \\$2}\")'"
   adb shell "su -c 'setsid /data/adb/modules/tricky_store/daemon </dev/null >/dev/null 2>&1 &'"
   ```
4. Force-stop GMS to clear cached attestation results:
   ```bash
   adb shell "su -c 'am force-stop com.google.android.gms; am force-stop com.google.android.gms.unstable'"
   ```
5. No reboot needed — TrickyStore reads keybox at each attestation call

**Keybox format:**

```xml
<?xml version="1.0"?>
<AndroidAttestation>
  <NumberOfKeyboxes>1</NumberOfKeyboxes>
  <Keybox DeviceID="...">
    <Key algorithm="ecdsa">
      <PrivateKey format="pem">
-----BEGIN EC PRIVATE KEY-----
...
-----END EC PRIVATE KEY-----
      </PrivateKey>
      <CertificateChain>
        <NumberOfCertificates>...</NumberOfCertificates>
        <Certificate format="pem">
-----BEGIN CERTIFICATE-----
...
-----END CERTIFICATE-----
        </Certificate>
      </CertificateChain>
    </Key>
  </Keybox>
</AndroidAttestation>
```

### TrickyStore configuration files

All files at `/data/adb/tricky_store/`:

| File | Purpose | Example |
|---|---|---|
| `keybox.xml` | Hardware attestation key for STRONG integrity | (PEM key + certificate chain) |
| `target.txt` | Apps to intercept keystore for | `com.google.android.gms`, `com.android.vending` |
| `security_patch.txt` | Spoofed security patch level in attestation | `all=2026-06-01` |
| `tee_status` | Auto-detected TEE state | `teeBroken=true` |
| `key_db/keystore.db` | Persistent generated key storage | (auto-managed) |

**target.txt mode modifiers** (append after package name):

| Modifier | Mode | When to use |
|---|---|---|
| (none) | Auto — leaf hack if TEE works, generate if broken | Default |
| `!` | Force generate mode | TEE broken, leaf hack doesn't work |
| `?` | Force leaf hack mode | TEE works, want minimal modification |

```bash
# Example target.txt:
# com.google.android.gms!          ← force generate mode
# io.github.vvb2060.mahoshojo?     ← force leaf hack mode
# com.android.vending              ← auto mode
```

**security_patch.txt format:**

```bash
# Simple (all fields same date):
2026-06-01

# Advanced (per-field):
system=2026-06-01
vendor=2026-06-01
boot=no                  # don't spoof boot patch level
# all=2026-06-01         # default for all
# system=prop            # keep consistent with system prop
```

### Full module stack after installation

| Module | Version | Purpose |
|---|---|---|
| tricky_store | v1.4.1 (245) | Keystore attestation bypass |
| playintegrityfix (IntegrityBox) | v37 (37000) | Prop spoofing + keybox management + WebUI |
| rezygisk | v1.0.0 (515) | Zygisk implementation |
| zygisk_lsposed | v1.9.2 (7024) | Xposed framework (for VPNHide Java hooks) |
| vpnhide_kmod | v0.7.1 (701) | VPNHide UID resolver at boot |
| zygisk-detach | v1.23.1 (33) | Detach apps from Play Store |
| youtube-jhc | v20.14.43 | YouTube ReVanced |

### Long-term stability

| Integrity level | Stability | What can break it | Fix |
|---|---|---|---|
| **BASIC** | High — months/years | KSU-Next detection (unlikely) | Update KSU-Next |
| **DEVICE** | Medium — months | Google server-side attestation change | Update TrickyStore |
| **STRONG** | Low — weeks/months | Keybox revocation (guaranteed eventually) | Replace keybox.xml |

**Why TrickyStore is more stable than the dead PIF:**

PIF (PlayIntegrityFix) used prop spoofing — changing `ro.build.fingerprint` and similar props to pretend to be a Pixel. Google broke this server-side by cross-referencing fingerprint with attestation data. One server-side change killed all PIF users simultaneously.

TrickyStore intercepts the **keystore attestation pipeline** itself — it modifies the certificate chain that the hardware produces. To break this, Google would need to change how certificate chains are verified server-side, which risks breaking legitimate devices with older TEE firmware. This is architecturally harder for Google to attack.

**STRONG is fragile by design:** the keybox is a shared leaked key. Google sees anomalous usage patterns (one key → thousands of devices) and revokes it. This is a cat-and-mouse game that will continue indefinitely.

**Practical recommendation:** DEVICE integrity covers 99% of apps (banking, Google Pay, Tinkoff, streaming). STRONG is a bonus while the keybox lasts — don't rely on it for critical functionality.

### Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| BASIC fails | KSU-Next not hiding properly | Reboot, check KSU-Next manager status |
| DEVICE fails | TrickyStore not injecting | Check `tee_status`, reflash TrickyStore, reboot |
| DEVICE fails | Conflicting PIF module | Remove old PlayIntegrityFix module, keep only IntegrityBox |
| STRONG fails | Keybox revoked | Replace keybox.xml via `key.sh` or manually (see keybox management above) |
| STRONG fails | Public keybox (Device Integrity) only passes DEVICE | Need private unrevoked keybox — not publicly available |
| STRONG fails | Keybox format wrong | Verify XML is well-formed, check TrickyStore logs |
| DEVICE fails | GMS cache stale | `am force-stop com.google.android.gms; pm clear com.google.android.gms` |
| DEVICE fails | `verifiedbootstate` prop missing | `resetprop -n ro.boot.verifiedbootstate green` (see Part 5) |
| DEVICE fails | TrickyStore daemon not running | Restart daemon (see keybox management above) |
| "Device not certified" in Play Store | GMS vending cache stale | IntegrityBox WebUI → clear cache, or `am force-stop com.android.vending` |
| SELinux permissive warning | Custom kernel or module set permissive | Ensure `getenforce` returns `Enforcing` |
| All fail after GMS update | GMS version too new / incompatible | Wait for TrickyStore update, or downgrade GMS temporarily |

---

## Part 3: Ozon "No Connection" Fix — TrustMeAlready SSL Hook

### Problem

The Ozon app (`ru.ozon.app.android`) showed a "no connection" error immediately on launch — within ~488ms, too fast for a real network round-trip. The error screen appeared before any actual network request could complete, indicating a **local failure**, not a server-side issue.

### Root cause: TrustMeAlready LSPosed module

**TrustMeAlready** (`com.virb3.trustmealready`, LSPosed module ID 3) was in Ozon's LSPosed scope. TrustMeAlready hooks `TrustManagerImpl.checkTrustedRecursive` in the target app's process, disabling all SSL/TLS certificate validation. This breaks the SSL handshake for apps that use **libcronet** (Chromium's network stack) — which Ozon does.

**Detection chain:**

```
Ozon launches
    │
    ▼
TrustMeAlready hooks TrustManagerImpl.checkTrustedRecursive in Ozon process
    │
    ▼
Ozon's libcronet (libcronet.138.0.7204.157.so) attempts HTTPS to api.ozon.ru
    │
    ▼
SSL/TLS handshake fails — TrustManagerImpl returns no trusted certificates
    │
    ▼
Chromium net stack: SSL error code 1, net_error -207 (ERR_BAD_SSL_CLIENT_AUTH_CERT)
    │
    ▼
libcronet reports UnknownHostException/ConnectException to Ozon Java layer
    │
    ▼
ScreenStateExtKt.java:43 catches exception → shows R.string.error_composer_message_no_connection_full
    │
    ▼
User sees "no connection" error (488ms after launch)
```

**Key evidence from logcat:**

```
SSL error code 1, net_error -207  (ERR_BAD_SSL_CLIENT_AUTH_CERT)
BXInterceptor: Have 403 on url https://api.ozon.ru/composer-api.bx/_action/mapKeys
FullScreenAntibotActivity appeared 488ms after launch  (too fast for network response)
```

The 403 from the antibot endpoint (`Ed0/w.java` checks HTTP 403 for `incidentId` from `AntibotDTO`) was a **secondary symptom** — the antibot system was triggered by the broken SSL handshake, not by VPN detection or DNS issues.

### What it was NOT

| Suspected cause | Investigated? | Ruled out? |
|---|---|---|
| VPNHide kernel hooks | Yes — traced 11 hooks, all working correctly | ✅ Ruled out |
| VPNHide LSPosed Java hooks | Yes — traced NC/NI/LP writeToParcel hooks | ✅ Ruled out |
| DNS resolution failure | Yes — tested Tele2/Google/Cloudflare/Yandex DNS | ✅ Ruled out (DNS was working) |
| Private DNS / DoT timeout | Yes — Tele2 DNS doesn't support DoT (see [Part 4](#part-4-dns--private-dns-configuration)) | ✅ Fixed separately, but not the Ozon cause |
| Ozon antibot detection | Yes — decompiled Ozon APK, analyzed antibot flow | ✅ Secondary symptom, not root cause |
| RootBeer root detection | Yes — `libtoolChecker.so` is RootBeer, not VPN detection | ✅ Ruled out |

### Fix

Remove Ozon from TrustMeAlready's LSPosed scope. TrustMeAlready should only be applied to apps that need certificate pinning bypass (e.g., Wildberries for API interception) — **not** to apps that need valid SSL (e.g., Ozon, banking apps).

**Via LSPosed DB (no sqlite3 on device):**

```bash
# Pull LSPosed DB
adb shell "su -c 'cp /data/adb/lspd/config/modules_config.db /data/local/tmp/modules_config.db'"
adb pull /data/local/tmp/modules_config.db /tmp/lspd.db

# Edit with sqlite3 on host
sqlite3 /tmp/lspd.db
# View TrustMeAlready scope (mid=3):
# SELECT * FROM scope WHERE mid=3;
# Remove Ozon entries:
# DELETE FROM scope WHERE mid=3 AND app_pkg_name IN ('ru.ozon.app.android', 'ru.ozon.seller_app');
# .quit

# Push back
adb push /tmp/lspd.db /data/local/tmp/modules_config.db
adb shell "su -c 'cp /data/local/tmp/modules_config.db /data/adb/lspd/config/modules_config.db'"
adb shell "su -c 'cp /data/local/tmp/modules_config.db-wal /data/adb/lspd/config/modules_config.db-wal 2>/dev/null'"
adb shell "su -c 'chown root:root /data/adb/lspd/config/modules_config.db*'"
adb shell "su -c 'chmod 600 /data/adb/lspd/config/modules_config.db*'"
```

**Via LSPosed Manager UI:**

1. Open LSPosed Manager
2. Go to TrustMeAlready → Scope
3. Uncheck `ru.ozon.app.android` and `ru.ozon.seller_app`
4. Reboot (or force-stop Ozon)

**After reboot:** Ozon launches and connects successfully ✅

### TrustMeAlready scope recommendations

| App | In scope? | Reason |
|---|---|---|
| `com.wildberries.ru` | ✅ Yes | Wildberries uses cert pinning that blocks API interception |
| `wb.partners` | ✅ Yes | WB Partners seller app — same reason |
| `system` | ✅ Yes | System-level cert bypass for debugging |
| `ru.ozon.app.android` | ❌ No | Ozon uses libcronet — SSL bypass breaks its network stack |
| `ru.ozon.seller_app` | ❌ No | Same as above |
| Banking apps | ❌ No | SSL bypass breaks certificate-based mutual TLS |

### Ozon antibot system (for reference)

Ozon uses a server-side antibot system. When triggered (HTTP 403), it returns an `AntibotDTO` with:
- `incidentId` — server-generated incident ID (e.g., "Incident 050")
- `challengeURL` — URL for antibot challenge page
- `captchaURL` — URL for CAPTCHA if needed
- `errorText` — human-readable error message

The antibot handler (`Ed0/w.java`) checks HTTP 403 responses for `incidentId` and shows `FullScreenAntibotActivity` for challenges. This is a **legitimate server-side protection** — not related to VPN, root, or SSL. If you see the antibot screen, it means the server detected suspicious behavior (too many requests, unusual patterns, etc.).

---

## Part 4: DNS / Private DNS Configuration

### Problem

After fixing the Ozon SSL issue, DNS resolution was slow (3+ seconds) for some apps, causing intermittent connection timeouts. This was caused by Android's **Private DNS** (DNS-over-TLS) configuration.

### Root cause: Tele2 DNS servers do not support DoT

On Tele2 Russia (carrier), the default DNS servers are:
- `176.59.62.126` (primary)
- `176.59.62.125` (secondary)

These DNS servers **do not support DNS-over-TLS (DoT)** — port 853 times out (3+ seconds, not refused, just silently dropped). When Android's Private DNS mode is set to `opportunistic` (the default, `private_dns_mode = null`), Android tries DoT on port 853 first, waits for timeout, then falls back to plain DNS on port 53. This causes 3+ second delays on every DNS resolution.

**DNS server comparison (tested from Tele2 network in Russia):**

| DNS server | Port 53 (plain) | Port 853 (DoT) | Notes |
|---|---|---|---|
| Tele2 `176.59.62.126` | ✅ Works | ❌ Timeout (3+s) | Default carrier DNS — no DoT support |
| Tele2 `176.59.62.125` | ✅ Works | ❌ Timeout (3+s) | Same |
| Google `8.8.8.8` | ❌ Refused | ❌ Refused | Blocked by TSPU (Russian DPI) |
| Cloudflare `1.1.1.1` | ❌ Refused | ❌ Refused | Blocked by TSPU |
| Yandex `77.88.8.8` | ✅ Works | ✅ Works (DoT) | Only Russian DNS with DoT that works |

**Russia whitelist mode note:** Foreign DNS servers (8.8.8.8, 1.1.1.1) are blocked by TSPU until a VPN tunnel is up. Even with VPN, using foreign DNS for plain DNS can cause issues. Yandex DNS (77.88.8.8) is the most reliable choice for Russia.

### Fix: Disable Private DNS

```bash
# Check current Private DNS mode
adb shell "settings get global private_dns_mode"
# null = opportunistic (default) — causes DoT timeout on Tele2

# Disable Private DNS (use plain DNS only)
adb shell "settings put global private_dns_mode off"

# Verify
adb shell "settings get global private_dns_mode"
# off
```

**Do NOT use `private_dns_mode = hostname` with Tele2 DNS:**

```bash
# This BREAKS DNS entirely:
adb shell "settings put global private_dns_mode hostname"
adb shell "settings put global private_dns_specifier dns.yandex.ru"
# Android tries DoT to Tele2's DNS servers (not dns.yandex.ru!) → all DNS fails
# Tele2 DNS doesn't support DoT → complete DNS outage
```

The `private_dns_specifier` only works when the carrier DNS servers support DoT — it specifies the hostname for the TLS certificate, but Android still connects to the **carrier's DNS servers** on port 853, not to the specified hostname. On Tele2, this means DoT goes to `176.59.62.126:853` which times out.

### Recommended DNS configuration for Tele2 Russia

```bash
# Disable Private DNS (plain DNS via carrier)
adb shell "settings put global private_dns_mode off"

# If using VPN tether (VPN Tether module), DNS is handled by the module:
# - DHCP pushes 77.88.8.8 (Yandex DNS) to tethered clients
# - DNAT rule redirects all tethered DNS traffic to 77.88.8.8
# - This bypasses carrier DNS entirely for tethered clients
```

### Verification

```bash
# Test DNS resolution speed
adb shell "su -c 'time nslookup api.ozon.ru'"
# Should resolve in <100ms with private_dns_mode=off

# Test with DoT (should timeout on Tele2):
adb shell "su -c 'time nc -w3 176.59.62.126 853 && echo open || echo timeout'"
# timeout (3+ seconds)

# Test plain DNS (should work instantly):
adb shell "su -c 'time nc -w3 176.59.62.126 53 && echo open || echo timeout'"
# open (instant)
```

---

## Part 5: verifiedbootstate & resetprop_if_diff bug

### Problem

After reboot, `ro.boot.verifiedbootstate` was empty (not set). Play Integrity DEVICE check requires this prop to be `green`. IntegrityBox's `resetprop_if_diff` function was supposed to set it, but didn't.

### Root cause: IntegrityBox `resetprop_if_diff` bug

The `resetprop_if_diff` function in `/data/adb/modules/playintegrityfix/common_func.sh` has a logic bug:

```bash
# Buggy implementation:
resetprop_if_diff() {
    NAME="$1"
    EXPECTED="$2"
    CURRENT=$(getprop "$NAME")
    [ -z "$CURRENT" ] || [ "$CURRENT" = "$EXPECTED" ] || $RESETPROP "$NAME" "$EXPECTED"
}
```

The logic `[ -z "$CURRENT" ] || [ "$CURRENT" = "$EXPECTED" ] || $RESETPROP "$NAME" "$EXPECTED"` means:
1. If `CURRENT` is empty → first condition `[ -z "$CURRENT" ]` is true → **short-circuits, prop never set**
2. If `CURRENT` equals `EXPECTED` → second condition is true → short-circuits, no need to set (correct)
3. If `CURRENT` differs from `EXPECTED` → both false → prop is set (correct)

**The bug:** When the prop doesn't exist at all (empty), the function **skips setting it** — the exact opposite of what's needed. Non-existent props are the most common case on devices that don't have these props in kernel bootargs.

### Why `ro.boot.verifiedbootstate` is missing on OnePlus 7 Pro

OnePlus 7 Pro (guacamole, OOS 11) does not include `ro.boot.verifiedbootstate` in the kernel bootargs. The prop simply doesn't exist after boot. Other props that may be missing:
- `ro.boot.flash.locked` — exists but set to `0` (unlocked)
- `ro.boot.vbmeta.device_state` — exists, set to `locked` (but can be wrong on some ROMs)

### Fix: Manual resetprop after each boot

```bash
# Set the missing/wrong props manually
adb shell "su -c '/data/adb/ksu/bin/resetprop -n ro.boot.verifiedbootstate green'"
adb shell "su -c '/data/adb/ksu/bin/resetprop -n ro.boot.flash.locked 1'"
adb shell "su -c '/data/adb/ksu/bin/resetprop -n ro.boot.vbmeta.device_state locked'"

# Verify
adb shell "getprop ro.boot.verifiedbootstate"  # green
adb shell "getprop ro.boot.flash.locked"       # 1
adb shell "getprop ro.boot.vbmeta.device_state" # locked
```

**Note:** These props are NOT persistent across reboots — `resetprop -n` sets them in the running property service, but they're reset on reboot. You must re-run these commands after every reboot, or create a post-fs-data.sh script.

### Automated fix (persistent across reboots)

Create a KSU module or add to an existing module's `post-fs-data.sh`:

```bash
#!/system/bin/sh
RESETPROP="/data/adb/ksu/bin/resetprop"
$RESETPROP -n ro.boot.verifiedbootstate green
$RESETPROP -n ro.boot.flash.locked 1
$RESETPROP -n ro.boot.vbmeta.device_state locked
```

Or patch the IntegrityBox bug directly:

```bash
# Pull common_func.sh
adb shell "su -c 'cp /data/adb/modules/playintegrityfix/common_func.sh /data/local/tmp/common_func.sh'"
adb pull /data/local/tmp/common_func.sh

# Fix the bug: change [ -z "$CURRENT" ] || to always set when empty
# Original:  [ -z "$CURRENT" ] || [ "$CURRENT" = "$EXPECTED" ] || $RESETPROP "$NAME" "$EXPECTED"
# Fixed:     [ "$CURRENT" = "$EXPECTED" ] || $RESETPROP "$NAME" "$EXPECTED"

# Push back
adb push common_func.sh /data/local/tmp/common_func.sh
adb shell "su -c 'cp /data/local/tmp/common_func.sh /data/adb/modules/playintegrityfix/common_func.sh'"
adb shell "su -c 'chmod 644 /data/adb/modules/playintegrityfix/common_func.sh'"
```

The fix removes the `[ -z "$CURRENT" ] ||` clause entirely — if the prop is empty OR differs from expected, it gets set. This is the correct behavior: non-existent props should be created with the expected value.

### Full prop verification checklist

```bash
# All props that Play Integrity checks:
adb shell "getprop ro.boot.verifiedbootstate"        # green
adb shell "getprop ro.boot.flash.locked"             # 1
adb shell "getprop ro.boot.vbmeta.device_state"      # locked
adb shell "getprop ro.build.type"                    # user
adb shell "getprop ro.build.tags"                    # release-keys
adb shell "getprop ro.debuggable"                    # 0
adb shell "getprop ro.secure"                        # 1
adb shell "getprop ro.build.version.security_patch"  # 2026-06-01 (or recent)
```

### Sources

- [TrickyStore](https://github.com/5ec1cff/TrickyStore) — 5ec1cff, v1.4.1, Nov 2025
- [IntegrityBox](https://github.com/MeowDump/Integrity-Box) — MeowDump, v37, actively maintained
- [VPN Hide](https://github.com/okhsunrog/vpnhide) — Xposed module for Java-level VPN hiding
- [TrustMeAlready](https://github.com/ViRb3/TrustMeAlready) — LSPosed module for SSL certificate pinning bypass
- [ReZygisk](https://github.com/PerformanC/ReZygisk) — standalone Zygisk implementation
- [zygisk_lsposed](https://github.com/LSPosed/LSPosed) — LSPosed via Zygisk
