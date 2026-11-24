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

# --- 网络/自动/白名单 ---
NET_TYPE=$(grep '^type=' /data/adb/star-fluency/net_state 2>/dev/null | cut -d= -f2)
NET_VPN=$(grep '^vpn=' /data/adb/star-fluency/net_state 2>/dev/null | cut -d= -f2)
[ -z "$NET_TYPE" ] && NET_TYPE=unknown
[ -z "$NET_VPN" ] && NET_VPN=none
TFO=$(rd /proc/sys/net/ipv4/tcp_fastopen)
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
  "cpu":{"f0":${F0:-0},"f4":${F4:-0},"f7":${F7:-0}},
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
  "net":{"type":"$(esc "$NET_TYPE")","vpn":"$(esc "$NET_VPN")","fastopen":"$(esc "${TFO:-}")"},
  "auto":{"scene":${AUTO_SC:-0},"temp":${AUTO_TP:-0},"threshold":${TEMP_TH:-42},"cur_temp":${AUTO_T:-0},"warn":${AUTO_W:-0}},
  "whitelist":${WL_CNT:-0},
  "autostart":{"disabled":${AS_CNT:-0}}
}
JSONEOF
exit 0
