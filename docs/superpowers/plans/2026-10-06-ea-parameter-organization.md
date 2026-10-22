# EA Parameter Organization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Organize the Chinese parameter UI across the standard and XAU MT4/MT5 EAs without changing trading behavior or input compatibility.

**Architecture:** Keep input identifiers, types, and defaults intact while moving declarations into category blocks so the Strategy Tester optimization list visibly sorts related settings together. Add native `input group` headings to MT5 and matching comment dividers/labels to MT4; XAU cost controls get their own final group.

**Tech Stack:** MQL4, MQL5, Python pytest, MetaEditor compiler PowerShell script.

---

### Task 1: Capture input declaration compatibility

**Files:**
- Modify: `tests/test_strategy_logic.py`
- Test: `tests/test_strategy_logic.py`

- [ ] **Step 1: Add one source-contract test for all four EA files**

Assert each source's input names follow the approved category order, require MT5 group headings and inline Chinese labels in all four files, and keep MQL4 display labels within 63 characters. Preserve every name, type, and default while allowing declaration order to change.

- [ ] **Step 2: Run the focused test and confirm it fails for missing group/display labels**

Run: `python -m pytest tests/test_strategy_logic.py -k parameter_organization -q`
Expected: FAIL because the four sources do not yet satisfy the grouping/display-label contract.

### Task 2: Organize standard EA parameter displays

**Files:**
- Modify: `NoMatterRiseFall_MT4.mq4`
- Modify: `NoMatterRiseFall_MT5.mq5`

- [ ] **Step 1: Add the six shared category headings in MT5 and matching inline category labels in MT4**

Use these categories in order: `策略与首单`, `入场信号`, `时间箱体` (standard EA only), `手数与风险`, `网格与止盈`, `止盈止损距离`, `订单识别`, `交易时段`. Reorder declarations into these blocks and give each parameter a concise label that identifies its purpose; include units or `0` semantics where needed. Do not change names, types, defaults, or trading logic.

- [ ] **Step 2: Run the focused source-contract test**

Run: `python -m pytest tests/test_strategy_logic.py -k parameter_organization -q`
Expected: PASS for standard MT4/MT5 declarations, group headings, and display labels.

### Task 3: Organize XAU NetRR parameter displays

**Files:**
- Modify: `NoMatterRiseFall_MT4_XAU_NetRR_v2_10.mq4`
- Modify: `NoMatterRiseFall_MT5_XAU_NetRR_v2_10.mq5`

- [ ] **Step 1: Apply matching shared groups and add the XAU-only cost group**

Keep common strategy inputs in the same categories as the standard EAs. Place XAU NetRR/cost parameters under `净盈亏比与交易成本`. Use matching concise labels in MT4 comments and MT5 comments; retain every declaration name, type, and default.

- [ ] **Step 2: Run the focused source-contract test**

Run: `python -m pytest tests/test_strategy_logic.py -k parameter_organization -q`
Expected: PASS for all four sources.

### Task 4: Run required regression checks and compile both platforms

**Files:**
- Verify: `NoMatterRiseFall_MT4.mq4`
- Verify: `NoMatterRiseFall_MT5.mq5`
- Verify: `tests/test_strategy_logic.py`

- [ ] **Step 1: Run the relevant automated tests**

Run: `python -m pytest tests/test_strategy_logic.py -q`
Expected: all tests pass.

- [ ] **Step 2: Compile both canonical platform sources**

Run: `powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\compile-mql.ps1 -Target Both`
Expected: MetaEditor reports zero errors for MT4 and MT5, and refreshed `.ex4`/`.ex5` files exist beside canonical sources. Record warnings and output paths.

- [ ] **Step 3: Review the final diff**

Run `git diff --check` and verify production changes are limited to input declaration ordering, group headings, and display comments; ensure the compatibility test confirms names remain present in the approved order.
