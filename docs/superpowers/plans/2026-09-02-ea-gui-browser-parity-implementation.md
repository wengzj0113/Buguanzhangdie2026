# EA Browser Parity GUI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rebuild the MT5 chart overlay so its proportions, hierarchy, spacing, and controls closely match `terminal-dark-ui-rendered.html` while preserving the EA's trading logic.

**Architecture:** Keep the existing MQL5 object-based renderer and draft/applied configuration model, but replace the fixed 520px single-column coordinate system with a 760px terminal shell: full-width title bar, 178px navigation rail, and 560px content panel over the chart. Add small layout helpers for two-column forms and shared overview cards so all pages use the same geometry. Keep all UI changes draft-only until “应用参数”.

**Tech Stack:** MQL5 chart objects (`OBJ_RECTANGLE_LABEL`, `OBJ_LABEL`, `OBJ_BUTTON`, `OBJ_EDIT`), Python `pytest` static regression tests, MetaEditor CLI compilation, MT5 visual tester.

---

### Task 1: Lock browser-parity geometry and safety contracts with tests

**Files:**
- Modify: `tests/test_strategy_logic.py`
- Modify: `NoMatterRiseFall_MT5.mq5`

- [ ] **Step 1: Write failing tests** for 760px shell geometry, 178px navigation, 560px content, full-width title bar, two-column field coordinates, complete overview keys, numeric rejection, edit-session preservation, overlay error handling, and Magic Number prefix refresh.
- [ ] **Step 2: Run targeted tests** with `python -m pytest tests/test_strategy_logic.py -k "browser_parity or validation or edit_session or overlay or magic" -q`; confirm the new contracts fail against the current 520px layout.
- [ ] **Step 3: Commit the red tests** with `git add tests/test_strategy_logic.py && git commit -m "test: define browser parity gui contracts"`.

### Task 2: Replace the compressed shell with browser-parity layout primitives

**Files:**
- Modify: `NoMatterRiseFall_MT5.mq5`

- [ ] **Step 1: Add constants/helpers** for `GUI_WINDOW_WIDTH=760`, `GUI_WINDOW_HEIGHT=640`, `GUI_TITLE_HEIGHT=42`, `GUI_NAV_WIDTH=178`, `GUI_CONTENT_WIDTH=560`, content padding 20, and two-column field widths/gaps.
- [ ] **Step 2: Update title/navigation/content/action coordinates** so the title spans 760px, navigation is 178px wide, content begins at x=196 and is 560px wide, and actions remain inside the content panel at its bottom.
- [ ] **Step 3: Add shared two-column render helpers** that create labels and `OBJ_EDIT`/`OBJ_BUTTON` values at stable positions, including dropdown popups that remain inside the content panel.
- [ ] **Step 4: Run the targeted geometry/style tests** and confirm they pass.
- [ ] **Step 5: Commit** with `git add NoMatterRiseFall_MT5.mq5 tests/test_strategy_logic.py && git commit -m "feat: align mt5 gui shell with browser layout"`.

### Task 3: Match browser content hierarchy and complete the overview

**Files:**
- Modify: `NoMatterRiseFall_MT5.mq5`
- Modify: `tests/test_strategy_logic.py`

- [ ] **Step 1: Add tests** requiring the overview to render status, direction, reversals, positions/orders, floating profit, cycle mode, distance mode, order type, initial lots, both lot multipliers, grid count/multiplier, stop/take-profit distances, take-profit mode, schedule, Magic Number, and order comment.
- [ ] **Step 2: Implement the browser hierarchy:** content header, live status badge, three metric cards, two-column summary fields, strategy summary, and bottom action row; keep page labels/counts consistent with the reference (`总览 01`, `开仓 07`, `距离与止盈 06`, `网格 03`, `风控与时段 05`).
- [ ] **Step 3: Render opening/distance/grid/risk pages as two-column forms** using dropdown buttons only for enum values and editable fields only for scalar/text values.
- [ ] **Step 4: Run overview/layout tests** and commit with `git add NoMatterRiseFall_MT5.mq5 tests/test_strategy_logic.py && git commit -m "feat: match browser content hierarchy"`.

### Task 4: Harden editing, validation, overlay lifecycle, and object identity

**Files:**
- Modify: `NoMatterRiseFall_MT5.mq5`
- Modify: `tests/test_strategy_logic.py`

- [ ] **Step 1: Validate edit text before assigning draft values:** reject empty/non-numeric input, preserve the current draft value, set a field-level notice, and do not redraw away the invalid text while the edit is active.
- [ ] **Step 2: Guard redraws during an active edit:** sync only on `CHARTEVENT_OBJECT_ENDEDIT`, preserve `g_gui_edit_key`, and avoid deleting/recreating the active edit object until the edit session ends.
- [ ] **Step 3: Check chart overlay preparation/restoration return values** and surface a visible GUI error when chart property changes fail.
- [ ] **Step 4: Rebuild the object prefix after a valid Magic Number change, clean old prefixes, and keep names below MT5 object-name limits.
- [ ] **Step 5: Run all tests and commit** with `git add NoMatterRiseFall_MT5.mq5 tests/test_strategy_logic.py && git commit -m "fix: harden gui editing and lifecycle"`.

### Task 5: Compile, deploy, and verify the merged-quality artifact

**Files:**
- Modify: `NoMatterRiseFall_MT5.ex5`
- Modify: `NoMatterRiseFall_MT5.log`

- [ ] **Step 1: Run `python -m pytest -q` and require zero failures.**
- [ ] **Step 2: Compile with `C:\Program Files\MetaTrader 5\metaeditor64.exe /compile:<absolute mq5 path> /log` and require `Result: 0 errors, 0 warnings`**.
- [ ] **Step 3: Copy the EX5 to both `C:\Program Files\MetaTrader 5\MQL5\Experts\NoMatterRiseFall_MT5.ex5` and `C:\Program Files\MetaTrader 5\MQL5\Experts\不管涨跌复刻\NoMatterRiseFall_MT5.ex5`; compare SHA-256 hashes**.
- [ ] **Step 4: In MT5 visual tester, verify the full shell proportions, complete overview, page navigation, dropdown open/select, numeric edit, invalid input retention, and apply-draft behavior without using the live-account cleanup action.
- [ ] **Step 5: Run final `git diff --check`, inspect status, then use the finishing-a-development-branch workflow to merge to `main`.
