# Simultaneous Grid Pending Orders Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make every unfilled internal grid level pending at the same time, while preserving the existing interval-count semantics and keeping remaining grid orders after any one level fills.

**Architecture:** Replace the single “next grid level” state machine with a per-level filled mask for the single group and each parallel group. Ensure functions will iterate levels 1 through `grid_count - 1`, use level-aware order matching/normalization, and only update the filled bit for the level whose order was filled. Keep the existing group-wide pending deletion paths for take-profit, stop-loss, reversal, reset, and insufficient-funds cleanup.

**Tech Stack:** MQL4, MQL5, Python 3, pytest, MetaEditor command-line compilation.

---

### Task 1: Add red tests for simultaneous grid placement

**Files:**
- Modify: `tests/strategy_logic.py:254-510`
- Modify: `tests/test_strategy_logic.py:892-1020`
- Modify: `tests/test_strategy_logic.py` source-contract section near the existing `EnsureGridPending` assertions

- [ ] **Step 1: Add a test for all internal levels on initial placement**

Add a `StrategyModel(grid_count=5)` test that calls `on_tick()` once and collects `kind == "grid_pending"` actions. Assert there are four actions, with levels `[1, 2, 3, 4]`, unique prices at each interval, and the expected direction/order types.

- [ ] **Step 2: Add a test for an arbitrary fill retaining the other levels**

Expose the model operation as `fill_grid_pending(level=2)` (or the equivalent smallest testable API), fill only level 2, and assert the model still contains levels 1, 3, and 4. Call `on_tick()` again and assert no duplicate `grid_pending` action is produced and no new level is created.

- [ ] **Step 3: Update the N=2 regression assertion**

Keep the existing interval semantic test: `grid_count=2` creates only level 1 and, after it fills, has no remaining grid pending order.

- [ ] **Step 4: Add source-contract assertions for both platforms**

Read both MQ source files in the existing source contract tests. Assert the single-group and multi-group ensure/place functions contain a loop over internal grid levels and the old sole-chain expression `filled_levels + 1` is not the only placement path. Assert both source files contain persistent per-level state and a level-aware grid normalization/find helper.

- [ ] **Step 5: Run the focused tests and verify the expected red failure**

Run:

```powershell
python -m pytest tests/test_strategy_logic.py -q
```

Expected: the new simultaneous-placement and retained-level tests fail because the model currently exposes only one `grid_pending` and advances only to `filled_levels + 1`; unrelated baseline tests remain green.

### Task 2: Extend the Python behavior model to represent multiple grid orders

**Files:**
- Modify: `tests/strategy_logic.py:300-510,536-731`
- Modify: `tests/test_strategy_logic.py:892-1020`

- [ ] **Step 1: Replace the single grid pending field with a level map while keeping compatibility helpers**

Store pending grid orders by level, for example `self.grid_pendings: dict[int, Pending]`, initialize it empty in every reset/start path, and provide a deterministic action conversion that returns actions ordered by ascending level. If existing tests or callers inspect `grid_pending`, make it a compatibility property returning the lowest active level rather than using it as the source of truth.

- [ ] **Step 2: Implement all-level ensure behavior**

Change `_ensure_grid_pending()` to iterate `range(1, self.grid_count)`, skip levels already marked filled or present in the map, compute each level’s price/order type, and add every missing `Pending`. Return the collection of newly created/current pending records needed by `on_tick()` rather than one record.

- [ ] **Step 3: Make fill selection level-specific**

Change `fill_grid_pending()` to accept an optional level or price, select that exact pending record, remove only it, mark that level filled, update total lots/entry/stops/TP, and call `_ensure_grid_pending()` without deleting the other pending records. Preserve the existing default behavior for old tests by selecting the lowest active level when no selector is supplied.

- [ ] **Step 4: Update action-producing paths**

Update initial entry, reversal, pending-transition, and ordinary tick paths so they append all currently active grid pending actions. Ensure take-profit, stop-loss, reversal, no-money, and reset paths clear the whole map.

- [ ] **Step 5: Run focused tests and then the full Python suite**

Run:

```powershell
python -m pytest tests/test_strategy_logic.py -q
python -m pytest -q
```

Expected: new tests and all existing tests pass. Any old assertion that assumed a single `grid_pending` must be updated to assert the compatibility lowest level or the full level collection without changing production requirements.

### Task 3: Implement per-level simultaneous grid state in MT4

**Files:**
- Modify: `NoMatterRiseFall_MT4.mq4:154-388` state persistence/reset/load functions
- Modify: `NoMatterRiseFall_MT4.mq4:735-830` pending discovery/normalization helpers
- Modify: `NoMatterRiseFall_MT4.mq4:1371-1454` single-group grid placement/fill/ensure functions
- Modify: `NoMatterRiseFall_MT4.mq4:1940-2200,2570-2665, multi-group persistence and grid functions`

- [ ] **Step 1: Add a persisted filled-level mask**

Add a mask field for the single group and `MultiGroupState`, persist it beside the existing grid fields, load it with backward-compatible default zero, and clear it wherever a new group, reversal group, reset, or no-money reset clears `g_grid_filled_levels`. Retain `g_grid_filled_levels` only as a derived/legacy count if existing display/state code needs it.

- [ ] **Step 2: Add level-aware pending discovery**

Implement helpers that search an order belonging to the current group and grid level using the new level marker in the comment plus expected direction/price/volume, while accepting the legacy `.Grid` comment when the expected price identifies the level. A per-level normalizer must delete only duplicate orders for that level and must leave other levels untouched; do not call `NormalizeSingleGroupPending(true, ...)` for the multi-level grid path.

- [ ] **Step 3: Tag each placed MT4 grid order with its level**

Extend the grid comment from the generic `.Grid` marker to include the level, while keeping `IsGridPendingComment()` compatible with both formats. Persist the returned ticket/price only as compatibility metadata; the mask and level-aware scans are authoritative.

- [ ] **Step 4: Replace single-group chain placement**

Make `EnsureGridPending(position_type)` loop from level 1 to `InpGridCount - 1`, skip filled levels, normalize/find that level, and call `PlaceGridPending(position_type, level)` only when that level is missing. Do not delete other levels when one level is normalized.

- [ ] **Step 5: Detect and process individual fills**

Make `HandleGridFill()` inspect each unfilled level’s tracked/current/history order state, identify the level whose grid order filled, and update only that bit, total lots, last entry, and stops/TP. If multiple levels filled between ticks, process each filled level without overwriting prior bits. A canceled or deleted pending must not be marked filled solely because it disappeared.

- [ ] **Step 6: Apply the same behavior to multi-group MT4**

Update `MultiPlaceGridPending()` to iterate all internal levels, use group-specific level matching, and leave other levels intact. Update `MultiHandleGridFill()` and multi-group save/load/reset paths to use the group mask and preserve all active grid orders.

- [ ] **Step 7: Compile MT4 in the feature worktree and inspect compiler output**

Run the repository’s existing MetaEditor compile command for `NoMatterRiseFall_MT4.mq4`. Expected: exit code 0, no errors, and no warnings beyond the two existing `OrderDelete` warnings recorded in the baseline log.

### Task 4: Port the exact behavior to MT5

**Files:**
- Modify: `NoMatterRiseFall_MT5.mq5:154-450` state persistence/reset/load functions
- Modify: `NoMatterRiseFall_MT5.mq5:1670-1810` pending discovery/normalization helpers
- Modify: `NoMatterRiseFall_MT5.mq5:2386-2520` single-group grid placement/fill/ensure functions
- Modify: `NoMatterRiseFall_MT5.mq5:2990-3805, multi-group persistence and grid functions`

- [ ] **Step 1: Mirror the persisted mask and compatibility migration**

Add the single-group and `MultiGroupState` mask fields, save/load/clear them with the same keys and zero-default migration behavior as MT4.

- [ ] **Step 2: Mirror level-aware order matching and comments**

Use MT5 order/history APIs to find one active or filled order for an expected group/level, recognize both new level-tagged comments and legacy `.Grid`, and normalize duplicates for only the selected level.

- [ ] **Step 3: Mirror all-level placement and individual fill handling**

Loop through levels 1 to `grid_count - 1` in both single-group and multi-group ensure/place paths. Process fills per level, keep remaining pending orders, and retain all group-wide deletion behavior.

- [ ] **Step 4: Compile MT5 and compare the MT4/MT5 behavior paths**

Run the existing MetaEditor compile command for `NoMatterRiseFall_MT5.mq5`, then inspect the paired functions to ensure no MT4-only chain logic or MT5-only deletion behavior remains.

### Task 5: Verify, review, merge, and preserve generated artifacts

**Files:**
- Modify: `docs/superpowers/plans/2026-09-04-simultaneous-grid-pending-implementation.md` checklist status only if useful
- Merge: feature branch into the current `main` branch

- [ ] **Step 1: Run the complete Python verification**

Run `python -m pytest -q` and record the exact passing count.

- [ ] **Step 2: Run both source compilers from the main source paths**

Compile MT4 and MT5 after the feature branch is ready. Verify exit code 0 and inspect logs for errors/warnings.

- [ ] **Step 3: Review the complete diff and status**

Run `git diff main...HEAD --stat`, `git diff main...HEAD -- NoMatterRiseFall_MT4.mq4 NoMatterRiseFall_MT5.mq5 tests`, and `git status --short`. Confirm generated `.ex4`, `.ex5`, and `.log` artifacts already dirty on main are not overwritten or staged as source changes unless the build explicitly updates them.

- [ ] **Step 4: Commit implementation in focused commits**

Use separate commits for tests/model, MT4, and MT5 when the changes are independently green, with messages such as `test: cover simultaneous grid pending orders`, `feat: place all grid pending orders in MT4`, and `feat: place all grid pending orders in MT5`.

- [ ] **Step 5: Merge into main without touching unrelated dirty artifacts**

From the main worktree, merge `codex/simultaneous-grid-pending` with a non-destructive fast-forward or normal merge as appropriate. Do not reset, checkout, clean, or delete the four pre-existing generated artifacts.

- [ ] **Step 6: Run final verification on main**

Run the full Python suite and both compilers again from main. Only report completion after the tests and compiler outputs prove the stated acceptance criteria.
