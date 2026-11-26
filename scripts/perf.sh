#!/system/bin/sh
# 性能辅助（保留实际在用的三项）
#   1) 关键进程绑小核  2) 启动加速  3) 每周 fstrim
# 已移除：CPU 上限 / GPU 上限 / 充电直通 / 热控对抗（本机定频模型下无效，UI 已删）
# 用法: perf.sh tick|status|boost|trim|watch|fg|aff-on|aff-off|lboost-on|lboost-off

MODDIR=${MODDIR:-/data/adb/modules/star_fluency}
SF=/data/adb/star-fluency
CONF=$SF/config.conf
LOG=$SF/fluency.log
PD=$SF/perf
ST=$PD/state
CPU=${SF_CPU:-/sys/devices/system/cpu/cpufreq}
USB=${SF_USB:-/sys/class/power_supply/usb}
TOPAPP=/dev/cpuset/top-app/cgroup.procs
mkdir -p "$PD" 2>/dev/null

log() { echo "$(date '+%m-%d %H:%M:%S') [perf] $*" >> "$LOG" 2>/dev/null; }
conf() { awk -F= -v k="$1" '$1==k{v=$2} END{print v}' "$CONF" 2>/dev/null; }
setk() { if grep -q "^$1=" "$CONF" 2>/dev/null; then sed -i "s|^$1=.*|$1=$2|" "$CONF"; else echo "$1=$2" >> "$CONF"; fi; }
stget() { awk -F= -v k="$1" '$1==k{v=$2} END{print v}' "$ST" 2>/dev/null; }
stset() { touch "$ST" 2>/dev/null; sed -i "/^$1=/d" "$ST" 2>/dev/null; echo "$1=$2" >> "$ST"; }
rd() { cat "$1" 2>/dev/null; }
soc_temp() { T=$(rd /sys/class/thermal/thermal_zone0/temp); [ -z "$T" ] && T=0; echo $((T / 1000)); }

aff_apply() {
    command -v taskset >/dev/null 2>&1 || return 1
    N=0
    for n in logd kswapd0 kcompactd0; do
        for p in $(pidof $n 2>/dev/null); do
            taskset -p 7 "$p" >/dev/null 2>&1 && N=$((N + 1))
        done
    done
    stset aff_pids "$N"
}

boost_now() {
    [ "$(conf PERF_LBOOST)" = "0" ] && return 0
    M0=$(rd $CPU/policy0/scaling_min_freq); M4=$(rd $CPU/policy4/scaling_min_freq); M7=$(rd $CPU/policy7/scaling_min_freq)
    echo 1401000 > $CPU/policy0/scaling_min_freq 2>/dev/null
    echo 1766400 > $CPU/policy4/scaling_min_freq 2>/dev/null
    echo 1785600 > $CPU/policy7/scaling_min_freq 2>/dev/null
    sleep 1.2
    [ -n "$M0" ] && echo "$M0" > $CPU/policy0/scaling_min_freq 2>/dev/null
    [ -n "$M4" ] && echo "$M4" > $CPU/policy4/scaling_min_freq 2>/dev/null
    [ -n "$M7" ] && echo "$M7" > $CPU/policy7/scaling_min_freq 2>/dev/null
}

fg_pkg() {
    for p in $(cat "$TOPAPP" 2>/dev/null | head -20); do
        C=$(tr -d '\0' < /proc/$p/cmdline 2>/dev/null | head -c 80)
        case "$C" in
            *.*)
                case "$C" in *system_server*|*surfaceflinger*|*android.*) continue ;; esac
                echo "$C"; return ;;
        esac
    done
}

case "$1" in
  tick|apply)
    NOW=$(date +%s)
    if [ "$(conf PERF_AFF)" != "0" ]; then
        LAST=$(stget aff_ts); [ -z "$LAST" ] && LAST=0
        [ $((NOW - LAST)) -ge 300 ] && { aff_apply; stset aff_ts "$NOW"; }
    fi
    LASTT=$(stget trim_ts); [ -z "$LASTT" ] && LASTT=0
    if [ $((NOW - LASTT)) -ge 604800 ] && command -v fstrim >/dev/null 2>&1; then
        ( fstrim /data >/dev/null 2>&1; fstrim /cache >/dev/null 2>&1; log "fstrim 完成" ) &
        stset trim_ts "$NOW"
    fi
    ;;
  status)
    echo "aff_on=$(conf PERF_AFF)"
    echo "aff_pids=$(stget aff_pids)"
    echo "lboost=$(conf PERF_LBOOST)"
    echo "fg=$(stget fg)"
    echo "soc_temp=$(soc_temp)"
    echo "trim_ts=$(stget trim_ts)"
    ;;
  boost)  boost_now ;;
  trim)   fstrim /data 2>/dev/null; fstrim /cache 2>/dev/null; stset trim_ts "$(date +%s)"; echo "fstrim 完成" ;;
  fg)     fg_pkg ;;
  aff-on)  setk PERF_AFF 1; aff_apply; stset aff_ts "$(date +%s)" ;;
  aff-off) setk PERF_AFF 0; echo "绑核 → 关闭" ;;
  lboost-on)  setk PERF_LBOOST 1; echo "启动加速 → 开" ;;
  lboost-off) setk PERF_LBOOST 0; echo "启动加速 → 关" ;;
  watch)
    while true; do
        sleep 1.5
        [ "$(rd $USB/online)" = "1" ] && continue
        F=$(fg_pkg)
        [ -z "$F" ] && continue
        if [ "$F" != "$(stget fg)" ]; then
            stset fg "$F"
            boost_now
        fi
    done
    ;;
  *) echo "用法: perf.sh tick|status|boost|trim|watch|fg|aff-on|aff-off|lboost-on|lboost-off" ;;
esac
exit 0
