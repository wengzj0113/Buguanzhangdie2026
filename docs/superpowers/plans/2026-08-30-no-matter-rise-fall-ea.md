# 不管涨跌 EA Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build an MT5 EA and an equivalent MT4 EA that opens a configured first trade, places an opposite pending stop at the active trade's stop-loss price, doubles the volume by a configurable multiplier on each reversal, and ends the cycle after take-profit.

**Architecture:** The MQL5 and MQL4 files each implement the same small state machine: reconcile one strategy position and one opposite pending order, create the initial market order when the symbol is idle, create the reverse stop at the current position's SL, and perform a defensive market transition if the SL level is reached before the broker fills the pending order. A Python model test covers the price/volume/order-intent rules independently of terminal APIs.

**Tech Stack:** MQL5 (`CTrade`), MQL4 trading API, Python 3 standard library/pytest.

---

### Task 1: Lock down strategy behavior with executable model tests

**Files:**
- Create: `tests/test_strategy_logic.py`
- Create: `tests/strategy_logic.py`

- [ ] **Step 1: Write tests for initial order, reverse order, repeated doubling, and TP cleanup.**
- [ ] **Step 2: Run `python -m pytest -q` and confirm the tests fail because the model is not implemented.**
- [ ] **Step 3: Implement the minimal pure-Python state model.**
- [ ] **Step 4: Run `python -m pytest -q` and confirm all model tests pass.**

### Task 2: Implement the MT5 EA

**Files:**
- Create: `不管涨跌_MT5.mq5`

- [ ] **Step 1: Add user inputs for direction, initial lots, multiplier, SL/TP distance, magic number, and order comment.**
- [ ] **Step 2: Add symbol/magic filtering, volume and price normalization, and current-position/pending-order discovery.**
- [ ] **Step 3: Add initial market entry and opposite `BUY_STOP`/`SELL_STOP` placement at the current position SL.**
- [ ] **Step 4: Add SL-level defensive transition, pending cleanup, and TP cycle reset.**
- [ ] **Step 5: Compile with MetaEditor64 in `/compile` mode and inspect the generated log.**

### Task 3: Implement the MT4 EA with matching behavior

**Files:**
- Create: `不管涨跌_MT4.mq4`

- [ ] **Step 1: Port the same inputs and state rules to the MT4 order model.**
- [ ] **Step 2: Add initial entry, reverse stop placement, defensive transition, and TP cleanup.**
- [ ] **Step 3: Compile with MetaEditor in `/compile` mode and inspect the generated log.**

### Task 4: Verify the delivered artifacts

- [ ] **Step 1: Run the complete Python test suite.**
- [ ] **Step 2: Recompile both EA files from a clean command invocation.**
- [ ] **Step 3: Audit every requested parameter and transition against the source and test output.**
