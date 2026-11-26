#!/system/bin/sh
# /dev/null 守护：必须是字符设备 1,3 且上下文 null_device
ND=/dev/null
LOG=/data/adb/star-fluency/fluency.log
TS=$(date '+%m-%d %H:%M:%S')
L=$(ls -l $ND 2>/dev/null)
case "$L" in
    c*c*1,*3*) exit 0 ;;
esac
echo "$TS [nullguard] /dev/null 异常：$L" >> "$LOG" 2>/dev/null
rm -f $ND 2>/dev/null
mknod $ND c 1 3 2>/dev/null
chmod 666 $ND 2>/dev/null
chown root:root $ND 2>/dev/null
chcon u:object_r:null_device:s0 $ND 2>/dev/null
L2=$(ls -l $ND 2>/dev/null)
case "$L2" in
    c*c*1,*3*) echo "$TS [nullguard] 已修复：$L2" >> "$LOG" 2>/dev/null ;;
    *)         echo "$TS [nullguard] 修复失败：$L2" >> "$LOG" 2>/dev/null ;;
esac
exit 0
