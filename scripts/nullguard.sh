#!/system/bin/sh
# /dev/null 守护
# 注意：这个脚本里绝对不能出现 "2>/dev/null" —— /dev/null 缺失时，重定向会把它创建成普通文件，
# 反而制造故障。所有输出统一写 LOG。
ND=/dev/null
LOG=/data/adb/star-fluency/fluency.log
TS=$(date '+%m-%d %H:%M:%S')
[ -c "$ND" ] && exit 0
{
    echo "$TS [nullguard] 异常：$(ls -l $ND 2>&1)"
} >> "$LOG"
rm -f "$ND"
mknod "$ND" c 1 3
chmod 666 "$ND"
chown root:root "$ND"
chcon u:object_r:null_device:s0 "$ND"
if [ -c "$ND" ]; then
    echo "$TS [nullguard] 已修复为字符设备" >> "$LOG"
else
    echo "$TS [nullguard] 修复失败：$(ls -l $ND 2>&1)" >> "$LOG"
fi
exit 0
