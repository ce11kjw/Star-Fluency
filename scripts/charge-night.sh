#!/system/bin/sh
# Star-Fluency 充电控制
#   1) 容量上限（pause/resume，参考 VR-25/acc 的 pause_capacity/resume_capacity）
#   2) 温度分档限流（38/41/44°C → 3.0/2.0/1.2A，含 2°C 迟滞）
#   3) 夜间时段限流（23-07 → 1.5A）
# 三者相互独立，取最严；拔电一律解除暂停并还原电流
#
# 用法: charge-night.sh on|off|temp-on|temp-off|limit-on|limit-off|tick|status

MODDIR=${MODDIR:-/data/adb/modules/star_fluency}
SF=/data/adb/star-fluency
CD=$SF/charge
CONF=$SF/config.conf
LOG=$SF/fluency.log
ST=$CD/state
B=${SF_BAT:-/sys/class/power_supply/battery}
Q=${SF_QBAT:-/sys/class/qcom-battery}
CCC=$B/constant_charge_current
NIGHT=$Q/night_charging
SUSP=$Q/input_suspend
USB=${SF_USB:-/sys/class/power_supply/usb}
mkdir -p "$CD" 2>/dev/null

log() { echo "$(date '+%m-%d %H:%M:%S') [charge] $*" >> "$LOG" 2>/dev/null; }
conf() { grep -E "^$1=" "$CONF" 2>/dev/null | cut -d= -f2 | head -1; }
setk() { if grep -q "^$1=" "$CONF" 2>/dev/null; then sed -i "s|^$1=.*|$1=$2|" "$CONF"; else echo "$1=$2" >> "$CONF"; fi; }

NIGHT_ON=$(conf CHARGE_NIGHT);      [ -z "$NIGHT_ON" ] && NIGHT_ON=1
TEMP_ON=$(conf CHARGE_TEMP_ON);     [ -z "$TEMP_ON" ] && TEMP_ON=1
LIMIT_ON=$(conf CHARGE_LIMIT_ON);   [ -z "$LIMIT_ON" ] && LIMIT_ON=0
LPCT=$(conf CHARGE_LIMIT_PCT);      [ -z "$LPCT" ] && LPCT=80
GAP=$(conf CHARGE_LIMIT_GAP);       [ -z "$GAP" ] && GAP=3
START_H=$(conf CHARGE_NIGHT_START); [ -z "$START_H" ] && START_H=23
END_H=$(conf CHARGE_NIGHT_END);     [ -z "$END_H" ] && END_H=7
NIGHT_MA=$(conf CHARGE_SLOW_MA);    [ -z "$NIGHT_MA" ] && NIGHT_MA=1500
T1=$(conf CHARGE_T1); [ -z "$T1" ] && T1=38
T1MA=$(conf CHARGE_T1_MA); [ -z "$T1MA" ] && T1MA=3000
T2=$(conf CHARGE_T2); [ -z "$T2" ] && T2=41
T2MA=$(conf CHARGE_T2_MA); [ -z "$T2MA" ] && T2MA=2000
T3=$(conf CHARGE_T3); [ -z "$T3" ] && T3=44
T3MA=$(conf CHARGE_T3_MA); [ -z "$T3MA" ] && T3MA=1200
MAX_MA=$(conf CHARGE_MAX_MA); [ -z "$MAX_MA" ] && MAX_MA=6370
HYST=$(conf CHARGE_TEMP_HYST); [ -z "$HYST" ] && HYST=2

applied() { [ -f "$ST" ] && grep -q '^applied=1' "$ST" 2>/dev/null; }
paused() { [ -f "$ST" ] && grep -q '^paused=1' "$ST" 2>/dev/null; }
orig_ccc() { grep '^orig_ccc=' "$ST" 2>/dev/null | cut -d= -f2; }
orig_night() { grep '^orig_night=' "$ST" 2>/dev/null | cut -d= -f2; }
setflag() { touch "$ST" 2>/dev/null; sed -i "/^$1=/d" "$ST" 2>/dev/null; echo "$1=$2" >> "$ST"; }
clearflag() { [ -f "$ST" ] && sed -i "/^$1=/d" "$ST" 2>/dev/null; }

in_window() {
    H=$(date +%H); H=${H#0}; [ -z "$H" ] && H=0
    if [ "$START_H" -le "$END_H" ]; then
        [ "$H" -ge "$START_H" ] && [ "$H" -lt "$END_H" ]
    else
        [ "$H" -ge "$START_H" ] || [ "$H" -lt "$END_H" ]
    fi
}

# 温度 + 夜间的电流上限（mA），带迟滞
desired_ma() {
    PREV=$(grep '^tier=' "$ST" 2>/dev/null | cut -d= -f2)
    [ -z "$PREV" ] && PREV=0
    RAW=$(cat $B/temp 2>/dev/null); [ -z "$RAW" ] && RAW=0
    T=$((RAW / 10))
    TARGET=$MAX_MA
    E1=$T1; E2=$T2; E3=$T3
    [ "$PREV" -ge 1 ] && E1=$((T1 - HYST))
    [ "$PREV" -ge 2 ] && E2=$((T2 - HYST))
    [ "$PREV" -ge 3 ] && E3=$((T3 - HYST))
    TIER=0
    WHY="不限"
    if [ "$TEMP_ON" = "1" ]; then
        if [ "$T" -ge "$E3" ]; then TARGET=$T3MA; TIER=3; WHY="${T}°C≥${E3}°C"
        elif [ "$T" -ge "$E2" ]; then TARGET=$T2MA; TIER=2; WHY="${T}°C≥${E2}°C"
        elif [ "$T" -ge "$E1" ]; then TARGET=$T1MA; TIER=1; WHY="${T}°C≥${E1}°C"
        fi
    fi
    if [ "$NIGHT_ON" = "1" ] && in_window; then
        if [ "$NIGHT_MA" -lt "$TARGET" ]; then
            TARGET=$NIGHT_MA
            WHY="夜间时段"
        fi
    fi
    echo "$TARGET $WHY $T $TIER"
}

write_ma() {
    MA=$1
    if [ "$MA" -ge "$MAX_MA" ]; then
        restore_cur
        return 0
    fi
    if ! applied; then
        OCCC=$(cat "$CCC" 2>/dev/null); [ -z "$OCCC" ] && OCCC=$((MAX_MA * 1000))
        ONIGHT=$(cat "$NIGHT" 2>/dev/null); [ -z "$ONIGHT" ] && ONIGHT=0
        setflag applied 1
        setflag orig_ccc "$OCCC"
        setflag orig_night "$ONIGHT"
    fi
    echo "${MA}000" > "$CCC" 2>/dev/null
    NOW=$(cat "$CCC" 2>/dev/null)
    [ "$NOW" != "${MA}000" ] && echo "${MA}000" > "$CCC" 2>/dev/null
    setflag cur_ma "$MA"
}

restore_cur() {
    OC=$(orig_ccc); ON=$(orig_night)
    [ -z "$OC" ] && OC=$((MAX_MA * 1000))
    [ -z "$ON" ] && ON=0
    echo "$OC" > "$CCC" 2>/dev/null
    echo "$ON" > "$NIGHT" 2>/dev/null
    clearflag applied
    clearflag cur_ma
    clearflag orig_ccc
    clearflag orig_night
    clearflag tier
}

case "$1" in
  on)  setk CHARGE_NIGHT 1; echo "夜间时段限流：开（${START_H}:00-${END_H}:00 → ${NIGHT_MA}mA）" ;;
  off) setk CHARGE_NIGHT 0; echo "夜间时段限流：关" ;;
  temp-on)  setk CHARGE_TEMP_ON 1; echo "温度限流：开（≥${T1}°C→${T1MA}mA，≥${T2}°C→${T2MA}mA，≥${T3}°C→${T3MA}mA，迟滞 ${HYST}°C）" ;;
  temp-off) setk CHARGE_TEMP_ON 0; echo "温度限流：关" ;;
  limit-on)  setk CHARGE_LIMIT_ON 1; echo "充电上限：开（充到 ${LPCT}% 停，降到 $((LPCT - GAP))% 续）" ;;
  limit-off)
    setk CHARGE_LIMIT_ON 0
    echo 0 > "$SUSP" 2>/dev/null
    clearflag paused
    echo "充电上限：关（已恢复充电）"
    ;;
  set-limit)
    [ -z "$2" ] && { echo "用法: set-limit <50-100>"; exit 1; }
    setk CHARGE_LIMIT_PCT "$2"
    echo "充电上限已设为 $2%"
    ;;
  tick)
    ONLINE=$(cat $USB/online 2>/dev/null); [ -z "$ONLINE" ] && ONLINE=0
    CAP=$(cat $B/capacity 2>/dev/null); [ -z "$CAP" ] && CAP=0
    RPCT=$((LPCT - GAP))

    # ---- 1) 容量上限（input_suspend 开关，参考 acc 的 pause/resume）----
    if [ "$ONLINE" != "1" ]; then
        # 拔电：必须解除暂停，否则下次插上不充电
        if paused; then
            echo 0 > "$SUSP" 2>/dev/null
            clearflag paused
            log "拔电，已解除充电暂停"
        fi
        echo 0 > "$SUSP" 2>/dev/null
    elif [ "$LIMIT_ON" = "1" ]; then
        if [ "$CAP" -ge "$LPCT" ] && ! paused; then
            echo 1 > "$SUSP" 2>/dev/null
            setflag paused 1
            log "充电上限 ${LPCT}%：暂停充电（当前 ${CAP}%）"
        elif [ "$CAP" -le "$RPCT" ] && paused; then
            echo 0 > "$SUSP" 2>/dev/null
            clearflag paused
            log "充电上限：恢复充电（当前 ${CAP}%）"
        fi
    elif paused; then
        echo 0 > "$SUSP" 2>/dev/null
        clearflag paused
    fi

    # ---- 2) 温度/夜间限流（只在真正充电时）----
    S_STATUS=$(cat $B/status 2>/dev/null)
    if [ "$S_STATUS" = "Charging" ]; then
        set -- $(desired_ma)
        TARGET=$1; WHY=$2; T=$3; TIER=$4
        CUR_MA=$(( $(cat "$CCC" 2>/dev/null || echo 0) / 1000 ))
        if [ "$TARGET" -ge "$MAX_MA" ]; then
            applied && restore_cur && log "电流恢复正常（${T}°C）"
            clearflag tier
        elif [ "$CUR_MA" != "$TARGET" ]; then
            write_ma "$TARGET"
            setflag tier "$TIER"
            log "限流 ${TARGET}mA（$WHY，${T}°C）"
        fi
    else
        applied && restore_cur
        clearflag tier
    fi
    ;;
  status)
    set -- $(desired_ma)
    CAP=$(cat $B/capacity 2>/dev/null)
    ONLINE=$(cat $USB/online 2>/dev/null)
    echo "limit_enabled=$LIMIT_ON"
    echo "limit_pct=$LPCT"
    echo "limit_resume=$((LPCT - GAP))"
    echo "limit_paused=$(paused && echo 1 || echo 0)"
    echo "capacity=${CAP:-0}"
    echo "usb_online=${ONLINE:-0}"
    echo "night_enabled=$NIGHT_ON"
    echo "temp_enabled=$TEMP_ON"
    echo "window=${START_H}:00-${END_H}:00"
    echo "night_ma=$NIGHT_MA"
    echo "tiers=${T1}°C→${T1MA}mA / ${T2}°C→${T2MA}mA / ${T3}°C→${T3MA}mA"
    echo "max_ma=$MAX_MA"
    echo "applied=$(applied && echo 1 || echo 0)"
    echo "cur_ma=$(echo "$(cat "$CCC" 2>/dev/null)" | awk '{printf "%d", $1/1000}')"
    echo "target_ma=$1"
    echo "reason=$2"
    echo "temp=$3"
    echo "in_window=$(in_window && echo 1 || echo 0)"
    echo "batt_status=$(cat $B/status 2>/dev/null)"
    echo "orig_ccc=$(orig_ccc)"
    ;;
  *)
    echo "用法: charge-night.sh {on|off|temp-on|temp-off|limit-on|limit-off|set-limit <pct>|tick|status}"
    ;;
esac
