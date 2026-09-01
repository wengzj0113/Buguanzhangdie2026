# 不管涨跌 EA GUI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 为 MT4 和 MT5 版本增加一个图表左上角的深色悬浮 GUI，支持专家/简洁模式、参数草稿应用、运行状态查看和安全的便捷交易操作，同时不改变现有策略的订单算法。

**Architecture:** 在现有单文件 EA 结构中增加同语义的 GUI 状态层、运行时配置层、图表对象视图层和事件控制层。策略层只读取运行时配置并输出只读快照；GUI 通过命令入口请求暂停、恢复、应用参数和清仓，不直接复制订单组算法。MT4 与 MT5 保持相同的状态机和控件命名，平台差异只留在图表对象和交易查询适配代码中。

**Tech Stack:** MQL4、MQL5、MT4/MT5 图表对象 API、现有 Python `pytest` 策略模型、MetaEditor 编译器和现有策略测试器配置。

---

## 文件边界

- Modify: `NoMatterRiseFall_MT5.mq5` — MT5 运行时配置、GUI 对象、事件处理、状态快照和命令接入。
- Modify: `NoMatterRiseFall_MT4.mq4` — MT4 与 MT5 相同的 GUI 语义及平台 API 适配。
- Modify: `tests/strategy_logic.py` — 增加不依赖图表 API 的配置草稿、暂停和应用语义模型。
- Modify: `tests/test_strategy_logic.py` — 覆盖 GUI 命令语义和现有策略回归。
- Modify: `README.md` — 增加 GUI 使用说明、按钮语义和参数生效规则。
- Create: `mt5_gui_smoke_test.ini` — 仅用于策略测试器/人工冒烟测试的 GUI 相关默认配置记录。

不创建独立桌面程序，也不把 MT4/MT5 的对象 API 强行抽成一个平台不兼容的公共 include 文件；现有两个 EA 文件保持可单独编译和交付。

### Task 1: 建立基线与 GUI 状态模型测试

**Files:**
- Modify: `tests/strategy_logic.py`
- Modify: `tests/test_strategy_logic.py`

- [ ] **Step 1: 记录当前测试基线**

Run: `pytest -q`

Expected: 当前已有测试全部通过；记录测试数量，后续不得因 GUI 改动减少。

- [ ] **Step 2: 写失败测试，定义 GUI 草稿和运行命令语义**

在 `tests/test_strategy_logic.py` 增加以下测试：

```python
def test_gui_draft_does_not_change_applied_config_until_apply():
    gui = GuiStateModel(applied={"initial_lots": 0.01, "cycle_mode": "mode1"})

    gui.edit("initial_lots", 0.05)

    assert gui.applied["initial_lots"] == 0.01
    assert gui.draft["initial_lots"] == 0.05
    assert gui.has_unapplied_changes is True

    result = gui.apply()

    assert result.ok is True
    assert gui.applied["initial_lots"] == 0.05
    assert gui.has_unapplied_changes is False


def test_gui_pause_only_blocks_new_initial_entry():
    gui = GuiStateModel(applied={"initial_lots": 0.01})

    gui.pause_new_initial_entry()

    assert gui.paused_new_initial_entry is True
    assert gui.strategy_management_enabled is True
    assert gui.pending_orders_are_preserved is True


def test_gui_close_all_requires_confirmation_and_reports_incomplete_cleanup():
    gui = GuiStateModel(applied={"initial_lots": 0.01})

    assert gui.request_close_all().requires_confirmation is True
    assert gui.confirm_close_all(close_ok=False, delete_ok=True).status == "cleanup_incomplete"
```

- [ ] **Step 3: 运行测试确认它们失败**

Run: `pytest tests/test_strategy_logic.py -q`

Expected: FAIL because `GuiStateModel` and its result types do not exist。

- [ ] **Step 4: 实现最小的纯 Python GUI 状态模型**

在 `tests/strategy_logic.py` 增加 `GuiApplyResult`、`GuiCloseResult` 和 `GuiStateModel`。模型必须保存 `applied` 与 `draft` 两份字典；`edit()` 只改草稿；`apply()` 复制草稿到已应用配置；`pause_new_initial_entry()` 只改变暂停标志；`confirm_close_all()` 在任一清理动作失败时返回 `cleanup_incomplete`。

- [ ] **Step 5: 运行新增测试**

Run: `pytest tests/test_strategy_logic.py -q`

Expected: 新增 GUI 状态测试和原有策略测试全部 PASS。

- [ ] **Step 6: 提交基线模型**

```bash
git add tests/strategy_logic.py tests/test_strategy_logic.py
git commit -m "test: define EA GUI state semantics"
```

### Task 2: 在 MT5 增加运行时配置和 GUI 状态变量

**Files:**
- Modify: `NoMatterRiseFall_MT5.mq5` — 放在现有 `input` 和全局状态之后。

- [ ] **Step 1: 定义 GUI 页面、显示模式和运行命令枚举**

增加与以下签名等价的类型，名称必须稳定，后续页面和事件代码只依赖这些类型：

```cpp
enum GuiPage { GUI_PAGE_OVERVIEW, GUI_PAGE_OPENING, GUI_PAGE_DISTANCE,
               GUI_PAGE_GRID, GUI_PAGE_RISK };
enum GuiDisplayMode { GUI_MODE_EXPERT, GUI_MODE_SIMPLE };
enum GuiRunState { GUI_RUN_RUNNING, GUI_RUN_PAUSED_INITIAL,
                   GUI_RUN_CLEANING, GUI_RUN_ERROR };
enum GuiCommand { GUI_CMD_NONE, GUI_CMD_APPLY, GUI_CMD_PAUSE_INITIAL,
                  GUI_CMD_RESUME_INITIAL, GUI_CMD_REQUEST_CLOSE_ALL,
                  GUI_CMD_CONFIRM_CLOSE_ALL, GUI_CMD_CANCEL_CLOSE_ALL };
```

- [ ] **Step 2: 增加运行时配置副本和草稿状态**

建立一个 `GuiConfig` 结构，字段覆盖所有可设置的输入参数：方向、循环、距离、开单方式、K 线模式、多组开关、止盈移动模式、手数/倍数、网格、距离范围、最大反手次数、订单识别编号、订单注释和时间。

增加以下全局状态：

```cpp
GuiConfig g_gui_applied_config;
GuiConfig g_gui_draft_config;
GuiPage g_gui_page = GUI_PAGE_OVERVIEW;
GuiDisplayMode g_gui_display_mode = GUI_MODE_EXPERT;
GuiRunState g_gui_run_state = GUI_RUN_RUNNING;
bool g_gui_full_window = true;
bool g_gui_has_unapplied_changes = false;
bool g_gui_close_confirm_open = false;
string g_gui_notice = "";
```

- [ ] **Step 3: 初始化配置并建立策略读取边界**

实现 `GuiConfig LoadConfigFromInputs()`、`bool ValidateGuiConfig(const GuiConfig&, string &error)`、`bool ApplyGuiConfig(const GuiConfig&, string &error)`。

`LoadConfigFromInputs()` 只在 `OnInit()` 读取 input；策略交易函数后续改读已应用运行时配置。`ApplyGuiConfig()` 只更新尚未锁定的下一订单组配置，不修改当前订单组已经锁定的距离、方向、网格和手数状态；暂停/恢复状态不经过配置复制。

- [ ] **Step 4: 替换 MT5 策略中直接读取 input 的路径**

逐项把策略读取 `Inp...` 宏或中文 input 的位置改成 `g_gui_applied_config` 对应字段，并保留 input 作为初始化默认值。不得修改 `SequenceDirection`、订单组切换、挂单去重和清仓算法的条件语义。

- [ ] **Step 5: 运行现有 Python 回归测试并编译 MT5**

Run: `pytest -q`

Run: 使用当前项目已有的 MetaEditor 编译命令编译 `NoMatterRiseFall_MT5.mq5`。

Expected: Python 测试 PASS；MT5 编译 0 errors，新增 GUI 代码没有未使用的未初始化配置路径。

- [ ] **Step 6: 提交 MT5 运行时配置边界**

```bash
git add NoMatterRiseFall_MT5.mq5
git commit -m "feat: add MT5 runtime configuration boundary"
```

### Task 3: 实现 MT5 图表窗口和固定布局

**Files:**
- Modify: `NoMatterRiseFall_MT5.mq5`

- [ ] **Step 1: 定义对象命名和几何常量**

增加只作用于当前 EA 的对象前缀函数 `GuiObjectName(const string suffix)`，前缀至少包含账户、品种和订单识别编号。定义标题栏、左侧导航、内容区、按钮和最小化状态栏的坐标常量；窗口默认左上角，完整窗口和最小化状态使用不同的宽高。

- [ ] **Step 2: 写窗口创建函数**

实现以下函数，并让每个函数只负责一个边界：

```cpp
bool GuiCreate();
void GuiDestroy();
void GuiRender();
void GuiRenderTitleBar();
void GuiRenderNavigation();
void GuiRenderContent();
void GuiRenderActions();
void GuiRenderMinimizedBar();
```

使用 `OBJ_RECTANGLE_LABEL`、`OBJ_LABEL`、`OBJ_EDIT`、`OBJ_BUTTON`、`OBJ_COMBOBOX` 等图表对象；背景、标题和只读文本设置 `OBJPROP_SELECTABLE=false`，按钮、编辑框和下拉框保持可交互，窗口固定左上角且不允许拖动改变位置。

- [ ] **Step 3: 实现完整/最小化切换**

标题栏最小化按钮把 `g_gui_full_window` 设为 false，删除或隐藏完整窗口对象后只绘制横向状态栏；恢复按钮反向操作。切换不得改变 `g_gui_page`、草稿值或策略运行状态。

- [ ] **Step 4: 在生命周期中接入 GUI**

`OnInit()` 在策略状态恢复后调用 `GuiCreate()`；`OnTick()` 只在快照或脏标志改变时调用 `GuiRender()`，避免每个 Tick 无条件重建对象；`OnDeinit()` 调用 `GuiDestroy()`，关闭按钮只隐藏 GUI，不清仓、不停止策略。

- [ ] **Step 5: 编译并人工检查窗口**

在 MT5 图表上加载 EA，检查左上角完整窗口、五项导航、标题栏、最小化/恢复和不遮挡主要行情区域。Expected: 完整窗口默认展开，最小化只保留状态栏。

- [ ] **Step 6: 提交 MT5 布局**

```bash
git add NoMatterRiseFall_MT5.mq5
git commit -m "feat: add MT5 floating GUI layout"
```

### Task 4: 实现 MT5 参数页和专家/简洁模式

**Files:**
- Modify: `NoMatterRiseFall_MT5.mq5`

- [ ] **Step 1: 为每个页面建立字段清单**

总览页只读显示运行状态、方向、订单组、反手次数、盈亏、持仓和挂单；开仓页显示首单方向、循环模式、开单方式、K 线开单模式、多组开关、首单手数和首单手数倍数；距离页显示距离模式、固定距离、K 线范围和止盈移动模式；网格页显示网格数量、网格手数倍数及当前网格只读数据；风控页显示最大反手次数、时间、订单识别编号和订单注释。

- [ ] **Step 2: 实现编辑控件与草稿回写**

所有编辑控件的初始值来自 `g_gui_draft_config`。在 `OnChartEvent` 中只更新草稿，并将 `g_gui_has_unapplied_changes` 设为 true；不得在控件事件中直接调用下单、撤单或改变 `g_gui_applied_config`。

- [ ] **Step 3: 实现专家/简洁模式**

默认 `GUI_MODE_EXPERT`。简洁模式保留首单方向、循环模式、距离模式、首单手数、距离范围/固定距离、时间和底部操作按钮；专家模式显示全部字段。切换模式不删除草稿字段，只改变控件可见性。

- [ ] **Step 4: 实现动态字段显示**

距离模式为固定距离时只显示固定止损/止盈；K 线高度模式显示最小/最大高度、开单方式和 K 线开单模式。高级字段折叠时只隐藏，不重置值。所有字段旁显示中文标签和必要单位（点、手、时:分）。

- [ ] **Step 5: 实现字段校验和应用结果**

点击“应用参数”时按 `ValidateGuiConfig()` 校验手数步进、距离范围、K 线最小/最大高度、网格数量、最大反手次数、时间格式和订单识别编号。失败时在对应字段旁显示错误并保留草稿；成功时复制到已应用配置并显示“已应用；当前订单组锁定参数保持不变，新设置从下一轮生效”。

- [ ] **Step 6: 编译并验证模式切换**

验证专家/简洁切换、固定距离/K 线高度切换、非法值提示和应用成功/失败状态。Expected: 未点击“应用参数”时策略行为和已应用配置不变。

- [ ] **Step 7: 提交 MT5 参数页**

```bash
git add NoMatterRiseFall_MT5.mq5
git commit -m "feat: add MT5 GUI parameter pages"
```

### Task 5: 实现 MT5 总览快照和状态栏

**Files:**
- Modify: `NoMatterRiseFall_MT5.mq5`

- [ ] **Step 1: 定义只读策略快照**

增加 `GuiSnapshot` 结构，字段至少包括运行状态、当前方向、订单组/循环索引、反手次数、最大反手次数、浮动盈亏、持仓数量、挂单数量、首单摘要、反向挂单摘要、网格摘要、最近日志和草稿状态。

- [ ] **Step 2: 实现快照收集**

实现 `GuiSnapshot BuildGuiSnapshot()`，只读取现有策略状态、持仓和挂单查询结果。快照函数不能发送交易请求、修改订单组状态或清除持久化状态。

- [ ] **Step 3: 绘制总览页**

总览页固定显示状态标题、方向、反手次数、订单组、浮动盈亏和持仓/挂单摘要；订单明细与最近 5 条日志使用可折叠区域，不新增左侧导航项。

- [ ] **Step 4: 绘制最小化状态栏**

最小化状态栏显示“ 不管涨跌 EA ”、运行状态、BUY/SELL/无持仓、反手次数和“恢复”按钮。运行状态变化时只更新文本和颜色，不重建完整窗口。

- [ ] **Step 5: 编译并验证异常状态**

分别验证运行中、暂停、清理中、参数错误和重复持仓保护状态。Expected: 颜色和文字与状态一致，异常状态不显示“运行中”。

- [ ] **Step 6: 提交 MT5 总览**

```bash
git add NoMatterRiseFall_MT5.mq5
git commit -m "feat: add MT5 GUI overview snapshot"
```

### Task 6: 实现 MT5 便捷操作和安全确认

**Files:**
- Modify: `NoMatterRiseFall_MT5.mq5`
- Modify: `tests/strategy_logic.py`
- Modify: `tests/test_strategy_logic.py`

- [ ] **Step 1: 写交易命令语义测试**

增加以下测试，确保按钮不直接绕过策略边界：

```python
def test_gui_resume_does_not_force_an_initial_order():
    gui = GuiStateModel(applied={"initial_lots": 0.01})
    gui.pause_new_initial_entry()

    gui.resume_new_initial_entry()

    assert gui.paused_new_initial_entry is False
    assert gui.should_force_market_order is False


def test_gui_close_all_cancel_confirmation_has_no_side_effect():
    gui = GuiStateModel(applied={"initial_lots": 0.01})

    gui.request_close_all()
    result = gui.cancel_close_all()

    assert result.status == "cancelled"
    assert gui.close_all_requested is False
```

- [ ] **Step 2: 实现暂停/恢复命令**

“暂停新首单”只设置 `g_gui_run_state=GUI_RUN_PAUSED_INITIAL`，并在首单入口增加门控；持仓管理、反向预挂单、网格挂单和止盈止损管理继续执行。恢复只清除门控，不强制下单。

- [ ] **Step 3: 实现清仓确认框**

第一次点击“平仓删挂单”只设置 `g_gui_close_confirm_open=true` 并绘制确认框，确认框显示“将关闭本 EA 当前品种和订单识别编号范围内的全部持仓，并删除全部挂单”。取消只关闭确认框；确认后调用现有 `BeginFullReset()`/`ProcessReset()` 清理路径，不复制清仓逻辑。

- [ ] **Step 4: 接入清理结果**

清理未完成时保持 `GUI_RUN_CLEANING`，显示“清理中”和失败数量；只有持仓与挂单均确认清零后才显示成功。任何服务器错误都进入 `GUI_RUN_ERROR` 或最近日志，不显示假成功。

- [ ] **Step 5: 运行测试和编译**

Run: `pytest -q`

Expected: GUI 语义测试和全部策略回归测试 PASS；MT5 编译 0 errors。

- [ ] **Step 6: 提交 MT5 操作命令**

```bash
git add NoMatterRiseFall_MT5.mq5 tests/strategy_logic.py tests/test_strategy_logic.py
git commit -m "feat: add MT5 safe trading controls"
```

### Task 7: 将 MT5 GUI 生命周期接入现有 Tick/ChartEvent

**Files:**
- Modify: `NoMatterRiseFall_MT5.mq5`

- [ ] **Step 1: 实现 `OnChartEvent` 路由**

仅处理带有本 EA 前缀的对象点击和输入事件；导航点击更新 `g_gui_page`，模式切换更新 `g_gui_display_mode`，标题栏按钮处理最小化/隐藏，参数控件更新草稿，操作按钮发出 `GuiCommand`。

- [ ] **Step 2: 调整 `OnTick` 顺序**

每个 Tick 先处理待完成清理和策略管理，再构建只读 GUI 快照；若有状态或草稿变化则局部刷新 GUI。暂停门控放在新首单入口，不得包住当前订单组管理。

- [ ] **Step 3: 增加图表重绘节流**

记录上次快照摘要和渲染时间；当摘要未改变时不重建对象，避免高频行情下不断删除/创建图表对象。参数编辑期间只刷新受影响的字段。

- [ ] **Step 4: 验证重启和关闭行为**

终端重启后先恢复既有策略状态，再创建 GUI；GUI 隐藏或 EA 卸载只清理 GUI 对象，不关闭交易。Expected: 重启窗口不会重复下单。

- [ ] **Step 5: 提交生命周期接入**

```bash
git add NoMatterRiseFall_MT5.mq5
git commit -m "feat: connect MT5 GUI lifecycle"
```

### Task 8: 复制 GUI 语义到 MT4

**Files:**
- Modify: `NoMatterRiseFall_MT4.mq4`

- [ ] **Step 1: 复制配置、状态和页面契约**

使用与 MT5 相同的枚举、`GuiConfig` 字段、`GuiSnapshot` 字段、对象后缀、页面顺序和中文文案。MT4 策略 input 只作为初始值，运行时读取已应用配置。

- [ ] **Step 2: 实现 MT4 图表对象适配**

将 MT5 对象创建、属性设置和事件常量映射为 MT4 可编译 API；保留 `GuiCreate`、`GuiDestroy`、`GuiRender`、`OnChartEvent` 等函数语义一致，平台差异只存在函数体中的 API 调用。

- [ ] **Step 3: 接入 MT4 策略和清理路径**

把暂停门控、配置应用和清仓确认接入现有 MT4 首单入口、订单组管理和清理函数；不修改 MT4 的订单类型、止损止盈和挂单去重规则。

- [ ] **Step 4: 编译 MT4 并做双平台检查**

Expected: MT4 与 MT5 均 0 errors；五个页面、专家/简洁模式、最小化、暂停和二次确认的文字语义一致。

- [ ] **Step 5: 提交 MT4 GUI**

```bash
git add NoMatterRiseFall_MT4.mq4
git commit -m "feat: add MT4 chart GUI"
```

### Task 9: 增加双平台冒烟配置、文档和回归验证

**Files:**
- Create: `mt5_gui_smoke_test.ini`
- Modify: `README.md`
- Modify: `tests/test_strategy_logic.py`

- [ ] **Step 1: 增加 GUI 冒烟测试配置**

创建配置记录当前默认策略参数和 GUI 验证场景：专家模式、默认展开、固定距离、首单 0.01 手、最大反手次数 5、交易时间 08:00-23:00。该文件只供测试器/人工测试，不改变交付 EA 的默认输入。

- [ ] **Step 2: 增加 README GUI 使用章节**

写明：窗口固定图表左上角；完整/最小化；五项导航；专家/简洁模式首次默认专家；参数先草稿后应用；暂停只阻止新首单；清仓删挂单需要二次确认；当前订单组参数锁定，新配置下一轮生效。

- [ ] **Step 3: 增加界面状态回归测试**

覆盖简洁/专家切换不丢草稿、应用失败不改变已应用配置、暂停保留持仓/挂单、取消清仓确认无副作用和清理不完整状态。

- [ ] **Step 4: 运行完整验证**

Run: `pytest -q`

Run: 编译 `NoMatterRiseFall_MT4.mq4` 和 `NoMatterRiseFall_MT5.mq5`。

Run: 在 MT4/MT5 策略测试器执行固定距离、K 线高度、单组、多组、资金不足、最大反手次数和重启恢复场景。

Expected: Python 全部 PASS；双平台编译 0 errors；GUI 操作没有额外开仓/平仓副作用；清仓失败和重复订单状态可见。

- [ ] **Step 5: 检查工作树并提交交付文档**

```bash
git add mt5_gui_smoke_test.ini README.md tests/test_strategy_logic.py
git commit -m "docs: document EA GUI and add smoke checks"
git status --short
```

Expected: 只剩未纳入版本控制的本地可视化伴侣目录（如果存在），EA 源码、测试和文档均已提交。

## 计划自检

- 规格覆盖：窗口布局与最小化由 Tasks 3/8 覆盖；五项导航、总览和专家/简洁模式由 Tasks 4/5/8 覆盖；草稿、应用和当前订单组锁定由 Tasks 1/2/4 覆盖；暂停、清仓确认和失败状态由 Task 6/8 覆盖；MT4/MT5 分层和生命周期由 Tasks 2/7/8 覆盖；错误处理、测试和文档由 Tasks 6/9 覆盖。
- 检查结果：计划步骤均包含明确文件、函数边界、验证命令或验收条件，没有未定义的实现空白。
- 类型一致性：`GuiConfig`、`GuiSnapshot`、`GuiPage`、`GuiDisplayMode`、`GuiRunState` 和 `GuiCommand` 在 MT5 首次定义，MT4 按相同字段契约复制；所有页面和事件任务使用相同命名。
- 范围检查：计划只修改两个 EA、现有 Python 测试和 README，未扩展到独立客户端、远程控制或策略算法重写。
