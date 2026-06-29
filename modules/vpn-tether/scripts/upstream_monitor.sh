#!/system/bin/sh
#
# VPN Tether - upstream_monitor.sh
# Background process that detects new LTE upstream interfaces (rmnet_dataN)
# and adds routing/NAT/FORWARD rules for them dynamically.
#
# Why this is needed:
# - LTE interface number (rmnet_data0, rmnet_data2, etc.) depends on SIM/APN
# - The routing table for an interface is NOT registered until the interface
#   is activated by Android (gets an IP address)
# - At AP start time, the LTE table might not exist yet
# - This monitor scans every 5 seconds for new active LTE interfaces
#   and adds rules when they appear
#
# Started by start_ap.sh, killed by stop_ap.sh (when ap_running is removed)
#

MODDIR=/data/adb/modules/vpn-tether
STATE_DIR="$MODDIR/state"
CONF_DIR="$MODDIR/conf"
AP_IFACE="wlan_ap0"
SUBNET=192.168.204

# Load config
if [ -f "$CONF_DIR/ap_config" ]; then
    . "$CONF_DIR/ap_config"
fi

# Track which interfaces we've already configured (from state file + runtime)
CONFIGURED=""
# Load already-configured interfaces from state
if [ -f "$STATE_DIR/upstream_ifaces" ]; then
    CONFIGURED=$(cat "$STATE_DIR/upstream_ifaces")
fi

while [ -f "$STATE_DIR/ap_running" ]; do
    for i in 0 1 2 3 4 5 6 7 8 9 10; do
        iface="rmnet_data$i"

        # Skip if already configured
        echo "$CONFIGURED" | grep -qw "$iface" && continue

        # Check if this interface's routing table exists and has a default route
        # Table name is registered by Android when interface is activated
        if ip route show table "$iface" 2>/dev/null | grep -q "^default"; then
            # New active LTE upstream found!
            PRIO=$((5100 + i * 10))

            # Add ip rule for this upstream
            ip rule add from "${SUBNET}.0/24" lookup "$iface" priority "$PRIO" 2>/dev/null || {
                ip rule del from "${SUBNET}.0/24" lookup "$iface" priority "$PRIO" 2>/dev/null
                ip rule add from "${SUBNET}.0/24" lookup "$iface" priority "$PRIO" 2>/dev/null
            }

            # Add MASQUERADE on this interface
            iptables -t nat -C POSTROUTING -s "${SUBNET}.0/24" -o "$iface" -j MASQUERADE 2>/dev/null || \
                iptables -t nat -A POSTROUTING -s "${SUBNET}.0/24" -o "$iface" -j MASQUERADE

            # Add FORWARD ACCEPT (insert at position 2, after DROP wlan_ap0→tun0)
            iptables -C FORWARD -i "$AP_IFACE" -o "$iface" -j ACCEPT 2>/dev/null || \
                iptables -I FORWARD 2 -i "$AP_IFACE" -o "$iface" -j ACCEPT

            # Mark as configured
            CONFIGURED="$CONFIGURED $iface"
            echo "$CONFIGURED" | xargs > "$STATE_DIR/upstream_ifaces"
        fi
    done
    sleep 5
done
