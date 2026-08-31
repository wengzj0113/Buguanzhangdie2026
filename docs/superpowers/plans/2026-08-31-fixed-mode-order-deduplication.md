# 固定距离模式订单防重 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 保证固定距离模式在同一账户、品种和订单识别编号下只有一个交易管理者，并阻止重复首单、反向挂单、网格挂单及挂单成交后的重复市价反手继续放大手数。

**Architecture:** MT4和MT5在初始化时取得跨终端独占文件锁，第二实例直接初始化失败。单组管理入口先归一化服务器挂单并检测重复主持仓；所有开单前重新核对服务器状态，止损切换优先接管已成交挂单，异常重复状态只撤销未成交风险并暂停，不改变策略计算公式。

**Tech Stack:** MQL5/CTrade、MQL4、Python 3、pytest、MetaEditor。

---

## 文件结构与职责

- Modify: `tests/strategy_logic.py` — 增加实例所有权、挂单唯一化和重复风险暂停的可执行模型。
- Modify: `tests/test_strategy_logic.py` — 增加双实例、重复挂单、重复主订单和成交后禁止市价补单的回归测试。
- Modify: `NoMatterRiseFall_MT5.mq5` — 独占实例锁、挂单枚举归一化、重复持仓保护和止损切换复核。
- Modify: `NoMatterRiseFall_MT4.mq4` — 与MT5一致的防重逻辑。
- Modify: `README.md` — 说明相同订单识别编号只能由一个EA实例管理及异常保护行为。
- Modify: `docs/superpowers/specs/2026-08-31-fixed-mode-order-deduplication-design.md` — 记录最终采用的公共文件独占锁机制。

## Task 1: 建立可复现的防重模型

**Files:**
- Modify: `tests/strategy_logic.py`
- Modify: `tests/test_strategy_logic.py`

- [ ] **Step 1: 写实例所有权失败测试**

在 `tests/test_strategy_logic.py` 增加：

```python
def test_same_scope_allows_only_one_execution_owner():
    registry = ExecutionOwnershipRegistry()
    assert registry.acquire((111, "XAUUSD", 20260830), "chart-a") is True
    assert registry.acquire((111, "XAUUSD", 20260830), "chart-b") is False
    registry.release((111, "XAUUSD", 20260830), "chart-a")
    assert registry.acquire((111, "XAUUSD", 20260830), "chart-b") is True


def test_different_magic_numbers_have_independent_execution_owners():
    registry = ExecutionOwnershipRegistry()
    assert registry.acquire((111, "XAUUSD", 1), "chart-a") is True
    assert registry.acquire((111, "XAUUSD", 2), "chart-b") is True
```

- [ ] **Step 2: 写挂单唯一化失败测试**

```python
def test_duplicate_reverse_pending_keeps_tracked_ticket_and_deletes_rest():
    orders = [
        PendingRecord(12, "reverse", Direction.SELL, 0.06, 4436.69),
        PendingRecord(10, "reverse", Direction.SELL, 0.06, 4436.69),
    ]
    result = normalize_pending_records(orders, tracked_ticket=12)
    assert result.keep_ticket == 12
    assert result.delete_tickets == [10]


def test_duplicate_grid_pending_without_tracked_ticket_keeps_lowest_ticket():
    orders = [
        PendingRecord(22, "grid", Direction.BUY, 0.04, 4437.69),
        PendingRecord(20, "grid", Direction.BUY, 0.04, 4437.69),
    ]
    result = normalize_pending_records(orders)
    assert result.keep_ticket == 20
    assert result.delete_tickets == [22]
```

- [ ] **Step 3: 写重复主订单暂停失败测试**

```python
def test_duplicate_base_positions_pause_new_risk_and_lot_growth():
    exposure = ExposureSnapshot(base_positions=2, duplicate_grid_levels=0)
    decision = exposure_guard(exposure)
    assert decision.pause_new_orders is True
    assert decision.cancel_pending is True
    assert decision.accumulate_loss_lots is False
```

- [ ] **Step 4: 运行测试确认RED**

Run: `python -m pytest -q tests/test_strategy_logic.py -k "execution_owner or duplicate_reverse or duplicate_grid or duplicate_base"`

Expected: FAIL，提示 `ExecutionOwnershipRegistry`、`PendingRecord` 或 `ExposureSnapshot` 尚未定义。

- [ ] **Step 5: 实现最小Python模型**

在 `tests/strategy_logic.py` 增加 `ExecutionOwnershipRegistry`、`PendingRecord`、`PendingNormalization`、`normalize_pending_records()`、`ExposureSnapshot`、`ExposureDecision` 和 `exposure_guard()`。所有选择必须确定性：优先保留仍存在的跟踪票据，否则保留最小票据。

- [ ] **Step 6: 运行测试确认GREEN**

Run: `python -m pytest -q tests/test_strategy_logic.py -k "execution_owner or duplicate_reverse or duplicate_grid or duplicate_base"`

Expected: 新增测试全部通过。

## Task 2: MT5独占管理者和异常风险门控

**Files:**
- Modify: `NoMatterRiseFall_MT5.mq5`
- Test: `tests/test_strategy_logic.py`

- [ ] **Step 1: 增加MT5源码契约失败测试**

在 `tests/test_strategy_logic.py` 读取 `NoMatterRiseFall_MT5.mq5` 并断言源码包含 `AcquireExecutionOwnership`、`ReleaseExecutionOwnership`、`NormalizeSingleGroupPending` 和 `HasDuplicateSingleGroupExposure`，且 `OnInit()` 获取锁、`OnDeinit()`释放锁、`Manage()`在交易动作前执行异常门控。

- [ ] **Step 2: 运行源码契约测试确认RED**

Run: `python -m pytest -q tests/test_strategy_logic.py -k "mt5_dedup_source_contract"`

Expected: FAIL，缺少新的防重函数。

- [ ] **Step 3: 实现MT5独占文件锁**

增加全局锁句柄和函数：

```cpp
int g_execution_lock_handle = INVALID_HANDLE;

string ExecutionLockFileName();
bool AcquireExecutionOwnership();
void ReleaseExecutionOwnership();
```

锁文件名包含账户服务器、登录号、品种和订单识别编号；非测试环境使用 `FILE_COMMON|FILE_BIN|FILE_READ|FILE_WRITE` 且不设置共享标志。`OnInit()`参数校验后获取锁，失败时打印冲突信息并返回 `INIT_FAILED`；`OnDeinit()`关闭句柄。

- [ ] **Step 4: 实现MT5挂单归一化**

实现 `NormalizeSingleGroupPending(bool grid)`：扫描当前品种和Magic下该类别全部挂单，优先保留 `g_pending_ticket` 对应的有效反向挂单，否则保留最小票据；删除其余同类挂单。删除失败返回 `false`。`Manage()`在重置检查之后、持仓和首单判断之前调用反向及网格归一化，失败立即返回。

- [ ] **Step 5: 实现MT5重复风险门控**

实现 `HasDuplicateSingleGroupExposure()`：对冲账户中非网格主持仓超过一张，或存在方向、开仓价和手数均相同的重复网格持仓时返回 `true`。触发后删除尚未成交挂单、设置日志去重标记并从 `Manage()` 返回；不累计亏损、不推进循环、不自动平仓。

- [ ] **Step 6: 加强MT5止损市价复核**

在 `Transition()` 调用 `OpenMarket()` 前重新执行挂单归一化和服务器状态扫描。若 `g_pending_ticket` 已成交并能通过订单或成交历史找到对应持仓，返回上层接管成交结果；若仍存在无法删除的挂单或重复主持仓，禁止市价发送。

- [ ] **Step 7: 编译MT5并运行契约测试**

Run: `python -m pytest -q tests/test_strategy_logic.py -k "mt5_dedup_source_contract or duplicate"`

Run: `& 'C:\Program Files\MetaTrader 5\MetaEditor64.exe' /compile:'<worktree>\NoMatterRiseFall_MT5.mq5' /log`

Expected: 测试通过；编译日志 `Result: 0 errors, 0 warnings`。

## Task 3: MT4同步防重行为

**Files:**
- Modify: `NoMatterRiseFall_MT4.mq4`
- Test: `tests/test_strategy_logic.py`

- [ ] **Step 1: 增加MT4源码契约失败测试**

读取 `NoMatterRiseFall_MT4.mq4`，断言与MT5相同的四个防重函数以及 `OnInit()`/`OnDeinit()`接线存在。

- [ ] **Step 2: 运行源码契约测试确认RED**

Run: `python -m pytest -q tests/test_strategy_logic.py -k "mt4_dedup_source_contract"`

Expected: FAIL，缺少MT4防重函数。

- [ ] **Step 3: 实现MT4独占文件锁**

使用 `FileOpen(..., FILE_COMMON|FILE_BIN|FILE_READ|FILE_WRITE)`、`FileClose()` 和 `INVALID_HANDLE` 实现与MT5相同的账户、服务器、品种、Magic锁键。`OnInit()`冲突时返回 `INIT_FAILED`，`OnDeinit()`释放。

- [ ] **Step 4: 实现MT4挂单归一化和重复风险门控**

使用 `OrderSelect`、`OrderTicket`、`OrderComment`、`OrderOpenPrice`、`OrderLots` 实现与MT5相同的确定性保留规则和重复主订单/网格订单检测。删除失败时不允许继续开单。

- [ ] **Step 5: 加强MT4止损市价复核**

在 `Transition()` 的 `OrderSend` 前重新扫描历史订单和当前持仓；已存在预期成交结果时不得再次市价发送，异常重复状态暂停新增风险。

- [ ] **Step 6: 编译MT4并运行契约测试**

Run: `python -m pytest -q tests/test_strategy_logic.py -k "mt4_dedup_source_contract or duplicate"`

Run: `& 'C:\Program Files (x86)\FXGiants MetaTrader 4\metaeditor.exe' /compile:'<worktree>\NoMatterRiseFall_MT4.mq4' /log`

Expected: 测试通过；编译日志 `Result: 0 errors, 0 warnings`。

## Task 4: 文档、完整回归和交付

**Files:**
- Modify: `README.md`
- Modify: `docs/superpowers/specs/2026-08-31-fixed-mode-order-deduplication-design.md`

- [ ] **Step 1: 更新中文运行说明**

说明同一账户、品种和订单识别编号只能运行一个EA管理实例；冲突实例初始化失败。说明检测到历史重复主订单时会撤销剩余挂单并暂停新增风险，不会自动平掉已有持仓。

- [ ] **Step 2: 运行完整自动测试**

Run: `python -m pytest -q`

Run: `python -m py_compile tests/strategy_logic.py tests/test_strategy_logic.py`

Expected: 全部测试通过，Python编译无输出。

- [ ] **Step 3: 编译MT5和MT4**

分别使用MetaEditor编译两份源码。

Expected: 两份日志均为 `0 errors, 0 warnings`。

- [ ] **Step 4: 做静态审计**

Run: `git diff --check`

Run: `rg -n "OpenMarket\(|PlaceNextPending\(|PlaceGridPending\(|AcquireExecutionOwnership|NormalizeSingleGroupPending|HasDuplicateSingleGroupExposure" NoMatterRiseFall_MT5.mq5 NoMatterRiseFall_MT4.mq4`

逐个确认首单、反向挂单、网格挂单和市价反手入口均受唯一管理者和服务器状态复核保护。

- [ ] **Step 5: 同步编译产物并核验哈希**

将工作树生成的 `.ex5`/`.ex4` 复制到项目主工作区和已安装MetaTrader对应EA目录，使用SHA256确认源产物与目标文件一致。

- [ ] **Step 6: 完成最终审计**

对照设计规格逐项确认：固定模式唯一首单、反向挂单唯一、网格挂单唯一、已成交不重复市价、重复风险停止放大、策略公式未变、MT4/MT5编译和完整测试均有直接证据。
