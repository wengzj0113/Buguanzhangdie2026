# Bollinger Expansion Implementation Plan

**Goal:** 新增第十种独立 EA，仅改变开单信号与初始距离来源。

**Architecture:** 新建 BollingerExpansion MT4/MT5 薄入口，扩展现有两平台核心的条件编译信号与 MT5 配置面板；公共交易流程复用。专有枚举距离模式只在新profile生效，原九种指纹不改变。

**Tech Stack:** MQL4/MQL5、pytest、PowerShell、MetaEditor、隔离 MT5 策略测试器。

- [x] 在 tests/test_bollinger_expansion.py 添加红灯测试：`bollinger_expansion_signal(200,[80,120],2,25)==(50,50)`，199不触发；固定模式仍检查阈值，独立固定SL/TP；无效历史、N、百分比、点数不下单。
- [x] 扩展 tests/test_ea_profile_contract.py 与 tests/test_distance_mode_build.py 到10模式、20入口；暴露首单方向/中轨方向、布林周期/标准差、比较N、距离模式、百分比、固定SL/TP；新Magic唯一。
- [x] 新建 NoMatterRiseFall_BollingerExpansion_MT4.mq4/.mq5；两Core实现 GetBollingerExpansionSignal，闭合shift1对shift2..N+1、>=2、有限正数验证、百分比/固定距离及信号日志。接入原 PrepareInitialSignal 和锁定距离。
- [x] MT5专有GuiConfig字段（比较N、距离子模式、百分比）、加载、验证、指纹、面板编辑/枚举/坐标/同步；新专有指纹拒绝旧配置迁移。修改编译打包矩阵。
- [x] 运行 `uv run --with pytest -- python -m pytest -q`，修复必要问题后全套通过；运行 `powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\compile-mql.ps1 -Target Both -Profile All` 与默认 Both，检查22个刷新输出和零错误、记录警告。
- [x] 新建 scripts/test-bollinger-expansion-mt5.ps1，隔离终端测试百分比单组和固定双组，保存set/ini/log/报告；逐条验证阈值、距离、初始组唯一性和首次实际SL/TP。
- [x] 更新使用说明与验证记录，生成 BollingerExpansion_2026-10-18.zip 和 TenDistanceModeEAs_2026-10-18.zip；核对60份源码/核心/字节码SHA256及ZIP可读性，记录结果。

按当前已授权工作区连续实施，不提交混有用户现有修改的提交；不切换或清理已有工作目录。
