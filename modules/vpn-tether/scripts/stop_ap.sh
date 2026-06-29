#!/system/bin/sh
#
# VPN Tether - stop_ap.sh
# Stop concurrent WiFi AP and clean up all rules
#

MODDIR=/data/adb/modules/vpn-tether
STATE_DIR="$MODDIR/state"
CONF_DIR="$MODDIR/conf"
AP_IFACE="wlan_ap0"

# Load config for subnet
SUBNET=192.168.204
if [ -f "$CONF_DIR/ap_config" ]; then
    . "$CONF_DIR/ap_config"
fi

# Load saved state
WLAN_GW=""
WLAN_IP=""
STA_IFACE="wlan0"
if [ -f "$STATE_DIR/upstream_gw" ]; then
    WLAN_GW=$(cat "$STATE_DIR/upstream_gw")
fi
if [ -f "$STATE_DIR/upstream_ip" ]; then
    WLAN_IP=$(cat "$STATE_DIR/upstream_ip")
fi
if [ -f "$STATE_DIR/sta_iface" ]; then
    STA_IFACE=$(cat "$STATE_DIR/sta_iface")
fi

# Check if running
if [ ! -f "$STATE_DIR/ap_running" ]; then
    echo '{"ok":false,"error":"AP not running"}'
    exit 1
fi

# Revoke VPN for all granted devices
if [ -f "$STATE_DIR/vpn_grants" ] && [ -s "$STATE_DIR/vpn_grants" ]; then
    GRANTS_TEMP=$(cat "$STATE_DIR/vpn_grants")
    > "$STATE_DIR/vpn_grants"
    echo "$GRANTS_TEMP" | while IFS= read -r ip; do
        [ -n "$ip" ] && sh "$MODDIR/scripts/revoke_vpn.sh" "$ip" >/dev/null 2>&1
    done
fi

# Kill hostapd and udhcpd
pkill -f "hostapd.*$AP_IFACE" 2>/dev/null
if [ -f "$STATE_DIR/udhcpd.pid" ]; then
    kill "$(cat "$STATE_DIR/udhcpd.pid")" 2>/dev/null
    rm -f "$STATE_DIR/udhcpd.pid"
fi
pkill -f "udhcpd.*vpn-tether" 2>/dev/null

sleep 1

# Remove FORWARD rules
iptables -D FORWARD -i "$AP_IFACE" -j ACCEPT 2>/dev/null
iptables -D FORWARD -o "$AP_IFACE" -j ACCEPT 2>/dev/null

# Remove NAT rules
iptables -t nat -D POSTROUTING -s "${SUBNET}.0/24" -o "$STA_IFACE" -j MASQUERADE 2>/dev/null

# Remove DNS DNAT rules
iptables -t nat -D PREROUTING -i "$AP_IFACE" -p udp --dport 53 -j DNAT --to-destination "$WLAN_GW:53" 2>/dev/null
iptables -t nat -D PREROUTING -i "$AP_IFACE" -p tcp --dport 53 -j DNAT --to-destination "$WLAN_GW:53" 2>/dev/null

# Remove DNS SNAT rules
iptables -t nat -D POSTROUTING -d "$WLAN_GW" -p udp --dport 53 -o "$STA_IFACE" -j SNAT --to-source "$WLAN_IP" 2>/dev/null
iptables -t nat -D POSTROUTING -d "$WLAN_GW" -p tcp --dport 53 -o "$STA_IFACE" -j SNAT --to-source "$WLAN_IP" 2>/dev/null

# Remove routing rules
ip rule del from "${SUBNET}.0/24" lookup "$STA_IFACE" priority 5000 2>/dev/null
ip rule del to "${SUBNET}.0/24" lookup main priority 4000 2>/dev/null

# Remove AP interface
ip link set "$AP_IFACE" down 2>/dev/null

# Find iw for interface deletion
IW=""
for p in /vendor/bin/iw /system/bin/iw; do
    if [ -x "$p" ]; then IW="$p"; break; fi
done
if [ -n "$IW" ]; then
    $IW dev "$AP_IFACE" del 2>/dev/null
fi

# Disable IP forwarding if no other tether active
if ! ip link show rndis0 2>/dev/null | grep -q "state UP"; then
    if ! ip link show bnep0 2>/dev/null | grep -q "state UP"; then
        echo 0 > /proc/sys/net/ipv4/ip_forward 2>/dev/null
    fi
fi

# Clean state
rm -f "$STATE_DIR/ap_running" "$STATE_DIR/upstream_gw" "$STATE_DIR/upstream_ip" "$STATE_DIR/sta_iface" "$STATE_DIR/udhcpd.leases"

echo '{"ok":true}'
