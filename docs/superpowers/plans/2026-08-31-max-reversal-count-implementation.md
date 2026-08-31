# 最大反手次数 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在MT4和MT5中限制订单组止损切换次数，达到默认5次后全量清仓并从下一次Tick重新开始首单周期。

**Architecture:** 在现有六单循环索引之外增加独立的反手计数，避免把循环位置误当作风险次数。所有止损切换路径（预挂单成交和市价切换）都先检查上限；达到上限后复用全量清仓状态机，清仓完成的Tick只结束流程，下一Tick进入固定或动态首单逻辑。

**Tech Stack:** MQL5/CTrade、MQL4、Python 3、pytest、MetaEditor。

---

## 文件职责和变更范围

- Modify: `NoMatterRiseFall_MT5.mq5` — 参数、计数状态、持久化、预挂单门控和达到上限后的清仓。
- Modify: `NoMatterRiseFall_MT4.mq4` — MT4对应实现。
- Modify: `tests/strategy_logic.py` — 增加最大反手次数模型状态和止损切换门控。
- Modify: `tests/test_strategy_logic.py` — 增加上限、零值、重启首单和清仓时序测试。
- Modify: `README.md` — 增加中文参数和策略规则说明。
- Modify: `mt5_cycle_test.ini` — 增加默认参数项`最大反手次数=5`。
- Create: `docs/superpowers/specs/2026-08-31-max-reversal-count-design.md` — 已确认的设计规格。
- Create: `docs/superpowers/plans/2026-08-31-max-reversal-count-implementation.md` — 本实施计划。

## Task 1: 用测试锁定计数语义

**Files:**

- Modify: `tests/strategy_logic.py:65-360`
- Modify: `tests/test_strategy_logic.py:1-700`

- [ ] **Step 1: 为模型增加最大次数参数和计数状态**

在`StrategyModel`增加`max_reversals=5`参数、`self.max_reversals`和`self.reversal_count`，并为`_reset_after_no_money()`清零反手次数。新增辅助方法：

```python
def _reset_after_max_reversals(self):
    self.position = None
    self.pending = None
    self.grid_pending = None
    self.current_index = 0
    self.reversal_count = 0
    self.cumulative_loss_lots = 0.0
    self.previous_grid_lots = None
    self.grid_lots = 0.0
    self.group_total_lots = 0.0
    self.grid_filled_levels = 0
    self.group_anchor_entry = None
    self.group_stop_points = None
    self.group_take_profit_points = None
    self.linear_extreme = None
```

- [ ] **Step 2: 写入失败测试**

加入以下测试：

```python
def test_max_reversals_five_allows_five_switches_then_resets():
    model = StrategyModel(
        Direction.BUY, CycleMode.MODE_1, 0.01, 2.0, 500, 0.0001,
        max_reversals=5,
    )
    model.on_tick(bid=1.1000, ask=1.1002)

    for expected_count in range(1, 6):
        stop_price = model.position.stop_loss
        actions = model.on_tick(bid=stop_price, ask=stop_price + 0.0002)
        assert actions[1]["kind"] == "market"
        assert model.reversal_count == expected_count

    stop_price = model.position.stop_loss
    actions = model.on_tick(bid=stop_price, ask=stop_price + 0.0002)
    assert actions == [{"kind": "reset_max_reversals"}]
    assert model.position is None
    assert model.pending is None
    assert model.reversal_count == 0
    assert model.cumulative_loss_lots == pytest.approx(0.0)


def test_zero_max_reversals_resets_after_the_first_group_stop():
    model = StrategyModel(
        Direction.BUY, CycleMode.MODE_1, 0.01, 2.0, 500, 0.0001,
        max_reversals=0,
    )
    model.on_tick(bid=1.1000, ask=1.1002)
    stop_price = model.position.stop_loss

    actions = model.on_tick(bid=stop_price, ask=stop_price + 0.0002)

    assert actions == [{"kind": "reset_max_reversals"}]
    assert model.position is None
    assert model.pending is None


def test_new_cycle_after_max_reversals_uses_base_lot_on_next_tick():
    model = StrategyModel(
        Direction.BUY, CycleMode.MODE_1, 0.01, 2.0, 500, 0.0001,
        max_reversals=0, initial_lot_multiplier=2.0,
    )
    model.on_tick(bid=1.1000, ask=1.1002)
    stop_price = model.position.stop_loss
    model.on_tick(bid=stop_price, ask=stop_price + 0.0002)

    actions = model.on_tick(bid=1.1000, ask=1.1002)

    assert actions[0]["kind"] == "market"
    assert actions[0]["lots"] == pytest.approx(0.01)
```

- [ ] **Step 3: 运行新增测试确认先失败**

Run:

```text
python -m pytest -q tests/test_strategy_logic.py -k "max_reversals"
```

Expected: FAIL，因为当前模型没有`max_reversals`参数和次数门控。

## Task 2: 实现Python模型并验证红绿循环

**Files:**

- Modify: `tests/strategy_logic.py:65-360`

- [ ] **Step 1: 在止损切换前检查上限**

在`on_tick()`的止损分支中，将上限判断放在累计亏损和开下一组之前：

```python
if self.reversal_count >= self.max_reversals:
    self._reset_after_max_reversals()
    return [{"kind": "reset_max_reversals"}]
self.reversal_count += 1
```

- [ ] **Step 2: 禁止达到上限后的反向预挂单**

在`_next_pending()`开头加入：

```python
if self.reversal_count >= self.max_reversals:
    self.pending = None
    return None
```

调用方只有在`pending`不为空时才生成预挂单动作。

- [ ] **Step 3: 调整受六单循环测试影响的用例**

需要继续验证完整六单循环的测试显式传入`max_reversals=6`，因为该测试还要检查第六组之后的循环回到第一组；新增限制测试使用默认5或显式0。

- [ ] **Step 4: 运行测试确认绿色**

Run:

```text
python -m pytest -q tests/test_strategy_logic.py -k "max_reversals or cycle or losing_group"
```

Expected: 新增和受影响的测试全部通过。

## Task 3: 接入MT5订单状态机

**Files:**

- Modify: `NoMatterRiseFall_MT5.mq5:38-71, 89-222, 570-630, 750-1030, 1200-1240`

- [ ] **Step 1: 增加中文参数和持久化计数**

增加：

```cpp
input int 最大反手次数 = 5;
int g_reversal_count = 0;
```

将计数写入`StatePrefix()+".reversals"`，从全局变量读取；`ClearState()`和所有新周期重置路径将计数置0；`OnInit()`拒绝负数。

- [ ] **Step 2: 抽取统一的最大次数清仓入口**

在现有`BeginResetAfterNoMoney()`旁增加最大次数入口，复用同一清仓动作但输出不同原因：

```cpp
void BeginResetAfterMaxReversals()
  {
   PrintFormat("Maximum reversal count reached (%d); clearing all EA positions and pending orders.",
               最大反手次数);
   BeginFullReset();
  }
```

实际实现可以将现有重置字段初始化和清仓动作抽到`BeginFullReset()`，保证资金不足和次数上限使用同一套清仓状态。

- [ ] **Step 3: 在预挂单成交路径限制次数**

在`Manage()`确认`pending_filled`后、累加亏损和更新循环索引前加入：

```cpp
if(g_reversal_count >= 最大反手次数)
  {
   BeginResetAfterMaxReversals();
   return;
  }
g_reversal_count++;
```

这样即使预挂单已经被平台成交，也不会让第`最大反手次数+1`组继续运行。

- [ ] **Step 4: 在市价切换路径限制次数**

在`Transition()`开始处检查：

```cpp
if(g_reversal_count >= 最大反手次数)
  {
   BeginResetAfterMaxReversals();
   return false;
  }
```

只有未达到上限时才累计亏损、推进循环索引、增加`g_reversal_count`并开下一组。

- [ ] **Step 5: 禁止达到上限后继续挂反向单**

在`PlaceNextPending()`和`EnsureNextPending()`增加上限保护；达到上限时不新增反向预挂单，但不影响当前订单组的网格加单和止盈止损管理。

- [ ] **Step 6: 编译MT5并运行Python回归测试**

Run:

```text
python -m pytest -q
python -m py_compile tests/strategy_logic.py tests/test_strategy_logic.py
& 'C:\\Program Files\\MetaTrader 5\\MetaEditor64.exe' /compile:'D:\\00_EA\\codx-ea\\Experts\\不管涨跌复刻\\NoMatterRiseFall_MT5.mq5' /log
```

Expected: pytest全部通过，Python语法检查通过，MT5为`0 errors, 0 warnings`。

## Task 4: 同步MT4实现

**Files:**

- Modify: `NoMatterRiseFall_MT4.mq4:36-69, 87-219, 540-590, 700-960, 1145-1165`

- [ ] **Step 1: 增加参数、计数持久化和清零**

使用与MT5相同的参数名、默认值和`.reversals`键。

- [ ] **Step 2: 在预挂单成交和市价切换路径增加上限检查**

使用与MT5相同的计数顺序：达到上限先全量清仓；未达到上限才增加计数并建立下一组。

- [ ] **Step 3: 编译MT4并运行完整测试**

Run:

```text
python -m pytest -q
& 'C:\\Program Files (x86)\\MetaTrader 4 IC Markets Global\\metaeditor.exe' /compile:'D:\\00_EA\\codx-ea\\Experts\\不管涨跌复刻\\NoMatterRiseFall_MT4.mq4' /log
```

Expected: pytest全部通过，MT4为`0 errors, 0 warnings`。

## Task 5: 更新配置、说明和验收

**Files:**

- Modify: `README.md`
- Modify: `mt5_cycle_test.ini`

- [ ] **Step 1: 增加中文参数说明**

说明默认5次、0次语义、计数包含同向衔接、达到上限后全量清仓、下一Tick重新首单，以及固定/动态模式的重新判断规则。

- [ ] **Step 2: 检查变更质量**

Run:

```text
git diff --check
git diff --stat
```

Expected: 无空白错误，变更范围仅包含最大反手次数、测试、配置和文档。

- [ ] **Step 3: 完成需求审计**

逐项确认默认值5、计数边界、预挂单成交路径、市价切换路径、网格不受影响、资金不足清仓不受影响、下一Tick时序、固定模式时间、动态模式突破、MT4/MT5编译和Python测试结果均有直接证据。
