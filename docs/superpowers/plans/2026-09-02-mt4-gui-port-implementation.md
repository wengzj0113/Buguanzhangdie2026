# MT4 GUI 完全对齐移植 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 `NoMatterRiseFall_MT4.mq4` 中实现与 MT5 GUI 完全对齐的原生 MT4 图表界面、参数编辑和便捷操作，同时保持现有 MT4 交易逻辑不变。

**Architecture:** 在现有 MT4 单文件 EA 中增加边界清晰的 `Gui*` 函数层、草稿配置/已应用配置模型和 MQL4 `OnChartEvent` 事件分发。GUI 使用 MQL4 原生图表对象，策略逻辑只读取已应用配置；总览动态内容使用对象属性局部更新，页面切换和布局变化才触发完整渲染。

**Tech Stack:** MQL4 chart objects (`OBJ_RECTANGLE_LABEL`, `OBJ_LABEL`, `OBJ_BUTTON`, `OBJ_EDIT`), Python `pytest` source-contract tests, MetaEditor 4 compiler, MT4 chart runtime.

---

## 文件结构与职责

- Modify: `D:/00_EA/codx-ea/Experts/不管涨跌复刻/NoMatterRiseFall_MT4.mq4`
  - 保留现有枚举、输入参数、订单管理、网格、反手、止损止盈和时间过滤逻辑。
  - 新增 GUI 常量、`GuiConfig`、渲染器、对象命名、事件分发、输入解析和配置应用适配。
- Modify: `D:/00_EA/codx-ea/Experts/不管涨跌复刻/tests/test_strategy_logic.py`
  - 增加 MT4 源码读取入口和 GUI 源码契约测试；保留全部 MT5 回归测试。
- Generate and verify: `D:/00_EA/codx-ea/Experts/不管涨跌复刻/NoMatterRiseFall_MT4.ex4`
  - 仅由 MetaEditor 编译生成，不手工编辑。
- Generate and inspect: `D:/00_EA/codx-ea/Experts/不管涨跌复刻/NoMatterRiseFall_MT4.log`
  - 保存编译输出和运行验证证据。

## Task 1: 建立 MT4 GUI 红测试和源代码契约

**Files:**
- Modify: `D:/00_EA/codx-ea/Experts/不管涨跌复刻/tests/test_strategy_logic.py`
- Reference: `D:/00_EA/codx-ea/Experts/不管涨跌复刻/docs/superpowers/specs/2026-09-02-mt4-gui-port-design.md`

- [ ] **Step 1: 增加 MT4 源码路径和读取辅助函数。** 在现有 `MT5_SOURCE` 后加入：

```python
MT4_SOURCE = Path(__file__).resolve().parents[1] / "NoMatterRiseFall_MT4.mq4"


def read_mt4_source():
    return MT4_SOURCE.read_text(encoding="utf-8")
```

- [ ] **Step 2: 写入失败测试，锁定完整 GUI 生命周期和 MT4 事件机制。** 测试必须要求 MT4 源码包含 `GuiCreate`、`GuiDestroy`、`GuiRender`、`GuiRefreshOverviewData`、`OnChartEvent`、`OnInit`、`OnDeinit`，以及 `OBJ_RECTANGLE_LABEL`、`OBJ_LABEL`、`OBJ_BUTTON`、`OBJ_EDIT`。

- [ ] **Step 3: 写入失败测试，锁定完整参数和页面。** 测试必须检查以下 20 个 GUI key 均出现在 MT4 内容渲染路径中：

```python
keys = [
    "first_direction", "cycle_mode", "distance_mode", "order_type",
    "candle_order_mode", "candle_enable_multiple", "take_profit_mode",
    "initial_lots", "initial_lots_multiplier", "max_reversals",
    "grid_count", "grid_lot_multiplier", "stop_loss_distance_points",
    "take_profit_distance_points", "candle_min_range_points",
    "candle_max_range_points", "magic_number", "order_comment",
    "start_time", "end_time",
]
for key in keys:
    assert f'"{key}"' in content_body
```

测试还要检查五个页面枚举/标签：`GUI_PAGE_OVERVIEW`、`GUI_PAGE_OPENING`、`GUI_PAGE_DISTANCE`、`GUI_PAGE_GRID`、`GUI_PAGE_RISK`。

- [ ] **Step 4: 写入失败测试，锁定浏览器对齐几何和大箭头。** 测试要求存在 `GUI_WINDOW_WIDTH = 760`、`GUI_WINDOW_HEIGHT = 640`、`GUI_NAV_WIDTH = 178`、`GUI_CONTENT_WIDTH = 560`、`GUI_DROPDOWN_ARROW_WIDTH = 34`、`GUI_DROPDOWN_ARROW_FONT_SIZE = 30` 和 `GuiCreateDropdownArrow`。

- [ ] **Step 5: 运行红测试并提交。**

```powershell
python -m pytest tests/test_strategy_logic.py -k "mt4_gui or mt4_dropdown or mt4_overview" -q
```

Expected: FAIL，因为 MT4 当前没有图表 GUI 和 `OnChartEvent`。

```powershell
git add tests/test_strategy_logic.py
git commit -m "test: define MT4 GUI parity contracts"
```

## Task 2: 建立 MT4 配置模型和对象命名边界

**Files:**
- Modify: `D:/00_EA/codx-ea/Experts/不管涨跌复刻/NoMatterRiseFall_MT4.mq4`
- Test: `D:/00_EA/codx-ea/Experts/不管涨跌复刻/tests/test_strategy_logic.py`

- [ ] **Step 1: 增加 GUI 常量、页面状态和配置结构。** 在输入参数和现有全局状态附近定义 `GuiPage`、`GuiDisplayMode`、`GuiRunState`、`GuiConfig`，字段覆盖 MT4 当前全部输入参数；同时定义窗口、导航、内容、字段、箭头和选项层尺寸，箭头使用宽度 34、字体 30。

- [ ] **Step 2: 增加草稿/应用状态和渲染标志。** 建立 `g_gui_applied_config`、`g_gui_draft_config`、当前页面、显示模式、运行状态、脏标记、下拉 key、编辑 key、编辑前文本、提示文本和总览快照。所有 GUI 输入先写入 draft，不直接修改交易状态。

- [ ] **Step 3: 实现 MT4 输入适配函数。** 增加 `GuiLoadConfigFromInputs()`、`GuiCopyConfig()`、`GuiConfigFingerprint()` 和 `GuiConfigHasChanged()`，将 `首单方向`、`循环模式`、`距离模式`、`开单方式`、`K线开单模式`、`kline_enable_multiple`、`止盈移动模式`、11 个指定参数、订单识别编号、订单注释、开始时间和结束时间全部映射到结构体。

- [ ] **Step 4: 实现稳定对象命名函数。** 增加 `GuiObjectPrefix()`、`GuiObjectName(kind, key)` 和 `GuiDeleteOwnedObjects()`。对象名必须包含 EA 实例标识和当前 magic/order id，长度控制在 MT4 对象名限制内；删除时只删除本 EA 前缀对象。

- [ ] **Step 5: 运行模型契约测试并提交。**

```powershell
python -m pytest tests/test_strategy_logic.py -k "mt4_gui_config or mt4_object_prefix" -q
git add NoMatterRiseFall_MT4.mq4 tests/test_strategy_logic.py
git commit -m "feat: add MT4 GUI configuration model"
```

Expected: 所有 Task 1/Task 2 相关测试 PASS。

## Task 3: 实现 MT4 原生 GUI 渲染和生命周期

**Files:**
- Modify: `D:/00_EA/codx-ea/Experts/不管涨跌复刻/NoMatterRiseFall_MT4.mq4`
- Test: `D:/00_EA/codx-ea/Experts/不管涨跌复刻/tests/test_strategy_logic.py`

- [ ] **Step 1: 实现通用对象创建函数。** 增加 `GuiCreatePanel`、`GuiCreateText`、`GuiCreateButton`、`GuiCreateEdit`、`GuiUpdateText` 和 `GuiDeleteObject`。所有交互对象设置 `OBJPROP_SELECTABLE=true`、`OBJPROP_HIDDEN=false`、`OBJPROP_ZORDER=1000`；面板使用较低 z-order，文字使用高于面板但低于控件的 z-order。

- [ ] **Step 2: 实现窗口、标题栏、导航和底部操作栏。** 增加 `GuiRenderTitleBar`、`GuiRenderNavigation`、`GuiRenderActions`，使用与 MT5 相同的深色调色板、状态颜色、标题上下文和按钮布局。窗口位于图表左上角，内容区从导航右侧开始，操作按钮保持在窗口内部。

- [ ] **Step 3: 实现最小化与恢复。** 增加 `GuiRenderMinimizedBar`、`GuiToggleDisplayMode` 和恢复按钮。最小化只保留标题/状态横条，恢复时重新渲染当前页面和所有字段；不得遗留旧页面对象。

- [ ] **Step 4: 接入 MT4 生命周期。** `OnInit` 在交易逻辑初始化成功后加载配置、创建 GUI 并渲染当前页面；`OnDeinit` 删除 GUI 对象并恢复 GUI 修改过的图表属性；`OnTick` 保持原有交易调用顺序，并在 GUI 节流周期调用动态状态刷新。

- [ ] **Step 5: 运行静态渲染测试并提交。**

```powershell
python -m pytest tests/test_strategy_logic.py -k "mt4_gui_render or mt4_gui_lifecycle or mt4_palette" -q
git add NoMatterRiseFall_MT4.mq4 tests/test_strategy_logic.py
git commit -m "feat: render native MT4 terminal GUI"
```

## Task 4: 实现页面、普通下拉框和 11 个可编辑下拉框

**Files:**
- Modify: `D:/00_EA/codx-ea/Experts/不管涨跌复刻/NoMatterRiseFall_MT4.mq4`
- Test: `D:/00_EA/codx-ea/Experts/不管涨跌复刻/tests/test_strategy_logic.py`

- [ ] **Step 1: 实现页面内容渲染入口。** 增加 `GuiRenderContent` 和 `GuiRenderField`，将 20 个参数分配到开仓、距离、网格、风控页面；枚举/模式参数调用 `GuiRenderDropdownField`，11 个数值/时间参数调用 `GuiRenderEditableDropdownField`，魔术号和订单注释调用 `GuiRenderEditField`。

- [ ] **Step 2: 实现普通下拉选项模型。** 增加 `GuiDropdownOptionCount`、`GuiDropdownOptionText`、`GuiDropdownValueIndex`、`GuiSetDropdownValue`，覆盖方向、循环、距离、开单、K 线模式、K 线倍数开关和止盈移动模式。

- [ ] **Step 3: 实现 11 组常用选项。** 增加 `GuiEditableDropdownOptionCount`、`GuiEditableDropdownOptionText`、`GuiEditableDropdownOptionColumns`，准确生成：手数 0.01/0.02/0.03/0.04/0.05/0.1/0.2/0.3/0.4/0.5；初始倍数 1.0/1.2/1.3/1.5/2.0；距离和高度 100 至 1000 步长 100 及 1500；网格数量 1 至 10；网格倍数 1.0 至 5.0 步长 0.5；反手次数 2 至 20；时间 00:00 至 23:00。

- [ ] **Step 4: 实现统一大箭头。** 增加 `GuiCreateDropdownArrow`，使用独立 `OBJ_BUTTON`、文本 `▼`、`OBJPROP_FONTSIZE=30` 和宽度 34。普通下拉框和可编辑下拉框必须共同调用此函数，禁止在字段文本中拼接小箭头。

- [ ] **Step 5: 实现选项层几何和 z-order。** 增加 `GuiRenderDropdownOverlay`、`GuiCreateDropdownOption` 和 `GuiClearDropdownOverlay`。选项层在所有页面字段渲染完成后创建，使用 z-order 2000；长列表使用两列，且选项层保持在内容面板和图表可见区域内。

- [ ] **Step 6: 运行页面和选项测试并提交。**

```powershell
python -m pytest tests/test_strategy_logic.py -k "mt4_dropdown or mt4_pages or mt4_parameter" -q
git add NoMatterRiseFall_MT4.mq4 tests/test_strategy_logic.py
git commit -m "feat: add MT4 parity dropdown controls"
```

## Task 5: 实现点击、键盘编辑和输入校验

**Files:**
- Modify: `D:/00_EA/codx-ea/Experts/不管涨跌复刻/NoMatterRiseFall_MT4.mq4`
- Test: `D:/00_EA/codx-ea/Experts/不管涨跌复刻/tests/test_strategy_logic.py`

- [ ] **Step 1: 增加事件分发。** 实现 `OnChartEvent`，按顺序处理对象点击、编辑结束、键盘事件和坐标点击。对象点击路由到 `GuiHandleFieldClick`、`GuiHandleDropdownClick`、导航和操作按钮；事件处理后释放按钮状态，避免一次点击触发两次。

- [ ] **Step 2: 实现编辑会话。** 增加 `GuiEnterEditSession`、`GuiSyncEditValue`、`GuiHandleEditEnd`、`GuiLeaveEditSession` 和 `GuiHandleEditKeyDown`。编辑对象必须设置 `OBJPROP_READONLY=false`；点击输入区时保留原生焦点，不立即删除/重建该 `OBJ_EDIT`。

- [ ] **Step 3: 实现数值和时间解析。** 增加 `GuiTryParseDouble`、`GuiTryParseInteger`、`GuiParseTimeText` 和 `GuiParseEditableDropdownValue`。接受列表外但合法的值，例如 `0.07`、`2.25`、`750`、`08:30`；拒绝空值、非数字、负数、超范围整数、无效时间，并按品种最小手数/最大手数/步长和策略约束校验。

- [ ] **Step 4: 实现 Enter/Esc/失焦语义。** Enter 提交当前字段到 draft，Esc 恢复编辑前值，失焦执行同样的提交校验。非法输入保留最后有效 draft 值，显示字段级提示，并保持当前页面和编辑控件可见。

- [ ] **Step 5: 防止刷新打断编辑。** `GuiRenderIfNeeded` 在存在活动编辑会话时只更新非编辑动态对象；完整渲染完成后重新同步活动编辑对象的文本和焦点状态，不能让 `OBJ_EDIT` 退化为不可编辑文本。

- [ ] **Step 6: 增加交互契约测试并提交。** 测试必须覆盖 `CHARTEVENT_OBJECT_CLICK`、`CHARTEVENT_KEYDOWN`、`CHARTEVENT_OBJECT_ENDEDIT`、`OBJPROP_READONLY=false`、合法自定义值、非法值保留和 Esc 取消。

```powershell
python -m pytest tests/test_strategy_logic.py -k "mt4_edit or mt4_key or mt4_validation" -q
python -m pytest -q
git add NoMatterRiseFall_MT4.mq4 tests/test_strategy_logic.py
git commit -m "feat: make MT4 GUI controls editable"
```

## Task 6: 实现总览局部刷新和应用参数安全流程

**Files:**
- Modify: `D:/00_EA/codx-ea/Experts/不管涨跌复刻/NoMatterRiseFall_MT4.mq4`
- Test: `D:/00_EA/codx-ea/Experts/不管涨跌复刻/tests/test_strategy_logic.py`

- [ ] **Step 1: 实现总览快照。** 增加 `GuiBuildOverviewSnapshot` 和 `GuiRefreshOverviewData`，只用 `ObjectSetString`/`ObjectSetInteger` 更新方向、运行状态、持仓、挂单、浮动盈亏、反手次数、风控和配置摘要对象；函数体不得调用 `ObjectsDeleteAll`、`GuiDestroy` 或完整 `GuiRender`。

- [ ] **Step 2: 实现统一配置应用。** 增加 `GuiValidateConfig` 和 `GuiApplyDraft`，验证 draft 后把值写入已应用配置，并让后续策略函数读取已应用配置；失败时保留 draft 和页面，显示明确的原因。

- [ ] **Step 3: 接入持仓/挂单安全限制。** 使用 MT4 `OrdersTotal`、`OrderSelect`、`OrderSymbol`、`OrderMagicNumber` 检查当前 EA 的暴露。普通参数允许在下一个交易周期应用；订单识别编号/magic 变化在有持仓或挂单时拒绝，且不改变原配置和订单归属。

- [ ] **Step 4: 实现按钮状态反馈。** “应用参数”显示成功/失败提示，“暂停/继续”更新运行状态，“平仓并撤单”复用现有关闭逻辑并显示执行结果；所有按钮都必须通过同一事件路径触发。

- [ ] **Step 5: 运行安全和刷新测试并提交。**

```powershell
python -m pytest tests/test_strategy_logic.py -k "mt4_overview_refresh or mt4_apply or mt4_exposure" -q
python -m pytest -q
git add NoMatterRiseFall_MT4.mq4 tests/test_strategy_logic.py
git commit -m "feat: apply MT4 gui config safely"
```

## Task 7: 编译、部署和 MT4 实机交互验收

**Files:**
- Verify: `D:/00_EA/codx-ea/Experts/不管涨跌复刻/NoMatterRiseFall_MT4.mq4`
- Generate: `D:/00_EA/codx-ea/Experts/不管涨跌复刻/NoMatterRiseFall_MT4.ex4`
- Inspect: `D:/00_EA/codx-ea/Experts/不管涨跌复刻/NoMatterRiseFall_MT4.log`

- [ ] **Step 1: 运行完整 Python 测试。**

```powershell
python -m pytest -q
```

Expected: 0 failures。

- [ ] **Step 2: 自动定位 MT4 编译器并编译。** 使用以下 PowerShell 命令查找 `metaeditor.exe`/`MetaEditor.exe`，再用找到的第一个可执行文件编译：

```powershell
$editors = Get-ChildItem 'C:\Program Files','C:\Program Files (x86)' -Filter 'metaeditor*.exe' -File -Recurse -ErrorAction SilentlyContinue
if (-not $editors) { throw 'MetaEditor for MT4 was not found under Program Files.' }
$editor = $editors | Select-Object -First 1
& $editor.FullName /compile:'D:\00_EA\codx-ea\Experts\不管涨跌复刻\NoMatterRiseFall_MT4.mq4' /log
```

Expected: compiler log contains `0 error(s), 0 warning(s)` or the equivalent localized result with zero errors and zero warnings。

- [ ] **Step 3: 部署到 MT4 Experts 目录并校验产物。** 从编译器输出目录找到最新 `NoMatterRiseFall_MT4.ex4`，复制到对应 MT4 `MQL4\\Experts` 目录和本项目产物目录；复制后用 `Get-FileHash -Algorithm SHA256` 比较两个文件。

- [ ] **Step 4: 在真实 MT4 图表执行交互清单。** 打开 XAUUSD M1，加载 EA，依次验证：窗口显示、五个页面、每个模式下拉框、11 个可编辑下拉框的箭头和选项层、键盘输入 `0.07`/`2.25`/`750`/`08:30`、Enter、Esc、失焦、非法输入提示、文本框编辑、最小化/恢复、暂停/继续和应用参数。

- [ ] **Step 5: 验证交易安全与刷新行为。** 在无暴露状态应用普通参数；在有持仓/挂单状态尝试修改 magic，确认被拒绝；确认总览数值变化时只更新数据对象，没有整页闪烁或 GUI 消失；确认平仓并撤单仍使用原有策略函数。

- [ ] **Step 6: 完成最终证据检查。**

```powershell
git diff --check
git status --short
```

记录测试通过数量、编译日志、EX4 SHA-256、MT4 图表截图和交互结果；只有所有项目通过后才进入分支合并流程。

## Task 8: 合并前回归与交付

**Files:**
- Verify: `D:/00_EA/codx-ea/Experts/不管涨跌复刻/NoMatterRiseFall_MT4.mq4`
- Verify: `D:/00_EA/codx-ea/Experts/不管涨跌复刻/tests/test_strategy_logic.py`

- [ ] **Step 1: 检查变更范围。** 确认策略交易函数没有被 GUI 事件处理器直接调用，GUI 改动集中在 `Gui*` 函数和必要的生命周期钩子，MT5 源码没有被本次移植意外修改。

- [ ] **Step 2: 执行完整测试和编译复核。** 再次运行 `python -m pytest -q`、MT4 MetaEditor 编译和 `git diff --check`，结果必须与 Task 7 一致。

- [ ] **Step 3: 生成交付摘要。** 摘要包含 GUI 完全对齐范围、MT4 编译结果、自动测试结果、实机验证结果、EX4 路径和未执行的高风险操作清单；不得宣称未验证的 MT4 交互已经通过。

- [ ] **Step 4: 使用 finishing-a-development-branch 流程选择合并方式。** 在所有验证通过后展示合并到 `main` 的选项，按用户选择完成合并，不执行强制 reset、清理或未授权的远程 push。

