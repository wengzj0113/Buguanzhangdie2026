from pathlib import Path
import math

import pytest

from strategy_logic import Direction, average_double_candle_signal


ROOT = Path(__file__).resolve().parents[1]


@pytest.mark.parametrize("height,expected", [(199, None), (200, (Direction.BUY, 100)), (201, (Direction.BUY, 101))])
def test_two_times_average_threshold_includes_equality(height, expected):
    assert average_double_candle_signal(1000, 1100, height, [80, 120], 2, 50) == expected


def test_bearish_signal_uses_signal_range_not_average_for_both_distances():
    assert average_double_candle_signal(1100, 1000, 300, [80, 120], 2, 25) == (Direction.SELL, 75)


def test_only_selected_preceding_n_candles_contribute_to_average():
    assert average_double_candle_signal(1000, 1100, 200, [80, 120, 10000], 2, 50) == (Direction.BUY, 100)


def test_user_multiplier_and_reverse_direction_control_signal():
    assert average_double_candle_signal(1100, 1000, 150, [100, 100], 2, 50, 1.5, 1) == (Direction.BUY, 75)
    assert average_double_candle_signal(1100, 1000, 149, [100, 100], 2, 50, 1.5, 1) is None


@pytest.mark.parametrize("platform", ["MT4", "MT5"])
def test_average_double_candle_labels_explain_trigger_and_distance(platform):
    source = (ROOT / f"NoMatterRiseFall_{platform}_Core.mqh").read_text(encoding="utf-8-sig")

    assert '// [信号]用于计算平均K线长度的根数' in source
    assert '// [信号]当前K线长度达到前N根平均长度×此倍数时开单' in source
    assert '// [止盈止损]距离=信号K线长度×此百分比' in source
    if platform == "MT5":
        assert '"平均K线根数"' in source
        assert '"触发倍数"' in source
        assert '"止盈止损距离(%)"' in source


@pytest.mark.parametrize("open_,close,height,ranges,n,percent", [
    (1000, 1000, 200, [100], 1, 50),
    (1000, 1100, 200, [100], 0, 50),
    (1000, 1100, 200, [100], 2, 50),
    (1000, 1100, 200, [0], 1, 50),
    (1000, 1100, 200, [math.nan], 1, 50),
    (1000, 1100, math.inf, [100], 1, 50),
    (1000, 1100, 200, [100], 1, 0),
    (1000, 1100, 200, [100], 1, math.nan),
    (1000, 1100, 200, [100], 1, 1e20),
    (1000, 1100, 200, [100], 1, 0.01),
])
def test_invalid_data_or_unrepresentable_distance_does_not_open(open_, close, height, ranges, n, percent):
    assert average_double_candle_signal(open_, close, height, ranges, n, percent) is None


@pytest.mark.parametrize("platform", ["MT4", "MT5"])
def test_native_signal_uses_closed_snapshot_and_shared_entry_latch(platform):
    source = (ROOT / f"NoMatterRiseFall_{platform}_Core.mqh").read_text(encoding="utf-8-sig")
    assert "bool GetAverageDoubleCandleSignal(" in source
    assert "CopyRates(" in source
    assert "DISTANCE_AVERAGE_DOUBLE_CANDLE = 8" in source
    assert "NMR_PROFILE_AVERAGE_DOUBLE_CANDLE" in source
    signal = source[source.index("bool GetAverageDoubleCandleSignal("):source.index("bool GetLongCandleDirection(")]
    assert "1, count + 1, rates" in signal
    assert "rates[count]" in signal
    assert "index < count" in signal
    assert "trigger_multiplier * average_range" in signal
    assert "均值触发倍数" in source
    assert "ORDERTYPE_REVERSE" in signal
    assert "distance_percent / 100.0" in signal
    assert "take_profit_points = stop_points" in signal
    assert "AVERAGE_DOUBLE_CANDLE_SIGNAL" in signal
    assert "PrepareInitialSignal(signal_bar_time, first_direction, signal_id)" in source

