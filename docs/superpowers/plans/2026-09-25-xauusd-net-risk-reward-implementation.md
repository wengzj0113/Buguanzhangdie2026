# XAUUSD 净盈亏比与成交成本控制 Implementation Plan（待审阅）

> **For agentic workers:** Implement task by task in an isolated worktree. Checkboxes track progress. Do not start implementation until the user approves the design and this plan.

**Goal:** 在 MT4、MT5 现有订单组流程中，按实际成交价格、费用和滑点预算约束整轮预计净盈亏比；成本超标时不新增风险，同时保留服务器止损。

**Architecture:** 以可独立测试的成本计算模型定义 `cycle` 现金账本、报价门槛和 TP 求解；在两份 MQL 源码中分别实现平台适配。新增风险订单在成本模式下由持久化虚拟触发器驱动，已持仓的服务器保护仍由现有保护路径管理。旧模式保持原行为，模式切换只在完全空仓且无旧挂单时生效。

**Tech Stack:** MQL4、MQL5、Python 3、pytest、MetaEditor、MT5 Strategy Tester 与目标经纪商 XAUUSD Tick 数据。

**Design:** [XAUUSD 实际净盈亏比与成交成本控制设计](../specs/2026-09-25-xauusd-net-risk-reward-design.md)

---

## 文件职责与实施前准备

| 文件 | 职责 |
| --- | --- |
| `tests/strategy_logic.py` | 纯计算参考模型：现金账本、报价门槛、TP 求解、状态决策；不执行交易 |
| `tests/test_strategy_logic.py` | 数值与状态场景测试，并检查 MT4/MT5 接入点 |
| `NoMatterRiseFall_MT5.mq5` | MT5 参数/UI、成交历史、状态持久化、报价监控、下单和保护适配 |
| `NoMatterRiseFall_MT4.mq4` | MT4 同一策略规则的平台适配，明确无硬性限价保证的边界 |
| `README.md`、`EA软件使用手册.html` | 参数语义、运行限制及成本模式说明 |
| `mt5_auto_test_*.ini` | 现有自动测试配置；仅在需要新增模拟场景时新增配置，不改旧基线 |

- [ ] **准备 1：锁定基线。** 在实施用独立 worktree 中记录 `git rev-parse HEAD`、`git status --short`、MT4/MT5 源码与 EX4/EX5 哈希；检查当前分支的用户改动并保留。验证 Python/pytest 和 MetaEditor 的真实路径，不能使用 WindowsApps 的空 Python 别名作为测试结果。
- [ ] **准备 2：复核模式与账户能力。** 记录目标 XAUUSD 的 `_Point`、tick size、合约大小、最小手数及步长、执行模式、是否支持 Stop Limit、账户是净持仓还是对冲，以及经纪商佣金何时记账。MT5 成本模式仅在对冲账户启用；缺少经纪商数据时可以开发与回测，但不能确定实盘阈值。
- [ ] **准备 3：保存旧版基线。** 用现有测试器配置保留一份旧版回测结果，含交易次数、每轮现金结果、最大回撤及最长连续止损；回测输入和历史数据版本要固定，供末尾对比。

## Task 1：净结果和 TP 求解纯模型

**Files:** `tests/strategy_logic.py`、`tests/test_strategy_logic.py`

- [ ] **Step 1：先写失败的数值测试。** 覆盖买/卖对称、实际开仓价偏移、已发生负佣金、预计平仓费、止损滑点预算、止盈价 tick 向有利方向取整及 `P<=0` / `L>=0` 的不可行结果。测试公式固定为：

```text
cycle_tp_cash = realized_cycle_net + sum(position_profit(actual_or_worst_entry, tp))
                + estimated_not_yet_paid_fees - adverse_tp_slippage_cash
cycle_sl_cash = realized_cycle_net + sum(position_profit(actual_or_worst_entry, sl))
                + estimated_not_yet_paid_fees - adverse_sl_slippage_cash
feasible = cycle_tp_cash > 0 and (
    cycle_sl_cash >= 0 or cycle_tp_cash >= target_R * abs(cycle_sl_cash))
```

- [ ] **Step 2：运行定向测试，确认失败。** 命令：`python -m pytest tests/test_strategy_logic.py -k "net_rr or tp_solver" -q`；预期为新增函数尚不存在导致失败。
- [ ] **Step 3：实现纯函数。** 定义 `CashLeg(direction, volume, entry_price)`、`CycleCashState(realized_cycle_net, estimated_not_yet_paid_fees)`、`NetTargetDecision(feasible, tp_price, tp_cash, sl_cash, reason)`；实现 `estimate_cycle_outcomes(...)` 和 `solve_net_target_tp(...)`。求解器先验算策略 TP，再按 tick 二分/步进至第一个满足净 RR 的价格，超过点数或比例补偿上限返回 `TARGET_INFEASIBLE`。
- [ ] **Step 4：补价格示例测试。** 500 点 SL、买卖方向对称、费用预算非零时求得的 TP 必须严格大于无费用目标；零费用与零滑点时恢复价格距离模型的结果。已入账费用使用平台返回的有符号值计入 `realized_cycle_net`，不再次扣减同一笔费用。
- [ ] **Step 5：运行定向和全量 Python 测试。** 两条命令分别为 `python -m pytest tests/test_strategy_logic.py -k "net_rr or tp_solver" -q`、`python -m pytest -q`；均须无失败后进入下一任务。

## Task 2：报价门槛与触发器决策模型

**Files:** `tests/strategy_logic.py`、`tests/test_strategy_logic.py`

- [ ] **Step 1：先写失败测试。** 覆盖正常/过期报价、超绝对点差、超止损占比、买价超上限、卖价低于下限、恢复确认、防同一 K 线双向触发和点差恢复后不执行过期反手。
- [ ] **Step 2：实现 `QuoteGateDecision`。** 输入 tick 时间、Bid、Ask、止损点数、绝对点差上限、相对上限、最差允许开仓价；输出 `ALLOW` 或精确原因码 `STALE_QUOTE`、`SPREAD_ABSOLUTE`、`SPREAD_RELATIVE`、`ENTRY_PRICE_LIMIT`。无有效报价时一律关闭门槛。
- [ ] **Step 3：实现 `TriggerDecision`。** 每个触发器记录 `cycle_id`、`group_id`、类型、方向、价位、所属 K 线、生命周期和是否已消费。双向首单同一报价同时触发时两个都不发送；单次 K 线模式已消费后不再重建。止损后的反手仅在本次止损事件及报价门槛均有效时触发，失败即结束该轮。
- [ ] **Step 4：运行定向和全量测试。** `python -m pytest tests/test_strategy_logic.py -k "quote_gate or trigger_decision" -q`，再 `python -m pytest -q`。

## Task 3：MT5 参数、成交账本与持久化

**Files:** `NoMatterRiseFall_MT5.mq5` 的参数/`GuiConfig`/`ValidateGuiConfig`/`ApplyGuiConfig`、`SaveState`/`LoadState`、`MultiGroupState`/`MultiSaveGroup`/`MultiLoadGroups`、`OnTradeTransaction`；`tests/test_strategy_logic.py`

- [ ] **Step 1：新增成本模式参数和 GUI 字段。** 加入设计文档列出的目标 RR、点差、滑点、佣金、TP 补偿、风险和报价时效参数；目标 RR 默认“跟随该轮原止盈/止损距离之比”，显式正数可覆盖。成本模式默认关闭。启用时缺少任何关键预算则配置无效。已活动的旧版 cycle 不能被热切换到新模式。
- [ ] **Step 2：建立成交账本。** 成交事件按 deal ticket 去重，用 deal/order/position 映射到 cycle 和 group，记录实际价、手数、`DEAL_PROFIT`、`DEAL_COMMISSION`、`DEAL_FEE`、`DEAL_SWAP`。未来尚未入账佣金用预算保留；实际佣金到账后替换预算，不重复计数。无法归属到具体订单组的账户级佣金扣款单独报告，不把预算清零。反手组已实现亏损保持在同一 cycle。
- [ ] **Step 3：加入恢复规则。** 持久化 cycle 起点、group 关联、触发器和冻结原因；启动时先按历史成交重建账本，再允许交易。若 broker 修改注释、历史不足或账本无法归属，则保持仓位 SL/TP，并禁止新增风险，日志输出 `COST_LEDGER_INCOMPLETE`。
- [ ] **Step 4：测试并编译 MT5。** 测试正常佣金、延迟佣金、部分成交、重复事件、重启、多组独立账本；运行定向 pytest。用隔离 MetaEditor 编译，检查编译日志 `0 error(s)`、`0 warning(s)`；记录实际编译器路径和命令。

## Task 4：MT5 单组成本门槛、TP 和保护

**Files:** `NoMatterRiseFall_MT5.mq5` 的 `Manage`、`SendMarketLeg`、`PlaceInitialPendingPair`、`EnsureGridPending`、`HandleGridFill`、`Transition`、`GroupStopPrice`、`GroupTakeProfitPrice`、`SetGroupStops`、`StopsVerified`；`tests/test_strategy_logic.py`

- [ ] **Step 1：引入统一的 `EvaluateNewExposure`。** 首单、每一格逆势/顺势网格、反手和失败补单在发送前调用同一门槛；使用候选最差成交价、组内现有仓位、已实现 cycle 结果、实际 SL 和费用预算求解。风险或目标不可行时返回原因码，不能继续走 `OrderSend`。
- [ ] **Step 2：实现持久化虚拟触发器。** 成本模式下不建立新的长期有效开仓挂单；原有价格计算仅生成触发器。已有服务器旧挂单必须在 flat 切换条件中清空，不能与虚拟触发器并存。`OnTick` 负责价格触发和开仓；`OnTimer` 负责报价过期、状态诊断与恢复，不以旧 Tick 价格下单。
- [ ] **Step 3：保证保护顺序。** 允许时在市价请求中提交有效初始 SL/TP；成交后以实际价格及 broker 约束重新求解，修改并回读所有仓位保护。保护失败时不发送任何跟进网格/反手；实际 SL 向外调整导致风险超限时冻结并执行既有清理保护流程。
- [ ] **Step 4：接入两种止盈移动模式。** 每次 `g_group_last_entry` 或线性极值变化，先算原策略 TP，再算成本目标 TP；买组取更高值、卖组取更低值。超过补偿上限冻结新增风险，现有 SL 不扩大。
- [ ] **Step 5：接入反手失败决策。** 旧组经纪商 SL 或 EA 市价平仓后，若点差/滑点/净 RR 不合格，记录完整 cycle 亏损并结束该轮；不得保留延迟反手以便稍后追价。已发送但未确认请求保持当前请求锁和重启幂等逻辑。
- [ ] **Step 6：运行状态测试与 MT5 编译。** 覆盖双向首单、网格连续触发、止损与反手同 tick、TP 修改拒绝、被动 SL 先于 EA Tick、成交超预算及部分成交；编译日志必须零错误、零警告。

## Task 5：MT5 多组并行与账户总风险

**Files:** `NoMatterRiseFall_MT5.mq5` 的 `MultiGroupState`、`MultiManageGroup`、`MultiTryOpenCandleGroup`、`MultiPlaceGridPending`、`MultiPlaceReversePending`、`MultiSetStops`、`ManageMultipleCandleGroups`；`tests/strategy_logic.py`、`tests/test_strategy_logic.py`

- [ ] **Step 1：多组复用同一规则。** 每组保留 cycle 现金账本与触发器；一个组的费用、SL/TP 和 TP 补偿不得用于另一个组。
- [ ] **Step 2：加账户总风险上限。** 拟新增一组或一格时，用所有活跃组的现有仓位与可能成交触发器的保守止损损失之和检查权益比例；覆盖无网格、逐层逆势、顺势后回撤及两侧成交的情况。一个组触发风险上限不强制清理其他组，只阻止该笔新增风险。
- [ ] **Step 3：覆盖重启和清组。** 多组数组删除、组 ID 续增、历史成交回放以及单组资金不足清理后，不能复用旧 cycle ID 或重复记佣金。
- [ ] **Step 4：运行多组测试与编译。** `python -m pytest tests/test_strategy_logic.py -k "multi or parallel or cost" -q` 后编译 MT5。

## Task 6：MT4 等价规则及平台差异

**Files:** `NoMatterRiseFall_MT4.mq4` 的参数/`OnInit`、状态保存、`Manage`、`SendMarketLeg`、`EnsureGridPending`、`Transition`、多组管理、`OnTimer`；`tests/test_strategy_logic.py`

- [ ] **Step 1：移植参数与纯计算公式。** MT4 与 MT5 对同一组实际价格、费用和配置返回相同的净 RR、TP tick 方向及原因码；金额换算按 MT4 合约/点值校验，不假设所有 XAUUSD 合约为 100 盎司。
- [ ] **Step 2：移植虚拟触发器和账本。** MT4 用订单 ticket、`OrderProfit`、`OrderCommission`、`OrderSwap` 及历史订单重建；多组按组 ID 隔离。先保护、再新增的顺序与 MT5 一致。
- [ ] **Step 3：明确成交价边界。** MT4 `OrderSend` 发送前检查 Ask/Bid 与允许最差价格，设置非零滑点预算，成交后立即读取实际价；经纪商忽略偏差或跳价导致超预算时冻结该 cycle 新增风险。不能把这一机制描述成 MT4 的硬限价保证。
- [ ] **Step 4：运行对称测试与编译。** 同一组输入分别检验 MT4/MT5 计划结果；检查 MT4 编译日志零错误，记录任何已存在警告及是否新增。

## Task 7：文档、历史回测与模拟验证

**Files:** `README.md`、`EA软件使用手册.html`、测试配置文件（若新增）、MT4/MT5 编译产物

- [ ] **Step 1：写明新参数与真实承诺。** 文档说明目标 RR 为预计值、止损滑点不可保证、虚拟开仓依赖终端在线、旧模式与成本模式的切换边界，以及点差不重复扣费。
- [ ] **Step 2：运行全部自动检查。** `python -m pytest -q`、`git diff --check`、MT4/MT5 完整编译。必须记录测试数量、编译器路径、日志结果和 EX4/EX5 哈希。
- [ ] **Step 3：固定数据做旧版对照。** 用同一 XAUUSD 经纪商真实 Bid/Ask Tick 数据、相同交易时段、合约及费用，对比旧版、新版补偿 0%/10%/20% 和点差占比 5%/8%/10%；保留一段未用于选参数的样本外数据。
- [ ] **Step 4：报告完整结果。** 报告每轮实际净 RR 分布、未达标比例、总净收益、最大回撤、交易次数、拒单/漏单率、实际滑点 95 分位、费用占比和保证金低点。样本外若仅靠大幅减少交易次数改善回撤，也要明确报告。
- [ ] **Step 5：模拟账户演练。** 至少验证断线/重启、换日扩点、双向 K 线触发、经纪商止损先成交、佣金延迟入账、多组并行和保护修改失败。记录每例日志及预期/实际状态。
- [ ] **Step 6：审阅最终差异。** 确认只修改本设计涉及文件、没有覆盖用户已有改动，编译产物与源码一致。未经用户对本计划及最终结果的后续指示，不部署到实盘账户。

## 阶段交付与停止条件

| 阶段 | 可交付结果 | 不满足时的停止条件 |
| --- | --- | --- |
| 模型（Task 1–2） | 现金净 RR、TP 求解和报价门槛可独立测试 | 买卖不对称、费用重复计算、边界价格错一 tick |
| MT5 单组（Task 3–4） | 成本模式可在模拟/测试器中运行；旧模式回归 | 任一未保护仓位仍允许新增风险 |
| MT5 多组（Task 5） | 独立账本与账户总风险限制 | 跨组误记费用或风险上限可被并行组绕过 |
| MT4 对齐（Task 6） | 相同策略结果与已披露的平台差异 | 把滑点参数误当作成交价保证 |
| 验证（Task 7） | 编译、测试、真实 Tick 对照及模拟记录 | 样本外净收益/风险没有可解释改善时不建议实盘启用 |

## 计划自审清单

- [ ] 设计中的每条入场路径、两种 TP、动态 SL、网格两侧、单组/多组、重启和费用晚到均能映射至上面的任务与测试。
- [ ] 新模式关闭时，旧版行为和现有参数语义没有改变。
- [ ] 任何不能保证的成交价、净盈亏比或止损结果均在文档与报告中明确表述。
