#!/system/bin/sh
# 开机自启管理
# 用法:
#   autostart.sh list              列出自启应用
#   autostart.sh disable <包名>    禁用
#   autostart.sh enable <包名>     恢复
#   autostart.sh disabled          列出已禁用

SF_DIR=/data/adb/star-fluency
LOG=$SF_DIR/fluency.log
DB=$SF_DIR/autostart_db.txt      # 记录 包名|组件全名（每行一个已禁用组件）
mkdir -p "$SF_DIR" 2>/dev/null
touch "$DB" 2>/dev/null
chmod 600 "$DB" 2>/dev/null

log() { echo "$(date '+%m-%d %H:%M:%S') [auto] $*" >> "$LOG" 2>/dev/null; }
svc() { su -c "$*" 2>/dev/null || eval "$*" 2>/dev/null; }

# 查所有 BOOT_COMPLETED 接收器，输出 pkg/component
query_boot_receivers() {
    cmd package query-receivers --components -a android.intent.action.BOOT_COMPLETED 2>/dev/null | grep '/'
}

# 从 component 全名里取包名：com.a.b/.Xxx -> com.a.b ；com.a.b/com.a.b.Xxx -> com.a.b
pkg_of() {
    echo "$1" | cut -d/ -f1
}

case "$1" in
  list)
    echo "=== 开机自启应用 ==="
    query_boot_receivers | cut -d/ -f1 | sort -u | while read -r p; do
        [ -z "$p" ] && continue
        MARK=""
        grep -q "^${p}|" "$DB" 2>/dev/null && MARK=" [已禁用]"
        echo "  $p$MARK"
    done
    ;;
  disabled)
    if [ -s "$DB" ]; then
        cut -d'|' -f1 "$DB" | sort -u
    else
        echo "(无)"
    fi
    ;;
  disable)
    P="$2"
    [ -z "$P" ] && { echo "用法: autostart.sh disable <包名>"; exit 1; }
    CNT=0
    query_boot_receivers | grep "^${P}/" > /tmp/as_comps.txt
    while read -r comp; do
        [ -z "$comp" ] && continue
        if svc "pm disable --user 0 $comp" >/dev/null 2>&1; then
            echo "${P}|${comp}" >> "$DB"
            log "禁用自启 $comp"
            CNT=$((CNT+1))
        fi
    done < /tmp/as_comps.txt
    echo "已禁用 $P 的开机自启（$CNT 个组件）"
    ;;
  enable)
    P="$2"
    [ -z "$P" ] && { echo "用法: autostart.sh enable <包名>"; exit 1; }
    CNT=0
    grep "^${P}|" "$DB" 2>/dev/null | cut -d'|' -f2 > /tmp/as_restore.txt
    while read -r comp; do
        [ -z "$comp" ] && continue
        if svc "pm enable --user 0 $comp" >/dev/null 2>&1; then
            log "恢复自启 $comp"
            CNT=$((CNT+1))
        fi
    done < /tmp/as_restore.txt
    grep -v "^${P}|" "$DB" > "$DB.tmp" 2>/dev/null
    mv "$DB.tmp" "$DB" 2>/dev/null
    echo "已恢复 $P 的开机自启（$CNT 个组件）"
    ;;
  *)
    echo "用法:"
    echo "  autostart.sh list              列出自启应用"
    echo "  autostart.sh disable <包名>    禁用"
    echo "  autostart.sh enable <包名>     恢复"
    echo "  autostart.sh disabled          列出已禁用"
    ;;
esac
