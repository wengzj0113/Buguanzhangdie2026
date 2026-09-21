# v_enable UI Toggle Implementation Plan

> **For agentic workers:** Execute this plan task-by-task with verification checkpoints.

**Goal:** Add a default-off `v_enable` parameter to both EA variants, isolate MT5 UI behavior from trading management, and remove only demonstrably dead/redundant code found during the review.

**Architecture:** Treat `v_enable` as an initialization-time presentation switch. MT5 UI creation, rendering, and chart-event handling are guarded independently; the trading timer and trade-transaction recovery remain unconditional. MT4 receives the compatibility input but has no custom UI path to toggle.

**Tech Stack:** MQL4, MQL5, Python `pytest`, MetaEditor command-line compilation, PowerShell.

---

### Task 1: Add failing source-contract tests

**Files:**
- Modify: `tests/test_strategy_logic.py`

- [ ] **Step 1: Add tests that require `v_enable` in both source files.**

Use the existing source-loading helpers and assert:

```python
def test_v_enable_defaults_to_zero_in_both_eas():
    assert re.search(r"input\\s+int\\s+v_enable\\s*=\\s*0", mt4_source)
    assert re.search(r"input\\s+int\\s+v_enable\\s*=\\s*0", mt5_source)

def test_mt5_ui_switch_does_not_disable_trade_timer():
    assert "if(v_enable == 1)" in mt5_source
    assert re.search(r"if\\s*\\(!EventSetTimer\\(1\\)\\)", mt5_source)
```

- [ ] **Step 2: Run the focused tests and verify they fail before implementation.**

```powershell
python -m pytest -q tests/test_strategy_logic.py -k v_enable
```

Expected: failures for the missing declaration and UI guard.

### Task 2: Implement the UI switch without changing trading behavior

**Files:**
- Modify: `NoMatterRiseFall_MT4.mq4`
- Modify: `NoMatterRiseFall_MT5.mq5`

- [ ] **Step 1: Add the compatibility input in the existing Chinese input section.**

```mql
input int            v_enable = 0; // 可视化界面开关：0=关闭，1=开启
```

- [ ] **Step 2: Guard MT5 UI creation, rendering, and chart events.**

Create the UI only when `v_enable == 1`. Return early from `OnChartEvent` and `GuiRenderIfNeeded` when it is not enabled. Keep `EventSetTimer(1)`, `OnTimer`, and `OnTradeTransaction` unconditional because they perform trading recovery and order coordination.

- [ ] **Step 3: Keep destruction and trading cleanup safe.**

Keep `GuiDestroy()` in `OnDeinit`, but ensure it does nothing when UI objects were not created. Do not gate `EventKillTimer()` or state/ownership cleanup on `v_enable`.

- [ ] **Step 4: Review and remove only provably dead or exact-duplicate code.**

Use `rg` plus the call sites and preserve all trading-state, recovery, retry, pending-order, and historical-compatibility branches unless their non-reachability and lack of side effects are proven.

- [ ] **Step 5: Run the focused tests.**

```powershell
python -m pytest -q tests/test_strategy_logic.py -k v_enable
```

Expected: all focused tests pass.

### Task 3: Update user-facing documentation

**Files:**
- Modify: `README.md`
- Modify: `EA软件使用手册.html`

- [ ] **Step 1: Document `v_enable` in Chinese.**

Explain that `0` disables the MT5 custom UI while trading continues, `1` enables it, changes take effect after reloading the EA, and MT4 keeps the parameter for compatibility because it has no matching custom UI.

- [ ] **Step 2: Verify documentation text and HTML validity.**

Confirm `v_enable`, `0`, and `1` are documented in both files and run the existing static HTML checks if present.

### Task 4: Full verification and build artifacts

**Files:**
- Generated: `NoMatterRiseFall_MT4.ex4`, `NoMatterRiseFall_MT5.ex5`, compiler logs and configured destination copies.

- [ ] **Step 1: Run the complete Python suite.**

```powershell
python -m pytest -q
```

- [ ] **Step 2: Compile MT5 and MT4 with the configured MetaEditor commands.**

Require `0 errors` and `0 warnings` in both compiler logs.

- [ ] **Step 3: Run `git diff --check` and inspect the final diff.**

Confirm no unrelated existing user changes were overwritten.

- [ ] **Step 4: Compare hashes of generated binaries and destination EA files.**

Report the exact compile and test results.
