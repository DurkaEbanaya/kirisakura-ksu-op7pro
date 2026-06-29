#!/system/bin/sh
#
# VPN Tether - stop_ap.sh
# Stop concurrent WiFi AP and clean up all rules for all upstream interfaces
#

MODDIR=/data/adb/modules/vpn-tether
STATE_DIR="$MODDIR/state"
CONF_DIR="$MODDIR/conf"
AP_IFACE="wlan_ap0"

# Load config for subnet and DNS
SUBNET=192.168.204
DNS_SERVER="77.88.8.8"
if [ -f "$CONF_DIR/ap_config" ]; then
    . "$CONF_DIR/ap_config"
fi
[ -n "$DNS" ] && DNS_SERVER="$DNS"

# Read upstream interface list from state (new format)
# Fallback to old sta_iface for backward compatibility
UPSTREAM_IFACES=""
if [ -f "$STATE_DIR/upstream_ifaces" ]; then
    UPSTREAM_IFACES=$(cat "$STATE_DIR/upstream_ifaces")
fi
if [ -z "$UPSTREAM_IFACES" ]; then
    if [ -f "$STATE_DIR/sta_iface" ]; then
        UPSTREAM_IFACES=$(cat "$STATE_DIR/sta_iface")
    fi
    [ -z "$UPSTREAM_IFACES" ] && UPSTREAM_IFACES="wlan0"
fi

# Read old state for backward-compatible SNAT/DNAT cleanup
OLD_GW=""
OLD_IP=""
[ -f "$STATE_DIR/upstream_gw" ] && OLD_GW=$(cat "$STATE_DIR/upstream_gw" 2>/dev/null)
[ -f "$STATE_DIR/upstream_ip" ] && OLD_IP=$(cat "$STATE_DIR/upstream_ip" 2>/dev/null)

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
pkill -f "hostapd.*vpn-tether-hostapd" 2>/dev/null
pkill -f "hostapd.*wlan_ap0" 2>/dev/null
sleep 0.5
pgrep -f "hostapd.*vpn-tether-hostapd" 2>/dev/null && pkill -9 -f "hostapd.*vpn-tether-hostapd" 2>/dev/null

# Kill upstream monitor
pkill -f "upstream_monitor.*vpn-tether" 2>/dev/null

if [ -f "$STATE_DIR/udhcpd.pid" ]; then
    kill "$(cat "$STATE_DIR/udhcpd.pid")" 2>/dev/null
    rm -f "$STATE_DIR/udhcpd.pid"
fi
pkill -f "udhcpd.*vpn-tether" 2>/dev/null

sleep 1

# Remove FORWARD rules for each upstream + tun0 + return + broad
# Also scan all rmnet_dataN in case monitor added interfaces not in state
ALL_IFACES="$UPSTREAM_IFACES wlan0 wlan1"
for i in 0 1 2 3 4 5 6 7 8 9 10; do
    ALL_IFACES="$ALL_IFACES rmnet_data$i"
done
for iface in $ALL_IFACES; do
    while iptables -D FORWARD -i "$AP_IFACE" -o "$iface" -j ACCEPT 2>/dev/null; do :; done
done
while iptables -D FORWARD -i "$AP_IFACE" -o tun0 -j DROP 2>/dev/null; do :; done
while iptables -D FORWARD -o "$AP_IFACE" -j ACCEPT 2>/dev/null; do :; done
# Old broad rules (cleanup from very old versions)
while iptables -D FORWARD -i "$AP_IFACE" -j ACCEPT 2>/dev/null; do :; done

# Remove MASQUERADE on each upstream (scan all rmnet_dataN too)
for iface in $ALL_IFACES; do
    while iptables -t nat -D POSTROUTING -s "${SUBNET}.0/24" -o "$iface" -j MASQUERADE 2>/dev/null; do :; done
done

# Remove DNS DNAT rules (new DNS_SERVER + old gateway if upgrading)
for dns in "$DNS_SERVER" $OLD_GW; do
    [ -z "$dns" ] && continue
    while iptables -t nat -D PREROUTING -i "$AP_IFACE" -p udp --dport 53 -j DNAT --to-destination "$dns:53" 2>/dev/null; do :; done
    while iptables -t nat -D PREROUTING -i "$AP_IFACE" -p tcp --dport 53 -j DNAT --to-destination "$dns:53" 2>/dev/null; do :; done
done

# Remove old DNS SNAT rules (from old version)
if [ -n "$OLD_GW" ] && [ -n "$OLD_IP" ]; then
    for iface in wlan0 wlan1; do
        while iptables -t nat -D POSTROUTING -d "$OLD_GW" -p udp --dport 53 -o "$iface" -j SNAT --to-source "$OLD_IP" 2>/dev/null; do :; done
        while iptables -t nat -D POSTROUTING -d "$OLD_GW" -p tcp --dport 53 -o "$iface" -j SNAT --to-source "$OLD_IP" 2>/dev/null; do :; done
    done
fi

# Remove ip rules for each upstream + unreachable + return
ip rule del from "${SUBNET}.0/24" lookup wlan0 priority 5000 2>/dev/null
for i in 0 1 2 3 4 5 6 7 8 9 10; do
    PRIO=$((5100 + i * 10))
    ip rule del from "${SUBNET}.0/24" lookup "rmnet_data$i" priority "$PRIO" 2>/dev/null
done
# Remove unreachable rule
ip rule del from "${SUBNET}.0/24" unreachable priority 5200 2>/dev/null
# Remove return traffic rule
ip rule del to "${SUBNET}.0/24" lookup main priority 4000 2>/dev/null

# Remove AP interface
ip link set "$AP_IFACE" down 2>/dev/null

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
rm -f "$STATE_DIR/ap_running" "$STATE_DIR/upstream_ifaces" "$STATE_DIR/sta_iface" \
      "$STATE_DIR/upstream_gw" "$STATE_DIR/upstream_ip" "$STATE_DIR/udhcpd.leases"

echo '{"ok":true}'
