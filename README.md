# Star-Fluency

小米 11 Ultra（star / SM8350 / 澎湃 OS4.0）系统流畅度调优 + 动图修复，一个 KSU / APatch / Magisk 模块。

## 功能

| 页面 | 内容 |
|---|---|
| 调优 | 平衡 / 流畅两档，参数逐项显示「当前 / 原厂」，一键恢复原厂；场景自动切换（充电 / 夜间）；温度感知降级 |
| 网络 | TCP Fast Open、拥塞窗口、MTU 探测、连接回收、初始窗口、按接口分缓冲；可单独恢复原厂值 |
| 动图 | 相机拍完的微视频自动合成进 JPG（原 MotionFix 功能全保留） |
| 精简 | 负一屏、GMS 后台、Play 商店、小米商店、内容中心、缓存进程上限、GMS 组件精简、后台白名单、开机自启管理、动画缩放、相机闲置清理 |
| 状态 | 可用内存、Swap、Zram 压缩率、负载、各核频率、运行日志 |
| 诊断 | 一键回答「为什么卡」：负载 / 内存 / Swap / Zram / PSI / 温度 / ANR / OOM / Top CPU / Top 内存 / 结论 |

## 设计原则

- **纯 runtime 调参**，不覆盖任何系统文件（`/` 与 `/vendor` 是 erofs 只读）
- **全部可逆**：所有改动都在首次运行时备份原厂值，`uninstall.sh` 与「恢复原厂」按钮都会还原
- **不动**：thermal 配置、perf HAL、LMK、微信、输入法、隐藏相关模块
- **热更新**：脚本改动立即生效，不需要重启手机

## WebUI 兼容

KernelSU / KernelSU Next / SukiSU Ultra / APatch / FinaSU / KsuWebUIStandalone（`ksuwebui`）/ MMRL（含 `config.json` 声明）/ AxManager（`Axeron`）/ 原生 Magisk（无桥时自动降级到本地 HTTP 服务）

## 安装

管理器里刷入 Release 里的 `Star-Fluency.zip`，或者用 `updateJson` 自动更新。

## 已知限制

- 本机内核只带 `cubic` / `reno`，没有 BBR，所以网络优化只调参数不换算法
- zram 换算法需要 `mkswap` 后才能 `swapon`（这个自定义内核的行为），已在脚本内处理
- 切换 zram 会清空 swap 内容，因此只在开机时切一次

## 许可

个人自用，未做兼容性承诺。参考过 TCP_Optimiser_Module 的接口区分思路。
