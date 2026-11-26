#!/system/bin/sh
# 性能上限与硬件开关
#   CPU/GPU 上限（eco/balance/perf）、充电直通、热控对抗、关键进程绑核、启动加速、每周 fstrim
# 用法: perf.sh tick|status|restore|boost|trim|watch|fg|cap-on|cap-off|cap-level X|gpu-*|hot-*|aff-*|lboost-*|chgfull-*

MODDIR=${MODDIR:-/data/adb/modules/star_fluency}
SF=/data/adb/star-fluency
CONF=$SF/config.conf
LOG=$SF/fluency.log
PD=$SF/perf
ST=$PD/state
CPU=${SF_CPU:-/sys/devices/system/cpu/cpufreq}
G=${SF_G:-/sys/class/kgsl/kgsl-3d0}
USB=${SF_USB:-/sys/class/power_supply/usb}
TOPAPP=/dev/cpuset/top-app/cgroup.procs
mkdir -p "$PD" 2>/dev/null

log() { echo "$(date '+%m-%d %H:%M:%S') [perf] $*" >> "$LOG" 2>/dev/null; }
conf() { awk -F= -v k="$1" '$1==k{v=$2} END{print v}' "$CONF" 2>/dev/null; }
setk() { if grep -q "^$1=" "$CONF" 2>/dev/null; then sed -i "s|^$1=.*|$1=$2|" "$CONF"; else echo "$1=$2" >> "$CONF"; fi; }
stget() { awk -F= -v k="$1" '$1==k{v=$2} END{print v}' "$ST" 2>/dev/null; }
stset() { touch "$ST" 2>/dev/null; sed -i "/^$1=/d" "$ST" 2>/dev/null; echo "$1=$2" >> "$ST"; }
rd() { cat "$1" 2>/dev/null; }
hw_max() { rd $CPU/policy$1/cpuinfo_max_freq; }
charging() { [ "$(rd $USB/online)" = "1" ]; }
soc_temp() { T=$(rd /sys/class/thermal/thermal_zone0/temp); [ -z "$T" ] && T=0; echo $((T / 1000)); }

cap_set() {
    case "$1" in
        eco)     C0=1401000; C4=1555200; C7=1785600 ;;
        balance) C0=1804800; C4=1996800; C7=2380800 ;;
        perf)    C0=1804800; C4=2419200; C7=2841600 ;;
        *)       C0=0; C4=0; C7=0 ;;
    esac
}
cap_apply() {
    LV=$(conf PERF_CAP_LEVEL); [ -z "$LV" ] && LV=balance
    cap_set "$LV"
    # Scene 在线配置会把 min 锁成等于 max，开上限会把频率锁死（已踩过一次）
    SS=$(grep -o 'name="scene_profile_source">[^<]*' /data/data/com.omarea.vtools/shared_prefs/global.xml 2>/dev/null | sed 's/.*>//')
    if [ "$SS" = "SOURCE_SCENE_ONLINE" ] || [ "$SS" = "SOURCE_SCENE_ACTIVE" ] || [ "$SS" = "SOURCE_SCENE_CONSERVATIVE" ]; then
        log "跳过 CPU 上限：Scene 在线配置会锁频，请先把 Scene 配置源换成 Unofficial"
        stset cap_lvl "blocked-by-scene"
        return 0
    fi
    [ "$C0" = "0" ] && return 0
    [ -z "$(stget cap_orig0)" ] && { stset cap_orig0 "$(rd $CPU/policy0/scaling_max_freq)"; stset cap_orig4 "$(rd $CPU/policy4/scaling_max_freq)"; stset cap_orig7 "$(rd $CPU/policy7/scaling_max_freq)"; }
    H0=$(hw_max 0); H4=$(hw_max 4); H7=$(hw_max 7)
    [ -n "$H0" ] && [ "$C0" -gt "$H0" ] && C0=$H0
    [ -n "$H4" ] && [ "$C4" -gt "$H4" ] && C4=$H4
    [ -n "$H7" ] && [ "$C7" -gt "$H7" ] && C7=$H7
    for kv in "0:$C0" "4:$C4" "7:$C7"; do
        P=${kv%%:*}; V=${kv#*:}
        M=$(rd $CPU/policy$P/scaling_min_freq)
        [ -n "$M" ] && [ "$M" -gt "$V" ] && echo "$V" > $CPU/policy$P/scaling_min_freq 2>/dev/null
        echo "$V" > $CPU/policy$P/scaling_max_freq 2>/dev/null
    done
    stset cap_lvl "$LV"
}
cap_restore() {
    O0=$(stget cap_orig0); O4=$(stget cap_orig4); O7=$(stget cap_orig7)
    [ -z "$O0" ] && O0=$(hw_max 0)
    [ -z "$O4" ] && O4=$(hw_max 4)
    [ -z "$O7" ] && O7=$(hw_max 7)
    [ -n "$O0" ] && echo "$O0" > $CPU/policy0/scaling_max_freq 2>/dev/null
    [ -n "$O4" ] && echo "$O4" > $CPU/policy4/scaling_max_freq 2>/dev/null
    [ -n "$O7" ] && echo "$O7" > $CPU/policy7/scaling_max_freq 2>/dev/null
    stset cap_lvl none
}
gpu_apply() {
    F=$(rd $G/devfreq/available_frequencies)
    [ -z "$F" ] && return 0
    LV=$(conf PERF_GPU_LEVEL); [ -z "$LV" ] && LV=balance
    case "$LV" in
        eco)     T=608000000 ;;
        balance) T=676000000 ;;
        perf)    T=0 ;;
        *)       gpu_restore; return 0 ;;
    esac
    [ -z "$(stget gpu_orig)" ] && stset gpu_orig "$(rd $G/max_pwrlevel)"
    if [ "$T" = "0" ]; then gpu_restore; return 0; fi
    IDX=0; SEL=""
    for f in $F; do
        if [ "$f" -le "$T" ]; then SEL=$IDX; break; fi
        IDX=$((IDX + 1))
    done
    [ -z "$SEL" ] && SEL=$((IDX - 1))
    echo "$SEL" > $G/max_pwrlevel 2>/dev/null
    echo "$T" > $G/devfreq/max_freq 2>/dev/null
    stset gpu_lvl "$LV"
}
gpu_restore() {
    O=$(stget gpu_orig); [ -z "$O" ] && O=0
    echo "$O" > $G/max_pwrlevel 2>/dev/null
    F=$(rd $G/devfreq/available_frequencies)
    if [ -n "$F" ]; then for f in $F; do H=$f; break; done; [ -n "$H" ] && echo "$H" > $G/devfreq/max_freq 2>/dev/null; fi
    stset gpu_lvl none
}
aff_apply() {
    command -v taskset >/dev/null 2>&1 || return 1
    N=0
    for n in logd kswapd0 kcompactd0 surfaceflinger; do
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
    CAP_ON=$(conf PERF_CAP);            [ -z "$CAP_ON" ] && CAP_ON=1
    HOT_ON=$(conf PERF_HOT);            [ -z "$HOT_ON" ] && HOT_ON=0
    HOT_HARD=$(conf PERF_HOT_HARD);     [ -z "$HOT_HARD" ] && HOT_HARD=78
    AFF_ON=$(conf PERF_AFF);            [ -z "$AFF_ON" ] && AFF_ON=1
    CHG_FULL=$(conf PERF_CHARGE_FULL);  [ -z "$CHG_FULL" ] && CHG_FULL=1
    NOW=$(date +%s); T=$(soc_temp)

    HOT_ACT=0
    if [ "$HOT_ON" = "1" ]; then
        if [ "$T" -ge "$HOT_HARD" ]; then
            if [ "$(stget hot)" = "1" ]; then
                log "热控对抗：核心 ${T}°C ≥ ${HOT_HARD}°C，停手并还原"
                sh "$0" restore >/dev/null 2>&1
            fi
            stset hot 0
        else
            [ "$(stget hot)" != "1" ] && log "热控对抗：开启（核心 ${T}°C，${HOT_HARD}°C 停手）"
            stset hot 1; HOT_ACT=1
        fi
    else
        [ "$(stget hot)" = "1" ] && log "热控对抗：关闭"
        stset hot 0
    fi

    if [ "$CHG_FULL" = "1" ] && charging; then
        stset chg_full 1
        [ -n "$(stget cap_lvl)" ] && [ "$(stget cap_lvl)" != "none" ] && { cap_restore; log "充电直通：解除 CPU 上限"; }
        [ -n "$(stget gpu_lvl)" ] && [ "$(stget gpu_lvl)" != "none" ] && { gpu_restore; log "充电直通：解除 GPU 上限"; }
    else
        stset chg_full 0
        if [ "$CAP_ON" = "1" ]; then
            LV=$(conf PERF_CAP_LEVEL); [ -z "$LV" ] && LV=balance
            if [ "$HOT_ACT" = "1" ] || [ "$(stget cap_lvl)" != "$LV" ]; then
                cap_apply
                [ "$(stget cap_lvl)" = "$LV" ] && log "CPU 上限 → $LV"
            fi
        else
            [ -n "$(stget cap_lvl)" ] && [ "$(stget cap_lvl)" != "none" ] && { cap_restore; log "CPU 上限 → 关闭"; }
        fi
        if [ "$(conf PERF_GPU)" != "0" ]; then
            GLV=$(conf PERF_GPU_LEVEL); [ -z "$GLV" ] && GLV=balance
            if [ "$HOT_ACT" = "1" ] || [ "$(stget gpu_lvl)" != "$GLV" ]; then
                gpu_apply
                [ "$(stget gpu_lvl)" = "$GLV" ] && log "GPU 上限 → $GLV"
            fi
        else
            [ -n "$(stget gpu_lvl)" ] && [ "$(stget gpu_lvl)" != "none" ] && { gpu_restore; log "GPU 上限 → 关闭"; }
        fi
    fi

    if [ "$AFF_ON" = "1" ]; then
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
    echo "cap_on=$(conf PERF_CAP)"
    echo "cap_level=$(conf PERF_CAP_LEVEL)"
    echo "cap_applied=$(stget cap_lvl)"
    echo "p0_max=$(rd $CPU/policy0/scaling_max_freq)"
    echo "p4_max=$(rd $CPU/policy4/scaling_max_freq)"
    echo "p7_max=$(rd $CPU/policy7/scaling_max_freq)"
    echo "p0_hw=$(hw_max 0)"
    echo "p4_hw=$(hw_max 4)"
    echo "p7_hw=$(hw_max 7)"
    echo "gpu_on=$(conf PERF_GPU)"
    echo "gpu_level=$(conf PERF_GPU_LEVEL)"
    echo "gpu_applied=$(stget gpu_lvl)"
    echo "gpu_max=$(rd $G/devfreq/max_freq)"
    echo "gpu_pl=$(rd $G/max_pwrlevel)"
    echo "charge_full=$(conf PERF_CHARGE_FULL)"
    echo "charging=$(charging && echo 1 || echo 0)"
    echo "chg_full=$(stget chg_full)"
    echo "hot_on=$(conf PERF_HOT)"
    echo "hot_applied=$(stget hot)"
    echo "hot_hard=$(conf PERF_HOT_HARD)"
    echo "aff_on=$(conf PERF_AFF)"
    echo "aff_pids=$(stget aff_pids)"
    echo "lboost=$(conf PERF_LBOOST)"
    echo "fg=$(stget fg)"
    echo "soc_temp=$(soc_temp)"
    echo "trim_ts=$(stget trim_ts)"
    ;;

  restore) cap_restore; gpu_restore; stset hot 0; log "已还原性能上限" ;;
  boost)   boost_now ;;
  trim)    fstrim /data 2>/dev/null; fstrim /cache 2>/dev/null; stset trim_ts "$(date +%s)"; echo "fstrim 完成" ;;
  fg)      fg_pkg ;;
  cap-on)      setk PERF_CAP 1;          exec sh "$0" tick ;;
  cap-off)     setk PERF_CAP 0;          cap_restore; log "CPU 上限 → 关闭" ;;
  cap-level)   setk PERF_CAP_LEVEL "$2"; setk PERF_CAP 1; exec sh "$0" tick ;;
  gpu-on)      setk PERF_GPU 1;          exec sh "$0" tick ;;
  gpu-off)     setk PERF_GPU 0;          gpu_restore; log "GPU 上限 → 关闭" ;;
  gpu-level)   setk PERF_GPU_LEVEL "$2"; setk PERF_GPU 1; exec sh "$0" tick ;;
  hot-on)      setk PERF_HOT 1;          exec sh "$0" tick ;;
  hot-off)     setk PERF_HOT 0;          stset hot 0; log "热控对抗 → 关闭" ;;
  hot-hard)    setk PERF_HOT_HARD "$2";  echo "硬上限 ${2}°C" ;;
  aff-on)      setk PERF_AFF 1;          aff_apply ;;
  aff-off)     setk PERF_AFF 0;          echo "绑核 → 关闭" ;;
  lboost-on)   setk PERF_LBOOST 1;       echo "启动加速 → 开" ;;
  lboost-off)  setk PERF_LBOOST 0;       echo "启动加速 → 关" ;;
  chgfull-on)  setk PERF_CHARGE_FULL 1;  exec sh "$0" tick ;;
  chgfull-off) setk PERF_CHARGE_FULL 0;  exec sh "$0" tick ;;
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
  *) echo "用法: perf.sh tick|status|restore|boost|trim|watch|fg|cap-on|cap-off|cap-level <eco|balance|perf>|gpu-on|gpu-off|gpu-level <eco|balance|perf>|hot-on|hot-off|hot-hard <C>|aff-on|aff-off|lboost-on|lboost-off|chgfull-on|chgfull-off" ;;
esac
exit 0
