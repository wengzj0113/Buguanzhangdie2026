# Dual Basket Strategy Parity Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make each opposite basket follow the same MT5 strategy rules as a single basket, with only its starting direction and order ownership changed.

**Architecture:** Keep the established single-basket execution route. Extract shared pure rule helpers for cycle direction and basket price calculations so the single and multi-group paths cannot drift. Keep per-basket state and order scoping in the group manager, calculate stop-reversal lots from all losses including the group just stopped, and end only the basket that reaches its own reversal limit. EA-wide no-money cleanup remains global.

**Tech Stack:** MQL5, Python strategy model, pytest, PowerShell MetaEditor build script.

---

### Task 1: Add regression checks for strategy parity

**Files:**
- Modify: `tests/test_strategy_logic.py`
- Modify: `tests/strategy_logic.py`

- [x] Assert both MT5 manager wrappers call shared cycle, stop-price, take-profit, and grid-price rule helpers.
- [x] Assert grouped stop-reversal sizing includes prior cumulative losses plus the just-stopped group's volume for first-order lot type 1.
- [x] Assert reaching a group's maximum reversal count uses group-scoped cleanup and does not invoke the EA-wide reset path.
- [x] Assert a broker take-profit that leaves a group flat cancels that group's remaining pending orders before an active-order wait can preserve it.
- [x] Run the focused tests and confirm each new regression check fails on the current implementation.

### Task 2: Share strategy calculations between single and grouped baskets

**Files:**
- Modify: `NoMatterRiseFall_MT5.mq5`
- Modify: `NoMatterRiseFall_MT5_Core.mqh`
- Modify: `dist/DistanceModeEAs_2026-10-11/BollingerRange/MT5/Experts/NoMatterRiseFall_MT5_Core.mqh`

- [x] Add parameterized helpers for cycle direction, stop/target prices, and adverse/favorable grid prices.
- [x] Make legacy single-basket and grouped-basket wrappers delegate to those same helpers without changing their order-scoped operations.
- [x] Correct grouped stop-transition sizing to include the currently stopped group before applying the recovery multiplier.

### Task 3: Scope configured reversal-limit completion to each basket

**Files:**
- Modify: the MT5 sources listed in Task 2

- [x] Add a group completion helper that deletes only that group's pending orders and closes only its positions before deactivating it.
- [x] Use that helper for reverse-pending fills, broker-closed stops, and tick-detected stops at the reversal limit.
- [x] Preserve account/magic-wide cleanup for insufficient funds and preserve legacy single-basket behavior.
- [x] Detect a broker-closed take-profit in the flat-group path and retry group-scoped pending cleanup until it succeeds.

### Task 4: Verify and compile

**Files:**
- No additional source changes unless verification finds a defect

- [x] Run relevant strategy tests and the full `pytest -q` suite.
- [x] Run `powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\compile-mql.ps1 -Target Both`.
- [x] Compile the BollingerRange MT5 profile source with MetaEditor and verify its `.ex5` is refreshed beside the source.
- [x] Review the diff and ensure pre-existing user changes remain untouched.

---

## Acceptance checklist

- [x] Both group directions use the same cycle, stops, take-profit, and grid calculations as the single basket.
- [x] For recovery lot type 1, a stopped group's lots are included exactly once in the next reversal size.
- [x] One basket reaching its reversal limit does not close its live peer basket.
- [x] A basket whose positions were broker-closed by take-profit cannot stay active solely because a pending order remains.
- [x] EA-wide no-money cleanup remains account/magic scoped as before.
- [x] Tests and required MT4/MT5 builds complete successfully with refreshed outputs.
