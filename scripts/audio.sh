#!/system/bin/sh
# Star-Fluency 外放音效调参（Dolby DAX 配置，bind mount 方式，不改分区文件）
# 用法: audio.sh on | off | status
#
# 依据：ieq_warm 预设把 77–329Hz 抬了 7–10dB，而 11U 外放物理上放不出这段，
#       多余能量变成削顶失真（Soom al 实测有破音与高频伴生谐波）。
# 调整：低频少抬、800/1k 少压、Movie 档降强度与 volmax

MODDIR=${MODDIR:-/data/adb/modules/star_fluency}
SF=/data/adb/star-fluency
AD=$SF/audio
SRC=/vendor/etc/dolby/dax-default.xml
TUNED=$MODDIR/audio/dax-tuned.xml
ORIG=$AD/dax-default.orig.xml
LOG=$SF/fluency.log
mkdir -p "$AD" "$MODDIR/audio" 2>/dev/null

log() { echo "$(date '+%m-%d %H:%M:%S') [audio] $*" >> "$LOG" 2>/dev/null; }

case "$1" in
  build)
    [ -f "$SRC" ] || { echo "找不到 $SRC"; exit 1; }
    [ -f "$ORIG" ] || cp -f "$SRC" "$ORIG" 2>/dev/null
    awk '
      # ieq_warm 预设内的低频与中频修正
      /preset id="ieq_warm"/ { inw=1 }
      inw && /band_ieq frequency="77"/    { sub(/target="[0-9-]+"/, "target=\"300\""); }
      inw && /band_ieq frequency="185"/   { sub(/target="[0-9-]+"/, "target=\"350\""); }
      inw && /band_ieq frequency="196"/   { sub(/target="[0-9-]+"/, "target=\"450\""); }
      inw && /band_ieq frequency="329"/   { sub(/target="[0-9-]+"/, "target=\"500\""); }
      inw && /band_ieq frequency="844"/   { sub(/target="[0-9-]+"/, "target=\"-200\""); }
      inw && /band_ieq frequency="1031"/  { sub(/target="[0-9-]+"/, "target=\"-250\""); }
      inw && /<\/preset>/                 { inw=0 }
      # Movie profile 的音箱块：降强度、降 volmax（该段位于 Movie 内）
      /profile id="1" name="Movie"/       { inm=1 }
      inm && /ieq-amount value="13"/      { sub(/value="13"/, "value=\"9\"") }
      inm && /volmax-boost value="52"/    { sub(/value="52"/, "value=\"40\"") }
      inm && /<\/profile>/                { inm=0 }
      { print }
    ' "$ORIG" > "$TUNED"
    echo "已生成 $TUNED（$(wc -c < "$TUNED") 字节）"
    ;;
  on)
    [ -f "$TUNED" ] || sh "$0" build >/dev/null 2>&1
    [ -f "$TUNED" ] || { echo "生成失败"; exit 1; }
    # 已是 bind 状态先卸掉
    mount | grep -q "dax-default.xml" && umount /vendor/etc/dolby/dax-default.xml 2>/dev/null
    if mount -o bind "$TUNED" "$SRC" 2>/dev/null; then
        echo "on" > "$AD/enabled"
        log "外放调参已启用（bind mount）"
        killall audioserver 2>/dev/null
        echo "已启用（音频栈已重载）"
    else
        echo "bind mount 失败（可能 /vendor 不可写或 SELinux 限制）"
        exit 1
    fi
    ;;
  off)
    umount /vendor/etc/dolby/dax-default.xml 2>/dev/null
    echo "off" > "$AD/enabled"
    log "外放调参已还原"
    killall audioserver 2>/dev/null
    echo "已还原为原厂配置（音频栈已重载）"
    ;;
  status)
    if mount | grep -q "dax-default.xml"; then
        echo "state=on"
    else
        echo "state=off"
    fi
    echo "enabled_flag=$(cat "$AD/enabled" 2>/dev/null)"
    echo "tuned_exists=$([ -f "$TUNED" ] && echo yes || echo no)"
    echo "orig_exists=$([ -f "$ORIG" ] && echo yes || echo no)"
    echo "speaker_77=$(grep -A2 'frequency="77"' "$SRC" 2>/dev/null | grep -o 'target="[0-9-]*"' | head -1)"
    ;;
  *)
    echo "用法: audio.sh {build|on|off|status}"
    ;;
esac
