# First Order Lot Type Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add selectable stop-loss follow-up first-order lot sizing while preserving the existing algorithm as type 1 and making type 2 the default.

**Architecture:** Introduce one calculation helper per platform that branches on `FirstOrderLotType`, and persist the current group’s first-order lot in both single-group and multi-group state. Route pending reversal, direct market reversal, prepared-transition recovery, and Python model behavior through the same semantic formulas.

**Tech Stack:** MQL4, MQL5, Python 3, pytest, Markdown documentation.

---

### Task 1: Add failing behavior tests

**Files:**
- Modify: `tests/strategy_logic.py`
- Modify: `tests/test_strategy_logic.py`

- [ ] **Step 1: Add a type-2 regression test**

Create a model with `initial_lots=0.01`, one filled grid lot so the stopped group total is `0.03`, `first_order_lot_type=2`, and `first_order_mult=2.0`. Assert the next stop transition opens `0.02` lots, not `0.06`.

- [ ] **Step 2: Add a consecutive type-2 regression test**

After the first type-2 transition, stop the new group and assert the next first order is twice the immediately previous group first order. The result must not depend on the prior group’s grid additions or cumulative stopped total.

- [ ] **Step 3: Add a type-1 compatibility test**

With the same group totals, set `first_order_lot_type=1` and `initial_lot_multiplier=1.0`; assert the next first order remains the accumulated stopped-group total.

- [ ] **Step 4: Add source-contract checks**

Assert both MQL sources contain the new parameters, a type branch, persisted first-order-lot state, and the type-2 formula marker. Assert the default values are `2` and `2.0`.

- [ ] **Step 5: Run the focused tests and verify RED**

Run `python -m pytest tests/test_strategy_logic.py -q`. The new tests must fail because the model and MQL sources do not yet implement the new parameters.

### Task 2: Implement the Python behavior model

**Files:**
- Modify: `tests/strategy_logic.py`
- Modify: `tests/test_strategy_logic.py`

- [ ] **Step 1: Add constructor defaults and current-group first-lot state**

Add `first_order_lot_type=2` and `first_order_mult=2.0` parameters, preserve positional compatibility by appending them, and initialize `group_first_lots` from the actual opening lot.

- [ ] **Step 2: Add the unified next-first-lot helper**

Implement:

```python
def _next_first_lots(self):
    if self.first_order_lot_type == 2:
        return self.group_first_lots * self.first_order_mult
    return (self.cumulative_loss_lots + self.group_total_lots) * self.initial_lot_multiplier
```

Use it for both pending and direct stop transitions.

- [ ] **Step 3: Update transitions and reset paths**

When a new group opens, save its actual first-order lots. Do not change initial independent K-line group creation, which continues to use `initial_lots`. Clear the field on full reset.

- [ ] **Step 4: Run focused and full Python tests**

Run `python -m pytest tests/test_strategy_logic.py -q` and then `python -m pytest -q`; fix only implementation or test compatibility failures.

### Task 3: Implement MT4 parameters, state, and formulas

**Files:**
- Modify: `NoMatterRiseFall_MT4.mq4`
- Modify: `README.md`

- [ ] **Step 1: Add validated MT4 inputs**

Add `input int FirstOrderLotType = 2;` and `input double FirstOrderMult = 2.0;`, expose aliases if needed by the existing naming pattern, and reject values other than 1/2 or non-positive/non-finite multipliers in `OnInit` validation.

- [ ] **Step 2: Add persisted first-order-lot state**

Add the single-group field and `MultiGroupState` field, save/load/clear them with backward-compatible fallback to current group total or actual first position volume.

- [ ] **Step 3: Add the unified MT4 helper**

Branch type 1 through the existing cumulative formula and type 2 through `group_first_lots * FirstOrderMult`, then call it from `NextGroupLots`, direct `Transition`, prepared recovery, and all multi-group reversal paths.

- [ ] **Step 4: Set the field on every new group**

Record the actual normalized volume after the initial market order or initial pending fill becomes a position. Keep independent K-line group creation on the base `首单手数`.

- [ ] **Step 5: Update README and run source-contract tests**

Document both parameters and formulas, then run the focused tests before compiling if a MetaEditor compiler is available.

### Task 4: Implement MT5 parameters, GUI, state, and formulas

**Files:**
- Modify: `NoMatterRiseFall_MT5.mq5`
- Modify: `README.md`

- [ ] **Step 1: Add MT5 inputs and GuiConfig fields**

Add the two input values, load them into `GuiConfig`, include them in configuration serialization/signature and validation, and expose editable GUI fields with draft/applied handling.

- [ ] **Step 2: Add persisted first-order-lot state**

Extend single-group and `MultiGroupState` save/load/reset logic with a backward-compatible fallback, and initialize it from actual normalized entry volume.

- [ ] **Step 3: Add the unified MT5 helper**

Use type 1 for the old cumulative formula and type 2 for previous-group-first-lot times `FirstOrderMult`. Route `NextGroupLots`, `Transition`, `ResumePreparedTransition`, `MultiNextGroupLots`, and multi-group stop reversal through it.

- [ ] **Step 4: Update GUI labels and overview**

Show the applied values in the overview and allow editing in the same parameter page as the existing first-order lot fields. Keep applying changes from affecting active groups beyond the existing configuration behavior.

- [ ] **Step 5: Run Python/source-contract tests and inspect MT5 diff**

Run `python -m pytest -q` and inspect all changed MT5 paths for formula consistency.

### Task 5: Verify and commit

**Files:**
- Modify: `docs/superpowers/specs/2026-09-10-first-order-lot-type-design.md`
- Modify: `docs/superpowers/plans/2026-09-10-first-order-lot-type-implementation.md`
- Modify: `NoMatterRiseFall_MT4.mq4`
- Modify: `NoMatterRiseFall_MT5.mq5`
- Modify: `tests/strategy_logic.py`
- Modify: `tests/test_strategy_logic.py`
- Modify: `README.md`

- [ ] **Step 1: Run verification**

Run `python -m pytest -q`, inspect `git diff --check`, and run the available MT4/MT5 compiler commands or report if MetaEditor is unavailable.

- [ ] **Step 2: Review the complete diff**

Confirm type 1 is unchanged semantically, type 2 uses the previous group first lot, independent new K-line groups use base lots, and no generated binaries/logs were unintentionally changed.

- [ ] **Step 3: Commit the implementation**

Create focused commits for tests/model and MQL/documentation changes, or one cohesive commit if the repository workflow requires atomic changes.
