#!/system/bin/sh
#
# VPN Tether - list_devices.sh
# List all tethered devices across all tether interfaces (WiFi AP, USB, BT)
# Output JSON array
#

MODDIR=/data/adb/modules/vpn-tether
STATE_DIR="$MODDIR/state"
IW=/vendor/bin/iw

# Determine which tether interfaces are active
AP_IFACE=""
TETHER_IFACES=""

# Our concurrent AP
if [ -f "$STATE_DIR/ap_running" ] && ip link show wlan_ap0 2>/dev/null | grep -q "state UP"; then
    TETHER_IFACES="$TETHER_IFACES wlan_ap0"
    AP_IFACE="wlan_ap0"
fi

# Android WiFi hotspot (wlan0 in AP mode)
WLAN_TYPE=$($IW dev wlan0 info 2>/dev/null | grep "type " | awk '{print $2}')
if [ "$WLAN_TYPE" = "ap" ]; then
    TETHER_IFACES="$TETHER_IFACES wlan0"
fi

# USB tether
if ip link show rndis0 2>/dev/null | grep -q "state UP"; then
    TETHER_IFACES="$TETHER_IFACES rndis0"
fi

# BT tether
if ip link show bnep0 2>/dev/null | grep -q "state UP"; then
    TETHER_IFACES="$TETHER_IFACES bnep0"
fi

# Read VPN grants
VPN_GRANTED_IPS=""
if [ -f "$STATE_DIR/vpn_grants" ]; then
    VPN_GRANTED_IPS=$(cat "$STATE_DIR/vpn_grants")
fi

# Build JSON array
echo -n "["

FIRST=true

for IFACE in $TETHER_IFACES; do
    # Read ARP entries for this interface
    cat /proc/net/arp 2>/dev/null | grep "$IFACE" | while read -r arp_line; do
        DEV_IP=$(echo "$arp_line" | awk '{print $1}')
        DEV_MAC=$(echo "$arp_line" | awk '{print $4}')
        DEV_FLAGS=$(echo "$arp_line" | awk '{print $3}')

        # Skip empty MACs
        if [ "$DEV_MAC" = "00:00:00:00:00:00" ]; then
            continue
        fi

        # Determine tether type
        TETHER_TYPE="wifi"
        case "$IFACE" in
            wlan_ap0) TETHER_TYPE="wifi-ap" ;;
            wlan0) TETHER_TYPE="wifi-ap" ;;
            rndis0) TETHER_TYPE="usb" ;;
            bnep0) TETHER_TYPE="bt" ;;
        esac

        # Check VPN status
        VPN_GRANTED=false
        if echo "$VPN_GRANTED_IPS" | grep -qx "$DEV_IP"; then
            VPN_GRANTED=true
        fi

        # Determine device name from DHCP lease
        DEV_NAME="unknown"
        if [ -f "$STATE_DIR/udhcpd.leases" ]; then
            LEASE_NAME=$(grep "$DEV_IP" "$STATE_DIR/udhcpd.leases" 2>/dev/null | awk '{print $4}')
            if [ -n "$LEASE_NAME" ]; then
                DEV_NAME="$LEASE_NAME"
            fi
        fi

        # Output JSON object
        if [ "$FIRST" = true ]; then
            FIRST=false
        else
            echo -n ","
        fi

        echo -n "{\"ip\":\"$DEV_IP\",\"mac\":\"$DEV_MAC\",\"iface\":\"$IFACE\",\"type\":\"$TETHER_TYPE\",\"name\":\"$DEV_NAME\",\"vpn\":$VPN_GRANTED}"
    done
done

echo "]"
