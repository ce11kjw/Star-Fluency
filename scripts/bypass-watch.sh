#!/system/bin/sh
# 旁路验证监视：每 20 秒记录一次，直到 SOC>=82 或拔电或 90 分钟
B=/sys/class/power_supply/battery
Q=/sys/class/qcom-battery
U=/sys/class/power_supply/usb
L=/data/adb/star-fluency/bypass-watch.log
: > "$L"
echo "# ts soc% i_uA status night_charging temp usb_online ccc" >> "$L"
N=0
while [ $N -lt 270 ]; do
    SOC=$(cat $B/capacity 2>/dev/null)
    I=$(cat $B/current_now 2>/dev/null)
    ST=$(cat $B/status 2>/dev/null)
    NT=$(cat $Q/night_charging 2>/dev/null)
    T=$(cat $B/temp 2>/dev/null)
    ON=$(cat $U/online 2>/dev/null)
    CC=$(cat $B/constant_charge_current 2>/dev/null)
    echo "$(date +%H:%M:%S) $SOC $I $ST $NT $((T / 10)) $ON $CC" >> "$L"
    [ "$ON" != "1" ] && echo "# 拔电退出" >> "$L" && exit 0
    [ "$SOC" -ge 82 ] 2>/dev/null && echo "# 已到 82%，继续观察 10 次" >> "$L" && N=$((N + 260))
    N=$((N + 1))
    sleep 20
done
echo "# 结束" >> "$L"
