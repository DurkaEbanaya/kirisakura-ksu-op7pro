2026-07-01 23:40:21.857 adb[91909:687846] [CornerFix] constructor loaded process=adb bundle=(none) lite=0
#!/system/bin/sh
# meta-kirisakura: Log mount status after boot for debugging

MODDIR="${0%/*}"
echo "[meta-kirisakura] Post-boot mount status:"
cat /proc/mounts | grep KSU 2>/dev/null || echo "[meta-kirisakura] No KSU mounts found"
