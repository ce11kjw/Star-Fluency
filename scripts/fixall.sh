#!/system/bin/sh

MODDIR=${0%/*}
[ -f "$MODDIR/mf.sh" ] || MODDIR=/data/adb/modules/motionfix/bin
MF="$MODDIR/mf.sh"
DRY=0
[ "$1" = "--dry" ] && DRY=1

STATE=/data/adb/motionfix
CONF=$STATE/config.conf
mkdir -p "$STATE" 2>/dev/null

getconf() {
  local k="$1" d="$2" v=""
  [ -f "$CONF" ] && v=$(grep -E "^${k}=" "$CONF" 2>/dev/null | tail -1 | cut -d= -f2-)
  [ -z "$v" ] && v="$d"
  echo "$v"
}

PENDING=$(getconf PENDING_DIR /data/user/0/com.android.camera/files/livephoto_pending)
CAMERA=$(getconf CAMERA_DIR /sdcard/DCIM/Camera)
BACKUP=$(getconf BACKUP 1)
LOGF=$(getconf LOG "$STATE/motionfix.log")
CLEANUP=$(getconf CLEANUP 0)

say() { echo "[batch] $*"; }
log() { echo "$(date '+%m-%d %H:%M:%S') $*" >> "$LOGF" 2>/dev/null; }

[ -d "$PENDING" ] || { say "pending 目录不存在: $PENDING"; exit 0; }

N_OK=0; N_SKIP=0; N_FAIL=0; N_MP4=0
for MP4 in "$PENDING"/microvideo_*.mp4; do
  [ -f "$MP4" ] || continue
  N_MP4=$(( N_MP4 + 1 ))
  BASE=${MP4##*/microvideo_}
  BASE=${BASE%.mp4}
  JPG="$CAMERA/$BASE.jpg"

  if [ ! -f "$JPG" ]; then
    say "缺 jpg: $BASE"; log "FAIL nojpg $BASE"; N_FAIL=$(( N_FAIL + 1 )); continue
  fi

  if grep -aq 'GCamera:MicroVideo' "$JPG"; then
    say "已合成: $BASE"; log "SKIP $BASE"
    if [ "$CLEANUP" = "1" ] && [ "$DRY" = "0" ]; then rm -f "$MP4"; fi
    N_SKIP=$(( N_SKIP + 1 )); continue
  fi

  if [ "$DRY" = "1" ]; then
    say "[dry] 待修复: $BASE ($(stat -c%s "$MP4")B)"; N_OK=$(( N_OK + 1 )); continue
  fi

  MT=$(stat -c%y "$JPG" 2>/dev/null)
  TMP="$JPG.mfx"
  rm -f "$TMP"

  if sh "$MF" "$JPG" "$MP4" "$TMP" > /tmp/mf_out 2>&1; then
    if [ "$BACKUP" = "1" ]; then
      mkdir -p "$STATE/backup" 2>/dev/null
      cp -a "$JPG" "$STATE/backup/$BASE.jpg" 2>/dev/null || say "  备份失败"
    fi
    if mv -f "$TMP" "$JPG"; then
      chown media_rw:media_rw "$JPG" 2>/dev/null
      chmod 660 "$JPG" 2>/dev/null
      [ -n "$MT" ] && touch -d "$MT" "$JPG" 2>/dev/null
      say "修复: $BASE"; log "OK $BASE"
      [ "$CLEANUP" = "1" ] && rm -f "$MP4"
      N_OK=$(( N_OK + 1 ))
    else
      say "移动失败: $BASE"; log "FAIL move $BASE"; N_FAIL=$(( N_FAIL + 1 ))
    fi
  else
    E=$(tail -1 /tmp/mf_out 2>/dev/null)
    say "失败: $BASE -> $E"; log "FAIL $BASE $E"
    rm -f "$TMP"; N_FAIL=$(( N_FAIL + 1 ))
  fi
done

if [ "$N_MP4" -eq 0 ]; then say "没有待处理的微视频"; exit 0; fi

say "完成: 修复 $N_OK / 跳过 $N_SKIP / 失败 $N_FAIL"
log "SUMMARY ok=$N_OK skip=$N_SKIP fail=$N_FAIL"

if [ "$N_OK" -gt 0 ] && [ "$DRY" = "0" ]; then
  content call --uri content://media --method scan_volume --arg external_primary >/dev/null 2>&1
fi
exit 0
