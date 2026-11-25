#!/system/bin/sh
# Star-Fluency 场景识别守护（15s 一轮）
# 分工：
#   Scene = HP/LP/在线配置  -> 完全让位（只把 clamp_min 归 0）
#   Scene = 外部来源        -> Scene 驱动档位，我们只守温度
#   Scene = 自定义 / 无     -> 我们自己管（温度 > 应用规则 > 息屏 > 充电 > 基准）
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
scene_source() {
    grep -oE 'name="scene_profile_source">[^<]*' /data/data/com.omarea.vtools/shared_prefs/global.xml 2>/dev/null | sed 's/.*>//'
}
top_app() {
    A=$(dumpsys window 2>/dev/null | grep -m1 "mCurrentFocus=Window{" | sed -n "s/.*u[0-9]* \([a-zA-Z0-9_.]*\)\/.*/\1/p")
    [ -z "$A" ] && A=$(dumpsys window 2>/dev/null | grep -m1 "mFocusedApp=ActivityRecord{" | sed -n "s/.*u[0-9]* \([a-zA-Z0-9_.]*\)\/.*/\1/p")
    echo "$A"
}
# 完整组件 pkg/Activity（支持按页面绑定）
top_app_full() {
    F=$(dumpsys window 2>/dev/null | grep -m1 "mCurrentFocus=Window{" | sed -n 's/.*u[0-9]* \([a-zA-Z0-9_.]*\)\/\([a-zA-Z0-9_.]*\).*/\1\/\2/p')
    [ -z "$F" ] && F=$(dumpsys window 2>/dev/null | grep -m1 "mFocusedApp=ActivityRecord{" | sed -n 's/.*u[0-9]* \([a-zA-Z0-9_.]*\)\/\([a-zA-Z0-9_.]*\).*/\1\/\2/p')
    echo "$F"
}

# push = 只写参数，不改基准档位（Scene 驱动时不能覆盖它的选择）
apply() {
    M="$1"; R="$2"; A="$3"
    sh "$MODDIR/scripts/sched.sh" push "$M" >/dev/null 2>&1
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

    [ "$(conf SCHED_ENABLED)" = "0" ] && continue

    SS=$(scene_source)
    YIELD=$(conf SCHED_YIELD_SCENE); [ -z "$YIELD" ] && YIELD=1
    TBAT=$(conf SCHED_TEMP_LIMIT); [ -z "$TBAT" ] && TBAT=42
    TCORE=$(conf SCHED_CORE_TEMP_LIMIT); [ -z "$TCORE" ] && TCORE=68

    BAT=$(cat /sys/class/power_supply/battery/temp 2>/dev/null)
    [ -z "$BAT" ] && BAT=0
    BAT=$((BAT / 10))
    CORE=$(cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null)
    [ -z "$CORE" ] && CORE=0
    CORE=$((CORE / 1000))

    HOT=0
    [ "$BAT" -ge "$TBAT" ] && HOT=1
    [ "$CORE" -ge "$TCORE" ] && HOT=1

    # ---- 1) Scene 自带配置在跑 -> 完全让位 ----
    case "$SS" in
      SOURCE_SCENE_ONLINE|SOURCE_SCENE_ACTIVE|SOURCE_SCENE_CONSERVATIVE)
        if [ "$YIELD" = "1" ]; then
            if [ "$(cur_reason)" != "yield:$SS" ]; then
                echo 0 > /proc/sys/kernel/sched_util_clamp_min 2>/dev/null
                {
                    echo "mode=yield"
                    echo "reason=yield:$SS"
                    echo "app="
                    echo "ts=$(date +%s)"
                } > "$STATE"
                log "让位给 Scene ($SS)：不写频率，clamp_min 归 0"
            fi
            continue
        fi
        ;;
    esac

    BASE=$(conf SCHED_MODE)
    [ -z "$BASE" ] && BASE=$(conf PROFILE)
    [ -z "$BASE" ] && BASE=balance
    case "$BASE" in smooth) BASE=performance ;; stock) BASE=balance ;; esac

    # ---- 2) Scene 用外部来源（调我们）：档位由它定，我们只守温度 ----
    if [ "$SS" = "SOURCE_OUTSIDE" ]; then
        if [ "$HOT" = "1" ]; then
            [ "$(cur_reason)" != "过热" ] && apply powersave "过热" ""
        else
            case "$(cur_reason)" in
                过热) apply "$BASE" "温度恢复" "" ;;
            esac
        fi
        continue
    fi

    # ---- 3) 我们自己管 ----
    OVERRIDE=$(conf SCHED_APP_OVERRIDE); [ -z "$OVERRIDE" ] && OVERRIDE=0
    SCREEN_SAVE=$(conf SCHED_SCREEN_SAVE); [ -z "$SCREEN_SAVE" ] && SCREEN_SAVE=1
    CHG_BOOST=$(conf SCHED_CHG_BOOST); [ -z "$CHG_BOOST" ] && CHG_BOOST=1

    BL=$(cat /sys/class/leds/lcd-backlight/brightness 2>/dev/null)
    [ -z "$BL" ] && BL=1
    CHG=$(cat /sys/class/power_supply/battery/status 2>/dev/null)

    APP=""
    if [ "$OVERRIDE" = "1" ] && [ -s "$APPS" ]; then
        APP=$(top_app)
        FULL=$(top_app_full)
    fi

    MODE="$BASE"
    REASON="基准"

    if [ "$HOT" = "1" ]; then
        MODE=powersave
        REASON="过热"
        log "温度 核心${CORE}C 电池${BAT}C 超阈值"
    else
        AM=""
        if [ -n "$APP" ] && [ -f "$APPS" ]; then
            AM=$(grep -F "$FULL=" "$APPS" 2>/dev/null | head -1 | cut -d= -f2)
            [ -z "$AM" ] && AM=$(grep -E "^$APP=" "$APPS" 2>/dev/null | head -1 | cut -d= -f2)
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
