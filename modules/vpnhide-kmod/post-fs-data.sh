#!/system/bin/sh
# Runs early in boot, before apps start. The vpnhide functionality is
# built into the kernel (CONFIG_VPNHIDE=y), so no insmod is needed.
# This script just records load_status for the app and verifies that
# /proc/vpnhide_targets exists (i.e., the built-in hooks are active).

MODDIR="${0%/*}"
MODULE_PROP="$MODDIR/module.prop"
STATUS_DIR="/data/adb/vpnhide_kmod"
STATUS_FILE="$STATUS_DIR/load_status"

mkdir -p "$STATUS_DIR"

BOOT_ID=$(cat /proc/sys/kernel/random/boot_id 2>/dev/null)
UNAME_R=$(uname -r 2>/dev/null)
NOW=$(date +%s 2>/dev/null)
KMOD_VERSION=$(grep '^version=' "$MODULE_PROP" 2>/dev/null | cut -d= -f2)

ROOT_MANAGER="unknown"
[ -d /data/adb/ksu ] && ROOT_MANAGER="kernelsu"
[ -d /data/adb/ap ] && ROOT_MANAGER="apatch"
[ -d /data/adb/magisk ] && ROOT_MANAGER="magisk"

# Check if vpnhide is built into the kernel
VPNHIDE_BUILTIN=0
if [ -e /proc/vpnhide_targets ]; then
    VPNHIDE_BUILTIN=1
fi

{
    printf 'timestamp=%s\n' "$NOW"
    printf 'boot_id=%s\n' "$BOOT_ID"
    printf 'uname_r=%s\n' "$UNAME_R"
    printf 'kmod_version=%s\n' "$KMOD_VERSION"
    printf 'root_manager=%s\n' "$ROOT_MANAGER"
    printf 'builtin=%s\n' "$VPNHIDE_BUILTIN"
    printf 'loaded=%s\n' "$VPNHIDE_BUILTIN"
    printf 'insmod_exit=0\n'
} > "$STATUS_FILE.tmp" && mv "$STATUS_FILE.tmp" "$STATUS_FILE"
chmod 0644 "$STATUS_FILE" 2>/dev/null

if [ "$VPNHIDE_BUILTIN" = "1" ]; then
    log -t vpnhide "vpnhide built-in active (kernel=$UNAME_R)"
    exit 0
else
    log -t vpnhide "vpnhide NOT active — /proc/vpnhide_targets missing (kernel without CONFIG_VPNHIDE?)"
    exit 1
fi
