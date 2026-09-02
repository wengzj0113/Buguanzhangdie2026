# K线高度模式首单双向预埋 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 MT4/MT5 的 K 线高度且“每根一次”模式中同时预埋上一根 K 线最高/最低点的两张首单，并在一张成交后取消另一张；保持“每根多次”和固定距离模式原行为。

**Architecture:** 将首单双向预埋作为独立于现有反向挂单的 OCO 状态处理。单组和多组分别保存两张首单票据、价格和成交状态；首单成交后转入现有订单组生命周期，并清理另一张首单。Python 模型先表达行为，再用 MT4/MT5 源码契约测试约束双平台实现的一致结构。

**Tech Stack:** MQL5, MQL4, Python 3 `dataclasses`, pytest, Markdown。

---

### Task 1: 为首单双向预埋建立失败行为测试

**Files:**
- Modify: `tests/test_strategy_logic.py`（K线首单行为测试区域）
- Modify: `tests/strategy_logic.py`（仅在后续 Task 2 实现模型接口）

- [ ] **Step 1: 添加正向“每根一次”双向预埋测试**

在现有 K 线模式测试附近加入：

```python
def test_candle_once_places_buy_at_high_and_sell_at_low_without_market_entry():
    model = StrategyModel(
        Direction.BUY, CycleMode.MODE_1, 0.01, 2.0, 500, 0.0001,
        distance_mode=DistanceMode.CANDLE_RANGE,
        order_type=OrderType.FORWARD, korder_type=0,
    )

    actions = model.on_tick(
        bid=1.0500, ask=1.0502, candle_range_points=600,
        previous_high=1.1000, previous_low=1.0400, candle_id=10,
    )

    assert [action["kind"] for action in actions] == [
        "initial_pending", "initial_pending",
    ]
    assert {(action["direction"], action["price"]) for action in actions} == {
        (Direction.BUY, 1.1000), (Direction.SELL, 1.0400),
    }
    assert all(action["kind"] != "market" for action in actions)
```

- [ ] **Step 2: 添加逆向方向和重复 Tick 测试**

```python
def test_candle_once_reverse_places_sell_at_high_and_buy_at_low_once():
    model = StrategyModel(
        Direction.BUY, CycleMode.MODE_1, 0.01, 2.0, 500, 0.0001,
        distance_mode=DistanceMode.CANDLE_RANGE,
        order_type=OrderType.REVERSE, korder_type=0,
    )

    first = model.on_tick(
        bid=1.0500, ask=1.0502, candle_range_points=600,
        previous_high=1.1000, previous_low=1.0400, candle_id=10,
    )
    second = model.on_tick(
        bid=1.0500, ask=1.0502, candle_range_points=600,
        previous_high=1.1000, previous_low=1.0400, candle_id=10,
    )

    assert {(action["direction"], action["price"]) for action in first} == {
        (Direction.SELL, 1.1000), (Direction.BUY, 1.0400),
    }
    assert second == []
```

- [ ] **Step 3: 添加“每根多次”保持突破市价开单的测试**

```python
def test_candle_repeat_still_waits_for_breakout_and_opens_market_order():
    model = StrategyModel(
        Direction.BUY, CycleMode.MODE_1, 0.01, 2.0, 500, 0.0001,
        distance_mode=DistanceMode.CANDLE_RANGE,
        order_type=OrderType.FORWARD, korder_type=1,
    )

    actions = model.on_tick(
        bid=1.0500, ask=1.0502, candle_range_points=600,
        previous_high=1.1000, previous_low=1.0400, candle_id=10,
    )
    assert actions == []

    actions = model.on_tick(
        bid=1.1001, ask=1.1003, candle_range_points=600,
        previous_high=1.1000, previous_low=1.0400, candle_id=10,
    )
    assert actions[0]["kind"] == "market"
    assert all(action["kind"] != "initial_pending" for action in actions)
```

- [ ] **Step 4: 添加首单成交后的 OCO 测试**

```python
def test_initial_pending_fill_cancels_the_other_side_and_starts_group():
    model = StrategyModel(
        Direction.BUY, CycleMode.MODE_1, 0.01, 2.0, 500, 0.0001,
        distance_mode=DistanceMode.CANDLE_RANGE,
        order_type=OrderType.FORWARD, korder_type=0,
    )
    model.on_tick(
        bid=1.0500, ask=1.0502, candle_range_points=600,
        previous_high=1.1000, previous_low=1.0400, candle_id=10,
    )

    actions = model.fill_initial_pending(Direction.BUY, 1.1000)

    assert actions[0] == {"kind": "cancel_initial_pending", "direction": Direction.SELL}
    assert model.position.direction is Direction.BUY
    assert model.position.entry == 1.1000
    assert model.initial_pending == []
```

- [ ] **Step 5: 运行新增测试，确认它们因接口尚未实现而失败**

Run: `python -m pytest -q tests/test_strategy_logic.py -k "candle_once_places_buy or candle_once_reverse or candle_repeat_still or initial_pending_fill"`

Expected: FAIL，失败原因是 `StrategyModel` 尚未产生 `initial_pending` 行为或尚未提供 `fill_initial_pending`。

- [ ] **Step 6: Commit the failing tests**

```bash
git add tests/test_strategy_logic.py
git commit -m "test: specify candle first-order pending behavior"
```

### Task 2: 实现 Python 行为模型的双向首单 OCO

**Files:**
- Modify: `tests/strategy_logic.py:224-590`
- Test: `tests/test_strategy_logic.py`

- [ ] **Step 1: 增加独立的首单挂单集合状态**

在 `StrategyModel.__init__` 增加 `self.initial_pending = []`，保持 `self.pending` 只表示后续反向挂单；新增 `_initial_pending_directions(previous_high, previous_low)`，按 `OrderType.FORWARD` 返回 `(BUY, SELL)`，否则返回 `(SELL, BUY)`。

- [ ] **Step 2: 实现只在距离模式 K线高度且 korder_type=0 时创建两张首单挂单**

在 `on_tick` 的空仓入口先处理 `self.initial_pending`；当模式满足条件时校验距离和上一根 K 线高低点，构造两个 `Pending(kind="initial")`，价格分别为 `previous_high` 和 `previous_low`，订单类型根据当前 bid/ask 选择 STOP/LIMIT，并返回两个 `initial_pending` 动作。不要调用 `_try_open` 或 `_breakout_direction`。

- [ ] **Step 3: 实现首单成交后的 OCO 转换**

新增 `fill_initial_pending(direction, entry_price)`：查找指定方向的首单挂单，清空整个 `initial_pending`，调用 `_open(direction, entry_price, initial_lots, distance_points)`，并返回一个 `cancel_initial_pending` 动作；随后沿用 `_next_pending` 与 `_ensure_grid_pending` 产生现有后续挂单。

- [ ] **Step 4: 保持每根多次和固定距离分支不变**

仅把双向预埋分支放在 `distance_mode is CANDLE_RANGE and korder_type == 0`；原有 `korder_type == 1` 突破判断与固定距离市价开仓路径继续执行。

- [ ] **Step 5: 运行新增和全量模型测试**

Run: `python -m pytest -q tests/test_strategy_logic.py -k "candle_once_places_buy or candle_once_reverse or candle_repeat_still or initial_pending_fill"`

Expected: 4 passed。

Run: `python -m pytest -q tests/test_strategy_logic.py`

Expected: 4 个新增模型测试通过；若现有的“每根一次”旧测试仍断言市价开仓，则把该旧测试改为断言双向 `initial_pending`，其余非K线首单、后续反向、网格和GUI测试保持通过。

- [ ] **Step 6: Commit Python implementation**

```bash
git add tests/strategy_logic.py tests/test_strategy_logic.py
git commit -m "feat: model candle first-order pending OCO"
```

### Task 3: 添加 MT4/MT5 源码契约测试并实现单组路径

**Files:**
- Modify: `tests/test_strategy_logic.py`（源码契约）
- Modify: `NoMatterRiseFall_MT5.mq5`（单组状态、持久化、首单挂单与管理）
- Modify: `NoMatterRiseFall_MT4.mq4`（单组状态、持久化、首单挂单与管理）

- [ ] **Step 1: 添加源码契约测试并先运行确认失败**

契约测试对两份源码断言存在独立的 `PlaceInitialPendingPair`、`HandleInitialPendingFill`、`initial_high_ticket`、`initial_low_ticket` 和 `KORDER_ONCE_PER_BAR` 分支；运行 `python -m pytest -q tests/test_strategy_logic.py -k "initial_pending_source_contract"`，预期因函数/字段尚不存在而失败。

- [ ] **Step 2: 为 MT5 单组增加首单双票据和持久化字段**

增加 `g_initial_high_ticket`、`g_initial_low_ticket`、对应价格/方向字段；在 SaveState/LoadState/ClearState/ResetInMemoryStrategyState 中保存、读取和清理。MT4 使用对应的 `int` 类型和相同语义。

- [ ] **Step 3: 实现两平台的首单挂单发送和回滚**

新增 `PlaceInitialPendingPair(previous_high, previous_low, range_points, volume)`：按照开单方式选方向，在高低点发送两张带止盈止损的 pending；第一张成功但第二张失败时删除第一张并返回 false；成功后保存两张票据和价格。使用带首单标识的注释，使其不被 `FindPending` 当作反向挂单。

- [ ] **Step 4: 实现两平台的首单状态检测和 OCO 清理**

新增首单状态函数，分别识别 ACTIVE、FILLED、CANCELED/UNKNOWN；若任一票据成交，先删除另一张仍活动的首单，再根据成交订单找到持仓、初始化组锚点/手数/止盈止损距离，最后调用现有 `EnsureNextPending` 和 `EnsureGridPending`。删除失败时保持状态并在下一 Tick 重试。

- [ ] **Step 5: 修改单组 Manage 空仓入口**

在“距离模式=K线高度、K线开单模式=每根一次”时，先恢复/管理首单双向挂单；没有首单双票据且无其他挂单时，读取上一根 K 线高度并调用 `PlaceInitialPendingPair`。只有“每根多次”继续调用现有 `GetBreakoutDirection` 后 `OpenMarket`；固定距离分支不变。

- [ ] **Step 6: 运行契约测试并提交单组实现**

Run: `python -m pytest -q tests/test_strategy_logic.py -k "initial_pending_source_contract or candle_distance_mode"`

Expected: PASS，且 MT4/MT5 均通过。

```bash
git add NoMatterRiseFall_MT4.mq4 NoMatterRiseFall_MT5.mq5 tests/test_strategy_logic.py
git commit -m "feat: add single-group candle first-order pending OCO"
```

### Task 4: 实现允许多订单组并行路径

**Files:**
- Modify: `tests/test_strategy_logic.py`（多组行为/源码契约）
- Modify: `tests/strategy_logic.py`（多组模型的首单成交转发）
- Modify: `NoMatterRiseFall_MT5.mq5`（`MultiGroupState` 与多组管理）
- Modify: `NoMatterRiseFall_MT4.mq4`（`MultiGroupState` 与多组管理）

- [ ] **Step 1: 添加多组模型首单双向预埋测试并先确认失败**

在 `ParallelStrategyModel` 测试区域断言 `kline_enable_multiple=1` 且 `korder_type=0` 时新组返回两个 `initial_pending` 动作，第二次同一 candle_id 不新增组；`korder_type=1` 仍返回 market 动作。

- [ ] **Step 2: 为 MT4/MT5 `MultiGroupState` 增加首单双票据字段**

增加 high/low 两张首单票据、价格和方向字段，在 `MultiResetState`、`MultiSaveGroup`、`MultiLoadGroups` 中对称处理；多组注释必须同时包含 group id 与首单标识，避免跨组误删。

- [ ] **Step 3: 实现 `MultiPlaceInitialPendingPair` 和组级 OCO**

按组配置的 K线高度、手数和开单方式发送双向首单；失败时回滚已发送单；检测任一成交后删除另一张，初始化该组首单状态并进入现有 `MultiSetStops`、`MultiPlaceReversePending`、`MultiPlaceGridPending` 流程。

- [ ] **Step 4: 修改 `MultiTryOpenCandleGroup` 的模式分支**

`KORDER_ONCE_PER_BAR` 分支只负责创建双向首单组并记录 `g_multi_last_trigger_bar`；`KORDER_REPEAT_PER_BAR` 分支保留现有突破判断与 `MultiOpenMarket`。已有活动组仍先管理，首单双挂单不应被当作“无活动组”而删除。

- [ ] **Step 5: 运行多组测试并提交**

Run: `python -m pytest -q tests/test_strategy_logic.py -k "parallel or initial_pending"`

Expected: 新增多组测试与现有多组测试全部通过。

```bash
git add NoMatterRiseFall_MT4.mq4 NoMatterRiseFall_MT5.mq5 tests/strategy_logic.py tests/test_strategy_logic.py
git commit -m "feat: support candle first-order pending in parallel groups"
```

### Task 5: 更新文档并完成全量验证

**Files:**
- Modify: `README.md:8,16,30`（K线模式和参数说明）
- Modify: `docs/superpowers/specs/2026-09-02-candle-first-order-pending-design.md`（仅在最终实现字段名与设计文档不一致时同步字段/恢复说明）

- [ ] **Step 1: 更新 README 行为描述**

明确写出：K线高度且每根一次时，在上一根已完成 K 线最高/最低点同时预埋首单；正向为高点多、低点空，逆向相反；一张成交后取消另一张。每根多次仍为突破后市价开单。

- [ ] **Step 2: 运行格式和全量测试**

Run: `git diff --check`

Expected: 无输出。

Run: `python -m pytest -q`

Expected: 全部测试通过。

- [ ] **Step 3: 检查源码状态和提交记录**

Run: `git status --short; git log --oneline -6`

Expected: 只有本功能相关的已提交变更，无意外生成文件；若没有 MT4/MT5 编译器，则明确记录未执行编译，并依靠源码契约和 Python 测试验证结构。

- [ ] **Step 4: Commit documentation and final changes**

```bash
git add README.md docs/superpowers/specs/2026-09-02-candle-first-order-pending-design.md
git commit -m "docs: document candle first-order pending behavior"
```
