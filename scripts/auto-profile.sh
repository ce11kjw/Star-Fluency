#!/system/bin/sh
# 场景自动切换 + 温度感知降级
# 用法: auto-profile.sh       执行一次检查（由守护每 60s 调用）
#       auto-profile.sh status 查看当前状态

SF_DIR=/data/adb/star-fluency
CONF=$SF_DIR/config.conf
LOG=$SF_DIR/fluency.log
STATE=$SF_DIR/auto_state
mkdir -p "$SF_DIR" 2>/dev/null

log() { echo "$(date '+%m-%d %H:%M:%S') [auto] $*" >> "$LOG" 2>/dev/null; }
conf() { grep -E "^$1=" "$CONF" 2>/dev/null | cut -d= -f2; }

# 开关
AUTO_SCENE=$(conf AUTO_SCENE); [ -z "$AUTO_SCENE" ] && AUTO_SCENE=0
AUTO_TEMP=$(conf AUTO_TEMP); [ -z "$AUTO_TEMP" ] && AUTO_TEMP=0
TEMP_THRESHOLD=$(conf TEMP_THRESHOLD); [ -z "$TEMP_THRESHOLD" ] && TEMP_THRESHOLD=42
TEMP_RECOVER=$(conf TEMP_RECOVER); [ -z "$TEMP_RECOVER" ] && TEMP_RECOVER=38

case "$1" in
  status)
    echo "AUTO_SCENE=$AUTO_SCENE"
    echo "AUTO_TEMP=$AUTO_TEMP"
    echo "TEMP_THRESHOLD=$TEMP_THRESHOLD"
    echo "TEMP_RECOVER=$TEMP_RECOVER"
    cat "$STATE" 2>/dev/null
    exit 0
    ;;
esac

# 当前温度（0.1°C → °C）
BAT_T=$(cat /sys/class/power_supply/battery/temp 2>/dev/null)
[ -z "$BAT_T" ] && BAT_T=0
BAT_C=$(( BAT_T / 10 ))

# 当前充电状态
CHG=$(cat /sys/class/power_supply/battery/status 2>/dev/null)

# 上一轮状态
PREV_PROF=$(grep '^prof=' "$STATE" 2>/dev/null | cut -d= -f2)
PREV_TEMP_WARN=$(grep '^temp_warn=' "$STATE" 2>/dev/null | cut -d= -f2)

# ---- 温度降级优先 ----
TARGET=""
REASON=""
if [ "$AUTO_TEMP" = "1" ]; then
    if [ "$BAT_C" -ge "$TEMP_THRESHOLD" ]; then
        TARGET=balance     # 降级到平衡档
        REASON="温度 ${BAT_C}°C >= ${TEMP_THRESHOLD}°C，降级"
        [ "$PREV_TEMP_WARN" != "1" ] && log "过热降级: ${BAT_C}°C"
    elif [ "$BAT_C" -le "$TEMP_RECOVER" ] && [ "$PREV_TEMP_WARN" = "1" ]; then
        TARGET=""          # 温度恢复，交回场景逻辑
        REASON="温度回落到 ${BAT_C}°C，解除降级"
        log "温度恢复: ${BAT_C}°C"
    fi
fi

# ---- 场景切换（温度未触发时）----
if [ -z "$TARGET" ] && [ "$AUTO_SCENE" = "1" ] && [ "$PREV_TEMP_WARN" != "1" ]; then
    case "$CHG" in
        Charging|Full)
            TARGET=smooth
            REASON="充电中，切流畅档"
            ;;
        *)
            H=$(date +%H); H=${H#0}; [ -z "$H" ] && H=0
            if [ "$H" -ge 23 ] || [ "$H" -lt 7 ]; then
                TARGET=balance
                REASON="夜间(${H}点)，切平衡档"
            else
                TARGET=""
            fi
            ;;
    esac
fi

# ---- 应用 ----
CUR_PROF=$(conf PROFILE); [ -z "$CUR_PROF" ] && CUR_PROF=balance
if [ -n "$TARGET" ] && [ "$TARGET" != "$CUR_PROF" ]; then
    sh /data/adb/modules/star_fluency/scripts/apply.sh "$TARGET" >/dev/null 2>&1
    log "自动切换 $CUR_PROF -> $TARGET ($REASON)"
    CUR_PROF=$TARGET
fi

# ---- 记录状态 ----
WARN=0
[ "$AUTO_TEMP" = "1" ] && [ "$BAT_C" -ge "$TEMP_THRESHOLD" ] && WARN=1
{
    echo "prof=$CUR_PROF"
    echo "temp=$BAT_C"
    echo "temp_warn=$WARN"
    echo "chg=$CHG"
    echo "updated=$(date '+%H:%M:%S')"
} > "$STATE"

exit 0
