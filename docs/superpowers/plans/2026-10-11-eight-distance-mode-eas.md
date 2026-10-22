# Split Distance-Mode EAs Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deliver eight fixed-mode EA entry points for MT4 and MT5 while preserving the existing all-mode EA as a compatibility build and keeping order-group management in shared platform cores.

**Architecture:** Keep `NoMatterRiseFall_MT4.mq4` and `NoMatterRiseFall_MT5.mq5` unchanged as the legacy all-mode entry points. Create one shared `.mqh` core per platform for the eight new EA families, using current source behavior as the starting point; compile each of eight mode-specific wrappers with one strategy adapter and a compile-time profile ID. The cores consume a common entry-signal contract and contain no runtime mode selector. Namespace new state by profile and version, reserve each account/symbol/Magic scope so a second EA cannot adopt or co-manage it, and build/package all 16 new outputs independently.

**Tech Stack:** MQL4, MQL5, Python `pytest`, PowerShell, MT4/MT5 MetaEditor.

---

## Repository map and implementation choices

- `NoMatterRiseFall_MT4.mq4` and `NoMatterRiseFall_MT5.mq5` are the current all-mode monoliths. They contain input declarations, strategy-specific signal logic, order-group/grid/take-profit/risk management, persistence, and lifecycle handlers. MT5 also contains `GuiConfig`, configuration fingerprints, custom-panel rendering, Apply, and chart-event handling.
- `tests/strategy_logic.py` and `tests/test_strategy_logic.py` hold the Python behavior model and regressions for the current eight modes, OCO, multi-groups, baskets, and box-breakout recovery. Keep those tests passing as the source implementation moves.
- `scripts/compile-mql.ps1` currently compiles the two canonical sources for `-Target MT4|MT5|Both`. `tests/test_build_workflow.py` verifies the current build contract; it is already present as a user-created untracked file, so preserve its existing contents if it needs an update.
- `Indicators/MT4/ZigZag.mq4` and `.ex4`, and `Indicators/MT5/Examples/ZigZag.mq5` and `.ex5`, are the current ZigZag dependency files.
- Update `README.md` and `EA软件使用手册.html`; do not modify the XAU NetRR variants or unrelated user changes.
- At implementation start, inspect `git status --short` and save SHA-256 hashes of both canonical source files. Retain every pre-existing user edit, compare those source hashes after the split-core work, and stage/commit only the files named in each task.

The profile IDs are fixed as `legacy=0`, `fixed_distance=1`, `candle_height=2`, `average_candle_height=3`, `long_candle=4`, `bollinger_range=5`, `zigzag_swing=6`, `box_height=7`, and `box_breakout=8`. The eight new EA names are `FixedDistance`, `CandleHeight`, `AverageCandleHeight`, `LongCandle`, `BollingerRange`, `ZigZagSwing`, `BoxHeight`, and `BoxBreakout`; each name has an MT4 and MT5 output. Keep legacy Magic `20260830`. Assign new defaults from `2026101101` through `2026101116`, one value per platform/profile, and use MT4 `int` / MT5 `ulong` declarations while keeping all values within positive signed 32-bit range. MQL conditional compilation selects profiles with `#define NMR_PROFILE_<NAME>` and `#ifdef` guards; do not use numeric `#if` expressions, which are not part of the documented MQL preprocessor directive set.

MQL input lists are fixed at compile time: MT4 cannot hide input fields dynamically after a user changes another input. Therefore `布林带周期` and `布林带标准差` stay visible in FixedDistance, AverageCandleHeight, and BoxHeight profiles because each supports Bollinger-based first-direction selection; the values affect direction only when that selector is set to Bollinger. Keep the same profile-specific fields visible in the MT5 panel for consistent settings. Preserve `v_enable` on the legacy builds and all MT5 builds; omit it from new MT4 profiles because the existing MT4 implementation has no panel and does not use it.

## Implementation tasks

### Task 1: Add fixed-profile input and identity contract tests

**Files:**
- Create: `tests/test_ea_profile_contract.py`
- Test: `tests/test_ea_profile_contract.py`
- Verify: `tests/test_strategy_logic.py`

- [ ] **Step 1: Define the expected profile-to-mode and profile-to-input matrix**

In `tests/test_ea_profile_contract.py`, define the eight profile names and map them to the existing source semantics: FixedDistance→`DISTANCE_FIXED`, CandleHeight→`DISTANCE_CANDLE_RANGE`, AverageCandleHeight→`DISTANCE_AVERAGE_CANDLE_RANGE`, LongCandle→`DISTANCE_LONG_CANDLE`, BollingerRange→`DISTANCE_BOLLINGER_RANGE`, ZigZagSwing→`DISTANCE_ZIGZAG_RANGE`, BoxHeight→`DISTANCE_BOX_RANGE`, and BoxBreakout→`DISTANCE_BOX_BREAKOUT`. Define each expected public input set from the table in `docs/superpowers/specs/2026-10-11-distance-mode-eas-design.md`, adding the common inputs listed there. Include `距离模式` only in legacy builds; include `v_enable` in new MT5 profiles and not in new MT4 profiles.

- [ ] **Step 2: Add a recursive source-contract reader and profile tests**

The reader follows quoted MQL `#include` paths relative to the including file, reads the wrapper's single `#define NMR_PROFILE_<NAME>`, and evaluates nested `#ifdef`, `#ifndef`, `#else`, and `#endif` around input declarations. Add tests named `test_each_profile_has_one_fixed_identity`, `test_each_profile_exposes_only_common_and_mode_inputs`, `test_new_profile_magic_defaults_are_unique`, and `test_legacy_sources_keep_all_mode_inputs_and_magic`. Assert that every fixed wrapper includes exactly one matching adapter and never declares `input DistanceMode`; assert that the two canonical legacy sources retain `input DistanceMode` and Magic `20260830`.

- [ ] **Step 3: Run the contract tests and confirm the expected red result**

Run: `python -m pytest tests/test_ea_profile_contract.py -q`

Expected: FAIL because fixed-profile wrappers and profile-specific input guards do not exist yet. Do not change canonical strategy logic in this task.

### Task 2: Create platform cores while leaving legacy files untouched

**Files:**
- Create: `NoMatterRiseFall_MT4_Core.mqh`
- Create: `NoMatterRiseFall_MT5_Core.mqh`
- Test: `tests/test_ea_profile_contract.py`

- [ ] **Step 1: Create the split MT4 core from the current source**

Copy the current MT4 implementation into `NoMatterRiseFall_MT4_Core.mqh`, omitting only top-level `#property` directives. Keep `NoMatterRiseFall_MT4.mq4` byte-for-byte unchanged as the legacy all-mode source. In the new core, place common declarations and order management behind profile guards while retaining the copied all-mode logic as the initial parity reference; do not route the canonical legacy build through the new core. The copy must include the current working source contents so the new EA family starts from the behavior currently in this shared workspace.

- [ ] **Step 2: Create the split MT5 core from the current source**

Copy the current MT5 implementation into `NoMatterRiseFall_MT5_Core.mqh`, omitting only top-level `#property` and `#include <Trade/Trade.mqh>` directives. Keep `NoMatterRiseFall_MT5.mq5` byte-for-byte unchanged as the legacy all-mode source. In the new core, retain the legacy `GuiConfig` and mode dispatch only as an extraction baseline; subsequent profile tasks remove the runtime mode selector from profiles 1–8 while leaving the canonical source available for rollback. The copy must include the current working source contents so the new EA family starts from the behavior currently in this shared workspace.

- [ ] **Step 3: Run current logic tests and verify the legacy sources remain unchanged**

Run: `python -m pytest tests/test_strategy_logic.py -q`

Run: `powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\compile-mql.ps1 -Target Both`

Expected: all existing Python tests pass; MetaEditor reports zero errors for both canonical sources and refreshes `NoMatterRiseFall_MT4.ex4` and `NoMatterRiseFall_MT5.ex5`. Record compiler warnings and output paths. SHA-256 hashes for both canonical source files must match the values recorded before extraction; existing user diffs remain untouched.

- [ ] **Step 4: Commit only the new core files**

Commit only `NoMatterRiseFall_MT4_Core.mqh` and `NoMatterRiseFall_MT5_Core.mqh` with message `refactor: create shared cores for fixed-profile EAs`. Do not stage the pre-existing dirty canonical sources or generated binaries.

### Task 3: Add the entry-signal contract and profile ownership foundation

**Files:**
- Create: `NoMatterRiseFall_EntrySignal_MT4.mqh`
- Create: `NoMatterRiseFall_EntrySignal_MT5.mqh`
- Modify: `NoMatterRiseFall_MT4_Core.mqh`
- Modify: `NoMatterRiseFall_MT5_Core.mqh`
- Modify: `tests/test_ea_profile_contract.py`

- [ ] **Step 1: Declare the platform-specific signal contract**

Add the same logical contract to each platform header, using native MQL types:

```mql
enum EntryAction
  {
   ENTRY_NONE = 0,
   ENTRY_MARKET = 1,
   ENTRY_INITIAL_OCO = 2
  };

struct EntrySignal
  {
   int      action;
   int      direction;
   int      stop_points;
   int      take_profit_points;
   datetime signal_time;
   long     signal_id;
   double   buy_stop_price;
   double   sell_stop_price;
  };

bool ProfileInitialize(string &error);
void ProfileShutdown();
bool ProfileBuildEntrySignal(EntrySignal &signal);
void ProfileRecordEntryResult(const EntrySignal &signal, const bool accepted);
```

The core resets an output signal before calling the adapter. `ENTRY_MARKET` requires positive stop/take-profit distances and a stable signal ID. `ENTRY_INITIAL_OCO` carries both initial pending prices, distances, time, and ID. A failed submission is reported through `ProfileRecordEntryResult` so CandleHeight and BoxBreakout can preserve retry/de-duplication behavior.

- [ ] **Step 2: Add profile-aware state identity without changing legacy keys**

For profile IDs 1–8, form a short state suffix from account, symbol, Magic, numeric profile ID, and schema version `1`; leave the canonical legacy source's state prefix untouched. Keep the account/server/symbol/Magic execution reservation shared by all profiles so identical Magic scopes collide; record the profile ID in the reservation and refuse a second live owner. In both MT4 and MT5 initialization, refuse to start when the requested Magic has existing exposure or persisted state owned by another profile. Do not use order comments as the ownership test.

- [ ] **Step 3: Assert adapter and identity requirements**

Add assertions to `tests/test_ea_profile_contract.py` for the signal fields, profile-aware state suffix, legacy prefix preservation, and a second instance failing ownership when account/symbol/Magic are identical. Run: `python -m pytest tests/test_ea_profile_contract.py -q`. Expected: PASS for the interface/identity cases; profile input cases remain red until the following tasks add the wrappers.

### Task 4: Implement FixedDistance and LongCandle adapters on both platforms

**Files:**
- Create: `profiles/mt4/FixedDistance.mqh`, `profiles/mt4/LongCandle.mqh`
- Create: `profiles/mt5/FixedDistance.mqh`, `profiles/mt5/LongCandle.mqh`
- Create: `NoMatterRiseFall_FixedDistance_MT4.mq4`, `NoMatterRiseFall_FixedDistance_MT5.mq5`
- Create: `NoMatterRiseFall_LongCandle_MT4.mq4`, `NoMatterRiseFall_LongCandle_MT5.mq5`
- Modify: both platform core `.mqh` files and `tests/test_ea_profile_contract.py`

- [ ] **Step 1: Add the four fixed-mode wrapper entry points**

Each wrapper defines exactly one profile macro such as `NMR_PROFILE_FIXED_DISTANCE`, keeps the platform `#property` directives, includes `<Trade/Trade.mqh>` for MT5, and includes the platform core. The core conditionally includes only the matching strategy adapter and input block using `#ifdef`. These wrappers do not declare or expose `DistanceMode`.

- [ ] **Step 2: Implement fixed-distance signal generation**

Reuse the existing preset/Bollinger first-direction rules and fixed stop/take-profit values. Preserve the middle-band tie behavior (wait without market submission). Declare `固定止损距离`, `固定止盈距离`, `首单方向`, `首单方向确定方式`, `布林带周期`, and `布林带标准差` only in FixedDistance inputs, plus common fields and the platform-specific `v_enable` rule above.

- [ ] **Step 3: Implement long-candle signal generation**

Reuse the current completed-bar body-direction check, doji rejection, and 20-bar comparison. Expose only `固定止损距离` and `固定止盈距离` plus common fields. Do not add a comparison-window input.

- [ ] **Step 4: Run the focused profile and behavior tests**

Run: `python -m pytest tests/test_ea_profile_contract.py tests/test_strategy_logic.py -k "profile or long_candle or first_direction" -q`

Expected: both profiles expose exactly the expected input sets; fixed-mode tie and long-candle boundary regressions pass on MT4 and MT5 source contracts.

### Task 5: Implement CandleHeight and AverageCandleHeight adapters

**Files:**
- Create: `profiles/mt4/CandleHeight.mqh`, `profiles/mt4/AverageCandleHeight.mqh`
- Create: `profiles/mt5/CandleHeight.mqh`, `profiles/mt5/AverageCandleHeight.mqh`
- Create: `NoMatterRiseFall_CandleHeight_MT4.mq4`, `NoMatterRiseFall_CandleHeight_MT5.mq5`
- Create: `NoMatterRiseFall_AverageCandleHeight_MT4.mq4`, `NoMatterRiseFall_AverageCandleHeight_MT5.mq5`
- Modify: both platform core `.mqh` files and `tests/test_ea_profile_contract.py`

- [ ] **Step 1: Preserve CandleHeight's two distinct entry actions**

For `KORDER_ONCE_PER_BAR`, return `ENTRY_INITIAL_OCO` with the previous candle high/low, one bar signal time, and the existing signal ID; keep OCO reconciliation and the per-bar de-duplication state. For repeated entries, return the existing market-breakout signal with `开单方式` mapping. Expose candle min/max, `开单方式`, `K线开单模式`, and `K线多组`, plus common settings. Keep `K线多组` behavior only in this adapter/core interface.

- [ ] **Step 2: Preserve AverageCandleHeight distance and first-direction rules**

Use only completed candles in the current average window; keep the current invalid-data behavior and rounding. Expose `平均K线根数`, `平均止损倍数`, `平均止盈倍数`, `首单方向`, `首单方向确定方式`, `布林带周期`, and `布林带标准差`, plus common settings.

- [ ] **Step 3: Test OCO, repeated-entry, multi-group, and average-boundary behavior**

Run: `python -m pytest tests/test_ea_profile_contract.py tests/test_strategy_logic.py -k "profile or candle or average or oco or multi_group" -q`

Expected: one-per-bar still reconciles both OCO fills without creating a third basket; repeated mode preserves its trigger rule; multi-group entries keep distinct group IDs; average distances use N completed candles and reject invalid history.

### Task 6: Implement BollingerRange and ZigZagSwing adapters

**Files:**
- Create: `profiles/mt4/BollingerRange.mqh`, `profiles/mt4/ZigZagSwing.mqh`
- Create: `profiles/mt5/BollingerRange.mqh`, `profiles/mt5/ZigZagSwing.mqh`
- Create: `NoMatterRiseFall_BollingerRange_MT4.mq4`, `NoMatterRiseFall_BollingerRange_MT5.mq5`
- Create: `NoMatterRiseFall_ZigZagSwing_MT4.mq4`, `NoMatterRiseFall_ZigZagSwing_MT5.mq5`
- Modify: both platform core `.mqh` files and `tests/test_ea_profile_contract.py`

- [ ] **Step 1: Preserve BollingerRange touch direction and distance limits**

Only upper/lower-band touches create signals; map direction through `开单方式`, retain configured stop percentage, reward/risk ratio, and inclusive min/max checks. Expose the band period/deviation, `开单方式`, `布林带止损百分比`, `布林带盈亏比`, and min/max stop distance plus common settings. Do not expose first-direction fields in this profile.

- [ ] **Step 2: Preserve ZigZagSwing confirmed-pivot and broker-distance behavior**

Use the current fourth/fifth confirmed extrema selection, depth/deviation/backstep parameters, minimum/maximum band distance, stop percentage, take-profit multiplier, and direction mapping. Initialize the platform indicator in `ProfileInitialize`; fail initialization with a clear message if the indicator cannot be loaded; release its handle in `ProfileShutdown` on MT5. Expose only the seven ZigZag parameters, `开单方式`, and common settings.

- [ ] **Step 3: Test band boundaries and ZigZag dependency behavior**

Run: `python -m pytest tests/test_ea_profile_contract.py tests/test_strategy_logic.py -k "profile or bollinger or zigzag" -q`

Expected: upper/lower touch direction and inclusive distance limits match existing tests; invalid pivots or broker-invalid distances produce no entry; source-contract checks verify `ProfileInitialize` rejects an invalid indicator handle. Confirm the missing-indicator/no-order case in the MT4/MT5 terminal matrix.

### Task 7: Implement BoxHeight and BoxBreakout adapters

**Files:**
- Create: `profiles/mt4/BoxHeight.mqh`, `profiles/mt4/BoxBreakout.mqh`
- Create: `profiles/mt5/BoxHeight.mqh`, `profiles/mt5/BoxBreakout.mqh`
- Create: `NoMatterRiseFall_BoxHeight_MT4.mq4`, `NoMatterRiseFall_BoxHeight_MT5.mq5`
- Create: `NoMatterRiseFall_BoxBreakout_MT4.mq4`, `NoMatterRiseFall_BoxBreakout_MT5.mq5`
- Modify: both platform core `.mqh` files and `tests/test_ea_profile_contract.py`

- [ ] **Step 1: Preserve BoxHeight's distance-only behavior**

Use the existing M1 rolling or daily-session range and inclusive min/max bounds to resolve equal stop/take-profit distances. Do not add a breakout trigger. Expose box time mode, lookback hours, start/end, min/max height, `首单方向`, `首单方向确定方式`, and the Bollinger period/deviation fields used by that selector, plus common settings.

- [ ] **Step 2: Preserve BoxBreakout's confirmation and retry state**

Keep the current confirmed-box discovery, two consecutive closed-bar breakout confirmation, direction mapping, frozen signal time/ID, expiry, and retry behavior. Return the confirmed entry through `EntrySignal` and call `ProfileRecordEntryResult` after order submission. Expose the complete box-breakout parameter set and `开单方式`, plus common settings; do not expose BoxHeight's time-window fields.

- [ ] **Step 3: Test both box modes and restart recovery**

Run: `python -m pytest tests/test_ea_profile_contract.py tests/test_strategy_logic.py -k "profile or box_height or box_breakout" -q`

Expected: BoxHeight uses range only; BoxBreakout waits for a confirmed box and two closes, restores and retries the same failed signal once without a duplicate entry, and expires stale signals before replay.

### Task 8: Enforce profile-safe order ownership and state recovery

**Files:**
- Modify: `NoMatterRiseFall_MT4_Core.mqh`
- Modify: `NoMatterRiseFall_MT5_Core.mqh`
- Modify: `tests/test_ea_profile_contract.py`
- Create: `validation/distance-mode-ea-terminal-checks.md`

- [ ] **Step 1: Add persisted owner metadata to the shared account/symbol/Magic reservation**

Use the existing MT5 scope registry and execution-ownership path as the reference. Extend it to store the profile ID and state schema alongside the reserved account/symbol/Magic key. Add the equivalent fail-closed checks to MT4. Reject initialization if a different live profile owns the key, if persisted state belongs to another profile/version, or if managed exposure exists without matching profile state. Do not delete, close, or adopt the discovered orders.

- [ ] **Step 2: Preserve same-profile restart and reject duplicate charts**

After a clean restart, the same profile and Magic may load its own state and resume existing groups. A second chart using the same account, symbol, and Magic must fail initialization even when its profile ID matches. A different profile with a different default Magic must initialize with independent group counters, box/candle state, locks, and configuration fingerprints.

- [ ] **Step 3: Write the terminal validation matrix**

In `validation/distance-mode-ea-terminal-checks.md`, document the exact MT4/MT5 tester fixtures and expected signal/order outputs for all eight modes against the matching legacy mode. Also record demo-terminal cases: run two distinct profiles with defaults on one symbol; attach a second chart with the same Magic and verify refusal; restart one profile with an active test group and verify recovery; try a profile against foreign/unowned exposure and verify no order changes; verify missing ZigZag prevents initialization; keep a legacy group attached until flat, then start its new profile with a fresh default Magic. Record terminal version, account mode, symbol, profile IDs, Magic values, and observed result for every case.

- [ ] **Step 4: Test ownership source contracts and run all Python regressions**

Run: `python -m pytest tests/test_ea_profile_contract.py tests/test_strategy_logic.py -q`

Expected: all existing order-group, basket, OCO, grid, stop, recovery, and mode regressions pass; profile-contract tests prove state/profile separation and collision refusal. Manual terminal cases remain pending until MT4/MT5 validation.

### Task 9: Make the MT5 chart panel profile-specific

**Files:**
- Modify: `NoMatterRiseFall_MT5_Core.mqh`
- Modify: `tests/test_ea_profile_contract.py`
- Verify: `tests/test_strategy_logic.py`

- [ ] **Step 1: Remove mode selection from fixed-profile panels**

Compile the distance-mode dropdown, `distance_mode` editable field, mode-selection dropdown options, and all unrelated profile page fields only in legacy profile 0. In profiles 1–8 render the fixed profile name as read-only text. Keep Apply, pause/resume, close/delete, common risk/order fields, and the profile's own editable settings.

- [ ] **Step 2: Version profile-specific configuration fingerprints**

For profiles 1–8, fingerprint the profile ID, schema version, common applied values, and that profile's inputs only. Keep the existing legacy fingerprints/migrations in profile 0. Update `ValidatePersistedConfigForMagic`, `ApplyGuiConfig`, input-to-`GuiConfig` conversion, saved configuration writes, and restart loads together so hidden legacy mode fields cannot invalidate or mutate a fixed-profile configuration.

- [ ] **Step 3: Test panel visibility, Apply, and restart**

Add tests that inspect each profile's field-key list and assert that no fixed panel contains `distance_mode` or another profile's fields. Assert the fixed profile label is read-only, Apply validates and saves only displayed fields, and a profile/config fingerprint mismatch refuses state adoption. Run: `python -m pytest tests/test_ea_profile_contract.py tests/test_strategy_logic.py -k "profile or mt5_gui or fingerprint" -q`.

### Task 10: Extend compile and package workflows for 16 fixed outputs

**Files:**
- Modify: `scripts/compile-mql.ps1`
- Modify: `.gitignore`
- Create: `scripts/package-distance-mode-eas.ps1`
- Create: `tests/test_distance_mode_build.py`
- Verify: `tests/test_build_workflow.py`

- [ ] **Step 1: Add a profile selector without changing the legacy command**

Add `-Profile Legacy|FixedDistance|CandleHeight|AverageCandleHeight|LongCandle|BollingerRange|ZigZagSwing|BoxHeight|BoxBreakout|All`. Keep the existing `-Target MT4|MT5|Both` parameter and preserve its default behavior: `-Target Both` with no profile compiles the two canonical legacy sources. `-Profile FixedDistance -Target MT4` compiles one fixed profile; `-Profile All -Target Both` compiles all 16 new outputs. Use the existing MetaEditor discovery, log parsing, zero-error check, and refreshed-output check for every source.

- [ ] **Step 2: Add build-script contract tests**

In `tests/test_distance_mode_build.py`, assert that the default/legacy Both target resolves only the canonical files, a single profile resolves exactly one source per selected platform, All resolves exactly 16 source paths, and all output extensions are `.ex4`/`.ex5`. Run: `python -m pytest tests/test_distance_mode_build.py tests/test_build_workflow.py -q`.

- [ ] **Step 3: Package per-profile outputs and the ZigZag indicator**

Make `scripts/package-distance-mode-eas.ps1` copy compiled outputs into `dist/DistanceModeEAs/<Profile>/MT4/Experts` and `dist/DistanceModeEAs/<Profile>/MT5/Experts`. Copy `Indicators/MT4/ZigZag.ex4` and `Indicators/MT5/Examples/ZigZag.ex5` only into the ZigZagSwing profile's matching indicator folders, along with the corresponding `.mq4`/`.mq5` source files and an install note. Fail packaging if any expected EA output or ZigZag dependency is missing or empty. Test the copy matrix with temporary fixture files so tests do not modify real `.ex4`/`.ex5` artifacts.

- [ ] **Step 4: Ignore generated release bundles**

Add `dist/` to `.gitignore` so package outputs remain local release artifacts and do not enter commits by accident.

- [ ] **Step 5: Run the actual canonical and split builds**

Run: `powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\compile-mql.ps1 -Target Both`

Then run: `powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\compile-mql.ps1 -Profile All -Target Both`

Expected: all 18 targets (2 legacy + 16 fixed) report zero compiler errors, each expected output is refreshed, and warnings and paths are recorded. Run the package script and verify all eight profile folders exist and only ZigZagSwing contains indicator dependencies.

### Task 11: Update release docs and complete verification

**Files:**
- Modify: `README.md`
- Modify: `EA软件使用手册.html`
- Modify: `validation/distance-mode-ea-terminal-checks.md`
- Verify: all 18 source/output pairs

- [ ] **Step 1: Document the eight fixed EA choices and parameter lists**

Explain each profile's entry rule, public mode-specific inputs, shared order-management settings, unique default Magic, and same-symbol multi-EA setup. Keep the legacy eight-mode EA under a visibly separate compatibility label; state that old chart templates still load that legacy filename and that new names select fixed profiles.

- [ ] **Step 2: Document migration and dependency behavior**

State that the legacy EA manages active groups until flat; fixed EAs refuse unowned/foreign exposure and do not silently adopt or close it. Explain that matching common `.set` values can be reused only after review, profile-specific settings must be checked, and the old `距离模式` value does not select a new EA's profile. Include the ZigZag indicator install paths and explain that the other seven profiles do not need that dependency.

- [ ] **Step 3: Run final automated tests and compiler validation**

Run: `python -m pytest -q`

Run both canonical and all-profile build commands from Task 10, then run `git diff --check`. Expected: all automated tests pass, MetaEditor reports zero errors, all 18 outputs are present and refreshed, and `git diff --check` is clean for the task's own changes. Confirm no pre-existing user edits, XAU files, parameter reports, or spreadsheet content were staged.

- [ ] **Step 4: Commit implementation in focused commits**

Commit each completed task's production and test files together. Keep generated `.ex4`/`.ex5` files only if they are tracked deliverables in this repository; do not stage any pre-existing unrelated `.ex4`/`.ex5` changes, the XAU NetRR files, or user-created docs and spreadsheets.

## Spec coverage check

- Eight fixed entries, two platform builds, mode-specific input lists, immutable profile names, signal identity, and shared order management: Tasks 1–7.
- MT4/MT5 same-symbol parallel isolation, unique Magic defaults, profile state, duplicate ownership rejection, fail-closed recovery, and flat-only legacy transition: Task 8.
- MT5 profile label, no mode selector, profile-only fields, Apply and fingerprint/restart behavior: Task 9.
- Legacy `Both` build compatibility, single-profile and all-profile builds, 16 new outputs, ZigZag-only dependency packaging: Task 10.
- README, HTML manual, migration guidance, tests, and MetaEditor verification: Task 11.

## Self-review

- No `TODO`, `TBD`, or unspecified file placeholders are used.
- The canonical legacy source files retain the current all-mode inputs, Magic default, and migration behavior; fixed wrappers cannot expose `DistanceMode`.
- The signal contract includes market and paired-OCO data plus signal ID/time so order de-duplication and retry behavior remain representable.
- The same Magic reservation remains shared to reject duplicate managers, while profile identity versions persistent strategy state; this avoids making distinct state paths accidentally permit the same orders to be managed by two EAs.
- The MT4 input-page limitation is handled explicitly: profile-specific values are hidden at compile time, while Bollinger direction settings remain visible in the three profiles that can use them.
- The plan covers all eight rows in the approved spec and retains the required canonical `-Target Both` build.
