2026-07-01 23:40:21.749 adb[91913:687842] [CornerFix] constructor loaded process=adb bundle=(none) lite=0
#!/system/bin/sh
# meta-kirisakura: Cleanup hook for module uninstall
# Called when a regular module is uninstalled (MODULE_ID env var set)

MODULE_ID="${MODULE_ID:-}"
MODDIR="${0%/*}"

echo "[meta-kirisakura] metauninstall called for module: $MODULE_ID"
# Nothing to clean — overlays are temporary (cleared on reboot)
exit 0
