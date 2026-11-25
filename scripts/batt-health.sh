#!/system/bin/sh
# Star-Fluency 电池容量/健康度估算
# 用法: batt-health.sh [数据目录]
# 输出 key=value

BD=${1:-/data/adb/star-fluency/battery}
B=/sys/class/power_supply/battery

DESIGN=$(cat $B/charge_full_design 2>/dev/null)
FULL=$(cat $B/charge_full 2>/dev/null)
CYC=$(cat $B/cycle_count 2>/dev/null)
[ -z "$DESIGN" ] && DESIGN=0
[ -z "$FULL" ] && FULL=0
[ -z "$CYC" ] && CYC=0
DESIGN_MAH=$((DESIGN / 1000))
FULL_MAH=$((FULL / 1000))

# 系统值（单点推算）
SYS_H=0
[ "$DESIGN_MAH" -gt 0 ] && SYS_H=$(awk -v f="$FULL_MAH" -v d="$DESIGN_MAH" 'BEGIN{printf "%.0f", f*100/d}')

# 实测值：最近 5 个区段取中位数
SEGS=0
MEAS_MAH=0
if [ -f "$BD/segments.tsv" ]; then
    SEGS=$(wc -l < "$BD/segments.tsv" 2>/dev/null | tr -d ' ')
    [ -z "$SEGS" ] && SEGS=0
    if [ "$SEGS" -gt 0 ]; then
        MEAS_MAH=$(tail -5 "$BD/segments.tsv" | awk '{print $5}' | sort -n | awk '{a[NR]=$1} END{ if(NR==0) print 0; else if(NR%2) print a[(NR+1)/2]; else print int((a[NR/2]+a[NR/2+1])/2) }')
    fi
fi
[ -z "$MEAS_MAH" ] && MEAS_MAH=0
MEAS_H=0
[ "$MEAS_MAH" -gt 0 ] && [ "$DESIGN_MAH" -gt 0 ] && MEAS_H=$(awk -v m="$MEAS_MAH" -v d="$DESIGN_MAH" 'BEGIN{printf "%.0f", m*100/d}')

# 内阻：近 50 条中位数 + 相对首条的趋势
IR=0
IR_TREND=0
IR_N=0
if [ -f "$BD/ir.tsv" ]; then
    IR_N=$(wc -l < "$BD/ir.tsv" 2>/dev/null | tr -d ' ')
    [ -z "$IR_N" ] && IR_N=0
    if [ "$IR_N" -gt 0 ]; then
        IR=$(tail -50 "$BD/ir.tsv" | awk '{print $2}' | sort -n | awk '{a[NR]=$1} END{ if(NR==0) print 0; else if(NR%2) print a[(NR+1)/2]; else printf "%.1f", (a[NR/2]+a[NR/2+1])/2 }')
        FIRST=$(head -1 "$BD/ir.tsv" | awk '{print $2}')
        [ -n "$FIRST" ] && IR_TREND=$(awk -v a="$IR" -v b="$FIRST" 'BEGIN{ if(b>0) printf "%.0f", (a-b)*100/b; else print 0 }')
    fi
fi

# 最终健康度：有实测用实测，否则系统值
HEALTH=$SYS_H
SRC=system
if [ "$MEAS_H" -gt 0 ]; then
    HEALTH=$MEAS_H
    SRC=measured
fi

echo "design_mah=$DESIGN_MAH"
echo "sys_mah=$FULL_MAH"
echo "sys_health=$SYS_H"
echo "meas_mah=$MEAS_MAH"
echo "meas_health=$MEAS_H"
echo "health=$HEALTH"
echo "health_src=$SRC"
echo "cycles=$CYC"
echo "segs=$SEGS"
echo "ir_mohm=$IR"
echo "ir_trend=$IR_TREND"
echo "ir_n=$IR_N"
