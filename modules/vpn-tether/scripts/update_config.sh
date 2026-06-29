#!/system/bin/sh
#
# VPN Tether - update_config.sh
# Update AP configuration (SSID, password, channel)
#

MODDIR=/data/adb/modules/vpn-tether
CONF_DIR="$MODDIR/conf"
STATE_DIR="$MODDIR/state"

SSID="$1"
PASS="$2"
CHANNEL="$3"

if [ -z "$SSID" ]; then
    echo '{"ok":false,"error":"SSID required"}'
    exit 1
fi

if [ ${#PASS} -lt 8 ]; then
    echo '{"ok":false,"error":"Password must be at least 8 characters"}'
    exit 1
fi

if [ -z "$CHANNEL" ]; then
    CHANNEL=6
fi

# Check if AP is running
if [ -f "$STATE_DIR/ap_running" ]; then
    echo '{"ok":false,"error":"Stop AP first to change config"}'
    exit 1
fi

# Write config
cat > "$CONF_DIR/ap_config" << EOF
SSID="$SSID"
PASS="$PASS"
CHANNEL="$CHANNEL"
SUBNET="192.168.204"
EOF

echo "{\"ok\":true,\"ssid\":\"$SSID\",\"channel\":\"$CHANNEL\"}"
