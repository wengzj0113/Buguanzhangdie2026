# 资金不足全量清仓重启 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 修复MT4/MT5在资金不足错误后停留在无单状态的问题，使EA清理本EA全部订单并从下一次Tick按首单规则重新开始。

**Architecture:** 在现有订单状态机上增加“清仓中”状态。资金不足只触发当前品种和Magic Number范围内的全量删除/平仓；清仓完成的当前Tick直接结束，下一Tick才进入固定距离或K线突破首单分支。动态模式只在新的首单组建立时重新计算K线距离，旧订单组的循环、网格和距离逻辑不改。

**Tech Stack:** MQL5/CTrade、MQL4、Python 3、pytest、MetaEditor命令行编译。

---

## 文件职责和变更范围

- Modify: `NoMatterRiseFall_MT5.mq5` — MT5清仓状态、全量订单扫描、资金不足触发和首单流程门控。
- Modify: `NoMatterRiseFall_MT4.mq4` — MT4对应的错误码判断、挂单删除、全量持仓关闭和状态门控。
- Modify: `tests/strategy_logic.py` — 为策略模型增加市价单资金不足注入和清仓重启状态。
- Modify: `tests/test_strategy_logic.py` — 添加资金不足后的行为回归测试。
- Modify: `README.md` — 记录资金不足后的清仓和下一Tick规则。
- Verify: `mt5_cycle_test.ini` — 保持现有默认策略参数不变。
- Create: `docs/superpowers/plans/2026-08-30-insufficient-funds-reset-implementation.md` — 本实施计划。

## Task 1: 建立资金不足清仓的失败测试

**Files:**

- Modify: `tests/strategy_logic.py:65-340`
- Modify: `tests/test_strategy_logic.py:1-340`

- [x] **Step 1: 扩展测试模型以注入市价单资金不足**

在`StrategyModel.__init__`增加`market_order_failures=0`，保存为`self.market_order_failures`；新增：

```python
def _try_open(self, direction, entry, lots, distance_points):
    if self.market_order_failures > 0:
        self.market_order_failures -= 1
        return False
    self._open(direction, entry, lots, distance_points)
    return True
```

让首单分支和止损切换分支都先调用`_try_open`，失败时返回`{"kind": "no_money"}`并进入清仓状态；测试模型的清仓状态必须在下一次`on_tick`前完成，并且清仓完成的Tick只返回清理动作。

- [x] **Step 2: 写入资金不足后的清仓重启测试**

在`tests/test_strategy_logic.py`加入至少以下测试：

```python
def test_no_money_closes_group_resets_state_and_restarts_on_next_tick():
    model = StrategyModel(
        Direction.BUY, CycleMode.MODE_1, 0.01, 2.0, 500, 0.0001,
        market_order_failures=1,
    )

    first = model.on_tick(bid=1.1000, ask=1.1002)
    assert first[0]["kind"] == "no_money"
    assert model.position is None
    assert model.pending is None
    assert model.cumulative_loss_lots == pytest.approx(0.0)
    assert model.current_index == 0

    model.market_order_failures = 0
    second = model.on_tick(bid=1.1000, ask=1.1002)
    assert second[0] == {
        "kind": "market", "direction": Direction.BUY, "lots": pytest.approx(0.01),
    }


def test_no_money_after_stop_starts_a_fresh_base_lot_group():
    model = StrategyModel(
        Direction.BUY, CycleMode.MODE_1, 0.01, 2.0, 500, 0.0001,
        initial_lot_multiplier=2.0, market_order_failures=1,
    )
    model.market_order_failures = 0
    model.on_tick(bid=1.1000, ask=1.1002)
    model.market_order_failures = 1
    stop_price = model.position.stop_loss
    failed = model.on_tick(bid=stop_price, ask=stop_price + 0.0002)

    assert failed[0]["kind"] == "no_money"
    assert model.position is None
    assert model.pending is None
    assert model.cumulative_loss_lots == pytest.approx(0.0)

    model.market_order_failures = 0
    restarted = model.on_tick(bid=1.1000, ask=1.1002)
    assert restarted[0]["lots"] == pytest.approx(0.01)


def test_no_money_dynamic_mode_rechecks_current_breakout_after_reset():
    model = StrategyModel(
        Direction.SELL, CycleMode.MODE_2, 0.01, 2.0, 500, 0.0001,
        distance_mode=DistanceMode.CANDLE_RANGE,
        min_range_points=500, max_range_points=1000,
        order_type=OrderType.FORWARD,
        market_order_failures=1,
    )
    waiting = model.on_tick(
        bid=1.0700, ask=1.0702, candle_range_points=600,
        previous_high=1.1000, previous_low=1.0400,
    )
    assert waiting == []

    failed = model.on_tick(
        bid=1.1010, ask=1.1012, candle_range_points=600,
        previous_high=1.1000, previous_low=1.0400,
    )
    assert failed[0]["kind"] == "no_money"

    no_breakout = model.on_tick(
        bid=1.0700, ask=1.0702, candle_range_points=700,
        previous_high=1.1000, previous_low=1.0400,
    )
    assert no_breakout == []

    restarted = model.on_tick(
        bid=1.1010, ask=1.1012, candle_range_points=700,
        previous_high=1.1000, previous_low=1.0400,
    )
    assert restarted[0]["kind"] == "market"
    assert model.group_stop_points == pytest.approx(700)


def test_no_money_reset_does_not_open_again_on_the_same_tick():
    model = StrategyModel(
        Direction.BUY, CycleMode.MODE_1, 0.01, 2.0, 500, 0.0001,
        market_order_failures=1,
    )
    actions = model.on_tick(bid=1.1000, ask=1.1002)
    assert [action["kind"] for action in actions] == ["no_money"]
```

- [x] **Step 3: 运行新增测试，确认它们先失败**

Run:

```text
python -m pytest -q tests/test_strategy_logic.py -k "no_money"
```

Expected: FAIL，因为当前模型没有资金不足注入、清仓状态和重新首单行为。

## Task 2: 在MT5增加全量清仓状态和订单扫描

**Files:**

- Modify: `NoMatterRiseFall_MT5.mq5:89-222, 400-456, 514-530`

- [x] **Step 1: 增加清仓状态字段和持久化键**

增加：

```cpp
bool g_reset_pending = false;
```

在`SaveState()`写入`StatePrefix() + ".reset"`；在`LoadState()`读取它；在`ClearState()`删除该键并将运行时字段恢复为false。旧版本不存在该全局变量时按false处理。

- [x] **Step 2: 增加全量持仓和挂单检查函数**

新增两个职责单一的函数：

```cpp
bool HasOurPosition()
  {
   for(int index = 0; index < PositionsTotal(); index++)
      if(IsOurPosition(PositionGetTicket(index)))
         return true;
   return false;
  }

bool HasOurPending()
  {
   ulong ticket = 0;
   long type = 0;
   double volume = 0.0;
   double price = 0.0;
   if(FindPending(ticket, type, volume, price))
      return true;
   if(FindGridPending(ticket, type, volume, price))
      return true;
   return false;
  }
```

新增不区分多空的`CloseAllOurPositions()`，遍历当前品种和Magic Number匹配的所有持仓并关闭；返回值必须同时确认关闭调用成功且`HasOurPosition()`为false。

- [x] **Step 3: 增加统一清仓处理函数**

新增：

```cpp
void BeginResetAfterNoMoney()
  {
   g_reset_pending = true;
   g_had_position = false;
   g_last_take_profit = 0.0;
   g_cycle_index = 0;
   g_pending_index = -1;
   g_group_stop_points = 0;
   g_group_take_profit_points = 0;
   g_cumulative_loss_lots = 0.0;
   g_previous_grid_lots = 0.0;
   g_grid_lots = 0.0;
   g_group_total_lots = 0.0;
   g_group_anchor_price = 0.0;
   g_group_last_entry = 0.0;
   g_group_linear_extreme = 0.0;
   g_grid_filled_levels = 0;
   g_grid_pending_level = 0;
   g_grid_pending_price = 0.0;
   SaveState();
   DeleteAllPending();
   CloseAllOurPositions();
  }

bool ProcessReset()
  {
   DeleteAllPending();
   CloseAllOurPositions();
   if(HasOurPosition() || HasOurPending())
      return false;
   ClearState();
   g_reset_pending = false;
   return true;
  }
```

`ProcessReset()`完成清仓时只返回状态，不在本次调用中进入首单分支；由`Manage()`立即返回，保证下一次Tick才重新开首单。

## Task 3: 将MT5资金不足接入订单状态机

**Files:**

- Modify: `NoMatterRiseFall_MT5.mq5:648-667, 888-1118`

- [x] **Step 1: 增加MT5资金不足错误码判断**

在`OpenMarket()`保存`g_trade.ResultRetcode()`到局部变量；失败时如果等于`TRADE_RETCODE_NO_MONEY`，调用`BeginResetAfterNoMoney()`，然后返回false。日志同时保留retcode和文字描述。

- [x] **Step 2: 在`Manage()`最前面优先处理清仓状态**

在任何`FindPosition()`、`PastLastTakeProfit()`、时间判断和K线突破判断之前加入：

```cpp
if(g_reset_pending)
  {
   ProcessReset();
   return;
  }
```

这样清仓未完成时不会触发新首单；清仓完成的Tick也直接结束。

- [x] **Step 3: 保持Transition的原订单组清理流程并让资金不足触发全量重置**

`Transition()`仍先使用当前订单组已经确定的距离计算下一组，并在切换前删除挂单、关闭当前持仓。下一组市价单失败时由`OpenMarket()`统一触发全量重置；不得再调用新的K线突破分支或保留累计手数。

- [x] **Step 4: 确认新首单分支使用基础手数**

重置后`g_cumulative_loss_lots`为0，因此现有表达式：

```cpp
const double initial_lots = g_cumulative_loss_lots > 0.0
                            ? VolumeNormalize(g_cumulative_loss_lots)
                            : VolumeNormalize(InpInitialLots);
```

必须走`InpInitialLots`分支。不得在重置路径中复用旧循环索引、旧网格手数或旧订单组距离。

- [x] **Step 5: 运行MT5相关Python测试，确认绿色**

Run:

```text
python -m pytest -q tests/test_strategy_logic.py -k "no_money"
```

Expected: 新增资金不足测试全部通过。

## Task 4: 在MT4实现同等清仓规则

**Files:**

- Modify: `NoMatterRiseFall_MT4.mq4:80-215, 385-499, 614-630, 822-1072`

- [x] **Step 1: 增加MT4清仓字段、持久化和全量扫描**

与MT5保持相同的`g_reset_pending`语义；使用MT4订单轮询实现`HasOurPosition()`、`HasOurPending()`和不区分多空的`CloseAllOurPositions()`，只处理`OrderSymbol()==Symbol()`且`OrderMagicNumber()==InpMagicNumber`的订单。

- [x] **Step 2: 记录OrderSend错误码并识别资金不足**

`OpenMarket()`在`OrderSend()`返回负数时先保存`const int error = GetLastError();`，再打印错误。错误等于`ERR_NOT_ENOUGH_MONEY`（134）时调用MT4版`BeginResetAfterNoMoney()`。

- [x] **Step 3: 在MT4的`Manage()`入口处理清仓状态**

与MT5一致，清仓状态优先级高于持仓管理、止盈判断、时间判断和K线突破判断；清仓完成当前Tick返回，下一Tick才进入首单流程。

- [x] **Step 4: 运行Python模型测试，确保MT4/MT5共享行为契约**

Run:

```text
python -m pytest -q
```

Expected: 全部原有测试和新增测试通过。

## Task 5: 文档、回测配置和代码质量检查

**Files:**

- Modify: `README.md`
- Modify: `tests/strategy_logic.py`
- Modify: `tests/test_strategy_logic.py`

- [x] **Step 1: 更新中文参数和策略说明**

在README中明确：资金不足不会等待资金恢复；本EA订单会被全部清理；清仓完成当前Tick不新开单；下一Tick按照固定距离或K线模式重新执行首单；新周期使用基础首单手数。

- [x] **Step 2: 补充边界测试**

覆盖以下边界：

- 资金不足时同时存在多空持仓，必须全部关闭；
- 同时存在反向预挂单和网格挂单，必须全部删除；
- 清仓函数失败时保持清仓状态，不能新开单；
- 固定模式在时间窗口外等待到窗口内才开基础首单；
- K线模式没有突破时继续等待，突破后使用当时有效K线高度；
- 清仓后的首单不继承旧循环索引和累计亏损手数。

- [x] **Step 3: 检查变更范围**

Run:

```text
git diff --check
git diff --stat
```

Expected: 无空白错误；变更仅涉及资金不足清仓功能、测试和说明文档，不覆盖工作区中此前已有的其他策略改动。

## Task 6: 编译和回测验证

**Files:**

- Verify: `NoMatterRiseFall_MT5.mq5`
- Verify: `NoMatterRiseFall_MT4.mq4`
- Verify: `NoMatterRiseFall_MT5.ex5`
- Verify: `NoMatterRiseFall_MT4.ex4`

- [x] **Step 1: 运行完整Python验证**

Run:

```text
python -m pytest -q
python -m py_compile tests/strategy_logic.py tests/test_strategy_logic.py
```

Expected: pytest无失败，py_compile退出码为0。

- [x] **Step 2: 使用MetaEditor分别编译MT5和MT4**

Run:

```powershell
& 'C:\Program Files\MetaTrader 5\MetaEditor64.exe' /compile:'D:\00_EA\codx-ea\Experts\不管涨跌复刻\NoMatterRiseFall_MT5.mq5' /log
& 'C:\Program Files (x86)\MetaTrader 4 IC Markets Global\metaeditor.exe' /compile:'D:\00_EA\codx-ea\Experts\不管涨跌复刻\NoMatterRiseFall_MT4.mq4' /log
```

Expected:

```text
0 errors
0 warnings
```

- [ ] **Step 3: 执行低资金回测场景**

使用低于下一订单组保证金需求的账户资金，确认日志顺序为：资金不足→删除本EA挂单→关闭本EA持仓→清空状态→当前Tick不再开单→下一Tick重新执行首单判断。

- [ ] **Step 4: 执行动态模式回测场景**

确认清仓后的动态模式使用当时上一根K线的高度和突破方向，未突破时不下单，突破后首单手数回到基础“首单手数”。

- [ ] **Step 5: 审核最终需求覆盖**

逐项确认：MT4/MT5、资金不足错误码、全部挂单、全部持仓、Magic Number隔离、清仓状态、下一Tick时序、固定模式时间、K线模式突破、基础首单手数、旧状态清空和编译测试结果均有直接证据。
