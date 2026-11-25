#!/system/bin/sh
# status.sh 的带缓存包装：默认 20 秒内复用上次结果
# 用法: status-cache.sh [max_age_seconds]
MODDIR=${MODDIR:-/data/adb/modules/star_fluency}
SF_DIR=/data/adb/star-fluency
CACHE=$SF_DIR/status.cache
AGE=${1:-60}
mkdir -p "$SF_DIR" 2>/dev/null

if [ -s "$CACHE" ]; then
    MT=$(stat -c %Y "$CACHE" 2>/dev/null)
    NOW=$(date +%s)
    if [ -n "$MT" ] && [ $((NOW - MT)) -le "$AGE" ]; then
        cat "$CACHE"
        exit 0
    fi
fi

OUT=$(sh "$MODDIR/scripts/status.sh" 2>/dev/null)
if [ -n "$OUT" ]; then
    printf '%s\n' "$OUT" > "$CACHE.tmp" 2>/dev/null && mv "$CACHE.tmp" "$CACHE" 2>/dev/null
    printf '%s\n' "$OUT"
else
    # 采集失败时退回旧缓存，避免前端空白
    [ -s "$CACHE" ] && cat "$CACHE"
fi
