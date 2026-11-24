#!/system/bin/sh
# zram 压缩算法 + 容量调整
# 用法: zram-algo.sh <lz4|zstd> [容量GB]
# ⚠️ 本机内核(Neko-CL 5.4)在 reset 之后必须 mkswap，否则 swapon 报 EINVAL
# ⚠️ Android sh 的 $(( )) 是 32 位，超过 2GB 的字节数必须用 awk 算

TARGET="$1"
SIZE_GB="$2"
LOG=/data/adb/star-fluency/fluency.log
DEV=/sys/block/zram0
ALGO_NODE=$DEV/comp_algorithm

log() { echo "$(date '+%m-%d %H:%M:%S') [zram] $*" >> "$LOG" 2>/dev/null; }
g2b() { awk -v g="$1" 'BEGIN{printf "%.0f", g*1073741824}'; }
b2g() { awk -v b="$1" 'BEGIN{printf "%.0f", b/1073741824}'; }

[ -e "$ALGO_NODE" ] || { log "zram0 不存在"; exit 1; }

CUR=$(sed -n 's/.*\[\([^]]*\)\].*/\1/p' "$ALGO_NODE" 2>/dev/null)
CUR_DS=$(cat "$DEV/disksize" 2>/dev/null)
case "$CUR_DS" in ''|0) CUR_DS=12884901888 ;; esac

if [ -n "$SIZE_GB" ]; then
    NEW_DS=$(g2b "$SIZE_GB")
else
    NEW_DS=$CUR_DS
fi

if [ "$CUR" = "$TARGET" ] && [ "$NEW_DS" = "$CUR_DS" ]; then
    log "已是 $TARGET / $(b2g "$CUR_DS")GB，跳过"
    exit 0
fi

AVAIL=$(cat "$ALGO_NODE" 2>/dev/null)
case "$AVAIL" in
    *"$TARGET"*) : ;;
    *) log "算法 $TARGET 不支持（可用: $AVAIL）"; exit 1 ;;
esac

log "调整 ${CUR}/$(b2g "$CUR_DS")GB -> ${TARGET}/$(b2g "$NEW_DS")GB"
BEFORE=$(cat /proc/swaps | awk '/zram0/{print $4}')

swapoff /dev/block/zram0 2>/dev/null || { log "swapoff 失败，放弃"; exit 1; }
echo 1 > "$DEV/reset" 2>/dev/null
sleep 1

echo "$TARGET" > "$ALGO_NODE" 2>/dev/null
NOW=$(sed -n 's/.*\[\([^]]*\)\].*/\1/p' "$ALGO_NODE" 2>/dev/null)
if [ "$NOW" != "$TARGET" ]; then
    log "写算法失败(读回=$NOW)，回滚"
    echo "$CUR" > "$ALGO_NODE" 2>/dev/null
    echo "$CUR_DS" > "$DEV/disksize" 2>/dev/null
    mkswap /dev/block/zram0 >/dev/null 2>&1
    swapon /dev/block/zram0 2>/dev/null
    exit 1
fi

echo "$NEW_DS" > "$DEV/disksize" 2>/dev/null
mkswap /dev/block/zram0 >/dev/null 2>&1
swapon /dev/block/zram0 2>/dev/null
if [ $? -ne 0 ]; then
    log "swapon 失败，回滚"
    swapoff /dev/block/zram0 2>/dev/null
    echo 1 > "$DEV/reset" 2>/dev/null
    sleep 1
    echo "$CUR" > "$ALGO_NODE" 2>/dev/null
    echo "$CUR_DS" > "$DEV/disksize" 2>/dev/null
    mkswap /dev/block/zram0 >/dev/null 2>&1
    swapon /dev/block/zram0 2>/dev/null
    log "回滚 swapon=$?"
    exit 1
fi

log "成功 -> ${TARGET}/$(b2g "$NEW_DS")GB（原用量 ${BEFORE}KB）"
exit 0
