#!/system/bin/sh
# post-fs-data.sh — load IPv6 NAT modules + pre-create iptables chains BEFORE netd starts
#
# Two problems solved:
# 1. CONFIG_NF_NAT_IPV6=m (module) — load before netd so ip6tables-restore finds nat table
# 2. Android 11 netd IptablesRestoreController sends "-nvx -L tetherctrl_counters" via
#    iptables-restore pipe. If tetherctrl_counters chain doesn't exist, iptables-restore
#    exits with error and DIES. Netd doesn't restart it → all subsequent iptables ops
#    fail with EREMOTEIO → hotspot/tethering NAT setup fails.
#    Fix: pre-create tetherctrl chains so the -L command succeeds.

MODDIR="/data/adb/modules/ipv6nat"

# --- Load IPv6 NAT modules (dependency order) ---
insmod "$MODDIR/modules/nf_nat_ipv6.ko"
insmod "$MODDIR/modules/nf_nat_masquerade_ipv6.ko"
insmod "$MODDIR/modules/ip6table_nat.ko"
insmod "$MODDIR/modules/ip6t_MASQUERADE.ko"

# --- Pre-create tetherctrl iptables chains (both IPv4 and IPv6) ---
# These must exist before netd starts, otherwise IptablesRestoreController
# kills the iptables-restore/ip6tables-restore process when it tries to list
# a non-existent chain via "-nvx -L tetherctrl_counters" sent through the
# restore pipe. iptables-restore doesn't understand -L syntax and exits(1),
# netd doesn't restart it → all subsequent iptables ops fail with EREMOTEIO.
for BIN in iptables ip6tables; do
    $BIN -N tetherctrl_counters 2>/dev/null
    $BIN -N tetherctrl_FORWARD 2>/dev/null
    $BIN -t nat -N tetherctrl_nat_POSTROUTING 2>/dev/null

    # Hook tetherctrl_FORWARD into FORWARD chain (idempotent)
    $BIN -C FORWARD -j tetherctrl_FORWARD 2>/dev/null || $BIN -A FORWARD -j tetherctrl_FORWARD
    # Hook tetherctrl_nat_POSTROUTING into POSTROUTING (idempotent)
    $BIN -t nat -C POSTROUTING -j tetherctrl_nat_POSTROUTING 2>/dev/null || $BIN -t nat -A POSTROUTING -j tetherctrl_nat_POSTROUTING
done

# --- Verify ---
STATUS="ok"
if ! grep -q nat /proc/net/ip6_tables_names 2>/dev/null; then
    STATUS="ip6tables nat table missing"
fi
if ! iptables -L tetherctrl_counters >/dev/null 2>&1; then
    STATUS="$STATUS; tetherctrl_counters missing"
fi

echo "ipv6nat: $STATUS" > /data/adb/modules/ipv6nat/status
