#!/system/bin/sh
# Star-Fluency 充电限流（温度分档 + 夜间时段）
# 用法: charge-night.sh on|off|temp-on|temp-off|tick|status
#
# 生效条件：只在「充电中」生效；否则还原
# 取两个上限里更严的那个：
#   夜间时段（默认 23-07）  -> 1500mA
#   温度分档（默认 38/41/44°C -> 3000/2000/1200mA）

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
mkdir -p "$CD" 2>/dev/null

log() { echo "$(date '+%m-%d %H:%M:%S') [charge] $*" >> "$LOG" 2>/dev/null; }
conf() { grep -E "^$1=" "$CONF" 2>/dev/null | cut -d= -f2 | head -1; }
setk() { grep -q "^$1=" "$CONF" 2>/dev/null && sed -i "s|^$1=.*|$1=$2|" "$CONF" || echo "$1=$2" >> "$CONF"; }

NIGHT_ON=$(conf CHARGE_NIGHT);      [ -z "$NIGHT_ON" ] && NIGHT_ON=1
TEMP_ON=$(conf CHARGE_TEMP_ON);     [ -z "$TEMP_ON" ] && TEMP_ON=1
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

applied() { [ -f "$ST" ] && grep -q '^applied=1' "$ST" 2>/dev/null; }
orig_ccc() { grep '^orig_ccc=' "$ST" 2>/dev/null | cut -d= -f2; }
orig_night() { grep '^orig_night=' "$ST" 2>/dev/null | cut -d= -f2; }

in_window() {
    H=$(date +%H); H=${H#0}; [ -z "$H" ] && H=0
    if [ "$START_H" -le "$END_H" ]; then
        [ "$H" -ge "$START_H" ] && [ "$H" -lt "$END_H" ]
    else
        [ "$H" -ge "$START_H" ] || [ "$H" -lt "$END_H" ]
    fi
}

# 根据温度与时段算出目标电流（mA），以及原因
desired_ma() {
    RAW=$(cat $B/temp 2>/dev/null); [ -z "$RAW" ] && RAW=0
    T=$((RAW / 10))
    TARGET=$MAX_MA
    WHY="不限"
    if [ "$TEMP_ON" = "1" ]; then
        if [ "$T" -ge "$T3" ]; then TARGET=$T3MA; WHY="${T}°C≥${T3}°C"
        elif [ "$T" -ge "$T2" ]; then TARGET=$T2MA; WHY="${T}°C≥${T2}°C"
        elif [ "$T" -ge "$T1" ]; then TARGET=$T1MA; WHY="${T}°C≥${T1}°C"
        fi
    fi
    if [ "$NIGHT_ON" = "1" ] && in_window; then
        if [ "$NIGHT_MA" -lt "$TARGET" ]; then
            TARGET=$NIGHT_MA
            WHY="夜间时段"
        fi
    fi
    echo "$TARGET $WHY $T"
}

write_ma() {
    MA=$1
    if [ "$MA" -ge "$MAX_MA" ]; then
        restore
        return 0
    fi
    if ! applied; then
        OCCC=$(cat "$CCC" 2>/dev/null); [ -z "$OCCC" ] && OCCC=$((MAX_MA * 1000))
        ONIGHT=$(cat "$NIGHT" 2>/dev/null); [ -z "$ONIGHT" ] && ONIGHT=0
        {
            echo "applied=1"
            echo "orig_ccc=$OCCC"
            echo "orig_night=$ONIGHT"
        } > "$ST"
    fi
    echo "${MA}000" > "$CCC" 2>/dev/null
    NOW=$(cat "$CCC" 2>/dev/null)
    echo "applied=1" > "$ST.tmp" 2>/dev/null
    if [ "$NOW" != "${MA}000" ]; then
        # 驱动可能在上报旧值，再写一次
        echo "${MA}000" > "$CCC" 2>/dev/null
    fi
    echo "cur_ma=$MA" >> "$ST"
}

restore() {
    OC=$(orig_ccc); ON=$(orig_night)
    [ -z "$OC" ] && OC=$((MAX_MA * 1000))
    [ -z "$ON" ] && ON=0
    echo "$OC" > "$CCC" 2>/dev/null
    echo "$ON" > "$NIGHT" 2>/dev/null
    rm -f "$ST" "$ST.tmp" 2>/dev/null
}

case "$1" in
  on)  setk CHARGE_NIGHT 1; echo "夜间时段限流：开（${START_H}:00-${END_H}:00 → ${NIGHT_MA}mA）" ;;
  off) setk CHARGE_NIGHT 0; echo "夜间时段限流：关" ;;
  temp-on)  setk CHARGE_TEMP_ON 1; echo "温度限流：开（≥${T1}°C→${T1MA}mA，≥${T2}°C→${T2MA}mA，≥${T3}°C→${T3MA}mA）" ;;
  temp-off) setk CHARGE_TEMP_ON 0; echo "温度限流：关" ;;
  tick)
    S_STATUS=$(cat $B/status 2>/dev/null)
    case "$S_STATUS" in
      Charging)
        set -- $(desired_ma)
        TARGET=$1; WHY=$2; T=$3
        CUR_MA=$(( $(cat "$CCC" 2>/dev/null || echo 0) / 1000 ))
        if [ "$TARGET" -ge "$MAX_MA" ]; then
            applied && restore && log "充电不限流（${T}°C）"
        elif [ "$CUR_MA" != "$TARGET" ]; then
            write_ma "$TARGET"
            echo "night_charging" > /dev/null
            log "充电限流 ${TARGET}mA（$WHY，${T}°C）"
        fi
        ;;
      *)
        applied && restore
        exit 0
        applied && restore
        ;;
    esac
    ;;
  status)
    set -- $(desired_ma)
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
    echo "用法: charge-night.sh {on|off|temp-on|temp-off|tick|status}"
    ;;
esac
