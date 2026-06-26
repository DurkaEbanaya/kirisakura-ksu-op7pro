# LSPosed Java Hooks & Play Integrity Bypass

This document covers two post-install configurations for the Kirisakura-KSU-Next kernel on OnePlus 7 Pro (OOS 11):

1. **Enabling LSPosed Java hooks for VPNHide** — completing the two-level VPN hiding architecture
2. **Bypassing Play Integrity** — passing BASIC, DEVICE, and STRONG integrity checks with unlocked bootloader

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
│  Result: DEVICE ✅, STRONG ✅ (if keybox valid)          │
└──────────────────────────────────────────────────────────┘
```

**TEE status:** `teeBroken=true` on this device (unlocked bootloader breaks Qualcomm QSEE). TrickyStore automatically falls back to **generate mode** — it creates a new certificate chain signed by the keybox.xml private key, with spoofed attestation values (bootloader locked, verified boot green, security level TrustedEnvironment).

### How IntegrityBox works

IntegrityBox (module ID: `playintegrityfix`) handles everything TrickyStore doesn't:

| Feature | What it does |
|---|---|
| Prop spoofing | `ro.boot.flash.locked` → `locked`, `ro.boot.verifiedbootstate` → empty, `ro.boot.vbmeta.device_state` → empty |
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
# (empty — IntegrityBox clears this)

adb shell "su -c 'getprop ro.boot.vbmeta.device_state'"
# (empty — IntegrityBox clears this)

adb shell "su -c 'getprop ro.build.version.security_patch'"
# 2026-06-01 (spoofed)
```

#### Step 5: Test with Play Integrity checker

Install any Play Integrity checker app (e.g. `gr.nikolasspyr.integritycheck`) and run it:

| Check | Expected result |
|---|---|
| MEETS BASIC INTEGRITY | PASS |
| MEETS DEVICE INTEGRITY | PASS |
| MEETS STRONG INTEGRITY | PASS (if keybox valid) |

### Keybox management (for STRONG integrity)

**STRONG integrity requires a valid, unrevoked `keybox.xml`** at `/data/adb/tricky_store/keybox.xml`.

The keybox is a hardware attestation key leaked from a real device. Google can revoke it server-side at any time.

**IntegrityBox WebUI shows keybox status:**
- Green (3 dots) = valid, passes STRONG
- Yellow (2 green, 1 red) = passes DEVICE only
- Red (3 red) = revoked, passes nothing beyond BASIC

**When keybox is revoked:**

1. Open IntegrityBox WebUI (KSU Next Manager → module settings)
2. Use "Get Keybox" button (fetches from community Telegram bot `@integritybox`)
3. Or manually replace `/data/adb/tricky_store/keybox.xml` with a new unrevoked keybox
4. No reboot needed — TrickyStore reads keybox at each attestation call

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
| STRONG fails | Keybox revoked | Replace keybox.xml (IntegrityBox WebUI → Get Keybox) |
| STRONG fails | Keybox format wrong | Verify XML is well-formed, check TrickyStore logs |
| "Device not certified" in Play Store | GMS vending cache stale | IntegrityBox WebUI → clear cache, or `am force-stop com.android.vending` |
| SELinux permissive warning | Custom kernel or module set permissive | Ensure `getenforce` returns `Enforcing` |
| All fail after GMS update | GMS version too new / incompatible | Wait for TrickyStore update, or downgrade GMS temporarily |

### Sources

- [TrickyStore](https://github.com/5ec1cff/TrickyStore) — 5ec1cff, v1.4.1, Nov 2025
- [IntegrityBox](https://github.com/MeowDump/Integrity-Box) — MeowDump, v37, actively maintained
- [KeyBoxer](https://github.com/shall0e/KeyBoxer) — free keybox scraper (community keyboxes)
- [VPN Hide](https://github.com/okhsunrog/vpnhide) — Xposed module for Java-level VPN hiding
- [ReZygisk](https://github.com/PerformanC/ReZygisk) — standalone Zygisk implementation
- [zygisk_lsposed](https://github.com/LSPosed/LSPosed) — LSPosed via Zygisk
