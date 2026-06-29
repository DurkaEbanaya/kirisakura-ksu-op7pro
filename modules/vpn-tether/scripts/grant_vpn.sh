#!/system/bin/sh
#
# VPN Tether - grant_vpn.sh
# Grant VPN tunnel access to a specific tethered device by IP.
# Routes that device's traffic through tun0 (VPN) instead of direct upstream.
#
# Mechanism:
# - ip rule at priority 4500 (before upstream rules at 5000/5100) → lookup tun0
# - FORWARD ACCEPT inserted at position 1 (before DROP wlan_ap0→tun0)
# - DNS RETURN: skip DNAT to 77.88.8.8, let DNS go through VPN naturally
# - MASQUERADE on tun0 for this IP
#

MODDIR=/data/adb/modules/vpn-tether
STATE_DIR="$MODDIR/state"
AP_IFACE="wlan_ap0"

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

# Add ip rule: route this device's traffic through tun0 table
# Priority 4500 < 5000 (upstream rules), so this takes precedence
ip rule add from "$IP_ADDR" lookup tun0 priority 4500 2>/dev/null
if [ $? -ne 0 ]; then
    # Rule may already exist — delete and re-add
    ip rule del from "$IP_ADDR" lookup tun0 priority 4500 2>/dev/null
    ip rule add from "$IP_ADDR" lookup tun0 priority 4500 2>/dev/null
fi

# NAT: masquerade this device's traffic on tun0
iptables -t nat -C POSTROUTING -s "$IP_ADDR" -o tun0 -j MASQUERADE 2>/dev/null
if [ $? -ne 0 ]; then
    iptables -t nat -A POSTROUTING -s "$IP_ADDR" -o tun0 -j MASQUERADE
fi

# FORWARD: allow this device through tun0 (insert before the DROP rule)
iptables -I FORWARD 1 -i "$AP_IFACE" -o tun0 -s "$IP_ADDR" -j ACCEPT

# DNS: skip DNAT for this IP — let DNS go through VPN tunnel naturally
# (VPN's internal DNS handles resolution, bypasses 77.88.8.8 redirect)
iptables -t nat -I PREROUTING 1 -i "$AP_IFACE" -s "$IP_ADDR" -p udp --dport 53 -j RETURN 2>/dev/null
iptables -t nat -I PREROUTING 1 -i "$AP_IFACE" -s "$IP_ADDR" -p tcp --dport 53 -j RETURN 2>/dev/null

# Save to state file for persistence (deduplicate)
touch "$STATE_DIR/vpn_grants"
grep -qx "$IP_ADDR" "$STATE_DIR/vpn_grants" 2>/dev/null || echo "$IP_ADDR" >> "$STATE_DIR/vpn_grants"

echo "{\"ok\":true,\"ip\":\"$IP_ADDR\"}"
