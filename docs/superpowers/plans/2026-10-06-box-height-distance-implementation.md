# 箱体高度距离模式 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** Add a box-height distance mode to MT4 and MT5 using rolling-hour or completed daily-session M1 highs/lows with an inclusive configurable height range.

**Architecture:** Append distance enum value 6. Implement a shared rule in the Python strategy harness and platform-specific M1 range readers in MT4/MT5. Feed the validated box height into the existing stop/take distance state and preserve it through each stop-switch cycle; expose all settings in MT5 GUI configuration.

**Tech Stack:** MQL4, MQL5, Python pytest.

---

### Task 1: Add failing box-range logic tests

**Files:**
- Modify: `tests/strategy_logic.py`
- Modify: `tests/test_strategy_logic.py`

- [x] Add a `BOX_RANGE` distance mode and a tested helper that filters M1 bars by `[start, end)`, computes rounded box height in points, and rejects missing, malformed, or out-of-bound ranges.
- [x] Add tests for rolling start/end selection, daily last-completed session selection, exact minimum/maximum acceptance, one-point-outside rejection, incomplete daily session, and missing history.
- [x] Add StrategyModel tests that the box height supplies both stop/take distance, does not add a breakout entry condition, and remains fixed for stop-switched groups until a fresh cycle.
- [x] Add source contract tests for enum value 6, MT4/MT5 parameter defaults, M1 history use, type validation, and MT5 GUI option.
- [x] Run the new targeted tests and confirm expected failures before modifying production sources.

### Task 2: Implement MT4 box range

**Files:**
- Modify: `NoMatterRiseFall_MT4.mq4`

- [x] Append `DISTANCE_BOX_RANGE = 6` and declare inputs for time mode, lookback hours (12), daily range start/end (01:00/12:00), and min/max height points (500/1000).
- [x] Implement server-time parsing and most-recent-completed daily session selection; implement M1 bar scanning for both the rolling interval and fixed session interval, rejecting insufficient history.
- [x] Validate positive hours, valid unequal clock times, positive min/max heights, and `max >= min` during initialization.
- [x] Route box height through `GetDistancePoints` as equal stop/take distances, enforce inclusive bounds, and freeze selected distances through subsequent stop switches until a fresh cycle.

### Task 3: Implement MT5 box range and GUI

**Files:**
- Modify: `NoMatterRiseFall_MT5.mq5`

- [x] Append distance enum value 6 and add matching `GuiConfig` fields, default-input copying, config fingerprint, validation, and parameter checks.
- [x] Implement M1 CopyRates range calculation with identical rolling/session boundaries and insufficient-history behavior as MT4.
- [x] Route box height through `GetDistancePoints`; retain the locked distances through single-group and multi-group stop transitions.
- [x] Extend distance dropdown labels/options and conditionally display time-mode, lookback hours, start/end, and min/max height controls on the distance page.
- [x] Include new editable keys in GUI value text, value application, parsing, validation, and page keyboard/focus field lists.

### Task 4: Document and verify

**Files:**
- Modify: `README.md`
- Modify: `EA软件使用手册.html`

- [x] Document box-range selection, defaults, time boundaries, completed-session rule, validity limits, and stop/take behavior.
- [x] Run targeted box tests, then the full pytest suite.
- [x] Compile both canonical files with `powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\compile-mql.ps1 -Target Both`.
- [x] Confirm refreshed `.ex4` and `.ex5` files, zero errors, and report compiler warnings and output paths.
