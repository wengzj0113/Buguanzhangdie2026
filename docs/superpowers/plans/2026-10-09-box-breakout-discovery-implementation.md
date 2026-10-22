# 箱体确认突破模式实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**目标：** 在 MT4 和 MT5 新增独立的箱体确认突破距离模式：从可配置的已收盘 K 线窗口确认并锁定箱体，突破确认后按既有方向映射开单，并将箱体宽度同时用作止损和止盈距离。

**架构：** 在现有距离模式枚举末尾追加新模式值 7，保留 0 至 6 的兼容性。Python 策略模型提供可单测的候选识别、触碰/往返计数和突破状态规则；MT4、MT5 分别读取本平台历史 K 线并实现相同状态流程。MT5 的输入参数、GuiConfig、参数页、校验和应用流程同步扩展。确认箱体状态在无仓等待突破期间持久化，订单组建立后沿用现有锁定距离逻辑。

**技术栈：** MQL4、MQL5、Python、pytest、MT5 图表面板。

---

## 实施范围与固定规则

- 新模式名称为“箱体确认突破”，枚举值追加为 `DISTANCE_BOX_BREAKOUT = 7`；既有 `DISTANCE_BOX_RANGE = 6` 及其 M1 时间箱体参数、行为完全不变。
- 默认识别周期为当前图表周期，观察窗口为最近 60 根已收盘 K 线；每根识别周期新 K 线只评估一次。
- 候选上沿/下沿为该窗口最高价/最低价。ATR 周期默认 14；触碰容差默认 `0.2 × ATR`。同一根 K 线若同时触及上下沿，视为歧义数据，不计入触碰或往返，避免一根长 K 线制造箱体确认。
- 触碰事件需与同侧上次事件至少间隔 3 根已收盘 K 线。触碰侧按 high/low 与冻结候选边界的容差距离判断。
- 上沿和下沿各自默认至少 2 次触碰；最少完整往返默认 2 次。完整往返定义为顺序触碰事件 `上沿→下沿→上沿` 或 `下沿→上沿→下沿`；相邻同侧事件不构成往返。
- 箱体宽度以整数 points 计算，默认允许 500 至 1000 点，含边界。最小/最大宽度是新参数，不复用旧模式的输入。
- 确认时锁定上沿、下沿、宽度和突破缓冲；突破缓冲默认 `0.2 × 确认时 ATR`。连续两根识别周期已收盘 K 线收在边界加/减缓冲之外才确认突破；收回箱体内会清零连续计数。
- 方向沿用“开单方式”：正向上破做多、下破做空；反向则相反。使用市价开首单，不创建双向突破挂单。
- 止损距离与止盈距离均为 `round((上沿-下沿)/Point)`。以首单实际成交价为基准，多单止损向下、止盈向上；空单相反。
- 箱体在确认后保持冻结，直到有效突破或过期。为避免无限期等待旧箱体，过期时间固定为确认后经过与“观察窗口K线数”相同数量的新 K 线；过期后清除该箱体并重新扫描。此规则不新增参数。
- 突破状态评估以识别周期的已收盘 K 线时间作为事件时间；MT5 首单信号去重、请求中状态和失败重试均使用第二根确认 K 线的时间/方向，不使用图表周期的当前 bar 时间。
- 新模式走 EA 现有普通首单流程：篮子数量为 1 时按现有单组流程开市价单；篮子数量为 2 时继续按现有 `MultiStartResolvedPair` 流程启动。它不使用“K线多组”并行触发逻辑，不增加图表画框、告警或双向突破挂单。已有网格、循环、止损切换和移动止盈照旧。
- 原有交易时段、首单点差限制、手数归一化、止损校验和资金不足恢复仍由既有首单流程执行；突破事件不得绕过这些保护。

## 文件职责

- `tests/strategy_logic.py`：纯 Python 箱体候选筛选、触碰事件、往返数、突破确认和模拟策略状态。
- `tests/test_strategy_logic.py`：算法边界、状态转换、方向映射、距离锁定及 MT4/MT5 源码契约测试。
- `NoMatterRiseFall_MT4.mq4`：MT4 输入、校验、历史数据读取、箱体/突破状态持久化、首单触发和距离锁定。
- `NoMatterRiseFall_MT5.mq5`：MT5 对应交易逻辑、ATR handle 生命周期、输入及 GUI 参数传递、GUI 显示/编辑/校验/应用和旧配置指纹迁移。
- `README.md`、`EA软件使用手册.html`：记录新模式规则、输入参数、默认值和现有箱体高度模式的区别。

## 任务 1：为箱体发现和突破状态写纯逻辑测试

**文件：**
- 修改：`tests/test_strategy_logic.py`

- [ ] **步骤 1：添加窗口和候选箱体测试**

只在 `tests/test_strategy_logic.py` 添加将调用新接口的失败测试，不实现生产逻辑或 Python 辅助函数。测试输入为按时间升序的已收盘 OHLC 元组，要求未来的 `find_confirmed_box(rates, config, point)` 使用最近 N 根计算上下沿、ATR、points 宽度、独立触碰和交替触碰序列。

测试名称与条件：`test_box_breakout_requires_lookback_closed_bars`、`test_box_breakout_counts_separated_touch_events`、`test_box_breakout_requires_two_full_round_trips`、`test_box_breakout_ignores_bar_touching_both_edges`、`test_box_breakout_width_bounds_are_inclusive`、`test_box_breakout_rejects_missing_or_invalid_history`。构造固定 OHLC 数据分别验证：少于 N 根拒绝；同侧相邻触碰仅计一次；U-L-U-L-U 序列计 2 个完整往返；一根 K 线同时触及两侧不增加任何触碰计数；最小/最大宽度均接受，超界拒绝。

- [ ] **步骤 2：添加突破判定测试**

新增 `advance_box_breakout(box_state, closed_bar, point)`，使用确认时冻结的 ATR 缓冲，只在每根新收盘 K 线上更新；返回 `"wait"`、`"reset"`、`"buy"` 或 `"sell"`。覆盖单根越界不触发、连续第二根越界触发、收回区间清零计数、上下边界方向和无效数值拒绝。

测试名称：`test_box_breakout_needs_two_consecutive_closes`、`test_box_breakout_resets_when_close_returns_inside`、`test_box_breakout_maps_upper_and_lower_with_order_type`。另外验证确认缓冲锁定于确认时 ATR，即后续 ATR 波动不会移动已确认突破线。

- [ ] **步骤 3：添加策略模型距离锁定/生命周期测试**

只添加尚未实现的模型行为测试：新模式必须先取得确认箱体和突破信号才产生 market action；有效开仓时两距离都等于箱体宽度，后续 `on_tick`、网格成交和止损切换不改变本订单组距离；确认箱体过期后回到扫描态。

测试名称：`test_box_breakout_mode_waits_for_confirmed_box_and_breakout`、`test_box_breakout_mode_locks_equal_stop_and_take_distances`、`test_box_breakout_box_expires_after_lookback_bars`、`test_box_breakout_state_restores_without_recounting_or_duplicate_entry`。模型需覆盖确认等待状态保存/恢复、离线期间过期/补处理最近已收盘 K 线、首单请求失败重试、请求成功后信号消费和活动组锁定距离。

- [ ] **步骤 4：运行新增测试确认初始失败**

运行：`python -m pytest tests/test_strategy_logic.py -k box_breakout -q`

预期：因新模式和纯逻辑函数尚不存在而失败；记录失败测试，随后再开始生产代码实现。

## 任务 2：实现 MT4 箱体识别、冻结和突破入场

**文件：**
- 修改：`NoMatterRiseFall_MT4.mq4`

- [ ] **步骤 1：追加枚举和专用输入**

在 `DistanceMode` 追加值 7；增加识别周期、观察窗口 K 线数 60、ATR 周期 14、触碰 ATR 倍数 0.2、上/下沿最少触碰 2、往返数 2、同侧最小间隔 3、最小/最大宽度 500/1000 points、突破缓冲 ATR 倍数 0.2。全部使用新名称并仅由新模式读取。

- [ ] **步骤 2：实现确定性候选扫描**

添加 `FindConfirmedBox(...)`：通过 `iBars/iHigh/iLow/iClose/iATR` 读取识别周期最近 N 根已完成 K 线（shift 从 1 起），数据不足或任何价格/ATR 无效则返回 false。按窗口极值确定边界，依输入容差把触边 K 线归并为间隔合格的事件，统计边界次数和交替事件产生的完整往返。宽度用 `MathRound((upper-lower)/Point)`，按含边界最小/最大值检查。

- [ ] **步骤 3：实现确认箱体持久化与过期**

增加箱体状态结构/全局字段：有效标志、上沿、下沿、宽度 points、确认 ATR/突破缓冲、确认时间、最后处理 K 线时间、上下突破连续收盘计数。增加独立的 `SaveBoxState`、`LoadBoxState`、`ClearBoxState`；不要把等待中的箱体字段混入会在订单组转换时调用的 `ClearState`。保存时先写所有数值，再写有效版本标志；读取时只有版本标志、边界、宽度、时间戳和新模式参数指纹全部有效才恢复。使用识别周期的 `iBarShift`/`CopyRates` 计算确认后已过去的 bar 数，保证 EA 离线期间也会过期；若未处理已收盘 K 线不超过有效期，则按时间顺序补处理并更新两根突破计数，否则清除旧箱体。已存在活动订单组时以现有订单组锁定点数为准，不重算距离。新箱体在订单组已建立并完成 `SaveState` 后消费；下单请求失败时保留同一箱体/信号，以便既有重试机制继续重试，避免重扫生成不同信号。持久化写入失败时不得发起交易请求。

- [ ] **步骤 4：实现突破方向与首单**

新增 `GetBoxBreakoutDirection(...)`：每个识别周期新 K 线只读取刚收盘 K 线收盘价；连续两根收盘超过冻结边界及缓冲才返回方向，回到箱体内时清除该侧计数。上破/下破映射沿用 `开单方式`。将第二根确认 K 线时间作为稳定 signal bar time 接入 MT4/MT5 已有首单入口和 MT5 `PrepareInitialSignal` / trade-request 去重流程。突破确认后，把冻结宽度同时赋给初始止损点数和止盈点数，继续调用现有首单入口：单篮子走 `OpenMarket`，双篮子走 `MultiStartResolvedPair`；不绕过交易时段、点差检查、保护单验证或现有请求重试。

- [ ] **步骤 5：接入参数校验和组距离读取**

在 `OnInit` 参数校验中检查识别周期属于有效 timeframe、观察窗口大于 0、ATR 周期大于 0、倍数有限且大于 0、触碰数/往返数/间隔为正、宽度范围正且 max >= min。对窗口能否容纳要求的事件序列做合理性检查；历史 bar 数或 ATR 数据不足时运行期不确认箱体，不设置任意的观察窗口上限。让新模式的 `GetDistancePoints` 不再尝试即时扫描候选；无首单上下文时返回 false，确保已有组的 `GetActiveDistancePoints` 仍使用已锁定止损止盈点数。已有订单因终端重启且保护单缺失时，只能从该订单组已保存距离或与该组关联的已持久化突破信号恢复保护，不得重新扫描市场后套用另一个箱体的宽度。

- [ ] **步骤 6：保持现有订单组与恢复流程不变**

在首单后调用现有状态保存并确认 `ClearState`、止损反手、止盈结束、资金不足重置不会丢失活动订单组的 `g_group_stop_points/g_group_take_profit_points`。箱体候选字段只由 `ClearBoxState` 控制；确认成交后清除箱体状态，但保留已写入订单组的距离。订单组完成后状态清零，下一周期重新发现箱体。

## 任务 3：实现 MT5 箱体交易及配置面板

**文件：**
- 修改：`NoMatterRiseFall_MT5.mq5`

- [ ] **步骤 1：添加 MT5 模式输入和配置字段**

追加距离模式值 7 和与 MT4 完全同名/同默认值的 inputs。识别周期使用 `ENUM_TIMEFRAMES`，面板提供明确的周期标签与枚举映射；扩展 `GuiConfig`、`LoadConfigFromInputs`、GUI 配置文本/指纹函数、持久化 GUI 配置序列化与解析，使所有新字段能从 EA inputs 加载，也能由面板编辑后保存和应用。

- [ ] **步骤 2：实现 MT5 候选读取和交易状态**

用 `CopyRates` 与 `iATR` handle/`CopyBuffer` 实现与 MT4 相同的闭合 bar 范围、边界、触碰、往返、宽度和突破条件。ATR handle 按已应用的识别周期/ATR 周期创建或重建，在 `OnDeinit` 释放；CopyRates 或 CopyBuffer 历史不足/失败时不确认箱体。持久化箱体状态使用与当前 MT5 symbol/magic 作用域一致的 Global Variables 命名；确认时间、已处理 K 线时间和过期检查必须与 MT4 结果一致。接入首单流程时使用现有单篮子/双篮子首单入口、MT5 信号去重和 trade-request 恢复机制，锁定宽度作为组止盈止损距离。

- [ ] **步骤 3：扩展面板选项、字段编辑和校验**

将距离模式显示文本/选项数由 7 项扩至 8 项并将索引 7 显示为“箱体确认突破”。更新 `GuiDistanceModeText`、`GuiDistanceSummaryText` 和距离参数页：仅当新模式选中时显示周期、窗口、ATR、触碰/往返/间隔、宽度范围、突破缓冲字段。更新 `GuiIsEditableFieldKey`、字段读取/写入、数字/枚举解析、apply/reset、`ValidateGuiConfig`、输入配置合法性检查和页面键盘焦点字段列表。宽度范围在 GUI 和启动校验中均包含边界且限制 min <= max。将新字段加入 MT5 当前配置指纹，并增加“上一版配置指纹（含旧箱体高度字段、不含箱体突破字段）→当前指纹”的迁移分支，保证升级时有活动订单组也能恢复；此分支不得接受其他不匹配的配置。

- [ ] **步骤 4：管理 ATR handle 和配置变更**

增加统一的 `EnsureBoxAtrHandle` / `ReleaseBoxAtrHandle`。初始化及 GUI 应用配置后比较识别周期和 ATR 周期，变化时释放并重建 handle；`OnDeinit` 释放句柄。活动订单组的恢复继续使用已锁定点数；仅在无持仓/挂单时，箱体设置变更才清除等待中的冻结箱体并按新参数扫描。

## 任务 4：完成策略模型并跑相关自动化验证

**文件：**
- 修改：`tests/strategy_logic.py`
- 修改：`tests/test_strategy_logic.py`

- [ ] **步骤 1：实现 Python 纯逻辑至新增测试通过**

按任务 1 的函数签名实现窗口扫描、ATR/Wilder 计算约定、事件间隔、往返计数、冻结箱体状态、突破连续计数、方向映射和到期处理。ATR 的计算必须明确采用 MT4/MT5 一致的 Wilder 平滑真实波幅；Python 测试用同一组手工 OHLC 验证结果。

- [ ] **步骤 2：实现 StrategyModel 新模式入口和锁定**

让模型在无有效 BoxState 或未突破时不发送 market action；突破时创建首单并保存 `group_stop_points == group_take_profit_points == box_width_points`。清空旧组后才恢复扫描状态。运行：`python -m pytest tests/test_strategy_logic.py -k box_breakout -q`，预期全部通过。

- [ ] **步骤 3：添加 MT4/MT5 源码契约测试**

断言两源码均包含 enum 值 7、参数同默认、仅 shift >= 1/CopyRates 已完成数据、相同方向映射、两距离赋值和状态过期字段；断言 MT5 距离模式选项数为 8、GUI 字段可编辑、旧配置指纹迁移覆盖新增模式前的版本且配置校验覆盖新参数。运行上述 targeted pytest，预期通过。

## 任务 5：更新用户说明

**文件：**
- 修改：`README.md`
- 修改：`EA软件使用手册.html`

- [ ] **步骤 1：增加新模式说明并区分旧箱体模式**

说明新模式如何以已收盘窗口极值、ATR 触碰容差、触碰/往返、最小最大点数确认箱体；说明上破/下破两根收盘确认和“开单方式”映射；说明箱体宽度作为等距止损/止盈且订单组锁定；说明新箱体过期规则和历史不足时等待。明确“箱体高度”仍是既有 M1 时间范围模式，不增加突破入场。

- [ ] **步骤 2：核对说明中的参数默认值和名称**

对照 MT4 inputs、MT5 inputs 与 GUI 标签，逐项核对观察窗口 60、ATR 14、0.2 倍数、每侧触碰 2、往返 2、间隔 3、宽度 500/1000、突破缓冲 0.2。

## 任务 6：完整验证和构建

**文件：**
- 验证：`tests/test_strategy_logic.py`
- 构建：`NoMatterRiseFall_MT4.mq4`、`NoMatterRiseFall_MT5.mq5`

- [ ] **步骤 1：运行相关策略测试**

运行：`python -m pytest -q`

预期：完整自动化测试套件全部通过，包括箱体确认突破、旧箱体高度和其他距离模式的回归测试。

- [ ] **步骤 2：编译两份 canonical EA**

运行：`powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\compile-mql.ps1 -Target Both`

预期：MetaEditor 对 MT4、MT5 均报告 0 errors，`.ex4` 和 `.ex5` 存在且时间戳刷新；记录警告、日志位置和产物路径。如发现失败，按 AGENTS.md 使用显式 MetaEditor 路径重试，不跳过任一平台。

- [ ] **步骤 3：检查兼容性和差异**

运行：`git diff --check`，并确认 `DISTANCE_BOX_RANGE = 6`、旧箱体时间输入和旧箱体高度说明未被改名/重解释；确认新增状态键与现有订单组状态键不同名。记录最终改动文件、测试输出、编译错误/警告和产物路径。

## 自审清单

- 所有 V2.0 要求分别由算法测试、MT4/MT5 逻辑、MT5 GUI、文档、构建任务覆盖。
- 新箱体过期、完整往返含义、ATR 平滑方法、已收盘 K 线处理和方向映射已在本计划固定，避免实现阶段分歧。
- 现有箱体高度模式和距离模式枚举值 0–6 保持兼容；本计划没有引入绘图、告警、双向挂单或多箱体交易等扩展。
- 本计划创建于已有未提交工作区中；执行时只修改列出的目标文件，不清理或覆盖其他未提交改动。
