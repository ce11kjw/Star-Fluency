#!/system/bin/sh
# 相机闲置自动清理：前台不是相机 + 超过 N 分钟 => kill

SF_DIR=/data/adb/star-fluency
LOG=$SF_DIR/fluency.log
IDLE_FILE=$SF_DIR/cam_idle_since
IDLE_MIN=5

log() { echo "$(date '+%m-%d %H:%M:%S') [cam] $*" >> "$LOG" 2>/dev/null; }

# 当前前台
FG=$(dumpsys activity activities 2>/dev/null | grep -m1 -E "topResumedActivity|mResumedActivity" | sed -n "s/.*u[0-9]* \([a-zA-Z0-9_.]*\)\/.*/\1/p")
[ -z "$FG" ] && FG=$(dumpsys window 2>/dev/null | grep -m1 "mCurrentFocus" | grep -oE "[a-zA-Z0-9_.]+/" | head -1 | tr -d '/')

if [ "$FG" = "com.android.camera" ]; then
    rm -f "$IDLE_FILE" 2>/dev/null
    exit 0
fi

PID=$(pidof com.android.camera 2>/dev/null)
[ -z "$PID" ] && { rm -f "$IDLE_FILE" 2>/dev/null; exit 0; }

# 记录首次发现闲置的时间
NOW=$(date +%s)
if [ ! -f "$IDLE_FILE" ]; then
    echo "$NOW" > "$IDLE_FILE"
    exit 0
fi

SINCE=$(cat "$IDLE_FILE" 2>/dev/null)
[ -z "$SINCE" ] && { echo "$NOW" > "$IDLE_FILE"; exit 0; }

ELAPSED=$(( NOW - SINCE ))
if [ "$ELAPSED" -ge $(( IDLE_MIN * 60 )) ]; then
    RSS=$(ps -o RSS= -p "$PID" 2>/dev/null | tr -d ' ')
    kill -9 "$PID" 2>/dev/null
    log "相机闲置 ${ELAPSED}s，已清理 (RSS=${RSS}KB pid=$PID)"
    rm -f "$IDLE_FILE" 2>/dev/null
fi
exit 0
