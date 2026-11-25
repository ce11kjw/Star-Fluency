#!/system/bin/sh
# 电池历史曲线数据：从 battery/samples.tsv 抽样输出 JSON
# 用法: battery-history.sh [小时数] [点数]
# 输出: {"points":[[ts,soc,temp,pwr],...],"max":N,"count":M}

SF=/data/adb/star-fluency
BD=$SF/battery
HOURS=${1:-24}
POINTS=${2:-48}
S=$BD/samples.tsv

[ -s "$S" ] || { echo '{"points":[],"max":0,"count":0}'; exit 0; }

CUT=$(( $(date +%s) - HOURS * 3600 ))

# 只取窗口内、状态正常的样本，按时间等间隔抽样
awk -v cut="$CUT" -v want="$POINTS" '
  BEGIN { n=0 }
  {
    ts=$1; soc=$2; v=$4; i=$5; t=$6; st=$7;
    if (ts+0 < cut+0) next;
    if (soc+0 < 0 || soc+0 > 100) next;
    rows[++n] = ts " " soc " " int(t/10) " " v " " i;
  }
  END {
    if (n == 0) { printf "{\"points\":[],\"max\":0,\"count\":0}\n"; exit }
    step = (n > want) ? int(n / want) : 1;
    [step < 1] && step = 1;
    printf "{\"points\":[";
    out = 0;
    for (k = 1; k <= n; k += step) {
      split(rows[k], f, " ");
      p = f[4] * (f[5] < 0 ? -f[5] : f[5]) / 1000000000;
      if (out++) printf ",";
      printf "[%s,%s,%s,%.1f]", f[1], f[2], f[3], p;
    }
    printf "],\"max\":%d,\"count\":%d}\n", n, n;
  }
' "$S"
