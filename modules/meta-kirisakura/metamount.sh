2026-07-01 23:40:21.524 adb[91910:687821] [CornerFix] constructor loaded process=adb bundle=(none) lite=0
#!/system/bin/sh
# meta-kirisakura: Shell-based OverlayFS metamodule for KernelSU Next
#
# Designed for OnePlus 7 Pro (kernel 4.14.243) where:
#   - fsopen() API is unavailable (ENOSYS) — Rust binary meta-overlayfs fails
#   - Vendor overlays exist: /system/india/app -> /system/product/app, etc.
#
# This script mounts overlayfs for all enabled KSU modules with system/ dirs.
# It reads system/ directly from /data/adb/modules/<id>/system/ (no ext4 image).
#
# Key design decisions:
#   - Uses `mount -t overlay` shell command (works on 4.14, unlike fsopen)
#   - Sets SELinux context=u:object_r:system_file:s0 (critical — without it,
#     overlay files get wrong labels and /system/bin/sh becomes inaccessible)
#   - Resolves vendor overlay lowerdirs: if a module targets /system/india/app,
#     the overlay is mounted on /system/product/app (the vendor overlay's
#     mount point), stacking on top of the existing vendor overlay
#   - Walks up directory tree to find the shallowest existing path or
#     vendor-overlay lowerdir, so deep module paths (e.g. system/india/app/
#     YouTube/) correctly resolve to the overlay mount point
#   - Mount source is always "KSU" (required for kernel umount)

MODDIR="${0%/*}"
MODULE_DIR="${MODULE_DIR:-/data/adb/modules}"
TMPDIR="${TMPDIR:-/data/local/tmp}"

log() { echo "[meta-kirisakura] $*"; }

log "Starting module mount process"
log "MODULE_DIR=$MODULE_DIR"

# -------------------------------------------------------------------
# Build vendor overlay map from /proc/mounts
# Format: "lowerdir_path  mount_point" per line
# e.g., "/system/india/app  /system/product/app"
# -------------------------------------------------------------------
OVERLAY_MAP="$TMPDIR/meta-kirisakura-omap"
: > "$OVERLAY_MAP"

while IFS=' ' read -r _ mp _ opts _; do
    case "$opts" in
        *lowerdir=*)
            lds=$(echo "$opts" | tr ',' '\n' | grep '^lowerdir=' | cut -d= -f2-)
            oldifs="$IFS"
            IFS=':'
            for d in $lds; do
                [ -n "$d" ] && echo "$d $mp" >> "$OVERLAY_MAP"
            done
            IFS="$oldifs"
            ;;
    esac
done < /proc/mounts

log "Vendor overlay map:"
while read -r d m; do
    log "  $d -> $m"
done < "$OVERLAY_MAP"

# Check if a path is a lowerdir of a vendor overlay.
# Returns the overlay mount point on stdout if found, empty otherwise.
lookup_overlay() {
    local path="$1"
    while read -r dir mnt; do
        if [ "$dir" = "$path" ]; then
            echo "$mnt"
            return 0
        fi
    done < "$OVERLAY_MAP"
    return 1
}

# -------------------------------------------------------------------
# For a module file, find the correct mount point by walking up the
# directory tree until we find either:
#   1. A path that is a vendor overlay lowerdir → mount on the overlay's
#      mount point, with the module's corresponding directory as lowerdir
#   2. An existing path on the filesystem → mount on that path directly
#
# Outputs: "mount_target  mod_dir" (space-separated)
# -------------------------------------------------------------------
find_mount_point() {
    local sys_path="$1"  # e.g., /system/india/app/YouTube
    local mod_dir="$2"   # e.g., /data/adb/modules/rvt-replace/system/india/app/YouTube

    while [ "$sys_path" != "/" ] && [ -n "$sys_path" ]; do
        # Check vendor overlay map
        overlay_mnt=$(lookup_overlay "$sys_path")
        if [ -n "$overlay_mnt" ]; then
            echo "$overlay_mnt $mod_dir"
            return 0
        fi
        # Check if path exists on filesystem
        if [ -e "$sys_path" ]; then
            echo "$sys_path $mod_dir"
            return 0
        fi
        # Walk up one level
        sys_path=$(dirname "$sys_path")
        mod_dir=$(dirname "$mod_dir")
    done
    return 1
}

# -------------------------------------------------------------------
# Collect mount operations from all enabled modules
# Format: "mount_target  mod_dir" per line
# -------------------------------------------------------------------
OPS="$TMPDIR/meta-kirisakura-ops"
: > "$OPS"

for module in "$MODULE_DIR"/*; do
    [ -d "$module" ] || continue
    [ -f "$module/disable" ] && continue
    [ -f "$module/skip_mount" ] && continue
    [ -d "$module/system" ] || continue

    mod_id=$(basename "$module")
    log "Processing module: $mod_id"

    # Find all files under system/ and resolve their mount points
    find "$module/system" -type f 2>/dev/null | while read -r f; do
        fdir=$(dirname "$f")
        # Compute the system path: module/system/X → /system/X
        rel="${fdir#"$module/system"}"
        sys_path="/system${rel}"

        # Walk up to find the mount point
        result=$(find_mount_point "$sys_path" "$fdir")
        if [ -n "$result" ]; then
            echo "$result" >> "$OPS"
        else
            log "  could not resolve mount point for $sys_path"
        fi
    done
done

# -------------------------------------------------------------------
# Group by mount_target (merge multiple modules targeting same path)
# and mount overlayfs for each unique target
# -------------------------------------------------------------------
SORTED_OPS="$TMPDIR/meta-kirisakura-sorted"
sort -u "$OPS" > "$SORTED_OPS"

# Use awk to group: output "target  dir1:dir2:..."
awk '
{
    if ($1 != prev && prev != "") {
        print prev, dirs
        dirs = ""
    }
    if (dirs == "") {
        dirs = $2
    } else {
        dirs = dirs ":" $2
    }
    prev = $1
}
END {
    if (prev != "") print prev, dirs
}
' "$SORTED_OPS" | while read -r target mod_dirs; do
    [ -e "$target" ] || continue

    # lowerdir = module_dirs : original_target
    # Module dirs take priority (listed first in lowerdir = top layer)
    lowerdir_arg="${mod_dirs}:${target}"

    # Mount overlay with SELinux context
    # context=u:object_r:system_file:s0 is critical — without it,
    # overlay files inherit wrong labels and break system_server
    mount -t overlay KSU \
        -o "ro,context=u:object_r:system_file:s0,lowerdir=${lowerdir_arg}" \
        "$target" 2>/dev/null

    rc=$?
    if [ $rc -eq 0 ]; then
        log "mounted overlay on $target (layers: $(echo "$mod_dirs" | tr ':' ' ' | wc -w) module + 1 system)"
    else
        log "FAILED to mount overlay on $target (rc=$rc), trying without context..."
        mount -t overlay KSU \
            -o "ro,lowerdir=${lowerdir_arg}" \
            "$target" 2>/dev/null
        rc=$?
        if [ $rc -eq 0 ]; then
            log "mounted overlay on $target (no context, fallback)"
        else
            log "FAILED to mount overlay on $target (rc=$rc, no fallback)"
        fi
    fi
done

# Cleanup temp files
rm -f "$OVERLAY_MAP" "$OPS" "$SORTED_OPS"

log "Mount completed successfully"
exit 0
