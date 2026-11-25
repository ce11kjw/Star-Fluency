#!/system/bin/sh
# 第二轮：找出真正能"停止充电"的节点（第一轮 restrict_chg / input_suspend 都无效）
B=/sys/class/power_supply/battery
Q=/sys/class/qcom-battery
U=/sys/class/power_supply/usb
LOG=/data/adb/star-fluency/bypass-probe2.log
: > "$LOG"
log() { echo "$*" >> "$LOG"; }

samp() {  # 12 秒内采 4 次
    n=0; si=0; ss=0
    while [ $n -lt 4 ]; do
        i=$(cat $B/current_now 2>/dev/null); [ -z "$i" ] && i=0
        s=$(cat $B/status 2>/dev/null)
        si=$((si + i)); ss="$s"
        n=$((n + 1)); [ $n -lt 4 ] && sleep 3
    done
    echo "$((si / 4)) $ss"
}

try() {
    NAME="$1"; NODE="$2"; VAL="$3"; RESTORE="$4"
    S0=$(cat $B/capacity 2>/dev/null)
    echo "$VAL" > "$NODE" 2>/dev/null
    sleep 2
    RB=$(cat "$NODE" 2>/dev/null)
    set -- $(samp)
    I=$1; ST=$2
    S1=$(cat $B/capacity 2>/dev/null)
    echo "$RESTORE" > "$NODE" 2>/dev/null
    sleep 6
    printf "%-30s 写=%s 读回=%-10s bat_I=%5dmA SOC %s→%s %s\n" \
      "$NAME" "$VAL" "$RB" $((I / 1000)) "$S0" "$S1" "$ST" >> "$LOG"
}

log "===== 第二轮：找停充节点 $(date '+%H:%M:%S') SOC=$(cat $B/capacity)% ====="
set -- $(samp)
log "基线: bat_I=$(($1 / 1000))mA  $2"
sleep 3

try "ccc=0（主充电流归零）"         $B/constant_charge_current 0       6370000
try "vbus_disable=1（断 VBUS）"      $Q/vbus_disable            1       0
try "cool_mode=1"                    $Q/cool_mode               1       0
try "usb/input_current_limit=100mA"  $U/input_current_limit     100000  0
try "charge_control_limit=1"         $B/charge_control_limit    1       0
try "restrict_cur=100mA"             $Q/restrict_cur            100000  1000000

set -- $(samp)
log "收尾: bat_I=$(($1 / 1000))mA  $2  ccc=$(cat $B/constant_charge_current)"
log "===== 完成 $(date '+%H:%M:%S') ====="
