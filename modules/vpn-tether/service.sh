#!/system/bin/sh
#
# VPN Tether - service.sh
# Restore VPN grants after reboot
#

MODDIR=/data/adb/modules/vpn-tether
STATE_DIR="$MODDIR/state"
SCRIPTS="$MODDIR/scripts"

# Wait for boot
until [ "$(getprop sys.boot_completed)" = "1" ]; do
    sleep 2
done
sleep 15

# Restore VPN grants
if [ -f "$STATE_DIR/vpn_grants" ]; then
    while IFS= read -r ip; do
        [ -n "$ip" ] && sh "$SCRIPTS/grant_vpn.sh" "$ip" >/dev/null 2>&1
    done < "$STATE_DIR/vpn_grants"
fi

