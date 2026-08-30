# 六单循环模式 EA 优化实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将当前固定“每次止损后反向开单”的MT5/MT4 EA升级为可选择六单循环模式的一致策略。

**Architecture:** 用一个六元素方向数组表示当前循环，首单方向决定数组内容，循环模式决定数组模板。状态机只跟踪当前订单在六单中的索引，下一单方向由 `(current_index + 1) % 6` 得出；下一单仍然挂在当前单止损价位，但根据目标方向与价格位置自动选择 Stop 或 Limit 类型。MT5使用交易事件加Tick校正，MT4使用订单轮询与历史订单校正，二者共享相同的序列和状态规则。

**Tech Stack:** MQL5/CTrade、MQL4交易API、Python/pytest、MetaEditor编译器。

---

## 1. 目标行为

### 模式模板

以首单方向为基准，运行时生成以下六元素序列：

| 循环模式 | 首单多 | 首单空 |
|---|---|---|
| 模式一 | BUY, SELL, SELL, BUY, SELL, SELL | SELL, BUY, BUY, SELL, BUY, BUY |
| 模式二 | BUY, SELL, BUY, SELL, BUY, BUY | SELL, BUY, SELL, BUY, SELL, SELL |
| 模式三 | BUY, SELL, BUY, BUY, SELL, BUY | SELL, BUY, SELL, SELL, BUY, SELL |

六单完成后索引回到0，继续循环。手数规则保持不变：首单使用 `InitialLots`，后续每单为上一单手数乘 `ReverseMultiplier`。

### 价格与挂单类型

下一单入场价固定取当前持仓止损价：

- 目标方向与当前方向相反时：使用相反方向的 Stop 单。
- 当前多单止损价低于现价，下一单仍为多单：使用 `Buy Limit`。
- 当前空单止损价高于现价，下一单仍为空单：使用 `Sell Limit`。
- 如价格跳空越过目标价，EA先清理旧挂单、关闭当前持仓，再以目标方向市价补单，并基于实际成交价重新计算止损、止盈和下一挂单。

### 周期结束

任意当前持仓达到止盈时，删除本EA剩余挂单并结束本轮；下一次完全空闲时，从用户设置的首单方向重新开始第0个序号。

## 2. 参数设计

新增：

- `InpCycleMode`：`CYCLE_MODE_1`、`CYCLE_MODE_2` 或 `CYCLE_MODE_3`，默认模式一。

保留：

- `InpFirstDirection`
- `InpInitialLots`
- `InpReverseMultiplier`
- `InpStopLossDistancePoints`
- `InpTakeProfitDistancePoints`
- `InpMagicNumber`
- `InpOrderComment`

建议增加但默认关闭的风险保护参数（需用户确认后启用）：

- `InpMaxCycleOrders = 0`：0表示不限制，否则达到上限后停止继续加单。
- `InpMaxLots = 0`：0表示不限制，否则超过上限时停止开新单。
- `InpMaxSpreadPoints = 0`：0表示不限制，否则开单前检查最大点差。

这些保护参数不改变默认循环逻辑，只用于避免连续止损时手数无限增长。

## 3. 实施步骤

### Task 1: 扩展纯逻辑模型和测试

**Files:**
- Modify: `tests/strategy_logic.py`
- Modify: `tests/test_strategy_logic.py`

- [x] 新增 `CycleMode` 和六组方向序列断言：模式一/二/三 × 首单多/空。
- [x] 测试索引从0到5，完成第6单后回到0。
- [x] 测试每一步手数按倍数递增，并验证自定义倍数。
- [x] 测试同向衔接的挂单类型：Buy Limit、Sell Limit；反向衔接使用Stop类型。
- [x] 测试止盈取消挂单，止损推进到下一个序号。
- [x] 先运行 `python -m pytest -q` 验证新增测试失败，再实现最小模型并验证全部通过。

### Task 2: 重构MT5序列状态机

**File:** `NoMatterRiseFall_MT5.mq5`

- [x] 新增 `CycleMode` 输入和序列计算，根据首单方向生成六元素序列。
- [x] 用 `g_cycle_index` 记录当前订单序号，并在新一单确认成交后递增；止盈后重置为0。
- [x] 将固定反向挂单逻辑改为 `PlaceNextPending()`，目标方向来自序列。
- [x] 根据目标方向和目标价格相对Bid/Ask的位置选择 `Buy Stop`、`Buy Limit`、`Sell Stop` 或 `Sell Limit`。
- [x] 在终端全局变量中保存循环模式、首单方向、当前序号和下一单序号，重启后恢复状态。
- [x] 通过Tick状态校正防止挂单成交后的重复开单，并校验已有挂单的方向、价格和手数。
- [x] 保留Magic Number和品种过滤，执行交易量和价格归一化。

### Task 3: 同步重构MT4

**File:** `NoMatterRiseFall_MT4.mq4`

- [x] 与MT5使用完全相同的四组六元素序列和索引推进规则。
- [x] 将挂单发送扩展为 `OP_BUYSTOP`、`OP_BUYLIMIT`、`OP_SELLSTOP`、`OP_SELLLIMIT`。
- [x] 用终端全局变量恢复循环序号，并通过当前订单状态识别已成交挂单。
- [x] 同步实现重复订单防护、跳空补市价单、止盈清理和交易量/价格归一化。

### Task 4: 回归测试和编译

- [x] 运行 `python -m pytest -q`，所有方向、模式、索引、手数和挂单类型模型测试通过。
- [x] 使用MetaEditor分别编译MT5和MT4，均为0错误、0警告。
- [x] 用Python确定性模型覆盖模式一/二/三及首单多/空六种组合，检查订单方向序列和手数序列；真实MT5策略测试器回放需用户终端提供历史数据后进行。
- [x] 通过模型与源码检查验证止盈清理、循环索引恢复和同向Limit挂单。
- [x] 更新README，说明模式选择、四组序列、挂单类型和递增手数风险。

## 4. 验收标准

- 模式一、模式二和模式三均可由输入项选择。
- 首单多/空六种组合都得到正确六单方向序列。
- 每次止损推进一个序号，而不是简单反向。
- 第六单后循环回到第一单。
- 同向连续单在止损价位使用正确的Limit挂单。
- 反向连续单使用正确的Stop挂单。
- 止盈会删除剩余挂单并重新开始下一轮。
- MT5与MT4源码分别编译通过，Python行为测试通过。
