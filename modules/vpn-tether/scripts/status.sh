#!/system/bin/sh
#
# VPN Tether - status.sh
# Output JSON status for WebUI
#

MODDIR=/data/adb/modules/vpn-tether
STATE_DIR="$MODDIR/state"
CONF_DIR="$MODDIR/conf"
AP_IFACE="wlan_ap0"

# Find iw
IW=""
for p in /vendor/bin/iw /system/bin/iw; do
    if [ -x "$p" ]; then IW="$p"; break; fi
done

# Load AP config
SSID=""
PASS=""
CHANNEL=""
SUBNET=""
if [ -f "$CONF_DIR/ap_config" ]; then
    . "$CONF_DIR/ap_config"
fi

# ─── Detect STA interface ───
STA_IFACE=""
if [ -n "$IW" ]; then
    for iface in wlan0 wlan1 eth0; do
        TYPE=$($IW dev "$iface" info 2>/dev/null | grep "type " | awk '{print $2}' | tr 'A-Z' 'a-z')
        if [ "$TYPE" = "managed" ]; then
            STA_IFACE="$iface"
            break
        fi
    done
fi

# WiFi STA status
WIFI_SSID=""
WIFI_IP=""
WIFI_CONNECTED=false
WLAN_TYPE=""
if [ -n "$STA_IFACE" ] && [ -n "$IW" ]; then
    WLAN_TYPE=$($IW dev "$STA_IFACE" info 2>/dev/null | grep "type " | awk '{print $2}' | tr 'A-Z' 'a-z')
    if [ "$WLAN_TYPE" = "managed" ]; then
        WIFI_SSID=$($IW dev "$STA_IFACE" info 2>/dev/null | grep "ssid " | sed 's/.*ssid //' | tr -d '\t')
        WIFI_IP=$(ip addr show "$STA_IFACE" 2>/dev/null | grep 'inet ' | awk '{print $2}' | cut -d/ -f1)
        if [ -n "$WIFI_IP" ]; then
            WIFI_CONNECTED=true
        fi
    fi
fi

# If wlan0 is in AP mode (Android hotspot), report it
if [ -z "$STA_IFACE" ] && [ -n "$IW" ]; then
    WLAN_TYPE=$($IW dev wlan0 info 2>/dev/null | grep "type " | awk '{print $2}' | tr 'A-Z' 'a-z')
fi

# VPN status
VPN_ACTIVE=false
VPN_TUN=""
VPN_IP=""
if ip addr show tun0 2>/dev/null | grep -q "inet "; then
    VPN_ACTIVE=true
    VPN_TUN="tun0"
    VPN_IP=$(ip addr show tun0 2>/dev/null | grep 'inet ' | awk '{print $2}' | cut -d/ -f1)
fi

# AP status
AP_ACTIVE=false
AP_SSID=""
AP_IP=""
AP_CLIENTS=0
if [ -f "$STATE_DIR/ap_running" ]; then
    if ip link show "$AP_IFACE" 2>/dev/null | grep -q "state UP"; then
        AP_ACTIVE=true
        if [ -n "$IW" ]; then
            AP_SSID=$($IW dev "$AP_IFACE" info 2>/dev/null | grep "ssid " | sed 's/.*ssid //' | tr -d '\t')
        fi
        AP_IP=$(ip addr show "$AP_IFACE" 2>/dev/null | grep 'inet ' | awk '{print $2}' | cut -d/ -f1)
        AP_CLIENTS=$(cat /proc/net/arp 2>/dev/null | grep "$AP_IFACE" | grep -v "00:00:00:00:00:00" | wc -l)
    fi
fi

# Tether interfaces (USB/BT)
USB_TETHER=false
BT_TETHER=false
if ip link show rndis0 2>/dev/null | grep -q "state UP"; then
    USB_TETHER=true
fi
if ip link show bnep0 2>/dev/null | grep -q "state UP"; then
    BT_TETHER=true
fi

# Output JSON
cat << EOF
{
  "wifi": {
    "connected": $WIFI_CONNECTED,
    "ssid": "$WIFI_SSID",
    "ip": "$WIFI_IP",
    "type": "$WLAN_TYPE"
  },
  "vpn": {
    "active": $VPN_ACTIVE,
    "tun": "$VPN_TUN",
    "ip": "$VPN_IP"
  },
  "ap": {
    "active": $AP_ACTIVE,
    "iface": "$AP_IFACE",
    "ssid": "$AP_SSID",
    "ip": "$AP_IP",
    "clients": $AP_CLIENTS
  },
  "tether": {
    "usb": $USB_TETHER,
    "bt": $BT_TETHER
  },
  "ap_config": {
    "ssid": "$SSID",
    "pass": "$PASS",
    "channel": "$CHANNEL",
    "subnet": "$SUBNET"
  }
}
EOF
