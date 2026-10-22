# ZigZag 波段距离 Implementation Plan

> **For agentic workers:** Execute tasks in order. Use tests before production edits and verify each task.

**Goal:** 给 MT4/MT5 增加可配置、可恢复的 ZigZag 波段止损和止盈距离模式。

**Architecture:** 两平台从标准 ZigZag 的第 4、第 5 个极值读取已稳定的相邻高低点，再用同一公式换算点数。沿用现有市价首单和订单组距离持久化路径；MT5 面板配置进入现有草稿与应用流程。

**Tech Stack:** MQL4, MQL5, Python pytest, MetaEditor, MetaTrader tester.

---

### Task 1: 距离计算和参数校验

**Files:** `tests/strategy_logic.py`, `tests/test_strategy_logic.py`, `NoMatterRiseFall_MT4.mq4`, `NoMatterRiseFall_MT5.mq5`

- [x] 为拐点过滤、波段最小/最大值、百分比、止盈倍数及无效数值写失败测试并运行。
- [x] 新增枚举值 5、七个输入参数和计算函数；MT4 `iCustom` 读缓冲区 0，MT5 `iCustom` 句柄加 `CopyBuffer`；只选第 4、第 5 个有效极值。
- [x] 在两个 `GetDistancePoints` 增加 ZigZag 分支；校验配置和计算结果，运行聚焦测试。

### Task 2: MT5 界面和配置生命周期

**Files:** `NoMatterRiseFall_MT5.mq5`, `tests/test_strategy_logic.py`

- [x] 为面板参数接入、配置指纹、模式下拉和页面布局写失败测试并运行。
- [x] 把七个参数接入 `GuiConfig` 的加载、复制、编辑、校验、指纹和摘要；距离页按模式显示参数，所有显示的控件可点击编辑。
- [x] 运行聚焦测试，检查参数的草稿、应用与取消路径。

### Task 3: 状态恢复和风险保护

**Files:** `NoMatterRiseFall_MT4.mq4`, `NoMatterRiseFall_MT5.mq5`, `tests/test_strategy_logic.py`

- [x] 为活动组缺失锁定距离、指标缺失、点数溢出、交易商止损限制写失败测试。
- [x] ZigZag 活动组从持久状态恢复锁定距离；不能恢复则暂停新增订单，不用当前指标重算。新首单距离不符合交易商限制时跳过。
- [x] 运行聚焦测试。

### Task 4: 交付验证

**Files:** `README.md`, `EA软件使用手册.html`, ZigZag 指标文件, 两平台 EA 文件

- [x] 补充参数、公式、安装位置及重绘保护说明。
- [x] 运行完整 Python 测试；编译 MT4 和 MT5 指标与 EA，检查编译日志。
- [x] MT5 测试器验证有效波段与越界；自动化测试覆盖极值不足、活动组缺失锁定距离和旧距离模式；记录结果并复查差异。

## 验证记录（2026-09-26）

- Python：`300 passed`。
- MT4 EA、MT4 ZigZag、MT5 EA、MT5 ZigZag：各为 `0 errors, 0 warnings`。
- MT5 XAUUSD M5，2026-01-01 至 2026-01-07：距离模式 5，Depth/Deviation/Backstep 为 12/5/3，最小/最大为 1/100000 点，百分比 100%，止盈倍数 1.0；测试器通过，首单 4319.08，止损 4282.84，止盈 4355.32。
- MT5 XAUUSD M5，2026-01-01 至 2026-01-03：最小/最大均设为 100000 点；测试器通过，没有成交。
- MT4 的策略测试器和运行中重启恢复未做端到端验证；对应代码通过编译，关键保护路径由自动化测试覆盖。
