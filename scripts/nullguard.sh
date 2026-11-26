#!/system/bin/sh
# /dev/null 守护
# 重要：本脚本里禁止出现 "2>/dev/null"（/dev/null 缺失时重定向会把它建成普通文件）
# 还想说清楚一个事实：rm + mknod 会换掉 inode，而 zygote 的 allowlist 只认开机时那个 inode，
# 所以重建之后 webview_zygote 会 abort（"Not allowlisted (92): /dev/null (deleted)"），
# 表现就是所有 WebView 页面（含各模块的 KSU/APatch WebUI）都打不开 —— 必须重启才能恢复。
ND=/dev/null
LOG=/data/adb/star-fluency/fluency.log
TS=$(date '+%m-%d %H:%M:%S')
[ -c "$ND" ] && exit 0
{
    echo "$TS [nullguard] /dev/null 异常：$(ls -l $ND 2>&1)"
} >> "$LOG"
rm -f "$ND"
mknod "$ND" c 1 3
chmod 666 "$ND"
chown root:root "$ND"
chcon u:object_r:null_device:s0 "$ND"
if [ -c "$ND" ]; then
    echo "$TS [nullguard] 已重建为字符设备；⚠️ 更换 inode 后 webview_zygote 会拒绝启动，需要重启才能恢复模块 WebUI" >> "$LOG"
    touch /data/adb/star-fluency/NEED_REBOOT 2>/dev/null
else
    echo "$TS [nullguard] 修复失败：$(ls -l $ND 2>&1)" >> "$LOG"
fi
exit 0
