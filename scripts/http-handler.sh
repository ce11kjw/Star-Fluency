#!/system/bin/sh
# Star-Fluency HTTP handler（独立脚本，供 busybox nc -e 调用）

MODDIR=$(dirname "${0%/*}")
[ -d "$MODDIR/webroot" ] || MODDIR=/data/adb/modules/star_fluency
SF_DIR=/data/adb/star-fluency
LOG=$SF_DIR/fluency.log

read -r line 2>/dev/null
method=$(echo "$line" | awk '{print $1}')
path=$(echo "$line" | awk '{print $2}')

while read -r h; do
    h=$(echo "$h" | tr -d '\r')
    [ -z "$h" ] && break
done

# 输出 JSON 字符串（转义 \ 和 "，换行转 \n 用 printf 保证正确）
jstr() {
    printf '%s' "$1" | awk 'BEGIN{ORS=""} {
        gsub(/\\/,"\\\\")
        gsub(/"/,"\\\"")
        gsub(/\t/,"\\t")
        gsub(/\r/,"")
        gsub(/\001/,"")
        print
        if (NR>0) printf "\\n"
    }' | sed 's/\\n$//'
}

send() {
    printf 'HTTP/1.1 200 OK\r\nContent-Type: %s\r\nContent-Length: %d\r\nAccess-Control-Allow-Origin: *\r\nConnection: close\r\n\r\n%s' "$1" "${#2}" "$2"
}

case "$path" in
    /api/status | /api/status\?*)
        body=$(sh /data/adb/modules/star_fluency/scripts/status.sh </dev/null 2>/dev/null)
        send "application/json; charset=utf-8" "$body"
        ;;
    /api/apply*)
        p=$(echo "$path" | sed -n 's/.*profile=\([a-z]*\).*/\1/p')
        [ -z "$p" ] && p=balance
        sh "$MODDIR/scripts/apply.sh" "$p" >/dev/null 2>&1
        send "application/json" '{"ok":true}'
        ;;
    /api/motion*)
        act=$(echo "$path" | sed -n 's/.*action=\([a-z-]*\).*/\1/p')
        case "$act" in
            run)      out=$(sh "$MODDIR/scripts/motion.sh" run 2>&1) ;;
            auto-on)  out=$(sh "$MODDIR/scripts/motion.sh" auto-on 2>&1) ;;
            auto-off) out=$(sh "$MODDIR/scripts/motion.sh" auto-off 2>&1) ;;
            *)        out="" ;;
        esac
        j=$(printf '%s' "$out" | awk 'BEGIN{ORS=""} {gsub(/\\/,"\\\\"); gsub(/"/,"\\\""); printf "%s\\n", $0}' | sed 's/\\n$//')
        send "application/json" "{\"ok\":true,\"out\":\"$j\"}"
        ;;
    /api/trim*)
        k=$(echo "$path" | sed -n 's/.*key=\([a-z]*\).*/\1/p')
        m=$(echo "$path" | sed -n 's/.*mode=\([a-z]*\).*/\1/p')
        [ -z "$k" ] && k=pa
        [ -z "$m" ] && m=apply
        sh "$MODDIR/scripts/trim.sh" "$m" "$k" >/dev/null 2>&1
        CF=$SF_DIR/config.conf
        UP=$(echo "$k" | tr a-z A-Z)
        V=0; [ "$m" = "apply" ] && V=1
        touch "$CF" 2>/dev/null
        if grep -q "^TRIM_$UP=" "$CF" 2>/dev/null; then
            sed -i "s|^TRIM_$UP=.*|TRIM_$UP=$V|" "$CF"
        else
            echo "TRIM_$UP=$V" >> "$CF"
        fi
        send "application/json" '{"ok":true}'
        ;;
    /api/camidle*)
        v=$(echo "$path" | sed -n 's/.*v=\([01]\).*/\1/p')
        [ -z "$v" ] && v=0
        CF=$SF_DIR/config.conf
        touch "$CF" 2>/dev/null
        if grep -q '^CAM_IDLE_KILL=' "$CF" 2>/dev/null; then
            sed -i "s|^CAM_IDLE_KILL=.*|CAM_IDLE_KILL=$v|" "$CF"
        else
            echo "CAM_IDLE_KILL=$v" >> "$CF"
        fi
        send "application/json" '{"ok":true}'
        ;;
    /api/log)
        body=$(tail -n 80 "$LOG" 2>/dev/null | awk 'BEGIN{ORS=""} {gsub(/\\/,"\\\\"); gsub(/"/,"\\\""); printf "%s\\n", $0}' | sed 's/\\n$//')
        send "application/json" "{\"log\":\"$body\"}"
        ;;
    /api/sh*)
        cmd=$(echo "$path" | sed -n 's/.*cmd=\(.*\)$/\1/p' | sed 's/%20/ /g; s/%2F/\//g; s/%3B/;/g; s/%24/$/g; s/%22/"/g; s/%7C/|/g; s/%26/\&/g' | sed "s/%27/'/g")
        code=0; out=""
        case "$cmd" in
            *star-fluency*|*star_fluency*)
                out=$(sh -c "$cmd" 2>&1); code=$?
                ;;
            *) code=1; out="not allowed" ;;
        esac
        j=$(printf '%s' "$out" | awk 'BEGIN{ORS=""} {gsub(/\\/,"\\\\"); gsub(/"/,"\\\""); printf "%s\\n", $0}' | sed 's/\\n$//')
        send "application/json" "{\"code\":$code,\"out\":\"$j\",\"err\":\"\"}"
        ;;
    / | /index.html)
        f="$MODDIR/webroot/index.html"
        if [ -f "$f" ]; then
            printf 'HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: %d\r\nConnection: close\r\n\r\n' "$(stat -c%s "$f")"
            cat "$f"
        else
            printf 'HTTP/1.1 404 Not Found\r\nContent-Length: 2\r\nConnection: close\r\n\r\nno'
        fi
        ;;
    *)
        printf 'HTTP/1.1 404 Not Found\r\nContent-Length: 2\r\nConnection: close\r\n\r\nno'
        ;;
esac
