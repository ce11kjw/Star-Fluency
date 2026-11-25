#!/system/bin/sh
# 网络参数优化
# 参考 fatalcoder524/TCP_Optimiser_Module 的接口区分思路
# 用法: net.sh apply|revert [balance|smooth|stock]

MODE="$1"
PROF="${2:-balance}"
LOG=/data/adb/star-fluency/fluency.log
STOCK=/data/adb/star-fluency/net_stock.txt
mkdir -p /data/adb/star-fluency 2>/dev/null

log() { echo "$(date '+%m-%d %H:%M:%S') [net] $*" >> "$LOG" 2>/dev/null; }
# ---- 用户可调参数（配置缺失时用默认值）----
CF=/data/adb/star-fluency/config.conf
cf() { awk -F= -v k="$1" '$1==k{v=$2} END{print v}' "$CF" 2>/dev/null; }
if [ "$MODE" = "defaults" ]; then
    sed -i '/^NET_SS=/d;/^NET_MTU=/d;/^NET_TW=/d;/^NET_NL=/d;/^NET_FIN=/d;/^NET_BUF_MB=/d;/^NET_INITCWND=/d' "$CF" 2>/dev/null
    {
        echo "NET_SS=0"; echo "NET_MTU=1"; echo "NET_TW=1"; echo "NET_NL=131072"
        echo "NET_FIN=30"; echo "NET_BUF_MB=0"; echo "NET_INITCWND=20"
    } >> "$CF"
    MODE=apply
    log "已恢复网络参数默认值"
fi
NET_SS=$(cf NET_SS);         [ -z "$NET_SS" ] && NET_SS=0
NET_MTU=$(cf NET_MTU);       [ -z "$NET_MTU" ] && NET_MTU=1
NET_TW=$(cf NET_TW);         [ -z "$NET_TW" ] && NET_TW=1
NET_NL=$(cf NET_NL);         [ -z "$NET_NL" ] && NET_NL=131072
NET_FIN=$(cf NET_FIN);       [ -z "$NET_FIN" ] && NET_FIN=30
NET_BUF_MB=$(cf NET_BUF_MB); [ -z "$NET_BUF_MB" ] && NET_BUF_MB=0
NET_ICW=$(cf NET_INITCWND);  [ -z "$NET_ICW" ] && NET_ICW=20

snap() {
    [ -f "$STOCK" ] && return 0
    {
        for f in tcp_fastopen tcp_slow_start_after_idle tcp_mtu_probing tcp_fin_timeout \
                 tcp_notsent_lowat tcp_rmem tcp_wmem tcp_timestamps tcp_sack \
                 tcp_window_scaling tcp_ecn tcp_tw_reuse tcp_keepalive_time; do
            v=$(cat /proc/sys/net/ipv4/$f 2>/dev/null | tr '\t' ' ')
            [ -n "$v" ] && echo "ipv4_$f=$v"
        done
        for f in rmem_max wmem_max rmem_default wmem_default somaxconn netdev_max_backlog; do
            v=$(cat /proc/sys/net/core/$f 2>/dev/null)
            [ -n "$v" ] && echo "core_$f=$v"
        done
    } >> "$STOCK" 2>/dev/null
    chmod 600 "$STOCK" 2>/dev/null
}

w() {
    local node="$1" val="$2" name="$3"
    [ -e "$node" ] || return 0
    local cur; cur=$(cat "$node" 2>/dev/null | tr '\t' ' ')
    [ "$cur" = "$val" ] && return 0
    if echo "$val" > "$node" 2>/dev/null; then
        local now; now=$(cat "$node" 2>/dev/null | tr '\t' ' ')
        [ "$now" = "$val" ] && log "OK   $name: $cur -> $val" || log "FAIL $name (读回=$now)"
    else
        log "SKIP $name (不可写)"
    fi
}

# 判断真实出口类型（跳过 tun 类接口，看底层物理网卡）
detect_net() {
    # 优先看 wlan0 / rmnet 是否 UP 且有地址
    for ifc in $(ip -o link show up 2>/dev/null | awk -F': ' '{print $2}' | sed 's/@.*//'); do
        case "$ifc" in
            wlan*)
                if [ "$(cat /sys/class/net/$ifc/carrier 2>/dev/null)" = "1" ]; then echo "wifi:$ifc"; return; fi
                if ip -4 addr show "$ifc" 2>/dev/null | grep -q "inet "; then
                    echo "wifi:$ifc"; return
                fi
                ;;
        esac
    done
    for ifc in $(ip -o link show up 2>/dev/null | awk -F': ' '{print $2}' | sed 's/@.*//'); do
        case "$ifc" in
            rmnet*|ccmni*|pdp*)
                if ip -4 addr show "$ifc" 2>/dev/null | grep -q "inet "; then
                    echo "cellular:$ifc"; return
                fi
                ;;
        esac
    done
    echo "unknown:"
}

snap

DETECT=$(detect_net)
NET_TYPE=${DETECT%%:*}
PHYS_IF=${DETECT#*:}
# 是否走了 VPN/TUN
TUN_IF=$(ip -o link show up 2>/dev/null | awk -F': ' '{print $2}' | sed 's/@.*//' | grep -E '^(tun|utun|wg)' | head -1)

log "===== 网络优化: $MODE (类型=$NET_TYPE 物理=$PHYS_IF VPN=${TUN_IF:-无}) ====="

if [ "$MODE" = "stock" ] || [ "$MODE" = "revert" ]; then
    [ -f "$STOCK" ] || { log "无原厂备份"; exit 0; }
    while IFS='=' read -r k v; do
        [ -z "$k" ] && continue
        case "$k" in
            ipv4_*) w "/proc/sys/net/ipv4/${k#ipv4_}" "$v" "$k" ;;
            core_*) w "/proc/sys/net/core/${k#core_}" "$v" "$k" ;;
        esac
    done < "$STOCK"
    log "===== 已恢复原厂 ====="
    exit 0
fi

case "$PROF" in
  smooth) BUF=33554432 ;;
  *)      BUF=16777216 ;;
esac
# 用户自定义缓冲上限（0 = 按档位）
[ "$NET_BUF_MB" -gt 0 ] 2>/dev/null && BUF=$((NET_BUF_MB * 1048576))

# ---- TCP 核心（全局，不分接口）----
w /proc/sys/net/ipv4/tcp_fastopen 3 tcp_fastopen
w /proc/sys/net/ipv4/tcp_slow_start_after_idle "$NET_SS" tcp_slow_start_after_idle
w /proc/sys/net/ipv4/tcp_mtu_probing "$NET_MTU" tcp_mtu_probing
w /proc/sys/net/ipv4/tcp_notsent_lowat "$NET_NL" tcp_notsent_lowat
w /proc/sys/net/ipv4/tcp_fin_timeout "$NET_FIN" tcp_fin_timeout
w /proc/sys/net/ipv4/tcp_tw_reuse "$NET_TW" tcp_tw_reuse

# ---- 缓冲区 ----
w /proc/sys/net/core/rmem_max "$BUF" rmem_max
w /proc/sys/net/core/wmem_max "$BUF" wmem_max
if [ "$NET_TYPE" = "cellular" ]; then
    w /proc/sys/net/ipv4/tcp_rmem "4096 87380 $BUF" tcp_rmem
    w /proc/sys/net/ipv4/tcp_wmem "4096 65536 $BUF" tcp_wmem
    log "蜂窝：缓冲区 $((BUF/1048576))MB（保守）"
else
    w /proc/sys/net/ipv4/tcp_rmem "4096 1048576 $BUF" tcp_rmem
    w /proc/sys/net/ipv4/tcp_wmem "4096 1048576 $BUF" tcp_wmem
    log "Wi-Fi/未知：缓冲区 $((BUF/1048576))MB"
fi

# ---- initcwnd: Android 多路由表 ----
RT_OK=0
for TB in $(ip route show table all 2>/dev/null | grep '^default' | sed -n 's/.*table \([a-zA-Z0-9_]*\).*/\1/p' | sort -u); do
    [ "$TB" = "lo" ] && continue
    LINE=$(ip route show table "$TB" 2>/dev/null | grep '^default' | grep -v unreachable | head -1)
    [ -z "$LINE" ] && continue
    VIA=$(echo "$LINE" | grep -oE 'via [0-9a-fA-F:.]+' | head -1)
    DEV=$(echo "$LINE" | grep -oE 'dev [a-zA-Z0-9_]+' | head -1)
    [ -z "$DEV" ] && continue
    if ip route change default $VIA $DEV table "$TB" initcwnd $NET_ICW initrwnd $NET_ICW 2>/dev/null; then
        RT_OK=$((RT_OK+1))
        log "OK   initcwnd -> $NET_ICW (table $TB)"
    fi
done
[ "$RT_OK" -eq 0 ] && log "SKIP initcwnd"
# ---- txqueuelen ----
for IF in $(ip -o link show up 2>/dev/null | awk -F': ' '{print $2}' | sed 's/@.*//' | grep -vE '^lo$'); do
    ip link set "$IF" txqueuelen 2000 2>/dev/null
done
log "OK   txqueuelen -> 2000"

# ---- 记录当前生效状态供 status 读取 ----
echo "type=$NET_TYPE" > /data/adb/star-fluency/net_state
echo "phys=$PHYS_IF" >> /data/adb/star-fluency/net_state
echo "vpn=${TUN_IF:-none}" >> /data/adb/star-fluency/net_state
echo "initcwnd=$NET_ICW" >> /data/adb/star-fluency/net_state
echo "buf_mb=$((BUF / 1048576))" >> /data/adb/star-fluency/net_state

log "===== 完成: $PROF / $NET_TYPE ====="
exit 0
