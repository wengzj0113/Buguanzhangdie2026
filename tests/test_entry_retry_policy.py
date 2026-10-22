from dataclasses import dataclass
from pathlib import Path
import re

import pytest


ROOT = Path(__file__).resolve().parents[1]
CORES = {
    "MT4": ROOT / "NoMatterRiseFall_MT4_Core.mqh",
    "MT5": ROOT / "NoMatterRiseFall_MT5_Core.mqh",
}


class EntrySignalGate:
    """Model that consumes one immutable signal event at most once."""

    def __init__(self):
        self.last_signal_id = None

    def consume(self, signal_id):
        if signal_id is None or signal_id <= 0 or signal_id == self.last_signal_id:
            return False
        self.last_signal_id = signal_id
        return True


@dataclass
class BollingerTouchGate:
    """Model the outer-band touch episode and its re-arm condition."""

    armed: bool = True
    sequence: int = 0

    def update(self, price, upper, lower, point, order_type=0):
        from strategy_logic import bollinger_touch_direction

        if point <= 0 or upper <= lower:
            return None
        tolerance = point * 0.5
        if lower + tolerance < price < upper - tolerance:
            self.armed = True
            return None
        direction = bollinger_touch_direction(
            price, upper, lower, point, order_type,
        )
        if not self.armed or direction is None:
            return None
        self.armed = False
        self.sequence += 1
        return direction, self.sequence


@dataclass
class ReversePendingRetryGate:
    retry_after: int = 0
    attempts: int = 0

    def can_attempt(self, now):
        return now >= self.retry_after

    def record_failure(self, now, retcode):
        self.attempts += 1
        if retcode in (10018, 10027, 132, 133):
            delay = 60
        elif retcode in (10033, 148):
            delay = 60
        else:
            delay = min(5 * (2 ** (self.attempts - 1)), 300)
        self.retry_after = now + delay

    def record_success(self):
        self.retry_after = 0
        self.attempts = 0


def mt5_pending_request_accepted(sent, retcode, order_ticket):
    return sent and retcode in (10008, 10009) and order_ticket > 0


def mt5_market_request_accepted(retcode):
    return retcode in (10008, 10009, 10010)


def mt5_market_request_unresolved(retcode):
    return retcode in (10012, 10031)


def _function_body(source, signature):
    start = source.rindex(signature)
    opening = source.index("{", start)
    depth = 0
    for offset in range(opening, len(source)):
        if source[offset] == "{":
            depth += 1
        elif source[offset] == "}":
            depth -= 1
            if depth == 0:
                return source[opening + 1:offset]
    raise AssertionError(f"unclosed function body: {signature}")


def test_dual_basket_signal_is_consumed_before_new_group_ids_are_allocated():
    mt5 = CORES["MT5"].read_text(encoding="utf-8-sig")
    mt4 = CORES["MT4"].read_text(encoding="utf-8-sig")
    for source, signature, allocation in (
        (mt5, "bool MultiStartResolvedPair(const long direction,", "ArrayResize(g_multi_groups"),
        (mt4, "void StartResolvedMultiPair(const int first_type,", "ArrayResize(g_multi_groups"),
    ):
        body = _function_body(source, signature)
        assert "PrepareInitialSignal" in body
        assert body.index("PrepareInitialSignal") < body.index(allocation)


def test_bollinger_signal_only_rearms_after_price_returns_inside_bands():
    gate = BollingerTouchGate()

    first = gate.update(price=101, upper=100, lower=90, point=0.1)
    repeated = gate.update(price=102, upper=100, lower=90, point=0.1)
    assert first is not None
    assert repeated is None

    assert gate.update(price=95, upper=100, lower=90, point=0.1) is None
    second = gate.update(price=101, upper=100, lower=90, point=0.1)
    assert second is not None
    assert second[1] == first[1] + 1


def test_bollinger_ids_stay_exact_when_pair_ids_are_appended():
    for path in CORES.values():
        source = path.read_text(encoding="utf-8-sig")
        assert re.search(
            r"BuildSignalId\(signal_bar_time,\s*first_direction\)\s*\*\s*100\s*\+\s*next_sequence\s*%\s*99",
            source,
        )
        assert re.search(
            r"BuildSignalId\(bar_time,\s*direction\)\s*\*\s*100\s*\+\s*next_sequence\s*%\s*99",
            source,
        )

    latest_expected_unix_time = 2_200_000_000
    largest_pair_signal_id = (latest_expected_unix_time * 10 + 1) * 100 * 1000 + 99_999
    assert largest_pair_signal_id < 2**53


def test_entry_gate_accepts_new_signal_but_rejects_duplicate_event():
    gate = EntrySignalGate()
    assert gate.consume(101)
    assert not gate.consume(101)
    assert gate.consume(102)


def test_every_core_consumes_a_signal_once_and_has_a_bollinger_touch_latch():
    for platform, path in CORES.items():
        source = path.read_text(encoding="utf-8-sig")
        prepare = _function_body(source, "bool PrepareInitialSignal(")
        touch = _function_body(source, "bool GetBollingerTouchDirection(")

        assert re.search(r"if\s*\(g_signal_consumed\s*&&.*?\)\s*return false", prepare, re.S)
        assert "g_bollinger_touch_armed" in touch, platform
        assert "g_bollinger_touch_sequence" in touch, platform


def test_mt5_signal_latch_survives_flat_state_cleanup_and_reload():
    source = CORES["MT5"].read_text(encoding="utf-8-sig")
    load = _function_body(source, "bool LoadStateFromPrefix(")
    clear = _function_body(source, "void ClearState(")

    assert load.index('".signalconsumed"') < load.index('".index"')
    assert 'GlobalVariableDel(prefix + ".signalconsumed")' not in clear


def test_candle_multigroup_only_consumes_a_signal_after_failure():
    for platform, path in CORES.items():
        source = path.read_text(encoding="utf-8-sig")
        body = _function_body(source, "bool MultiTryOpenCandleGroup(")

        assert "IsInitialSignalConsumed" in body, platform
        if platform == "MT5":
            assert "MultiCandleSignalInFlight" in body
        market_send = body.index("MultiOpenMarket(state")
        assert body.index("PrepareInitialSignal", market_send) > market_send, platform
        assert body.count("PrepareInitialSignal") >= 2, platform
        assert body.index("MultiFindPosition", market_send) > market_send, platform
        assert "if(!market_opened)" in body[market_send:], platform
        if platform == "MT5":
            assert body.index("g_multi_groups[new_index] = state") < market_send


def test_mt5_market_request_rejection_does_not_leave_request_in_flight():
    source = CORES["MT5"].read_text(encoding="utf-8-sig")
    body = _function_body(source, "bool MultiSendMarketLeg(")

    assert "const uint retcode = g_trade.ResultRetcode();" in body
    assert "MultiMarketRequestAccepted(retcode)" in body
    assert "if(!sent || !MultiMarketRequestAccepted(retcode))" in body
    assert mt5_market_request_accepted(10018) is False
    assert mt5_market_request_accepted(10008) is True
    assert mt5_market_request_accepted(10010) is True
    assert "IsUnresolvedMultiMarketRetcode(retcode)" in body
    assert mt5_market_request_unresolved(10012) is True
    assert mt5_market_request_unresolved(10031) is True
    assert mt5_market_request_unresolved(10020) is False
    assert mt5_market_request_unresolved(10021) is False
    assert mt5_market_request_unresolved(10024) is False


def test_mt5_unresolved_market_requests_are_reconciled_and_quarantined():
    source = CORES["MT5"].read_text(encoding="utf-8-sig")
    state = _function_body(source, "bool MultiManageGroup(")

    assert "request_sent_time" in source
    assert "request_reconcile_quarantine" in source
    assert '".rt"' in source
    assert '".rq"' in source
    history = _function_body(source, "bool MultiHistoryRequestTerminal(")
    assert "HistoryOrderSelect(order_ticket)" in history
    assert "MultiRequestReconciliationExpired(group)" in state
    assert "PrepareInitialSignal(group.request_bar_time, group.request_direction)" in state
    quarantine = state[state.index("if(group.request_reconcile_quarantine)"):state.index("if(group.request_in_flight)")]
    assert "REQUEST_RECONCILIATION_EXPIRED" not in quarantine
    assert "group.request_sent_time < 240" not in quarantine


def test_mt5_visible_request_confirmation_requires_new_volume_since_send():
    source = CORES["MT5"].read_text(encoding="utf-8-sig")
    visible = _function_body(source, "bool MultiConfirmTradeRequestFromVisible(")
    send = _function_body(source, "bool MultiSendMarketLeg(")

    assert "request_position_volume_before" in source
    assert '".rvb"' in source
    assert "volume <= group.request_position_volume_before + tolerance" in visible
    assert "request_position_volume_before = MultiTotalPositionVolume(group.id," in send


def test_mt5_transaction_confirmation_is_correlated_to_the_current_leg():
    source = CORES["MT5"].read_text(encoding="utf-8-sig")
    transaction = _function_body(source, "bool MultiConfirmTradeRequestFromTransaction(")

    assert "trans.order != group.request_order_ticket" in transaction
    assert "request_position_volume_before" in transaction
    assert re.search(
        r"MultiTotalPositionVolume\(group\.id,\s*expected_position_type\)",
        transaction,
    )


@pytest.mark.parametrize("platform", ["MT4", "MT5"])
def test_unresolved_split_leg_recovers_anchor_and_protection_after_restart(platform):
    source = CORES[platform].read_text(encoding="utf-8-sig")
    recover = _function_body(source, "bool MultiRecoverRequestExposure(")
    manage = _function_body(source, "bool MultiManageGroup(")

    assert "group.anchor_price = entry" in recover
    assert "group.last_entry = entry" in recover
    assert "group.linear_extreme = entry" in recover
    assert "request_exposure_hydrated" in recover
    assert "market_request_volume_before <= tolerance" not in recover
    assert "request_position_volume_before <= tolerance" not in recover
    assert "MultiSetStops(group, type)" in recover
    assert "MultiStopsVerified(group, type)" in recover
    assert '".mrh"' in source if platform == "MT4" else '".reh"' in source
    assert manage.index("MultiRecoverRequestExposure(group)") < manage.index(
        "if(group.request_reconcile_quarantine)" if platform == "MT5"
        else "if(!MultiReconcileMarketRequest(group))"
    )


@pytest.mark.parametrize("platform", ["MT4", "MT5"])
@pytest.mark.parametrize("variant", ["Core", "Legacy"])
def test_multi_group_reset_cannot_leave_stale_array_index(platform, variant):
    extension = ".mq4" if platform == "MT4" else ".mq5"
    suffix = f"{platform}_Core.mqh" if variant == "Core" else f"{platform}{extension}"
    path = ROOT / f"NoMatterRiseFall_{suffix}"
    source = path.read_text(encoding="utf-8-sig")
    body = _function_body(source, "void ManageMultipleCandleGroups()")
    manage_call = body.index("MultiManageGroup(g_multi_groups[index])")
    guard = body.index("index >= ArraySize(g_multi_groups)", manage_call)

    assert guard < body.index("g_multi_groups[index]", manage_call + len("MultiManageGroup(g_multi_groups[index])"))


def test_mt4_ambiguous_market_request_keeps_and_reconciles_its_group():
    source = CORES["MT4"].read_text(encoding="utf-8-sig")
    send = _function_body(source, "bool MultiSendMarketLeg(")
    reconcile = _function_body(source, "bool MultiReconcileMarketRequest(")
    entry = _function_body(source, "bool MultiTryOpenCandleGroup(")
    manage = _function_body(source, "bool MultiManageGroup(")

    assert "market_request_unresolved" in source
    assert '".mru"' in source
    assert '".mrvb"' in source
    assert "MultiLaunchErrorIsAmbiguous(error)" in send
    assert re.search(
        r"MultiTotalLots\(group\.id,\s*group\.market_request_direction\)",
        reconcile,
    )
    assert "request_tag" in reconcile
    assert '".R"' in source
    assert "StringFind(OrderComment(), request_tag)" in reconcile
    assert "if(state.market_request_unresolved)" in entry
    assert "MultiReconcileMarketRequest(group)" in manage


def test_mt4_ambiguous_market_request_is_not_retried_or_expired_by_time():
    source = CORES["MT4"].read_text(encoding="utf-8-sig")
    reconcile = _function_body(source, "bool MultiReconcileMarketRequest(")

    assert "group.market_request_unresolved = true" in source
    assert "group.market_request_unresolved = false" in reconcile
    assert "TimeCurrent() - group.market_request_time" not in reconcile


def test_mt5_dual_basket_partial_initial_fill_keeps_a_managed_group():
    source = CORES["MT5"].read_text(encoding="utf-8-sig")
    body = _function_body(source, "bool MultiStartResolvedPair(const long direction,")
    failure = body.index("if(!MultiOpenMarket(g_multi_groups[first_index]")
    partial = body.index("MultiFindPosition(first_id", failure)
    inactive = body.index("g_multi_groups[first_index].active = false", failure)

    assert failure < partial < inactive
    assert "transition_target_lots = 0.0" in body[partial:inactive]
    assert "MultiSetStops(g_multi_groups[first_index], partial_type)" in body[partial:inactive]


@pytest.mark.parametrize("platform", ["MT4", "MT5"])
def test_failed_reverse_pending_is_gated_and_success_clears_retry_state(platform):
    source = CORES[platform].read_text(encoding="utf-8-sig")
    body = _function_body(source, "bool MultiPlaceReversePending(")

    assert "MultiReversePendingRetryAllowed(group)" in body
    assert "MultiRecordReversePendingFailure(group," in body
    assert "MultiClearReversePendingFailure(group)" in body


def test_mt5_reverse_pending_uses_server_retcode_even_when_ct_trade_returns_true():
    source = CORES["MT5"].read_text(encoding="utf-8-sig")
    body = _function_body(source, "bool MultiPlaceReversePending(")

    assert "const uint retcode = g_trade.ResultRetcode();" in body
    assert "const ulong order_ticket = g_trade.ResultOrder();" in body
    assert re.search(
        r"if\s*\(!sent\s*\|\|.*?TRADE_RETCODE_DONE.*?TRADE_RETCODE_PLACED.*?order_ticket\s*==\s*0",
        body,
        re.S,
    )
    assert mt5_pending_request_accepted(True, 10033, 0) is False
    assert mt5_pending_request_accepted(True, 10008, 12345) is True
    assert mt5_pending_request_accepted(False, 10008, 12345) is False


def test_reverse_pending_retry_gate_exponentially_backs_off_and_uses_error_class():
    gate = ReversePendingRetryGate()
    assert gate.can_attempt(100)

    gate.record_failure(100, 10033)
    assert not gate.can_attempt(159)
    assert gate.can_attempt(160)

    gate.record_failure(160, 10020)
    assert gate.retry_after == 170
    gate.record_success()
    assert gate.can_attempt(161)
    assert gate.attempts == 0


