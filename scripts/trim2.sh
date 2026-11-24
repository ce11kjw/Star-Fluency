#!/system/bin/sh
# 扩展精简项：小米商店 / 内容中心 / 缓存进程数 / GMS 精简
# 用法: trim2.sh apply|revert <key>
#   market  小米应用商店
#   content 内容中心（com.miui.contentextension）
#   cached  缓存进程数上限
#   gms     GMS 非核心组件

MODE="$1"
KEY="$2"
LOG=/data/adb/star-fluency/fluency.log
SF_DIR=/data/adb/star-fluency
mkdir -p "$SF_DIR" 2>/dev/null

log() { echo "$(date '+%m-%d %H:%M:%S') [trim2] $*" >> "$LOG" 2>/dev/null; }
svc() { su -c "$*" 2>/dev/null || eval "$*" 2>/dev/null; }

MARKET=com.xiaomi.market
CONTENT=com.miui.contentextension

case "$KEY" in
  market|content)
    WLP=com.xiaomi.market
    [ "$KEY" = "content" ] && WLP=com.miui.contentextension
    if [ "$MODE" = "apply" ] && sh /data/adb/modules/star_fluency/scripts/whitelist.sh check "$WLP" 2>/dev/null; then
        log "$WLP 在白名单，跳过限制"
        exit 0
    fi
    ;;
esac

case "$KEY" in
  market)
    if [ "$MODE" = "apply" ]; then
      svc "appops set $MARKET RUN_IN_BACKGROUND ignore"
      svc "appops set $MARKET RUN_ANY_IN_BACKGROUND ignore"
      svc "am force-stop $MARKET"
      log "小米应用商店后台已限制"
    else
      svc "appops set $MARKET RUN_IN_BACKGROUND allow"
      svc "appops set $MARKET RUN_ANY_IN_BACKGROUND allow"
      log "小米应用商店已恢复"
    fi
    ;;
  content)
    if [ "$MODE" = "apply" ]; then
      svc "appops set $CONTENT RUN_IN_BACKGROUND ignore"
      svc "appops set $CONTENT RUN_ANY_IN_BACKGROUND ignore"
      svc "am force-stop $CONTENT"
      log "内容中心后台已限制"
    else
      svc "appops set $CONTENT RUN_IN_BACKGROUND allow"
      svc "appops set $CONTENT RUN_ANY_IN_BACKGROUND allow"
      log "内容中心已恢复"
    fi
    ;;
  cached)
    if [ "$MODE" = "apply" ]; then
      # max_cached_processes：控制后台缓存进程数量
      svc "settings put global activity_manager_constants max_cached_processes=64"
      log "缓存进程上限 -> 64"
    else
      svc "settings delete global activity_manager_constants"
      log "缓存进程上限已恢复默认"
    fi
    ;;
  gms)
    if [ "$MODE" = "apply" ]; then
      sh /data/adb/modules/star_fluency/scripts/gms-slim.sh apply
    else
      sh /data/adb/modules/star_fluency/scripts/gms-slim.sh revert
    fi
    ;;
  *)
    echo "用法: trim2.sh apply|revert {market|content|cached|gms}"
    ;;
esac
