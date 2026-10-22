from pathlib import Path
import pytest
import strategy_logic as logic

ROOT = Path(__file__).resolve().parents[1]
TARGETS = [ROOT / name for name in (
    'NoMatterRiseFall_MT4.mq4', 'NoMatterRiseFall_MT5.mq5',
    'NoMatterRiseFall_MT4_Core.mqh', 'NoMatterRiseFall_MT5_Core.mqh',
)]


@pytest.mark.parametrize('direction', list(logic.Direction))
def test_initial_mode3_is_two_opposite_baskets(direction):
    assert len(logic.basket_directions(direction, 3)) == 2
    launch, missing = logic.plan_initial_basket_launch(
        7, 1, 2, direction, 3, .03, 500, 700,
    )
    assert launch.opposite is not None
    assert launch.primary.direction != launch.opposite.direction
    assert launch.primary.lots == launch.opposite.lots == .03
    assert [leg.group_id for leg in missing] == [1]


def action(**changes):
    values = dict(mode=3, peer_state='ended', primary_confirmed=True,
                  primary_alive=True, protected=True, source_stage_matches=True,
                  event_consumed=False, reset=False, child_status='absent',
                  actual_direction=logic.Direction.BUY, actual_first_lots=.03)
    values.update(changes)
    return logic.mode3_companion_action(**values)


@pytest.mark.parametrize('changes,expected', [
    ({}, ('create', logic.Direction.SELL, .03)),
    ({'actual_direction': logic.Direction.SELL, 'actual_first_lots': .07},
     ('create', logic.Direction.BUY, .07)),
    ({'mode': 1}, ('none', None, 0.)),
    ({'mode': 2}, ('none', None, 0.)),
    ({'peer_state': 'active'}, ('none', None, 0.)),
    ({'peer_state': 'unknown'}, ('wait', None, 0.)),
    ({'primary_confirmed': False}, ('wait', None, 0.)),
    ({'protected': False}, ('wait', None, 0.)),
    ({'primary_alive': False}, ('cancel', None, 0.)),
    ({'source_stage_matches': False}, ('cancel', None, 0.)),
    ({'child_status': 'in_flight'}, ('reconcile', None, 0.)),
    ({'child_status': 'partial'}, ('reconcile', None, 0.)),
    ({'child_status': 'unknown'}, ('reconcile', None, 0.)),
    ({'child_status': 'confirmed'}, ('adopt', None, 0.)),
    ({'event_consumed': True}, ('none', None, 0.)),
    ({'reset': True}, ('none', None, 0.)),
])
def test_companion_policy(changes, expected):
    assert action(**changes) == expected


@pytest.mark.parametrize('source', TARGETS, ids=lambda p: p.name)
def test_four_strategy_targets_connect_shared_renewal_module(source):
    text = source.read_text(encoding='utf-8')
    assert '#include "NoMatterRiseFall_BasketRenewal.mqh"' in text
    assert 'BasketRenewalPrepareStop(group' in text
    assert 'BasketRenewalConfirmFirstOrder(group' in text
    assert 'BasketRenewalBeginBatch();' in text
    assert 'BasketRenewalProcess();' in text
    for field in ('basket_mode_at_start', 'basket_family_id', 'stop_event_sequence',
                  'renewal_request_state', 'renewal_deal_cursor', 'renewal_request_direction',
                  'renewal_request_volume_before'):
        assert text.count(field) >= 5


def function_body(text, signature):
    start = text.index('{', text.index(signature))
    depth = 1
    end = start + 1
    while depth:
        depth += (text[end] == '{') - (text[end] == '}')
        end += 1
    return text[start:end]


@pytest.mark.parametrize('source', TARGETS, ids=lambda p: p.name)
def test_each_host_restores_current_request_and_records_definite_failure(source):
    text = source.read_text(encoding='utf-8')
    load = function_body(text, 'void MultiLoadGroups(')
    for field in ('renewal_request_state', 'renewal_deal_cursor',
                  'renewal_request_direction', 'renewal_request_volume_before', 'rrcommit'):
        assert field in load
    send = function_body(text, 'bool MultiSendMarketLeg(')
    assert 'BasketRenewalAfterLeg(group,false,' in send


def test_pending_child_history_uses_current_leg_identity():
    shared = (ROOT / 'NoMatterRiseFall_BasketRenewal.mqh').read_text(encoding='utf-8')
    process = function_body(shared, 'void BasketRenewalProcess(')
    assert 'R3HistoryShowsEntry(child.id)' not in process
    assert 'R3NewEntryAfterRequest(child)' in process
    durable = function_body(shared, 'bool R3HasDurableAttempt(')
    assert '.rrcommit' in durable


def test_mode3_scope_uses_raw_server_and_symbol_and_applied_magic():
    shared = (ROOT / 'NoMatterRiseFall_BasketRenewal.mqh').read_text(encoding='utf-8')
    scope = function_body(shared, 'string R3ScopeForState(')
    assert 'ACCOUNT_SERVER' in scope and 'AccountServer()' in scope and 'Symbol()' in scope
    assert 'DEAL_MAGIC)==InpMagicNumber' not in shared
    assert 'DEAL_MAGIC)!=InpMagicNumber' not in shared
    assert 'ORDER_MAGIC)==InpMagicNumber' not in shared


def test_current_second_deals_are_inside_history_window():
    shared = (ROOT / 'NoMatterRiseFall_BasketRenewal.mqh').read_text(encoding='utf-8')
    assert 'HistorySelect(0,TimeCurrent())' not in shared


@pytest.mark.parametrize('source', [p for p in TARGETS if 'MT5' in p.name])
def test_delayed_fill_callbacks_protect_without_sending_another_leg(source):
    text = source.read_text(encoding='utf-8')
    for signature in ('void OnTradeTransaction(', 'void OnTimer('):
        assert 'BasketRenewalProtectVisible();' in function_body(text, signature)
    assert 'BasketRenewalConfigPrefix(' in function_body(text, 'bool ValidatePersistedConfigForMagic(')


def test_next_child_leg_clears_previous_commit_before_saving_new_intent():
    shared = (ROOT / 'NoMatterRiseFall_BasketRenewal.mqh').read_text(encoding='utf-8')
    process = function_body(shared, 'void BasketRenewalProcess(')
    before_pending = process.index('f.volume_before=cv;f.request_pending=1;')
    clear_previous = process.rfind('R3PrepareNextLeg(child)', 0, before_pending)
    assert clear_previous >= 0
    helper = function_body(shared, 'bool R3PrepareNextLeg(')
    assert 'R3ClearRequest(group)' in helper and '.rrcommit' in helper
    assert 'GlobalVariablesFlush()' in helper


def test_completed_reset_releases_compact_configuration_lock():
    shared = (ROOT / 'NoMatterRiseFall_BasketRenewal.mqh').read_text(encoding='utf-8')
    cancel = function_body(shared, 'void BasketRenewalCancelAll(')
    assert 'GlobalVariableDel(R3Prefix()+".cfgok")' in cancel


def test_live_opening_remainder_blocks_resend_and_reset_keeps_its_identity():
    shared = (ROOT / 'NoMatterRiseFall_BasketRenewal.mqh').read_text(encoding='utf-8')
    assert 'R3HasOpeningOrder(group.id)' in function_body(shared, 'bool BasketRenewalBeforeLeg(')
    process = function_body(shared, 'void BasketRenewalProcess(')
    assert 'if(R3HasPending(child.id))' in process
    assert 'R3CancelOutstandingOrders(child.id)' in process
    assert 'R3CancelOutstandingOrders(group.id)' in function_body(shared, 'bool BasketRenewalResetReady(')
    assert 'IsReversePendingType' not in function_body(shared, 'bool R3CancelOutstandingOrders(')


def test_closed_partial_is_canceled_before_waiting_on_an_active_order():
    shared = (ROOT / 'NoMatterRiseFall_BasketRenewal.mqh').read_text(encoding='utf-8')
    process = function_body(shared, 'void BasketRenewalProcess(')
    closed = process.index('child.first_lots>R3Tolerance()')
    assert closed < process.index('if(R3HasPending(child.id))')


@pytest.mark.parametrize('source', [p for p in TARGETS if 'MT5' in p.name])
def test_stale_deal_callback_cannot_replace_current_mode3_order_identity(source):
    text = source.read_text(encoding='utf-8')
    callback = function_body(text, 'bool MultiConfirmTradeRequestFromTransaction(')
    assert 'trans.deal<=group.renewal_deal_cursor' in callback
    assert 'group.request_order_ticket!=trans.order' in callback


@pytest.mark.parametrize('source', TARGETS, ids=lambda p: p.name)
def test_reset_does_not_delete_mode3_registry_inside_a_borrowed_group_call(source):
    text = source.read_text(encoding='utf-8')
    reset = function_body(text, 'void BeginFullReset(')
    assert 'BasketRenewalResetRequiresDeferral()' in reset
    assert 'if(renewal_cleanup) BasketRenewalDeferReset(); else MultiClearAll();' in reset
    assert '!renewal_cleanup && BasketRenewalResetReady()' in reset


@pytest.mark.parametrize('source', [p for p in TARGETS if 'MT5' in p.name])
def test_mode3_oco_adopts_original_fill_after_peer_changes_to_market_order(source):
    text = source.read_text(encoding='utf-8')
    oco = function_body(text, 'bool MultiHandleOcoBasketGroup(')
    assert 'group.basket_mode_at_start==3 && peer_ticket==0' in oco
    assert 'g_multi_groups[peer_index].signal_consumed' in oco


@pytest.mark.parametrize('source', [p for p in TARGETS if 'MT5' in p.name])
def test_initial_actual_exposure_is_adopted_before_peer_or_request_gates(source):
    text = source.read_text(encoding='utf-8')
    oco = function_body(text, 'bool MultiHandleOcoBasketGroup(')
    assert oco.index('BasketRenewalAdoptInitial(group)') < oco.index('if(peer_index < 0)')
    assert 'BasketRenewalAdoptInitial(group,true)' not in oco
    manage = function_body(text, 'bool MultiManageGroup(')
    assert manage.index('BasketRenewalAdoptInitial(group,true)') < manage.index('if(group.request_in_flight)')
    shared = (ROOT / 'NoMatterRiseFall_BasketRenewal.mqh').read_text(encoding='utf-8')
    adopt = function_body(shared, 'bool BasketRenewalAdoptInitial(')
    assert adopt.index('MultiStopsVerified(group,type)') < adopt.index('group.pair_role=0;')
    assert 'R3RequestUnknown(group)' in adopt and 'R3CancelOutstandingOrders(group.id)' in adopt
    assert 'R3FirstLotsSince(first,entry)' in adopt
    assert adopt.index('if(!allow_send)') < adopt.index('R3_OPEN_INITIAL_REMAINDER(group,type,target)')
    assert 'volume>volume_before+R3Tolerance()' in adopt
    assert 'return live;' not in adopt  # historical adoption is its own batch
    assert 'BasketRenewalAdoptInitial(group)' in function_body(shared, 'void BasketRenewalProtectVisible(')


def test_reset_without_decodable_family_still_marks_born_mode3_cleanup():
    shared = (ROOT / 'NoMatterRiseFall_BasketRenewal.mqh').read_text(encoding='utf-8')
    defer = function_body(shared, 'bool BasketRenewalDeferReset(')
    assert 'if(!BasketRenewalResetRequiresDeferral()) return false;' in defer


@pytest.mark.parametrize('source', [p for p in TARGETS if 'MT4' in p.name])
def test_mt4_initial_second_leg_is_adopted_before_missing_parent_gate(source):
    text = source.read_text(encoding='utf-8')
    manage = function_body(text, 'bool MultiManageGroup(')
    assert manage.index('BasketRenewalAdoptInitialMT4(group)') < manage.index('if(group.pair_parent_id>0')
    assert 'if(group.pair_parent_id>0 && group.basket_mode_at_start!=3)' in manage
    adopt = function_body(text, 'bool BasketRenewalAdoptInitialMT4(')
    assert adopt.index('R3Position(group.id') < adopt.rindex('group.pair_parent_id=0')
    assert 'R3RequestUnknown(group)' in adopt and 'R3FirstLotsSince(first,entry)' in adopt
    assert 'MultiStopsVerified(group,type)' in adopt
    assert 'parent_ready' in adopt
    assert 'BasketRenewalProtectInitialMT4();' in function_body(text, 'void OnTimer(')
