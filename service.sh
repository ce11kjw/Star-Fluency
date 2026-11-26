#!/system/bin/sh
# Star-Fluency 开机服务

MODDIR=${0%/*}
SF_DIR=/data/adb/star-fluency
LOG=$SF_DIR/fluency.log
mkdir -p "$SF_DIR/motion" 2>/dev/null
chmod 700 "$SF_DIR" 2>/dev/null

log() { echo "$(date '+%m-%d %H:%M:%S') [svc] $*" >> "$LOG" 2>/dev/null; }

log "service.sh 启动"

# 等系统起完
i=0
while [ "$(getprop sys.boot_completed)" != "1" ] && [ $i -lt 180 ]; do sleep 1; i=$((i+1)); done
log "boot_completed=1 (${i}s)"

# 等 mmd_setup 把 zram 建好（本机约开机后 55-60 秒）
i=0
while [ $i -lt 60 ]; do
    [ -s /proc/swaps ] && grep -q zram0 /proc/swaps && break
    sleep 2; i=$((i+1))
done
log "zram swap 就绪 (${i}×2s)"

# 应用调优（含 zram 算法切换）
sh "$MODDIR/scripts/apply.sh" 2>>"$LOG"
log "调优应用完成"

# 网络优化
NETON=$(grep -E '^NET_OPT=' "$SF_DIR/config.conf" 2>/dev/null | cut -d= -f2)
[ -z "$NETON" ] && NETON=1
grep -q '^NET_OPT=' "$SF_DIR/config.conf" 2>/dev/null || echo 'NET_OPT=1' >> "$SF_DIR/config.conf"
if [ "$NETON" = "1" ]; then
    sleep 5
    PROF=$(grep -E '^PROFILE=' "$SF_DIR/config.conf" 2>/dev/null | cut -d= -f2)
    [ -z "$PROF" ] && PROF=balance
    sh "$MODDIR/scripts/net.sh" apply "$PROF" >>"$LOG" 2>&1
    log "网络优化已应用"
fi

# 启动 HTTP 服务（给浏览器看 WebUI）
if ! netstat -tln 2>/dev/null | grep -q 18123; then
    setsid nohup sh "$MODDIR/scripts/http.sh" >/dev/null 2>&1 &
    log "HTTP 服务已启动 :18123"
fi

# 动图自动监视
if [ -f "$SF_DIR/motion/auto.on" ]; then
    log "启动动图自动监视"
    (
        while [ -f "$SF_DIR/motion/auto.on" ]; do
            sleep 180
            sh "$MODDIR/scripts/motion.sh" run >/dev/null 2>&1
        done
    ) &
fi

# 相机闲置清理
CAMIDLE=$(grep -E '^CAM_IDLE_KILL=' "$SF_DIR/config.conf" 2>/dev/null | cut -d= -f2)
if [ "$CAMIDLE" = "1" ]; then
    log "启动相机闲置清理"
    (
        while true; do
            sleep 60
            sh "$MODDIR/scripts/cam-idle.sh" >/dev/null 2>&1
        done
    ) &
fi

# Play 商店后台压制（每 5 分钟）
PLAYON=$(grep -E '^TRIM_PLAY=' "$SF_DIR/config.conf" 2>/dev/null | cut -d= -f2)
if [ "$PLAYON" = "1" ]; then
    log "启动 Play 商店压制守护"
    (
        while true; do
            sleep 300
            sh "$MODDIR/scripts/play-guard.sh" >/dev/null 2>&1
        done
    ) &
fi

# 微信小程序容器闲置清理（每 3 分钟）
ABON=$(grep -E '^APPBRAND_IDLE=' "$SF_DIR/config.conf" 2>/dev/null | cut -d= -f2)
if [ "$ABON" = "1" ]; then
    log "启动小程序容器闲置清理"
    (
        while true; do
            sleep 180
            sh "$MODDIR/scripts/appbrand-idle.sh" >/dev/null 2>&1
        done
    ) &
fi

# 场景自动切换 + 温度降级（每 60s）
AUTON=$(grep -E '^AUTO_SCENE=|^AUTO_TEMP=' "$SF_DIR/config.conf" 2>/dev/null | grep '=1' | head -1)
if [ -n "$AUTON" ]; then
    log "启动场景自动切换守护"
    (
        while true; do
            sleep 60
            sh "$MODDIR/scripts/auto-profile.sh" >/dev/null 2>&1
        done
    ) &
fi

# 自研调度守护（场景识别 + Scene 外部源）
SCHED_ON=$(grep -E '^SCHED_ENABLED=' "$SF_DIR/config.conf" 2>/dev/null | cut -d= -f2)
if [ "$SCHED_ON" != "0" ]; then
    PIDF="$SF_DIR/sched/sched.pid"
    if [ ! -f "$PIDF" ] || ! kill -0 "$(cat "$PIDF" 2>/dev/null)" 2>/dev/null; then
        log "启动调度守护"
        setsid sh "$MODDIR/scripts/sched-daemon.sh" >/dev/null 2>&1 &
    fi
fi

# 电池采样守护（60s，估算容量/内阻）
BATD_ON=$(grep -E '^BATTD_ON=' "$SF_DIR/config.conf" 2>/dev/null | cut -d= -f2)
[ -z "$BATD_ON" ] && BATD_ON=1
if [ "$BATD_ON" != "0" ]; then
    BPIDF="$SF_DIR/battery/battd.pid"
    if [ ! -f "$BPIDF" ] || ! kill -0 "$(cat "$BPIDF" 2>/dev/null)" 2>/dev/null; then
        mkdir -p "$SF_DIR/battery" 2>/dev/null
        setsid sh "$MODDIR/scripts/battd.sh" >/dev/null 2>&1 &
    fi
fi

# 外放调参（开机重新挂载，开关记录在 audio/enabled）
if [ "$(cat "$SF_DIR/audio/enabled" 2>/dev/null)" = "on" ]; then
    sh "$MODDIR/scripts/audio.sh" on >/dev/null 2>&1 && log "外放调参已挂载"
fi

sh "$MODDIR/scripts/charge-night.sh" tick >/dev/null 2>&1
log "充电策略已应用（含全速开关状态）"
rm -f /data/adb/star-fluency/NEED_REBOOT
sh "$MODDIR/scripts/nullguard.sh"
setsid sh -c "while true; do sleep 3600; sh $MODDIR/scripts/nullguard.sh; done" >/dev/null 2>&1 &
LBOOST=$(grep -E '^PERF_LBOOST=' "$SF_DIR/config.conf" 2>/dev/null | cut -d= -f2)
if [ "$LBOOST" != "0" ]; then
    setsid sh "$MODDIR/scripts/perf.sh" watch >/dev/null 2>&1 &
fi
log "service.sh 完成"
