#!/system/bin/sh
# 轻量状态：全程用 shell 内建 read 读文件，避免 fork
# 目标 <100ms，给 10 秒轮询用；batt-health 结果缓存 120s

MODDIR=${MODDIR:-/data/adb/modules/star_fluency}
SF=/data/adb/star-fluency
CPU=/sys/devices/system/cpu/cpufreq
B=/sys/class/power_supply/battery

# ---- 内存：一次 awk ----
awk '/^MemTotal:/{t=$2} /^MemAvailable:/{a=$2} END{print "MEM_T="t" MEM_A="a}' /proc/meminfo > /tmp/.sfm 2>/dev/null
. /tmp/.sfm 2>/dev/null
[ -z "$MEM_T" ] && MEM_T=0
[ -z "$MEM_A" ] && MEM_A=0

# ---- 负载：内建 read ----
read -r L1 L2 L3 _rest < /proc/loadavg 2>/dev/null

# ---- 频率 / 温度：内建 read ----
read -r F0 < $CPU/policy0/scaling_cur_freq 2>/dev/null
read -r F4 < $CPU/policy4/scaling_cur_freq 2>/dev/null
read -r F7 < $CPU/policy7/scaling_cur_freq 2>/dev/null
read -r CPUT < /sys/class/thermal/thermal_zone0/temp 2>/dev/null
[ -z "$CPUT" ] && CPUT=0
CPUT=$((CPUT / 1000))

# ---- 电池 ----
read -r SOC < $B/capacity 2>/dev/null
read -r BT < $B/temp 2>/dev/null
read -r BI < $B/current_now 2>/dev/null
read -r BP < $B/power_now 2>/dev/null
read -r BST < $B/status 2>/dev/null
[ -z "$BT" ] && BT=0; BT=$((BT / 10))
[ -z "$BI" ] && BI=0
[ -z "$BP" ] && BP=0

# ---- 健康度：缓存 120 秒 ----
HC=$SF/battery/health.cache
BH=""
if [ -s "$HC" ]; then
    MT=$(stat -c %Y "$HC" 2>/dev/null)
    NOW=$(date +%s)
    [ -n "$MT" ] && [ $((NOW - MT)) -le 120 ] && BH=$(cat "$HC" 2>/dev/null)
fi
if [ -z "$BH" ]; then
    BH=$(sh "$MODDIR/scripts/batt-health.sh" 2>/dev/null)
    mkdir -p "$SF/battery" 2>/dev/null
    printf '%s\n' "$BH" > "$HC" 2>/dev/null
fi

BH_H=""; BH_SRC=""; BH_MEAS=""; BH_SEGS=""; BH_SYS=""; BH_DES=""; BH_CYC=""; BH_IR=""; BH_IRTR=""
while IFS='=' read -r k v; do
    case "$k" in
        health) BH_H=$v ;;
        health_src) BH_SRC=$v ;;
        meas_mah) BH_MEAS=$v ;;
        segs) BH_SEGS=$v ;;
        sys_mah) BH_SYS=$v ;;
        design_mah) BH_DES=$v ;;
        cycles) BH_CYC=$v ;;
        ir_mohm) BH_IR=$v ;;
        ir_trend) BH_IRTR=$v ;;
    esac
done <<EOF
$BH
EOF

[ -z "$BH_H" ] && BH_H=0
[ -z "$BH_SRC" ] && BH_SRC=system
[ -z "$BH_MEAS" ] && BH_MEAS=0
[ -z "$BH_SEGS" ] && BH_SEGS=0
[ -z "$BH_SYS" ] && BH_SYS=0
[ -z "$BH_DES" ] && BH_DES=0
[ -z "$BH_CYC" ] && BH_CYC=0
[ -z "$BH_IR" ] && BH_IR=0
[ -z "$BH_IRTR" ] && BH_IRTR=0

printf '{"mem":{"total":%s,"avail":%s},"load":"%s %s %s","cpu":{"f0":%s,"f4":%s,"f7":%s,"temp":%s},"bat":{"soc":%s,"health":%s,"src":"%s","mah":%s,"design":%s,"cycles":%s,"meas":%s,"segs":%s,"temp":%s,"cur":%s,"pwr":%s,"status":"%s","ir":%s,"irtr":%s}}\n' \
    "$MEM_T" "$MEM_A" "$L1" "$L2" "$L3" \
    "${F0:-0}" "${F4:-0}" "${F7:-0}" "$CPUT" \
    "${SOC:-0}" "$BH_H" "$BH_SRC" "$BH_SYS" "$BH_DES" "$BH_CYC" "$BH_MEAS" "$BH_SEGS" "$BT" "$BI" "$BP" "$BST" "$BH_IR" "$BH_IRTR"
