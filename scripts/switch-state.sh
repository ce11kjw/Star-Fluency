#!/system/bin/sh
# 开关状态快取：只输出开关相关字段，目标 < 200ms
# 系统读（appops / settings）带 30s 缓存，UI 切换后立即删除缓存文件即可刷新
SF=/data/adb/star-fluency
CONF=$SF/config.conf
CACHE=$SF/swstate.cache
TTL=${SWSTATE_TTL:-30}

now=$(date +%s)
mt=$(stat -c %Y "$CACHE" 2>/dev/null)
if [ -z "$mt" ] || [ $((now - mt)) -gt "$TTL" ]; then
    {
        for kv in pa:com.miui.personalassistant gms:com.google.android.gms play:com.android.vending \
                  market:com.xiaomi.market content:com.miui.contentextension; do
            n=${kv%%:*}; p=${kv#*:}
            s=$(appops get "$p" RUN_IN_BACKGROUND 2>/dev/null | awk '{print $NF; exit}')
            [ "$s" = "ignore" ] || s=allow
            echo "$n=$s"
        done
        echo "anim=$(settings get global window_animation_scale 2>/dev/null)"
        echo "cachedraw=$(settings get global activity_manager_constants 2>/dev/null)"
    } > "$CACHE.tmp" 2>/dev/null
    mv "$CACHE.tmp" "$CACHE" 2>/dev/null
fi

pa=allow; gms=allow; play=allow; market=allow; content=allow
anim=""; cachedraw=""
[ -f "$CACHE" ] && . "$CACHE"

case "$anim" in
    0|0.0|0.5|0.25) ;;
    *) anim=1 ;;
esac
cached=$(echo "$cachedraw" | sed -n 's/.*max_cached_processes=\([0-9]*\).*/\1/p')
[ -z "$cached" ] && cached=0

# 配置项（一次 read 循环，无 fork）
while IFS='=' read -r k v; do
    case "$k" in
        CAM_IDLE_KILL) CAM=$v ;;
        APPBRAND_IDLE) AB=$v ;;
        AUTO_SCENE) ASC=$v ;;
        AUTO_TEMP) ATP=$v ;;
    esac
done < "$CONF"

MOTION=0
[ -f "$SF/motion/auto.on" ] && MOTION=1
SLIM=0
[ -f "$SF/gms_slimmed" ] && SLIM=1

echo "pa=$pa"
echo "gms=$gms"
echo "play=$play"
echo "market=$market"
echo "content=$content"
echo "anim=$anim"
echo "cached=$cached"
echo "cam=${CAM:-0}"
echo "ab=${AB:-0}"
echo "auto=$MOTION"
echo "scene=${ASC:-0}"
echo "temp=${ATP:-0}"
echo "gms_slim=$SLIM"
