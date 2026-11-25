#!/system/bin/sh
# Star-Fluency 夜间慢充
# 白名单时段内把充电电流压低（默认 1.5A ≈ 6.4W），白天/关闭时还原
# 用法: charge-night.sh on | off | tick | status

MODDIR=${MODDIR:-/data/adb/modules/star_fluency}
SF=/data/adb/star-fluency
CD=$SF/charge
CONF=$SF/config.conf
LOG=$SF/fluency.log
ST=$CD/state
B=/sys/class/power_supply/battery
Q=/sys/class/qcom-battery
CCC=$B/constant_charge_current
NIGHT=$Q/night_charging
mkdir -p "$CD" 2>/dev/null

log() { echo "$(date '+%m-%d %H:%M:%S') [charge] $*" >> "$LOG" 2>/dev/null; }
conf() { grep -E "^$1=" "$CONF" 2>/dev/null | cut -d= -f2 | head -1; }

LIMIT_MA=$(conf CHARGE_SLOW_MA); [ -z "$LIMIT_MA" ] && LIMIT_MA=1500
START_H=$(conf CHARGE_NIGHT_START); [ -z "$START_H" ] && START_H=23
END_H=$(conf CHARGE_NIGHT_END); [ -z "$END_H" ] && END_H=7
applied() { grep -q '^applied=1' "$ST" 2>/dev/null; }
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

apply() {
    OCCC=$(cat "$CCC" 2>/dev/null); [ -z "$OCCC" ] && OCCC=0
    ONIGHT=$(cat "$NIGHT" 2>/dev/null); [ -z "$ONIGHT" ] && ONIGHT=0
    {
        echo "applied=1"
        echo "orig_ccc=$OCCC"
        echo "orig_night=$ONIGHT"
        echo "ts=$(date +%s)"
    } > "$ST"
    echo "${LIMIT_MA}000" > "$CCC" 2>/dev/null
    echo 1 > "$NIGHT" 2>/dev/null
    NOW=$(cat "$CCC" 2>/dev/null)
    log "夜间慢充已启用：${LIMIT_MA}mA（读回 $NOW，原 $OCCC）"
}

restore() {
    OC=$(orig_ccc); ON=$(orig_night)
    [ -z "$OC" ] && OC=6370000
    [ -z "$ON" ] && ON=0
    echo "$OC" > "$CCC" 2>/dev/null
    echo "$ON" > "$NIGHT" 2>/dev/null
    rm -f "$ST" 2>/dev/null
    log "夜间慢充已还原（ccc=$OC night=$ON）"
}

case "$1" in
  on)
    sed -i '/^CHARGE_NIGHT=/d' "$CONF" 2>/dev/null
    echo "CHARGE_NIGHT=1" >> "$CONF"
    echo "已开启夜间慢充（${START_H}:00 - ${END_H}:00，限流 ${LIMIT_MA}mA）"
    ;;
  off)
    sed -i '/^CHARGE_NIGHT=/d' "$CONF" 2>/dev/null
    echo "CHARGE_NIGHT=0" >> "$CONF"
    applied && restore
    echo "已关闭夜间慢充"
    ;;
  tick)
    EN=$(conf CHARGE_NIGHT)
    if [ "$EN" != "1" ]; then
        applied && restore
        exit 0
    fi
    ST_STATUS=$(cat $B/status 2>/dev/null)
    if in_window; then
        case "$ST_STATUS" in
          Charging|Full)
            CUR=$(cat "$CCC" 2>/dev/null)
            if [ "$CUR" != "${LIMIT_MA}000" ]; then
                if applied; then
                    # 已应用但被驱动重置，只重写电流，保留原值
                    echo "${LIMIT_MA}000" > "$CCC" 2>/dev/null
                else
                    apply
                fi
            fi
            ;;
          *)
            # 窗口内但没在充电：保持备份，等插上再压
            ;;
        esac
    else
        applied && restore
    fi
    ;;
  status)
    echo "enabled=$(conf CHARGE_NIGHT)"
    echo "window=${START_H}:00-${END_H}:00"
    echo "limit_ma=$LIMIT_MA"
    echo "applied=$(applied && echo 1 || echo 0)"
    echo "ccc_now=$(cat "$CCC" 2>/dev/null)"
    echo "night_now=$(cat "$NIGHT" 2>/dev/null)"
    echo "in_window=$(in_window && echo 1 || echo 0)"
    echo "batt_status=$(cat $B/status 2>/dev/null)"
    echo "orig_ccc=$(orig_ccc)"
    ;;
  *)
    echo "用法: charge-night.sh {on|off|tick|status}"
    ;;
esac
