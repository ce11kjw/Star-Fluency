#!/system/bin/sh
# Star-Fluency 公共函数

SF_DIR=/data/adb/star-fluency
SF_CONF=$SF_DIR/config.conf
SF_STOCK=$SF_DIR/stock.txt
SF_LOG=$SF_DIR/fluency.log

mkdir -p "$SF_DIR" 2>/dev/null
chmod 700 "$SF_DIR" 2>/dev/null

sf_log() {
    echo "$(date '+%m-%d %H:%M:%S') $*" >> "$SF_LOG" 2>/dev/null
    [ -f "$SF_LOG" ] && [ "$(stat -c%s "$SF_LOG" 2>/dev/null || echo 0)" -gt 262144 ] && tail -n 800 "$SF_LOG" > "$SF_LOG.tmp" 2>/dev/null && mv -f "$SF_LOG.tmp" "$SF_LOG" 2>/dev/null
}

sf_get() {
    local k="$1" d="$2" v=""
    [ -f "$SF_CONF" ] && v=$(grep -E "^${k}=" "$SF_CONF" 2>/dev/null | tail -1 | cut -d= -f2-)
    [ -z "$v" ] && v="$d"
    echo "$v"
}

sf_set() {
    local k="$1" v="$2"
    touch "$SF_CONF" 2>/dev/null
    chmod 600 "$SF_CONF" 2>/dev/null
    if grep -qE "^${k}=" "$SF_CONF" 2>/dev/null; then
        sed -i "s|^${k}=.*|${k}=${v}|" "$SF_CONF" 2>/dev/null
    else
        echo "${k}=${v}" >> "$SF_CONF"
    fi
}

# 写节点（带原厂值备份）
sf_write() {
    local node="$1" val="$2"
    [ -e "$node" ] || { sf_log "SKIP 节点不存在 $node"; return 1; }
    local cur
    cur=$(cat "$node" 2>/dev/null)
    [ "$cur" = "$val" ] && return 0
    if echo "$val" > "$node" 2>/dev/null; then
        local now
        now=$(cat "$node" 2>/dev/null)
        if [ "$now" = "$val" ]; then
            sf_log "OK   $node : $cur -> $val"
            return 0
        fi
        sf_log "FAIL $node : 写入后读回='$now' 期望='$val'"
        return 1
    fi
    sf_log "FAIL $node : 写入被拒"
    return 1
}

# 读原厂值（只在第一次记录）
sf_snap() {
    local key="$1" node="$2"
    [ -f "$SF_STOCK" ] && grep -qE "^${key}=" "$SF_STOCK" 2>/dev/null && return 0
    local v
    v=$(cat "$node" 2>/dev/null)
    [ -z "$v" ] && return 0
    echo "${key}=${v}" >> "$SF_STOCK" 2>/dev/null
    chmod 600 "$SF_STOCK" 2>/dev/null
}

sf_stock_of() {
    local key="$1"
    [ -f "$SF_STOCK" ] && grep -E "^${key}=" "$SF_STOCK" 2>/dev/null | tail -1 | cut -d= -f2-
}
