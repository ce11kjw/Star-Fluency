#!/system/bin/sh
export PATH=/data/adb/ksu/bin:/data/adb/magisk:/system/bin:/system/xbin:/vendor/bin:/product/bin:$PATH
# appops 读取（含 su 兜底）
aop() {
    local r
    r=$(appops get "$1" RUN_IN_BACKGROUND 2>/dev/null | grep -oE "ignore|allow" | head -1)
    [ -z "$r" ] && r=$(su -c "appops get $1 RUN_IN_BACKGROUND" 2>/dev/null | grep -oE "ignore|allow" | head -1)
    echo "$r"
}
#!/system/bin/sh
# 输出 JSON 状态给 WebUI

SF_DIR=/data/adb/star-fluency
SF_CONF=$SF_DIR/config.conf
SF_STOCK=$SF_DIR/stock.txt

esc() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g' | tr -d '\n\r'; }

rd() { cat "$1" 2>/dev/null | tr -d '\n' | head -c 60; }
stock_of() { [ -f "$SF_STOCK" ] && grep -E "^${1}=" "$SF_STOCK" 2>/dev/null | tail -1 | cut -d= -f2-; }
conf_of() { [ -f "$SF_CONF" ] && grep -E "^${1}=" "$SF_CONF" 2>/dev/null | tail -1 | cut -d= -f2-; }

PROFILE=$(conf_of PROFILE); [ -z "$PROFILE" ] && PROFILE=balance

# --- zram ---
Z_ALGO=$(cat /sys/block/zram0/comp_algorithm 2>/dev/null | sed -n 's/.*\[\([^]]*\)\].*/\1/p')
MM=$(cat /sys/block/zram0/mm_stat 2>/dev/null)
Z_ORIG=$(echo "$MM" | awk '{print $1}')
Z_COMP=$(echo "$MM" | awk '{print $2}')
Z_MEM=$(echo "$MM" | awk '{print $3}')
Z_RATIO="0"
if [ -n "$Z_COMP" ] && [ "$Z_COMP" -gt 0 ] 2>/dev/null; then
    Z_RATIO=$(awk "BEGIN{printf \"%.2f\", $Z_ORIG/$Z_COMP}")
fi

# --- swap ---
SWAP_LINE=$(cat /proc/swaps 2>/dev/null | awk '/zram0/{print $3" "$4}')
SWAP_TOTAL=$(echo "$SWAP_LINE" | awk '{print $1}')
SWAP_USED=$(echo "$SWAP_LINE" | awk '{print $2}')

# --- 内存 ---
MI=$(cat /proc/meminfo)
MEM_TOTAL=$(echo "$MI" | awk '/^MemTotal:/{print $2}')
MEM_AVAIL=$(echo "$MI" | awk '/^MemAvailable:/{print $2}')
MEM_FREE=$(echo "$MI" | awk '/^MemFree:/{print $2}')

# --- 负载 ---
LA=$(cat /proc/loadavg | cut -d' ' -f1-3)

# --- CPU 频率 ---
F0=$(cat /sys/devices/system/cpu/cpufreq/policy0/scaling_cur_freq 2>/dev/null)
F4=$(cat /sys/devices/system/cpu/cpufreq/policy4/scaling_cur_freq 2>/dev/null)
F7=$(cat /sys/devices/system/cpu/cpufreq/policy7/scaling_cur_freq 2>/dev/null)

# --- 当前参数 ---
CUR_SWAP=$(rd /proc/sys/vm/swappiness)
CUR_VFS=$(rd /proc/sys/vm/vfs_cache_pressure)
CUR_DIRTY=$(rd /proc/sys/vm/dirty_ratio)
CUR_DIRTYBG=$(rd /proc/sys/vm/dirty_background_ratio)
CUR_MINFREE=$(rd /proc/sys/vm/min_free_kbytes)
CUR_SCHED=$(rd /sys/block/sda/queue/scheduler)
CUR_RA=$(rd /sys/block/sda/queue/read_ahead_kb)
CUR_C0=$(rd /sys/devices/system/cpu/cpufreq/policy0/scaling_min_freq)
CUR_C4=$(rd /sys/devices/system/cpu/cpufreq/policy4/scaling_min_freq)
CUR_C7=$(rd /sys/devices/system/cpu/cpufreq/policy7/scaling_min_freq)
CUR_GOV=$(rd /sys/devices/system/cpu/cpufreq/policy0/scaling_governor)

# --- 动图 ---
MS=/data/adb/star-fluency/motion
M_AUTO=$([ -f "$MS/auto.on" ] && echo 1 || echo 0)
M_PEND=$(ls /data/user/0/com.android.camera/files/livephoto_pending/microvideo_*.mp4 2>/dev/null | wc -l)
M_DONE=$(ls "$MS"/backup/*.jpg 2>/dev/null | wc -l)
M_LOG=$(tail -n 1 "$MS/motion.log" 2>/dev/null)

# --- 精简状态 ---
PA_ST=$(aop com.miui.personalassistant)
GMS_ST=$(aop com.google.android.gms)
ANIM_ST=$(settings get global window_animation_scale 2>/dev/null | grep -oE "^[0-9.]+$")
PLAY_ST=$(aop com.android.vending)
PLAY_PID=$(pidof com.android.vending 2>/dev/null)
PLAY_KILLS=$(cat /data/adb/star-fluency/play_killed_count 2>/dev/null)
[ -z "$PLAY_KILLS" ] && PLAY_KILLS=0
NER_ST=$(aop com.xiaomi.aiservice)
MKT_ST=$(aop com.xiaomi.market)
CTN_ST=$(aop com.miui.contentextension)
CACHED_RAW=$(settings get global activity_manager_constants 2>/dev/null)
CACHED_MAX=$(echo "$CACHED_RAW" | sed -n 's/.*max_cached_processes=\([0-9]*\).*/\1/p')
[ -z "$CACHED_MAX" ] && CACHED_MAX=0
GMS_SVC=$(dumpsys activity services com.google.android.gms 2>/dev/null | awk '/ServiceRecord/{n++} END{print n+0}')
GMS_SLIM=$([ -f /data/adb/star-fluency/gms_slimmed ] && echo 1 || echo 0)
AB_PID=$(pgrep -f "com.tencent.mm:appbrand" 2>/dev/null | head -1)
AB_ON=$(conf_of APPBRAND_IDLE); [ -z "$AB_ON" ] && AB_ON=0
AB_RSS=$(ps -o RSS= -p "${AB_PID:-0}" 2>/dev/null | tr -d ' ')
[ -z "$AB_RSS" ] && AB_RSS=0
GPU_IDLE=$(cat /sys/class/kgsl/kgsl-3d0/idle_timer 2>/dev/null)
CAM_IDLE=$(conf_of CAM_IDLE_KILL); [ -z "$CAM_IDLE" ] && CAM_IDLE=0
CAM_PID=$(pidof com.android.camera 2>/dev/null)
# --- 电池健康 ---
BAT_DESIGN=$(cat /sys/class/power_supply/battery/charge_full_design 2>/dev/null)
BAT_FULL=$(cat /sys/class/power_supply/battery/charge_full 2>/dev/null)
BAT_CYC=$(cat /sys/class/power_supply/battery/cycle_count 2>/dev/null)
[ -z "$BAT_DESIGN" ] && BAT_DESIGN=0
[ -z "$BAT_FULL" ] && BAT_FULL=0
[ -z "$BAT_CYC" ] && BAT_CYC=0
BAT_HEALTH=0
[ "$BAT_DESIGN" -gt 0 ] && BAT_HEALTH=$(awk -v f="$BAT_FULL" -v d="$BAT_DESIGN" 'BEGIN{printf "%.0f", f*100/d}')
# --- 估算引擎结果 ---
BH=$(sh "${MODDIR:-/data/adb/modules/star_fluency}/scripts/batt-health.sh" 2>/dev/null)
bhg() { echo "$BH" | grep "^$1=" | cut -d= -f2; }
BH_H=$(bhg health); [ -z "$BH_H" ] && BH_H=$BAT_HEALTH
BH_SRC=$(bhg health_src); [ -z "$BH_SRC" ] && BH_SRC=system
BH_MEAS=$(bhg meas_mah); [ -z "$BH_MEAS" ] && BH_MEAS=0
BH_SEGS=$(bhg segs); [ -z "$BH_SEGS" ] && BH_SEGS=0
BH_IR=$(bhg ir_mohm); [ -z "$BH_IR" ] && BH_IR=0
BH_IRTR=$(bhg ir_trend); [ -z "$BH_IRTR" ] && BH_IRTR=0
BAT_T=$(cat /sys/class/power_supply/battery/temp 2>/dev/null); [ -z "$BAT_T" ] && BAT_T=0; BAT_T=$((BAT_T / 10))
BAT_I=$(cat /sys/class/power_supply/battery/current_now 2>/dev/null); [ -z "$BAT_I" ] && BAT_I=0
BAT_P=$(cat /sys/class/power_supply/battery/power_now 2>/dev/null); [ -z "$BAT_P" ] && BAT_P=0
CPU_T=$(cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null); [ -z "$CPU_T" ] && CPU_T=0; CPU_T=$((CPU_T / 1000))


# --- 网络/自动/白名单 ---
# --- 网络/自动/白名单 ---
# 实时判断当前出口（只读 sysfs / proc，不 fork 进程，实测 <5ms）
NET_TYPE=unknown
NET_PHYS=""
for f in /sys/class/net/wlan*/carrier; do
    [ -e "$f" ] || continue
    read -r c < "$f" 2>/dev/null
    if [ "$c" = "1" ]; then
        NET_TYPE=wifi
        NET_PHYS=${f#/sys/class/net/}
        NET_PHYS=${NET_PHYS%/carrier}
        break
    fi
done
if [ "$NET_TYPE" = "unknown" ]; then
    while read -r ifc dst gw fl _r; do
        case "$ifc" in
            rmnet*|ccmni*|pdp*)
                if [ "$dst" = "00000000" ]; then NET_TYPE=cellular; NET_PHYS=$ifc; break; fi
                ;;
        esac
    done < /proc/net/route
fi
if [ "$NET_TYPE" = "unknown" ] && [ -r /proc/net/if_inet6 ]; then
    while read -r a1 a2 a3 a4 a5 ifc _r; do
        case "$ifc" in
            rmnet*|ccmni*|pdp*) NET_TYPE=cellular; NET_PHYS=$ifc; break ;;
        esac
    done < /proc/net/if_inet6
fi
# VPN：接口存在且未 down 才算（旧实现读快照，VPN 关了还显示 tun0）
NET_VPN=none
for d in /sys/class/net/tun* /sys/class/net/utun* /sys/class/net/wg*; do
    [ -e "$d" ] || continue
    read -r op < "$d/operstate" 2>/dev/null
    [ "$op" = "down" ] && continue
    NET_VPN=${d#/sys/class/net/}
    break
done
# 上次应用参数时用的是哪种网络（仅用于提示是否需要重新应用）
NET_APPLIED=$(grep '^type=' /data/adb/star-fluency/net_state 2>/dev/null | cut -d= -f2)
[ -z "$NET_APPLIED" ] && NET_APPLIED=unknown
NET_STALE=0
if [ "$NET_APPLIED" != "unknown" ] && [ "$NET_APPLIED" != "$NET_TYPE" ]; then NET_STALE=1; fi
TFO=$(rd /proc/sys/net/ipv4/tcp_fastopen)
# 网络参数：内核真实值（K）+ 用户设定值（S）
NET_SS_K=$(rd /proc/sys/net/ipv4/tcp_slow_start_after_idle); [ -z "$NET_SS_K" ] && NET_SS_K=0
NET_MTU_K=$(rd /proc/sys/net/ipv4/tcp_mtu_probing);          [ -z "$NET_MTU_K" ] && NET_MTU_K=0
NET_TW_K=$(rd /proc/sys/net/ipv4/tcp_tw_reuse);              [ -z "$NET_TW_K" ] && NET_TW_K=0
NET_NL_K=$(rd /proc/sys/net/ipv4/tcp_notsent_lowat);         [ -z "$NET_NL_K" ] && NET_NL_K=0
NET_FIN_K=$(rd /proc/sys/net/ipv4/tcp_fin_timeout);          [ -z "$NET_FIN_K" ] && NET_FIN_K=0
NET_BUF_K=$(rd /proc/sys/net/core/rmem_max);                 [ -z "$NET_BUF_K" ] && NET_BUF_K=0
NET_BUF_K=$((NET_BUF_K / 1048576))
NET_ICW_K=$(grep '^initcwnd=' /data/adb/star-fluency/net_state 2>/dev/null | cut -d= -f2)
[ -z "$NET_ICW_K" ] && NET_ICW_K=0
eval "$(awk -F= '$1=="NET_SS"{print "NET_SS_S="($2+0)} $1=="NET_MTU"{print "NET_MTU_S="($2+0)} $1=="NET_TW"{print "NET_TW_S="($2+0)} $1=="NET_NL"{print "NET_NL_S="($2+0)} $1=="NET_FIN"{print "NET_FIN_S="($2+0)} $1=="NET_BUF_MB"{print "NET_BUF_S="($2+0)} $1=="NET_INITCWND"{print "NET_ICW_S="($2+0)}' /data/adb/star-fluency/config.conf 2>/dev/null)"
[ -z "$NET_SS_S" ] && NET_SS_S=0
[ -z "$NET_MTU_S" ] && NET_MTU_S=1
[ -z "$NET_TW_S" ] && NET_TW_S=1
[ -z "$NET_NL_S" ] && NET_NL_S=131072
[ -z "$NET_FIN_S" ] && NET_FIN_S=30
[ -z "$NET_BUF_S" ] && NET_BUF_S=0
[ -z "$NET_ICW_S" ] && NET_ICW_S=20
NET_BUF_EFF=$NET_BUF_S
if [ "$NET_BUF_EFF" = "0" ]; then
    NET_BUF_EFF=$(grep '^buf_mb=' /data/adb/star-fluency/net_state 2>/dev/null | cut -d= -f2)
    [ -z "$NET_BUF_EFF" ] && NET_BUF_EFF=$NET_BUF_K
fi
AUTO_SC=$(conf_of AUTO_SCENE); [ -z "$AUTO_SC" ] && AUTO_SC=0
AUTO_TP=$(conf_of AUTO_TEMP); [ -z "$AUTO_TP" ] && AUTO_TP=0
TEMP_TH=$(conf_of TEMP_THRESHOLD); [ -z "$TEMP_TH" ] && TEMP_TH=42
AUTO_T=$(grep '^temp=' /data/adb/star-fluency/auto_state 2>/dev/null | cut -d= -f2)
AUTO_W=$(grep '^temp_warn=' /data/adb/star-fluency/auto_state 2>/dev/null | cut -d= -f2)
[ -z "$AUTO_T" ] && AUTO_T=0
[ -z "$AUTO_W" ] && AUTO_W=0
WL_CNT=$(grep -c . /data/adb/star-fluency/whitelist.txt 2>/dev/null)
[ -z "$WL_CNT" ] && WL_CNT=0
AS_CNT=$(cut -d'|' -f1 /data/adb/star-fluency/autostart_db.txt 2>/dev/null | sort -u | grep -c .)
[ -z "$AS_CNT" ] && AS_CNT=0

cat <<JSONEOF
{
  "profile":"$PROFILE",
  "zram":{"algo":"$(esc "$Z_ALGO")","ratio":$Z_RATIO,"orig":${Z_ORIG:-0},"comp":${Z_COMP:-0},"mem":${Z_MEM:-0}},
  "swap":{"total":${SWAP_TOTAL:-0},"used":${SWAP_USED:-0}},
  "mem":{"total":${MEM_TOTAL:-0},"avail":${MEM_AVAIL:-0},"free":${MEM_FREE:-0}},
  "load":"$(esc "$LA")",
  "cpu":{"f0":${F0:-0},"f4":${F4:-0},"f7":${F7:-0},"temp":${CPU_T:-0}},
  "bat":{"health":${BH_H:-0},"cycles":${BAT_CYC:-0},"mah":$((BAT_FULL / 1000)),"design":$((BAT_DESIGN / 1000)),"meas":${BH_MEAS:-0},"segs":${BH_SEGS:-0},"src":"$(esc "$BH_SRC")","temp":${BAT_T:-0},"cur":${BAT_I:-0},"pwr":${BAT_P:-0},"ir":${BH_IR:-0},"irtr":${BH_IRTR:-0}},
  "cur":{
    "swappiness":"$CUR_SWAP","vfs":"$CUR_VFS","dirty":"$CUR_DIRTY","dirtybg":"$CUR_DIRTYBG",
    "minfree":"$CUR_MINFREE","sched":"$(esc "$CUR_SCHED")","readahead":"$CUR_RA",
    "c0":"$CUR_C0","c4":"$CUR_C4","c7":"$CUR_C7","gov":"$CUR_GOV"
  },
  "stock":{
    "swappiness":"$(stock_of swappiness)","vfs":"$(stock_of vfs_cache_pressure)",
    "dirty":"$(stock_of dirty_ratio)","dirtybg":"$(stock_of dirty_bg_ratio)",
    "minfree":"$(stock_of min_free_kbytes)","sched":"$(esc "$(stock_of sda_sched)")",
    "readahead":"$(stock_of sda_readahead)","c0":"$(stock_of cpu0_min)","c4":"$(stock_of cpu4_min)",
    "c7":"$(stock_of cpu7_min)","gov":"$(stock_of cpu0_gov)","zram":"$(stock_of zram_comp)"
  },
  "motion":{"auto":$M_AUTO,"pending":$M_PEND,"done":$M_DONE,"last":"$(esc "$M_LOG")"},
  "trim":{
    "pa":"$(esc "$PA_ST")","gms":"$(esc "$GMS_ST")","anim":"$(esc "${ANIM_ST:-1}")",
    "play":"$(esc "$PLAY_ST")","ner":"$(esc "$NER_ST")",
    "market":"$(esc "$MKT_ST")","content":"$(esc "$CTN_ST")","cached":${CACHED_MAX:-0}
  },
  "play":{"running":"$(esc "${PLAY_PID:-}")","kills":${PLAY_KILLS:-0}},
  "appbrand":{"running":"$(esc "${AB_PID:-}")","rss":${AB_RSS:-0},"idle_on":${AB_ON:-0}},
  "gpu":{"idle_timer":"$(esc "${GPU_IDLE:-}")"},
  "gms":{"services":${GMS_SVC:-0},"slim":${GMS_SLIM:-0}},
  "cam":{"idle_kill":$CAM_IDLE,"running":"$(esc "${CAM_PID:-}")"}
  ,
  "net":{"type":"$(esc "$NET_TYPE")","phys":"$(esc "$NET_PHYS")","vpn":"$(esc "$NET_VPN")","applied":"$(esc "$NET_APPLIED")","stale":${NET_STALE:-0},"fastopen":"$(esc "${TFO:-}")","params":{"ss":${NET_SS_K:-0},"mtu":${NET_MTU_K:-0},"tw":${NET_TW_K:-0},"nl":${NET_NL_K:-0},"fin":${NET_FIN_K:-0},"buf":${NET_BUF_K:-0},"icw":${NET_ICW_K:-0},"ss_set":${NET_SS_S:-0},"mtu_set":${NET_MTU_S:-1},"tw_set":${NET_TW_S:-1},"nl_set":${NET_NL_S:-131072},"fin_set":${NET_FIN_S:-30},"buf_set":${NET_BUF_S:-0},"icw_set":${NET_ICW_S:-20},"buf_eff":${NET_BUF_EFF:-0}}},
  "auto":{"scene":${AUTO_SC:-0},"temp":${AUTO_TP:-0},"threshold":${TEMP_TH:-42},"cur_temp":${AUTO_T:-0},"warn":${AUTO_W:-0}},
  "whitelist":${WL_CNT:-0},
  "autostart":{"disabled":${AS_CNT:-0}}
}
JSONEOF
exit 0
