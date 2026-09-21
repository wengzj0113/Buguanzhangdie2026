# 长K线市价入场模式 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a long-candle market-entry mode to both experts while preserving all existing order-group management.

**Architecture:** Add one new mode to the existing distance-mode routing. The mode validates K1 against K2–K21, derives direction from K1 body, returns fixed configured stop/take distances, and then reuses the existing market-entry path and follow-up management.

**Tech Stack:** MQL4, MQL5, Python `pytest`.

---

### Task 1: Add failing pure-logic and source-contract tests

**Files:** `tests/strategy_logic.py`, `tests/test_strategy_logic.py`

- [ ] Add a `LONG_CANDLE_MARKET` mode and a helper contract for K1/K2–K21 selection.
- [ ] Add tests proving qualifying bullish/bearish K1 opens market in the matching direction, a doji skips, a non-long K1 skips, and fixed distances are used.
- [ ] Add source assertions for both experts.
- [ ] Run the focused tests and observe failures caused by the missing mode/helper.

### Task 2: Implement MT4 and MT5 mode routing

**Files:** `NoMatterRiseFall_MT4.mq4`, `NoMatterRiseFall_MT5.mq5`

- [ ] Add the new enum value and display/input mapping while keeping existing defaults unchanged.
- [ ] Add the long-candle detector using K1 and K2–K21, with strict data validation and body-direction handling.
- [ ] Return fixed stop/take distances for the new mode and route qualifying signals through the existing market-entry branch.
- [ ] Keep candle-range pending/breakout branches guarded exclusively by `DISTANCE_CANDLE_RANGE`.

### Task 3: Update documentation and verify

**Files:** `README.md`, `tests/strategy_logic.py`, `tests/test_strategy_logic.py`

- [ ] Document the new mode and its K1/K2–K21 semantics.
- [ ] Run the complete Python test suite.
- [ ] Inspect the diff for MT4/MT5 parity and unchanged existing mode guards.
- [ ] Compile with MetaEditor when available and report any unavailable compiler verification.
