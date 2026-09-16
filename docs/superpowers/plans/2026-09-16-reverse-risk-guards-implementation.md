# 反手订单保护与手数拆分 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or **superpowers:executing-plans** to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make MT4 and MT5 refuse unprotected follow-up orders, recover failed reversal orders safely, split reversal totals between 100 and 200 lots, and restart a fresh base-lot group at 200 lots or above.

**Architecture:** Add one deterministic lot-decision seam to the Python model and mirror the decision in both MQL sources with platform-specific order placement. Keep the existing grid interval semantics and per-level grid masks. Protect all order-creation paths behind a verified group-stop/target check; represent a split reversal as two same-price legs whose combined volume is tracked before the group advances.

**Tech Stack:** Python 3, pytest, MQL4, MQL5, MetaEditor command-line compilation.

---

### Task 1: Add failing model and source-contract tests

**Files:**
- Modify: `tests/strategy_logic.py`
- Modify: `tests/test_strategy_logic.py`

- [ ] **Step 1: Add a pure reversal-lot decision model**

Add a small model helper that returns one of `single`, `split`, or `restart` using the exact rules `<=100`, `>100 and <200`, and `>=200`. The split result contains two equal lots and the restart result contains no order lots.

- [ ] **Step 2: Add red tests for all boundaries**

Cover 100, 100.01, 120, 199.99, and 200. Assert split totals equal the requested total, each split leg is at most 100, and 200 produces a restart decision.

- [ ] **Step 3: Add a red model test for a protected-order gate**

Extend the model with a small `protection_ready` flag and an order-management path where a failed protection update returns `protection_failed` and creates no reverse/grid action. A successful retry must then permit the pending order path.

- [ ] **Step 4: Add source-contract tests for both platforms**

Assert both MQL sources contain the 100/200 thresholds, split-order helper/path, restart-group path, and an explicit protection result check before reverse/grid placement. Assert existing grid-loop semantics still use levels below the configured grid count.

- [ ] **Step 5: Run only the new tests and verify the expected failure**

Run:

```powershell
python -m pytest tests/test_strategy_logic.py -k "reversal_lot or protection_gate or max_reversal_lot or split" -q
```

Expected: the new tests fail because the helper and guarded behavior are not implemented yet; no production source has been changed in this task.

### Task 2: Implement the Python seam and regression model

**Files:**
- Modify: `tests/strategy_logic.py`
- Modify: `tests/test_strategy_logic.py`

- [ ] **Step 1: Implement deterministic lot decisions**

Implement `reversal_lot_decision(total, step=0.01)` with `single` for `total <= 100`, two normalized equal legs for `100 < total < 200`, and `restart` for `total >= 200`. Preserve the requested total by assigning any step-rounding remainder to the second leg.

- [ ] **Step 2: Add retry-aware model behavior**

Add `protection_ready` and `protection_failures` test inputs. Before `_next_pending()` or `_ensure_grid_pending()` runs after a group transition, return a `protection_failed` action while protection is unavailable; after a successful retry, create the expected pending actions exactly once.

- [ ] **Step 3: Model restart from base lots**

When the next reversal decision is `restart`, clear the active group state and make the next tick open with `initial_lots`, zero cumulative loss, zero reversal count, and no inherited grid state.

- [ ] **Step 4: Run the focused tests and then the full Python suite**

Run:

```powershell
python -m pytest tests/test_strategy_logic.py -k "reversal_lot or protection_gate or max_reversal_lot or split" -q
python -m pytest -q
```

Expected: the new tests and all existing tests pass.

### Task 3: Add shared MT4 single-group protection and split/restart behavior

**Files:**
- Modify: `NoMatterRiseFall_MT4.mq4:675-1455,1755-2145`
- Modify: `NoMatterRiseFall_MT4.mq4:2280-3345`

- [ ] **Step 1: Add constants and normalized lot-decision helpers**

Define internal thresholds `100.0` and `200.0`. Add helpers that classify the computed total and produce two broker-step-aligned equal legs for the only split range. Do not clamp a `>=200` total down to 100.

- [ ] **Step 2: Make protection verification return a boolean**

Change the MT4 group stop setter to return false when any `OrderModify` fails or when a managed position still has zero/mismatched SL/TP after modification. Add a helper that calls it and reports the actual verified state.

- [ ] **Step 3: Gate all single-group follow-up placement**

In initial-fill, pending-fill, grid-fill, recovery, and ordinary management paths, call the protection verifier before `EnsureNextPending()` and `EnsureGridPending()`. On failure, save state and return without creating new orders.

- [ ] **Step 4: Split single-group reverse pending and market reversal**

For a `100 < total < 200` reversal, place two same-direction, same-price pending legs or two equal market legs. Track both tickets/target volume in persisted state. Normalize pending orders by expected split leg volume and retain both legal legs; only advance the cycle after the combined filled volume reaches the target.

- [ ] **Step 5: Restart the group at `>=200`**

Before placing the oversized reversal, delete the current group’s pending orders, close current positions if present, clear accumulated loss/grid/cycle/transition fields, save the reset state, and return. The next tick must enter using the base initial lots.

- [ ] **Step 6: Run MT4 source-contract tests and compile**

Run the focused tests, then compile `NoMatterRiseFall_MT4.mq4`. Expected: zero errors and no warnings beyond the existing two unchecked `OrderDelete` warnings.

### Task 4: Port the exact behavior to MT5 single and multi groups

**Files:**
- Modify: `NoMatterRiseFall_MT5.mq5:2191-2489,2834-3240`
- Modify: `NoMatterRiseFall_MT5.mq5:3948-4633`

- [ ] **Step 1: Mirror lot classification and split-leg state**

Use the same 100/200 decisions, normalized split legs, persisted target volume, and two-ticket state for single and `MultiGroupState` paths.

- [ ] **Step 2: Make single and multi stop setters verifiable**

Change `SetGroupStops()` and `MultiSetStops()` to return a boolean and verify actual `POSITION_SL` and `POSITION_TP` values after modification. Do not place follow-up orders if verification fails.

- [ ] **Step 3: Gate initial fill, reverse fill, grid fill, recovery, and ordinary management**

Place reverse/grid orders only after verified protection. If a retry is needed, keep the group active and let the next tick retry without advancing state.

- [ ] **Step 4: Support split pending and market legs**

Place and track both same-price legs, preserve both in normalization, aggregate filled volume, and advance only after the target total is present. A failed leg must be retried without duplicating the successful leg.

- [ ] **Step 5: Restart only the oversized group**

At `>=200`, clear the affected single or multi group, delete its pending orders, and let the next tick create a new base-lot group. Other parallel groups must continue running.

- [ ] **Step 6: Run MT5 source-contract tests and compile**

Compile `NoMatterRiseFall_MT5.mq5` and inspect the compiler log for zero errors and zero warnings.

### Task 5: Documentation, integration, and final verification

**Files:**
- Modify: `README.md`
- Modify: `docs/superpowers/specs/2026-09-16-reverse-risk-guards-design.md`
- Include: compiled `NoMatterRiseFall_MT4.ex4`, `NoMatterRiseFall_MT5.ex5`

- [ ] **Step 1: Document the production rules in Chinese**

Document the 100/200 thresholds, two-leg split behavior, group-local restart, retry behavior, and unchanged grid-count semantics.

- [ ] **Step 2: Run all verification commands**

Run:

```powershell
python -m pytest -q
git diff --check
```

Compile both MQL sources again and confirm the final binary timestamps and hashes match the compiled outputs copied to each terminal Experts directory.

- [ ] **Step 3: Review the final diff and worktree**

Inspect source, tests, docs, compiler logs, and generated binaries. Confirm no debug markers or temporary files remain and no unrelated user changes were overwritten.

- [ ] **Step 4: Commit the implementation and merge it back**

Commit the isolated branch with focused messages, then fast-forward or merge it into the current project branch while preserving the pre-existing generated artifacts.
