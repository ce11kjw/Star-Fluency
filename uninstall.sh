#!/system/bin/sh
# 卸载：还原所有原厂设置

SF_DIR=/data/adb/star-fluency
MODDIR=${0%/*}

echo "=== Star-Fluency 卸载 ==="

# 1. 还原调优参数
STOCK=$SF_DIR/stock.txt
if [ -f "$STOCK" ]; then
    echo "-- 还原内核参数 --"
    for k in swappiness vfs_cache_pressure dirty_ratio dirty_bg_ratio min_free_kbytes; do
        v=$(grep -E "^${k}=" "$STOCK" 2>/dev/null | cut -d= -f2)
        node=""
        case "$k" in
            swappiness)            node=/proc/sys/vm/swappiness ;;
            vfs_cache_pressure)    node=/proc/sys/vm/vfs_cache_pressure ;;
            dirty_ratio)           node=/proc/sys/vm/dirty_ratio ;;
            dirty_bg_ratio)        node=/proc/sys/vm/dirty_background_ratio ;;
            min_free_kbytes)       node=/proc/sys/vm/min_free_kbytes ;;
        esac
        [ -n "$v" ] && [ -e "$node" ] && echo "$v" > "$node" 2>/dev/null && echo "  $k = $v"
    done

    echo "-- 还原 CPU 频率 --"
    for p in 0 4 7; do
        v=$(grep -E "^cpu${p}_min=" "$STOCK" 2>/dev/null | cut -d= -f2)
        [ -n "$v" ] && echo "$v" > "/sys/devices/system/cpu/cpufreq/policy$p/scaling_min_freq" 2>/dev/null && echo "  policy$p min = $v"
        g=$(grep -E "^cpu${p}_gov=" "$STOCK" 2>/dev/null | cut -d= -f2)
        [ -n "$g" ] && echo "$g" > "/sys/devices/system/cpu/cpufreq/policy$p/scaling_governor" 2>/dev/null
    done

    echo "-- 还原 IO 调度 --"
    for d in sda sdb sdc sdd sde sdf; do
        s=$(grep -E "^${d}_sched=" "$STOCK" 2>/dev/null | cut -d= -f2)
        [ -n "$s" ] && echo "$s" > "/sys/block/$d/queue/scheduler" 2>/dev/null
        r=$(grep -E "^${d}_readahead=" "$STOCK" 2>/dev/null | cut -d= -f2)
        [ -n "$r" ] && echo "$r" > "/sys/block/$d/queue/read_ahead_kb" 2>/dev/null
    done

    echo "-- 还原 zram 算法 --"
    z=$(grep -E "^zram_comp=" "$STOCK" 2>/dev/null | cut -d= -f2)
    cur=$(sed -n 's/.*\[\([^]]*\)\].*/\1/p' /sys/block/zram0/comp_algorithm 2>/dev/null)
    if [ -n "$z" ] && [ "$z" != "$cur" ]; then
        sh "$MODDIR/scripts/zram-algo.sh" "$z" 2>/dev/null && echo "  zram = $z"
    fi
else
    echo "-- 无原厂值记录，跳过 --"
fi

# 2. 还原精简项
echo "-- 还原精简项 --"
sh "$MODDIR/scripts/trim.sh" revert pa 2>/dev/null
sh "$MODDIR/scripts/trim.sh" revert gms 2>/dev/null
sh "$MODDIR/scripts/trim.sh" revert anim 2>/dev/null

# 3. 停掉后台任务
echo "-- 停止后台任务 --"
touch "$SF_DIR/motion/auto.on.off" 2>/dev/null
rm -f "$SF_DIR/motion/auto.on" 2>/dev/null

echo "=== 完成，重启后彻底生效 ==="
echo "数据保留在: $SF_DIR"
echo "如需彻底清除: rm -rf $SF_DIR"
