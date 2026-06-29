#!/system/bin/sh
#
# VPN Tether - grant_vpn.sh
# Grant VPN tunnel access to a specific tethered device by IP
# Routes that device's traffic through tun0 (VPN) instead of direct (wlan0)
#

MODDIR=/data/adb/modules/vpn-tether
STATE_DIR="$MODDIR/state"

IP_ADDR="$1"

if [ -z "$IP_ADDR" ]; then
    echo '{"ok":false,"error":"Usage: grant_vpn.sh <ip>"}'
    exit 1
fi

# Check VPN is active
if ! ip addr show tun0 2>/dev/null | grep -q "inet "; then
    echo '{"ok":false,"error":"VPN (tun0) is not active"}'
    exit 1
fi

# Remove the direct-routing rule for this IP (from start_ap.sh)
# so it falls through to the tun0 rule
ip rule del from "$IP_ADDR" lookup wlan0 priority 5000 2>/dev/null
ip rule del from "$IP_ADDR" lookup wlan1 priority 5000 2>/dev/null

# Add ip rule: route this device's traffic through tun0 table
ip rule add from "$IP_ADDR" lookup tun0 priority 4500 2>/dev/null
if [ $? -ne 0 ]; then
    ip rule del from "$IP_ADDR" lookup tun0 priority 4500 2>/dev/null
    ip rule add from "$IP_ADDR" lookup tun0 priority 4500 2>/dev/null
fi

# NAT: masquerade this device's traffic on tun0
iptables -t nat -C POSTROUTING -s "$IP_ADDR" -o tun0 -j MASQUERADE 2>/dev/null
if [ $? -ne 0 ]; then
    iptables -t nat -A POSTROUTING -s "$IP_ADDR" -o tun0 -j MASQUERADE
fi

# Remove DNS DNAT for this specific IP (let DNS go through VPN tunnel naturally)
# Detect AP interface
AP_IFACE="wlan_ap0"
iptables -t nat -I PREROUTING -i "$AP_IFACE" -s "$IP_ADDR" -p udp --dport 53 -j RETURN 2>/dev/null
iptables -t nat -I PREROUTING -i "$AP_IFACE" -s "$IP_ADDR" -p tcp --dport 53 -j RETURN 2>/dev/null

# Save to state file for persistence (deduplicate)
touch "$STATE_DIR/vpn_grants"
grep -qx "$IP_ADDR" "$STATE_DIR/vpn_grants" 2>/dev/null || echo "$IP_ADDR" >> "$STATE_DIR/vpn_grants"

echo "{\"ok\":true,\"ip\":\"$IP_ADDR\"}"
