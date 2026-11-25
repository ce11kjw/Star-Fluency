#!/system/bin/sh
# Star-Fluency 旁路能力探测（需要插着充电器）
# 逐个候选开关施加 25s，测电池净电流 / 适配器输入电流 / SOC 变化，然后立刻还原
# 判定：适配器有输入 且 电池电流≈0 且 SOC 不降 → 真旁路
#      适配器无输入 且 电池放电            → 假旁路（纯靠电池）
#      电池仍在充电                        → 该开关无效

B=/sys/class/power_supply/battery
Q=/sys/class/qcom-battery
U=/sys/class/power_supply/usb
LOG=/data/adb/star-fluency/bypass-probe.log
: > "$LOG"

log() { echo "$*" | tee -a "$LOG"; }

avg() {  # 采样 5 次取均值（每 4 秒一次）
    n=0; si=0; sv=0; sb=0
    while [ $n -lt 5 ]; do
        i=$(cat $B/current_now 2>/dev/null); [ -z "$i" ] && i=0
        v=$(cat $B/voltage_now 2>/dev/null); [ -z "$v" ] && v=0
        b=$(cat $Q/bq2597x_bus_current 2>/dev/null); [ -z "$b" ] && b=0
        si=$((si + i)); sv=$((sv + v)); sb=$((sb + b))
        n=$((n + 1))
        [ $n -lt 5 ] && sleep 4
    done
    echo "$((si / 5)) $((sv / 5)) $((sb / 5))"
}

probe() {
    NAME="$1"; TARGET="$2"; VAL="$3"
    SOC0=$(cat $B/capacity 2>/dev/null)
    echo "$VAL" > "$TARGET" 2>/dev/null
    OK=$?
    set -- $(avg)
    I=$1; V=$2; BUS=$3
    SOC1=$(cat $B/capacity 2>/dev/null)
    ST=$(cat $B/status 2>/dev/null)
    # 还原
    case "$TARGET" in
      */input_suspend|*/restrict_chg) echo 0 > "$TARGET" 2>/dev/null ;;
      */charge_control_limit) echo 0 > "$TARGET" 2>/dev/null ;;
      */constant_charge_current) echo 6370000 > "$TARGET" 2>/dev/null ;;
    esac
    sleep 8
    printf "%-22s write=%s  bat_I=%6d mA  bus_I=%6d mA  V=%.2f  SOC %s→%s  %s\n" \
      "$NAME" "$([ $OK -eq 0 ] && echo ok || echo FAIL)" \
      $((I / 1000)) $((BUS / 1000)) \
      $(awk -v v="$V" 'BEGIN{printf "%.2f", v/1000000}') "$SOC0" "$SOC1" "$ST" | tee -a "$LOG"
}

ONLINE=$(cat $U/online 2>/dev/null)
if [ "$ONLINE" != "1" ]; then
    log "!! 未检测到充电器（usb/online=$ONLINE），请插上充电器再跑"
    exit 1
fi

log "===== 旁路能力探测 $(date '+%m-%d %H:%M:%S') ====="
SOC=$(cat $B/capacity 2>/dev/null)
log "起始 SOC=${SOC}%  temp=$(($(cat $B/temp 2>/dev/null)/10))°C"
log ""

# 基线：不做任何事
SOC0=$(cat $B/capacity)
set -- $(avg)
printf "%-22s write=--  bat_I=%6d mA  bus_I=%6d mA  V=%.2f  SOC %s\n" \
  "基线（不干预）" $(($1 / 1000)) $(($3 / 1000)) \
  $(awk -v v="$2" 'BEGIN{printf "%.2f", v/1000000}') "$SOC0" | tee -a "$LOG"
sleep 5

probe "restrict_chg=1"          $Q/restrict_chg            1
probe "charge_control_limit=16" $B/charge_control_limit    16
probe "ccc=500mA"               $B/constant_charge_current 500000
probe "input_suspend=1"         $Q/input_suspend           1

log ""
log "判读：bus_I>0 且 bat_I≈0 且 SOC 不降 → 真旁路；bus_I≈0 且 bat_I>0 → 假旁路；bat_I<0 → 仍在充电"
