# K线高度模式多订单组 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在MT4和MT5中增加 `kline_enable_multiple`，使K线高度模式可按配置运行单订单组或多个相互独立的订单组。

**Architecture:** 保留现有单组路径作为 `kline_enable_multiple=0` 和固定距离模式的兼容实现；为多组路径增加订单组记录集合和按组处理器。每个订单的注释携带组ID，订单扫描按组归属，所有挂单、持仓、状态清理和距离计算都接收组对象，禁止继续使用全局“全部订单”操作处理正常组生命周期。

**Tech Stack:** MQL5/CTrade、MQL4、Python 3、pytest、MetaEditor。

---

## 文件结构与职责

- Modify: `NoMatterRiseFall_MT5.mq5` — 输入参数、订单组数据结构、按组查询/发送/管理和状态持久化。
- Modify: `NoMatterRiseFall_MT4.mq4` — 与MT5行为一致的订单组数据结构、订单筛选和管理实现。
- Modify: `tests/strategy_logic.py` — 增加多组策略模型和按组隔离的动作模拟。
- Modify: `tests/test_strategy_logic.py` — 增加参数、触发、隔离、恢复和异常路径测试。
- Modify: `README.md` — 中文参数说明、单组/多组差异和Korder_type组合规则。
- Modify: `mt5_cycle_test.ini` — 增加 `kline_enable_multiple=0` 的测试参数。
- Create: `docs/superpowers/specs/2026-08-31-kline-multiple-groups-design.md` — 已确认的设计规格。

## Task 1: 用Python模型定义多组边界

**Files:** `tests/strategy_logic.py`, `tests/test_strategy_logic.py`

- [ ] **Step 1: 增加配置和订单组模型接口**

定义 `OrderGroupState`，至少包含 `group_id`、`position`、`pending`、`grid_pending`、`group_stop_points`、`group_take_profit_points`、`current_index`、`reversal_count`、`cumulative_loss_lots`、`grid_lots` 和 `candle_id`。`StrategyModel`增加 `kline_enable_multiple=0`，单组模式继续由现有字段驱动，多组模式使用 `self.groups`。

```python
@dataclass
class OrderGroupState:
    group_id: int
    position: Position | None = None
    pending: Pending | None = None
    grid_pending: Pending | None = None
    group_stop_points: int | None = None
    group_take_profit_points: int | None = None
    current_index: int = 0
    reversal_count: int = 0
    cumulative_loss_lots: float = 0.0
    grid_lots: float = 0.0
    candle_id: int | None = None
```

- [ ] **Step 2: 写入失败测试**

新增以下验收用例：

```python
def dynamic_model(multiple, korder_type=0):
    return StrategyModel(
        Direction.BUY, CycleMode.MODE_1, 0.01, 2.0, 500, 0.0001,
        distance_mode=DistanceMode.CANDLE_RANGE,
        min_range_points=500, max_range_points=1000,
        order_type=OrderType.FORWARD, grid_count=2,
        korder_type=korder_type, kline_enable_multiple=multiple,
    )


def breakout(model, candle_id, range_points, bid=1.1010, ask=1.1012):
    return model.on_tick(
        bid=bid, ask=ask, candle_range_points=range_points,
        previous_high=1.1000, previous_low=1.0400,
        candle_id=candle_id,
    )


def test_kline_multiple_zero_blocks_new_group_while_existing_group_is_active():
    model = dynamic_model(0)
    assert breakout(model, 10, 600)[0]["kind"] == "market"
    assert breakout(model, 11, 900) == []
    assert len(model.groups) == 1


def test_kline_multiple_one_opens_independent_group_with_existing_group():
    model = dynamic_model(1)
    breakout(model, 10, 600)
    actions = breakout(model, 11, 900)
    assert actions[0]["kind"] == "market"
    assert len(model.groups) == 2
    assert {group.group_id for group in model.groups} == {1, 2}


def test_parallel_groups_keep_different_candle_distances():
    model = dynamic_model(1)
    breakout(model, 10, 600)
    breakout(model, 11, 900)
    assert [group.group_stop_points for group in model.groups] == [600, 900]
    assert [group.group_take_profit_points for group in model.groups] == [600, 900]


def test_take_profit_of_one_group_does_not_close_other_group():
    model = dynamic_model(1)
    breakout(model, 10, 600)
    breakout(model, 11, 900)
    first = model.groups[0]
    second = model.groups[1]
    model.on_tick(bid=first.position.take_profit,
                  ask=first.position.take_profit + 0.0002,
                  candle_id=11)
    assert first.position is None
    assert second.position is not None
    assert second.pending is not None


def test_parallel_groups_keep_reverse_and_grid_pending_separate():
    model = dynamic_model(1)
    breakout(model, 10, 600)
    breakout(model, 11, 900)
    first, second = model.groups
    assert first.pending is not None and second.pending is not None
    assert first.grid_pending is not None and second.grid_pending is not None
    first_pending = first.pending
    model.fill_pending(first_pending.price, group_id=first.group_id)
    assert second.pending is not None
    assert second.grid_pending is not None


def test_korder_type_zero_limits_parallel_initial_trigger_to_one_per_k0():
    model = dynamic_model(1, korder_type=0)
    breakout(model, 10, 600)
    assert breakout(model, 10, 600) == []
    assert len(model.groups) == 1


def test_korder_type_one_allows_parallel_initial_triggers_on_same_k0():
    model = dynamic_model(1, korder_type=1)
    breakout(model, 10, 600)
    assert breakout(model, 10, 600)[0]["kind"] == "market"
    assert len(model.groups) == 2
```

测试中必须明确：组A距离600点、组B距离900点；组A止盈后组B仍有持仓和挂单；组A和组B的反向挂单票据/网格层级不可互相覆盖。

- [ ] **Step 3: 运行测试确认失败**

运行 `python -m pytest -q tests/test_strategy_logic.py -k "multiple or parallel"`，预期新增测试因没有 `OrderGroupState` 和 `kline_enable_multiple` 行为而失败。

## Task 2: 完成Python模型的按组状态机

**Files:** `tests/strategy_logic.py`, `tests/test_strategy_logic.py`

- [ ] **Step 1: 实现组创建和触发门控**

新增 `can_open_candle_group()`、`create_candle_group()` 和 `manage_group(group)`。K线模式先验证 `k1` 高度和 `k0` 突破；参数为0时要求 `not self.groups`，参数为1时允许已有组。以 `(candle_id, breakout_side)` 作为触发键；`korder_type=0` 已触发后拒绝同一键，`korder_type=1`允许再次创建。

- [ ] **Step 2: 把现有生命周期逻辑改为组参数**

将止盈、止损、反向预挂单、网格成交、网格移动止盈、线性移动止盈、最大反手次数和资金不足动作全部改为接收 `group`。每个动作返回 `group_id`，例如 `{"kind": "market", "group_id": 2, "direction": Direction.BUY, "lots": 0.01}`，清理动作必须只清理对应组。

- [ ] **Step 3: 运行模型回归**

运行 `python -m pytest -q`，预期所有旧测试与新增多组测试通过；若旧测试依赖无组ID的动作，先保留单组模式动作格式兼容，再仅对多组动作增加组ID。

## Task 3: MT5增加订单组基础设施

**Files:** `NoMatterRiseFall_MT5.mq5`

- [ ] **Step 1: 增加输入参数和组结构**

增加用户参数并校验为0或1：

```cpp
input int kline_enable_multiple = 0; // K线高度模式是否允许多个订单组并行
```

定义可扩展的组数组，并在创建新组时用 `ArrayResize` 增加元素；组结构字段必须覆盖设计文档中的距离、循环、反手、网格、移动止盈、挂单票据和组ID。数组扩展失败时记录日志并暂停新组，已有组继续管理。

- [ ] **Step 2: 增加组注释和订单筛选函数**

实现以下接口，并让所有新订单调用它们：

```cpp
string GroupComment(const int group_id, const bool is_grid);
bool IsOurGroupOrder(const ulong ticket, const int group_id, const bool include_pending);
int FindGroupByOrder(const ulong ticket);
int AllocateGroup(const int candle_id, const long breakout_side);
void ReleaseGroup(const int group_id);
```

组注释保留原订单注释内容，并追加稳定的 `.G<group_id>` 标记；网格订单同时保留 `.Grid` 标记。

- [ ] **Step 3: 实现按组查询和清理**

将 `FindPosition`、`FindPending`、`FindGridPending`、`DeleteAllPending`、`CloseAllPositions` 的核心逻辑拆出带 `group_id` 的版本。多组正常运行只能调用 `DeleteGroupPending(group_id)` 和 `CloseGroupPositions(group_id)`；全量删除/平仓仅保留给资金不足、最大反手次数和显式全量重置。

## Task 4: MT5接入动态多组入口和独立管理

**Files:** `NoMatterRiseFall_MT5.mq5`

- [ ] **Step 1: 分离首单触发与单组管理**

将当前 `Manage()` 拆为 `ManageSingleGroup()`、`TryOpenCandleGroups()` 和 `ManageAllGroups()`。固定距离模式和 `kline_enable_multiple=0` 继续调用兼容单组路径；动态多组模式先遍历已有组，再执行K线入口，不得因为已有组而提前返回。

- [ ] **Step 2: 锁定新组的K线距离和方向**

每次创建组时从当前 `k1` 读取高度；只有高度处于闭区间 `[K线最小高度, K线最大高度]` 且 `k0` 突破极值时才发送首单。首单成功后把该高度写入组的止损和止盈距离，后续不再读取新K线覆盖该组字段。

- [ ] **Step 3: 将订单组生命周期改为组级操作**

组级处理顺序固定为：识别反向预挂单成交→识别网格挂单成交→补齐该组止损止盈→更新该组移动止盈→检查该组止盈→检查该组止损/反手→补该组反向预挂单→补该组下一网格预挂单。反向挂单成交后当前Tick立即返回该组处理结果，保留重复开单修复。

- [ ] **Step 4: 增加MT5持久化和重启恢复**

以 `StatePrefix()+".group.<id>.<field>"` 保存组状态，保存组ID分配器和触发键；启动时扫描本EA订单注释恢复活动组。无法完整恢复的组只保留订单管理所需最小字段，并等待下一Tick补齐，禁止误开新首单。

- [ ] **Step 5: 编译MT5并运行测试**

运行 `python -m pytest -q`、`python -m py_compile tests/strategy_logic.py tests/test_strategy_logic.py`，再运行
`& 'C:\\Program Files\\MetaTrader 5\\MetaEditor64.exe' /compile:'D:\\00_EA\\codx-ea\\Experts\\不管涨跌复刻\\NoMatterRiseFall_MT5.mq5' /log`。
预期Python测试全通过，编译日志为 `0 errors, 0 warnings`。

## Task 5: 同步MT4按组实现

**Files:** `NoMatterRiseFall_MT4.mq4`

- [ ] **Step 1: 复制参数、组结构和注释编码规则**

保持 `kline_enable_multiple` 默认0、有效值0/1和与MT5相同的 `.G<group_id>` / `.Grid` 注释格式；使用MT4订单票据和订单注释完成组归属。

- [ ] **Step 2: 实现MT4按组查询、挂单、平仓和状态恢复**

将MT5的组级接口逐一映射为MT4 `OrderSelect`、`OrderSend`、`OrderDelete`、`OrderClose` 逻辑；正常组生命周期不调用全量清理函数，资金不足和全局重置继续调用全量清理。

- [ ] **Step 3: 编译MT4并回归测试**

运行
`& 'C:\\Program Files (x86)\\FXGiants MetaTrader 4\\metaeditor.exe' /compile:'D:\\00_EA\\codx-ea\\Experts\\不管涨跌复刻\\NoMatterRiseFall_MT4.mq4' /log`，预期 `0 errors, 0 warnings`；随后再次运行 `python -m pytest -q`。

## Task 6: 配置、文档和验收

**Files:** `README.md`, `mt5_cycle_test.ini`, `tests/test_strategy_logic.py`

- [ ] **Step 1: 增加中文参数说明**

说明 `kline_enable_multiple=0` 是单组，`=1` 是并行多组；说明仅K线高度模式生效；说明 `Korder_type=0/1` 与多组参数的组合；说明组间独立和资金不足/最大反手次数仍是全量清仓例外。

- [ ] **Step 2: 更新测试配置**

在 `mt5_cycle_test.ini` 增加：

```text
kline_enable_multiple=0||0||0||1||N
```

- [ ] **Step 3: 做变更审计和静态检查**

运行 `git diff --check`、`rg -n "DeleteAllPending|CloseAllPositions|ClearState" NoMatterRiseFall_MT5.mq5 NoMatterRiseFall_MT4.mq4`，逐处确认正常多组路径使用带组ID的清理函数；再运行完整Python测试和两端编译。

- [ ] **Step 4: 生成验收记录**

记录以下场景的实际结果：单组动态模式、多组不同K线距离、同组反手、同组网格、同组移动止盈、组A止盈而组B继续、资金不足全量清仓、最大反手次数全量清仓、EA重启恢复。只有全部通过后才输出完成。
