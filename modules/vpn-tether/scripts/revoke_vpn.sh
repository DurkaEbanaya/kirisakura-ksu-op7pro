#!/system/bin/sh
#
# VPN Tether - revoke_vpn.sh
# Revoke VPN tunnel access from a specific tethered device
# Traffic reverts to direct routing with provider DNS
#

MODDIR=/data/adb/modules/vpn-tether
STATE_DIR="$MODDIR/state"
CONF_DIR="$MODDIR/conf"

IP_ADDR="$1"

if [ -z "$IP_ADDR" ]; then
    echo '{"ok":false,"error":"Usage: revoke_vpn.sh <ip>"}'
    exit 1
fi

# Load STA interface from state
STA_IFACE="wlan0"
if [ -f "$STATE_DIR/sta_iface" ]; then
    STA_IFACE=$(cat "$STATE_DIR/sta_iface")
fi

AP_IFACE="wlan_ap0"

# Remove tun0 routing rule
ip rule del from "$IP_ADDR" lookup tun0 priority 4500 2>/dev/null

# Re-add direct STA routing rule
ip rule add from "$IP_ADDR" lookup "$STA_IFACE" priority 5000 2>/dev/null

# Remove NAT rule for tun0
iptables -t nat -D POSTROUTING -s "$IP_ADDR" -o tun0 -j MASQUERADE 2>/dev/null

# Remove DNS RETURN rules (re-enable DNAT to provider DNS)
iptables -t nat -D PREROUTING -i "$AP_IFACE" -s "$IP_ADDR" -p udp --dport 53 -j RETURN 2>/dev/null
iptables -t nat -D PREROUTING -i "$AP_IFACE" -s "$IP_ADDR" -p tcp --dport 53 -j RETURN 2>/dev/null

# Remove from state file
if [ -f "$STATE_DIR/vpn_grants" ]; then
    grep -vx "$IP_ADDR" "$STATE_DIR/vpn_grants" > "$STATE_DIR/vpn_grants.tmp" 2>/dev/null
    mv "$STATE_DIR/vpn_grants.tmp" "$STATE_DIR/vpn_grants"
fi

echo "{\"ok\":true,\"ip\":\"$IP_ADDR\"}"
