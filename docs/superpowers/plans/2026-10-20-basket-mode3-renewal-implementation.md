# Basket Mode 3 Renewal Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. 本计划按顺序在当前会话执行；不要默认启动并行子代理修改交易源码。

**Goal:** 新增 `篮子数量=3`：首次正反双篮子；一篮子结束后，存续篮子的有效止损换单再配一个反向、等首单成交总手数的新篮子。

**Architecture:** 复用当前首单和组管理器，以独立持久配对记录保存归属、结束事实和一次性补开事件。三条原止损路径只记录与确认事件，原组遍历完成后统一对账并补开；不从活动组数量推断关系。

**Tech Stack:** MQL4/MQL5、终端 Global Variables、现有组注释与交易请求恢复、Python/pytest、PowerShell、MetaEditor、隔离 MT5 策略测试器。

**Spec:** `docs/superpowers/specs/2026-10-20-basket-mode3-renewal-design.md`。本计划仅落实该功能，不重构旧策略引擎。

---

## 文件地图与约束

项目根目录：`D:\00_EA\codx-ea\Experts\不管涨跌复刻`。下列项目相对路径均相对此目录；执行命令前先设置该工作目录。

| 文件 | 本轮责任 |
| --- | --- |
| `NoMatterRiseFall_MT4.mq4` | 兼容 MT4：输入、组状态、配对记录、止损/结束挂钩、遍历后补开 |
| `NoMatterRiseFall_MT5.mq5` | 兼容 MT5：同上，沿用 CTrade 请求与对冲账户要求 |
| `NoMatterRiseFall_MT4_Core.mqh` | 十种固定 MT4 模式：同上，保留已有请求未决保护和退避 |
| `NoMatterRiseFall_MT5_Core.mqh` | 十种固定 MT5 模式：同上，保留已有隔离和暴露恢复 |
| `tests/strategy_logic.py` | 扩展已有首次篮子方向/首单计划模型，新增模式 3 的纯规则判定 |
| `tests/test_strategy_logic.py` | 更新旧参数、方向、入口路由断言，保留独立 XAU 的 1/2 契约 |
| `tests/test_basket_mode3.py`（新） | 规则测试、四目标接线契约、批次/事件/恢复测试 |
| `tests/test_basket_mode3_replay.py`（新） | 交易审计器的有效/重复/手数错误/迟到事件样本测试 |
| `scripts/test-basket-mode3-mt5.ps1`（新） | 隔离对冲回放，分别运行模式 2/3，导出 set/ini/成交与日志 |
| `scripts/audit-basket-mode3-replay.py`（新） | 以实际订单/成交为准核对一次性、反向、等量和独立管理 |
| `validation/basket-mode3-2026-10-20/`（新） | 基线、场景清单、回放证据、编译汇总、交付 manifest |
| `README.md`、`EA软件使用手册.html` | 参数 3 的规则、示例、恢复和“不是三篮子”说明 |

固定模式薄入口、独立 XAU、指标源码、旧参数顺序、默认 Magic、原手数/方向/距离公式均不在本轮修改范围内。没有请求新增 GUI 控件；MT5 现有 `篮子数量` 是原生输入，检查其校验调用链即可，不凭旧计划假设它已是独立面板字段。

## 任务 0：冻结工作基线

**读/记录：** 四个目标源码、现有测试、AGENTS.md、编译脚本。**新建：** 验证目录。

- [ ] 执行下列命令，把输出保存到验证目录的 `baseline-status.txt`、`baseline-diff.txt`；记录四个目标 SHA256、长度、修改时间。已有改动属于实施前基线。

```powershell
git status --short
git diff --stat
git diff --cached --name-only
Get-FileHash -Algorithm SHA256 -LiteralPath .\NoMatterRiseFall_MT4.mq4, .\NoMatterRiseFall_MT5.mq5, .\NoMatterRiseFall_MT4_Core.mqh, .\NoMatterRiseFall_MT5_Core.mqh
```

- [ ] 将四个目标及将修改的既有测试/文档复制到验证目录的 `baseline/`，保留相对路径；只复制明确列出的文件，不递归移动或清理工作区。
- [ ] 执行一次实施前完整测试：`uv run --with pytest -- python -m pytest -q`。有失败时记录与本功能的关系；不把已有失败伪装成新改动，也不未经分析删除断言。
- [ ] 列出编译器与源矩阵：`powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\compile-mql.ps1 -ListCompilers`；再使用 `-ListSources -Target Both` 及 `-ListSources -Target Both -Profile All`。应分别列出 2 与 20 个目标；当前没有改源码，无需此时编译。
- [ ] 用 `rg` 重新定位下表锚点，后续按函数边界精确修改；行号是方案编写时的定位参考，不用于整段盲替换。

| 目标 | 重点锚点和当前行号 |
| --- | --- |
| MT4 兼容 | `MultiGroupState:3555`、`MultiHandleReverseFill:5240`、`MultiRecoverFlatGroupAfterBrokerStop:5316`、`MultiManageGroup:5421`、`StartResolvedMultiPair:5881`、`ManageAllMultiGroups:6017` |
| MT5 兼容 | `MultiGroupState:6003`、`MultiStartResolvedPair:7119`、`MultiHandleReverseFill:8111`、`MultiRecoverFlatGroupAfterBrokerStop:8210`、`MultiManageGroup:8300`、`ManageMultipleCandleGroups:8761` |
| MT4 核心 | `MultiGroupState:4261`、`MultiHandleReverseFill:6108`、`MultiRecoverFlatGroupAfterBrokerStop:6184`、`MultiManageGroup:6377`、`StartResolvedMultiPair:6882`、`ManageAllMultiGroups:7028` |
| MT5 核心 | `MultiGroupState:6718`、`MultiHandleReverseFill:9051`、`MultiRecoverFlatGroupAfterBrokerStop:9150`、`MultiManageGroup:9283`、`ManageMultipleCandleGroups:9910` |

**停止条件：** 不能确认实施前文件已保存，或测试执行环境不可用时，先解决基线问题，不修改交易代码。

## 任务 1：先固定可执行的行为契约

**修改：** `tests/strategy_logic.py`、`tests/test_strategy_logic.py`。**新建：** `tests/test_basket_mode3.py`。

- [ ] 扩展 `basket_directions` 接受 `(1, 2, 3)`；模式 2/3 都返回两个方向。`plan_initial_basket_launch` 中决定需要对端 ID、构造 opposite 的条件由 `==2` 改为 `in (2,3)`。非法值测试改成 `[-1,0,4]`，增加 3 的 BUY/SELL 场景。以下是明确的预期：

```python
import pytest
import strategy_logic


@pytest.mark.parametrize("direction", list(strategy_logic.Direction))
def test_mode3_initial_entry_still_has_two_opposite_baskets(direction):
    launch, missing = strategy_logic.plan_initial_basket_launch(
        event_id=7, primary_group_id=1, opposite_group_id=2,
        direction=direction, basket_count=3, lots=0.03,
        stop_points=500, take_profit_points=700,
    )
    assert launch.opposite is not None
    assert len(strategy_logic.basket_directions(direction, 3)) == 2
    assert launch.primary.direction != launch.opposite.direction
    assert launch.primary.lots == launch.opposite.lots == 0.03
    assert [leg.group_id for leg in missing] == [1]
```

- [ ] 在 `strategy_logic.py` 增加以下纯规则函数。此函数只提供资格与方向/手数契约，不代替 MQL 请求恢复和回放测试。

```python
def mode3_companion_action(*, mode, peer_state, primary_confirmed,
                           primary_alive, protected, source_stage_matches,
                           event_consumed, reset, child_status,
                           actual_direction, actual_first_lots):
    if mode != 3 or reset or event_consumed:
        return ("none", None, 0.0)
    if not primary_alive or not source_stage_matches:
        return ("cancel", None, 0.0)
    if peer_state == "unknown" or not primary_confirmed or not protected:
        return ("wait", None, 0.0)
    if peer_state != "ended":
        return ("none", None, 0.0)
    if child_status == "confirmed":
        return ("adopt", None, 0.0)
    if child_status in ("in_flight", "unknown", "partial"):
        return ("reconcile", None, 0.0)
    if child_status != "absent":
        return ("none", None, 0.0)
    if actual_direction not in (Direction.BUY, Direction.SELL):
        raise ValueError("invalid actual first-order direction")
    if not math.isfinite(actual_first_lots) or actual_first_lots <= 0:
        raise ValueError("invalid actual first-order volume")
    opposite = Direction.SELL if actual_direction is Direction.BUY else Direction.BUY
    return ("create", opposite, actual_first_lots)
```

- [ ] 参数化测试以下决策矩阵，失败信息中带场景名。把“对端是否在止损发生批次结束”提前转换为 `peer_state`，不能用当前批次的状态回填更早事件。

| mode | 对端 | 来源 | child | 预期 |
| --- | --- | --- | --- | --- |
| 1 或 2 | ended | 已确认且有保护 | absent | none |
| 3 | active | 已确认且有保护 | absent | none |
| 3 | ended | 尚未成交 | absent | wait |
| 3 | unknown | 已确认 | absent | wait |
| 3 | ended | 已确认但无保护 | absent | wait |
| 3 | ended | BUY 0.03、有效 | absent | create SELL 0.03 |
| 3 | ended | SELL 0.07、有效 | absent | create BUY 0.07 |
| 3 | ended | 有效 | in_flight / unknown / partial | reconcile |
| 3 | ended | 有效 | confirmed | adopt |
| 3 | ended | 已终止或阶段已变 | absent | cancel |
| 3 | ended | 有效、事件已消费或 reset | absent | none |

- [ ] 在添加实现前先运行新增测试确认因缺失新接口失败；增加实现后运行 `uv run --with pytest -- python -m pytest tests/test_basket_mode3.py tests/test_strategy_logic.py -q`。不要通过放宽旧 XAU 断言让该产品看起来支持 3。

## 任务 2：输入校验与首次路由

**修改：** 四个目标源码、`tests/test_basket_mode3.py`、既有相关源契约。

- [ ] 四个目标把输入注释明确为：`[开单]1=单篮子，2=反向双篮子，3=止损续配双篮子`；参数名、类型、默认 1、原顺序保持。增加或复用局部函数：

```cpp
bool IsPairedBasketMode()
  {
   return 篮子数量 == 2 || 篮子数量 == 3;
  }
```

- [ ] 将初始化有效值条件改为 `篮子数量 != 1 && 篮子数量 != 2 && 篮子数量 != 3`。MT5 将对冲账户条件扩为 `IsPairedBasketMode()`；错误提示同时覆盖 2/3。恢复出的模式 3 family 也校验对冲条件。
- [ ] 逐一核对 `ManageBoxBreakoutEntry`、`Manage` 普通首单/各距离模式、K 线 once 的 OCO、`MultiTryOpenCandleGroup`、`ProcessInitialPendingFillEvent` 和 `OnTick`。在“启动/管理双篮子”的分支采用 `IsPairedBasketMode()`；不要全局替换所有数值 2。
- [ ] 保留活动组阻止新配对的条件：`if(IsPairedBasketMode() && MultiHasActiveGroups()) return false;`。以后任务 6 再把未完成 family 也纳入占用判定；K 线 once、repeat 和多组分支都需覆盖。
- [ ] 入口和对冲校验的源契约测试按四目标更新。旧 XAU 的校验仍为 1/2；测试以参数化的 expected counts 区分，不删除其覆盖。
- [ ] 运行 `uv run --with pytest -- python -m pytest tests/test_basket_mode3.py tests/test_strategy_logic.py tests/test_ea_profile_contract.py tests/test_entry_retry_policy.py -q`。

## 任务 3：持久配对记录与恢复

**修改：** 四个目标源码、`tests/test_basket_mode3.py`。

- [ ] 在 `MultiGroupState` 增加技术方案 4.1 的三个字段；在 reset/save/load/change/delete 五处完整覆盖。键采用短后缀 `.bmode/.bfam/.stopseq`。读取先判断存在，旧记录默认 0，不从当前输入补写 3。
- [ ] 在组结构后增加完整的 family/事件结构和数组。下列字段是最少集合，私有实现不得以旧 `pair_peer_id` 替代永久归属：

```cpp
enum BasketRenewalPhase
  {
   R3_IDLE=0, R3_STOP_RECORDED=1, R3_PRIMARY_CONFIRMED=2,
   R3_NO_RENEWAL=3, R3_CHILD_RESERVED=4, R3_CHILD_IN_FLIGHT=5,
   R3_CHILD_PARTIAL=6, R3_PAIRED=7, R3_FAILED=8, R3_CANCELED=9
  };
enum BasketMemberStatus { R3_MEMBER_UNKNOWN=0, R3_MEMBER_RUNNING=1, R3_MEMBER_FINISHED=2 };
struct BasketFamilyState
  {
   int version;
   int journal_serial;
   int family_id;
   int mode_at_start;
   int pair_generation;
   int first_id;
   int second_id;
   int first_status;
   int second_status;
   int first_finish_batch;
   int second_finish_batch;
   int event_generation;
   int source_id;
   int source_stop_sequence;
   int event_batch;
   int old_peer_id;
   int peer_status_at_event;
   int old_cycle_index;
   int target_cycle_index;
   int old_reversal_count;
   int target_reversal_count;
   double old_cumulative_loss_lots;
   double target_cumulative_loss_lots;
   int target_direction;
   double target_lots;
   int stop_points;
   int take_profit_points;
   int cycle_mode;
   double confirmed_first_lots;
   int child_id;
   int phase;
   int failure_code;
  };
```

- [ ] 为该结构实现私有的索引查找、字段读写、双槽提交与恢复；共同规则是写入每项都检查成功，valid 最后写且 flush，恢复只读完整有效版本。为连续全局变量写入的每个断点注入一次失败/重启，验证恢复旧有效版本或进入未知，不能凭半份记录发 C。
- [ ] 新组 ID 在发送前与 family child reservation 一起持久化；恢复时把 `g_multi_next_id` 提升到所有有效 family 预留 ID 之外，避免 child ID 重用。保存的批次计数跨重启单调，不从 0 与旧批次碰撞。
- [ ] 增加私有的管理批次开始函数，在两种组管理循环开头先对账并递增批次；批次号保存于同一作用域的 `.r3.batch` 短键，恢复时取该键和所有有效 family 批次的最大值再递增。更新不完整时不声称对端与止损属于同批；计数溢出时只暂停新补开，继续保护已有持仓。
- [ ] 实现 `BasketRenewalLoad`，在 `MultiLoadGroups` 之后、任何交易事件回调可开新仓之前调用。校验 family 记录与组字段互相指认；损坏、缺失、不同作用域或版本未知时停止该 family 的补开，继续已有持仓管理。
- [ ] 实现 `BasketRenewalRecordFinished`：检查该组持仓/挂单/未决请求/换单目标确实为空，先写结束状态，再允许移除组。检查 `MultiRemoveGroup/MultiDeleteState` 每个调用点；写失败保留待收尾组，不能删掉唯一结束证据。
- [ ] 实现 `BasketRenewalCancelAll`：在无资金重置、显式全局 reset、`MultiClearAll` 清理前取消意图并持久化；把所有旧 child 已成交暴露交回原清理过程，不能先删除身份再清仓。
- [ ] 扩展 `MultiStateChanged` 包含新增字段；所有改动先标 dirty。记录保存失败不允许补开，也不得因 false 返回而跳过已有仓位所需的保护。

**事件恢复的断言：** 同一个 `(family,generation,source,stopseq)` 无论装载多少次只对应一个 child ID；原/目标循环推进和亏损累计只采用一个版本。

## 任务 4：登记首次配对，保留 OCO

**修改：** 四个目标源码的首次配对与 OCO 路径、`tests/test_basket_mode3.py`。

- [ ] 实现 `BasketRenewalRegisterPair(mode,family_id,first_id,second_id)`。mode!=3 无补开记录；mode3 初始化 generation=0、两个成员、无 stop 事件，在发送首次订单前提交身份；两个组字段标记出生模式和 family。
- [ ] 在 `StartResolvedMultiPair/MultiStartResolvedPair` 已分配两个 group ID 后、首次发送前调用登记。任一登记失败，不发这次新模式首单，原始信号消费/失败策略按现有入口处理。
- [ ] K 线 once 先登记包含两个候选 group ID 的 family，但首对状态保持启动中。OCO 一侧成交、另一侧撤销并转成反向市场首单后才算首次配对就绪；未完成初始第二腿不能被判定为“有篮子结束”。
- [ ] OCO 两侧都抢先成交时收养为首次两个篮子，记录两成员已启动；禁止再发第三个初始订单。已有部分失败、双挂单回滚和 timer/transaction 回调逻辑保留。
- [ ] 新增首次入口源契约，核对每个受影响距离模式仍使用原已解析方向/距离/手数；登记函数不重新计算指标，也不改变原信号 ID。
- [ ] 运行聚焦测试：`uv run --with pytest -- python -m pytest tests/test_basket_mode3.py tests/test_ea_profile_contract.py tests/test_average_double_candle.py tests/test_bollinger_expansion.py -q`。

## 任务 5：三条止损路径接入同一事件

**修改：** 四个目标的三条止损路径与 transition 恢复路径、`tests/test_basket_mode3.py`。

- [ ] 实现技术方案给出的 `BasketRenewalPrepareStop` 与 `BasketRenewalConfirmFirstOrder`。前者记录旧/新阶段和唯一 stopseq；重复调用识别同一事件，不增加第二次序号。后者核对目标阶段、目标量和保护，冻结实际首单量，不创建组。
- [ ] 在 `MultiHandleReverseFill` 中先识别 filled ticket，执行原上限/清理规则；允许提升时登记事件，在原晋级字段更新后持久化模式 3 状态。新阶段保护核对后确认首单，放在下一阶段网格/反手挂单创建之前。已成交票据不得因日志写失败重发。
- [ ] 在 `MultiRecoverFlatGroupAfterBrokerStop` 中保留原 next lots 和 `BuildReversalLotPlan`：原风控允许后登记、保存目标阶段及 `transition_target_lots`，再调用原 `MultiOpenMarket`。失败恢复复用同一事件；成交且保护完成后确认。
- [ ] 在 `MultiManageGroup` 的主动止损分支同样接入。原挂单撤销或旧持仓关闭失败时，事件停在清理阶段；不得重复增加亏损累计、反手次数或 stopseq。不要把三条路径简单贴上三个互不关联的发单代码块。
- [ ] 在 `transition_target_lots` 重试与请求可见性恢复分支完成后调用确认入口，传入原记录中的 stopseq；首次入场 transition 没有止损事件时不能凭首单成交生成补开。
- [ ] 确认首单使用本次换单全部拆单的合计总量、同方向且与冻结目标相符，误差为当前 lot step 的半步；不是止损前总手数、默认 `首单手数`，也不是包含后续网格的总量。确认后立即持久化。
- [ ] `PrepareStop/ConfirmFirstOrder` 的记录失败只取消/暂停新 C 的授权，不把必需的原反手或已有持仓保护跳过。模式3 原阶段持久化与请求核对无法确认时，按未决隔离管理已有风险；不能重新开来源单来试探。
- [ ] 保留原循环函数、三种止损首单类型、原 grid lot multiplier、动态止损和止盈移动代码。MT4 全局反手上限和 MT5 原组内上限均只执行原终止逻辑，不开 C。
- [ ] 新测试覆盖 3 条路径 × BUY/SELL × 3 种手数类型，并增加“循环下一阶段仍同方向”、网格止损、目标拆分及失败补量；所有路径对同一事件给出一致补开资格。

**插入点的顺序契约：**

```text
原止损事实/filled ticket确认
→ 原反手上限、超量和重置规则
→ PrepareStop（只登记，一次）
→ 原清理与阶段推进（模式3保存目标阶段）
→ 原市价发送/filled ticket提升/未决对账
→ 实际换单首单总量确认
→ 原保护设置与核对
→ ConfirmFirstOrder（冻结首单量）
→ 原新阶段后续管理
```

## 任务 6：遍历后补开、去重与晚到成交

**修改：** 四个目标源码、`tests/test_basket_mode3.py`。

- [ ] 实现 `BasketRenewalProcess`。先处理 reset，再对账本批结束事实及 stop 事件；对端同批结束可满足本事件，对端以后才结束不追溯；对端未知则等对账。未满足且事实已确定的事件记为 NO_RENEWAL，不能每 tick 重审成新机会。
- [ ] 在 MT4 两种管理循环、MT5 共用管理循环的旧组遍历完成后调用 process；安排在 `closed_group` 的提前 return 前，但不越过 `g_reset_pending`。任何 `ArrayResize/RemoveGroup` 只发生在退出旧组引用后，以 ID 重新定位；不把引用跨函数保存到下一 tick。
- [ ] 为新 C 只分配一个组，禁止调用 `StartResolvedMultiPair/MultiStartResolvedPair`，否则会重复创建来源 B。新 C 初始字段为：出生模式 3、相同 family、新 ID、反向实际方向、源锁定 SL/TP/循环模式、cycle_index=0、reversal_count=0、cumulative_loss_lots=0、previous_grid_lots=0、双向网格状态/缓存为空、transition target=冻结首单总量。MT5 同时标记 `dual_basket_member=true`。
- [ ] 对 family 中处于 CHILD_RESERVED/IN_FLIGHT/PARTIAL 的 child 增加私有代管判断：在 `MultiManageGroup` 原请求暴露核对之后、通用 `transition_target_lots` 自动发单之前，核对并保护已有 child，随后返回等待遍历后 process。此阶段唯一的缺口发送者是 process；不能让通用恢复代码绕过 source stopseq 检查自动开仓。配对完成后解除代管。
- [ ] 保存 child reservation 后使用原 `MultiOpenMarket` 与现有组注释提交。为本次 child 保留请求前暴露基线及请求状态；若返回失败但结果未明，先对账，不能把它当作 absent。兼容入口与核心的实现保持各自已有保护，模式3新增的必要保护只作用于此分支。
- [ ] 每次重试使用同一 child ID，重新核对 source stopseq/阶段和 child 持仓/订单/历史。临时错误按已有退避，永久错误记 FAILED；保证金不足进入原全局清理。只有确认拒绝且无暴露时才能重发。
- [ ] 对部分成交，补冻结目标减已确认首单量；单笔拆单使用原 lot plan，不补全额。child 首单未完成时暂停其网格派生；如 child 已超额、身份冲突或无法合法完成等量，记失败并保留管理，不宣称配对成功。
- [ ] 来源结束/阶段变化时取消尚未成交的意图，撤销可撤销请求；已成交 child 及晚到成交按原 child ID 收养、保护，不追加另一个 ID。该未决位置在对账完成前仍占用 family 的第二位置。取消后收养用实际量设置 child 的首单字段、清零剩余目标并交回原组管理；family 登记新的实际成员，不标记为等量配对成功。
- [ ] 若旧 child 尚未对账、来源已经再次止损，不覆盖旧事件的 child ID 和请求状态；来源继续原止损处理，本次不新建另一个 child。旧事件明确终结后只接受未来新的合格止损事件，不追补历史；永久失败但确认无暴露的事件也适用此规则。
- [ ] C 等量且保护通过后提交 PAIRED：成员更新为 B/C，代次+1，stopseq 保留，历史事件已消费；不能因为删除 A 丢掉防重记录。更新过程中任何重启都应恢复到同一 child。
- [ ] 管理派发条件纳入“存在待处理模式3记录”；所有相关订单暂时不可见时仍运行恢复管理，不掉回普通 `Manage` 开新一对。新初始信号占用判定纳入未决 family。模式 1/2 没有 family 时分派路径与原先一致。
- [ ] 加入结构化、限频日志，字段至少为 family、generation、source、stopseq、child、phase、direction、target、confirmed、broker code；日志不得代替实际成交事实。默认只记录阶段改变和必要失败，不新增每 tick 噪声。

**必须通过的恢复和顺序测试：**

| 情形 | 必须证明的结果 |
| --- | --- |
| A/B 管理顺序颠倒，同批 A TP+B SL | 同一个事件键、同一个 C、相同方向与量 |
| A 更晚批次才结束 | 不为早先 B 的换单补 C |
| child ID 保存后、发送前重启 | 使用原 ID，仅发送一次 |
| 请求已接受、响应丢失后重启 | 收养已有成交，不重发全额 |
| C 部分成交后重启 | 仅补差额，未完成不放行网格 |
| C 已成交、PAIRED 尚未提交重启 | 查到同一 C，提交原事件，不发 D |
| B 在 C 等待时再次止损 | 旧意图失效，晚到成交仍归原 child，占用位置 |
| 两篮子均存续，任一止损 | 仍只有两个策略篮子位置 |
| A 结束，B 无止损 | 没有新首单 |
| B/C 中 C 结束，B 下次止损 | 新代次恰好一个 D，B 进度不重置 |
| 全局 reset/无资金清理后重启 | 旧意图不复活 |
| 参数 3→1/2、旧 1/2→3 | 原 mode3 family 继续；旧组不追补 |
| 其他 Magic/profile/品种有订单 | 不参与本 family 状态或手数 |

## 任务 7：成交验证、回归与编译

**新建：** 回放脚本、成交审计器、审计器样本测试。**修改：** 两份用户文档。**输出：** 验证目录与编译字节码。

- [ ] 编写 `scripts/audit-basket-mode3-replay.py`，输入标准化审计 JSON，结构如下。JSON 由回放脚本从真实组日志及成交历史提取；审计器不能只检查“RENEWAL 成功”日志字符串。

```json
{
  "mode": 3,
  "volume_step": 0.01,
  "events": [
    {"family": 1, "generation": 0, "source": 2, "stopseq": 1,
     "child": 3, "peer_finished_in_event_batch": true,
     "primary_direction": "buy", "primary_first_deals": [0.02, 0.01],
     "child_direction": "sell", "child_first_deals": [0.03],
     "primary_cycle_after": 1, "child_cycle_at_start": 0,
     "child_reversals_at_start": 0, "child_loss_lots_at_start": 0.0,
     "primary_protected": true, "child_protected": true}
  ],
  "unresolved_events": []
}
```

- [ ] 审计规则：模式2 events 为空；模式3每唯一事件键只有一个 child，child ID 不跨事件复用；来源和 child 成交量相等、方向相反，peer事实满足；child 从独立首单阶段开始；保护完整；未决事件明确列出。允许多笔拆单，但不能把网格成交纳入 first deals。对重复事件、错误手数、同方向、缺保护、child继承亏损、缺少首单成交记录分别添加失败样本；合法拆单和无补开模式2应通过。
- [ ] 审计器提供 `--input <JSON> --output <JSON>`；成功退出0并输出 `passed/events_checked/unresolved_count`，错误退出非0并指出事件键。对“无预期事件覆盖”的模式3场景同样失败；不得用空 events 宣称通过。未决不算满足等量场景，应由场景清单注明这是专门的失败恢复测试还是尚缺验证。
- [ ] 编写 `scripts/test-basket-mode3-mt5.ps1`，提供参数 `SourceRoot/TerminalRoot/OutputRoot/TimeoutSeconds`，复用现有隔离脚本的 portable、隐藏启动和超时管理；只停止本脚本启动的进程，不操作用户运行终端。验证测试账户为 hedging。
- [ ] 先运行固定距离 `SL=TP=500、首单0.01、网格0、最大反手>=3` 的模式2/3对照，再增加网格、不同 lot type 与循环模式、K线 once OCO。若原行情不能稳定覆盖所有路径，使用隔离测试器自定义品种及预设 ticks；不得以无事件回测当通过。用 tester 专用探针触发超时/部分成交/重启断点，探针在测试脚本或验证目录中，不把测试输入发布到正式参数。
- [ ] 参考行情序列：100.00 附近首次配对；上涨到 A 多篮子 TP/B 空篮子 SL 后，B 现有换单为买、C 应卖且等量；再向相反方向推进，使 C 结束后 B 或其存续伙伴再次止损，验证第二代补开。按测试品种 point、spread 和真实 SL/TP 校验价格，不硬编码市场品种报价位数。
- [ ] MT5 交易探针导出订单/成交票据、group comment、首单/网格角色、实际成交量与保护、阶段日志。隔离回放用例还需覆盖反手挂单先成交、broker先平仓、主动检测三种分支；不允许用 Python 模型代替未触发的 MQL 分支。MT4 能运行测试器时做相同场景，否则记录缺失的平台运行证据。
- [ ] 更新 README 与 HTML：值1/2/3、0.01→0.03 示例、仅特定止损事件触发、同批交叉规则、参数对新/旧组影响、MT5对冲、两请求非原子。无需新增报表或修改用户现有 xlsx 参数表。
- [ ] 运行一次相关测试，失败修复后执行完整测试：

```powershell
uv run --with pytest -- python -m pytest tests/test_basket_mode3.py tests/test_basket_mode3_replay.py tests/test_strategy_logic.py tests/test_entry_retry_policy.py tests/test_ea_profile_contract.py tests/test_distance_mode_build.py tests/test_build_workflow.py -q
uv run --with pytest -- python -m pytest -q
```

- [ ] 自动测试通过后按项目指令编译，分别保存输出。不得只编一个平台，也不得因为核心能编译就省略兼容入口。

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\compile-mql.ps1 -Target Both
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\compile-mql.ps1 -Target Both -Profile All
```

- [ ] 验证 22 个目标均为 0 errors，字节码存在、非空且时间刷新；记录 warnings 数、源码/字节码路径及哈希、MetaEditor 日志路径。发现编译器未找到就用 `-MetaEditor4Path/-MetaEditor5Path` 或对应环境变量解决，不跳过。
- [ ] 再执行隔离原生回放和成交审计，保存 `results.json` 与场景覆盖。修复后按变更重跑必要测试及两个编译命令；没有新变更/失败则不反复跑全套。

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\test-basket-mode3-mt5.ps1 -OutputRoot .\validation\basket-mode3-2026-10-20
uv run -- python .\scripts\audit-basket-mode3-replay.py --input .\validation\basket-mode3-2026-10-20\mode3-audit-input.json --output .\validation\basket-mode3-2026-10-20\mode3-audit-result.json
```

预期：回放各场景成功退出并有真实交易证据；审计 `passed=true`，至少覆盖一个首次配对和两个有效续配事件。特殊失败场景在独立审计文件列出，不混入正常等量成功统计。
- [ ] 用任务0的基线检查功能 diff，不以 HEAD 的大 diff 判断范围。确认未更改手数公式、循环序列、距离模式、原模式1/2行为、XAU、指标或已有用户改动。对新增状态检查所有 save/load/reset/delete/change/cleanup 对称覆盖。
- [ ] 提交时只暂存本轮增量。由于四个源码原本已有改动，禁止 `git add .` 或整文件暂存混入基线；无法安全分离时保留工作树并报告，不强制制造干净提交。文档与全新测试文件可以单独明确暂存。
- [ ] 交付说明包含规则、测试结果、原生回放覆盖和限制、22个产物及警告、变更文件。需要分发包时使用现有打包脚本，新增模式不需要更改其目录结构；默认不部署到运行终端、不自动发布。

## 完成门槛

- [ ] 技术方案的需求映射表每行有实现和证据，所有未完成事件均可解释，三条止损路径均覆盖。
- [ ] 1/2 回归不变；3 正确配对、只补一次、不会因为全局订单数量或参数重载误补。
- [ ] C 的首单量严格来自对应换单首单成交总量；B 原进度保持，C 从首单开始。
- [ ] 未决、部分成交、重启及全局重置不会重复发单、丢弃已有风险或复活旧意图。
- [ ] 两个兼容入口和20个固定入口测试/编译证据齐全；任何缺失运行验证已明确记录。

本计划结束于可交付功能与验证证据；方案编写阶段不把任务勾选为已实现，不把文档检查当成交易功能测试。
