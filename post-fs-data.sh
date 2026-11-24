#!/system/bin/sh
# Star-Fluency 早期初始化：只记录原厂值，不改任何参数

MODDIR=${0%/*}
SF_DIR=/data/adb/star-fluency
mkdir -p "$SF_DIR/motion" 2>/dev/null
chmod 700 "$SF_DIR" 2>/dev/null
chmod 755 "$MODDIR"/scripts/*.sh 2>/dev/null

# 此时最接近出厂状态，记录原厂值（只记一次）
sh "$MODDIR/scripts/snapshot.sh" 2>/dev/null
