#!/system/bin/sh
# 微信小程序容器闲置清理
# com.tencent.mm:appbrand1 / appbrand2 是微信小程序运行时，退出小程序后常残留 400-500MB
# 规则：微信前台 或 小程序前台 时不处理；超过 N 分钟都未使用则结束小程序容器进程

SF_DIR=/data/adb/star-fluency
LOG=$SF_DIR/fluency.log
STATE=$SF_DIR/appbrand_idle
IDLE_MIN=$(grep -E '^APPBRAND_IDLE_MIN=' "$SF_DIR/config.conf" 2>/dev/null | cut -d= -f2)
[ -z "$IDLE_MIN" ] && IDLE_MIN=30

log() { echo "$(date '+%m-%d %H:%M:%S') [appbrand] $*" >> "$LOG" 2>/dev/null; }

# 当前前台应用
FG=$(dumpsys activity activities 2>/dev/null | grep -m1 -E "topResumedActivity|mResumedActivity" | sed -n "s/.*u[0-9]* \([a-zA-Z0-9_.]*\)\/.*/\1/p")
[ -z "$FG" ] && FG=$(dumpsys window 2>/dev/null | grep -m1 "mCurrentFocus" | grep -oE "[a-zA-Z0-9_.]+/" | head -1 | tr -d '/')

# 微信或小程序在前台 → 重置计时
case "$FG" in
    com.tencent.mm*)
        rm -f "$STATE" 2>/dev/null
        exit 0
        ;;
esac

# 没在跑就不管
PIDS=$(pgrep -f "com.tencent.mm:appbrand" 2>/dev/null)
[ -z "$PIDS" ] && { rm -f "$STATE" 2>/dev/null; exit 0; }

NOW=$(date +%s)
if [ ! -f "$STATE" ]; then
    echo "$NOW" > "$STATE"
    exit 0
fi

SINCE=$(cat "$STATE" 2>/dev/null)
[ -z "$SINCE" ] && { echo "$NOW" > "$STATE"; exit 0; }

ELAPSED=$(( NOW - SINCE ))
if [ "$ELAPSED" -ge $(( IDLE_MIN * 60 )) ]; then
    TOTAL=0
    for p in $PIDS; do
        R=$(ps -o RSS= -p "$p" 2>/dev/null | tr -d ' ')
        [ -n "$R" ] && TOTAL=$(( TOTAL + R ))
        kill -9 "$p" 2>/dev/null
    done
    log "小程序容器闲置 ${ELAPSED}s，已清理 ${TOTAL}KB"
    rm -f "$STATE" 2>/dev/null
fi
exit 0
