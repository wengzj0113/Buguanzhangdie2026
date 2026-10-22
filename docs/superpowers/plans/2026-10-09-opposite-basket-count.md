# Opposite Basket Count Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a default-one/two-basket setting so each normal initial-entry event can create its original basket and, when configured to two, one independently managed basket in the opposite direction.

**Architecture:** Keep the current single-basket entry and management path untouched for the default value. For value two, route the same resolved entry signal and locked stop/take-profit distances through the existing group-aware manager, creating unique group records and order comments for the original and opposite baskets. Persist pair-creation progress so a rejected or interrupted second order can be reconciled without duplicating the first. Apply the same behavior to canonical and XAU NetRR MT4/MT5 editions while preserving their platform-specific configuration and risk checks.

**Tech Stack:** MQL4, MQL5, Python strategy model and pytest, PowerShell MetaEditor build script, README/HTML parameter documentation.

---

## File and component map

- `NoMatterRiseFall_MT4.mq4`, `NoMatterRiseFall_MT5.mq5`: canonical input parameter, validation, entry routing, basket initialization/recovery, and UI configuration wiring on MT5.
- `NoMatterRiseFall_MT4_XAU_NetRR_v2_10.mq4`, `NoMatterRiseFall_MT5_XAU_NetRR_v2_10.mq5`: matching feature in the shipped XAU editions, retaining their NetRR filters and checks.
- `tests/strategy_logic.py`, `tests/test_strategy_logic.py`: small executable model for basket direction/pair state and source-contract checks for all four editions.
- `README.md`, `README_XAU_NetRR_v2_10.md`, `EA软件使用手册.html`: parameter behavior and interaction with K-line entry/multiple-group settings.
- `scripts/compile-mql.ps1`: existing build entry point for canonical MT4/MT5 files; use the discovered MetaEditor executables to compile the two XAU source paths separately without expanding this script's product scope.

## Invariants

1. `篮子数量=1` is the default and preserves the complete pre-feature dispatch: the legacy single-group route stays in use except where the existing `距离模式=K线高度` plus `K线多组=1` already selects the group manager.
2. `篮子数量=2` means two baskets per accepted initial-entry event. It does not cap simultaneous groups created by the existing `K线多组=1` feature; that setting continues to control whether separate K-line signals may create more groups.
3. Resolve entry direction, stop distance, take-profit distance, and first-order volume once in the existing `Manage()` first-entry path. Branch immediately before its legacy `OpenMarket` call. The second basket uses the exact opposite direction and same distances/volume; each basket anchors protection to its own fill price.
4. Assign unique group IDs/comments and persist each group independently. No group lookup, stop modification, grid, cycle progression, reversal, or normal take-profit cleanup may match the other group.
5. Preserve the K-line once-per-bar initial pending pair semantics: one side fills, the other pending order is canceled, and only then is the opposite market basket initialized.
6. MT5 basket count 2 requires a hedging account. On a netting account, reject the setting clearly before trading; do not let opposite deals net against one another and pretend they are independent baskets.
7. Keep existing account/magic-wide fail-safe cleanup for insufficient funds and configured maximum-reversal cleanup.
8. Changing the setting while baskets are active does not add or remove a basket in those existing groups; the new value applies to the next accepted initial-entry event.
9. Select the manager for existing exposure from persisted/order state, not only from the current input. A live legacy basket remains on the legacy manager until flat; live group-managed baskets stay on the group manager even if the input changes back to 1.

## Task 1: Specify pair-state behavior in the test model

**Files:**
- Modify: `tests/strategy_logic.py`
- Modify: `tests/test_strategy_logic.py`

- [ ] Add a pure helper that validates basket count as 1 or 2 and resolves a pair as `(original_direction,)` or `(original_direction, opposite_direction)`; reject all other counts.
- [ ] Add a tiny pair-launch state model with statuses `pending_primary`, `pending_opposite`, `active`, and `complete`; record successful group IDs so retries never reissue an already-confirmed leg.
- [ ] Add tests for BUY→BUY/SELL, SELL→SELL/BUY, count 1 yielding exactly one leg, invalid count rejection, and retry after only the primary leg succeeds without duplicate primary issuance.
- [ ] Add a test that each leg carries the same locked stop/take-profit distances and volume while retaining its own direction and group ID.
- [ ] Run `pytest tests/test_strategy_logic.py -q` and confirm these new tests fail before MQL implementation because the helpers do not yet exist.

## Task 2: Add the parameter and validation consistently

**Files:**
- Modify: all four MQL sources listed in the file map
- Modify: `tests/test_strategy_logic.py`

- [ ] Add `input int 篮子数量 = 1` in the strategy/entry input section in each edition, adjacent to `K线多组`; include the required `[开单]` comment and keep its length within the repository's 63-character parameter-comment check.
- [ ] Put the compact group/leg identity at the start of order comments, ahead of the user-editable comment, and keep the identity within broker/platform comment limits. Confirm group matching still recognizes comments after the broker's documented comment transformations and add a long-user-comment case to the source/model checks.
- [ ] In MT4 and MT5 initialization/config validation, accept only 1 or 2 and reject any other value with the repository's established invalid-parameter behavior.
- [ ] In MT5, when basket count is 2, require `ACCOUNT_MARGIN_MODE_RETAIL_HEDGING` and fail initialization with a clear diagnostic on netting/exchange accounts. Keep MT4 validation platform-appropriate.
- [ ] In MT5 `GuiConfig`, config fingerprint/snapshot/apply/validation paths, copy and validate the input so applying chart-panel settings cannot silently omit or reset the new value.
- [ ] Enforce the MT5 hedging-account requirement in both startup validation and any runtime GUI configuration apply path; changing the mode to 2 on a netting account must leave trading paused and report the reason.
- [ ] Update the parameter-order expectations for all four sources and add source-contract assertions for default 1 and validation of 1/2.
- [ ] Run the focused parameter organization and source-contract pytest cases; fix failures before continuing.

## Task 3: Generalize group entry initialization without changing signal resolution

**Files:**
- Modify: `NoMatterRiseFall_MT4.mq4`
- Modify: `NoMatterRiseFall_MT5.mq5`
- Modify: the corresponding XAU NetRR sources

- [ ] Extract or add a group-entry preparation boundary that receives the already-resolved first direction, stop points, take-profit points, first-order lots, and entry-event identity. Do not duplicate preset/Bollinger/K-line/long-candle/ZigZag/box signal calculations inside the group manager.
- [ ] Branch at the existing resolved-entry point immediately before `OpenMarket` in each `Manage()` implementation. Keep all existing direction resolution, distance resolution, time/spread/GUI/XAU gates, and lot calculation single-sourced; count 1 continues through the original `OpenMarket` branch.
- [ ] For `篮子数量=1`, preserve the current manager dispatch exactly, including the existing K-line multiple-group route when `距离模式=K线高度` and `K线多组=1`.
- [ ] For `篮子数量=2`, initialize the primary and opposite `MultiGroupState` records with distinct IDs, each with its own first direction, cycle index 0, locked distances, lots, and empty grid/reversal state.
- [ ] Open and identify the primary position through the existing group-scoped market-order helpers. Read back its actual fill and initialize anchor, totals, stop/take-profit protection, reverse pending order, and grid pending order using the current per-group routines.
- [ ] Open the opposite market order through the same group-scoped helper and initialize its protection/pendings independently. Verify that a failure to protect one basket pauses only that basket's follow-up orders and retains enough state for recovery.
- [ ] Ensure initial risk/entry gates (time window, spread, GUI permission, broker distance checks) run before pair launch. In XAU NetRR editions, calculate and persist a combined two-leg gross exposure/cost reservation against existing per-round and all-round limits before sending either leg; each leg still passes its current fresh-quote, spread, slippage, commission, and margin protections. Release or reconcile the reservation as both legs open/close, including restart recovery.
- [ ] Add platform-specific tests/source assertions that all distance modes feed the existing resolved distances into pair initialization, and that single basket mode still reaches the legacy branch.

## Task 4: Handle pending entries, retries, and crash recovery

**Files:**
- Modify: all four MQL sources listed in the file map
- Modify: `tests/strategy_logic.py`
- Modify: `tests/test_strategy_logic.py`

- [ ] Persist an entry-event record before the first order is sent: unique event ID, signal bar/time, original direction, locked distances, lots, allocated group IDs, XAU risk reservation where applicable, and per-leg state. Reuse the existing account/symbol/magic state-prefix conventions and do not change Magic Number semantics.
- [ ] After every send, reconcile the allocated group ID against open positions, active orders, and relevant history before retrying. If a send response is ambiguous, query first; never blindly resend a possibly accepted market order.
- [ ] If the primary order is definitely rejected before any position exists, clear the launch event and wait for a new accepted signal; do not open only the opposite basket.
- [ ] On a definite transient opposite-leg rejection, retain the primary and pending-opposite intent, then retry at most once per subsequent tick while the primary basket remains active. Treat this as completion of an already accepted event: do not reapply the initial operation-time or new-entry GUI gate, but recheck hard execution/risk gates (fresh quote, spread, slippage, margin, XAU cost budgets). Do not retry permanent parameter/volume/account-mode rejections indefinitely; log and persist the failed leg, keep managing the established basket, and clear the event when that basket closes. Prevent duplicate creation for the same event; otherwise preserve existing new-signal policy, including `K线多组=1` concurrent events.
- [ ] Because the two broker requests cannot be atomic, expose a durable, rate-limited partial-pair failure diagnostic (entry event/group IDs and broker reason) whenever the primary is managed without its required opposite leg; do not let the UI/log state imply that both baskets are active.
- [ ] If the primary has closed and no leg or related pending order remains, complete/clear the event instead of opening a late opposite basket.
- [ ] For `Korder_type=KORDER_ONCE_PER_BAR`, retain the existing high/low pending OCO pair. On the first fill, finish the existing OCO cancellation, create the filled-direction group, then create the opposite market group; persist the fill ticket and pair state so a restart between these actions resumes safely.
- [ ] Give the high and low OCO orders separate leg identities under one entry-event ID. If both fill before the cancellation reaches the server, adopt the two filled orders as the two baskets, cancel any remaining orders for that event, and do not issue a third opposite market order.
- [ ] On MT4 restart, restore group state and pair launch state from terminal global variables plus order comments. On MT5, restore from its existing per-magic state and group records. Treat unknown order/history status as unresolved and wait; do not infer a missing leg and duplicate it.
- [ ] Add model tests for restart after primary success, restart after ambiguous opposite send, first OCO fill followed by cancellation, and primary close before opposite retry.
- [ ] Add a failure-path test for insufficient funds on the second leg: invoke the existing EA-wide no-money cleanup state machine, do not issue more pair legs on the same tick, and do not recreate the pair until cleanup has completed and a new signal is accepted.

## Task 5: Route events through independent group management

**Files:**
- Modify: all four MQL sources listed in the file map
- Modify: `tests/test_strategy_logic.py`

- [ ] When basket count is two, run the group restore/manage loop for all supported distance modes, not only the current K-line multiple-group condition. Keep K-line signal creation rules and `K线多组` gating separate from the per-signal basket count; with basket count 1, preserve the current K-line multiple-group dispatch unchanged.
- [ ] With `K线多组=0`, do not accept another K-line initial signal while either basket from the prior event is active, pending, or being recovered. With `K线多组=1`, preserve its existing concurrent-signal policy; each accepted signal creates one or two baskets according to `篮子数量`.
- [ ] Preserve one-group-per-tick state isolation: each `MultiManageGroup` call receives only that group's state and order-comment selector; normal group completion removes only that group.
- [ ] When one basket reaches normal take-profit and closes, keep managing the other basket under its own state. Do not restart the signal or open a replacement basket until the event's remaining basket is also complete, unless the existing K-line multiple-group policy independently accepts a new signal.
- [ ] Check shared fail-safe paths explicitly: insufficient-funds cleanup and maximum-reversal cleanup continue to close/delete all orders owned by the EA scope as before; ordinary stop/TP, pending reconciliation, and grid updates remain group-local.
- [ ] Maintain compatibility: saved legacy single-group state continues through the old restore path when basket count is 1 (except the existing K-line multiple-group mode); switching to basket count 2 with an active legacy group waits until that group scope is flat before starting the new group manager.
- [ ] Choose the active manager by recovered ownership: if legacy-format single-group positions/pending orders exist, continue the legacy manager and suppress new entry until they are flat even when the input is now 2; if group-tagged positions/pending orders exist, continue the group manager even when the input is now 1. Apply the input only when admitting a new entry event.
- [ ] In XAU NetRR, also select between the legacy `g_cost_*` cycle and per-group cost ledgers from persisted ownership when basket count changes; never orphan a live cost cycle by routing it to the other manager.
- [ ] Add source-contract tests for all-mode two-basket manager routing, unchanged default single-group route, K-line OCO behavior, and group-scoped normal close/delete calls.
- [ ] Add a platform/source-contract check that MT5 refuses basket count 2 on netting accounts and accepts it on hedging accounts.

## Task 6: Update user-facing parameter documentation

**Files:**
- Modify: `README.md`
- Modify: `README_XAU_NetRR_v2_10.md`
- Modify: `EA软件使用手册.html`

- [ ] Document default 1 as the existing single basket and value 2 as a second opposite-direction market basket created from the same accepted signal.
- [ ] State that each basket then follows its own existing cycle/grid/stop/take-profit logic, that K-line OCO remains one-fill-then-cancel, and that `K线多组` independently controls multiple K-line signal groups.
- [ ] Explain that an active group is not retroactively duplicated when the parameter changes, and clarify any platform order-comment truncation limitation if group tags need a shorter token.
- [ ] Keep the docs consistent across canonical and XAU editions and add/update documentation assertions if present.

## Task 7: Verify and build all affected editions

**Files:**
- No additional source changes unless verification finds a defect

- [ ] Run the full automated suite: `pytest -q`.
- [ ] Compile canonical sources as required: `powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\compile-mql.ps1 -Target Both`.
- [ ] Compile both XAU NetRR sources with the same discovered MetaEditor installations by invoking the MT4/MT5 MetaEditor executables with each XAU source path and a separate log file; do not add product targets to the canonical build script for this feature.
- [ ] Treat a build as successful only when each compiler log reports zero errors and each expected `.ex4`/`.ex5` output exists and has a refreshed timestamp. Record warnings and all four output paths.
- [ ] Review the final diff to ensure unrelated pre-existing dirty files remain untouched and no generated bytecode/log artifacts are accidentally included in source changes.

## Acceptance checklist

- [ ] Default basket count 1 preserves existing behavior and tests.
- [ ] Basket count 2 opens one original-direction basket and exactly one opposite basket for every valid initial event.
- [ ] Each basket has unique identity and independent state through grids, stops, reversals, take-profit, and restart.
- [ ] K-line initial OCO semantics, existing multiple K-line group behavior, entry filters, GUI controls, and XAU NetRR checks remain intact.
- [ ] Simultaneous OCO fills create exactly two identified baskets, and MT5 refuses the feature on account modes that cannot hold both sides independently.
- [ ] All four editions pass tests and compile with refreshed bytecode outputs and zero errors.
