#!/system/bin/sh
# Star-Fluency 电池采样守护（60s 一轮）
# 目的：用库仑计差分算真实容量，不依赖系统那个单点值
#   samples.tsv   ts soc cc v i temp status
#   segments.tsv  ts start_soc end_soc dcc cap_mah hours temp
#   ir.tsv        ts ir_mohm v i

SF_DIR=/data/adb/star-fluency
BD=$SF_DIR/battery
B=/sys/class/power_supply/battery
MINDROP=25          # 区段最小 ΔSOC
mkdir -p "$BD" 2>/dev/null
echo $$ > "$BD/battd.pid" 2>/dev/null

log() { echo "$(date '+%m-%d %H:%M:%S') [battd] $*" >> "$SF_DIR/fluency.log" 2>/dev/null; }

sample() {
    TS=$(date +%s)
    SOC=$(cat $B/capacity 2>/dev/null)
    CC=$(cat $B/charge_counter 2>/dev/null)
    V=$(cat $B/voltage_now 2>/dev/null)
    I=$(cat $B/current_now 2>/dev/null)
    T=$(cat $B/temp 2>/dev/null)
    ST=$(cat $B/status 2>/dev/null)
    [ -z "$SOC" ] && return 1
    [ -z "$CC" ] && return 1
    [ -z "$T" ] && T=0
    [ -z "$V" ] && V=0
    [ -z "$I" ] && I=0

    echo "$TS $SOC $CC $V $I $T $ST" >> "$BD/samples.tsv"

    # ---- 内阻采样：相邻两点电流差 >= 300mA ----
    PREV=$(tail -2 "$BD/samples.tsv" 2>/dev/null | head -1)
    if [ -n "$PREV" ]; then
        pTS=$(echo "$PREV" | awk '{print $1}')
        pV=$(echo "$PREV" | awk '{print $4}')
        pI=$(echo "$PREV" | awk '{print $5}')
        pST=$(echo "$PREV" | awk '{print $7}')
        [ -z "$pTS" ] && pTS=0
        DT=$((TS - pTS))
        if [ "$DT" -le 180 ] && [ "$pST" = "$ST" ] && [ "$pV" -gt 0 ] && [ "$I" -gt 0 ]; then
            awk -v ts="$TS" -v v0="$pV" -v i0="$pI" -v v1="$V" -v i1="$I" -v out="$BD/ir.tsv" 'BEGIN{
                di = (i1 > i0) ? i1 - i0 : i0 - i1;
                if (di < 500000) exit;   # 要求 ΔI >= 0.5A，避免小电流噪声
                dv = (v1 > v0) ? v1 - v0 : v0 - v1;
                ir = dv / di * 1000;   # µV/µA = Ω -> mΩ
                if (ir < 25 || ir > 600) exit;   # 手机电芯合理区间
                printf "%s %.1f %s %s\n", ts, ir, v1, i1 >> out;
            }'
        fi
    fi

    # ---- 区段切分：只在放电时累计 ----
    SEG="$BD/seg.state"
    if [ "$ST" != "Discharging" ]; then
        rm -f "$SEG" 2>/dev/null
        return 0
    fi
    # 极端温度段不计入
    if [ "$T" -lt 100 ] || [ "$T" -gt 430 ]; then
        rm -f "$SEG" 2>/dev/null
        return 0
    fi

    if [ ! -f "$SEG" ]; then
        echo "$TS $SOC $CC $T" > "$SEG"
        return 0
    fi

    sTS=$(awk '{print $1}' "$SEG")
    sSOC=$(awk '{print $2}' "$SEG")
    sCC=$(awk '{print $3}' "$SEG")

    # SOC 回升（充过电）就以当前为起点重来
    if [ "$SOC" -ge "$sSOC" ]; then
        echo "$TS $SOC $CC $T" > "$SEG"
        return 0
    fi

    DROP=$((sSOC - SOC))
    if [ "$DROP" -lt "$MINDROP" ]; then
        return 0
    fi

    HOURS=$(awk -v a="$sTS" -v b="$TS" 'BEGIN{printf "%.2f", (b-a)/3600.0}')
    echo "$TS $sSOC $SOC $((sCC - CC)) 0 $HOURS $T" | awk '{
        dcc = $4; drop = $2 - $3;
        if (drop <= 0 || dcc <= 0) exit;
        cap = dcc * 100 / drop / 1000;      # mAh
        if (cap < 2000 || cap > 6500) exit;
        printf "%s %s %s %s %.0f %s %s\n", $1, $2, $3, $4, cap, $6, $7 >> "'"$BD"'/segments.tsv";
    }'
    log "完成一个放电区段: ${sSOC}% -> ${SOC}% 用时 ${HOURS}h"
    echo "$TS $SOC $CC $T" > "$SEG"
}

# 滚动清理：样本保留 7 天，内阻保留 2000 条
trim() {
    CUT=$(( $(date +%s) - 604800 ))
    if [ -f "$BD/samples.tsv" ]; then
        awk -v c="$CUT" '$1 >= c' "$BD/samples.tsv" > "$BD/samples.tmp" 2>/dev/null && mv "$BD/samples.tmp" "$BD/samples.tsv"
    fi
    if [ -f "$BD/ir.tsv" ]; then
        tail -2000 "$BD/ir.tsv" > "$BD/ir.tmp" 2>/dev/null && mv "$BD/ir.tmp" "$BD/ir.tsv"
    fi
}

case "$1" in
  once) sample; exit 0 ;;
esac

N=0
while true; do
    sample
    N=$((N + 1))
    [ $((N % 60)) -eq 0 ] && trim
    sleep 60
done
