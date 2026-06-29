#!/system/bin/sh
#
# VPN Tether - start_ap.sh
# Start concurrent WiFi AP on a separate interface while STA stays connected
# Driver's policy manager chooses channel automatically (SCC with STA)
#
# Key fixes discovered during testing:
# 1. channel=0 + hw_mode=g — driver picks SCC channel with STA (fixed channel fails)
# 2. hostapd config in /data/local/tmp — SELinux blocks /data/adb
# 3. udhcpd via setsid — background mode needed for busybox
# 4. DNS DNAT+SNAT — provider DNS, not 8.8.8.8 (blocked in whitelist mode)
# 5. Return routing rule — Android tables lack route to tethered subnet
# 6. Auto-detect: iw, hostapd, busybox, WiFi interface, upstream gateway
#

MODDIR=/data/adb/modules/vpn-tether
STATE_DIR="$MODDIR/state"
CONF_DIR="$MODDIR/conf"

# Load config
SSID="VPN Tether"
PASS="vpn12345"
CHANNEL=0
SUBNET=192.168.204
if [ -f "$CONF_DIR/ap_config" ]; then
    . "$CONF_DIR/ap_config"
fi

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
    # Try busybox iw
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

# ─── Auto-detect WiFi STA interface ───
STA_IFACE=""
for iface in wlan0 wlan1 eth0; do
    TYPE=$($IW dev "$iface" info 2>/dev/null | grep "type " | awk '{print $2}' | tr 'A-Z' 'a-z')
    if [ "$TYPE" = "managed" ]; then
        STA_IFACE="$iface"
        break
    fi
done
if [ -z "$STA_IFACE" ]; then
    echo '{"ok":false,"error":"No WiFi STA interface found. Connect to WiFi first."}'
    exit 1
fi

# ─── Detect upstream gateway and IP ───
UPSTREAM_IP=$($IW dev "$STA_IFACE" info 2>/dev/null | grep wiphy | awk '{print $2}')
UPSTREAM_GW=$(ip route show table "$STA_IFACE" 2>/dev/null | grep default | awk '{print $3}')
if [ -z "$UPSTREAM_GW" ]; then
    UPSTREAM_GW=$(ip route show 2>/dev/null | grep default | grep "$STA_IFACE" | awk '{print $3}' | head -1)
fi
STA_IP=$(ip addr show "$STA_IFACE" 2>/dev/null | grep 'inet ' | awk '{print $2}' | cut -d/ -f1)
if [ -z "$UPSTREAM_GW" ] || [ -z "$STA_IP" ]; then
    echo '{"ok":false,"error":"Cannot detect upstream gateway"}'
    exit 1
fi

# ─── Check if already running ───
if [ -f "$STATE_DIR/ap_running" ]; then
    echo '{"ok":false,"error":"AP already running"}'
    exit 1
fi

# ─── Detect phy ───
PHY=$($IW dev "$STA_IFACE" info 2>/dev/null | grep "wiphy" | awk '{print $2}')
if [ -z "$PHY" ]; then
    echo '{"ok":false,"error":"Cannot detect WiFi phy"}'
    exit 1
fi

# ─── Check concurrent AP support ───
if ! $IW phy "phy$PHY" info 2>/dev/null | grep -q "AP"; then
    echo '{"ok":false,"error":"WiFi chip does not support AP mode"}'
    exit 1
fi

# ─── Create AP interface ───
$IW phy "phy$PHY" interface add "$AP_IFACE" type __ap 2>/dev/null
if [ $? -ne 0 ]; then
    echo '{"ok":false,"error":"Cannot create AP interface (driver may not support concurrent STA+AP)"}'
    exit 1
fi

sleep 1

# Bring up interface
ip link set "$AP_IFACE" up

# ─── Generate hostapd config in /data/local/tmp (SELinux-safe) ───
HOSTAPD_CONF="/data/local/tmp/vpn-tether-hostapd.conf"
cat > "$HOSTAPD_CONF" << EOF
interface=$AP_IFACE
ssid=$SSID
hw_mode=g
channel=0
wpa=2
wpa_passphrase=$PASS
wpa_key_mgmt=WPA-PSK
rsn_pairwise=CCMP
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

# ─── Generate udhcpd config with provider DNS ───
UDHCPD_CONF="/data/local/tmp/vpn-tether-udhcpd.conf"
cat > "$UDHCPD_CONF" << EOF
start $DHCP_START
end $DHCP_END
interface $AP_IFACE
opt dns $UPSTREAM_GW 77.88.8.8
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
# Outbound: tethered traffic uses STA table (direct internet, not VPN)
ip rule add from "${SUBNET}.0/24" lookup "$STA_IFACE" priority 5000 2>/dev/null

# Return: traffic TO tethered subnet uses main table
ip rule add to "${SUBNET}.0/24" lookup main priority 4000 2>/dev/null

# ─── iptables ───
# FORWARD: allow traffic to/from AP interface
iptables -I FORWARD 1 -i "$AP_IFACE" -j ACCEPT
iptables -I FORWARD 1 -o "$AP_IFACE" -j ACCEPT

# NAT: default (no VPN) -> masquerade on STA interface
iptables -t nat -A POSTROUTING -s "${SUBNET}.0/24" -o "$STA_IFACE" -j MASQUERADE

# DNS fix: DNAT all DNS queries from tethered devices to provider DNS
iptables -t nat -I PREROUTING -i "$AP_IFACE" -p udp --dport 53 -j DNAT --to-destination "$UPSTREAM_GW:53"
iptables -t nat -I PREROUTING -i "$AP_IFACE" -p tcp --dport 53 -j DNAT --to-destination "$UPSTREAM_GW:53"

# SNAT for DNAT'd DNS
iptables -t nat -I POSTROUTING 1 -d "$UPSTREAM_GW" -p udp --dport 53 -o "$STA_IFACE" -j SNAT --to-source "$STA_IP"
iptables -t nat -I POSTROUTING 1 -d "$UPSTREAM_GW" -p tcp --dport 53 -o "$STA_IFACE" -j SNAT --to-source "$STA_IP"

# ─── Save state ───
touch "$STATE_DIR/ap_running"
echo "$UPSTREAM_GW" > "$STATE_DIR/upstream_gw"
echo "$STA_IP" > "$STATE_DIR/upstream_ip"
echo "$STA_IFACE" > "$STATE_DIR/sta_iface"

echo "{\"ok\":true,\"ssid\":\"$SSID\",\"ip\":\"$AP_IP\",\"iface\":\"$AP_IFACE\",\"sta\":\"$STA_IFACE\",\"gw\":\"$UPSTREAM_GW\"}"
