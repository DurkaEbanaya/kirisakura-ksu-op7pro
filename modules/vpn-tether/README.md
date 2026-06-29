# VPN Tether

KernelSU module for sharing VPN tunnel with tethered devices — without dropping WiFi connection.

## What it does

- **Concurrent WiFi AP**: Creates a separate AP interface (`wlan_ap0`) while WiFi stays connected as STA. Your WiFi doesn't drop when sharing.
- **Per-device VPN grant**: One button in WebUI to route a specific tethered device's traffic through the phone's VPN tunnel (tun0).
- **Provider DNS**: Automatically redirects DNS queries to the upstream gateway (not 8.8.8.8) — works in whitelist-restricted networks.
- **Works with USB/BT tethering too**: Enable tethering in Android Settings, then grant VPN per device in WebUI.

## Requirements

- **KernelSU** (for WebUI API)
- **WiFi chip with concurrent STA+AP support** (most Qualcomm WCN3xxx, some MediaTek)
- `iw`, `hostapd`, `busybox` — auto-detected from standard Android paths

## Installation

Flash `vpn-tether-v1.0.zip` in KernelSU Next Manager.

## Usage

1. Connect to WiFi (STA mode)
2. Open KSU Next Manager → Modules → VPN Tether → WebUI
3. Press **Start Hotspot** — concurrent AP starts, WiFi stays connected
4. Connect devices to the AP
5. Devices appear in the list — press **Grant VPN** for each device that needs VPN access
6. To revoke: press **VPN ON** button again

## How it works

### Concurrent AP
```
wlan0 (STA) ←→ MikrotikKAL (5GHz, 866Mbps)
wlan_ap0 (AP) ←→ "OnePlus 7 Pro VPN" (concurrent, same channel)
```

The QCA driver's policy manager automatically selects SCC (Same Channel Concurrent) mode — both STA and AP operate on the same frequency, sharing airtime efficiently.

### VPN routing
```
Tethered device (192.168.204.x)
  → ip rule: from 192.168.204.x lookup tun0
  → NAT: MASQUERADE on tun0
  → Traffic exits through VPN tunnel
```

Without VPN grant, traffic goes through `wlan0` directly (ip rule: lookup wlan0).

### DNS handling
DNS queries from tethered devices are DNAT'd to the upstream gateway (e.g. 192.168.1.1), not to 8.8.8.8. This is critical for whitelist-restricted networks where foreign DNS servers are blocked.

When VPN is granted for a device, DNS queries bypass the DNAT and go through the VPN tunnel naturally.

## WebUI

Built with Windows 10 Fluent Design System: rectangular surfaces, accent `#0078D7`, Reveal Highlight on hover, Acrylic effect on header.

## Configuration

Edit `conf/ap_config` on device:
```
SSID="My Hotspot"
PASS="password123"
CHANNEL="0"
SUBNET="192.168.204"
```

`CHANNEL=0` lets the driver choose the optimal channel (SCC with STA).

## Limitations

- **Android Settings hotspot**: Do NOT use the built-in Android hotspot toggle — it switches wlan0 from STA to AP, dropping WiFi. Use the WebUI instead.
- **VPN app must create tun0**: Standard Android VPN apps (WireGuard, Xray, Happ, etc.) create tun0. Apps using different interfaces may need script adjustments.
- **WebUI requires KernelSU**: The `ksu.exec()` API is KernelSU-specific.

## Tested on

- OnePlus 7 Pro (GM1910), OOS 11, Kirisakura kernel 4.14.243
- WCN3990 WiFi chip, QCA driver
- Pixel 6 as tethered client
- VPN: Happ (su.happ.proxyutility) with Xray
