#!/system/bin/sh
#
# VPN Tether - revoke_vpn.sh
# Revoke VPN tunnel access from a specific tethered device.
# Traffic reverts to direct upstream routing (WiFi or LTE via fallthrough).
#
# Mechanism:
# - Remove ip rule at priority 4500 → traffic falls through to 5000/5100 (upstream)
# - Remove FORWARD ACCEPT for tun0 → DROP catches it (no VPN)
# - Remove DNS RETURN → DNAT to 77.88.8.8 re-applies
# - No need to add per-IP upstream rule — subnet-wide rule at 5000/5100 covers it
#

MODDIR=/data/adb/modules/vpn-tether
STATE_DIR="$MODDIR/state"
AP_IFACE="wlan_ap0"

IP_ADDR="$1"

if [ -z "$IP_ADDR" ]; then
    echo '{"ok":false,"error":"Usage: revoke_vpn.sh <ip>"}'
    exit 1
fi

# Remove tun0 routing rule
ip rule del from "$IP_ADDR" lookup tun0 priority 4500 2>/dev/null

# Remove NAT rule for tun0
iptables -t nat -D POSTROUTING -s "$IP_ADDR" -o tun0 -j MASQUERADE 2>/dev/null

# Remove FORWARD ACCEPT for tun0 (traffic hits DROP again)
iptables -D FORWARD -i "$AP_IFACE" -o tun0 -s "$IP_ADDR" -j ACCEPT 2>/dev/null

# Remove DNS RETURN rules (re-enable DNAT to DNS_SERVER)
iptables -t nat -D PREROUTING -i "$AP_IFACE" -s "$IP_ADDR" -p udp --dport 53 -j RETURN 2>/dev/null
iptables -t nat -D PREROUTING -i "$AP_IFACE" -s "$IP_ADDR" -p tcp --dport 53 -j RETURN 2>/dev/null

# Remove from state file
if [ -f "$STATE_DIR/vpn_grants" ]; then
    grep -vx "$IP_ADDR" "$STATE_DIR/vpn_grants" > "$STATE_DIR/vpn_grants.tmp" 2>/dev/null
    mv "$STATE_DIR/vpn_grants.tmp" "$STATE_DIR/vpn_grants"
fi

echo "{\"ok\":true,\"ip\":\"$IP_ADDR\"}"
