# Multiple Operation Windows Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将 MT4/MT5 首单可用时间扩展为三个可独立配置的服务器时间窗口，并同步 MT5 GUI、测试和文档。

**Architecture:** 保留现有 `开始时间`/`结束时间` 作为时段1，新增两组输入和对应 GUI 字段。运行时统一把三组 `HH:MM` 转成分钟数组，窗口精确为 `00:00-00:00` 时关闭，其他相同起止时间表示全天，任意窗口命中即可允许首单。

**Tech Stack:** MQL4, MQL5, Python 3, pytest, MetaEditor compiler.

---

### Task 1: Add failing Python behavior tests

**Files:**
- Modify: `tests/test_strategy_logic.py`
- Modify: `tests/strategy_logic.py` only after the failing tests are observed

- [ ] **Step 1: Add tests for three-window matching**

Add tests next to the existing single-window tests. The tests must construct `StrategyModel` with `operation_windows` and cover an enabled later window, a disabled `00:00-00:00` window, a cross-midnight window, and management outside all windows:

```python
def test_initial_entry_is_allowed_when_any_operation_window_matches():
    model = StrategyModel(
        Direction.BUY, CycleMode.MODE_1, 0.01, 2.0, 500, 0.0001,
        operation_windows=[(8 * 60, 9 * 60), (13 * 60, 14 * 60), (0, 0)],
    )

    assert model.on_tick(1.1000, 1.1002, now_minute=10 * 60) == []
    actions = model.on_tick(1.1000, 1.1002, now_minute=13 * 60)
    assert actions[0]["kind"] == "market"


def test_disabled_operation_window_does_not_allow_initial_entry():
    model = StrategyModel(
        Direction.BUY, CycleMode.MODE_1, 0.01, 2.0, 500, 0.0001,
        operation_windows=[(0, 0), (0, 0), (0, 0)],
    )

    assert model.on_tick(1.1000, 1.1002, now_minute=12 * 60) == []


def test_cross_midnight_operation_window_matches_both_sides_of_midnight():
    model = StrategyModel(
        Direction.BUY, CycleMode.MODE_1, 0.01, 2.0, 500, 0.0001,
        operation_windows=[(22 * 60, 2 * 60), (0, 0), (0, 0)],
    )

    assert model.on_tick(1.1000, 1.1002, now_minute=23 * 60) != []
    model.reset()
    assert model.on_tick(1.1000, 1.1002, now_minute=1 * 60) != []


def test_existing_position_is_managed_outside_operation_windows():
    model = StrategyModel(
        Direction.BUY, CycleMode.MODE_1, 0.01, 2.0, 500, 0.0001,
        operation_windows=[(8 * 60, 9 * 60), (0, 0), (0, 0)],
    )
    model.on_tick(1.1000, 1.1002, now_minute=8 * 60)
    stop_price = model.position.stop_loss
    actions = model.on_tick(1.1000, stop_price + 0.0002, now_minute=12 * 60)
    assert any(action["kind"] == "market" for action in actions)
```

Use the existing model reset/position conventions if the exact stop-trigger call needs the same bid/ask ordering as the neighboring test.

- [ ] **Step 2: Run the new tests and verify the expected red failure**

Run: `python -m pytest tests/test_strategy_logic.py -k "operation_window" -q`

Expected: FAIL because `StrategyModel` does not yet accept `operation_windows` and the runtime still stores one start/end pair.

### Task 2: Implement the Python three-window model

**Files:**
- Modify: `tests/strategy_logic.py:300-410`
- Modify: `tests/strategy_logic.py:950-1045`

- [ ] **Step 1: Add a shared window predicate and backward-compatible constructor input**

Add a helper near the model definitions and add `operation_windows=None` after `end_minute` in both model constructors. Preserve old callers by converting the old pair to the first window and defaulting the other two to disabled:

```python
def is_operation_window_active(now_minute, start_minute, end_minute):
    if (start_minute, end_minute) == (0, 0):
        return False
    if start_minute == end_minute:
        return True
    if start_minute < end_minute:
        return start_minute <= now_minute < end_minute
    return now_minute >= start_minute or now_minute < end_minute


def is_initial_entry_allowed(now_minute, operation_windows):
    return now_minute is None or any(
        is_operation_window_active(now_minute, start, end)
        for start, end in operation_windows
    )
```

The constructor stores `self.operation_windows = tuple(operation_windows or ((start_minute, end_minute), (0, 0), (0, 0)))`, and `_is_initial_entry_allowed` delegates to the helper.

- [ ] **Step 2: Apply the same windows to `ParallelStrategyModel`**

Store `operation_windows` in `_config` and replace the inline start/end check with the shared predicate so multi-group candle mode follows the same behavior.

- [ ] **Step 3: Run Python tests**

Run: `python -m pytest tests/test_strategy_logic.py -q`

Expected: all tests pass, including the new four tests.

### Task 3: Add MQL inputs and runtime window logic

**Files:**
- Modify: `NoMatterRiseFall_MT4.mq4:112-116,200-205,526-550,4475-4498`
- Modify: `NoMatterRiseFall_MT5.mq5:126-132,338-346,1081-1100,1490-1505,1540-1645,1690-1720`

- [ ] **Step 1: Add compatible inputs and fixed-size minute arrays**

Keep the existing period-1 inputs and add:

```mql
input string         时段2开始时间 = "00:00";
input string         时段2结束时间 = "00:00";
input string         时段3开始时间 = "00:00";
input string         时段3结束时间 = "00:00";
```

Define `MAX_OPERATION_WINDOWS 3`, replace the two global minute values with `int g_start_operation_minutes[MAX_OPERATION_WINDOWS];` and `int g_end_operation_minutes[MAX_OPERATION_WINDOWS];`, and add a helper that returns false for `(0,0)`, true for nonzero equal values, and handles normal/cross-midnight ranges.

- [ ] **Step 2: Parse all three windows during initialization**

In MT4 `OnInit`, parse all six values and reject any negative result. In MT5 `LoadConfigFromInputs`, `ValidateGuiConfig`, and `ApplyGuiConfig`, carry all six strings and update/restore all six runtime minute values together.

- [ ] **Step 3: Replace single-window entry checks**

Both `IsInitialEntryAllowed` implementations should calculate current server minutes and loop from `0` through `MAX_OPERATION_WINDOWS - 1`, returning true on the first active matching window and false otherwise. No follow-up order or existing-position branch may call this new predicate.

- [ ] **Step 4: Add source-structure tests before moving on**

Add parametrized assertions in `tests/test_strategy_logic.py` for both source files checking the four new inputs, `MAX_OPERATION_WINDOWS`, a loop over windows, and the disabled-pair condition. Run:

```text
python -m pytest tests/test_strategy_logic.py -k "operation_window or time_window" -q
```

Expected: PASS.

### Task 4: Extend MT5 GUI configuration, editing, persistence, and summary

**Files:**
- Modify: `NoMatterRiseFall_MT5.mq5:220-249,507-535,1385-1503,1671-1702`
- Modify: `NoMatterRiseFall_MT5.mq5:6840-7180,7245-7310,7535-7550,7875-8045,8170-8490,8740-8830`
- Modify: `tests/test_strategy_logic.py` GUI source assertions

- [ ] **Step 1: Add six time strings to `GuiConfig` and its fingerprint**

Retain `start_time`/`end_time` for period 1 and add `start_time_2`, `end_time_2`, `start_time_3`, `end_time_3`. Append all four fields to `GuiConfigFingerprintText`.

- [ ] **Step 2: Validate and apply all six fields**

Validate each field with `ParseTimeMinutes`; allow exact `00:00` pairs as disabled; save/restore all six parsed minute values in `ApplyGuiConfig`; load the four added inputs in `LoadConfigFromInputs`.

- [ ] **Step 3: Register all new GUI keys and values**

Add `start_time_2`, `end_time_2`, `start_time_3`, `end_time_3` to editable-key checks, 24-option dropdowns, current-value lookup, dropdown assignment, text parsing, and edit synchronization. Treat them as time values so `HH:MM` normalization is shared with period 1.

- [ ] **Step 4: Render and hit-test six time fields**

On the risk page render three rows of paired fields with labels `时段1开始时间`, `时段1结束时间`, `时段2开始时间`, `时段2结束时间`, `时段3开始时间`, `时段3结束时间`. Expand the risk-page key arrays and field counts in both `GuiDropdownFieldPosition` and `GuiHandleChartClick` to include the new keys while keeping magic number and order comment editable below them.

- [ ] **Step 5: Render the three-window overview summary**

Add a helper that formats each window as `HH:MM-HH:MM`, returns `关闭` for `(00:00,00:00)`, and joins the three entries with ` / `. Use it in both overview schedule render paths and the compact overview refresh.

- [ ] **Step 6: Add GUI source assertions and run tests**

Extend the existing GUI tests to require all six keys, three labels, fingerprint references, and the multi-window summary helper. Run:

```text
python -m pytest tests/test_strategy_logic.py -k "gui or operation_window" -q
```

Expected: PASS.

### Task 5: Update user-facing documentation and generated defaults

**Files:**
- Modify: `README.md:44-46`
- Modify: `EA软件使用手册.html:72-84,133-134`

- [ ] **Step 1: Document the three parameters and semantics**

Explain that period 1 uses the existing names, periods 2/3 use the new names, any matching window allows a new initial order, windows use server time and may cross midnight, and exact `00:00-00:00` disables a window.

- [ ] **Step 2: Update troubleshooting wording**

Replace singular “首单时间窗口” wording with “三个首单时间窗口” where relevant and keep the existing statement that active positions/orders are unaffected.

- [ ] **Step 3: Add doc assertions**

Add tests that check README and HTML mention `时段2`, `时段3`, `00:00-00:00`, and cross-midnight semantics.

### Task 6: Compile and verify the complete change

**Files:**
- Verify: `NoMatterRiseFall_MT4.mq4`, `NoMatterRiseFall_MT5.mq5`, `tests/strategy_logic.py`, `tests/test_strategy_logic.py`, `README.md`, `EA软件使用手册.html`

- [ ] **Step 1: Run the full Python test suite**

Run: `python -m pytest tests/test_strategy_logic.py -q`

Expected: exit code 0 and no failed tests.

- [ ] **Step 2: Compile both expert advisors with the repository’s isolated MetaEditor**

Use `mt5_isolated_test\MetaEditor64.exe` with the same `/compile` and `/log` conventions as the existing `mt5_*_compile.log` files, compiling the working-tree MT5 and MT4 source files. Confirm both logs contain `0 error(s)` and no new warnings that indicate failed declarations.

- [ ] **Step 3: Inspect the final diff and status**

Run `git diff --check`, `git diff --stat`, and `git status --short`. Confirm only the feature source, tests, documentation, and the already tracked design/plan files are part of the intended change; do not stage or alter unrelated existing binaries, logs, or generated tester data.

- [ ] **Step 4: Record verification evidence**

Report the exact pytest result, both compiler results, and the main files changed. Do not claim completion until all commands exit successfully.
