#!/system/bin/sh
# Star-Fluency 调度引擎
# 自研场景识别 + 对外暴露 /data/powercfg.sh（Scene 外部来源）
#
# 用法:
#   sched.sh mode <powersave|balance|performance|fast>   Scene 调用（来源=scene）
#   sched.sh apply <mode>                                 手动调用（来源=self）
#   sched.sh init                                          Scene init 动作
#   sched.sh hook-on | hook-off                            安装/移除 /data/powercfg.sh
#   sched.sh status                                        输出 key=value
#   sched.sh app-add <包名> <mode> / app-del <包名> / app-list
#   sched.sh setcfg <KEY> <VAL>

SF_DIR=/data/adb/star-fluency
SCHED_DIR=$SF_DIR/sched
CONF=$SF_DIR/config.conf
LOG=$SF_DIR/fluency.log
STATE=$SCHED_DIR/state
APPS=$SCHED_DIR/apps.conf
mkdir -p "$SCHED_DIR" 2>/dev/null

log() { echo "$(date '+%m-%d %H:%M:%S') [sched] $*" >> "$LOG" 2>/dev/null; }
conf() { grep -E "^$1=" "$CONF" 2>/dev/null | cut -d= -f2 | head -1; }

# Scene 当前配置源（SOURCE_OUTSIDE = 外部来源，即调用我们的 powercfg.sh）
scene_source() {
    grep -oE 'name="scene_profile_source">[^<]*' /data/data/com.omarea.vtools/shared_prefs/global.xml 2>/dev/null | sed 's/.*>//'
}

# ---- 写节点：写后读回校验 ----
w() {
    node="$1"; val="$2"; name="$3"
    [ -e "$node" ] || return 0
    cur=$(cat "$node" 2>/dev/null | tr '\t' ' ')
    [ "$cur" = "$val" ] && return 0
    if echo "$val" > "$node" 2>/dev/null; then
        now=$(cat "$node" 2>/dev/null | tr '\t' ' ')
        [ "$now" = "$val" ] && log "OK   $name: $cur -> $val" || log "FAIL $name (读回=$now)"
    else
        log "SKIP $name (不可写)"
    fi
}

CPU=/sys/devices/system/cpu
# 每簇 schedutil 节点
snode() { echo "$CPU/cpufreq/policy$1/schedutil/$2"; }

# ---- 档位参数（骁龙 888：policy0=A55 / policy4=A78 / policy7=X1）----
set_mode() {
    MODE="$1"
    case "$MODE" in
      powersave)
        C0MIN=300000;  C4MIN=710400;  C7MIN=844800
        H0=1209600;    H4=1555200;    H7=1785600
        HL0=95;        HL4=95;        HL7=95
        UP=500;        DOWN=2000;     CLAMP=0
        ;;
      balance)
        C0MIN=595200;  C4MIN=710400;  C7MIN=844800
        H0=1209600;    H4=1670400;    H7=2035200
        HL0=90;        HL4=90;        HL7=90
        UP=200;        DOWN=800;      CLAMP=0
        ;;
      performance)
        C0MIN=691200;  C4MIN=960000;  C7MIN=1075200
        H0=1305600;    H4=1881600;    H7=2380800
        HL0=85;        HL4=85;        HL7=80
        UP=100;        DOWN=500;      CLAMP=128
        ;;
      fast)
        C0MIN=902400;  C4MIN=1209600; C7MIN=1305600
        H0=1401600;    H4=2112000;    H7=2592000
        HL0=80;        HL4=80;        HL7=75
        UP=50;         DOWN=200;      CLAMP=256
        ;;
      stock)
        C0MIN=$(conf cpu0_min); [ -z "$C0MIN" ] && C0MIN=595200
        C4MIN=$(conf cpu4_min); [ -z "$C4MIN" ] && C4MIN=710400
        C7MIN=$(conf cpu7_min); [ -z "$C7MIN" ] && C7MIN=844800
        H0=1209600;    H4=1670400;    H7=2035200
        HL0=90;        HL4=90;        HL7=90
        UP=200;        DOWN=800;      CLAMP=0
        ;;
      *) log "未知档位: $MODE"; return 1 ;;
    esac

    w "$CPU/cpufreq/policy0/scaling_min_freq" "$C0MIN" "policy0 min"
    w "$CPU/cpufreq/policy4/scaling_min_freq" "$C4MIN" "policy4 min"
    w "$CPU/cpufreq/policy7/scaling_min_freq" "$C7MIN" "policy7 min"

    w "$(snode 0 hispeed_freq)" "$H0" "p0 hispeed_freq"
    w "$(snode 4 hispeed_freq)" "$H4" "p4 hispeed_freq"
    w "$(snode 7 hispeed_freq)" "$H7" "p7 hispeed_freq"
    w "$(snode 0 hispeed_load)" "$HL0" "p0 hispeed_load"
    w "$(snode 4 hispeed_load)" "$HL4" "p4 hispeed_load"
    w "$(snode 7 hispeed_load)" "$HL7" "p7 hispeed_load"

    w "$(snode 0 up_rate_limit_us)" "$UP" "p0 up_rate"
    w "$(snode 4 up_rate_limit_us)" "$UP" "p4 up_rate"
    w "$(snode 7 up_rate_limit_us)" "$UP" "p7 up_rate"
    w "$(snode 0 down_rate_limit_us)" "$DOWN" "p0 down_rate"
    w "$(snode 4 down_rate_limit_us)" "$DOWN" "p4 down_rate"
    w "$(snode 7 down_rate_limit_us)" "$DOWN" "p7 down_rate"

    w /proc/sys/kernel/sched_util_clamp_min "$CLAMP" "clamp_min"
    w /proc/sys/kernel/sched_util_clamp_max 1024 "clamp_max"

    echo "mode=$MODE" > "$STATE"
    echo "ts=$(date +%s)" >> "$STATE"
    log "===== 档位 -> $MODE (clamp_min=$CLAMP) ====="
}

# ---- 前台应用（dumpsys，约 120ms）----
top_app_now() {
    A=$(dumpsys window 2>/dev/null | grep -m1 -E 'mCurrentFocus|mFocusedApp' | sed -n 's/.*u[0-9]* \([a-zA-Z0-9_.]*\)\/.*/\1/p')
    [ -z "$A" ] && A=$(dumpsys activity 2>/dev/null | grep -m1 'topResumedActivity' | sed -n 's/.*u[0-9]* \([a-zA-Z0-9_.]*\)\/.*/\1/p')
    echo "$A"
}

# ---- 按应用覆盖 ----
app_mode() {
    [ -f "$APPS" ] || return 1
    grep -E "^$1=" "$APPS" 2>/dev/null | head -1 | cut -d= -f2
}

case "$1" in
  push|mode|apply)
    M="$2"; [ -z "$M" ] && M=balance
    if [ "$(conf SCHED_ENABLED)" = "0" ]; then
        log "调度引擎已停用，跳过 $M"
        echo "已停用"
        exit 0
    fi
    SRC=self; [ "$1" = "mode" ] && SRC=scene
    echo "source=$SRC" > "$SCHED_DIR/source"
    [ -n "$top_app" ] && echo "$top_app" > "$SCHED_DIR/top_app"
    log "调用来源=$SRC 档位=$M 前台=${top_app:-未传}"
    set_mode "$M"
    # 手动切换才更新基准档位；Scene 调用(mode)与守护(push)不覆盖
    if [ "$1" = "apply" ]; then
        if grep -q '^SCHED_MODE=' "$CONF" 2>/dev/null; then
            sed -i "s|^SCHED_MODE=.*|SCHED_MODE=$M|" "$CONF"
        else
            echo "SCHED_MODE=$M" >> "$CONF"
        fi
        log "基准档位记为 $M"
    fi
    ;;
  init)
    # Scene 启动性能调节时执行一次
    log "Scene init"
    [ -f "$SCHED_DIR/state" ] || set_mode "$(conf PROFILE)"
    ;;
  hook-on)
    cat > /data/powercfg.sh <<'EOF'
#!/system/bin/sh
# Star-Fluency 调度入口（Scene 外部来源）
# Scene 会以: sh /data/powercfg.sh <init|powersave|balance|performance|fast> 调用
# 严格模式下会 export top_app=<前台包名>
export top_app
if [ "$1" = init ]; then exec sh /data/adb/modules/star_fluency/scripts/sched.sh init; fi
exec sh /data/adb/modules/star_fluency/scripts/sched.sh mode "$1"
EOF
    chmod 755 /data/powercfg.sh
    cp -f /data/powercfg.sh /data/powercfg-base.sh 2>/dev/null
    chmod 755 /data/powercfg-base.sh 2>/dev/null
    echo "source=scene" > "$SCHED_DIR/source"
    log "已安装 Scene 外部源 /data/powercfg.sh"
    echo "已安装 /data/powercfg.sh（去 Scene 里把配置源切到「外部来源」）"
    ;;
  hook-off)
    rm -f /data/powercfg.sh /data/powercfg-base.sh
    echo "source=self" > "$SCHED_DIR/source"
    log "已移除 Scene 外部源"
    echo "已移除 /data/powercfg.sh"
    ;;
  status)
    echo "enabled=$(conf SCHED_ENABLED)"
    echo "source=$(cat "$SCHED_DIR/source" 2>/dev/null | cut -d= -f2)"
    echo "hook=$([ -f /data/powercfg.sh ] && echo on || echo off)"
    echo "mode=$(cat /data/adb/star-fluency/sched/state 2>/dev/null | grep '^mode=' | cut -d= -f2)"
    echo "reason=$(cat /data/adb/star-fluency/sched/state 2>/dev/null | grep '^reason=' | cut -d= -f2)"
    echo "app=$(cat /data/adb/star-fluency/sched/state 2>/dev/null | grep '^app=' | cut -d= -f2)"
    echo "clamp_min=$(cat /proc/sys/kernel/sched_util_clamp_min 2>/dev/null)"
    echo "f0=$(cat $CPU/cpufreq/policy0/scaling_cur_freq 2>/dev/null)"
    echo "f4=$(cat $CPU/cpufreq/policy4/scaling_cur_freq 2>/dev/null)"
    echo "f7=$(cat $CPU/cpufreq/policy7/scaling_cur_freq 2>/dev/null)"
    echo "m0=$(cat $CPU/cpufreq/policy0/scaling_min_freq 2>/dev/null)"
    echo "m4=$(cat $CPU/cpufreq/policy4/scaling_min_freq 2>/dev/null)"
    echo "m7=$(cat $CPU/cpufreq/policy7/scaling_min_freq 2>/dev/null)"
    echo "soc_temp=$(cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null || echo 0)"
    echo "core_limit=$(conf SCHED_CORE_TEMP_LIMIT)"
    echo "scene=$(scene_source)"
    ;;
  fg)
    top_app_now
    ;;
  fgfull)
    F=$(dumpsys window 2>/dev/null | grep -m1 "mCurrentFocus=Window{" | sed -n 's/.*u[0-9]* \([a-zA-Z0-9_.]*\)\/\([a-zA-Z0-9_.]*\).*/\1\/\2/p')
    [ -z "$F" ] && F=$(dumpsys window 2>/dev/null | grep -m1 "mFocusedApp=ActivityRecord{" | sed -n 's/.*u[0-9]* \([a-zA-Z0-9_.]*\)\/\([a-zA-Z0-9_.]*\).*/\1\/\2/p')
    echo "$F"
    ;;
  app-add)
    P="$2"; M="$3"
    if [ -z "$P" ] || [ -z "$M" ]; then echo "用法: app-add <包名> <mode>"; exit 1; fi
    touch "$APPS"
    if grep -q "^$P=" "$APPS"; then
        sed -i "s|^$P=.*|$P=$M|" "$APPS"
    else
        echo "$P=$M" >> "$APPS"
    fi
    log "应用覆盖: $P -> $M"
    echo "已设置 $P -> $M"
    ;;
  app-del)
    P="$2"
    [ -z "$P" ] && { echo "用法: app-del <包名 或 包名/Activity>"; exit 1; }
    if [ -f "$APPS" ]; then
        awk -v p="$P" 'index($0, p "=") != 1' "$APPS" > "$APPS.tmp" 2>/dev/null && mv "$APPS.tmp" "$APPS"
    fi
    echo "已移除 $P"
    ;;
  app-list)
    if [ -s "$APPS" ]; then cat "$APPS"; else echo "(空)"; fi
    ;;
  setcfg)
    K="$2"; V="$3"
    [ -z "$K" ] && exit 1
    touch "$CONF"
    if grep -q "^$K=" "$CONF"; then
        sed -i "s|^$K=.*|$K=$V|" "$CONF"
    else
        echo "$K=$V" >> "$CONF"
    fi
    echo "已设置 $K=$V"
    ;;
  *)
    echo "用法: sched.sh {mode|apply|init|hook-on|hook-off|status|app-add|app-del|app-list|setcfg}"
    ;;
esac
