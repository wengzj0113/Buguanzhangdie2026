# 均值两倍 K 线 Implementation Plan

**Goal:** 新增第九个独立 MT4/MT5 EA，以已确认的均值两倍条件入场，以信号 K 线百分比锁定初始距离。

**Architecture:** 两个薄入口共享现有平台核心。仅新 profile 编译专有输入和 MT5 配置字段，不改变其他 profile 的配置指纹。首单进入现有信号锁、单/双篮子和保护管理路径。

**Tech Stack:** MQL4/MQL5、pytest、PowerShell、MetaEditor、MT5 隔离策略测试器。

- [x] 新建 tests/test_average_double_candle.py，覆盖均值排除信号线、>= 边界、方向、百分比、无效数据；扩充 profile/build/package 测试矩阵到 9 模式/18 入口。运行失败测试。
- [x] 创建 NoMatterRiseFall_AverageDoubleCandle_MT4.mq4/.mq5；在两平台 Core.mqh 新增固定模式 8、N/百分比输入、信号计算及单/双篮子入口；MT5 加入条件编译配置/指纹/面板编辑校验。
- [x] 运行定向回归并修正，再运行全套 pytest。检查原八模式暴露参数与状态隔离契约。
- [x] 使用 scripts/compile-mql.ps1 -Target Both -Profile All 编译 18 个入口；以默认 Legacy 编译两个兼容入口。每项须 0 errors 且输出刷新，记录 warnings。
- [x] 将新编译 MT5 二进制复制至隔离终端，核对 SHA256；按 XAUUSD M5 生成 tick 回放单/双篮子，保存报告、日志及输入参数。复核信号均值/距离、同根次数、最大反手重置和运行错误。
- [x] 更新 scripts/package-distance-mode-eas.ps1，生成九模式完整包及新模式独立包，校验源文件/核心/二进制和 ZIP 内容，更新说明并交付。
