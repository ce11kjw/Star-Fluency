# 更新日志

## v1.2.3（2026-11-25）

### 新增：与 Scene 共存（自动让位）
- 读 Scene 的 `scene_profile_source`（global.xml）判断它当前用什么源：
  - `SOURCE_SCENE_ONLINE/ACTIVE/CONSERVATIVE`（Scene HP/LP/在线）→ **自动让位**，只把 clamp_min 归 0，不写任何频率
  - `SOURCE_SCENE_CUSTOM`（自定义）→ **引擎继续接管**（Scene 只当界面/按应用绑定用）
  - `SOURCE_OUTSIDE`（外部来源）→ **引擎接管**，Scene 四档直接驱动本模块
- 调度页新增「调度引擎接管」总开关（`SCHED_ENABLED`），关掉后调度守护与「调优」页都不再碰 CPU
- 调度页显示 Scene 当前源；让位时档位显示「让位给 Scene」
- `SCHED_YIELD_SCENE`（默认 1）可关掉自动让位，强制引擎优先

## v1.2.2（2026-11-25）

- 调度页：新增「CPU 核心温度」（thermal_zone0）、「取当前前台应用」按钮（自动填包名）
- sched.sh：新增 `fg` 动作、status 增加 `soc_temp` 字段
- 状态缓存 TTL 20s → 60s（配合 10s 轮询，冷路径占比降到 1/6）

## v1.2.1（2026-11-25）

- 修复两套写频率的问题：「调优」页的 apply.sh 不再自己写 scaling_min_freq，改为委托调度引擎（balance→均衡、smooth→性能、stock→原厂），全局只有 sched.sh 一个写者

## v1.2.0（2026-11-25）

### 新增：自研场景调度引擎
- 四档调度：省电 / 均衡 / 性能 / 极速（按骁龙 888 三簇 1804 / 2419 / 2841 MHz 校准）
- 每档同时调 scaling_min_freq、schedutil hispeed_freq / hispeed_load、up/down_rate_limit_us、sched_util_clamp_min
- 场景识别守护（15s 一轮）：温度回退 > 按应用绑定 > 息屏省电 > 充电提档 > 手动档位
- 按应用绑定：指定包名在前台时自动切档
- **Scene 对接**：一键生成 `/data/powercfg.sh`，Scene 里把配置源切成「外部来源」后，Scene 的四档与按应用绑定直接驱动本模块（读取 Scene 传入的 `top_app`）
- 修正 `sched_util_clamp_min` 被拉到 1024（所有任务当满负载）导致 CPU 长期高频的问题

### 新增：调度页（WebUI 第 7 个标签）
- 当前档位 / 来源（手动·Scene）/ 原因 / 前台应用、clamp_min、三簇实时频率与下限
- 四档一键切换、Scene 外部源开关、息屏省电/充电提档开关、温度阈值点按切换 40/42/45/48
- 按应用绑定增删

### 性能：修 WebUI 卡顿
- 新增 `status-cache.sh`：状态结果缓存 20 秒，实测 2011ms → 81~94ms
- 轮询间隔 5s → 10s
- 旧的 auto-profile 场景切换关闭（由新调度守护接管，避免两套同时写频率）

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
