# 更新日志

## v1.1.0（2026-11-24）

### 新增
- **网络参数优化**：TCP Fast Open 3、空闲后不重置拥塞窗口、MTU 自动探测、连接回收 30 秒、新连接初始窗口 20 段；缓冲按 Wi-Fi / 蜂窝区分；兼容 tun0 代理接口与 Android 多路由表
- **一键诊断**：负载、内存、Swap、Zram 压缩率、PSI、温度、缓存进程数、ANR/OOM、Top CPU / Top 内存、结论
- **后台白名单**：把应用加入白名单后不受任何后台限制影响
- **开机自启管理**：按包名禁用 BOOT_COMPLETED 接收器，可一键恢复（实测 5 个组件禁用/恢复往返一致）
- **场景自动切换**：充电自动切流畅档，夜间 23:00-07:00 回平衡档
- **温度感知降级**：电池 ≥42°C 自动降为平衡档，≤38°C 自动解除

### 修复
- 网络「恢复原厂值」失效（模式名 revert 与 stock 不匹配，实测原厂值还原不一致）
- 精简页移除「小米 NER 语义服务」限制项，并把已生效的 appop 还原为 allow

### 界面
- 6 个标签页：调优 / 网络 / 动图 / 精简 / 状态 / 诊断
- 全管理器 WebUI 桥适配：KernelSU / KernelSU Next / SukiSU / APatch / FinaSU / KsuWebUIStandalone / MMRL / AxManager / 原生 Magisk（HTTP 降级）

## v1.0.0（2026-11-24）

- 首次发布：两档调优（平衡 / 流畅 / 恢复原厂）、zram lz4→zstd 与 16GB 扩容、swappiness、vfs_cache_pressure、dirty_ratio、IO 调度、read_ahead、min_free_kbytes、CPU 频率下限
- 后台限制：负一屏、GMS 后台、Play 商店（关自动更新 + 压制）、小米应用商店、内容中心、缓存进程上限、GMS 组件精简
- 闲置清理：微信小程序容器、相机
- 动画缩放 0.5
- 动图（MotionFix）修复功能完整并入
