#!/system/bin/sh
# Star-Fluency 调优应用
# 用法: apply.sh [balance|smooth|stock]

MODDIR=${0%/*}
MODDIR=${MODDIR%/scripts}
SF_DIR=/data/adb/star-fluency
SF_CONF=$SF_DIR/config.conf
SF_STOCK=$SF_DIR/stock.txt
LOG=$SF_DIR/fluency.log
mkdir -p "$SF_DIR" 2>/dev/null

log() { echo "$(date '+%m-%d %H:%M:%S') [apply] $*" >> "$LOG" 2>/dev/null; }

stock_of() {
    [ -f "$SF_STOCK" ] && grep -E "^${1}=" "$SF_STOCK" 2>/dev/null | tail -1 | cut -d= -f2- | tr -d '[]'
}

w() {
    local node="$1" val="$2" name="$3"
    [ -e "$node" ] || { log "SKIP $name (节点不存在)"; return; }
    local cur; cur=$(cat "$node" 2>/dev/null)
    [ "$cur" = "$val" ] && return
    if echo "$val" > "$node" 2>/dev/null; then
        local now; now=$(cat "$node" 2>/dev/null)
        [ "$now" = "$val" ] && log "OK   $name: $cur -> $val" || log "FAIL $name (读回='$now')"
    else
        log "FAIL $name (写入被拒)"
    fi
}

MODE="${1:-}"
[ -z "$MODE" ] && MODE=$(grep -E '^PROFILE=' "$SF_CONF" 2>/dev/null | cut -d= -f2)
[ -z "$MODE" ] && MODE=balance

log "===== 应用档位: $MODE ====="

case "$MODE" in
  balance)
    SWAPPINESS=60; VFS=60; DIRTY=15; DIRTYBG=8; MINFREE=16384
    CPU0_MIN=595200; CPU4_MIN=710400; CPU7_MIN=844800
    GOV=schedutil; SCHED=mq-deadline; READAHEAD=1024; ZRAM=zstd; ZRAM_GB=16; GPU_IDLE=40
    ;;
  smooth)
    SWAPPINESS=80; VFS=50; DIRTY=12; DIRTYBG=6; MINFREE=32768
    CPU0_MIN=691200; CPU4_MIN=960000; CPU7_MIN=1075200
    GOV=schedutil; SCHED=none; READAHEAD=2048; ZRAM=zstd; ZRAM_GB=16; GPU_IDLE=30
    ;;
  stock)
    SWAPPINESS=$(stock_of swappiness); VFS=$(stock_of vfs_cache_pressure)
    DIRTY=$(stock_of dirty_ratio); DIRTYBG=$(stock_of dirty_bg_ratio)
    MINFREE=$(stock_of min_free_kbytes)
    CPU0_MIN=$(stock_of cpu0_min); CPU4_MIN=$(stock_of cpu4_min); CPU7_MIN=$(stock_of cpu7_min)
    GOV=$(stock_of cpu0_gov); SCHED=$(stock_of sda_sched); READAHEAD=$(stock_of sda_readahead)
    ZRAM=$(stock_of zram_comp)
    [ -z "$SWAPPINESS" ] && SWAPPINESS=100
    [ -z "$VFS" ] && VFS=100
    [ -z "$DIRTY" ] && DIRTY=20
    [ -z "$DIRTYBG" ] && DIRTYBG=10
    [ -z "$MINFREE" ] && MINFREE=13502
    [ -z "$CPU0_MIN" ] && CPU0_MIN=595200
    [ -z "$CPU4_MIN" ] && CPU4_MIN=710400
    [ -z "$CPU7_MIN" ] && CPU7_MIN=844800
    [ -z "$GOV" ] && GOV=schedutil
    [ -z "$SCHED" ] && SCHED=bfq
    [ -z "$READAHEAD" ] && READAHEAD=512
    [ -z "$ZRAM" ] && ZRAM=lz4
    ZRAM_GB=12; GPU_IDLE=80
    ;;
  *)
    log "未知档位: $MODE"
    exit 1
    ;;
esac

# ---- 内存 ----
w /proc/sys/vm/swappiness "$SWAPPINESS" swappiness
w /proc/sys/vm/vfs_cache_pressure "$VFS" vfs_cache_pressure
w /proc/sys/vm/dirty_ratio "$DIRTY" dirty_ratio
w /proc/sys/vm/dirty_background_ratio "$DIRTYBG" dirty_background_ratio
w /proc/sys/vm/min_free_kbytes "$MINFREE" min_free_kbytes

# ---- CPU 频率下限 / governor ----
for p in 0 4 7; do
    node=/sys/devices/system/cpu/cpufreq/policy$p
    [ -e "$node" ] || continue
    case $p in
        0) MINV=$CPU0_MIN ;;
        4) MINV=$CPU4_MIN ;;
        7) MINV=$CPU7_MIN ;;
    esac
    w "$node/scaling_governor" "$GOV" "policy$p governor"
    [ -n "$MINV" ] && w "$node/scaling_min_freq" "$MINV" "policy$p min_freq"
done

# ---- IO ----
for d in sda sdb sdc sdd sde sdf; do
    [ -e "/sys/block/$d/queue/scheduler" ] || continue
    if grep -q "$SCHED" "/sys/block/$d/queue/scheduler" 2>/dev/null; then
        echo "$SCHED" > "/sys/block/$d/queue/scheduler" 2>/dev/null
        NOWSCHED=$(sed -n "s/.*\[\([^]]*\)\].*/\1/p" "/sys/block/$d/queue/scheduler" 2>/dev/null)
        if [ "$NOWSCHED" = "$SCHED" ]; then log "OK   ${d}_sched -> $SCHED"; else log "FAIL ${d}_sched (读回=$NOWSCHED)"; fi
    fi
    w "/sys/block/$d/queue/read_ahead_kb" "$READAHEAD" "${d}_readahead"
done

# ---- GPU 降频延迟 ----
[ -e /sys/class/kgsl/kgsl-3d0/idle_timer ] && w /sys/class/kgsl/kgsl-3d0/idle_timer "$GPU_IDLE" gpu_idle_timer

# ---- zram 算法 + 容量 ----
CUR_ALGO=$(sed -n 's/.*\[\([^]]*\)\].*/\1/p' /sys/block/zram0/comp_algorithm 2>/dev/null)
CUR_DS=$(cat /sys/block/zram0/disksize 2>/dev/null)
WANT_DS=$(awk -v g="$ZRAM_GB" 'BEGIN{printf "%.0f", g*1073741824}')
if [ "$CUR_ALGO" != "$ZRAM" ] || [ "$CUR_DS" != "$WANT_DS" ]; then
    sh "$MODDIR/scripts/zram-algo.sh" "$ZRAM" "$ZRAM_GB"
else
    log "zram 已是 $ZRAM / ${ZRAM_GB}GB"
fi

# ---- 精简项（第一组）----
for k in pa gms anim play ner; do
    v=$(grep -E "^TRIM_$(echo $k | tr a-z A-Z)=" "$SF_CONF" 2>/dev/null | cut -d= -f2)
    [ -z "$v" ] && v=0
    if [ "$v" = "1" ]; then
        sh "$MODDIR/scripts/trim.sh" apply "$k" 2>/dev/null
    else
        sh "$MODDIR/scripts/trim.sh" revert "$k" 2>/dev/null
    fi
done

# ---- 精简项（第二组：商店/内容中心/缓存/GMS 组件）----
for k in market content cached gms; do
    v=$(grep -E "^TRIM_$(echo $k | tr a-z A-Z)=" "$SF_CONF" 2>/dev/null | cut -d= -f2)
    [ -z "$v" ] && v=0
    if [ "$v" = "1" ]; then
        sh "$MODDIR/scripts/trim2.sh" apply "$k" 2>/dev/null
    else
        sh "$MODDIR/scripts/trim2.sh" revert "$k" 2>/dev/null
    fi
done

# ---- 记录档位 ----
if [ "$MODE" != "stock" ]; then
    if grep -q '^PROFILE=' "$SF_CONF" 2>/dev/null; then
        sed -i "s|^PROFILE=.*|PROFILE=$MODE|" "$SF_CONF" 2>/dev/null
    else
        echo "PROFILE=$MODE" >> "$SF_CONF"
    fi
fi

log "===== 完成: $MODE ====="
exit 0
