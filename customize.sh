#!/system/bin/sh
# 安装初始化

MODDIR=${0%/*}
SF_DIR=/data/adb/star-fluency

mkdir -p "$SF_DIR/motion" 2>/dev/null
chmod 700 "$SF_DIR" 2>/dev/null

# 初始化配置
CONF=$SF_DIR/config.conf
if [ ! -f "$CONF" ]; then
    cat > "$CONF" <<'EOFCONF'
PROFILE=balance
TRIM_PA=0
TRIM_GMS=0
TRIM_ANIM=0
CAM_IDLE_KILL=0
EOFCONF
    chmod 600 "$CONF" 2>/dev/null
fi

# 授权执行
chmod 755 "$MODDIR"/scripts/*.sh 2>/dev/null
chmod 755 "$MODDIR"/post-fs-data.sh "$MODDIR"/service.sh 2>/dev/null

ui_print "- Star-Fluency 安装完成"
ui_print "- 档位默认：平衡"
ui_print "- 可在管理器中打开 WebUI 切换"
