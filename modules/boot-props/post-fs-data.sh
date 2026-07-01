#!/system/bin/sh
# boot-props: Persistently set bootloader status props for Play Integrity
#
# Root cause: OnePlus 7 Pro (GM1910, OOS 11) bootloader does not pass
# androidboot.flash.locked or androidboot.verifiedbootstate in kernel cmdline.
# Only androidboot.vbmeta.device_state=unlocked is present.
#
# IntegrityBox (playintegrityfix) v37 tries to set these via resetprop_if_diff,
# but that function has a bug:
#
#   [ -z "$CURRENT" ] || [ "$CURRENT" = "$EXPECTED" ] || $RESETPROP "$NAME" "$EXPECTED"
#
# When CURRENT is empty (prop doesn't exist), the first clause is true,
# the entire || chain short-circuits, and the prop is NEVER set.
#
# This module runs in post-fs-data (before playintegrityfix's service.sh),
# creating the props with resetprop -n so they exist by the time
# playintegrityfix runs. From that point, resetprop_if_diff sees non-empty
# CURRENT and works correctly.
#
# Props set:
#   ro.boot.verifiedbootstate    = green   (verified boot, locked)
#   ro.boot.flash.locked         = 1       (bootloader locked)
#   ro.boot.vbmeta.device_state  = locked  (vbmeta locked)
#   vendor.boot.verifiedbootstate = green
#   vendor.boot.vbmeta.device_state = locked
#
# These are required for Play Integrity DEVICE pass.
# Without them, Google Play Services sees an unlocked bootloader.

MODDIR="${0%/*}"

# Wait for property service to be ready
while [ "$(getprop ro.crypto.state)" != "encrypted" ] && [ "$(getprop ro.crypto.state)" != "unsupported" ]; do
    sleep 1
done

# Force-set all bootloader status props with resetprop -n
# -n allows setting props that don't exist yet
resetprop -n ro.boot.verifiedbootstate green
resetprop -n ro.boot.flash.locked 1
resetprop -n ro.boot.vbmeta.device_state locked
resetprop -n vendor.boot.verifiedbootstate green
resetprop -n vendor.boot.vbmeta.device_state locked

# Also set OEM unlock to 0 (required for integrity)
resetprop -n sys.oem_unlock_allowed 0
resetprop -n ro.oem_unlock_supported 0

# Log
echo "[boot-props] Props set: verifiedbootstate=green, flash.locked=1, vbmeta.device_state=locked" > /data/local/tmp/boot-props.log
