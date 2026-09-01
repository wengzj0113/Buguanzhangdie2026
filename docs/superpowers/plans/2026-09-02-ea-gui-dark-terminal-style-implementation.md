# 不管涨跌 EA 深色专业交易终端风格 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将现有 MT5 图表 GUI 改造成可读、紧凑、可操作的深色专业交易终端风格，并保持参数编辑、下拉选择、草稿应用和交易安全语义不变。

**Architecture:** 沿用 `NoMatterRiseFall_MT5.mq5` 中现有 GUI 生命周期和状态模型，不拆分大文件。新增集中式 GUI 颜色/尺寸常量与少量渲染辅助函数，统一替换散落的颜色和控件样式；继续由现有 `GuiRender*` 函数负责视图，由 `OnChartEvent` 负责交互。Python 静态契约测试负责保证所有页面字段、控件类型、布局边界和图表遮罩生命周期不回退。

**Tech Stack:** MQL5 图表对象（`OBJ_RECTANGLE_LABEL`、`OBJ_LABEL`、`OBJ_BUTTON`、`OBJ_EDIT`）、MetaEditor 编译器、Python `pytest`。

---

## 文件结构和职责

- Modify: `NoMatterRiseFall_MT5.mq5:3450-4700` — GUI 颜色、字体、布局、状态展示和控件绘制；不改交易算法。
- Modify: `tests/test_strategy_logic.py:1-240` — GUI 风格与布局的静态契约测试，并保留已有交互回归测试。
- Create: `docs/superpowers/plans/2026-09-02-ea-gui-dark-terminal-style-implementation.md` — 本实施计划。
- Build output: `NoMatterRiseFall_MT5.ex5` — 由 MetaEditor 重新编译生成，不手工编辑。

### Task 1: 先建立深色终端样式的失败测试

**Files:**
- Modify: `tests/test_strategy_logic.py:1-240`
- Test: `tests/test_strategy_logic.py`

- [ ] **Step 1: 写失败测试，锁定样式和布局契约**

在现有测试文件中加入以下测试；测试读取 `NoMatterRiseFall_MT5.mq5`，先要求尚未存在的集中式样式函数和新的布局标记：

```python
def test_mt5_gui_uses_dark_terminal_palette_and_readable_controls():
    source = read_source()
    assert "color GuiColorPanel()" in source
    assert "color GuiColorSurface()" in source
    assert "color GuiColorInput()" in source
    assert "color GuiColorPrimary()" in source
    assert "color GuiColorDanger()" in source
    assert "OBJPROP_FONTSIZE, 10" in source
    assert "GuiColorInput()" in source
    assert "GuiColorPrimary()" in source
    assert "GuiColorDanger()" in source


def test_mt5_gui_has_terminal_header_context_and_overview_summary():
    source = read_source()
    title = re.search(r"bool GuiRenderTitleBar\(\).*?\n\s*\}", source, re.S).group(0)
    overview = re.search(r"bool GuiRenderContent\(\).*?\n\s*\}\n\s*bool GuiRenderActions", source, re.S).group(0)
    assert "GuiSymbolPeriodText()" in title
    for key in ("overview.state", "overview.direction", "overview.positions",
                "overview.orders", "overview.profit", "overview.reversal",
                "overview.cycle_mode", "overview.distance_mode",
                "overview.initial_lots", "overview.grid_count",
                "overview.stops", "overview.schedule"):
        assert key in overview


def test_mt5_gui_layout_keeps_panel_and_actions_inside_window():
    source = read_source()
    render = re.search(r"bool GuiRender\(\).*?\n\s*\}\n\s*void GuiDestroy", source, re.S).group(0)
    assert "520, 580" in render
    assert 'const int y = 570' in source
    assert 'GuiCreateButton(g_gui_object_prefix + "apply"' in source
    assert 'GuiCreateButton(g_gui_object_prefix + "pause"' in source
    assert 'GuiCreateButton(g_gui_object_prefix + "close"' in source


def test_mt5_gui_uses_dropdowns_for_enum_parameters_and_edits_for_values():
    source = read_source()
    content = re.search(r"bool GuiRenderContent\(\).*?\n\s*\}\n\s*bool GuiRenderActions", source, re.S).group(0)
    for key in ("first_direction", "cycle_mode", "order_type", "candle_order_mode",
                "candle_enable_multiple", "distance_mode", "take_profit_mode"):
        assert f'GuiRenderEnumField("{key}"' in content
    for key in ("initial_lots", "initial_lots_multiplier", "grid_count",
                "grid_lot_multiplier", "max_reversals", "magic_number", "order_comment"):
        assert f'GuiRenderEditField("{key}"' in content


def test_mt5_gui_keeps_dropdowns_and_edits_above_chart_objects():
    source = read_source()
    assert "ObjectSetInteger(0, name, OBJPROP_ZORDER, 1000);" in source
    assert "ObjectSetInteger(0, name, OBJPROP_ZORDER, 2000);" in source
    assert "CHART_SHOW_TRADE_LEVELS" in source
    assert "CHART_SHOW_TRADE_HISTORY" in source
```

- [ ] **Step 2: 运行新增测试，确认先红**

Run:

```powershell
python -m pytest tests/test_strategy_logic.py -k "dark_terminal_palette or terminal_header_context or layout_keeps_panel or uses_dropdowns or keeps_dropdowns" -q
```

Expected: 至少 `test_mt5_gui_uses_dark_terminal_palette_and_readable_controls` 因集中式样式函数不存在而失败；如果其他断言已经被现有实现满足，保持其结果并只修正真正缺失的样式契约。

## Task 2: 实现集中式深色终端视觉系统

**Files:**
- Modify: `NoMatterRiseFall_MT5.mq5:3450-3570`
- Test: `tests/test_strategy_logic.py`

- [ ] **Step 1: 添加最小样式函数让测试进入绿色**

在 `GuiSetObjectBase` 前加入固定深色主题的函数，所有函数返回 `color`，避免在渲染函数中继续散落颜色字面量：

```mql5
color GuiColorBackground() { return C'7,11,18'; }
color GuiColorPanel()      { return C'16,26,42'; }
color GuiColorSurface()    { return C'22,36,58'; }
color GuiColorInput()      { return C'11,21,37'; }
color GuiColorBorder()     { return C'59,90,126'; }
color GuiColorText()       { return C'237,245,255'; }
color GuiColorMuted()      { return C'142,168,196'; }
color GuiColorPrimary()    { return C'40,118,240'; }
color GuiColorSuccess()    { return C'54,217,138'; }
color GuiColorWarning()    { return C'231,189,103'; }
color GuiColorDanger()     { return C'119,31,39'; }
```

将 `GuiCreateButton` 的字体改为 10 号，并将默认边框、背景、文字颜色改用 `GuiColorBorder()`、`GuiColorSurface()` 和 `GuiColorText()`。将 `GuiCreateEdit` 的背景、边框、文字颜色改用 `GuiColorInput()`、`GuiColorBorder()` 和 `GuiColorText()`。下拉选项继续保留选中项主蓝色，未选中项使用输入背景。

- [ ] **Step 2: 运行样式测试，确认绿色**

Run:

```powershell
python -m pytest tests/test_strategy_logic.py -k "dark_terminal_palette or keeps_dropdowns" -q
```

Expected: 相关测试通过。

- [ ] **Step 3: 统一标题栏、导航栏、内容区和操作区配色**

将以下函数中的颜色替换为集中式颜色函数，并保留当前对象名称和交互语义：

- `GuiRenderTitleBar`：标题栏用 `GuiColorPanel()`，标题和上下文用 `GuiColorText()`/`GuiColorMuted()`，运行状态用 `GuiColorSuccess()`，错误用 `GuiColorDanger()`。
- `GuiRenderNavigation`：导航底板用 `GuiColorInput()`，当前项用 `GuiColorPrimary()`，未选中项使用输入背景和辅助文字。
- `GuiRenderContent`：内容底板用 `GuiColorSurface()`，字段标签使用 `GuiColorMuted()`，页面标题使用 `GuiColorText()`，模式提示使用 `GuiColorWarning()` 或 `GuiColorMuted()`。
- `GuiRenderActions`：应用使用 `GuiColorPrimary()`，暂停使用 `GuiColorSurface()`，清理使用 `GuiColorDanger()`。
- `GuiRenderNotice`：错误使用高对比红色，成功/普通提示使用绿色。

不得改变 `g_gui_object_prefix`、`g_gui_dropdown_key`、`g_gui_edit_key`、`GuiHandleDropdownClick` 或 `GuiSyncEditValue` 的语义。

## Task 3: 完善终端头部和总览信息层级

**Files:**
- Modify: `NoMatterRiseFall_MT5.mq5:3560-4060`
- Test: `tests/test_strategy_logic.py`

- [ ] **Step 1: 添加品种/周期显示函数并测试其调用**

新增 `GuiSymbolPeriodText()`，用 `_Symbol` 与 `_Period` 生成稳定文本；至少为 `PERIOD_M1`、`PERIOD_M5`、`PERIOD_M15`、`PERIOD_H1` 和其他周期提供可读回退值。标题栏新增一个只读文本对象，显示 `XAUUSD · M1` 形式的上下文。

```mql5
string GuiSymbolPeriodText()
  {
   string period = EnumToString(_Period);
   StringReplace(period, "PERIOD_", "");
   return _Symbol + " · " + period;
  }
```

标题栏状态必须仍使用 `GuiRunStateText()`；不把状态文本硬编码为“运行中”。

- [ ] **Step 2: 扩展总览页为可快速扫描的只读摘要**

保留现有字段键，并补充/整理以下摘要：持仓、挂单、浮盈、订单组/循环、反手次数、当前方向、循环模式、距离模式、开单方式、首单手数、网格数量、止损/止盈、运行时间、Magic Number 和订单备注。摘要控件全部使用 `GuiRenderReadOnlyField`，不伪装成可编辑输入。

总览页必须在 `content` 区域内完成渲染，底部提示不得覆盖操作区；若提示为空仍保留稳定布局。

- [ ] **Step 3: 运行总览和字段契约测试**

Run:

```powershell
python -m pytest tests/test_strategy_logic.py -k "terminal_header_context or layout_keeps_panel or uses_dropdowns" -q
```

Expected: 相关测试通过。

## Task 4: 保证控件可编辑且布局不被重绘破坏

**Files:**
- Modify: `NoMatterRiseFall_MT5.mq5:3690-4670`
- Test: `tests/test_strategy_logic.py`

- [ ] **Step 1: 增加字段坐标和焦点行为的静态契约**

新增测试确保：

```python
def test_mt5_gui_edit_session_is_not_rebuilt_while_typing():
    source = read_source()
    event = re.search(r"void OnChartEvent\(.*?\n\s*\}", source, re.S).group(0)
    assert "g_gui_edit_key" in source
    assert "CHARTEVENT_KEYDOWN" in event
    assert "GuiSyncEditValue(g_gui_edit_key)" in event
    assert "CHARTEVENT_OBJECT_ENDEDIT" in event
```

已有 dropdown z-order、坐标回退和图表遮罩测试必须继续保留。

- [ ] **Step 2: 统一字段宽度和纵向间距**

继续使用 `value_x = x + 166`、`value_width = 236` 和 24px 控件高度；页面字段以 30px 为最小行距，长文本/备注占满可用宽度。标题栏、内容区、导航区和操作区保持在 `520x580` 外框内：操作按钮起始 y=570，高度 28，不得被内容对象覆盖。

- [ ] **Step 3: 修复控件样式而不改变交互路径**

确认以下路径仍然成立：

- 枚举字段：`GuiRenderEnumField` → `GuiRenderDropdownField` → `GuiHandleDropdownClick` → `GuiSetDropdownValue` → `GuiMarkDraftChanged`。
- 可编辑字段：`GuiRenderEditField` → `GuiCreateEdit` → `CHARTEVENT_OBJECT_CLICK` 设置 `g_gui_edit_key` → `CHARTEVENT_KEYDOWN`/`CHARTEVENT_OBJECT_ENDEDIT` 调用 `GuiSyncEditValue`。
- 页面导航：`GuiHandlePageClick` 修改 `g_gui_page` 后标记 GUI dirty。

不要用 `OBJPROP_READONLY=true`、重建期间强制覆盖编辑值或把枚举字段降级为文本标签。

- [ ] **Step 4: 运行完整Python测试**

Run:

```powershell
python -m pytest -q
```

Expected: 全部已有策略和GUI契约测试通过。

## Task 5: 编译、部署和真实终端验证

**Files:**
- Build: `NoMatterRiseFall_MT5.mq5` → `NoMatterRiseFall_MT5.ex5`
- Deploy: `C:\Program Files\MetaTrader 5\MQL5\Experts\NoMatterRiseFall_MT5.ex5`
- Deploy: `C:\Program Files\MetaTrader 5\MQL5\Experts\不管涨跌复刻\NoMatterRiseFall_MT5.ex5`

- [ ] **Step 1: 使用 MetaEditor 编译并检查日志**

运行已验证的 MetaEditor 编译命令，读取编译日志，要求 `0 errors, 0 warnings`。如果编译失败，先修复源码并重复编译，不部署不完整的 EX5。

- [ ] **Step 2: 部署编译产物并比对哈希**

复制到两个 MT5 Experts 目标路径，分别计算 SHA-256，要求与工作区编译产物一致。不得删除用户已有日志、模板或交易数据。

- [ ] **Step 3: 在本机MT5图表上验证视觉状态**

使用 `C:\Program Files\MetaTrader 5\terminal64.exe` 对 XAUUSD M1 图表验证：

1. GUI 默认左上角显示，标题栏、导航、内容和底部按钮完整可见。
2. 图表箭头和水平交易线不会覆盖GUI对象。
3. 五个页面可切换，当前页有蓝色选中态。
4. 每个枚举字段可以打开下拉菜单并切换值。
5. 数字/时间/备注文本框可以获得焦点、替换文本，输入不会被 Tick 刷新覆盖。
6. 修改后显示未应用状态，点击应用参数后显示结果。
7. 最小化/恢复保留当前页面和草稿状态。

不得为了验证而关闭或清理用户当前持仓、挂单；平仓删挂单只验证确认框的取消路径。

- [ ] **Step 4: 保存验证证据**

记录 `pytest` 输出、MetaEditor 编译日志、部署哈希和MT5截图/日志中的GUI状态。任何无法在真实终端确认的行为都不得宣称已完成。

## Task 6: 提交和最终审计

**Files:**
- Modify: `NoMatterRiseFall_MT5.mq5`
- Modify: `tests/test_strategy_logic.py`
- Build: `NoMatterRiseFall_MT5.ex5`
- Review: `git diff` 和工作区状态

- [ ] **Step 1: 检查差异只包含本任务和既有GUI修复**

运行：

```powershell
git diff --check
git status --short
git diff --stat
```

确认没有修改策略算法、交易数据或用户终端目录中的无关文件。

- [ ] **Step 2: 重新运行全量验证**

```powershell
python -m pytest -q
```

再次确认 MetaEditor 编译日志为 `0 errors, 0 warnings`，并确认部署文件哈希一致。

- [ ] **Step 3: 提交实现**

```powershell
git add -- NoMatterRiseFall_MT5.mq5 tests/test_strategy_logic.py NoMatterRiseFall_MT5.ex5
git commit -m "feat: refresh MT5 GUI with dark terminal style"
```

- [ ] **Step 4: 完成要求审计**

逐项对照设计规格：深色专业终端配色、总览信息完整、枚举下拉、文本编辑、控件层级、图表遮罩、最小化/恢复、交易安全和自动测试。只有所有项目都有当前终端或命令输出证据时，才报告完成。
