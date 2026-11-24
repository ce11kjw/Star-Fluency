#!/system/bin/sh
# 记录原厂值（只记录一次）
SF_DIR=/data/adb/star-fluency
SF_STOCK=$SF_DIR/stock.txt
mkdir -p "$SF_DIR" 2>/dev/null
[ -f "$SF_STOCK" ] && exit 0

plain() {
    local key="$1" node="$2"
    [ -e "$node" ] || return 0
    local v
    v=$(cat "$node" 2>/dev/null | tr -d '\n' | head -c 120)
    [ -z "$v" ] && return 0
    echo "${key}=${v}" >> "$SF_STOCK"
}

# 取 [xxx] 里的当前值
bracketed() {
    local key="$1" node="$2"
    [ -e "$node" ] || return 0
    local v
    v=$(sed -n 's/.*\[\([^]]*\)\].*/\1/p' "$node" 2>/dev/null | head -1)
    [ -z "$v" ] && return 0
    echo "${key}=${v}" >> "$SF_STOCK"
}

plain swappiness /proc/sys/vm/swappiness
plain vfs_cache_pressure /proc/sys/vm/vfs_cache_pressure
plain dirty_ratio /proc/sys/vm/dirty_ratio
plain dirty_bg_ratio /proc/sys/vm/dirty_background_ratio
plain min_free_kbytes /proc/sys/vm/min_free_kbytes
bracketed zram_comp /sys/block/zram0/comp_algorithm
plain cpu0_min /sys/devices/system/cpu/cpufreq/policy0/scaling_min_freq
plain cpu4_min /sys/devices/system/cpu/cpufreq/policy4/scaling_min_freq
plain cpu7_min /sys/devices/system/cpu/cpufreq/policy7/scaling_min_freq
plain cpu0_gov /sys/devices/system/cpu/cpufreq/policy0/scaling_governor
plain cpu4_gov /sys/devices/system/cpu/cpufreq/policy4/scaling_governor
plain cpu7_gov /sys/devices/system/cpu/cpufreq/policy7/scaling_governor
for d in sda sdb sdc sdd sde sdf; do
    [ -e "/sys/block/$d/queue/scheduler" ] || continue
    bracketed "${d}_sched" "/sys/block/$d/queue/scheduler"
    plain "${d}_readahead" "/sys/block/$d/queue/read_ahead_kb"
done
chmod 600 "$SF_STOCK" 2>/dev/null
exit 0
