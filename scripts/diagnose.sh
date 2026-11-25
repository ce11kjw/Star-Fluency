#!/system/bin/sh
# 一键诊断：回答"为什么卡"
# 用法: diagnose.sh [json|text]

MODE="${1:-json}"
SF_DIR=/data/adb/star-fluency

esc() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g' | tr -d '\n\r' ; }
rd()  { cat "$1" 2>/dev/null | tr -d '\n' | head -c 80 ; }

# ---- 负载 ----
LA=$(cat /proc/loadavg 2>/dev/null | cut -d' ' -f1-3)
CORES=$(nproc 2>/dev/null || echo 8)
LA1=$(echo "$LA" | awk '{print $1}')
LA_PCT=$(awk -v l="$LA1" -v c="$CORES" 'BEGIN{printf "%.0f", (l/c)*100}')

# ---- 内存 ----
MI=$(cat /proc/meminfo)
MEM_TOTAL=$(echo "$MI" | awk '/^MemTotal:/{print $2}')
MEM_AVAIL=$(echo "$MI" | awk '/^MemAvailable:/{print $2}')
MEM_FREE=$(echo "$MI" | awk '/^MemFree:/{print $2}')
SWAP_TOTAL=$(echo "$MI" | awk '/^SwapTotal:/{print $2}')
SWAP_FREE=$(echo "$MI" | awk '/^SwapFree:/{print $2}')
SWAP_USED=$(( SWAP_TOTAL - SWAP_FREE ))
SWAP_PCT=0
[ "$SWAP_TOTAL" -gt 0 ] && SWAP_PCT=$(awk -v u="$SWAP_USED" -v t="$SWAP_TOTAL" 'BEGIN{printf "%.0f", (u/t)*100}')

# ---- zram ----
Z_ALGO=$(sed -n 's/.*\[\([^]]*\)\].*/\1/p' /sys/block/zram0/comp_algorithm 2>/dev/null)
MM=$(cat /sys/block/zram0/mm_stat 2>/dev/null)
Z_ORIG=$(echo "$MM" | awk '{print $1}')
Z_COMP=$(echo "$MM" | awk '{print $2}')
Z_RATIO=0
[ -n "$Z_COMP" ] && [ "$Z_COMP" -gt 0 ] 2>/dev/null && \
    Z_RATIO=$(awk "BEGIN{printf \"%.2f\", ($Z_ORIG+0)/($Z_COMP+0)}")

# ---- 内存压力 ----
PSI_SOME=$(awk '/^some/{print $2}' /proc/pressure/memory 2>/dev/null | sed 's/avg10=//')
PSI_FULL=$(awk '/^full/{print $2}' /proc/pressure/memory 2>/dev/null | sed 's/avg10=//')

# ---- TOP 5 CPU ----
TOP_CPU=$(dumpsys cpuinfo 2>/dev/null | sed -n 's/^  \([0-9.]*\)% \([0-9]*\)\/\([^: ]*\).*/\1\t\2\t\3/p' | awk -F'\t' '$1+0 >= 1.0' | head -5)

# ---- TOP 5 内存 ----
TOP_MEM=$(ps -A -o RSS,NAME 2>/dev/null | sort -rn | head -6 | tail -5)

# ---- 唤醒锁 ----
WK=$(dumpsys power 2>/dev/null | awk '/Wake Locks: size=/{print; exit}' | sed 's/.*size=//')
WK_LIST=$(dumpsys power 2>/dev/null | awk '/Wake Locks:/{f=1;next} f&&/^  [A-Z_]+ /{print;next} f&&!/^  /{exit}' | \
    sed -n 's/.*WORKSOURCE{[0-9]* \([a-zA-Z0-9_.]*\).*/\1/p' | sort | uniq -c | sort -rn | head -3 | \
    awk '{printf "%s(%s) ", $2, $1}')

# ---- 最近 ANR / OOM ----
ANR_CNT=$(logcat -d -b events 2>/dev/null | grep -c "am_anr" 2>/dev/null)
[ -z "$ANR_CNT" ] && ANR_CNT=0
OOM_CNT=$(logcat -d 2>/dev/null | grep -c "lowmemorykiller.*Killing" 2>/dev/null)
[ -z "$OOM_CNT" ] && OOM_CNT=0

# ---- 缓存进程 ----
CACHED=$(dumpsys activity processes 2>/dev/null | grep -c "cached=")

# ---- 温度 ----
TEMP=$(cat /sys/class/power_supply/battery/temp 2>/dev/null)

# ---- 综合诊断结论 ----
# ---- 调度状态 ----
SC_STATE=/data/adb/star-fluency/sched/state
SC_MODE=$(grep '^mode=' "$SC_STATE" 2>/dev/null | cut -d= -f2)
SC_REASON=$(grep '^reason=' "$SC_STATE" 2>/dev/null | cut -d= -f2)
SC_SCENE=$(grep -oE 'name="scene_profile_source">[^<]*' /data/data/com.omarea.vtools/shared_prefs/global.xml 2>/dev/null | sed 's/.*>//')
SC_CLAMP=$(cat /proc/sys/kernel/sched_util_clamp_min 2>/dev/null)
SC_EN=$(grep '^SCHED_ENABLED=' /data/adb/star-fluency/config.conf 2>/dev/null | cut -d= -f2)
CORE_RAW=$(cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null)
[ -z "$CORE_RAW" ] && CORE_RAW=0
CORE_T=$((CORE_RAW / 1000))

JUDGE=""
[ "$LA_PCT" -ge 150 ] && JUDGE="${JUDGE}负载过高(${LA1}/${CORES}核) "
[ "$SWAP_PCT" -ge 70 ] && JUDGE="${JUDGE}Swap用量高(${SWAP_PCT}%) "
[ "$(awk "BEGIN{print ($PSI_FULL+0 > 5)}")" = "1" ] && JUDGE="${JUDGE}内存压力大 "
[ "$OOM_CNT" -gt 3 ] && JUDGE="${JUDGE}近期OOM频繁(${OOM_CNT}次) "
[ "$ANR_CNT" -gt 2 ] && JUDGE="${JUDGE}近期ANR(${ANR_CNT}次) "
[ "$SC_CLAMP" = "1024" ] && JUDGE="${JUDGE}所有任务被当满负载(clamp 1024) "
[ "$CORE_T" -ge 70 ] && JUDGE="${JUDGE}核心温度偏高(${CORE_T}C) "
[ -z "$JUDGE" ] && JUDGE="未发现明显瓶颈"

if [ "$MODE" = "text" ]; then
    echo "====== 系统诊断 ======"
    echo "负载:     $LA  (${LA_PCT}% of ${CORES}核)"
    echo "内存:     可用 $((MEM_AVAIL/1024))MB / 总 $((MEM_TOTAL/1024))MB"
    echo "Swap:     已用 $((SWAP_USED/1024))MB / $((SWAP_TOTAL/1024))MB (${SWAP_PCT}%)"
    echo "Zram:     ${Z_ALGO} 压缩率 ${Z_RATIO}x"
    echo "内存压力: some=${PSI_SOME}% full=${PSI_FULL}%"
    echo "温度:     $((TEMP/10))°C"
    echo "缓存进程: ${CACHED}"
    echo "唤醒锁:   ${WK:-0} 个 ${WK_LIST}"
    echo "最近ANR:  ${ANR_CNT} 次"
    echo "最近OOM:  ${OOM_CNT} 次"
    echo ""
    echo "--- TOP CPU ---"
    echo "$TOP_CPU" | awk -F'\t' '{printf "  %5s%%  %-32s (pid %s)\n", $1, $3, $2}'
    echo "--- TOP 内存 ---"
    echo "$TOP_MEM" | awk '{printf "  %5s MB  %s\n", int($1/1024), $2}'
    echo ""
    echo ">>> 结论: $JUDGE"
    exit 0
fi

# ---- JSON 输出 ----
TOPCPU_JSON="["
FIRST=1
echo "$TOP_CPU" | while IFS='	' read -r pct pid name; do
    [ -z "$pct" ] && continue
    echo "$pct|$pid|$name"
done > /tmp/diag_cpu.txt
while IFS='|' read -r pct pid name; do
    [ -z "$pct" ] && continue
    [ "$FIRST" = "0" ] && TOPCPU_JSON="${TOPCPU_JSON},"
    TOPCPU_JSON="${TOPCPU_JSON}{\"pct\":$pct,\"pid\":${pid:-0},\"name\":\"$(esc "$name")\"}"
    FIRST=0
done < /tmp/diag_cpu.txt
TOPCPU_JSON="${TOPCPU_JSON}]"

TOPMEM_JSON="["
FIRST=1
echo "$TOP_MEM" | while read -r rss name; do
    [ -z "$rss" ] && continue
    echo "$rss|$name"
done > /tmp/diag_mem.txt
while IFS='|' read -r rss name; do
    [ -z "$rss" ] && continue
    [ "$FIRST" = "0" ] && TOPMEM_JSON="${TOPMEM_JSON},"
    TOPMEM_JSON="${TOPMEM_JSON}{\"mb\":$((rss/1024)),\"name\":\"$(esc "$name")\"}"
    FIRST=0
done < /tmp/diag_mem.txt
TOPMEM_JSON="${TOPMEM_JSON}]"

cat <<JSONEOF
{
  "load":{"la":"$(esc "$LA")","cores":$CORES,"pct":$LA_PCT},
  "mem":{"avail":${MEM_AVAIL:-0},"total":${MEM_TOTAL:-0},"free":${MEM_FREE:-0}},
  "swap":{"used":$SWAP_USED,"total":$SWAP_TOTAL,"pct":$SWAP_PCT},
  "zram":{"algo":"$(esc "$Z_ALGO")","ratio":$Z_RATIO},
  "psi":{"some":"$(esc "$PSI_SOME")","full":"$(esc "$PSI_FULL")"},
  "temp":$(( ${TEMP:-0} / 10 )),
  "cached":${CACHED:-0},
  "wakelocks":{"count":"$(esc "${WK:-0}")","top":"$(esc "$WK_LIST")"},
  "anr":$ANR_CNT,
  "oom":$OOM_CNT,
  "topCpu":$TOPCPU_JSON,
  "topMem":$TOPMEM_JSON,
  "core_temp":$CORE_T,
  "sched":{"mode":"$(esc "$SC_MODE")","reason":"$(esc "$SC_REASON")","scene":"$(esc "$SC_SCENE")","clamp":"$(esc "$SC_CLAMP")","enabled":"$(esc "$SC_EN")"},
  "judge":"$(esc "$JUDGE")"
}
JSONEOF
exit 0
