#!/system/bin/sh
# Star-Fluency 系统精简：单项可开可关
# 用法: trim.sh apply|revert <key>
#   pa     负一屏
#   gms    谷歌服务后台
#   anim   动画缩放
#   play   Play 商店自动更新 + 后台
#   appbrand 微信小程序容器闲置清理（由 cam-idle 类的守护处理）
#   ner   小米 NER 语义服务

MODE="$1"
KEY="$2"
LOG=/data/adb/star-fluency/fluency.log
mkdir -p /data/adb/star-fluency 2>/dev/null

log() { echo "$(date '+%m-%d %H:%M:%S') [trim] $*" >> "$LOG" 2>/dev/null; }

PA=com.miui.personalassistant
GMS=com.google.android.gms
PLAY=com.android.vending
NER=com.xiaomi.aiservice

# 用 su -c 包一层，确保 appops/pm/settings 在正确 SELinux 域下执行
svc() { su -c "$*" 2>/dev/null || eval "$*" 2>/dev/null; }

case "$KEY" in
  pa|gms|play|ner)
    WLP=com.miui.personalassistant
    [ "$KEY" = "gms" ] && WLP=com.google.android.gms
    [ "$KEY" = "play" ] && WLP=com.android.vending
    [ "$KEY" = "ner" ] && WLP=com.xiaomi.aiservice
    if [ "$MODE" = "apply" ] && sh /data/adb/modules/star_fluency/scripts/whitelist.sh check "$WLP" 2>/dev/null; then
        log "$WLP 在白名单，跳过限制"
        exit 0
    fi
    ;;
esac

case "$KEY" in
  pa)
    if [ "$MODE" = "apply" ]; then
      svc "pm suspend $PA"
      svc "appops set $PA RUN_IN_BACKGROUND ignore"
      svc "appops set $PA RUN_ANY_IN_BACKGROUND ignore"
      log "负一屏已限制"
    else
      svc "pm unsuspend $PA"
      svc "appops set $PA RUN_IN_BACKGROUND allow"
      svc "appops set $PA RUN_ANY_IN_BACKGROUND allow"
      log "负一屏已恢复"
    fi
    ;;
  gms)
    if [ "$MODE" = "apply" ]; then
      svc "appops set $GMS RUN_IN_BACKGROUND ignore"
      log "GMS 后台已限制"
    else
      svc "appops set $GMS RUN_IN_BACKGROUND allow"
      log "GMS 后台已恢复"
    fi
    ;;
  anim)
    if [ "$MODE" = "apply" ]; then
      svc "settings put global window_animation_scale 0.5"
      svc "settings put global transition_animation_scale 0.5"
      svc "settings put global animator_duration_scale 0.5"
      log "动画缩放 -> 0.5"
    else
      svc "settings put global window_animation_scale 1.0"
      svc "settings put global transition_animation_scale 1.0"
      svc "settings put global animator_duration_scale 1.0"
      log "动画缩放 -> 1.0"
    fi
    ;;
  play)
    if [ "$MODE" = "apply" ]; then
      # auto_update_mode: 0=从不自动更新  1=总是  2=仅WiFi  3=默认
      svc "settings put global auto_update_mode 0"
      svc "settings put global auto_update_apps 0"
      svc "appops set $PLAY RUN_IN_BACKGROUND ignore"
      svc "appops set $PLAY WAKE_LOCK ignore"
      svc "am force-stop $PLAY"
      log "Play 商店：关自动更新 + 后台限制 + 挂起"
    else
      svc "settings put global auto_update_mode 1"
      svc "settings delete global auto_update_apps"
      svc "appops set $PLAY RUN_IN_BACKGROUND allow"
      svc "appops set $PLAY WAKE_LOCK allow"
      true
      log "Play 商店已恢复"
    fi
    ;;
  ner)
    if [ "$MODE" = "apply" ]; then
      svc "appops set $NER RUN_IN_BACKGROUND ignore"
      svc "appops set $NER RUN_ANY_IN_BACKGROUND ignore"
      log "小米 NER 语义服务后台已限制"
    else
      svc "appops set $NER RUN_IN_BACKGROUND allow"
      svc "appops set $NER RUN_ANY_IN_BACKGROUND allow"
      log "小米 NER 已恢复"
    fi
    ;;
  *)
    echo "用法: trim.sh apply|revert {pa|gms|anim|play|ner}"
    ;;
esac
