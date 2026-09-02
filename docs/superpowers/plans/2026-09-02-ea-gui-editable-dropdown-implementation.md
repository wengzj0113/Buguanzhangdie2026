# EA 可编辑下拉框 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将 MT5 GUI 中指定的 11 个参数改为可从常用选项选择、也可键盘输入列表外有效值的可编辑下拉框，并把下拉箭头视觉尺寸放大约 3 倍。

**Architecture:** 保留现有 MQL5 图表对象 GUI、草稿/应用模型和交易策略逻辑。在 `NoMatterRiseFall_MT5.mq5` 内增加统一的可编辑下拉框字段描述、常用选项生成、字段类型校验和编辑会话管理；普通枚举下拉框继续复用现有逻辑。每个可编辑下拉框由输入区和独立箭头按钮组成，选项弹层最后绘制，避免被后续控件遮挡。

**Tech Stack:** MQL5 chart objects (`OBJ_EDIT`, `OBJ_BUTTON`, `OBJ_LABEL`, `OBJ_RECTANGLE_LABEL`), Python `pytest`, MetaEditor CLI, MT5 visual tester.

---

### Task 1: 建立参数选项、自由输入和箭头视觉的失败测试

**Files:**
- Modify: `D:/00_EA/codx-ea/Experts/不管涨跌复刻/tests/test_strategy_logic.py`
- Reference: `D:/00_EA/codx-ea/Experts/不管涨跌复刻/docs/superpowers/specs/2026-09-02-ea-gui-editable-dropdown-design.md`

- [ ] **Step 1: Add failing source-contract tests** for the 11 editable dropdown keys, the exact common option values, a separate arrow object, an arrow font/size contract approximately three times the current arrow, and the rule that these fields use `OBJ_EDIT` while retaining a dropdown overlay.

  The tests must assert these concrete source strings and structures:

  ```python
  editable_keys = [
      "initial_lots", "initial_lots_multiplier",
      "stop_loss_distance_points", "take_profit_distance_points",
      "candle_min_range_points", "candle_max_range_points",
      "grid_count", "grid_lot_multiplier", "max_reversals",
      "start_time", "end_time",
  ]
  for key in editable_keys:
      assert f'"{key}"' in source
  assert "0.03" in source
  assert "GUI_DROPDOWN_ARROW_WIDTH" in source
  assert "GuiCreateDropdownArrow" in source
  assert "OBJPROP_FONTSIZE, 30" in source
  ```

- [ ] **Step 2: Add failing tests** requiring the editable dropdown options to include `0.01` through `0.5` for lots, `1.0/1.2/1.3/1.5/2.0` for the initial multiplier, `100` through `1000` by 100 plus `1500` for distances/heights, `1` through `10` for grid count, `1.0` through `5.0` by `0.5` for grid multiplier, `2` through `20` for reversals, and hourly `00:00` through `23:00` for both time fields.

- [ ] **Step 3: Add failing tests** for the B behavior: a typed value such as `0.07`, `2.25`, `750`, or `08:30` must be accepted by the field validation path when it satisfies existing strategy and symbol rules, while malformed or out-of-range values must be rejected.

- [ ] **Step 4: Run the focused tests** with `python -m pytest tests/test_strategy_logic.py -k "editable_dropdown or dropdown_arrow or gui_input" -q`.

  Expected result: FAIL because the new option tables, arrow helper, and editable-dropdown validation contracts do not yet exist.

- [ ] **Step 5: Commit the red tests**:

  ```powershell
  git add tests/test_strategy_logic.py
  git commit -m "test: define editable dropdown parameter contracts"
  ```

### Task 2: Add one shared editable-dropdown option and field model

**Files:**
- Modify: `D:/00_EA/codx-ea/Experts/不管涨跌复刻/NoMatterRiseFall_MT5.mq5`
- Test: `D:/00_EA/codx-ea/Experts/不管涨跌复刻/tests/test_strategy_logic.py`

- [ ] **Step 1: Add the shared constants and declarations** near the current GUI constants and helper declarations:

  ```mql5
  const int GUI_DROPDOWN_ARROW_WIDTH = 34;
  const int GUI_DROPDOWN_ARROW_FONT_SIZE = 30;
  const int GUI_EDITABLE_OPTION_MAX = 24;
  
  bool GuiIsEditableDropdownKey(const string key);
  int GuiEditableDropdownOptionCount(const string key);
  string GuiEditableDropdownOptionText(const string key, const int index);
  bool GuiParseEditableDropdownValue(const string key, const string value,
                                     string &normalized, string &error);
  bool GuiCreateDropdownArrow(const string name, const int x, const int y,
                              const int width, const int height);
  ```

- [ ] **Step 2: Implement option generation** with deterministic index-to-value mappings:

  - lots: `0.01, 0.02, 0.03, 0.04, 0.05, 0.1, 0.2, 0.3, 0.4, 0.5`;
  - initial multiplier: `1.0, 1.2, 1.3, 1.5, 2.0`;
  - distances/heights: `100, 200, ..., 1000, 1500`;
  - grid count: `1, ..., 10`;
  - grid multiplier: `1.0, 1.5, ..., 5.0`;
  - reversals: `2, ..., 20`;
  - times: `00:00, 01:00, ..., 23:00`.

- [ ] **Step 3: Run the focused tests** and require the option mapping tests to pass before changing rendering.

- [ ] **Step 4: Commit the option model**:

  ```powershell
  git add NoMatterRiseFall_MT5.mq5 tests/test_strategy_logic.py
  git commit -m "feat: add editable dropdown option model"
  ```

### Task 3: Render all 11 parameters as editable fields with a large arrow

**Files:**
- Modify: `D:/00_EA/codx-ea/Experts/不管涨跌复刻/NoMatterRiseFall_MT5.mq5`
- Test: `D:/00_EA/codx-ea/Experts/不管涨跌复刻/tests/test_strategy_logic.py`

- [ ] **Step 1: Add `GuiCreateDropdownArrow`** as a dedicated `OBJ_BUTTON` with a right-side click area of `GUI_DROPDOWN_ARROW_WIDTH`, text `▼`, and `OBJPROP_FONTSIZE` set to `GUI_DROPDOWN_ARROW_FONT_SIZE` so the arrow is visually about three times the current size.

- [ ] **Step 2: Add `GuiRenderEditableDropdownField`** that renders the label, an `OBJ_EDIT` input area whose width excludes the arrow area, and the arrow button at the right edge. The edit object must set `OBJPROP_READONLY=false`, `OBJPROP_SELECTABLE=true`, `OBJPROP_HIDDEN=false`, and `OBJPROP_ZORDER=1000`.

- [ ] **Step 3: Replace the current `GuiRenderEditField` calls** for exactly these keys with `GuiRenderEditableDropdownField`, keeping their existing page positions and labels. Existing enum fields remain regular dropdown buttons.

- [ ] **Step 4: Extend dropdown positioning and overlay rendering** so all 11 editable fields can open an option list on the current page. Render the overlay after all page fields and give its options `OBJPROP_ZORDER=2000`; reserve enough vertical space or clip the list within the content panel without changing the left navigation.

- [ ] **Step 5: Run focused render tests** with `python -m pytest tests/test_strategy_logic.py -k "editable_dropdown or dropdown_arrow" -q` and require PASS.

- [ ] **Step 6: Commit the rendering change**:

  ```powershell
  git add NoMatterRiseFall_MT5.mq5 tests/test_strategy_logic.py
  git commit -m "feat: render gui parameters as editable dropdowns"
  ```

### Task 4: Implement click, keyboard, validation, and draft behavior

**Files:**
- Modify: `D:/00_EA/codx-ea/Experts/不管涨跌复刻/NoMatterRiseFall_MT5.mq5`
- Test: `D:/00_EA/codx-ea/Experts/不管涨跌复刻/tests/test_strategy_logic.py`

- [ ] **Step 1: Add field-name routing** for both `field.<key>` and `field.arrow.<key>` object names, so clicking the input starts an edit session and clicking the large arrow toggles the option overlay for the same key.

- [ ] **Step 2: Preserve native edit focus** by not calling `GuiRender()` for an editable input click. Store the edit-before value, set `g_gui_edit_key`, and only redraw when opening/closing the option list or changing a selected option.

- [ ] **Step 3: Add keyboard session handling** for text entry, replacement, Enter commit, Esc cancel, and focus loss. Synchronize legal text into `g_gui_draft_config`; keep the current edit object alive until the session ends.

- [ ] **Step 4: Route typed values through existing validation** without applying a whitelist. Numeric fields must preserve decimal precision and continue checking finite/positive values, symbol volume min/max/step, distance relationships, and integer constraints. Time fields must accept `HH:MM` from `00:00` to `23:59` and normalize one-digit hours to two digits.

- [ ] **Step 5: Reject invalid input visibly** by keeping the last valid draft value, showing a field-specific notice, and preventing `GuiApplyDraft()` from applying invalid data. Add tests for `0.07`, `2.25`, `750`, `08:30`, empty text, malformed text, invalid time, and minimum/maximum boundary values.

- [ ] **Step 6: Run the full Python suite** with `python -m pytest -q` and require all tests to pass.

- [ ] **Step 7: Commit the interaction change**:

  ```powershell
  git add NoMatterRiseFall_MT5.mq5 tests/test_strategy_logic.py
  git commit -m "fix: support editable dropdown keyboard input"
  ```

### Task 5: Compile, deploy, and verify in MT5

**Files:**
- Modify: `D:/00_EA/codx-ea/Experts/不管涨跌复刻/NoMatterRiseFall_MT5.ex5`
- Modify: `D:/00_EA/codx-ea/Experts/不管涨跌复刻/NoMatterRiseFall_MT5.log`

- [ ] **Step 1: Run the full Python suite**:

  ```powershell
  python -m pytest -q
  ```

  Expected result: zero failures.

- [ ] **Step 2: Compile the main source** using `C:\Program Files\MetaTrader 5\MetaEditor64.exe` with `/compile:<absolute mq5 path> /log`; require `Result: 0 errors, 0 warnings`.

- [ ] **Step 3: Deploy and compare SHA-256 hashes** for the repository EX5 and these two MT5 paths:

  ```text
  C:\Program Files\MetaTrader 5\MQL5\Experts\NoMatterRiseFall_MT5.ex5
  C:\Program Files\MetaTrader 5\MQL5\Experts\不管涨跌复刻\NoMatterRiseFall_MT5.ex5
  ```

- [ ] **Step 4: Run a clean MT5 visual test** on XAUUSD M1 with the tester window visible and paused before interaction. Verify each of the 11 fields can open its dropdown, show complete options, select an option, focus the edit area, replace the value with a legal list-outside value, commit with Enter or focus loss, cancel with Esc, and reject invalid input.

- [ ] **Step 5: Verify regression behavior**: left navigation remains unchanged, overview remains read-only, draft values require “应用参数”, existing-position protection messages remain intact, and no live-account cleanup action is invoked.

- [ ] **Step 6: Run `git diff --check`, inspect `git status --short`, and record the compile result, test count, screenshots, and deployed hashes before declaring completion.

