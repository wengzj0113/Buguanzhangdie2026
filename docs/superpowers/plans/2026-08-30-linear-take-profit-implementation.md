# 线性移动止盈 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 为MT4和MT5增加可选的线性移动止盈，并将输入参数说明统一为中文。

**Architecture:** 新增止盈移动模式枚举；订单组保存不利方向参考价。网格模式继续使用最后网格成交价，线性模式只在创出新的不利极值时更新止盈，所有模式共用现有订单组、网格和循环状态机。

**Tech Stack:** MQL4、MQL5、Python、pytest、MetaEditor。

---

### Task 1: Add behavioral tests

**Files:**
- Modify: `tests/strategy_logic.py`
- Modify: `tests/test_strategy_logic.py`

- [ ] Add a failing test proving a buy group's TP decreases by the adverse movement and does not recover on a rebound.
- [ ] Add a failing test proving the sell-side mirror behavior.
- [ ] Add a failing test proving grid moving TP remains fill-triggered and does not become linear by default.
- [ ] Run `python -m pytest tests/test_strategy_logic.py -q`; expected result is failure because the new mode and reference tracking do not exist.

### Task 2: Implement MT5 behavior

**Files:**
- Modify: `NoMatterRiseFall_MT5.mq5`

- [ ] Add a Chinese-described take-profit mode input and a persisted adverse reference price.
- [ ] Initialize the reference at each new order group anchor and restore it on restart.
- [ ] Add linear TP calculation for buy-low/sell-high adverse extremes, update only when the extreme worsens, and retain the fixed outer SL.
- [ ] Retry failed group stop/TP modifications on later ticks.
- [ ] Keep grid mode using the existing last-grid-entry calculation.

### Task 3: Implement MT4 behavior

**Files:**
- Modify: `NoMatterRiseFall_MT4.mq4`

- [ ] Mirror the MT5 mode, state, linear calculation, persistence, and retry behavior using MT4 quote and order APIs.

### Task 4: Chinese parameter and documentation update

**Files:**
- Modify: `README.md`
- Modify: `docs/superpowers/specs/2026-08-30-no-matter-rise-fall-design.md`
- Modify: `mt5_cycle_test.ini`

- [ ] Add Chinese explanations for every input and both TP modes.
- [ ] Document formulas, order-group scope, no-retraction behavior, and default mode.

### Task 5: Verify

**Files:**
- No additional files.

- [ ] Run `python -m pytest -q`.
- [ ] Run `python -m py_compile tests/strategy_logic.py tests/test_strategy_logic.py`.
- [ ] Compile MT5 and MT4 source and confirm zero errors and zero warnings.
- [ ] Run `git diff --check` and inspect the final diff for unintended changes.
