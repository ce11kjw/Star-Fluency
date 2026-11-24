#!/system/bin/sh
# GMS 非核心服务精简
# 只禁用 analytics/测量/附近共享/个人安全/晕车辅助等，不动 gcm/auth/location/chimera 核心
# 用法: gms-slim.sh apply|revert|status

MODE="$1"
LOG=/data/adb/star-fluency/fluency.log
GMS=com.google.android.gms

log() { echo "$(date '+%m-%d %H:%M:%S') [gms] $*" >> "$LOG" 2>/dev/null; }

# 可安全禁用的组件（全部为可选功能，不影响推送/定位/账号/Play商店）
COMPONENTS="
com.google.android.gms/.nearby.presence.service.LifeCycleService
com.google.android.gms/.nearby.sharing.ReceiveSurfaceService
com.google.android.gms/.nearby.sharing.SendSurfaceService
com.google.android.gms/.nearby.discovery.service.DiscoveryService
com.google.android.gms/.motionsicknessassist.persistent.MotionSicknessAssistPersistentService
com.google.android.gms/.remotegestures.api.RemoteGesturesService
com.google.android.gms/.personalsafety.service.SndDetectionService
com.google.android.gms/.personalsafety.service.PSAService
com.google.android.gms/.personalsafety.service.PersonalSafetyService
com.google.android.gms/.personalsafety.service.LockingTrustAgentService
com.google.android.gms/.magictether.service.TetherService
com.google.android.gms/.magictether.wifisync.WifiSyncService
com.google.android.gms/.crisisalerts.init.CrisisAlertsPersistentService
com.google.android.gms/.semanticlocation.service.SemanticLocationService
com.google.android.gms/.clearcut.debug.ClearcutDebugDumpService
com.google.android.gms/.mdm.services.SecureLockService
com.google.android.gms/.advancedprotection.service.AdvancedProtectionSyncService
com.google.android.gms/.cast.devicesuggestions.SuggestionsProviderChimeraService
com.google.android.gms/.thunderbird.EmergencyPersistentService
"

svc() { su -c "$*" 2>/dev/null || eval "$*" 2>/dev/null; }

case "$MODE" in
  apply)
    N=0
    echo "$COMPONENTS" | while read -r c; do
        [ -z "$c" ] && continue
        svc "pm disable --user 0 $c" >/dev/null 2>&1 && N=$((N+1))
    done
    touch /data/adb/star-fluency/gms_slimmed
    log "GMS 非核心组件已禁用"
    # 重启 GMS 让禁用生效（会短暂影响推送，几秒后恢复）
    svc "am force-stop $GMS"
    log "GMS 已重启"
    echo "done"
    ;;
  revert)
    echo "$COMPONENTS" | while read -r c; do
        [ -z "$c" ] && continue
        svc "pm enable --user 0 $c" >/dev/null 2>&1
    done
    rm -f /data/adb/star-fluency/gms_slimmed
    log "GMS 组件已全部恢复"
    svc "am force-stop $GMS"
    echo "done"
    ;;
  status)
    OFF=0; ON=0
    for c in $COMPONENTS; do
        if pm list packages -d 2>/dev/null | grep -q "^package:${c%/*}$"; then
            OFF=$((OFF+1))
        else
            # 单组件 disable 用 pm list packages -d 查不到，改用 dumpsys
            st=$(dumpsys package "$c" 2>/dev/null | grep -m1 "enabled=" | grep -oE "enabled=[0-9]" | cut -d= -f2)
            [ "$st" = "2" ] || [ "$st" = "3" ] || [ "$st" = "4" ] && OFF=$((OFF+1)) || ON=$((ON+1))
        fi
    done
    echo "disabled=$OFF enabled=$ON"
    ;;
  *)
    echo "用法: gms-slim.sh apply|revert|status"
    ;;
esac
