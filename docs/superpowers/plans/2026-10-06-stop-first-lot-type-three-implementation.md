# 止损首单固定手数类型 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add stop-first-lot type 3, which uses a separate user-configured fixed lot amount (default 0.01) for the next group after every stop transition.

**Architecture:** Extend the existing StrategyModel regression harness and type-specific calculations, then expose and validate the new setting in both canonical EAs. MT5's GUI draft/applied config, persistence fingerprint, editor controls, and validation must carry the new parameter; single-group and multi-group paths use the same type-3 rule.

**Tech Stack:** MQL4, MQL5, Python pytest.

---

### Task 1: Test type-three stop sizing

**Files:**
- Modify: `tests/strategy_logic.py`
- Modify: `tests/test_strategy_logic.py`

- [x] Add `stop_first_order_lots=0.01` to StrategyModel and make only stop-transition first-lot selection branch on type 3.
- [x] Add failing behavior tests proving type 3 returns the configured fixed amount after a stop, including consecutive stops and unchanged initial entry size.
- [x] Add source contract tests requiring both canonical sources to declare the new defaulted parameter and support type 3.
- [x] Run the targeted tests and confirm they fail because current code has no type-three behavior/parameter.

### Task 2: Add MT4 support

**Files:**
- Modify: `NoMatterRiseFall_MT4.mq4`

- [x] Declare `止损首单固定手数 = 0.01` and add its compatibility mapping.
- [x] Update type validation and positive/broker-volume validation.
- [x] Update single-group and multi-group next-group sizing helpers so type 3 returns the fixed value, normalized as broker volume.
- [x] Ensure pending reversal sizing and direct stop-open sizing both use these helpers or the equivalent type-three branch.

### Task 3: Add MT5 support

**Files:**
- Modify: `NoMatterRiseFall_MT5.mq5`

- [x] Add the fixed-lot input and `Config` field; include it in default loading, config fingerprint/persistence, validation, and broker volume checks.
- [x] Update single-group and multi-group next-group sizing helpers and direct stop-open sizing for type 3.
- [x] Extend GUI type choices, labels, config editing, applied/draft state, and parameter display to include type 3 and the fixed-lot field.

### Task 4: Verify and build

**Files:**
- No additional files.

- [x] Run the type-three targeted pytest cases, then the full repository automated test suite.
- [x] Compile both canonical EAs with `powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\compile-mql.ps1 -Target Both`.
- [x] Confirm zero compiler errors and refreshed `.ex4`/`.ex5` outputs; report warnings and output paths.
