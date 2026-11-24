#!/system/bin/sh
# Play 商店后台压制守护
# force-stop 后 Play 商店会被系统/GMS 唤醒，需要周期性压制
# 但用户主动打开 Play 商店时不能干扰 → 检测前台

SF_DIR=/data/adb/star-fluency
LOG=$SF_DIR/fluency.log
PLAY=com.android.vending
KILLED=$SF_DIR/play_killed_count

log() { echo "$(date '+%m-%d %H:%M:%S') [play-guard] $*" >> "$LOG" 2>/dev/null; }

# 用户正在用 Play → 不干扰
FG=$(dumpsys activity activities 2>/dev/null | grep -m1 -E "topResumedActivity|mResumedActivity" | sed -n "s/.*u[0-9]* \([a-zA-Z0-9_.]*\)\/.*/\1/p")
case "$FG" in
    com.android.vending*) exit 0 ;;
esac

# 有任何 vending 进程就压掉
PIDS=$(pgrep -f "$PLAY" 2>/dev/null)
if [ -n "$PIDS" ]; then
    TOTAL=0
    for p in $PIDS; do
        R=$(ps -o RSS= -p "$p" 2>/dev/null | tr -d ' ')
        [ -n "$R" ] && TOTAL=$(( TOTAL + R ))
    done
    # 用 am force-stop 比 kill 更彻底（会清任务栈）
    su -c "am force-stop $PLAY" 2>/dev/null || pkill -f "$PLAY" 2>/dev/null
    N=$(cat "$KILLED" 2>/dev/null || echo 0)
    echo $(( N + 1 )) > "$KILLED"
    log "压制 Play 商店 (${TOTAL}KB, 累计 $(( N + 1 )) 次)"
fi
exit 0
