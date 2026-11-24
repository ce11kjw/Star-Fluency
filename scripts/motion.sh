#!/system/bin/sh
# 动图修复（原 MotionFix 逻辑，路径改为本模块）

MODDIR=${0%/*}
MODDIR=${MODDIR%/scripts}
STATE=/data/adb/star-fluency/motion
MFDIR=$MODDIR/scripts
mkdir -p "$STATE" 2>/dev/null
chmod 700 "$STATE" 2>/dev/null

CONF=$STATE/config.conf

getconf() {
    local k="$1" d="$2" v=""
    [ -f "$CONF" ] && v=$(grep -E "^${k}=" "$CONF" 2>/dev/null | tail -1 | cut -d= -f2-)
    [ -z "$v" ] && v="$d"
    echo "$v"
}

# 初始化配置
init_conf() {
    [ -f "$CONF" ] && return 0
    cat > "$CONF" <<'EOFCONF'
CAMERA_DIR=/sdcard/DCIM/Camera
PENDING_DIR=/data/user/0/com.android.camera/files/livephoto_pending
BACKUP=1
CLEANUP=1
AUTO=1
LOG=/data/adb/star-fluency/motion/motion.log
EOFCONF
    chmod 600 "$CONF" 2>/dev/null
}

# 迁移旧 MotionFix 配置（首次）
migrate_old() {
    [ -f "$STATE/migrated" ] && return 0
    if [ -f /data/adb/motionfix/config.conf ]; then
        cp -a /data/adb/motionfix/config.conf "$CONF" 2>/dev/null
        sed -i 's|^LOG=.*|LOG=/data/adb/star-fluency/motion/motion.log|' "$CONF" 2>/dev/null
        # 迁移备份
        [ -d /data/adb/motionfix/backup ] && cp -a /data/adb/motionfix/backup "$STATE/" 2>/dev/null
        [ -f /data/adb/motionfix/motionfix.log ] && cp -a /data/adb/motionfix/motionfix.log "$STATE/motion.log" 2>/dev/null
        # 迁移 auto 开关
        [ -f /data/adb/motionfix/auto.on ] && touch "$STATE/auto.on" 2>/dev/null
    fi
    touch "$STATE/migrated" 2>/dev/null
}

init_conf
migrate_old

case "$1" in
    run)
        sh "$MFDIR/fixall.sh" "${2:-}"
        ;;
    dry)
        sh "$MFDIR/fixall.sh" --dry
        ;;
    auto-on)
        touch "$STATE/auto.on" 2>/dev/null
        sed -i 's|^AUTO=.*|AUTO=1|' "$CONF" 2>/dev/null
        echo "auto on"
        ;;
    auto-off)
        rm -f "$STATE/auto.on" 2>/dev/null
        sed -i 's|^AUTO=.*|AUTO=0|' "$CONF" 2>/dev/null
        # 杀掉轮询
        for p in $(pgrep -f "fixall.sh" 2>/dev/null); do
            [ "$p" != "$$" ] && kill "$p" 2>/dev/null
        done
        echo "auto off"
        ;;
    status)
        echo "AUTO=$(getconf AUTO 0)"
        echo "CLEANUP=$(getconf CLEANUP 1)"
        echo "BACKUP=$(getconf BACKUP 1)"
        echo "AUTO_ON=$([ -f "$STATE/auto.on" ] && echo 1 || echo 0)"
        P=$(getconf PENDING_DIR /data/user/0/com.android.camera/files/livephoto_pending)
        N=$(ls "$P"/microvideo_*.mp4 2>/dev/null | wc -l)
        echo "PENDING=$N"
        T=$(ls "$STATE"/backup/*.jpg 2>/dev/null | wc -l)
        echo "BACKUP_COUNT=$T"
        ;;
    log)
        tail -n "${2:-50}" "$(getconf LOG "$STATE/motion.log")" 2>/dev/null
        ;;
    clean-log)
        : > "$(getconf LOG "$STATE/motion.log")" 2>/dev/null
        echo ok
        ;;
    get|set)
        # 保留扩展
        ;;
    *)
        echo "用法: motion.sh {run|dry|auto-on|auto-off|status|log [n]|clean-log}"
        ;;
esac
