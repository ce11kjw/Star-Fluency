#!/system/bin/sh
# 轻量 HTTP 服务（端口 18123），handler 为独立脚本
PORT=18123
MODDIR=${0%/*}
MODDIR=${MODDIR%/scripts}
[ -d "$MODDIR/webroot" ] || MODDIR=/data/adb/modules/star_fluency

BB=""
for c in /data/adb/ksu/bin/busybox /data/adb/magisk/busybox /data/adb/ap/bin/busybox; do
    [ -x "$c" ] && { BB="$c"; break; }
done
[ -z "$BB" ] && BB=$(command -v busybox 2>/dev/null)
[ -z "$BB" ] && exit 1

echo "$(date '+%m-%d %H:%M:%S') [http] 启动 :$PORT (MODDIR=$MODDIR)" >> /data/adb/star-fluency/fluency.log 2>/dev/null
exec $BB nc -lk -p $PORT -e "$MODDIR/scripts/http-handler.sh" 2>/dev/null
