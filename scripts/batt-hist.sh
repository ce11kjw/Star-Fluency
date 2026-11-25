#!/system/bin/sh
# 电池历史曲线数据（降采样）+ 导出
# 用法: batt-hist.sh [小时=24] [最大点数=120]
#       batt-hist.sh export
MODDIR=${MODDIR:-/data/adb/modules/star_fluency}
SF=/data/adb/star-fluency
F=$SF/battery/samples.tsv

if [ "$1" = "export" ]; then
    OUT=/sdcard/Download/star-fluency-battery-$(date +%m%d-%H%M).csv
    if [ -s "$F" ]; then
        { echo "timestamp,time,soc,charge_uAh,voltage_uV,current_uA,temp_C,status"; \
          awk '{cmd="date -d @"$1" +%H:%M:%S"; cmd | getline t; close(cmd); printf "%s,%s,%s,%s,%s,%s,%.1f,%s\n",$1,t,$2,$3,$4,$5,$6/10,$7}' "$F"; } > "$OUT" 2>/dev/null
        echo "已导出: $OUT（$(wc -l < "$OUT") 行）"
    else
        echo "没有采样数据"
    fi
    exit 0
fi

H=${1:-24}
MAX=${2:-120}
NOW=$(date +%s)
START=$((NOW - H * 3600))

awk -v start="$START" -v now="$NOW" -v max="$MAX" '
  ($1 + 0) >= start { n++; ts[n] = $1; soc[n] = $2; tp[n] = $6 / 10 }
  END {
    if (n == 0) { printf "{\"from\":%d,\"to\":%d,\"n\":0,\"pts\":[],\"tpts\":[]}\n", start, now; exit }
    span = now - start; if (span <= 0) span = 1
    bucket = span / max; if (bucket < 60) bucket = 60
    for (i = 1; i <= n; i++) {
      b = int((ts[i] - start) / bucket)
      ss[b] += soc[i]; tt[b] += tp[i]; c[b]++
      if (ts[i] > last[b]) last[b] = ts[i]
      if (soc[i] > hmax) hmax = soc[i]
      if (soc[i] < hmin || hmin == 0) hmin = soc[i]
    }
    p = ""; q = ""
    for (b = 0; b <= max; b++) {
      if (c[b] > 0) {
        sv = int(ss[b] / c[b] + 0.5)
        tv = int(tt[b] / c[b] + 0.5)
        p = p (p == "" ? "" : ",") "[" last[b] "," sv "]"
        q = q (q == "" ? "" : ",") "[" last[b] "," tv "]"
      }
    }
    printf "{\"from\":%d,\"to\":%d,\"n\":%d,\"soc_min\":%d,\"soc_max\":%d,\"pts\":[%s],\"tpts\":[%s]}\n", start, now, n, hmin, hmax, p, q
  }' "$F"
