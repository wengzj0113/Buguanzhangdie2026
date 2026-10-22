from pathlib import Path
import math
import pytest

from strategy_logic import bollinger_expansion_signal
from test_ea_profile_contract import _expanded_source, _wrapper


@pytest.mark.parametrize("width,result", [(199, None), (200, (50, 50)), (201, (50, 50))])
def test_threshold_includes_equality(width, result):
    assert bollinger_expansion_signal(width, [80, 120], 2, 25) == result


def test_mean_excludes_signal_and_uses_only_n_preceding_widths():
    assert bollinger_expansion_signal(200, [80, 120, 10000], 2, 25) == (50, 50)


def test_fixed_mode_keeps_trigger_and_independent_fixed_distances():
    assert bollinger_expansion_signal(200, [100], 1, 0, 1, 300, 700) == (300, 700)
    assert bollinger_expansion_signal(199, [100], 1, 25, 1, 300, 700) is None


def test_user_trigger_multiplier_controls_bollinger_expansion():
    assert bollinger_expansion_signal(150, [100], 1, trigger_multiplier=1.5) == (38, 38)
    assert bollinger_expansion_signal(149, [100], 1, trigger_multiplier=1.5) is None


@pytest.mark.parametrize("platform", ["MT4", "MT5"])
def test_bollinger_expansion_labels_explain_trigger_and_distance(platform):
    source = _expanded_source(_wrapper("BollingerExpansion", platform))

    assert '// [信号]用于计算平均带宽的根数' in source
    assert '// [信号]当前带宽达到前N根平均带宽×此倍数时开单' in source
    assert '// [止盈止损]距离=信号K线带宽×此百分比' in source
    assert '// [止盈止损]按带宽百分比或固定点数计算' in source
    if platform == "MT5":
        assert '"平均带宽根数"' in source
        assert '"触发倍数"' in source
        assert '"止盈止损距离"' in source
        assert '"止盈止损百分比(%)"' in source


@pytest.mark.parametrize("width,prior,n,percent,mode,sl,tp", [
    (200, [100], 0, 25, 0, 500, 500),
    (200, [100], 10001, 25, 0, 500, 500),
    (200, [100], 2, 25, 0, 500, 500),
    (math.inf, [100], 1, 25, 0, 500, 500),
    (200, [math.nan], 1, 25, 0, 500, 500),
    (200, [0], 1, 25, 0, 500, 500),
    (200, [100], 1, 0, 0, 500, 500),
    (200, [100], 1, math.nan, 0, 500, 500),
    (200, [100], 1, 1e20, 0, 500, 500),
    (200, [100], 1, .01, 0, 500, 500),
    (200, [100], 1, 25, 2, 500, 500),
    (200, [100], 1, 25, 1, 0, 500),
    (200, [100], 1, 25, 1, 500, -1),
])
def test_invalid_signal_or_selected_distance_does_not_open(width, prior, n, percent, mode, sl, tp):
    assert bollinger_expansion_signal(width, prior, n, percent, mode, sl, tp) is None


@pytest.mark.parametrize("platform", ["MT4", "MT5"])
def test_native_signal_and_management_contract(platform):
    source = _expanded_source(_wrapper("BollingerExpansion", platform))
    assert "DISTANCE_BOLLINGER_EXPANSION = 9" in source
    body = source[source.index("bool GetBollingerExpansionSignal("):source.index("bool GetBollingerTouchDirection(")]
    assert "trigger_multiplier * average_width" in body
    assert "带宽触发倍数" in source
    assert "index < count" in body and "widths[count]" in body
    assert "BOLLINGER_EXPANSION_SIGNAL" in body
    assert "stop_points = fixed_stop" in body and "take_profit_points = fixed_take_profit" in body
    assert "take_profit_points = stop_points" in body
    assert "PrepareInitialSignal(signal_bar_time, first_direction, signal_id)" in source
    active = source[source.index("bool GetActiveDistancePoints("):]
    assert active.index("g_group_stop_points > 0") < active.index("DISTANCE_BOLLINGER_EXPANSION")


def test_new_config_fields_are_profile_scoped_and_ui_distance_fields_are_conditional():
    source = _expanded_source(_wrapper("BollingerExpansion", "MT5"))
    assert "config.boll_exp_count" in source and "config.boll_exp_distance_mode" in source
    assert 'key == "boll_exp_distance_mode"' in source
    assert "g_gui_draft_config.boll_exp_distance_mode == BOLL_EXP_PERCENT" in source
    for name in ("FixedDistance", "BollingerRange", "AverageDoubleCandle"):
        old = _expanded_source(_wrapper(name, "MT5"))
        assert "config.boll_exp_count" not in old


@pytest.mark.parametrize("platform", ["MT4", "MT5"])
def test_consumed_signal_bar_blocks_direction_change_after_failure_or_cleanup(platform):
    import re
    source = _expanded_source(_wrapper("BollingerExpansion", platform))
    # The earlier generic latch includes direction. This profile must additionally
    # reject an already consumed bar even if the live middle-band direction flips.
    prepare = re.findall(r"bool PrepareInitialSignal\([^;{]*\)\s*\{(.*?)\n  \}", source, re.S)[0]
    consumed = re.findall(r"bool IsInitialSignalConsumed\([^;{]*\)\s*\{(.*?)\n  \}", source, re.S)[0]
    assert re.search(r"if\(g_signal_consumed && g_signal_bar_time == bar_time\)\s*return false;", prepare)
    assert re.search(r"if\(g_signal_consumed && g_signal_bar_time == bar_time\)\s*return true;", consumed)


def test_mt5_lazy_indicator_requests_buffers_before_waiting_for_calculation():
    source = _expanded_source(_wrapper("BollingerExpansion", "MT5"))
    body = source[source.index("bool GetBollingerExpansionSignal("):source.index("bool GetBollingerTouchDirection(")]
    # MT5 tester can leave a handle created during OnTick at -1 until its first
    # CopyBuffer request. Gating that request on BarsCalculated deadlocks it.
    assert "BarsCalculated(" not in body
    assert "CopyBuffer(g_boll_exp_handle, 1, 1, count + 1, upper)" in body


def test_mt5_middle_band_direction_preserves_expansion_indicator_handle():
    source = _expanded_source(_wrapper("BollingerExpansion", "MT5"))
    body = source[source.index("bool GetBollingerFirstDirection("):source.index("bool GetBollingerExpansionSignal(")]
    assert "const int handle = g_boll_exp_handle;" in body
    assert "IndicatorRelease(handle)" not in body
    # Other profiles retain their existing ownership and direction semantics.
    old = _expanded_source(_wrapper("FixedDistance", "MT5"))
    original = old[old.index("bool GetBollingerFirstDirection("):old.index("bool GetBollingerTouchDirection(")]
    assert "IndicatorRelease(handle)" in original
