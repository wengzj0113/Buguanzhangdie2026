# Average Candle Distance Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a third distance mode to the MT4 and MT5 experts that calculates a frozen stop-loss distance from the average height of the previous N completed candles, then derives take-profit from that stop distance.

**Architecture:** Keep the existing fixed-distance and previous-candle-height behavior intact. Add one shared conceptual branch to each platform's distance resolver: validate and read N completed candles at shifts 1..N, round the average to points, multiply by the configured stop and take-profit factors, and let the existing group-state fields freeze those values. Keep the special high/low initial pending branch guarded exclusively by `DISTANCE_CANDLE_RANGE` plus once-per-bar mode; average mode will use the existing market-entry branch.

**Tech Stack:** MQL4, MQL5, Python `pytest`, MetaEditor command-line compilation.

---

### Task 1: Extend the executable behavior model and add failing tests

**Files:** `tests/strategy_logic.py`, `tests/test_strategy_logic.py`

- [ ] Add `DistanceMode.AVERAGE_CANDLE_RANGE` and model parameters for candle count and stop/take multipliers, with defaults 20, 2.0, and 2.0.
- [ ] Add a pure average-range helper that consumes completed candle ranges and rejects insufficient, invalid, or non-positive data.
- [ ] Add tests for exclusion of the current candle, average calculation, sequential multipliers, and invalid inputs.
- [ ] Add model tests proving average mode opens at market, does not create initial high/low pending orders, and preserves the calculated group distance for later actions.
- [ ] Add source-contract assertions for both MT4 and MT5 covering the third enum, average inputs/configuration, and the pending-entry guard.
- [ ] Run the focused tests and confirm they fail before production implementation.

### Task 2: Implement the MT4 average distance mode

**Files:** `NoMatterRiseFall_MT4.mq4`

- [ ] Add the third `DistanceMode` value and three inputs: average completed-candle count (20), stop multiplier (2.0), and take-profit multiplier (2.0).
- [ ] Validate the new parameters during initialization alongside the existing distance parameters.
- [ ] Add an average-range helper that reads shifts 1 through N, requires N+1 bars, rejects invalid candles, and returns rounded points.
- [ ] Extend `GetDistancePoints` so average mode computes `average × stop multiplier`, then `rounded stop × take-profit multiplier`; do not apply the single-candle min/max filter.
- [ ] Leave `GetActiveDistancePoints` group-state precedence intact and ensure the average mode remains in the existing market-entry branch.
- [ ] Verify the high/low initial pending condition remains exact for previous-candle mode and once-per-bar mode.

### Task 3: Implement the MT5 configuration, GUI, and distance mode

**Files:** `NoMatterRiseFall_MT5.mq5`

- [ ] Add the same third enum and three input parameters, then add matching `GuiConfig` fields and map them in `LoadConfigFromInputs`.
- [ ] Extend `ValidateGuiConfig` and both configuration fingerprints so invalid values are rejected and persisted state cannot be mistaken for a different configuration.
- [ ] Add the average branch and completed-candle helper to `GetDistancePoints`, preserving group-distance freezing and the existing single-candle filter semantics.
- [ ] Extend the distance-mode GUI options to display/select the third mode.
- [ ] Expose average candle count and both multipliers as editable fields on the distance settings page, including dropdown parsing, value lookup, and assignment.
- [ ] Add the new values to the applied-configuration overview or distance summary where the existing settings are shown.
- [ ] Keep the initial pending GUI/runtime condition restricted to previous-candle mode plus once-per-bar mode.

### Task 4: Verify, build, and integrate

**Files:** `tests/strategy_logic.py`, `tests/test_strategy_logic.py`, `NoMatterRiseFall_MT4.mq4`, `NoMatterRiseFall_MT5.mq5`

- [ ] Run the complete Python suite with the bundled Python runtime.
- [ ] Compile MT4 and MT5 with MetaEditor and confirm no new errors or warnings.
- [ ] Review the diff for MT4/MT5 parity, defaults, mode routing, and accidental changes to the existing pending/OCO logic.
- [ ] Commit the implementation and verification changes on the feature branch.
- [ ] Perform a read-only code review checkpoint and resolve any actionable findings.
- [ ] Fast-forward merge the feature branch into the main branch, rebuild both experts from main, rerun tests, and report the final artifacts.

## Verification commands

```powershell
C:\Users\user\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe -m pytest -q
```

```powershell
& 'C:\Program Files\MetaTrader 5\MetaEditor64.exe' /compile:'D:\00_EA\codx-ea\Experts\不管涨跌复刻\.worktrees\average-candle-distance\NoMatterRiseFall_MT5.mq5' /log:'D:\00_EA\codx-ea\Experts\不管涨跌复刻\.worktrees\average-candle-distance\mt5_compile.log'
& 'C:\Program Files (x86)\MetaTrader 4 IC Markets Global\metaeditor.exe' /compile:'D:\00_EA\codx-ea\Experts\不管涨跌复刻\.worktrees\average-candle-distance\NoMatterRiseFall_MT4.mq4' /log:'D:\00_EA\codx-ea\Experts\不管涨跌复刻\.worktrees\average-candle-distance\mt4_compile.log'
```
