# Favorable Grid Enable Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Add a `FavorableGridEnable` switch that optionally places the same number of grid additions in the profitable direction, with all user-visible MT5 labels in Chinese.

**Architecture:** Extend the existing grid level model with a direction side (`adverse` or `favorable`) while preserving the current adverse-side price and order rules. Store each side's filled mask and pending level in single-group and multi-group state, and route both MT4 and MT5 through the same side-aware reconciliation behavior.

**Tech Stack:** MQL4, MQL5, Python, pytest, MetaEditor command-line compilation, Markdown.

---

### Task 1: Add failing behavior tests

**Files:**
- Modify: `tests/strategy_logic.py`
- Modify: `tests/test_strategy_logic.py`

- [ ] **Step 1: Add a model switch and write red tests**

Add tests for a buy group and a sell group proving `favorable_grid_enable=0` has no profitable-direction grid pending, while `favorable_grid_enable=1` creates exactly `grid_count - 1` profitable-direction levels with the same grid lot size. Also add a test that the existing adverse-direction levels remain unchanged.

- [ ] **Step 2: Run the focused tests and verify RED**

Run `python -m pytest tests/test_strategy_logic.py -q -k favorable_grid`. The expected failure is an unexpected constructor keyword or missing profitable-direction grid pending, not a test collection error.

- [ ] **Step 3: Add model side-aware grid state**

Extend the model with `favorable_grid_enable=0`, separate favorable grid pending records and filled levels, and create profitable-direction pending levels only when the switch is `1`. Keep the existing adverse `grid_pending` compatibility properties and lot calculations unchanged.

- [ ] **Step 4: Run focused and full tests**

Run `python -m pytest tests/test_strategy_logic.py -q -k favorable_grid` and then `python -m pytest -q`; both must pass.

### Task 2: Add parameters and state to MT4

**Files:**
- Modify: `NoMatterRiseFall_MT4.mq4`
- Modify: `README.md`

- [ ] **Step 1: Add the input and validation**

Add the visible input `input int 有利方向加单 = 0;` next to the existing grid inputs and define the internal alias `#define FavorableGridEnable 有利方向加单`. Reject values other than `0` and `1` in `OnInit`.

- [ ] **Step 2: Extend single-group and multi-group grid state**

Add favorable-side filled-mask, filled-count, pending-level, and pending-price fields to the existing state structures. Save, load, reset, and delete those fields with backward-compatible defaults of zero.

- [ ] **Step 3: Implement favorable-side price and order handling**

For a buy position, create favorable grid levels above the anchor with same-direction pending orders (normally `OP_BUYSTOP`); for a sell position, create levels below the anchor with same-direction pending orders (normally `OP_SELLSTOP`). Reuse the configured grid count and grid lot size, and add the favorable side to reconciliation and fill detection only when `FavorableGridEnable == 1`.

- [ ] **Step 4: Update MT4 documentation and source contract tests**

Document the switch as “有利方向加单” with values `0/1`, and assert the MT4 source has the input, validation, and side-aware grid marker.

### Task 3: Add parameters, state, and Chinese MT5 UI

**Files:**
- Modify: `NoMatterRiseFall_MT5.mq5`
- Modify: `tests/test_strategy_logic.py`

- [ ] **Step 1: Add input, GUI config, validation, and fingerprint**

Load the Chinese visible input through the `FavorableGridEnable` alias into `GuiConfig`, include it in configuration identity and validation, and keep the default at zero.

- [ ] **Step 2: Expose the setting entirely in Chinese**

Add a dropdown or enum field whose visible label is exactly “有利方向加单” and whose choices are “关闭” and “开启”. Add the same Chinese label/value to the read-only overview; do not render `FavorableGridEnable` as a user-facing English label.

- [ ] **Step 3: Extend single-group and multi-group state**

Persist favorable-side grid masks and pending metadata, initialize missing fields to zero, and keep old compiled state recoverable.

- [ ] **Step 4: Implement and reconcile the favorable side**

Mirror the MT4 side-aware rules in single-group and multi-group grid placement, normalization, fill detection, duplicate cleanup, and restart recovery. The existing adverse path must remain active regardless of the new switch.

- [ ] **Step 5: Add MT5 source-contract assertions**

Assert that the source contains the default input, Chinese UI label and choice text, validation, persistence, and favorable-side grid placement marker.

### Task 4: Compile, verify, and deliver

**Files:**
- Modify: `NoMatterRiseFall_MT4.ex4`
- Modify: `NoMatterRiseFall_MT5.ex5`
- Modify: `NoMatterRiseFall_MT4.log`
- Modify: `NoMatterRiseFall_MT5.log`

- [ ] **Step 1: Run all automated verification**

Run `python -m pytest -q` and `git diff --check`. Confirm the full test suite has zero failures.

- [ ] **Step 2: Compile both experts**

Run MetaEditor with `/compile:"D:\00_EA\codx-ea\Experts\不管涨跌复刻\NoMatterRiseFall_MT5.mq5" /log` and the MT4 equivalent. Confirm MT5 has `0 errors, 0 warnings` and MT4 has `0 errors`.

- [ ] **Step 3: Sync the compiled files**

Copy the compiled MT5 file to the active `MetaTrader 5\MQL5\Experts` folder and the compiled MT4 file to the active `FXGiants MetaTrader 4\MQL4\Experts` folder, then verify source and deployed binary hashes match.

- [ ] **Step 4: Commit the implementation**

Commit source, tests, documentation, and compiled artifacts with a focused message describing the favorable-direction grid switch.
