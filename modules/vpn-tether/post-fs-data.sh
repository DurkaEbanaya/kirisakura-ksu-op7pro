#!/system/bin/sh
#
# VPN Tether - post-fs-data.sh
# Create directories and default config on boot
#

MODDIR=/data/adb/modules/vpn-tether
STATE_DIR="$MODDIR/state"
CONF_DIR="$MODDIR/conf"

mkdir -p "$STATE_DIR" "$CONF_DIR"

# Default AP config
if [ ! -f "$CONF_DIR/ap_config" ]; then
    cat > "$CONF_DIR/ap_config" << 'EOF'
SSID="OnePlus 7 Pro VPN"
PASS="vpn12345"
CHANNEL="0"
SUBNET="192.168.204"
EOF
fi

# VPN grants file
touch "$STATE_DIR/vpn_grants"

# Touch state files
touch "$STATE_DIR/ap_running"

# Remove stale state
rm -f "$STATE_DIR/ap_running" "$STATE_DIR/hostapd.pid" "$STATE_DIR/udhcpd.pid" "$STATE_DIR/udhcpd.leases"

# Set permissions
chmod 755 "$MODDIR/scripts"/*.sh
chmod 755 "$MODDIR/service.sh" "$MODDIR/post-fs-data.sh"
