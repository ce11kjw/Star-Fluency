#!/system/bin/sh
# 模块按钮：显示状态摘要

SF_DIR=/data/adb/star-fluency
ALGO=$(sed -n 's/.*\[\([^]]*\)\].*/\1/p' /sys/block/zram0/comp_algorithm 2>/dev/null)
PROF=$(grep -E '^PROFILE=' "$SF_DIR/config.conf" 2>/dev/null | cut -d= -f2)
[ -z "$PROF" ] && PROF=balance

echo "【Star-Fluency】"
echo "档位: $PROF"
echo "zram: $ALGO"
echo "swappiness: $(cat /proc/sys/vm/swappiness)"
echo "IO: $(sed -n 's/.*\[\([^]]*\)\].*/\1/p' /sys/block/sda/queue/scheduler)"
echo "可用内存: $(awk '/MemAvailable/{printf "%d", $2/1024}' /proc/meminfo) MB"
echo "Swap: $(awk '/SwapTotal|SwapFree/{printf "%d/%d ", $2/1024, $2/1024}' /proc/meminfo)"
