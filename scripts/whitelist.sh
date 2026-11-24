#!/system/bin/sh
# 后台限制白名单
# 被限制的包如果在白名单里，apply 时会跳过
# 用法: whitelist.sh add|del|list <pkg>
#   或 whitelist.sh check <pkg>  → exit 0 在白名单

SF_DIR=/data/adb/star-fluency
WL=$SF_DIR/whitelist.txt
LOG=$SF_DIR/fluency.log
mkdir -p "$SF_DIR" 2>/dev/null

log() { echo "$(date '+%m-%d %H:%M:%S') [wl] $*" >> "$LOG" 2>/dev/null; }

touch "$WL" 2>/dev/null
chmod 600 "$WL" 2>/dev/null

case "$1" in
  add)
    P="$2"
    [ -z "$P" ] && { echo "用法: whitelist.sh add <包名>"; exit 1; }
    if grep -qxF "$P" "$WL" 2>/dev/null; then
        echo "已在白名单: $P"
    else
        echo "$P" >> "$WL"
        log "白名单 + $P"
        echo "已加入白名单: $P"
    fi
    ;;
  del)
    P="$2"
    [ -z "$P" ] && { echo "用法: whitelist.sh del <包名>"; exit 1; }
    if grep -qxF "$P" "$WL" 2>/dev/null; then
        grep -vxF "$P" "$WL" > "$WL.tmp" 2>/dev/null
        mv "$WL.tmp" "$WL" 2>/dev/null
        log "白名单 - $P"
        echo "已移出白名单: $P"
    else
        echo "不在白名单: $P"
    fi
    ;;
  list)
    if [ -s "$WL" ]; then
        cat "$WL"
    else
        echo "(空)"
    fi
    ;;
  check)
    P="$2"
    [ -z "$P" ] && exit 1
    grep -qxF "$P" "$WL" 2>/dev/null && exit 0 || exit 1
    ;;
  *)
    echo "用法: whitelist.sh {add|del|list|check} [包名]"
    ;;
esac
