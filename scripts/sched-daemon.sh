#!/system/bin/sh
# Star-Fluency 场景识别守护（每 15s 一轮）
# 优先级：温度回退 > 按应用覆盖 > 息屏省电 > 充电提档 > 手动档位
# 由 service.sh 拉起；SCHED_ENABLED=0 时直接退出

SF_DIR=/data/adb/star-fluency
SCHED_DIR=$SF_DIR/sched
CONF=$SF_DIR/config.conf
LOG=$SF_DIR/fluency.log
STATE=$SCHED_DIR/state
APPS=$SCHED_DIR/apps.conf
MODDIR=${MODDIR:-/data/adb/modules/star_fluency}
mkdir -p "$SCHED_DIR" 2>/dev/null
echo $$ > "$SCHED_DIR/sched.pid" 2>/dev/null

log() { echo "$(date '+%m-%d %H:%M:%S') [schedd] $*" >> "$LOG" 2>/dev/null; }
conf() { grep -E "^$1=" "$CONF" 2>/dev/null | cut -d= -f2 | head -1; }
cur_mode() { grep '^mode=' "$STATE" 2>/dev/null | cut -d= -f2; }
cur_reason() { grep '^reason=' "$STATE" 2>/dev/null | cut -d= -f2; }

# 前台应用：跳过 mCurrentFocus=null，优先 Window{（约 100ms）
top_app() {
    A=$(dumpsys window 2>/dev/null | grep -m1 "mCurrentFocus=Window{" | sed -n "s/.*u[0-9]* \([a-zA-Z0-9_.]*\)\/.*/\1/p")
    [ -z "$A" ] && A=$(dumpsys window 2>/dev/null | grep -m1 "mFocusedApp=ActivityRecord{" | sed -n "s/.*u[0-9]* \([a-zA-Z0-9_.]*\)\/.*/\1/p")
    echo "$A"
}

apply() {
    M="$1"; R="$2"; A="$3"
    sh "$MODDIR/scripts/sched.sh" apply "$M" >/dev/null 2>&1
    {
        echo "mode=$M"
        echo "reason=$R"
        echo "app=$A"
        echo "ts=$(date +%s)"
    } > "$STATE"
    log "切换 $M ($R) 前台=${A:-无}"
}

while true; do
    sleep 15

    ENABLED=$(conf SCHED_ENABLED)
    [ "$ENABLED" = "0" ] && continue

    BL=$(cat /sys/class/leds/lcd-backlight/brightness 2>/dev/null)
    [ -z "$BL" ] && BL=1
    CHG=$(cat /sys/class/power_supply/battery/status 2>/dev/null)
    T=$(cat /sys/class/power_supply/battery/temp 2>/dev/null)
    [ -z "$T" ] && T=0
    T=$((T / 10))

    BASE=$(conf SCHED_MODE)
    [ -z "$BASE" ] && BASE=$(conf PROFILE)
    [ -z "$BASE" ] && BASE=balance
    case "$BASE" in smooth) BASE=performance ;; stock) BASE=balance ;; esac

    OVERRIDE=$(conf SCHED_APP_OVERRIDE); [ -z "$OVERRIDE" ] && OVERRIDE=1
    SCREEN_SAVE=$(conf SCHED_SCREEN_SAVE); [ -z "$SCREEN_SAVE" ] && SCREEN_SAVE=1
    CHG_BOOST=$(conf SCHED_CHG_BOOST); [ -z "$CHG_BOOST" ] && CHG_BOOST=1
    TLIMIT=$(conf SCHED_TEMP_LIMIT); [ -z "$TLIMIT" ] && TLIMIT=42

    APP=""
    if [ "$OVERRIDE" = "1" ] && [ -s "$APPS" ]; then
        APP=$(top_app)
    fi

    MODE="$BASE"
    REASON="基准"

    if [ "$T" -ge "$TLIMIT" ]; then
        MODE=powersave
        REASON="过热 ${T}C>=${TLIMIT}C"
    else
        AM=""
        if [ -n "$APP" ] && [ -f "$APPS" ]; then
            AM=$(grep -E "^$APP=" "$APPS" 2>/dev/null | head -1 | cut -d= -f2)
        fi
        if [ -n "$AM" ]; then
            MODE="$AM"
            REASON="应用规则 $APP"
        elif [ "$SCREEN_SAVE" = "1" ] && [ "$BL" -eq 0 ]; then
            MODE=powersave
            REASON="息屏"
        elif [ "$CHG_BOOST" = "1" ] && [ "$CHG" = "Charging" ]; then
            MODE=performance
            REASON="充电中"
        fi
    fi

    if [ "$MODE" != "$(cur_mode)" ] || [ "$REASON" != "$(cur_reason)" ]; then
        apply "$MODE" "$REASON" "$APP"
    fi
done
