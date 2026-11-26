#!/system/bin/sh
# status.sh 的带缓存包装
# 修复：缓存期内改了配置（开关），页面会继续读到旧状态 → 看起来"开了又自己关"。
# 现在只要下列任一文件比缓存新，就立刻重建缓存。
MODDIR=${MODDIR:-/data/adb/modules/star_fluency}
SF_DIR=/data/adb/star-fluency
CACHE=$SF_DIR/status.cache
AGE=${1:-20}
mkdir -p "$SF_DIR" 2>/dev/null

newer_than() {
    [ -e "$1" ] || return 1
    M=$(stat -c %Y "$1" 2>/dev/null) || return 1
    [ -n "$M" ] && [ "$M" -ge "$2" ]
}

if [ -s "$CACHE" ]; then
    MT=$(stat -c %Y "$CACHE" 2>/dev/null)
    NOW=$(date +%s)
    if [ -n "$MT" ] && [ $((NOW - MT)) -le "$AGE" ]; then
        STALE=0
        newer_than "$SF_DIR/config.conf" "$MT" && STALE=1
        newer_than "$SF_DIR/charge/state" "$MT" && STALE=1
        newer_than "$SF_DIR/sched/state" "$MT" && STALE=1
        newer_than "$SF_DIR/motion/auto.on" "$MT" && STALE=1
        newer_than "$SF_DIR/whitelist.txt" "$MT" && STALE=1
        [ "$STALE" = "0" ] && { cat "$CACHE"; exit 0; }
    fi
fi

OUT=$(sh "$MODDIR/scripts/status.sh" 2>/dev/null)
if [ -n "$OUT" ]; then
    printf '%s\n' "$OUT" > "$CACHE.tmp" 2>/dev/null && mv "$CACHE.tmp" "$CACHE" 2>/dev/null
    printf '%s\n' "$OUT"
else
    [ -s "$CACHE" ] && cat "$CACHE"
fi
