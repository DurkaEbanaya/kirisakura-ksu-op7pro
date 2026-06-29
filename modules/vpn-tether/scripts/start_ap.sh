#!/system/bin/sh
#
# VPN Tether - start_ap.sh
# Start concurrent WiFi AP on a separate interface.
# Works with ANY upstream: WiFi STA, LTE, or both (automatic failover).
#
# Architecture:
# 1. AP created on WiFi phy — works with or without WiFi STA connection
# 2. Multi-upstream routing via Linux ip rule fallthrough:
#    - WiFi (wlan0) at priority 5000 — preferred
#    - LTE (rmnet_data0) at priority 5100 — fallback
#    - When WiFi table loses default route, rule 5000 fails → falls to 5100
#    - No monitor loop needed — kernel handles failover automatically
# 3. unreachable rule at 5200 — drops traffic if NO upstream has default route
#    (prevents fallthrough to legacy_network → tun0 VPN leak)
# 4. MASQUERADE on all upstream interfaces
# 5. DNS: DNAT to 77.88.8.8 (Yandex) — works on all upstreams, not blocked in RU
# 6. FORWARD: DROP to tun0 by default, ACCEPT per upstream, ACCEPT return
# 7. hostapd config in /data/local/tmp (SELinux-safe)
# 8. udhcpd via setsid (busybox background mode)
# 9. VPN grants restored from state file on AP restart
#

MODDIR=/data/adb/modules/vpn-tether
STATE_DIR="$MODDIR/state"
CONF_DIR="$MODDIR/conf"

# Load config
SSID="VPN Tether"
PASS="vpn12345"
CHANNEL=0
SUBNET=192.168.204
DNS_SERVER="77.88.8.8"
if [ -f "$CONF_DIR/ap_config" ]; then
    . "$CONF_DIR/ap_config"
fi
# Allow DNS override from config
[ -n "$DNS" ] && DNS_SERVER="$DNS"

AP_IFACE="wlan_ap0"
AP_IP="${SUBNET}.1"
DHCP_START="${SUBNET}.10"
DHCP_END="${SUBNET}.50"

# ─── Auto-detect tools ───
IW=""
for p in /vendor/bin/iw /system/bin/iw /data/adb/ksu/bin/busybox; do
    if [ -x "$p" ] && "$p" dev >/dev/null 2>&1; then
        IW="$p"
        break
    fi
done
if [ -z "$IW" ]; then
    for p in /data/adb/ksu/bin/busybox /data/adb/magisk/busybox /data/adb/ap/bin/busybox; do
        if [ -x "$p" ] && [ "$("$p" iw --help 2>&1 | head -1)" != "" ]; then
            IW="$p iw"
            break
        fi
    done
fi
if [ -z "$IW" ]; then
    echo '{"ok":false,"error":"iw not found"}'
    exit 1
fi

HOSTAPD=""
for p in /vendor/bin/hw/hostapd /system/bin/hw/hostapd /vendor/bin/hostapd /system/bin/hostapd; do
    if [ -x "$p" ]; then
        HOSTAPD="$p"
        break
    fi
done
if [ -z "$HOSTAPD" ]; then
    echo '{"ok":false,"error":"hostapd not found"}'
    exit 1
fi

BUSYBOX=""
for p in /data/adb/ksu/bin/busybox /data/adb/magisk/busybox /data/adb/ap/bin/busybox /system/bin/busybox; do
    if [ -x "$p" ]; then
        BUSYBOX="$p"
        break
    fi
done
if [ -z "$BUSYBOX" ]; then
    echo '{"ok":false,"error":"busybox not found"}'
    exit 1
fi

# ─── Detect WiFi STA interface (optional — for SCC channel selection) ───
STA_IFACE=""
for iface in wlan0 wlan1; do
    TYPE=$($IW dev "$iface" info 2>/dev/null | grep "type " | awk '{print $2}' | tr 'A-Z' 'a-z')
    if [ "$TYPE" = "managed" ]; then
        STA_IFACE="$iface"
        break
    fi
done
# STA_IFACE may be empty — AP works without it (LTE-only mode)

# ─── Detect WiFi phy ───
PHY=""
# Try from STA if active
if [ -n "$STA_IFACE" ]; then
    PHY=$($IW dev "$STA_IFACE" info 2>/dev/null | grep "wiphy" | awk '{print $2}')
fi
# Try from any existing WiFi interface
if [ -z "$PHY" ]; then
    for iface in wlan0 wlan1 p2p0; do
        P=$($IW dev "$iface" info 2>/dev/null | grep "wiphy" | awk '{print $2}')
        if [ -n "$P" ]; then
            PHY="$P"
            break
        fi
    done
fi
# Last resort: scan for AP-capable phy
if [ -z "$PHY" ]; then
    for p in 0 1 2; do
        if $IW phy "phy$p" info 2>/dev/null | grep -q "AP"; then
            PHY="$p"
            break
        fi
    done
fi
if [ -z "$PHY" ]; then
    echo '{"ok":false,"error":"Cannot detect WiFi phy. Enable WiFi in Settings."}'
    exit 1
fi

# ─── Check AP support ───
if ! $IW phy "phy$PHY" info 2>/dev/null | grep -q "AP"; then
    echo '{"ok":false,"error":"WiFi chip does not support AP mode"}'
    exit 1
fi

# ─── Kill zombie hostapd from previous runs ───
pkill -f "hostapd.*vpn-tether-hostapd" 2>/dev/null
sleep 0.5
pkill -9 -f "hostapd.*vpn-tether-hostapd" 2>/dev/null
sleep 0.5

# ─── Check if already running ───
if [ -f "$STATE_DIR/ap_running" ]; then
    rm -f "$STATE_DIR/ap_running"
fi

# ─── Clean up ALL old rules from previous runs ───
# Read old state for backward-compatible cleanup
OLD_GW=""
OLD_IP=""
OLD_STA=""
[ -f "$STATE_DIR/upstream_gw" ] && OLD_GW=$(cat "$STATE_DIR/upstream_gw" 2>/dev/null)
[ -f "$STATE_DIR/upstream_ip" ] && OLD_IP=$(cat "$STATE_DIR/upstream_ip" 2>/dev/null)
[ -f "$STATE_DIR/sta_iface" ] && OLD_STA=$(cat "$STATE_DIR/sta_iface" 2>/dev/null)

# Clean up old FORWARD rules (all variations)
while iptables -D FORWARD -i "$AP_IFACE" -j ACCEPT 2>/dev/null; do :; done
while iptables -D FORWARD -o "$AP_IFACE" -j ACCEPT 2>/dev/null; do :; done
while iptables -D FORWARD -i "$AP_IFACE" -o tun0 -j DROP 2>/dev/null; do :; done
for iface in wlan0 wlan1 rmnet_data0 rmnet_data1 rmnet_data2 rmnet_data3 rmnet_data4 rmnet_data5 rmnet_data6 rmnet_data7 rmnet_data8 rmnet_data9 rmnet_data10 eth0; do
    while iptables -D FORWARD -i "$AP_IFACE" -o "$iface" -j ACCEPT 2>/dev/null; do :; done
done
# Clean up stale grant ACCEPT rules (if AP restart without stop)
if [ -f "$STATE_DIR/vpn_grants" ]; then
    while IFS= read -r gip; do
        [ -n "$gip" ] && while iptables -D FORWARD -i "$AP_IFACE" -o tun0 -s "$gip" -j ACCEPT 2>/dev/null; do :; done
    done < "$STATE_DIR/vpn_grants"
fi

# Clean up old MASQUERADE rules
for iface in wlan0 wlan1 rmnet_data0 rmnet_data1 rmnet_data2 rmnet_data3 rmnet_data4 rmnet_data5 rmnet_data6 rmnet_data7 rmnet_data8 rmnet_data9 rmnet_data10 eth0; do
    while iptables -t nat -D POSTROUTING -s "${SUBNET}.0/24" -o "$iface" -j MASQUERADE 2>/dev/null; do :; done
done

# Clean up old DNS DNAT rules (old gateway + new DNS_SERVER)
for dns in $OLD_GW "$DNS_SERVER"; do
    [ -z "$dns" ] && continue
    while iptables -t nat -D PREROUTING -i "$AP_IFACE" -p udp --dport 53 -j DNAT --to-destination "$dns:53" 2>/dev/null; do :; done
    while iptables -t nat -D PREROUTING -i "$AP_IFACE" -p tcp --dport 53 -j DNAT --to-destination "$dns:53" 2>/dev/null; do :; done
done

# Clean up old DNS SNAT rules (from old version, if upgrading)
if [ -n "$OLD_GW" ] && [ -n "$OLD_IP" ]; then
    for iface in wlan0 wlan1 "$OLD_STA"; do
        [ -z "$iface" ] && continue
        while iptables -t nat -D POSTROUTING -d "$OLD_GW" -p udp --dport 53 -o "$iface" -j SNAT --to-source "$OLD_IP" 2>/dev/null; do :; done
        while iptables -t nat -D POSTROUTING -d "$OLD_GW" -p tcp --dport 53 -o "$iface" -j SNAT --to-source "$OLD_IP" 2>/dev/null; do :; done
    done
fi

# Clean up old DNS RETURN rules (from grants)
if [ -f "$STATE_DIR/vpn_grants" ]; then
    while IFS= read -r gip; do
        [ -n "$gip" ] && {
            iptables -t nat -D PREROUTING -i "$AP_IFACE" -s "$gip" -p udp --dport 53 -j RETURN 2>/dev/null
            iptables -t nat -D PREROUTING -i "$AP_IFACE" -s "$gip" -p tcp --dport 53 -j RETURN 2>/dev/null
        }
    done < "$STATE_DIR/vpn_grants"
fi

# Clean up old ip rules
ip rule del to "${SUBNET}.0/24" lookup main priority 4000 2>/dev/null
ip rule del from "${SUBNET}.0/24" lookup wlan0 priority 5000 2>/dev/null
for i in 0 1 2 3 4 5 6 7 8 9 10; do
    PRIO=$((5100 + i * 10))
    ip rule del from "${SUBNET}.0/24" lookup "rmnet_data$i" priority "$PRIO" 2>/dev/null
done
ip rule del from "${SUBNET}.0/24" unreachable priority 5200 2>/dev/null
# Clean up stale per-IP rules from old revoke_vpn.sh
if [ -f "$STATE_DIR/vpn_grants" ]; then
    while IFS= read -r gip; do
        [ -n "$gip" ] && ip rule del from "$gip" lookup wlan0 priority 5000 2>/dev/null
    done < "$STATE_DIR/vpn_grants"
fi

# ─── Detect upstream interfaces ───
# WiFi upstream: always add (table registered when WiFi is enabled)
# LTE upstreams: scan all rmnet_dataN (0-10) — only add if table is registered
#   Table name is registered by Android when interface is first activated
#   At AP start, some tables might not exist yet → upstream_monitor.sh handles them
UPSTREAM_IFACES=""

# WiFi upstream (preferred, priority 5000)
if ip link show wlan0 2>/dev/null | grep -q "state"; then
    UPSTREAM_IFACES="wlan0"
fi

# LTE upstreams — scan all rmnet_dataN, try to add ip rule
# If table name not registered yet, ip rule add fails silently → monitor will handle later
for i in 0 1 2 3 4 5 6 7 8 9 10; do
    iface="rmnet_data$i"
    if ip link show "$iface" 2>/dev/null | grep -q "state"; then
        UPSTREAM_IFACES="$UPSTREAM_IFACES $iface"
    fi
done
# Trim
UPSTREAM_IFACES=$(echo "$UPSTREAM_IFACES" | xargs)

# ─── Create AP interface ───
$IW phy "phy$PHY" interface add "$AP_IFACE" type __ap 2>/dev/null
if [ $? -ne 0 ]; then
    echo '{"ok":false,"error":"Cannot create AP interface (driver may not support concurrent interfaces)"}'
    exit 1
fi

sleep 1

# Bring up interface
ip link set "$AP_IFACE" up

# ─── Determine hw_mode and channel ───
if [ "$CHANNEL" = "0" ]; then
    if [ -n "$STA_IFACE" ]; then
        # SCC: match STA's current band
        STA_FREQ=$($IW dev "$STA_IFACE" link 2>/dev/null | grep freq | awk '{print $2}')
        if [ -n "$STA_FREQ" ] && [ "$STA_FREQ" -gt 4000 ]; then
            HW_MODE="a"
        else
            HW_MODE="g"
        fi
    else
        # No STA (LTE-only mode) — channel=0 may not work, default to ch 6
        HW_MODE="g"
        CHANNEL=6
    fi
elif [ "$CHANNEL" -gt 14 ] 2>/dev/null; then
    HW_MODE="a"
else
    HW_MODE="g"
fi

# ─── Compute VHT lines for 5GHz ───
VHT_LINES=""
if [ "$HW_MODE" = "a" ]; then
    VHT_LINES="ieee80211ac=1
vht_oper_chwidth=0"
fi

# ─── Generate hostapd config in /data/local/tmp (SELinux-safe) ───
HOSTAPD_CONF="/data/local/tmp/vpn-tether-hostapd.conf"
cat > "$HOSTAPD_CONF" << EOF
interface=$AP_IFACE
ssid=$SSID
hw_mode=$HW_MODE
channel=$CHANNEL
wpa=2
wpa_passphrase=$PASS
wpa_key_mgmt=WPA-PSK
rsn_pairwise=CCMP
$VHT_LINES
EOF
chmod 644 "$HOSTAPD_CONF"

# ─── Start hostapd ───
$HOSTAPD -B "$HOSTAPD_CONF" 2>/dev/null
if [ $? -ne 0 ]; then
    echo '{"ok":false,"error":"hostapd failed to start"}'
    ip link set "$AP_IFACE" down 2>/dev/null
    $IW dev "$AP_IFACE" del 2>/dev/null
    exit 1
fi

sleep 2

# Set IP address on AP interface
ip addr add "${AP_IP}/24" dev "$AP_IFACE" 2>/dev/null

# ─── Generate udhcpd config ───
UDHCPD_CONF="/data/local/tmp/vpn-tether-udhcpd.conf"
cat > "$UDHCPD_CONF" << EOF
start $DHCP_START
end $DHCP_END
interface $AP_IFACE
opt dns $DNS_SERVER
opt router $AP_IP
opt subnet 255.255.255.0
lease_file $STATE_DIR/udhcpd.leases
pidfile $STATE_DIR/udhcpd.pid
EOF
chmod 644 "$UDHCPD_CONF"

# Start udhcpd via setsid
touch "$STATE_DIR/udhcpd.leases"
setsid $BUSYBOX udhcpd "$UDHCPD_CONF" >/dev/null 2>&1 &
sleep 1

# ─── Enable IP forwarding ───
echo 1 > /proc/sys/net/ipv4/ip_forward

# ─── Routing rules ───
# Return: traffic TO tethered subnet uses main table (has route to wlan_ap0)
ip rule add to "${SUBNET}.0/24" lookup main priority 4000 2>/dev/null

# Outbound: tethered traffic uses upstream tables with fallthrough
# WiFi at priority 5000 (preferred)
# LTE rmnet_dataN at priority 5100 + N*10 (e.g., rmnet_data0=5100, rmnet_data2=5120)
# When a table has no default route → rule fails → falls to next
# When all upstream rules fail → falls to 5200 (unreachable, prevents VPN leak)
for iface in $UPSTREAM_IFACES; do
    if [ "$iface" = "wlan0" ]; then
        PRIO=5000
    else
        # Extract N from rmnet_dataN
        N=$(echo "$iface" | sed 's/rmnet_data//')
        PRIO=$((5100 + N * 10))
    fi
    ip rule add from "${SUBNET}.0/24" lookup "$iface" priority "$PRIO" 2>/dev/null || {
        ip rule del from "${SUBNET}.0/24" lookup "$iface" priority "$PRIO" 2>/dev/null
        ip rule add from "${SUBNET}.0/24" lookup "$iface" priority "$PRIO" 2>/dev/null
    }
done

# Unreachable: if no upstream has a default route, drop (prevents VPN leak via legacy tables)
ip rule add from "${SUBNET}.0/24" unreachable priority 5200 2>/dev/null

# ─── iptables FORWARD chain ───
# Order (top to bottom):
# 1. ACCEPT for granted IPs → tun0 (from grant_vpn.sh, inserted later)
# 2. DROP wlan_ap0 → tun0 (block VPN by default for non-granted)
# 3. ACCEPT wlan_ap0 → wlan0 (WiFi direct internet)
# 4. ACCEPT wlan_ap0 → rmnet_data0 (LTE direct internet)
# 5. ACCEPT * → wlan_ap0 (return traffic to tethered devices)
# Insert in reverse so final order is correct:

# 5. Return traffic (inserted first, ends up last)
iptables -I FORWARD 1 -o "$AP_IFACE" -j ACCEPT

# 4+3. ACCEPT for each upstream (reverse order so first upstream is higher)
for iface in $(echo "$UPSTREAM_IFACES" | tr ' ' '\n' | tac | tr '\n' ' '); do
    iptables -I FORWARD 1 -i "$AP_IFACE" -o "$iface" -j ACCEPT
done

# 2. DROP to tun0 (inserted last, ends up first — before all ACCEPTs)
iptables -I FORWARD 1 -i "$AP_IFACE" -o tun0 -j DROP

# ─── NAT: MASQUERADE on all upstream interfaces ───
for iface in $UPSTREAM_IFACES; do
    iptables -t nat -A POSTROUTING -s "${SUBNET}.0/24" -o "$iface" -j MASQUERADE
done

# ─── DNS: DNAT all DNS queries to 77.88.8.8 (Yandex, works on all upstreams) ───
# This catches devices that hardcode 8.8.8.8/1.1.1.1 (blocked in RU whitelist mode)
# MASQUERADE on the upstream interface handles source translation
iptables -t nat -I PREROUTING -i "$AP_IFACE" -p udp --dport 53 -j DNAT --to-destination "$DNS_SERVER:53"
iptables -t nat -I PREROUTING -i "$AP_IFACE" -p tcp --dport 53 -j DNAT --to-destination "$DNS_SERVER:53"

# ─── Save state ───
touch "$STATE_DIR/ap_running"
echo "$UPSTREAM_IFACES" > "$STATE_DIR/upstream_ifaces"
echo "$STA_IFACE" > "$STATE_DIR/sta_iface"
# Clean up old state files that are no longer used
rm -f "$STATE_DIR/upstream_gw" "$STATE_DIR/upstream_ip" 2>/dev/null

# ─── Restore VPN grants from state file ───
if [ -f "$STATE_DIR/vpn_grants" ] && [ -s "$STATE_DIR/vpn_grants" ]; then
    while IFS= read -r gip; do
        [ -n "$gip" ] && sh "$MODDIR/scripts/grant_vpn.sh" "$gip" >/dev/null 2>&1
    done < "$STATE_DIR/vpn_grants"
fi

# ─── Start upstream monitor (detects new LTE interfaces dynamically) ───
# Monitor scans every 5s for rmnet_dataN tables that gain a default route
# and adds ip rule + MASQUERADE + FORWARD ACCEPT for them
# Killed by stop_ap.sh (when ap_running file is removed)
setsid sh "$MODDIR/scripts/upstream_monitor.sh" >/dev/null 2>&1 &

echo "{\"ok\":true,\"ssid\":\"$SSID\",\"ip\":\"$AP_IP\",\"iface\":\"$AP_IFACE\",\"upstreams\":\"$UPSTREAM_IFACES\",\"dns\":\"$DNS_SERVER\"}"
