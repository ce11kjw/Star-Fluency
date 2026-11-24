#!/system/bin/sh

JPG="$1"; MP4="$2"; OUT="$3"
say() { echo "[mf] $*"; }
err() { echo "[mf] ERROR: $*" >&2; exit 1; }

[ -n "$JPG" ] && [ -f "$JPG" ] || err "jpg 不存在"
[ -n "$MP4" ] && [ -f "$MP4" ] || err "mp4 不存在"

if grep -aq 'GCamera:MicroVideo' "$JPG"; then
  say "已是动图，跳过"; exit 2
fi

[ "$(od -An -tx1 -N2 "$JPG" | tr -d ' \n')" = "ffd8" ] || err "不是 JPEG"
[ "$(dd if="$MP4" bs=1 skip=4 count=4 2>/dev/null)" = "ftyp" ] || err "mp4 头无效"
MSIZE=$(stat -c%s "$MP4")
JSIZE=$(stat -c%s "$JPG")
[ "$MSIZE" -gt 1000 ] || err "mp4 太小 ($MSIZE)"

NS='http://ns.adobe.com/xap/1.0/'
NSLEN=$(( ${#NS} + 1 ))
XSTART=""; XEND=""
OFF=2; I=0
while [ $I -lt 24 ] && [ $OFF -lt $JSIZE ]; do
  MK=$(dd if="$JPG" bs=1 skip=$OFF count=2 2>/dev/null | od -An -tx1 | tr -d ' \n')
  case "$MK" in
    ffda) break ;;
    ffdb|ffc4|ffdd|fffe|ffc0|ffc1|ffc2|ffc3)
      B=$(dd if="$JPG" bs=1 skip=$((OFF+2)) count=2 2>/dev/null | od -An -tu1 | tr -s ' ')
      set -- $B; OFF=$(( OFF + 2 + $1 * 256 + $2 )); I=$(( I + 1 )) ;;
    ff??)
      B=$(dd if="$JPG" bs=1 skip=$((OFF+2)) count=2 2>/dev/null | od -An -tu1 | tr -s ' ')
      set -- $B; SLEN=$(( $1 * 256 + $2 ))
      [ "$SLEN" -lt 3 ] && break
      if [ "$MK" = "ffe1" ]; then
        H=$(dd if="$JPG" bs=1 skip=$((OFF+4)) count=$(( NSLEN - 1 )) 2>/dev/null)
        if [ "$H" = "$NS" ]; then
          XSTART=$OFF; XEND=$(( OFF + 2 + SLEN )); break
        fi
      fi
      OFF=$(( OFF + 2 + SLEN )); I=$(( I + 1 )) ;;
    *) break ;;
  esac
done

XMP='<x:xmpmeta xmlns:x="adobe:ns:meta/" x:xmptk="Adobe XMP Core 5.1.0-jc003">
  <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
    <rdf:Description rdf:about=""
        xmlns:GCamera="http://ns.google.com/photos/1.0/camera/"
      GCamera:MicroVideoVersion="1"
      GCamera:MicroVideo="1"
      GCamera:MicroVideoOffset="'"$MSIZE"'"
      GCamera:MicroVideoPresentationTimestampUs="0"/>
  </rdf:RDF>
</x:xmpmeta>
'
SEGLEN=$(( 2 + NSLEN + ${#XMP} ))
[ "$SEGLEN" -le 65533 ] || err "XMP 过长 ($SEGLEN)"
HI=$(( SEGLEN >> 8 )); LO=$(( SEGLEN & 255 ))

OUTTMP="${OUT:-${JPG}.mf.tmp}"
[ -f "$OUTTMP" ] && rm -f "$OUTTMP"

if [ -n "$XSTART" ]; then
  say "替换 XMP 段 [$XSTART,$XEND)"
  {
    dd if="$JPG" bs=1 count=$XSTART 2>/dev/null
    printf '\377\341'
    printf "\\$(printf '%03o' $HI)\\$(printf '%03o' $LO)"
    printf '%s\000' "$NS"
    printf '%s' "$XMP"
    dd if="$JPG" bs=1 skip=$XEND 2>/dev/null
    cat "$MP4"
  } > "$OUTTMP" || { rm -f "$OUTTMP"; err "写入失败"; }
  EXPECT=$(( JSIZE - (XEND - XSTART) + 2 + SEGLEN + MSIZE ))
else
  say "插入 XMP 段到 SOI 之后"
  {
    dd if="$JPG" bs=1 count=2 2>/dev/null
    printf '\377\341'
    printf "\\$(printf '%03o' $HI)\\$(printf '%03o' $LO)"
    printf '%s\000' "$NS"
    printf '%s' "$XMP"
    dd if="$JPG" bs=1 skip=2 2>/dev/null
    cat "$MP4"
  } > "$OUTTMP" || { rm -f "$OUTTMP"; err "写入失败"; }
  EXPECT=$(( JSIZE + 2 + SEGLEN + MSIZE ))
fi

OSIZE=$(stat -c%s "$OUTTMP")
if [ "$OSIZE" != "$EXPECT" ]; then
  rm -f "$OUTTMP"; err "大小不符 实际=$OSIZE 期望=$EXPECT"
fi

CHK=$(dd if="$OUTTMP" bs=1 skip=$(( OSIZE - MSIZE + 4 )) count=4 2>/dev/null)
[ "$CHK" = "ftyp" ] || { rm -f "$OUTTMP"; err "校验失败: mp4 起点非 ftyp"; }

say "OK $(basename "$JPG") ${JSIZE}+${MSIZE} -> ${OSIZE}B"
exit 0
