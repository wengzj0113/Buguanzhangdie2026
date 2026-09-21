# 动态止损 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or **superpowers:executing-plans** to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a Chinese `动态止损` switch to MT4 and MT5 so favorable grid fills trail the group stop by the corresponding grid distance, while the default behavior remains unchanged.

**Architecture:** Keep the existing favorable-grid filled bitmasks as the source of truth. Add one deterministic stop-price calculation seam to the Python regression model and mirror the same calculation in single-group and multi-group MQL4/MQL5 stop-price functions. The GUI and persisted configuration carry the new integer switch through validation, fingerprinting, and runtime configuration.

**Tech Stack:** Python 3, pytest, MQL4, MQL5, MetaEditor command-line compilation, MT5 Strategy Tester.

---

### Task 1: Add failing regression tests for dynamic stop behavior

**Files:**
- Modify: `tests/strategy_logic.py`
- Modify: `tests/test_strategy_logic.py`

- [ ] **Step 1: Add red model tests before changing the model**

Append tests that construct `StrategyModel(..., grid_count=4, favorable_grid_enable=1, dynamic_stop_loss_enable=1)` and assert:

```python
def test_dynamic_stop_moves_buy_stop_only_for_favorable_grid_levels():
    model = StrategyModel(
        Direction.BUY, CycleMode.MODE_1, 0.01, 2.0, 500, 0.0001,
        grid_count=4, favorable_grid_enable=1, dynamic_stop_loss_enable=1,
    )
    model.on_tick(bid=1.1000, ask=1.1002)
    initial_stop = model.position.stop_loss
    spacing = 500 * 0.0001 / 4

    model.fill_grid_pending(level=1)
    assert model.position.stop_loss == pytest.approx(initial_stop)

    model.fill_favorable_grid_pending(level=1)
    assert model.position.stop_loss == pytest.approx(initial_stop + spacing)

    model.fill_favorable_grid_pending(level=2)
    assert model.position.stop_loss == pytest.approx(initial_stop + 2 * spacing)
```

Add a sell-direction test asserting favorable fills move the stop downward, and a default-off test asserting favorable fills leave the original stop unchanged. These tests must initially fail because the constructor has no dynamic-stop argument and the model has no moving-stop implementation.

- [ ] **Step 2: Add source-contract tests for both MQL sources**

Add a parameterized test for `NoMatterRiseFall_MT4.mq4` and `NoMatterRiseFall_MT5.mq5` asserting each source contains all of the following:

```python
assert "动态止损 = 0" in source
assert "dynamic_stop_loss_enable" in source
assert "动态止损必须为0或1" in source
assert "最高有利网格" in source or "FavorableGrid" in source
assert "favorable_grid_filled_mask" in source
assert "GridLevelBit" in source
```

Also assert the source GUI includes the Chinese label and both single and multi stop functions reference the dynamic configuration. Run only these new tests and confirm the expected red failure before production changes.

Run:

```powershell
python -m pytest tests/test_strategy_logic.py -k "dynamic_stop" -q
```

Expected: failures caused by the missing constructor parameter and missing MQL configuration/calculation symbols.

### Task 2: Implement the Python model seam and make the focused tests green

**Files:**
- Modify: `tests/strategy_logic.py`

- [ ] **Step 1: Add the model parameter with the required default**

Extend `StrategyModel.__init__` after `favorable_grid_enable=0` with `dynamic_stop_loss_enable=0`, store it as `self.dynamic_stop_loss_enable`, and keep all existing callers valid through the default.

- [ ] **Step 2: Add deterministic stop calculation**

Add this method next to `_levels`:

```python
def _group_stop_loss(self):
    base_stop = self._levels(
        self.position.direction, self.group_anchor_entry, self.group_stop_points,
    )[0]
    if self.dynamic_stop_loss_enable != 1 or self.grid_count < 2:
        return base_stop
    favorable_mask = self.favorable_grid_filled_mask
    if favorable_mask == 0:
        return base_stop
    highest_level = max(
        level for level in range(1, self.grid_count)
        if favorable_mask & (1 << (level - 1))
    )
    spacing = self.group_stop_points * self.point / self.grid_count
    offset = highest_level * spacing
    return round(
        base_stop + offset if self.position.direction is Direction.BUY
        else base_stop - offset,
        10,
    )
```

- [ ] **Step 3: Apply the calculated stop after every grid fill**

In `fill_grid_pending`, after updating the favorable/adverse mask and recreating `self.position`, assign `self.position.stop_loss = self._group_stop_loss()` before updating take profit. This makes adverse fills leave the stop fixed and favorable fills move it by the highest filled favorable level.

- [ ] **Step 4: Run the focused tests and the full Python suite**

Run:

```powershell
python -m pytest tests/test_strategy_logic.py -k "dynamic_stop" -q
python -m pytest -q
```

Expected: all dynamic-stop tests pass and the complete existing suite remains green.

### Task 3: Add the parameter and calculation to MT4 and MT5 single groups

**Files:**
- Modify: `NoMatterRiseFall_MT4.mq4`
- Modify: `NoMatterRiseFall_MT5.mq5`

- [ ] **Step 1: Add the Chinese input and runtime configuration field**

In both files add:

```mql
// 有利方向网格成交后是否同步移动止损：0=关闭，1=开启
input int            动态止损 = 0;
```

Add `#define DynamicStopLossEnable 动态止损`. In MT5, add `int dynamic_stop_loss_enable` to `GuiConfig`, include it in the configuration fingerprint, load it in `LoadConfigFromInputs`, carry it through `ApplyGuiConfig`, and reject values other than 0 or 1 with the Chinese validation error `动态止损必须为0或1。`. In MT4, validate the native input during `OnInit` and print the same Chinese error before returning `INIT_PARAMETERS_INCORRECT`.

- [ ] **Step 2: Add the single-group highest-level calculation**

Add a helper beside `GridLevelBit`/`GridFilledLevelCountForMask`:

```mql
int HighestFavorableGridLevel(const long mask)
  {
   for(int level = InpGridCount - 1; level >= 1; level--)
      if((mask & GridLevelBit(level)) != 0)
         return level;
   return 0;
  }
```

Implement the same helper with MT5 types/config names. Update `GroupStopPrice` in both sources so it first computes the existing anchor-based stop, then, only when `DynamicStopLossEnable == 1`, `InpGridCount >= 2`, and the favorable mask has a level, adds `level * stop_points / grid_count * point` for buys or subtracts it for sells. Normalize the final price exactly once.

- [ ] **Step 3: Keep existing protection flow as the write path**

Do not create a second order-modification path. Existing `HandleGridFill`/`Manage` calls to `SetGroupStops` and existing `StopsVerified` checks must use the updated `GroupStopPrice`; existing reverse pending placement will therefore use the dynamic stop returned by `GroupStopPrice`.

- [ ] **Step 4: Run focused source tests and compile both sources**

Run:

```powershell
python -m pytest tests/test_strategy_logic.py -k "dynamic_stop or grid_fill or protection" -q
```

Compile `NoMatterRiseFall_MT4.mq4` with MetaEditor and inspect `NoMatterRiseFall_MT4.log`; compile `NoMatterRiseFall_MT5.mq5` and inspect `NoMatterRiseFall_MT5.log`. Expected: zero errors and zero warnings.

### Task 4: Add the Chinese MT5 GUI and multi-group calculation

**Files:**
- Modify: `NoMatterRiseFall_MT4.mq4`
- Modify: `NoMatterRiseFall_MT5.mq5`

- [ ] **Step 1: Add the GUI enum field**

MT5's custom GUI must register `dynamic_stop_loss_enable` in the dropdown option-count function, render its options as `关闭` and `开启`, map the draft value to index 0/1, and accept the selection in `GuiSetDropdownValue`. Add the field to the grid-page key arrays used for field positioning and dropdown hit-testing. Render the Chinese label `动态止损` in the grid page without introducing English text. MT4 has no custom GUI layer in the current source; its native input label `动态止损` is the user-facing setting.

- [ ] **Step 2: Add the multi-group calculation**

Add `MultiHighestFavorableGridLevel` and update `MultiStopPrice` with the same formula and guards as the single-group calculation, using `group.favorable_grid_filled_mask`, `group.stop_points`, `group.anchor_price`, and `g_gui_applied_config.grid_count`. This preserves independent dynamic stops for parallel groups.

- [ ] **Step 3: Add multi-group source assertions**

Extend the tests to assert `MultiStopPrice` reads `favorable_grid_filled_mask`, `MultiSetStops` remains the writer, and the grid GUI contains `动态止损` in both source files. Run the focused suite and compile both files again.

### Task 5: End-to-end verification and artifact delivery

**Files:**
- Modify: `README.md`
- Modify: `mt5_auto_test_normal.ini` or add a dedicated dynamic-stop tester configuration if the existing test settings cannot express the new parameter.
- Include: compiled `NoMatterRiseFall_MT4.ex4`, `NoMatterRiseFall_MT5.ex5`

- [ ] **Step 1: Document the parameter in Chinese**

Add a concise README entry: `动态止损=0` keeps the stop fixed; `动态止损=1` trails the stop one grid spacing per highest favorable grid level, while adverse grid fills do not loosen it.

- [ ] **Step 2: Run the complete verification suite**

Run:

```powershell
python -m pytest -q
git diff --check
```

Compile both MQL sources one final time. Copy the resulting binaries to:

```text
C:\Program Files\MetaTrader 5\MQL5\Experts\不管涨跌复刻\NoMatterRiseFall_MT5.ex5
C:\Program Files\MetaTrader 5\MQL5\Experts\NoMatterRiseFall_MT5.ex5
C:\Program Files (x86)\FXGiants MetaTrader 4\MQL4\Experts\不管涨跌复刻\NoMatterRiseFall_MT4.ex4
```

- [ ] **Step 3: Run the MT5 automatic tester**

Use the existing MT5 tester configuration with `动态止损=1`, `有利方向加单=1`, and `网格数量>=4`. Confirm the tester exits successfully and the journal contains the dynamic-stop configuration or successful stop modifications without compilation/runtime errors.

- [ ] **Step 4: Audit the final state**

Review `git diff`, source-contract tests, Python tests, compiler logs, binary timestamps, and tester logs. Verify default behavior remains covered by the existing tests and the new dynamic behavior is covered for buy, sell, adverse fill, favorable fill, and multi-group source paths.
