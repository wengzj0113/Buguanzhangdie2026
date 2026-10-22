from pathlib import Path
import re

import pytest
import strategy_logic


MT5_SOURCE = Path(__file__).resolve().parents[1] / "NoMatterRiseFall_MT5.mq5"
MT4_SOURCE = Path(__file__).resolve().parents[1] / "NoMatterRiseFall_MT4.mq4"
MT5_CORE_SOURCES = (
    Path(__file__).resolve().parents[1] / "NoMatterRiseFall_MT5_Core.mqh",
    Path(__file__).resolve().parents[1]
    / "dist" / "DistanceModeEAs_2026-10-11" / "BollingerRange" / "MT5"
    / "Experts" / "NoMatterRiseFall_MT5_Core.mqh",
)


def _box_breakout_config(**overrides):
    config_type = getattr(strategy_logic, "BoxBreakoutConfig", None)
    assert config_type is not None
    values = {
        "lookback_bars": 17,
        "atr_period": 3,
        "touch_atr_multiplier": 0.2,
        "min_upper_touches": 2,
        "min_lower_touches": 2,
        "min_round_trips": 2,
        "min_touch_spacing_bars": 3,
        "min_width_points": 100,
        "max_width_points": 100,
        "breakout_buffer_atr_multiplier": 0.2,
        "order_type": "forward",
    }
    values.update(overrides)
    return config_type(**values)


def _box_rates(touches=("U", "L", "U", "L", "U"), width=1.0):
    """Build 17 valid OHLC bars with requested separated edge contacts."""
    from datetime import datetime, timedelta

    rates = []
    touch_positions = {2 + index * 3: side for index, side in enumerate(touches)}
    lower = 10.0
    upper = lower + width
    for index in range(17):
        side = touch_positions.get(index)
        if side == "U":
            rates.append((datetime(2026, 1, 1) + timedelta(minutes=index),
                          upper - 0.2, upper, upper - 0.3, upper - 0.1))
        elif side == "L":
            rates.append((datetime(2026, 1, 1) + timedelta(minutes=index),
                          lower + 0.2, lower + 0.3, lower, lower + 0.1))
        else:
            center = (lower + upper) / 2
            rates.append((datetime(2026, 1, 1) + timedelta(minutes=index),
                          center, center + 0.15, center - 0.15, center + 0.05))
    return rates


def test_box_breakout_requires_lookback_closed_bars():
    find_box = getattr(strategy_logic, "find_confirmed_box", None)
    assert callable(find_box)
    rates = _box_rates()

    assert find_box(rates[:-1], _box_breakout_config(), point=0.01) is None
    box = find_box(rates, _box_breakout_config(), point=0.01)
    assert box is not None
    assert box.upper == pytest.approx(11.0)
    assert box.lower == pytest.approx(10.0)
    assert box.width_points == 100


def test_box_breakout_counts_separated_touch_events_and_two_round_trips():
    find_box = getattr(strategy_logic, "find_confirmed_box", None)
    assert callable(find_box)
    box = find_box(_box_rates(), _box_breakout_config(), point=0.01)

    assert box is not None
    assert box.upper_touches == 3
    assert box.lower_touches == 2
    assert box.round_trips == 2


def test_box_breakout_requires_two_full_round_trips():
    find_box = getattr(strategy_logic, "find_confirmed_box", None)
    assert callable(find_box)
    rates = _box_rates(touches=("U", "L", "U"))

    assert find_box(rates, _box_breakout_config(), point=0.01) is None


def test_box_breakout_ignores_bar_touching_both_edges():
    find_box = getattr(strategy_logic, "find_confirmed_box", None)
    assert callable(find_box)
    rates = _box_rates()
    rates[8] = (rates[8][0], 10.5, 11.0, 10.0, 10.5)

    box = find_box(rates, _box_breakout_config(), point=0.01)
    assert box is None


@pytest.mark.parametrize("width", [100, 200])
def test_box_breakout_width_bounds_are_inclusive(width):
    find_box = getattr(strategy_logic, "find_confirmed_box", None)
    assert callable(find_box)
    rates = _box_rates()
    if width == 200:
        rates = _box_rates(width=2.0)
    config = _box_breakout_config(min_width_points=width, max_width_points=width)

    box = find_box(rates, config, point=0.01)
    assert box is not None
    assert box.width_points == width


@pytest.mark.parametrize("rates,point", [([], 0.01), (_box_rates(), 0),
                                          (_box_rates()[:-1], 0.01)])
def test_box_breakout_rejects_missing_or_invalid_history(rates, point):
    find_box = getattr(strategy_logic, "find_confirmed_box", None)
    assert callable(find_box)
    assert find_box(rates, _box_breakout_config(), point=point) is None


def test_box_breakout_needs_two_consecutive_closes_and_uses_frozen_buffer():
    find_box = getattr(strategy_logic, "find_confirmed_box", None)
    advance = getattr(strategy_logic, "advance_box_breakout", None)
    assert callable(find_box) and callable(advance)
    box = find_box(_box_rates(), _box_breakout_config(), point=0.01)
    frozen_buffer = box.breakout_buffer

    assert advance(box, ("2026-02-01T00:00", 10.9), point=0.01) == "wait"
    assert advance(box, ("2026-02-01T00:01", 11.0 + frozen_buffer + 0.01),
                   point=0.01) == "wait"
    assert advance(box, ("2026-02-01T00:02", 11.0 + frozen_buffer + 0.01),
                   point=0.01) == "buy"
    assert box.breakout_buffer == frozen_buffer


def test_box_breakout_resets_when_close_returns_inside():
    find_box = getattr(strategy_logic, "find_confirmed_box", None)
    advance = getattr(strategy_logic, "advance_box_breakout", None)
    assert callable(find_box) and callable(advance)
    box = find_box(_box_rates(), _box_breakout_config(), point=0.01)
    beyond = box.upper + box.breakout_buffer + 0.01

    assert advance(box, (1, beyond), point=0.01) == "wait"
    assert advance(box, (2, box.upper), point=0.01) == "reset"
    assert advance(box, (3, beyond), point=0.01) == "wait"


def test_box_breakout_maps_upper_and_lower_with_order_type():
    find_box = getattr(strategy_logic, "find_confirmed_box", None)
    advance = getattr(strategy_logic, "advance_box_breakout", None)
    assert callable(find_box) and callable(advance)
    forward = find_box(_box_rates(), _box_breakout_config(), point=0.01)
    reverse = find_box(_box_rates(), _box_breakout_config(order_type="reverse"),
                       point=0.01)
    upper_close = forward.upper + forward.breakout_buffer + 0.01
    lower_close = forward.lower - forward.breakout_buffer - 0.01

    advance(forward, (1, upper_close), point=0.01)
    assert advance(forward, (2, upper_close), point=0.01) == "buy"
    advance(reverse, (1, upper_close), point=0.01)
    assert advance(reverse, (2, upper_close), point=0.01) == "sell"
    advance(reverse, (3, lower_close), point=0.01)
    assert advance(reverse, (4, lower_close), point=0.01) == "buy"


def _box_model(**overrides):
    values = dict(
        initial_direction=Direction.BUY, cycle_mode=CycleMode.MODE_1,
        initial_lots=0.01, multiplier=2.0, distance=500, point=0.01,
        distance_mode=DistanceMode.BOX_BREAKOUT,
        box_breakout_config=_box_breakout_config(),
    )
    values.update(overrides)
    return StrategyModel(**values)


def test_box_breakout_mode_waits_for_confirmed_box_and_two_close_breakout():
    model = _box_model()
    assert model.on_tick(10.8, 10.9, box_rates=_box_rates()) == []
    assert model.position is None
    box = model.box_state
    beyond = box.upper + box.breakout_buffer + 0.01

    assert model.on_tick(10.8, 10.9, box_closed_bar=("b1", beyond)) == []
    actions = model.on_tick(10.8, 10.9, box_closed_bar=("b2", beyond))

    assert actions[0]["kind"] == "market"
    assert model.position.direction is Direction.BUY


def test_box_breakout_mode_locks_equal_stop_and_take_distances():
    model = _box_model()
    model.on_tick(10.8, 10.9, box_rates=_box_rates())
    box = model.box_state
    beyond = box.upper + box.breakout_buffer + 0.01
    model.on_tick(10.8, 10.9, box_closed_bar=("b1", beyond))
    model.on_tick(10.8, 10.9, box_closed_bar=("b2", beyond))

    assert model.group_stop_points == model.group_take_profit_points == 100
    assert model.position.stop_loss == pytest.approx(10.9 - 1.0)
    assert model.position.take_profit == pytest.approx(10.9 + 1.0)


def test_box_breakout_box_expires_after_lookback_new_closed_bars():
    model = _box_model()
    model.on_tick(10.8, 10.9, box_rates=_box_rates())
    assert model.box_state is not None

    for index in range(1, 18):
        model.on_tick(10.8, 10.9, box_closed_bar=(f"b{index}", 10.5))

    assert model.box_state is None


def test_box_breakout_state_restores_and_retries_same_signal_without_duplicate_entry():
    model = _box_model(market_order_failures=1)
    model.on_tick(10.8, 10.9, box_rates=_box_rates())
    box = model.box_state
    beyond = box.upper + box.breakout_buffer + 0.01
    model.on_tick(10.8, 10.9, box_closed_bar=("b1", beyond))
    failed = model.on_tick(10.8, 10.9, box_closed_bar=("b2", beyond))
    assert failed[0]["kind"] == "market_retry"
    saved = model.save_box_state()

    restored = _box_model()
    restored.restore_box_state(saved)
    first = restored.on_tick(10.8, 10.9)
    second = restored.on_tick(10.8, 10.9)

    assert first[0]["kind"] == "market"
    assert second == []
    assert restored.position is not None


def test_box_breakout_pending_signal_expires_after_offline_gap():
    model = _box_model(market_order_failures=2,
                       operation_windows=[(8 * 60, 9 * 60), (0, 0), (0, 0)])
    model.on_tick(10.8, 10.9, box_rates=_box_rates())
    box = model.box_state
    beyond = box.upper + box.breakout_buffer + 0.01
    model.on_tick(10.8, 10.9, now_minute=10 * 60, box_closed_bar=("b1", beyond))
    model.on_tick(10.8, 10.9, now_minute=10 * 60, box_closed_bar=("b2", beyond))
    assert model.box_state.pending_signal_id

    for index in range(3, 3 + model.box_breakout_config.lookback_bars):
        model.on_tick(10.8, 10.9, now_minute=10 * 60,
                      box_closed_bar=(f"b{index}", 10.5))

    assert model.box_state is None
    assert model.position is None


def test_v_enable_defaults_to_zero_in_both_eas():
    for source_path in (MT4_SOURCE, MT5_SOURCE):
        source = source_path.read_text(encoding="utf-8")
        assert re.search(r"input\s+int\s+v_enable\s*=\s*0\b", source)


@pytest.mark.parametrize(
    "source_name,is_mt5,is_xau",
    [
        ("NoMatterRiseFall_MT4.mq4", False, False),
        ("NoMatterRiseFall_MT5.mq5", True, False),
        ("NoMatterRiseFall_MT4_XAU_NetRR_v2_10.mq4", False, True),
        ("NoMatterRiseFall_MT5_XAU_NetRR_v2_10.mq5", True, True),
    ],
)
def test_parameter_organization(source_name, is_mt5, is_xau):
    source = (Path(__file__).resolve().parents[1] / source_name).read_text(encoding="utf-8")
    input_lines = [line for line in source.splitlines() if re.match(r"\s*input\s+(?!group\b)", line)]
    assert input_lines
    assert all(re.search(r"//\s*\[[^]]+\]", line) for line in input_lines)
    assert all(len(re.search(r"//\s*(.*)$", line).group(1)) <= 63 for line in input_lines)

    expected_order = [
        "首单方向", "首单方向确定方式", "循环模式", "距离模式", "开单方式",
        "K线开单模式", "K线多组", "篮子数量", "布林带周期", "布林带标准差",
    ]
    if not is_xau:
        expected_order += [
            "箱体时间模式", "箱体回看小时数", "箱体开始时间", "箱体结束时间",
            "箱体最小高度", "箱体最大高度",
            "箱体识别周期", "箱体观察窗口K线数", "箱体ATR周期", "箱体触碰ATR倍数",
            "箱体上沿最少触碰", "箱体下沿最少触碰", "箱体最少完整往返",
            "箱体同侧触碰间隔", "箱体突破最小宽度", "箱体突破最大宽度",
            "箱体突破缓冲ATR倍数",

        ]
    expected_order += [
        "首单手数", "首单手数倍数", "止损首单类型", "首单类型2倍数",
    ]
    if not is_xau:
        expected_order.append("止损首单固定手数")
    expected_order += ["最大反手次数"]
    if not is_xau:
        expected_order.append("最大首单点差")
    expected_order += [
        "止盈移动模式", "网格数量", "有利方向加单", "动态止损", "网格手数倍数", "v_enable",
        "固定止损距离", "固定止盈距离",
    ]
    if not is_xau:
        expected_order += [
            "布林带止损百分比", "布林带盈亏比", "布林带最小止损距离", "布林带最大止损距离",
        ]
    expected_order += ["K线最小高度", "K线最大高度", "平均K线根数", "平均止损倍数", "平均止盈倍数"]
    if not is_xau:
        expected_order += [
            "ZigZag深度", "ZigZag偏差", "ZigZag回退", "ZigZag距离最小值", "ZigZag距离最大值",
            "ZigZag止损百分比", "ZigZag止盈倍数",
        ]
    expected_order += ["订单识别编号", "订单注释", "开始时间", "结束时间", "时段2开始时间", "时段2结束时间", "时段3开始时间", "时段3结束时间"]
    if is_xau:
        expected_order += [
            "启用XAU净盈亏比" if not is_mt5 else "启用XAU净盈亏比成本模式",
            "目标净盈亏比", "最大开仓点差点数", "最大点差占止损比例", "最大开仓滑点点数",
            "预计平仓滑点点数", "每手往返佣金费用预算", "最大止盈补偿点数", "最大止盈补偿比例",
            "单轮最大预计亏损权益比例", "全部轮次最大预计亏损权益比例", "最长报价延迟毫秒",
        ]
    actual_order = [line.split("=", 1)[0].split()[-1] for line in input_lines]
    assert actual_order == expected_order


@pytest.mark.parametrize(
    "source_name",
    [
        "NoMatterRiseFall_MT4.mq4",
        "NoMatterRiseFall_MT5.mq5",
        "NoMatterRiseFall_MT4_XAU_NetRR_v2_10.mq4",
        "NoMatterRiseFall_MT5_XAU_NetRR_v2_10.mq5",
    ],
)
def test_basket_count_defaults_to_one_and_is_validated(source_name):
    source = (Path(__file__).resolve().parents[1] / source_name).read_text(encoding="utf-8")

    assert re.search(r"input\s+int\s+篮子数量\s*=\s*1\s*;", source)
    assert re.search(r"篮子数量\s*!=\s*1\s*&&\s*篮子数量\s*!=\s*2", source)


@pytest.mark.parametrize(
    ("direction", "count", "expected"),
    [
        (strategy_logic.Direction.BUY, 1, (strategy_logic.Direction.BUY,)),
        (strategy_logic.Direction.BUY, 2, (strategy_logic.Direction.BUY, strategy_logic.Direction.SELL)),
        (strategy_logic.Direction.SELL, 1, (strategy_logic.Direction.SELL,)),
        (strategy_logic.Direction.SELL, 2, (strategy_logic.Direction.SELL, strategy_logic.Direction.BUY)),
    ],
)
def test_basket_directions_preserve_primary_and_add_only_its_opposite(direction, count, expected):
    resolve = getattr(strategy_logic, "basket_directions", None)
    assert callable(resolve)
    assert resolve(direction, count) == expected


@pytest.mark.parametrize("count", [0, 4, -1])
def test_basket_directions_reject_unsupported_counts(count):
    resolve = getattr(strategy_logic, "basket_directions", None)
    assert callable(resolve)
    with pytest.raises(ValueError):
        resolve(strategy_logic.Direction.BUY, count)


def test_initial_pair_recovery_sends_primary_before_opposite_and_uses_distinct_ids():
    launch, missing = strategy_logic.plan_initial_basket_launch(
        event_id=77, primary_group_id=91, opposite_group_id=92,
        direction=strategy_logic.Direction.BUY, basket_count=2, lots=0.03,
        stop_points=600, take_profit_points=800,
    )
    assert [leg.group_id for leg in missing] == [91]

    recovered, missing = strategy_logic.plan_initial_basket_launch(
        event_id=77, primary_group_id=91, opposite_group_id=92,
        direction=strategy_logic.Direction.BUY, basket_count=2, lots=0.03,
        stop_points=600, take_profit_points=800,
        visible_group_ids=[91],
    )
    assert recovered == launch
    assert [leg.group_id for leg in missing] == [92]
    assert missing[0].direction is strategy_logic.Direction.SELL
    assert missing[0].lots == launch.primary.lots
    assert missing[0].stop_points == launch.primary.stop_points
    assert missing[0].take_profit_points == launch.primary.take_profit_points


def test_initial_pair_recovery_does_not_resend_confirmed_legs():
    _, missing = strategy_logic.plan_initial_basket_launch(
        event_id=77, primary_group_id=91, opposite_group_id=92,
        direction=strategy_logic.Direction.SELL, basket_count=2, lots=0.01,
        stop_points=500, take_profit_points=750,
        visible_group_ids=[91, 92],
    )
    assert missing == ()


@pytest.mark.parametrize("source_name", ["NoMatterRiseFall_MT5.mq5", "NoMatterRiseFall_MT5_XAU_NetRR_v2_10.mq5"])
def test_mt5_dual_basket_mode_requires_hedging_account(source_name):
    source = (Path(__file__).resolve().parents[1] / source_name).read_text(encoding="utf-8")

    assert "ACCOUNT_MARGIN_MODE_RETAIL_HEDGING" in source
    paired = r"篮子数量\s*==\s*2" if "XAU_NetRR" in source_name else r"IsPairedBasketMode\(\)"
    assert re.search(paired + r".{0,240}ACCOUNT_MARGIN_MODE_RETAIL_HEDGING", source, re.DOTALL)


def test_two_basket_manager_preserves_existing_kline_multi_group_dispatch():
    for source_name in (
        "NoMatterRiseFall_MT4.mq4",
        "NoMatterRiseFall_MT5.mq5",
        "NoMatterRiseFall_MT4_XAU_NetRR_v2_10.mq4",
        "NoMatterRiseFall_MT5_XAU_NetRR_v2_10.mq5",
    ):
        source = (Path(__file__).resolve().parents[1] / source_name).read_text(encoding="utf-8")
        on_tick = source.split("void OnTick()", 1)[1].split("void OnDeinit", 1)[0]
        manage_start = re.search(r"void Manage\(\)\s*\{", source)
        assert manage_start
        manage_tail = source[manage_start.end():]
        next_function = re.search(r"\n(?:void|bool|int|double|string)\s+\w+\s*\(", manage_tail)
        manage = manage_tail[:next_function.start()] if next_function else manage_tail

        assert "ManageMultipleCandleGroups" in on_tick
        assert "MultiHasActiveGroups" in on_tick or "ManageAllMultiGroups" in on_tick
        assert "篮子数量" in source
        assert any(
            helper in source
            for helper in (
                "StartResolvedMultiPair",
                "MultiStartResolvedPair",
                "MultiStartResolvedStandardPair",
            )
        )


def test_mt5_single_and_multi_managers_share_direction_and_price_rules():
    source = (Path(__file__).resolve().parents[1] / "NoMatterRiseFall_MT5.mq5").read_text(
        encoding="utf-8",
    )

    assert "BasketSequenceDirection(" in source.split(
        "long SequenceDirection", 1,
    )[1].split("int NextCycleIndex", 1)[0]
    assert "BasketSequenceDirection(" in source.split(
        "long MultiSequenceDirection", 1,
    )[1].split("double MultiStopPrice", 1)[0]
    assert "BasketStopPrice(" in source.split(
        "double GroupStopPrice", 1,
    )[1].split("double GroupTakeProfitPrice", 1)[0]
    assert "BasketStopPrice(" in source.split(
        "double MultiStopPrice", 1,
    )[1].split("double MultiTakeProfitPrice", 1)[0]
    assert "BasketTakeProfitPrice(" in source.split(
        "double GroupTakeProfitPrice", 1,
    )[1].split("bool SetGroupStops", 1)[0]
    assert "BasketTakeProfitPrice(" in source.split(
        "double MultiTakeProfitPrice", 1,
    )[1].split("bool MultiSetStops", 1)[0]
    assert "BasketGridPrice(" in source.split(
        "double GridLevelPrice", 1,
    )[1].split("double FavorableGridLevelPrice", 1)[0]
    assert "BasketGridPrice(" in source.split(
        "double MultiGridLevelPrice", 1,
    )[1].split("double MultiFavorableGridLevelPrice", 1)[0]


def test_mt5_multi_stop_recovery_lots_include_the_group_that_just_stopped():
    source = (Path(__file__).resolve().parents[1] / "NoMatterRiseFall_MT5.mq5").read_text(
        encoding="utf-8",
    )
    sizing = source.split("double MultiNextGroupLotsAfterStopRaw", 1)[1].split(
        "double MultiNextGroupLotsAfterStop", 1,
    )[0]

    assert re.search(
        r"group\.cumulative_loss_lots\s*\+\s*fallback",
        sizing,
    )


def test_mt5_max_reversals_closes_only_the_group_that_reached_its_limit():
    source = (Path(__file__).resolve().parents[1] / "NoMatterRiseFall_MT5.mq5").read_text(
        encoding="utf-8",
    )
    multi_manage = source.split("bool MultiManageGroup", 1)[1].split(
        "void ProcessInitialPendingFillEvent", 1,
    )[0]
    finish_group = source.split("bool MultiFinishGroupAfterMaxReversals", 1)[1].split(
        "bool MultiRecoverFlatGroupAfterBrokerStop", 1,
    )[0]

    assert "BeginResetAfterMaxReversals" not in multi_manage
    assert "MultiFinishGroupAfterMaxReversals(group)" in multi_manage
    assert "MultiDeletePending(group.id)" in finish_group
    assert "MultiClosePositions(group.id)" in finish_group
    assert "group.active = false" in finish_group
    assert "if(!group.dual_basket_member)" in finish_group
    assert "BeginResetAfterMaxReversals()" in finish_group


def test_mt5_dual_basket_ownership_is_persisted_across_restarts():
    source = (Path(__file__).resolve().parents[1] / "NoMatterRiseFall_MT5.mq5").read_text(
        encoding="utf-8",
    )
    state = source.split("struct MultiGroupState", 1)[1].split("};", 1)[0]
    save = source.split("void MultiSaveGroup", 1)[1].split("void MultiLoadGroups", 1)[0]
    load = source.split("void MultiLoadGroups", 1)[1].split(
        "int MultiPendingStatus", 1,
    )[0]
    pair_start = source.split("bool MultiStartResolvedPair", 1)[1].split(
        "double MultiNextGroupLotsRaw", 1,
    )[0]

    assert "dual_basket_member" in state
    assert 'prefix + ".dualbasket"' in save
    assert 'prefix + ".dualbasket"' in load
    assert "first.dual_basket_member = true" in pair_start
    assert "second.dual_basket_member = true" in pair_start


@pytest.mark.parametrize(
    ("source_name", "entry_function", "end_marker"),
    [
        ("NoMatterRiseFall_MT4.mq4", "bool MultiTryOpenCandleGroup()", "void MarkMultiCandleTriggerBar"),
        ("NoMatterRiseFall_MT5.mq5", "bool MultiTryOpenCandleGroup()", "void MarkMultiCandleTriggerBar"),
        ("NoMatterRiseFall_MT4_XAU_NetRR_v2_10.mq4", "bool MultiTryOpenCandleGroup()", "void MarkMultiCandleTriggerBar"),
        ("NoMatterRiseFall_MT5_XAU_NetRR_v2_10.mq5", "bool MultiTryOpenCandleGroup()", "void MarkMultiCandleTriggerBar"),
    ],
)
def test_dual_basket_candle_entry_does_not_launch_another_pair_while_one_is_active(
    source_name, entry_function, end_marker,
):
    source = (Path(__file__).resolve().parents[1] / source_name).read_text(encoding="utf-8")
    entry = source.split(entry_function, 1)[1].split(end_marker, 1)[0]

    if "XAU_NetRR" not in source_name:
        assert "if(IsPairedBasketMode() && (MultiHasActiveGroups() || BasketRenewalHasWork()))" in entry
        return
    assert re.search(
        r"if\s*\(\s*篮子数量\s*==\s*2\s*&&\s*MultiHasActiveGroups\(\)\s*\)\s*return\s+false\s*;",
        entry,
    )


@pytest.mark.parametrize(
    ("source_name", "manager_function", "end_marker"),
    [
        ("NoMatterRiseFall_MT4.mq4", "bool MultiManageGroup", "bool ProcessInitialPendingFillEvent"),
        (
            "NoMatterRiseFall_MT4_XAU_NetRR_v2_10.mq4",
            "bool MultiManageGroup",
            "bool ProcessInitialPendingFillEvent",
        ),
    ],
)
def test_mt4_pair_child_waits_for_parent_visibility_instead_of_being_discarded(
    source_name, manager_function, end_marker,
):
    source = (Path(__file__).resolve().parents[1] / source_name).read_text(encoding="utf-8")
    manager = source.split(manager_function, 1)[1].split(end_marker, 1)[0]

    assert not re.search(
        r"launch_confirmed\s*\|\|\s*parent_status\s*==\s*2",
        manager,
    )


@pytest.mark.parametrize(
    ("source_name", "entry_function", "end_marker"),
    [
        (
            "NoMatterRiseFall_MT4_XAU_NetRR_v2_10.mq4",
            "void MultiCostManageGroups()",
            "bool MultiHasActiveGroups",
        ),
        (
            "NoMatterRiseFall_MT5_XAU_NetRR_v2_10.mq5",
            "bool MultiCostTryOpenCandleGroup()",
            "void ManageMultipleCandleGroups",
        ),
    ],
)
def test_dual_basket_cost_candle_entry_does_not_launch_another_pair_while_one_is_active(
    source_name, entry_function, end_marker,
):
    source = (Path(__file__).resolve().parents[1] / source_name).read_text(encoding="utf-8")
    entry = source.split(entry_function, 1)[1].split(end_marker, 1)[0]

    assert re.search(
        r"if\s*\(\s*篮子数量\s*==\s*2\s*&&\s*MultiHasActiveGroups\(\)\s*\)\s*return(?:\s+false)?\s*;",
        entry,
    )



def test_mt4_multi_group_comments_put_group_tag_before_user_comment():
    source = MT4_SOURCE.read_text(encoding="utf-8")
    comment = source.split("string MultiGroupComment", 1)[1].split("\n  }", 1)[0]

    assert "MultiGroupTag(group_id) + InpOrderComment" in comment


@pytest.mark.parametrize(
    ("source_name", "is_mt5", "is_xau"),
    [
        ("NoMatterRiseFall_MT4.mq4", False, False),
        ("NoMatterRiseFall_MT5.mq5", True, False),
        ("NoMatterRiseFall_MT4_XAU_NetRR_v2_10.mq4", False, True),
        ("NoMatterRiseFall_MT5_XAU_NetRR_v2_10.mq5", True, True),
    ],
)
def test_kline_initial_oco_resolves_both_fills_without_opening_third_basket(source_name, is_mt5, is_xau):
    source = (Path(__file__).resolve().parents[1] / source_name).read_text(encoding="utf-8")
    handler = source.split("bool MultiHandleInitialPendingFill", 1)[1].split(
        "bool MultiNormalizeReversePending", 1,
    )[0]

    oco_manager = source.split("bool MultiHandleOcoBasketGroup", 1)
    if len(oco_manager) == 2:
        oco_manager = oco_manager[1].split("\nbool ", 1)[0]
        assert "REVERSE_PENDING_FILLED" in oco_manager
        assert "peer_status" in oco_manager
        assert "own_status == REVERSE_PENDING_FILLED" in oco_manager
        assert "peer_status == REVERSE_PENDING_FILLED" in oco_manager
        assert "signal_consumed = true" in oco_manager
    else:
        assert "high_filled && low_filled" in handler or "MultiHandlePairedInitialPendingFill" in handler
        assert "MultiHandlePairedInitialPendingFill" in source
        paired_handler = source.split("bool MultiHandlePairedInitialPendingFill", 1)[1].split(
            "bool MultiHandleInitialPendingFill", 1,
        )[0]
        assert "peer_filled" in paired_handler
        assert "if(!peer_filled)" in paired_handler.replace(" ", "")



@pytest.mark.parametrize(
    ("source_name", "is_xau"),
    [
        ("NoMatterRiseFall_MT5.mq5", False),
        ("NoMatterRiseFall_MT5_XAU_NetRR_v2_10.mq5", True),
    ],
)
def test_mt5_input_groups_remain_in_their_documented_order(source_name, is_xau):
    source = (Path(__file__).resolve().parents[1] / source_name).read_text(encoding="utf-8")
    groups = re.findall(r'^input group "([^"]+)";', source, flags=re.MULTILINE)
    expected_groups = (
        [">>>> 策略与首单", ">>>> 入场信号", ">>>> 手数与风险", ">>>> 网格与止盈", ">>>> 止盈止损距离", ">>>> 订单识别", ">>>> 交易时段", ">>>> 净盈亏比与交易成本"]
        if is_xau
        else [">>>> 策略与首单", ">>>> 入场信号", ">>>> 时间箱体", ">>>> 箱体确认突破", ">>>> 手数与风险", ">>>> 网格与止盈", ">>>> 止盈止损距离", ">>>> 订单识别", ">>>> 交易时段"]

    )
    assert groups == expected_groups


def test_mt5_ui_switch_does_not_disable_trade_timer():
    source = MT5_SOURCE.read_text(encoding="utf-8")
    init_body = re.search(
        r"int OnInit\(\).*?\n\s*\}\n\nvoid OnTradeTransaction",
        source,
        flags=re.DOTALL,
    ).group(0)
    render_body = re.search(
        r"void GuiRenderIfNeeded\(\).*?\n\s*\}\n\nvoid GuiMarkDraftChanged",
        source,
        flags=re.DOTALL,
    ).group(0)
    chart_event_body = re.search(
        r"void OnChartEvent\(.*?\n\s*\}\n\nint OnInit",
        source,
        flags=re.DOTALL,
    ).group(0)

    assert re.search(r"if\s*\(v_enable\s*==\s*1\)", init_body)
    assert "EventSetTimer(1)" in init_body
    assert "if(v_enable != 1)" in render_body
    assert "if(v_enable != 1)" in chart_event_body

from strategy_logic import (
    CycleMode, Direction, DistanceMode, ExecutionOwnershipRegistry,
    ExposureSnapshot, GuiStateModel, OrderType, ParallelStrategyModel, PendingRecord,
    PreparedTransition, StrategyModel, TakeProfitMode, exposure_guard,
    average_candle_distances, normalize_pending_records, recover_prepared_transition,
    cycle_directions, FirstDirectionMode, long_candle_direction,
    plan_reversal_lots, resolve_first_direction,
)


@pytest.mark.parametrize(
    ("mode", "price", "middle", "expected"),
    [
        (FirstDirectionMode.PRESET, 105.0, 100.0, Direction.SELL),
        (FirstDirectionMode.BOLLINGER, 105.0, 100.0, Direction.BUY),
        (FirstDirectionMode.BOLLINGER, 95.0, 100.0, Direction.SELL),
        (FirstDirectionMode.BOLLINGER, 100.0, 100.0, None),
    ],
)
def test_first_direction_resolution_uses_bollinger_middle(mode, price, middle, expected):
    assert resolve_first_direction(mode, Direction.SELL, price, middle) is expected


def test_bollinger_middle_tie_does_not_open_a_market_order():
    assert resolve_first_direction(
        FirstDirectionMode.BOLLINGER, Direction.BUY, 100.0, 100.0,
    ) is None


def test_box_range_window_supports_rolling_lookback():
    from datetime import datetime, timedelta, timezone

    now = datetime(2026, 10, 6, 12, 34, tzinfo=timezone.utc)
    resolve_window = getattr(strategy_logic, "box_range_window", None)
    assert callable(resolve_window)

    start, end = resolve_window(now, "rolling", lookback_hours=12)

    assert start == now - timedelta(hours=12)
    assert end == now


@pytest.mark.parametrize(
    ("now", "expected_start", "expected_end"),
    [
        ("2026-10-06T08:00", "2026-10-05T01:00", "2026-10-05T12:00"),
        ("2026-10-06T12:00", "2026-10-06T01:00", "2026-10-06T12:00"),
        ("2026-10-06T12:01", "2026-10-06T01:00", "2026-10-06T12:00"),
    ],
)
def test_box_range_window_uses_most_recent_completed_daily_session(
        now, expected_start, expected_end):
    from datetime import datetime

    resolve_window = getattr(strategy_logic, "box_range_window", None)
    assert callable(resolve_window)

    start, end = resolve_window(
        datetime.fromisoformat(now), "daily_session",
        session_start="01:00", session_end="12:00",
    )

    assert start == datetime.fromisoformat(expected_start)
    assert end == datetime.fromisoformat(expected_end)


def test_box_range_window_rejects_invalid_duration_and_equal_session_times():
    from datetime import datetime, timezone

    resolve_window = getattr(strategy_logic, "box_range_window", None)
    assert callable(resolve_window)
    now = datetime(2026, 10, 6, 12, 0, tzinfo=timezone.utc)

    assert resolve_window(now, "rolling", lookback_hours=0) is None
    assert resolve_window(
        now, "daily_session", session_start="01:00", session_end="01:00",
    ) is None
    assert resolve_window(
        now, "daily_session", session_start="25:00", session_end="12:00",
    ) is None


@pytest.mark.parametrize("actual_points", [500, 1000])
def test_box_height_accepts_inclusive_minimum_and_maximum(actual_points):
    from datetime import datetime, timedelta

    start = datetime(2026, 10, 6, 1, 0)
    end = start + timedelta(minutes=2)
    rates = [
        (start, 100.0 + actual_points * 0.01, 100.0),
        (start + timedelta(minutes=1), 100.0 + actual_points * 0.01, 100.0),
    ]
    calculate = getattr(strategy_logic, "box_range_points", None)
    assert callable(calculate)

    points = calculate(rates, start, end, point=0.01,
                       min_points=500, max_points=1000)

    assert points == actual_points


def test_box_height_uses_extremes_and_rejects_out_of_range_or_missing_history():
    from datetime import datetime, timedelta

    start = datetime(2026, 10, 6, 1, 0)
    end = start + timedelta(minutes=3)
    rates = [
        (start, 10.0, 9.0),
        (start + timedelta(minutes=1), 13.0, 8.0),
        (start + timedelta(minutes=2), 11.0, 10.0),
    ]
    calculate = getattr(strategy_logic, "box_range_points", None)
    assert callable(calculate)

    assert calculate(rates, start, end, point=0.1,
                     min_points=10, max_points=100) == 50
    assert calculate(rates, start, end, point=0.1,
                     min_points=51, max_points=100) is None
    assert calculate([], start, end, point=0.1,
                     min_points=1, max_points=100) is None


def test_box_height_mode_uses_height_for_both_distances_without_breakout_entry():
    mode = getattr(DistanceMode, "BOX_RANGE", None)
    assert mode is not None
    model = StrategyModel(
        Direction.BUY, CycleMode.MODE_1, 0.01, 2.0, 500, 0.0001,
        distance_mode=mode, box_height_points=750,
        box_min_height_points=500, box_max_height_points=1000,
    )

    actions = model.on_tick(bid=1.1000, ask=1.1002)

    assert actions[0]["kind"] == "market"
    assert model.position.stop_loss == pytest.approx(1.1002 - 0.075)
    assert model.position.take_profit == pytest.approx(1.1002 + 0.075)


@pytest.mark.parametrize("source_path", [MT4_SOURCE, MT5_SOURCE])
def test_box_height_distance_mode_is_available_in_both_canonical_sources(source_path):
    source = source_path.read_text(encoding="utf-8")

    assert "DISTANCE_BOX_RANGE = 6" in source
    assert "箱体时间模式" in source
    assert "箱体回看小时数 = 12" in source
    assert '箱体开始时间 = "01:00"' in source
    assert '箱体结束时间 = "12:00"' in source
    assert "箱体最小高度 = 500" in source
    assert "箱体最大高度 = 1000" in source
    assert "PERIOD_M1" in source


def test_mt5_box_height_mode_is_exposed_and_editable_in_gui():
    source = MT5_SOURCE.read_text(encoding="utf-8")
    assert 'return key == "distance_mode" ? 8 : 2;' in source

    assert 'if(index == 6) return "箱体高度";' in source
    assert 'GuiRenderEnumField("box_range_time_mode"' in source
    assert 'GuiRenderEditableDropdownField("box_range_lookback_hours"' in source
    assert 'GuiRenderEditableDropdownField("box_range_start_time"' in source
    assert 'GuiRenderEditableDropdownField("box_range_min_points"' in source
    assert 'g_gui_draft_config.box_range_max_points = parsed_integer;' in source
    editable_field_keys = re.search(
        r"bool GuiIsEditableFieldKey\(.*?\n\s*\}", source, flags=re.DOTALL,
    ).group(0)
    for key in ("box_range_lookback_hours", "box_range_start_time",
                "box_range_end_time", "box_range_min_points",
                "box_range_max_points"):
        assert f'key == "{key}"' in editable_field_keys


@pytest.mark.parametrize("source_path", [MT4_SOURCE, MT5_SOURCE])
def test_box_breakout_expiry_precedes_pending_signal_replay(source_path):
    source = source_path.read_text(encoding="utf-8")
    body = source.split("bool AdvanceBoxBreakout(", 1)[1].split("\nbool ", 1)[0]
    assert body.index("age_bars + last_shift") < body.index("g_box_state.signal_id != 0")


def test_box_breakout_mode_scopes_validation_and_releases_mt5_atr_handle():
    mt4 = MT4_SOURCE.read_text(encoding="utf-8")
    mt5 = MT5_SOURCE.read_text(encoding="utf-8")
    assert re.search(
        r"InpDistanceMode\s*==\s*DISTANCE_BOX_BREAKOUT\s*&&\s*\(PeriodSeconds",
        mt4,
    )
    validation = mt5.split("bool ValidateGuiConfig(", 1)[1].split("\nint ", 1)[0]
    assert "if(config.distance_mode == DISTANCE_BOX_BREAKOUT)" in validation
    deinit = mt5.split("void OnDeinit(", 1)[1]
    assert "ReleaseBoxAtrHandle();" in deinit



@pytest.mark.parametrize(
    ("price", "expected"),
    [(110.0, Direction.SELL), (90.0, Direction.BUY),
     (105.0, None), (95.0, None), (100.0, None)],
)
def test_bollinger_distance_mode_only_enters_on_outer_band_touch(price, expected):
    resolver = getattr(strategy_logic, "bollinger_touch_direction", None)
    assert callable(resolver)
    assert resolver(price=price, upper=110.0, lower=90.0, point=1.0, order_type=1) is expected
    assert resolver(price=110.0 - 0.4, upper=110.0, lower=90.0, point=1.0, order_type=1) is Direction.SELL
    assert resolver(price=90.0 + 0.4, upper=110.0, lower=90.0, point=1.0, order_type=1) is Direction.BUY


@pytest.mark.parametrize("source_path", [MT4_SOURCE, MT5_SOURCE])
def test_bollinger_touch_direction_reuses_existing_order_type(source_path):
    source = source_path.read_text(encoding="utf-8")
    assert "GetBollingerTouchDirection" in source
    assert re.search(r"(?:distance_mode|InpDistanceMode)\s*==\s*DISTANCE_BOLLINGER_RANGE", source)
    assert "布林带开单方向" not in source
    function = re.search(
        r"bool GetBollingerTouchDirection\(.*?\n\s*\}\n",
        source,
        flags=re.DOTALL,
    )
    assert function
    body = function.group(0)
    order_type = "g_gui_applied_config.order_type" if source_path == MT5_SOURCE else "开单方式"
    assert order_type in body
    assert re.search(r"upper.*?ORDER_TYPE_BUY|upper.*?OP_BUY", body, flags=re.DOTALL)
    assert re.search(r"lower.*?ORDER_TYPE_SELL|lower.*?OP_SELL", body, flags=re.DOTALL)
    assert re.search(r"upper.*?ORDER_TYPE_SELL|upper.*?OP_SELL", body, flags=re.DOTALL)
    assert re.search(r"lower.*?ORDER_TYPE_BUY|lower.*?OP_BUY", body, flags=re.DOTALL)


@pytest.mark.parametrize(
    ("order_type", "price", "expected"),
    [
        (0, 110.0, Direction.BUY),
        (0, 90.0, Direction.SELL),
        (1, 110.0, Direction.SELL),
        (1, 90.0, Direction.BUY),
    ],
)
def test_bollinger_touch_direction_maps_upper_and_lower_by_selected_mode(
    order_type, price, expected,
):
    resolver = getattr(strategy_logic, "bollinger_touch_direction", None)
    assert resolver(price=price, upper=110.0, lower=90.0, point=1.0,
                    order_type=order_type) is expected


def test_bollinger_touch_direction_defaults_to_forward_and_rejects_unknown_order_type():
    resolver = getattr(strategy_logic, "bollinger_touch_direction", None)
    assert resolver(price=110.0, upper=110.0, lower=90.0, point=1.0) is Direction.BUY
    assert resolver(price=110.0, upper=110.0, lower=90.0, point=1.0,
                    order_type=2) is None


def test_bollinger_stop_distance_uses_configurable_percent_with_25_default():
    resolver = getattr(strategy_logic, "bollinger_stop_distance_points", None)
    assert callable(resolver)
    assert resolver(upper=110.0, lower=90.0, point=1.0) == 5
    assert resolver(upper=1.1010, lower=1.0990, point=0.0001) == 5
    assert resolver(upper=110.0, lower=90.0, point=1.0, percent=50.0) == 10
    assert resolver(upper=110.0, lower=90.0, point=1.0, percent=12.5) == 3


def test_bollinger_stop_distance_rejects_invalid_band_data():
    resolver = getattr(strategy_logic, "bollinger_stop_distance_points", None)
    assert callable(resolver)
    assert resolver(upper=100.0, lower=100.0, point=1.0) is None
    assert resolver(upper=90.0, lower=110.0, point=1.0) is None
    assert resolver(upper=110.0, lower=90.0, point=0.0) is None
    assert resolver(upper=110.0, lower=90.0, point=1.0, percent=0) is None
    assert resolver(upper=110.0, lower=90.0, point=1.0, percent=float("inf")) is None


@pytest.mark.parametrize(
    ("quarter_width", "expected"),
    [(199, None), (200, 200), (600, 600), (1000, 1000), (1001, None)],
)
def test_bollinger_quarter_width_only_allows_inclusive_entry_range(quarter_width, expected):
    assert strategy_logic.bollinger_stop_distance_points(
        upper=quarter_width * 4, lower=0, point=1,
        min_points=200, max_points=1000,
    ) == expected


def test_bollinger_entry_range_checks_rounded_distance():
    assert strategy_logic.bollinger_stop_distance_points(
        upper=798, lower=0, point=1, min_points=200, max_points=1000,
    ) == 200


def test_bollinger_entry_range_checks_configured_percent_before_filtering():
    assert strategy_logic.bollinger_stop_distance_points(
        upper=400, lower=0, point=1, min_points=200, max_points=200, percent=50,
    ) == 200
    assert strategy_logic.bollinger_stop_distance_points(
        upper=400, lower=0, point=1, min_points=201, max_points=1000, percent=50,
    ) is None


@pytest.mark.parametrize("source_name", ["NoMatterRiseFall_MT4.mq4", "NoMatterRiseFall_MT5.mq5"])
def test_bollinger_first_direction_inputs_and_tie_guard_exist(source_name):
    source = (Path(__file__).parents[1] / source_name).read_text(encoding="utf-8")

    assert "FirstDirectionMode" in source
    assert "首单方向确定方式" in source
    assert re.search(r"布林带周期\s*=\s*20", source)
    assert re.search(r"布林带标准差\s*=\s*2\.0", source)
    assert "iBands" in source
    assert "FIRST_DIRECTION_BOLLINGER" in source
    assert re.search(r"price\s*==\s*middle|middle\s*==\s*price|MathAbs\([^\n]*middle", source)


@pytest.mark.parametrize("source_name", ["NoMatterRiseFall_MT4.mq4", "NoMatterRiseFall_MT5.mq5"])
def test_bollinger_distance_mode_uses_upper_lower_width_and_percent(source_name):
    source = (Path(__file__).parents[1] / source_name).read_text(encoding="utf-8")

    assert "DISTANCE_BOLLINGER_RANGE" in source
    assert re.search(r"上轨|MODE_UPPER|base.*upper|upper", source, flags=re.IGNORECASE)
    assert re.search(r"下轨|MODE_LOWER|base.*lower|lower", source, flags=re.IGNORECASE)
    assert re.search(r"input\s+double\s+布林带止损百分比\s*=\s*25\.0\s*;", source)
    assert "GetBollingerDistancePoints" in source


@pytest.mark.parametrize("source_name", ["NoMatterRiseFall_MT4.mq4", "NoMatterRiseFall_MT5.mq5"])
def test_bollinger_distance_uses_configured_reward_risk_ratio(source_name):
    source = (Path(__file__).parents[1] / source_name).read_text(encoding="utf-8")
    body = re.search(
        r"bool GetBollingerDistancePoints\(.*?\n\s*\}\n",
        source,
        flags=re.DOTALL,
    ).group(0)
    assert "布林带止损百分比 / 100.0" in body or "bollinger_stop_percent / 100.0" in body
    assert re.search(r"input\s+double\s+布林带盈亏比\s*=\s*1\.0\s*;", source)
    assert "stop_loss_points * 布林带盈亏比" in body or "* g_gui_applied_config.bollinger_reward_risk_ratio" in body
    assert "take_profit_points = (int)MathRound(take_profit);" in body


@pytest.mark.parametrize("source_name", ["NoMatterRiseFall_MT4.mq4", "NoMatterRiseFall_MT5.mq5"])
def test_bollinger_entry_distance_has_separate_inclusive_limits(source_name):
    source = (Path(__file__).parents[1] / source_name).read_text(encoding="utf-8")
    assert re.search(r"input\s+int\s+布林带最小止损距离\s*=\s*200\s*;", source)
    assert re.search(r"input\s+int\s+布林带最大止损距离\s*=\s*1000\s*;", source)
    body = source.split("bool GetBollingerDistancePoints(", 1)[1].split("bool GetDistancePoints(", 1)[0]
    assert "stop_loss_points <" in body
    assert "stop_loss_points >" in body
    assert "布林带最小止损距离" in body or "bollinger_min_stop_points" in body
    assert "布林带最大止损距离" in body or "bollinger_max_stop_points" in body


def test_mt5_bollinger_limits_are_editable_on_distance_page():
    source = MT5_SOURCE.read_text(encoding="utf-8")
    for key in ("bollinger_min_stop_points", "bollinger_max_stop_points"):
        assert f'GuiRenderEditableDropdownField("{key}"' in source
        assert f'key == "{key}"' in source
        assert f'config.{key} = ' in source


def test_mt5_bollinger_percent_uses_gui_config_and_legacy_fingerprint_migration():
    source = MT5_SOURCE.read_text(encoding="utf-8")
    key = "bollinger_stop_percent"
    assert f'double {key};' in source
    assert f'config.{key} = 布林带止损百分比;' in source
    assert f'GuiRenderEditableDropdownField("{key}"' in source
    assert f'key == "{key}"' in source
    assert "GuiConfigBeforeBollingerPercentFingerprintText" in source


def test_mt5_bollinger_touch_reuses_existing_open_order_setting():
    source = MT5_SOURCE.read_text(encoding="utf-8")
    assert "bollinger_entry_direction" not in source
    assert "config.order_type = 开单方式;" in source
    assert 'GuiRenderEnumField("order_type", "开单方式"' in source
    function = re.search(r"bool GetBollingerTouchDirection\(.*?\n\s*\}\n", source, flags=re.DOTALL)
    assert function and "g_gui_applied_config.order_type" in function.group(0)


@pytest.mark.parametrize(
    ("total_lots", "status", "legs"),
    [
        (100.0, "single", (100.0,)),
        (100.01, "split", (50.005, 50.005)),
        (120.0, "split", (60.0, 60.0)),
        (199.99, "split", (99.995, 99.995)),
        (200.0, "restart_group", ()),
        (250.0, "restart_group", ()),
    ],
)
def test_reversal_lot_plan_enforces_terminal_broker_limits(total_lots, status, legs):
    plan = plan_reversal_lots(total_lots)

    assert plan.status == status
    assert plan.lots == pytest.approx(legs)
    assert all(lot <= 100.0 for lot in plan.lots)
    if status != "restart_group":
        assert sum(plan.lots) == pytest.approx(total_lots)


def test_reversal_lot_plan_rejects_non_positive_volume():
    with pytest.raises(ValueError):
        plan_reversal_lots(0.0)


@pytest.mark.parametrize("source_name", ["NoMatterRiseFall_MT4.mq4", "NoMatterRiseFall_MT5.mq5"])
def test_split_reversal_records_total_as_next_group_first_lot(source_name):
    source = (Path(__file__).parents[1] / source_name).read_text(encoding="utf-8")

    assert "g_group_total_lots = TotalPosition" in source
    assert "g_group_first_lots = g_group_total_lots;" in source


@pytest.mark.parametrize("source_name", ["NoMatterRiseFall_MT4.mq4", "NoMatterRiseFall_MT5.mq5"])
def test_multi_reverse_pending_is_reconciled_to_current_group_state(source_name):
    source = (Path(__file__).parents[1] / source_name).read_text(encoding="utf-8")
    body = re.search(
        r"bool MultiPlaceReversePending\(.*?\n\s*\}\n\n",
        source,
        flags=re.DOTALL,
    ).group(0)

    assert "MultiNormalizeReversePending" in body


@pytest.mark.parametrize("source_name", ["NoMatterRiseFall_MT4.mq4", "NoMatterRiseFall_MT5.mq5"])
def test_initial_double_fill_closes_the_other_initial_position(source_name):
    source = (Path(__file__).parents[1] / source_name).read_text(encoding="utf-8")
    assert "if(high_filled && low_filled)" in source
    assert ("MultiClosePositionsExcept" in source
            if source_name.endswith("MT5.mq5")
            else "ClosePreviousGroupAfterReverseFill" in source)


def test_mt5_gui_migrates_legacy_state_without_fingerprint_once():
    source = MT5_SOURCE.read_text(encoding="utf-8")
    migration = re.search(
        r"bool MigrateLegacyGuiConfig\(.*?\n\s*\}\n\n",
        source,
        flags=re.DOTALL,
    )

    assert migration, "MT5 GUI must provide a legacy-config migration path"
    body = migration.group(0)
    assert "configfingerprint" in body
    assert "GlobalVariableSet" in body
    assert "return true" in body

    validation = re.search(
        r"bool ValidatePersistedConfigForMagic\(.*?\n\s*\}\n\nvoid SaveState",
        source,
        flags=re.DOTALL,
    )
    assert validation
    assert "MigrateLegacyGuiConfig" in validation.group(0)


def test_mt5_gui_initial_load_allows_recovery_of_active_scope():
    source = MT5_SOURCE.read_text(encoding="utf-8")
    apply_config = re.search(
        r"bool ApplyGuiConfig\(.*?\n\s*\}\n\nGuiConfig LoadConfigFromInputs",
        source,
        flags=re.DOTALL,
    )

    assert apply_config
    first_line = re.search(
        r"const bool allow_initial_scope_recovery = (.*?);",
        apply_config.group(0),
        flags=re.DOTALL,
    )
    assert first_line
    assert "HasManagedExposureForMagic(config.magic_number)" in first_line.group(1)


def test_mt5_gui_keeps_editable_pages_stable_between_user_events():
    source = MT5_SOURCE.read_text(encoding="utf-8")
    render_if_needed = re.search(
        r"void GuiRenderIfNeeded\(\).*?\n\s*\}\n\nvoid GuiMarkDraftChanged",
        source,
        flags=re.DOTALL,
    )

    assert render_if_needed
    body = render_if_needed.group(0)
    assert "g_gui_page != GUI_PAGE_OVERVIEW" in body
    assert "g_gui_dirty" in body
    assert "return;" in body


def test_mt5_gui_exposes_every_input_parameter_on_an_editable_page():
    source = MT5_SOURCE.read_text(encoding="utf-8")
    render_content = re.search(
        r"bool GuiRenderContent\(\).*?\n\s*\}\n\nbool GuiRenderActions",
        source,
        flags=re.DOTALL,
    )

    assert render_content, "MT5 GUI content renderer must remain discoverable"
    body = render_content.group(0)
    for key in (
        "first_direction", "first_direction_mode", "cycle_mode", "distance_mode", "order_type",
        "candle_order_mode", "candle_enable_multiple", "take_profit_mode",
        "favorable_grid_enable",
        "initial_lots", "initial_lots_multiplier", "max_reversals",
        "grid_count", "grid_lot_multiplier", "stop_loss_distance_points",
        "take_profit_distance_points", "candle_min_range_points",
        "candle_max_range_points", "average_candle_count",
        "average_stop_multiplier", "average_take_profit_multiplier",
        "bollinger_period", "bollinger_deviation",
        "magic_number", "order_comment",
        "start_time", "end_time",
    ):
        assert f'"{key}"' in body, f"GUI is missing input parameter: {key}"


def test_mt5_gui_uses_dropdown_option_lists_for_all_selectable_modes():
    source = MT5_SOURCE.read_text(encoding="utf-8")
    assert "bool GuiRenderDropdownField" in source
    assert "bool GuiHandleDropdownClick" in source
    assert '"dropdown."' in source
    for key in (
        "first_direction", "first_direction_mode", "cycle_mode", "distance_mode", "order_type",
        "candle_order_mode", "candle_enable_multiple", "take_profit_mode",
        "favorable_grid_enable",
    ):
        assert f'"{key}"' in re.search(
            r"int GuiDropdownOptionCount\(.*?\n\s*\}\n\n",
            source,
            flags=re.DOTALL,
        ).group(0)


def test_mt5_gui_dropdown_clicks_are_dispatched_before_redraw():
    source = MT5_SOURCE.read_text(encoding="utf-8")
    chart_event = re.search(
        r"void OnChartEvent\(.*?\n\s*\}\n\nint OnInit",
        source,
        flags=re.DOTALL,
    )

    assert chart_event
    body = chart_event.group(0)
    assert "GuiHandleDropdownClick(sparam)" in body
    assert body.index("GuiHandleDropdownClick(sparam)") < body.index("GuiHandleEnumClick(sparam)")


def test_mt5_gui_overview_includes_applied_configuration_summary():
    source = MT5_SOURCE.read_text(encoding="utf-8")
    overview = re.search(
        r"if\(g_gui_page == GUI_PAGE_OVERVIEW\).*?\n\s*\}\n\s*else if\(g_gui_page == GUI_PAGE_OPENING\)",
        source,
        flags=re.DOTALL,
    )

    assert overview, "GUI overview page must remain discoverable"
    body = overview.group(0)
    for key in (
        "overview.cycle_mode", "overview.distance_mode", "overview.order_type",
        "overview.initial_lots", "overview.grid_count", "overview.stops",
        "overview.schedule",
    ):
        assert f'"{key}"' in body, f"Overview is missing applied configuration: {key}"


def test_mt5_gui_interactive_objects_have_explicit_event_priority():
    source = MT5_SOURCE.read_text(encoding="utf-8")
    button = re.search(
        r"bool GuiCreateButton\(.*?\n\s*\}\n\nbool GuiCreateEdit",
        source,
        flags=re.DOTALL,
    )
    edit = re.search(
        r"bool GuiCreateEdit\(.*?\n\s*\}\n\nbool GuiTrackCreateResult",
        source,
        flags=re.DOTALL,
    )

    assert button and edit
    assert "OBJPROP_SELECTABLE, true" in button.group(0)
    assert "OBJPROP_ZORDER, 1000" in button.group(0)
    assert "OBJPROP_SELECTABLE, true" in edit.group(0)
    assert "OBJPROP_ZORDER, 1000" in edit.group(0)


def test_mt5_gui_has_chart_coordinate_fallback_for_control_clicks():
    source = MT5_SOURCE.read_text(encoding="utf-8")
    assert "bool GuiHandleChartClick" in source
    chart_event = re.search(
        r"void OnChartEvent\(.*?\n\s*\}\n\nint OnInit",
        source,
        flags=re.DOTALL,
    )

    assert chart_event
    body = chart_event.group(0)
    assert "id == CHARTEVENT_CLICK" in body
    assert "GuiHandleChartClick((int)lparam, (int)dparam)" in body


def test_mt5_gui_chart_fallback_covers_navigation_and_actions():
    source = MT5_SOURCE.read_text(encoding="utf-8")
    chart_click = re.search(
        r"^bool GuiHandleChartClick\(.*?\n\s*\}\n\nbool GuiApplyDraft",
        source,
        flags=re.DOTALL | re.MULTILINE,
    )
    assert chart_click
    body = chart_click.group(0)
    assert "nav." in body
    assert "g_gui_page = (GuiPage)index" in body
    assert '"mode.toggle"' in body
    assert '"apply"' in body
    assert '"pause"' in body


def test_mt5_gui_chart_fallback_does_not_swallow_object_click_dispatch():
    source = MT5_SOURCE.read_text(encoding="utf-8")
    chart_event = re.search(
        r"if\(id == CHARTEVENT_CLICK\)\n\s*\{.*?\n\s*\}\n\s*if\(id == CHARTEVENT_KEYDOWN",
        source,
        flags=re.DOTALL,
    )
    assert chart_event
    body = chart_event.group(0)
    assert "GuiRender();\n      return;" not in body


def test_mt5_gui_edit_focus_does_not_turn_edit_boxes_into_draggable_objects():
    source = MT5_SOURCE.read_text(encoding="utf-8")
    chart_click = re.search(
        r"bool GuiHandleChartClick\(.*?\n\s*\}\n\nbool GuiApplyDraft",
        source,
        flags=re.DOTALL,
    )
    assert chart_click
    body = chart_click.group(0)
    assert "OBJPROP_SELECTED, true" not in body
    assert "OBJPROP_READONLY, false" in body


def test_mt5_gui_releases_button_state_after_object_click_dispatch():
    source = MT5_SOURCE.read_text(encoding="utf-8")
    chart_event = re.search(
        r"void OnChartEvent\(.*?\n\s*\}\n\nint OnInit",
        source,
        flags=re.DOTALL,
    )
    assert chart_event
    body = chart_event.group(0)
    assert "GuiReleaseButtonState(sparam)" in body


def test_mt5_gui_mode_toggle_has_visible_mode_hint():
    source = MT5_SOURCE.read_text(encoding="utf-8")
    assert '"mode.hint"' in source
    assert "全部参数仍可编辑" in source


def test_mt5_gui_dropdown_layer_is_above_other_interactive_controls():
    source = MT5_SOURCE.read_text(encoding="utf-8")
    dropdown = re.search(
        r"bool GuiCreateDropdownOption\(.*?\n\s*\}\n\nbool GuiRenderDropdownField",
        source,
        flags=re.DOTALL,
    )

    assert dropdown
    assert "OBJPROP_ZORDER, 2000" in dropdown.group(0)


def test_mt5_gui_dropdown_options_are_rendered_after_all_page_fields():
    source = MT5_SOURCE.read_text(encoding="utf-8")
    field = re.search(
        r"bool GuiRenderDropdownField\(.*?\n\s*\}\n\nbool GuiDropdownFieldPosition",
        source,
        flags=re.DOTALL,
    )
    overlay = re.search(
        r"bool GuiRenderDropdownOverlay\(.*?\n\s*\}\n\nbool GuiRenderLabelValue",
        source,
        flags=re.DOTALL,
    )
    content = re.search(
        r"bool GuiRenderContent\(.*?\n\s*\}\n\nbool GuiRenderActions",
        source,
        flags=re.DOTALL,
    )
    assert field and overlay and content
    assert "GuiCreateDropdownOption" not in field.group(0)
    assert "GuiCreateDropdownOption" in overlay.group(0)
    assert "GuiRenderDropdownOverlay(ok)" in content.group(0)


def test_mt5_gui_field_click_dispatch_is_before_active_edit_guard():
    source = MT5_SOURCE.read_text(encoding="utf-8")
    chart_event = re.search(
        r"void OnChartEvent\(.*?\n\s*\}\n\nint OnInit",
        source,
        flags=re.DOTALL,
    )
    assert chart_event
    body = chart_event.group(0)
    assert "GuiHandleFieldClick(sparam)" in body
    assert body.index("GuiHandleFieldClick(sparam)") < body.index(
        "id == CHARTEVENT_OBJECT_CLICK && StringLen(g_gui_edit_key) > 0"
    )


def test_mt5_gui_field_clicks_switch_edit_and_dropdown_sessions_cleanly():
    source = MT5_SOURCE.read_text(encoding="utf-8")
    field_click = re.search(
        r"bool GuiHandleFieldClick\(.*?\n\s*\}\n\nbool GuiHandleChartClick",
        source,
        flags=re.DOTALL,
    )
    assert field_click
    body = field_click.group(0)
    assert "g_gui_dropdown_key = \"\"" in body
    assert "g_gui_edit_key = \"\"" in body
    assert "GuiLeaveEditSession()" in body
    assert "OBJPROP_READONLY, false" in body


def test_mt5_gui_edit_click_keeps_native_edit_focus_without_recreating_objects():
    source = MT5_SOURCE.read_text(encoding="utf-8")
    chart_event = re.search(
        r"void OnChartEvent\(.*?\n\s*\}\n\nint OnInit",
        source,
        flags=re.DOTALL,
    )
    assert chart_event
    body = chart_event.group(0)
    dispatch = body[body.index("if(id == CHARTEVENT_OBJECT_CLICK && GuiHandleFieldClick(sparam))") :]
    assert "if(!GuiIsEditableFieldKey" in dispatch
    assert dispatch.index("if(!GuiIsEditableFieldKey") < dispatch.index("GuiRender();")


def test_mt5_gui_does_not_toggle_a_dropdown_twice_for_one_mouse_click():
    source = MT5_SOURCE.read_text(encoding="utf-8")
    assert "bool GuiShouldSkipChartClick" in source
    assert "void GuiRememberObjectClick" in source
    chart_event = re.search(
        r"void OnChartEvent\(.*?\n\s*\}\n\nint OnInit",
        source,
        flags=re.DOTALL,
    )
    assert chart_event
    body = chart_event.group(0)
    assert "GuiRememberObjectClick(lparam, (long)dparam)" in body
    assert "GuiShouldSkipChartClick(lparam, (long)dparam)" in body
    assert body.index("GuiRememberObjectClick(lparam, (long)dparam)") < body.index(
        "if(id == CHARTEVENT_CLICK)"
    )


def test_mt5_gui_declares_all_requested_editable_dropdown_fields():
    source = MT5_SOURCE.read_text(encoding="utf-8")
    keys = [
        "initial_lots", "initial_lots_multiplier",
        "stop_loss_distance_points", "take_profit_distance_points",
        "candle_min_range_points", "candle_max_range_points",
        "average_candle_count", "average_stop_multiplier",
        "average_take_profit_multiplier",
        "grid_count", "grid_lot_multiplier", "max_reversals",
        "start_time", "end_time",
    ]
    assert "bool GuiIsEditableDropdownKey" in source
    for key in keys:
        assert f'"{key}"' in source
    assert "0.03" in source


def test_mt5_gui_editable_dropdowns_have_requested_common_options():
    source = MT5_SOURCE.read_text(encoding="utf-8")
    for value in ["0.01", "0.02", "0.03", "0.04", "0.05", "0.1", "0.2", "0.3", "0.4", "0.5"]:
        assert value in source
    for value in ["1.2", "1.3", "1.5", "2.0", "1500", "5.0"]:
        assert value in source
    assert "for(int hour = 0; hour < 24; hour++)" in source
    assert 'StringFormat("%02d:00", hour)' in source
    assert "int GuiDropdownOptionColumns" in source
    assert "return 2;" in source


def test_mt5_gui_editable_dropdown_uses_large_dedicated_arrow():
    source = MT5_SOURCE.read_text(encoding="utf-8")
    assert "GUI_DROPDOWN_ARROW_WIDTH" in source
    assert "bool GuiCreateDropdownArrow" in source
    assert "GUI_DROPDOWN_ARROW_FONT_SIZE = 30" in source
    assert "GuiCreateDropdownArrow" in source


def test_mt5_gui_all_dropdowns_use_the_same_large_arrow():
    source = MT5_SOURCE.read_text(encoding="utf-8")
    dropdown = re.search(
        r"bool GuiRenderDropdownField\(.*?\n\s*\}\n\n"
        r"bool GuiRenderEditableDropdownField",
        source,
        flags=re.DOTALL,
    )
    assert dropdown
    body = dropdown.group(0)
    assert "GuiCreateDropdownArrow" in body
    assert "GUI_DROPDOWN_ARROW_WIDTH" in body
    assert 'value + " ▾"' not in body


def test_mt5_gui_overview_updates_data_in_place_without_rebuilding_panel():
    source = MT5_SOURCE.read_text(encoding="utf-8")
    assert "bool GuiRefreshOverviewData" in source
    refresh = re.search(
        r"\nbool GuiRefreshOverviewData\(\)\n\s*\{.*?\n\s*\}\n\nvoid GuiMarkDirty",
        source,
        flags=re.DOTALL,
    )
    assert refresh
    body = refresh.group(0)
    assert "metric.value.direction" in body
    assert "overview.positions" in body
    assert "overview.profit" in body
    assert "ObjectsDeleteAll" not in body
    render_if_needed = re.search(
        r"void GuiRenderIfNeeded\(\).*?\n\s*\}\n\nvoid GuiMarkDraftChanged",
        source,
        flags=re.DOTALL,
    )
    assert render_if_needed
    body = render_if_needed.group(0)
    assert "GuiRefreshOverviewData" in body


def test_mt5_gui_editable_dropdown_accepts_valid_custom_values_and_rejects_invalid_text():
    source = MT5_SOURCE.read_text(encoding="utf-8")
    assert "bool GuiParseEditableDropdownValue" in source
    assert "GuiParseEditableDropdownValue(key, value" in source
    assert "GuiHandleEditKeyDown" in source
    assert "key_code == 27" in source


def test_mt5_gui_panel_fits_compact_chart_viewport():
    source = MT5_SOURCE.read_text(encoding="utf-8")
    assert "GUI_WINDOW_WIDTH = 760" in source
    assert "GUI_WINDOW_HEIGHT = 640" in source
    assert "GUI_NAV_WIDTH = 178" in source
    assert "GUI_CONTENT_WIDTH = 560" in source


def test_mt5_gui_keeps_edit_session_alive_until_text_edit_ends():
    source = MT5_SOURCE.read_text(encoding="utf-8")
    assert 'g_gui_edit_key' in source
    assert "bool GuiSyncEditValue" in source
    chart_event = re.search(
        r"void OnChartEvent\(.*?\n\s*\}\n\nint OnInit",
        source,
        flags=re.DOTALL,
    )

    assert chart_event
    body = chart_event.group(0)
    assert "id == CHARTEVENT_KEYDOWN" in body
    assert "GuiSyncEditValue(g_gui_edit_key)" in body


def test_mt5_gui_temporarily_hides_chart_trade_overlays_and_restores_them():
    source = MT5_SOURCE.read_text(encoding="utf-8")
    assert "CHART_SHOW_TRADE_LEVELS" in source
    assert "CHART_SHOW_TRADE_HISTORY" in source
    assert "GuiPrepareChartForWindow" in source
    assert "GuiRestoreChartAfterWindow" in source
    assert "GuiSetChartOverlayProperty(CHART_SHOW_TRADE_LEVELS, false)" in source
    assert "GuiSetChartOverlayProperty(CHART_SHOW_TRADE_HISTORY, false)" in source


def test_mt5_gui_chart_overlay_state_is_prepared_and_restored_with_lifecycle():
    source = MT5_SOURCE.read_text(encoding="utf-8")
    create = re.search(
        r"bool GuiCreate\(\)\n\s*\{.*?\n\s*\}\n\nvoid GuiDestroy",
        source,
        flags=re.DOTALL,
    )
    destroy = re.search(
        r"void GuiDestroy\(\)\n\s*\{.*?\n\s*\}\n\nvoid OnChartEvent",
        source,
        flags=re.DOTALL,
    )

    assert create and destroy
    assert "GuiPrepareChartForWindow" in create.group(0)
    assert "GuiRestoreChartAfterWindow" in destroy.group(0)


def test_mt5_gui_uses_dark_terminal_palette_and_readable_controls():
    source = MT5_SOURCE.read_text(encoding="utf-8")
    assert "color GuiColorPanel()" in source
    assert "color GuiColorSurface()" in source
    assert "color GuiColorInput()" in source
    assert "color GuiColorPrimary()" in source
    assert "color GuiColorDanger()" in source
    assert "OBJPROP_FONTSIZE, 10" in source
    assert "GuiColorInput()" in source
    assert "GuiColorPrimary()" in source
    assert "GuiColorDanger()" in source


def test_mt5_gui_has_terminal_header_context_and_overview_summary():
    source = MT5_SOURCE.read_text(encoding="utf-8")
    title = re.search(
        r"bool GuiRenderTitleBar\(\)\n\s*\{.*?\n\s*\}\n\n"
        r"bool GuiRenderNavigation",
        source,
        flags=re.DOTALL,
    )
    overview = re.search(
        r"bool GuiRenderContent\(\).*?\n\s*\}\n\s*bool GuiRenderActions",
        source,
        flags=re.DOTALL,
    )
    assert title and overview
    assert "GuiSymbolPeriodText()" in title.group(0)
    for key in (
        "overview.state", "overview.direction", "overview.positions",
        "overview.orders", "overview.profit", "overview.reversal",
        "overview.cycle_mode", "overview.distance_mode",
        "overview.initial_lots", "overview.grid_count", "overview.stops",
        "overview.schedule",
    ):
        assert key in overview.group(0)


def test_mt5_gui_layout_keeps_panel_and_actions_inside_window():
    source = MT5_SOURCE.read_text(encoding="utf-8")
    assert 'g_gui_object_prefix + "window", 18, 18' in source
    assert 'GUI_WINDOW_WIDTH, GUI_WINDOW_HEIGHT' in source
    assert 'const int y = GUI_WINDOW_HEIGHT - 44' in source
    for action in ("apply", "pause", "close"):
        assert f'GuiCreateButton(g_gui_object_prefix + "{action}"' in source


def test_mt5_gui_uses_dropdowns_for_enum_parameters_and_edits_for_values():
    source = MT5_SOURCE.read_text(encoding="utf-8")
    content = re.search(
        r"bool GuiRenderContent\(\).*?\n\s*\}\n\s*bool GuiRenderActions",
        source,
        flags=re.DOTALL,
    )
    assert content
    body = content.group(0)
    for key in (
        "first_direction", "cycle_mode", "order_type", "candle_order_mode",
        "candle_enable_multiple", "distance_mode", "take_profit_mode",
    ):
        assert f'GuiRenderEnumField("{key}"' in body
    for key in (
        "initial_lots", "initial_lots_multiplier", "grid_count",
        "grid_lot_multiplier", "max_reversals", "magic_number", "order_comment",
    ):
        renderer = "GuiRenderEditField" if key in ("magic_number", "order_comment") \
            else "GuiRenderEditableDropdownField"
        assert f'{renderer}("{key}"' in body


def test_mt5_gui_keeps_dropdowns_and_edits_above_chart_objects():
    source = MT5_SOURCE.read_text(encoding="utf-8")
    assert "ObjectSetInteger(0, name, OBJPROP_ZORDER, 1000);" in source
    assert "ObjectSetInteger(0, name, OBJPROP_ZORDER, 2000);" in source
    assert "CHART_SHOW_TRADE_LEVELS" in source
    assert "CHART_SHOW_TRADE_HISTORY" in source


def test_mt5_gui_text_layers_are_above_panels():
    source = MT5_SOURCE.read_text(encoding="utf-8")
    panel = re.search(
        r"bool GuiCreatePanel\(.*?\n\s*\}\n\nbool GuiCreateText",
        source,
        flags=re.DOTALL,
    )
    text = re.search(
        r"bool GuiCreateText\(.*?\n\s*\}\n\nbool GuiCreateButton",
        source,
        flags=re.DOTALL,
    )
    assert panel and text
    assert "OBJPROP_ZORDER, 10" in panel.group(0)
    assert "OBJPROP_ZORDER, 500" in text.group(0)


def test_mt5_gui_does_not_render_default_label_for_clean_dirty_status():
    source = MT5_SOURCE.read_text(encoding="utf-8")
    title = re.search(
        r"bool GuiRenderTitleBar\(\)\n\s*\{.*?\n\s*\}\n\n"
        r"bool GuiRenderNavigation",
        source,
        flags=re.DOTALL,
    )
    assert title
    assert 'g_gui_has_unapplied_changes ? "· 未应用" : " "' in title.group(0)


def test_mt5_gui_matches_browser_shell_geometry():
    source = MT5_SOURCE.read_text(encoding="utf-8")
    title = re.search(
        r"bool GuiRenderTitleBar\(\)\n\s*\{.*?\n\s*\}\n\n"
        r"bool GuiRenderNavigation",
        source,
        flags=re.DOTALL,
    )
    navigation = re.search(
        r"bool GuiRenderNavigation\(\)\n\s*\{.*?\n\s*\}\n\n"
        r"bool GuiRenderCloseConfirmation",
        source,
        flags=re.DOTALL,
    )
    content = re.search(
        r"bool GuiRenderContent\(\)\n\s*\{.*?\n\s*\}\n\n"
        r"bool GuiRenderActions",
        source,
        flags=re.DOTALL,
    )
    assert title and navigation and content
    assert 'GUI_WINDOW_WIDTH' in title.group(0)
    assert 'GUI_NAV_WIDTH' in navigation.group(0)
    assert 'GUI_CONTENT_WIDTH' in content.group(0)
    assert 'const int GUI_CONTENT_X = GUI_NAV_WIDTH + 18' in source


def test_mt5_gui_overview_contains_browser_summary_fields():
    source = MT5_SOURCE.read_text(encoding="utf-8")
    overview = re.search(
        r"if\(g_gui_page == GUI_PAGE_OVERVIEW\).*?\n\s*\}\n\s*else if\(g_gui_page == GUI_PAGE_OPENING\)",
        source,
        flags=re.DOTALL,
    )
    assert overview
    body = overview.group(0)
    for key in (
        "overview.order_group", "overview.cycle",
        "overview.initial_lots_multiplier", "overview.grid_lot_multiplier",
        "overview.take_profit_mode", "overview.magic_number",
        "overview.order_comment",
    ):
        assert f'"{key}"' in body, f"Browser-parity overview is missing {key}"


def test_mt5_gui_rejects_invalid_numeric_edits_without_coercing_to_zero():
    source = MT5_SOURCE.read_text(encoding="utf-8")
    assert "bool GuiTryParseDouble" in source
    assert "bool GuiTryParseInteger" in source
    sync = re.search(
        r"bool GuiSyncEditValue\(.*?\n\s*\}\n\nbool GuiHandleEditEnd",
        source,
        flags=re.DOTALL,
    )
    assert sync
    assert "GuiTryParseDouble" in sync.group(0)
    assert "GuiTryParseInteger" in sync.group(0)
    assert "g_gui_notice" in sync.group(0)


def test_mt5_gui_preserves_active_edit_control_during_redraw():
    source = MT5_SOURCE.read_text(encoding="utf-8")
    render = re.search(
        r"bool GuiRender\(\)\n\s*\{.*?\n\s*\}\n\nvoid GuiRenderIfNeeded",
        source,
        flags=re.DOTALL,
    )
    assert render
    body = render.group(0)
    assert "GuiRenderActiveEdit" in body
    assert "g_gui_edit_key" in source


def test_mt5_gui_surfaces_chart_overlay_preparation_failure():
    source = MT5_SOURCE.read_text(encoding="utf-8")
    create = re.search(
        r"bool GuiCreate\(\)\n\s*\{.*?\n\s*\}\n\nvoid GuiDestroy",
        source,
        flags=re.DOTALL,
    )
    prepare = re.search(
        r"bool GuiPrepareChartForWindow\(\)\n\s*\{.*?\n\s*\}\n\nvoid GuiRestoreChartAfterWindow",
        source,
        flags=re.DOTALL,
    )
    assert create and prepare
    assert "if(!GuiPrepareChartForWindow())" in create.group(0)
    assert "GuiSetChartOverlayProperty" in prepare.group(0)
    assert "GetLastError" in prepare.group(0)
    assert "GuiSetChartOverlayProperty" in prepare.group(0)
    assert "GuiRestoreChartAfterWindow" in prepare.group(0)


def test_mt5_gui_rejects_integer_overflow_and_keeps_magic_number_wide():
    source = MT5_SOURCE.read_text(encoding="utf-8")
    assert "bool GuiTryParseLong" in source
    sync = re.search(
        r"bool GuiSyncEditValue\(.*?\n\s*\}\n\nbool GuiHandleEditEnd",
        source,
        flags=re.DOTALL,
    )
    assert sync
    body = sync.group(0)
    assert "GuiTryParseLong(value, parsed_long)" in body
    assert "g_gui_draft_config.magic_number" in body
    assert "INT_MAX" in source or "2147483647" in source


def test_mt5_gui_blocks_navigation_while_active_edit_is_invalid():
    source = MT5_SOURCE.read_text(encoding="utf-8")
    chart_event = re.search(
        r"void OnChartEvent\(.*?\n\s*\}\n\nint OnInit",
        source,
        flags=re.DOTALL,
    )
    assert chart_event
    body = chart_event.group(0)
    assert "GuiLeaveEditSession" in body
    assert body.index("GuiLeaveEditSession") < body.index("g_gui_edit_key = \"\";")


def test_mt5_gui_object_prefix_is_bounded_for_mql5_object_names():
    source = MT5_SOURCE.read_text(encoding="utf-8")
    prefix = re.search(
        r"string GuiObjectPrefix\(\)\n\s*\{.*?\n\s*\}",
        source,
        flags=re.DOTALL,
    )
    assert prefix
    body = prefix.group(0)
    assert "StringSubstr" in body
    assert "% 1000000" in body


def test_mt5_gui_rebuilds_object_prefix_after_magic_number_change():
    source = MT5_SOURCE.read_text(encoding="utf-8")
    apply_start = source.index("bool ApplyGuiConfig")
    apply_end = source.index("GuiConfig LoadConfigFromInputs", apply_start)
    apply = source[apply_start:apply_end]
    assert "g_gui_object_prefix" in apply
    assert "GuiObjectPrefix()" in apply


def test_mt5_gui_object_prefix_stays_short_for_mql5_object_names():
    source = MT5_SOURCE.read_text(encoding="utf-8")
    prefix = re.search(
        r"string GuiObjectPrefix\(\)\n\s*\{.*?\n\s*\}",
        source,
        flags=re.DOTALL,
    )
    assert prefix
    assert 'return "NMR.g."' in prefix.group(0)
    assert "ObjectsDeleteAll(0, legacy_prefix)" in source


def test_cycle_templates_cover_both_modes_and_first_directions():
    assert cycle_directions(Direction.BUY, CycleMode.MODE_1) == [
        Direction.BUY, Direction.SELL, Direction.SELL,
        Direction.BUY, Direction.SELL, Direction.SELL,
    ]
    assert cycle_directions(Direction.SELL, CycleMode.MODE_1) == [
        Direction.SELL, Direction.BUY, Direction.BUY,
        Direction.SELL, Direction.BUY, Direction.BUY,
    ]
    assert cycle_directions(Direction.BUY, CycleMode.MODE_2) == [
        Direction.BUY, Direction.SELL, Direction.BUY,
        Direction.SELL, Direction.BUY, Direction.BUY,
    ]
    assert cycle_directions(Direction.SELL, CycleMode.MODE_2) == [
        Direction.SELL, Direction.BUY, Direction.SELL,
        Direction.BUY, Direction.SELL, Direction.SELL,
    ]
    assert cycle_directions(Direction.BUY, CycleMode.MODE_3) == [
        Direction.BUY, Direction.SELL, Direction.BUY,
        Direction.BUY, Direction.SELL, Direction.BUY,
    ]
    assert cycle_directions(Direction.SELL, CycleMode.MODE_3) == [
        Direction.SELL, Direction.BUY, Direction.SELL,
        Direction.SELL, Direction.BUY, Direction.SELL,
    ]
    assert cycle_directions(Direction.BUY, CycleMode.MODE_4) == [
        Direction.BUY, Direction.SELL, Direction.SELL, Direction.BUY,
        Direction.BUY, Direction.SELL, Direction.SELL,
    ]
    assert cycle_directions(Direction.SELL, CycleMode.MODE_4) == [
        Direction.SELL, Direction.BUY, Direction.BUY, Direction.SELL,
        Direction.SELL, Direction.BUY, Direction.BUY,
    ]


@pytest.mark.parametrize("source_name", ["NoMatterRiseFall_MT5.mq5", "NoMatterRiseFall_MT4.mq4"])
def test_cycle_mode_four_uses_a_seven_order_cycle_in_both_experts(source_name):
    source = (Path(__file__).parents[1] / source_name).read_text(encoding="utf-8")

    assert "CYCLE_MODE_4" in source
    assert "首单多=多空空多多空空" in source
    assert "首单空=空多多空空多多" in source
    assert "CycleLength" in source


def test_mode_one_buy_uses_sell_stop_then_sell_limit_for_the_two_sell_steps():
    model = StrategyModel(
        Direction.BUY, CycleMode.MODE_1, 0.01, 2.0, 500, 0.0001,
        first_order_lot_type=1,
    )

    first_actions = model.on_tick(bid=1.1000, ask=1.1002)
    second_actions = model.on_tick(bid=1.0502, ask=1.0504)

    assert first_actions[0] == {"kind": "market", "direction": Direction.BUY, "lots": 0.01}
    assert first_actions[1] == {
        "kind": "pending", "direction": Direction.SELL, "lots": 0.01,
        "price": 1.0502, "order_type": "SELL_STOP",
    }
    assert second_actions[0] == {"kind": "delete_pending"}
    assert second_actions[1] == {"kind": "close", "direction": Direction.BUY}
    assert second_actions[2] == {"kind": "market", "direction": Direction.SELL, "lots": 0.01}
    assert second_actions[3] == {
        "kind": "pending", "direction": Direction.SELL, "lots": 0.02,
        "price": 1.1002, "order_type": "SELL_LIMIT",
    }


def test_stop_deletes_unfilled_reverse_pending_before_market_reversal():
    model = StrategyModel(Direction.BUY, CycleMode.MODE_1, 0.01, 2.0, 500, 0.0001)
    model.on_tick(bid=1.1000, ask=1.1002)

    stop_actions = model.on_tick(
        bid=model.position.stop_loss,
        ask=model.position.stop_loss + 0.0002,
    )

    assert stop_actions[0] == {"kind": "delete_pending"}
    assert stop_actions[1] == {"kind": "close", "direction": Direction.BUY}
    assert stop_actions[2]["kind"] == "market"


def test_mode_two_buy_reaches_buy_buy_and_wraps_after_six_orders():
    model = StrategyModel(
        Direction.BUY, CycleMode.MODE_2, 0.01, 2.0, 500, 0.0001,
        max_reversals=6,
    )
    directions = []

    actions = model.on_tick(bid=1.1000, ask=1.1002)
    directions.append(actions[0]["direction"])
    for _ in range(5):
        position = model.position
        if position.direction is Direction.BUY:
            bid, ask = position.stop_loss, position.stop_loss + 0.0002
        else:
            bid, ask = position.stop_loss - 0.0002, position.stop_loss
        actions = model.on_tick(bid=bid, ask=ask)
        directions.append(actions[2]["direction"])

    assert directions == [
        Direction.BUY, Direction.SELL, Direction.BUY,
        Direction.SELL, Direction.BUY, Direction.BUY,
    ]
    assert model.current_index == 5

    position = model.position
    actions = model.on_tick(bid=position.stop_loss, ask=position.stop_loss + 0.0002)
    assert actions[2]["direction"] == Direction.BUY
    assert model.current_index == 0


def test_grid_multiplier_is_applied_to_the_next_group_grid_lot():
    model = StrategyModel(Direction.SELL, CycleMode.MODE_1, 0.03, 3.0, 500, 0.0001,
                          grid_count=2, first_order_lot_type=1)

    first_actions = model.on_tick(bid=1.1000, ask=1.1002)
    model.on_tick(bid=1.1250, ask=1.1252)
    model.fill_grid_pending()
    next_actions = model.on_tick(bid=1.1500, ask=1.1502)

    assert first_actions[1]["lots"] == 0.03
    assert next_actions[2]["lots"] == pytest.approx(0.06)
    assert model.grid_lots == pytest.approx(0.09)


def test_only_a_post_stop_group_uses_the_initial_lot_multiplier():
    model = StrategyModel(
        Direction.BUY, CycleMode.MODE_1, 0.01, 2.0, 500, 0.0001,
        grid_count=2, initial_lot_multiplier=1.5, first_order_lot_type=1,
    )

    first_actions = model.on_tick(bid=1.1000, ask=1.1002)

    assert first_actions[0] == {
        "kind": "market", "direction": Direction.BUY, "lots": pytest.approx(0.01),
    }
    assert first_actions[1]["lots"] == pytest.approx(0.015)

    first_stop = model.position.stop_loss
    next_actions = model.on_tick(bid=first_stop, ask=first_stop + 0.0002)

    assert next_actions[2] == {
        "kind": "market", "direction": Direction.SELL, "lots": pytest.approx(0.015),
    }


def test_type_two_uses_previous_group_first_lot_after_grid_loss():
    model = StrategyModel(
        Direction.BUY, CycleMode.MODE_1, 0.01, 2.0, 500, 0.0001,
        grid_count=2, first_order_lot_type=2, first_order_mult=2.0,
    )

    initial_actions = model.on_tick(bid=1.1000, ask=1.1002)
    assert initial_actions[1]["lots"] == pytest.approx(0.02)
    model.fill_grid_pending()
    stop_actions = model.on_tick(
        bid=model.position.stop_loss,
        ask=model.position.stop_loss + 0.0002,
    )

    assert stop_actions[2] == {
        "kind": "market", "direction": Direction.SELL, "lots": pytest.approx(0.02),
    }


def test_default_first_order_lot_type_uses_previous_group_first_lot():
    model = StrategyModel(
        Direction.BUY, CycleMode.MODE_1, 0.01, 2.0, 500, 0.0001,
        grid_count=2,
    )

    model.on_tick(bid=1.1000, ask=1.1002)
    model.fill_grid_pending()
    stop_actions = model.on_tick(
        bid=model.position.stop_loss,
        ask=model.position.stop_loss + 0.0002,
    )

    assert stop_actions[2]["lots"] == pytest.approx(0.02)


@pytest.mark.parametrize("previous_first", [0.16, 0.32])
def test_type_two_grid_lot_recovers_to_first_lot_after_state_divergence(previous_first):
    model = StrategyModel(
        Direction.BUY, CycleMode.MODE_1, 0.01, 2.0, 500, 0.0001,
        grid_count=4, first_order_lot_type=2, first_order_mult=2.0,
    )
    model.on_tick(bid=1.1000, ask=1.1002)
    model.group_first_lots = previous_first
    model.grid_lots = previous_first * 2
    stop = model.position.stop_loss

    model.on_tick(bid=stop, ask=stop + 0.0002)

    assert model.group_first_lots == pytest.approx(previous_first * 2)
    assert model.grid_lots == pytest.approx(previous_first * 2)
    assert model.grid_pendings
    assert all(pending.lots == pytest.approx(previous_first * 2)
               for pending in model.grid_pendings.values())


@pytest.mark.parametrize("source_name", ["NoMatterRiseFall_MT4.mq4", "NoMatterRiseFall_MT5.mq5"])
def test_type_two_equal_multipliers_synchronize_grid_and_first_lots(source_name):
    source = (Path(__file__).parents[1] / source_name).read_text(encoding="utf-8")
    assert "double GridLotsForNewGroup(" in source
    assert "double MultiGridLotsForNewGroup(" in source
    assert "g_grid_lots = GridLotsForNewGroup(" in source
    assert "group.grid_lots = MultiGridLotsForNewGroup(" in source
    initial_fill = source.split("g_group_anchor_price = entry;", 1)[1].split(
        "g_group_total_lots =", 1,
    )[0]
    assert "g_group_first_lots = volume;" in initial_fill


@pytest.mark.parametrize("source_name", ["NoMatterRiseFall_MT4.mq4", "NoMatterRiseFall_MT5.mq5"])
def test_reverse_pending_fill_cancels_old_grid_pendings_before_promotion(source_name):
    source = (Path(__file__).parents[1] / source_name).read_text(encoding="utf-8")
    single = source.split("if(pending_filled)\n", 1)[1].split(
        "ClosePreviousGroupAfterReverseFill(position_ticket)", 1,
    )[0]
    multi = source.split("MultiHandleReverseFill(", 1)[1].split(
        "MultiClosePositionsExcept(group.id, filled_ticket)", 1,
    )[0]

    assert "DeleteAllPending()" in single
    assert "MultiDeletePending(group.id)" in multi


@pytest.mark.parametrize("source_name", ["NoMatterRiseFall_MT4.mq4", "NoMatterRiseFall_MT5.mq5"])
def test_filled_grid_position_prevents_same_level_from_being_recreated(source_name):
    source = (Path(__file__).parents[1] / source_name).read_text(encoding="utf-8")
    single = source.split("bool FindFilledGridOrder(", 1)[1].split(
        "bool PlaceGridPending(", 1,
    )[0]
    multi = source.split("bool MultiFindFilledGridOrder(", 1)[1].split(
        "bool MultiPlaceGridPending(", 1,
    )[0]
    assert "FindFilledGridPosition(" in single
    assert "MultiFindFilledGridPosition(" in multi
    single_fill = source.split("bool HandleGridFill(", 1)[1].split(
        "void EnsureGridPending(", 1,
    )[0]
    multi_fill = source.split("void MultiHandleGridFill(", 1)[1].split(
        "bool MultiHandleReverseFill(", 1,
    )[0] if source_name.endswith("mq4") else source.split(
        "bool MultiHandleGridFill(", 1,
    )[1].split("bool MultiHandleReverseFill(", 1)[0]
    assert "current_total_lots <= previous_total_lots" not in single_fill
    assert "current_total <= group.total_lots" not in multi_fill


def test_type_two_uses_immediately_previous_group_first_lot_on_consecutive_stops():
    model = StrategyModel(
        Direction.BUY, CycleMode.MODE_1, 0.01, 2.0, 500, 0.0001,
        grid_count=2, first_order_lot_type=2, first_order_mult=2.0,
    )

    model.on_tick(bid=1.1000, ask=1.1002)
    first_stop = model.position.stop_loss
    second_group = model.on_tick(bid=first_stop, ask=first_stop + 0.0002)
    assert second_group[2]["lots"] == pytest.approx(0.02)

    second_stop = model.position.stop_loss
    third_group = model.on_tick(bid=second_stop - 0.0002, ask=second_stop)
    assert third_group[2]["lots"] == pytest.approx(0.04)


def test_type_one_preserves_accumulated_group_total_formula():
    model = StrategyModel(
        Direction.BUY, CycleMode.MODE_1, 0.01, 2.0, 500, 0.0001,
        grid_count=2, initial_lot_multiplier=1.0,
        first_order_lot_type=1, first_order_mult=2.0,
    )

    model.on_tick(bid=1.1000, ask=1.1002)
    model.fill_grid_pending()
    stop_actions = model.on_tick(
        bid=model.position.stop_loss,
        ask=model.position.stop_loss + 0.0002,
    )

    assert stop_actions[2]["lots"] == pytest.approx(0.02)


def test_type_three_uses_configured_fixed_lot_after_each_stop_but_not_for_first_group():
    model = StrategyModel(
        Direction.BUY, CycleMode.MODE_1, 0.01, 2.0, 500, 0.0001,
        grid_count=2, initial_lot_multiplier=3.0,
        first_order_lot_type=3, first_order_mult=4.0,
        stop_first_order_lots=0.037,
    )

    initial_actions = model.on_tick(bid=1.1000, ask=1.1002)
    assert initial_actions[0]["lots"] == pytest.approx(0.01)
    assert initial_actions[1]["lots"] == pytest.approx(0.037)

    first_stop = model.position.stop_loss
    second_group = model.on_tick(bid=first_stop, ask=first_stop + 0.0002)
    assert second_group[2]["lots"] == pytest.approx(0.037)

    second_stop = model.position.stop_loss
    third_group = model.on_tick(bid=second_stop - 0.0002, ask=second_stop)
    assert third_group[2]["lots"] == pytest.approx(0.037)


@pytest.mark.parametrize("source_name", ["NoMatterRiseFall_MT4.mq4", "NoMatterRiseFall_MT5.mq5"])
def test_fixed_stop_first_order_lots_parameter_exists_in_both_expert_sources(source_name):
    source = (Path(__file__).parents[1] / source_name).read_text(encoding="utf-8")

    assert "input double         止损首单固定手数 = 0.01;" in source
    assert "FirstOrderLotType == 3" in source or "first_order_lot_type == 3" in source
    assert "NextGroupLotsAfterStopRaw" in source


def test_mt5_gui_exposes_fixed_stop_first_order_lots_and_type_three():
    source = (Path(__file__).parents[1] / "NoMatterRiseFall_MT5.mq5").read_text(
        encoding="utf-8",
    )

    assert 'key == "stop_first_order_lots"' in source
    assert 'index == 2) return "固定手数"' in source
    assert 'config.stop_first_order_lots = 止损首单固定手数;' in source


@pytest.mark.parametrize("source_name", ["NoMatterRiseFall_MT4.mq4", "NoMatterRiseFall_MT5.mq5"])
def test_first_order_lot_type_is_present_in_both_expert_sources(source_name):
    source = (Path(__file__).parents[1] / source_name).read_text(encoding="utf-8")

    assert "FirstOrderLotType" in source
    assert "FirstOrderMult" in source
    assert "first_order_lots" in source or "group_first_lots" in source
    assert "input int            止损首单类型 = 2;" in source
    assert "input double         首单类型2倍数 = 2.0;" in source
    assert "== 2" in source


@pytest.mark.parametrize("source_name", ["NoMatterRiseFall_MT5.mq5", "NoMatterRiseFall_MT4.mq4"])
def test_reversal_volume_is_classified_before_broker_max_lot_clamping(source_name):
    source = (Path(__file__).parents[1] / source_name).read_text(encoding="utf-8")

    assert "MAX_SINGLE_REVERSAL_LOTS" in source
    assert "MAX_GROUP_REVERSAL_LOTS" in source
    assert "ReversalLotPlan" in source
    assert ">= MAX_GROUP_REVERSAL_LOTS" in source
    assert "<= MAX_SINGLE_REVERSAL_LOTS" in source
    assert "requested_volume" in source


@pytest.mark.parametrize("source_name", ["NoMatterRiseFall_MT5.mq5", "NoMatterRiseFall_MT4.mq4"])
def test_follow_up_orders_are_blocked_until_position_protection_is_verified(source_name):
    source = (Path(__file__).parents[1] / source_name).read_text(encoding="utf-8")

    assert "bool SetGroupStops" in source
    assert "StopsVerified" in source
    assert "if(!SetGroupStops" in source or "if(!MultiSetStops" in source
    assert "protection is not verified" in source


@pytest.mark.parametrize("source_name", ["NoMatterRiseFall_MT5.mq5", "NoMatterRiseFall_MT4.mq4"])
def test_oversized_reversal_resets_only_the_current_order_group(source_name):
    source = (Path(__file__).parents[1] / source_name).read_text(encoding="utf-8")

    assert "ResetOrderGroupAfterOversizedReversal" in source
    assert "start a fresh base-lot group on the next tick" in source
    assert "NextGroupLotsRaw" in source


def test_initial_entry_is_allowed_only_inside_the_configured_time_window():
    model = StrategyModel(
        Direction.BUY, CycleMode.MODE_1, 0.01, 2.0, 500, 0.0001,
        start_minute=8 * 60, end_minute=23 * 60,
    )

    assert model.on_tick(bid=1.1000, ask=1.1002, now_minute=7 * 60 + 59) == []
    actions = model.on_tick(bid=1.1000, ask=1.1002, now_minute=8 * 60)

    assert actions[0] == {
        "kind": "market", "direction": Direction.BUY, "lots": pytest.approx(0.01),
    }


@pytest.mark.parametrize(
    ("spread_points", "maximum_points", "expected"),
    [
        (0, 0, True),
        (25, 0, True),
        (24, 25, True),
        (25, 25, True),
        (26, 25, False),
        (-1, 25, False),
        (1, -1, False),
    ],
)
def test_initial_spread_threshold_is_optional_and_inclusive(
    spread_points, maximum_points, expected
):
    assert strategy_logic.is_initial_spread_allowed(
        spread_points, maximum_points
    ) is expected


@pytest.mark.parametrize(
    ("has_pending", "signal_valid", "spread_points", "maximum_points", "expected"),
    [
        (False, True, 26, 25, "wait"),
        (False, True, 25, 25, "place"),
        (True, True, 26, 25, "cancel"),
        (True, True, 25, 25, "keep"),
        (False, False, 10, 25, "wait"),
    ],
)
def test_initial_pending_is_canceled_and_recreated_according_to_spread(
    has_pending, signal_valid, spread_points, maximum_points, expected
):
    assert strategy_logic.initial_pending_spread_action(
        has_pending, signal_valid, spread_points, maximum_points
    ) == expected


@pytest.mark.parametrize("source_name", ["NoMatterRiseFall_MT4.mq4", "NoMatterRiseFall_MT5.mq5"])
def test_spread_filter_is_limited_to_initial_entries(source_name):
    source = (Path(__file__).parents[1] / source_name).read_text(encoding="utf-8")
    assert re.search(r"input\s+int\s+最大首单点差\s*=\s*0\s*;", source)
    assert "bool IsInitialSpreadAllowed()" in source
    assert "CancelInitialPendingPairIfSpreadTooHigh" in source
    assert "CancelInitialPendingPairIfSpreadTooHigh()" in source


@pytest.mark.parametrize("source_name", ["NoMatterRiseFall_MT4.mq4", "NoMatterRiseFall_MT5.mq5"])
def test_initial_market_and_candle_pending_entries_check_spread(source_name):
    source = (Path(__file__).parents[1] / source_name).read_text(encoding="utf-8")
    market_entry = source.split("void Manage()", 1)[1]
    market_entry = market_entry.split("struct MultiGroupState", 1)[0]
    multi_entry = source.split("bool MultiTryOpenCandleGroup()", 1)[1]
    assert "IsInitialSpreadAllowed()" in market_entry
    assert "IsInitialSpreadAllowed()" in multi_entry
    initial_pair = source.split("bool PlaceInitialPendingPair(", 1)[1]
    assert "IsInitialSpreadAllowed()" in initial_pair.split("int InitialPendingStatus", 1)[0]


@pytest.mark.parametrize("source_name", ["NoMatterRiseFall_MT4.mq4", "NoMatterRiseFall_MT5.mq5"])
def test_pending_spread_cleanup_targets_only_initial_pending_orders(source_name):
    source = (Path(__file__).parents[1] / source_name).read_text(encoding="utf-8")
    cleanup = source.split("bool CancelInitialPendingPairIfSpreadTooHigh()", 1)[1]
    cleanup = cleanup.split("\n  }", 1)[0]
    assert "IsInitialPendingComment" in cleanup
    assert "IsInitialSpreadAllowed()" in cleanup
    assert "deletion_failed" in cleanup

    multi_handler = source.split("bool MultiHandleInitialPendingFill(", 1)[1]
    multi_handler = multi_handler.split("bool MultiNormalizeReversePending(", 1)[0]
    assert "IsInitialSpreadAllowed()" in multi_handler
    assert "MultiPlaceInitialPendingPair" in multi_handler
    assert "initial_high_price" in multi_handler
    assert "initial_low_price" in multi_handler
    assert "OrderDelete" in multi_handler or "DeletePendingTicket" in multi_handler


@pytest.mark.parametrize("source_name", ["NoMatterRiseFall_MT4.mq4", "NoMatterRiseFall_MT5.mq5"])
def test_spread_filter_uses_latest_quote_in_integer_points(source_name):
    source = (Path(__file__).parents[1] / source_name).read_text(encoding="utf-8")
    body = source.split("bool IsInitialSpreadAllowed()", 1)[1].split("\n  }", 1)[0]
    assert "最大首单点差 == 0" in body
    assert "MathCeil" in body
    assert re.search(r"spread_points\s*<=\s*\(double\)最大首单点差", body)
    if source_name.endswith("MT5.mq5"):
        assert "SymbolInfoTick(_Symbol, tick)" in body
        assert "tick.ask - tick.bid" in body
    else:
        assert "RefreshRates()" in body
        assert "Ask - Bid" in body


@pytest.mark.parametrize("source_name", ["NoMatterRiseFall_MT4.mq4", "NoMatterRiseFall_MT5.mq5"])
def test_spread_parameter_rejects_negative_values(source_name):
    source = (Path(__file__).parents[1] / source_name).read_text(encoding="utf-8")
    assert "最大首单点差 < 0" in source


@pytest.mark.parametrize("source_name", ["NoMatterRiseFall_MT4.mq4", "NoMatterRiseFall_MT5.mq5"])
def test_spread_filter_does_not_change_reversal_or_grid_orders(source_name):
    source = (Path(__file__).parents[1] / source_name).read_text(encoding="utf-8")
    grid_end_marker = (
        "bool PrepareGridPendingForCurrentStop("
        if source_name.endswith("MT4.mq4")
        else "void LogSingleTradeEvent("
    )
    for signature, end_marker in (
        ("bool OpenMarket(", "double NextGroupLotsRaw("),
        ("bool PlaceNextPending(", "bool StopReached("),
        ("bool PlaceGridPending(", grid_end_marker),
        ("bool MultiOpenMarket(", "bool MultiPlaceInitialPendingPair("),
    ):
        if signature not in source:
            continue
        body = source.split(signature, 1)[1].split(end_marker, 1)[0]
        assert "IsInitialSpreadAllowed()" not in body


@pytest.mark.parametrize("source_name", ["NoMatterRiseFall_MT4.mq4", "NoMatterRiseFall_MT5.mq5"])
def test_spread_filter_is_limited_to_initial_entries(source_name):
    source = (Path(__file__).parents[1] / source_name).read_text(encoding="utf-8")
    assert re.search(r"input\s+int\s+最大首单点差\s*=\s*0\s*;", source)
    assert "bool IsInitialSpreadAllowed()" in source
    assert "CancelInitialPendingPairIfSpreadTooHigh" in source
    assert "CancelInitialPendingPairIfSpreadTooHigh()" in source

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
    evening_model = StrategyModel(
        Direction.BUY, CycleMode.MODE_1, 0.01, 2.0, 500, 0.0001,
        operation_windows=[(22 * 60, 2 * 60), (0, 0), (0, 0)],
    )
    morning_model = StrategyModel(
        Direction.BUY, CycleMode.MODE_1, 0.01, 2.0, 500, 0.0001,
        operation_windows=[(22 * 60, 2 * 60), (0, 0), (0, 0)],
    )

    assert evening_model.on_tick(1.1000, 1.1002, now_minute=23 * 60)
    assert morning_model.on_tick(1.1000, 1.1002, now_minute=1 * 60)


@pytest.mark.parametrize("source_name", ["NoMatterRiseFall_MT4.mq4", "NoMatterRiseFall_MT5.mq5"])
def test_initial_market_and_candle_pending_entries_check_spread(source_name):
    source = (Path(__file__).parents[1] / source_name).read_text(encoding="utf-8")
    market_entry = source.split("void Manage()", 1)[1]
    market_entry = market_entry.split("struct MultiGroupState", 1)[0]
    multi_entry = source.split("bool MultiTryOpenCandleGroup()", 1)[1]
    assert "IsInitialSpreadAllowed()" in market_entry
    assert "IsInitialSpreadAllowed()" in multi_entry
    initial_pair = source.split("bool PlaceInitialPendingPair(", 1)[1]
    assert "IsInitialSpreadAllowed()" in initial_pair.split("int InitialPendingStatus", 1)[0]

def test_existing_position_is_managed_outside_operation_windows():
    model = StrategyModel(
        Direction.BUY, CycleMode.MODE_1, 0.01, 2.0, 500, 0.0001,
        operation_windows=[(8 * 60, 9 * 60), (0, 0), (0, 0)],
    )

    model.on_tick(1.1000, 1.1002, now_minute=8 * 60)
    stop_price = model.position.stop_loss
    actions = model.on_tick(
        bid=stop_price, ask=stop_price + 0.0002, now_minute=12 * 60,
    )

    assert actions[2]["kind"] == "market"


def test_existing_position_can_switch_groups_outside_the_initial_entry_window():
    model = StrategyModel(
        Direction.BUY, CycleMode.MODE_1, 0.01, 2.0, 500, 0.0001,
        start_minute=8 * 60, end_minute=23 * 60,
    )

    model.on_tick(bid=1.1000, ask=1.1002, now_minute=8 * 60)
    stop_price = model.position.stop_loss
    actions = model.on_tick(
        bid=stop_price, ask=stop_price + 0.0002, now_minute=23 * 60 + 30,
    )

    assert actions[2]["kind"] == "market"
    assert actions[2]["direction"] is Direction.SELL


@pytest.mark.parametrize("source_name", ["NoMatterRiseFall_MT4.mq4", "NoMatterRiseFall_MT5.mq5"])
def test_spread_parameter_rejects_negative_values(source_name):
    source = (Path(__file__).parents[1] / source_name).read_text(encoding="utf-8")
    assert "最大首单点差 < 0" in source

@pytest.mark.parametrize("source_name", ["NoMatterRiseFall_MT5.mq5", "NoMatterRiseFall_MT4.mq4"])
def test_expert_advisors_define_three_operation_windows(source_name):
    source = (Path(__file__).parents[1] / source_name).read_text(encoding="utf-8")

    for parameter in ("时段2开始时间", "时段2结束时间", "时段3开始时间", "时段3结束时间"):
        assert f"input string         {parameter}" in source
    assert "MAX_OPERATION_WINDOWS 3" in source
    assert "for(int window = 0; window < MAX_OPERATION_WINDOWS; window++)" in source
    assert "start_minutes == 0 && end_minutes == 0" in source


def test_mt5_gui_exposes_all_three_operation_windows():
    source = MT5_SOURCE.read_text(encoding="utf-8")
    render_content = re.search(
        r"bool GuiRenderContent\(\).*?\n\s*\}\n\nbool GuiRenderActions",
        source,
        flags=re.DOTALL,
    )

    assert render_content
    body = render_content.group(0)
    for key in (
        "start_time", "end_time", "start_time_2", "end_time_2",
        "start_time_3", "end_time_3",
    ):
        assert f'"{key}"' in body
    for label in ("时段1开始时间", "时段1结束时间", "时段2开始时间",
                  "时段2结束时间", "时段3开始时间", "时段3结束时间"):
        assert label in body
    assert "GuiScheduleSummaryText" in source



def test_operation_window_documentation_explains_all_window_rules():
    readme = (Path(__file__).parents[1] / "README.md").read_text(encoding="utf-8")
    manual = (Path(__file__).parents[1] / "EA软件使用手册.html").read_text(encoding="utf-8")

    for document in (readme, manual):
        assert "时段2" in document
        assert "时段3" in document
        assert "00:00-00:00" in document
        assert "跨午夜" in document


def test_first_group_grid_add_uses_initial_lot_and_moves_tp_and_next_group_lot():
    model = StrategyModel(
        Direction.BUY, CycleMode.MODE_1, 0.01, 2.0, 500, 0.0001,
        grid_count=5, first_order_lot_type=1,
    )

    first_actions = model.on_tick(bid=1.1000, ask=1.1002)
    assert first_actions[0]["lots"] == pytest.approx(0.01)
    assert first_actions[1]["lots"] == pytest.approx(0.01)
    assert first_actions[2] == {
        "kind": "grid_pending", "direction": Direction.BUY,
        "lots": 0.01, "price": 1.0902,
        "order_type": "BUY_LIMIT", "level": 1,
    }

    grid_actions = model.fill_grid_pending()

    assert grid_actions[0] == {
        "kind": "grid",
        "direction": Direction.BUY,
        "lots": 0.01,
        "price": 1.0902,
    }
    assert model.position.take_profit == pytest.approx(1.1402)
    assert model.pending.lots == pytest.approx(0.02)
    assert model.grid_pending.level == 2
    assert model.grid_pending.price == pytest.approx(1.0802)
    assert model.grid_pending.lots == pytest.approx(0.01)


def test_grid_count_five_places_all_internal_levels_at_once():
    model = StrategyModel(
        Direction.BUY, CycleMode.MODE_1, 0.01, 2.0, 500, 0.0001,
        grid_count=5, first_order_lot_type=1,
    )

    actions = model.on_tick(bid=1.1000, ask=1.1002)
    grid_actions = [action for action in actions if action["kind"] == "grid_pending"]

    assert [action["level"] for action in grid_actions] == [1, 2, 3, 4]
    assert [action["price"] for action in grid_actions] == [
        pytest.approx(1.0902), pytest.approx(1.0802),
        pytest.approx(1.0702), pytest.approx(1.0602),
    ]
    assert all(action["order_type"] == "BUY_LIMIT" for action in grid_actions)


def test_filling_one_grid_level_keeps_other_pending_levels_without_replacement():
    model = StrategyModel(
        Direction.BUY, CycleMode.MODE_1, 0.01, 2.0, 500, 0.0001,
        grid_count=5,
    )

    model.on_tick(bid=1.1000, ask=1.1002)
    model.fill_grid_pending(level=2)

    pending_levels = sorted(
        pending.level
        for pending in getattr(model, "grid_pendings", {}).values()
    )
    assert pending_levels == [1, 3, 4]

    model.on_tick(bid=1.0950, ask=1.0952)
    pending_levels_after_tick = sorted(
        pending.level
        for pending in getattr(model, "grid_pendings", {}).values()
    )
    assert pending_levels_after_tick == [1, 3, 4]


def test_linear_buy_tp_follows_adverse_move_and_does_not_retrace():
    model = StrategyModel(
        Direction.BUY, CycleMode.MODE_1, 0.01, 2.0, 500, 0.0001,
        take_profit_mode=TakeProfitMode.LINEAR,
    )

    model.on_tick(bid=1.1000, ask=1.1002)
    assert model.position.take_profit == pytest.approx(1.1502)

    model.on_tick(bid=1.0950, ask=1.0952)
    assert model.position.take_profit == pytest.approx(1.1452)

    model.on_tick(bid=1.0980, ask=1.0982)
    assert model.position.take_profit == pytest.approx(1.1452)


def test_linear_sell_tp_follows_adverse_move_and_does_not_retrace():
    model = StrategyModel(
        Direction.SELL, CycleMode.MODE_1, 0.01, 2.0, 500, 0.0001,
        take_profit_mode=TakeProfitMode.LINEAR,
    )

    model.on_tick(bid=1.1000, ask=1.1002)
    assert model.position.take_profit == pytest.approx(1.0500)

    model.on_tick(bid=1.1050, ask=1.1052)
    assert model.position.take_profit == pytest.approx(1.0550)

    model.on_tick(bid=1.1020, ask=1.1022)
    assert model.position.take_profit == pytest.approx(1.0550)


def test_grid_take_profit_stays_fixed_until_grid_fill():
    model = StrategyModel(
        Direction.BUY, CycleMode.MODE_1, 0.01, 2.0, 500, 0.0001,
        grid_count=5, take_profit_mode=TakeProfitMode.GRID,
    )

    model.on_tick(bid=1.1000, ask=1.1002)
    model.on_tick(bid=1.0950, ask=1.0952)
    assert model.position.take_profit == pytest.approx(1.1502)

    model.fill_grid_pending()
    assert model.position.take_profit == pytest.approx(1.1402)


def test_losing_group_initial_lots_accumulate_and_grid_lots_double():
    model = StrategyModel(
        Direction.BUY, CycleMode.MODE_1, 0.01, 2.0, 500, 0.0001,
        grid_count=5, first_order_lot_type=1,
    )

    model.on_tick(bid=1.1000, ask=1.1002)
    model.fill_grid_pending()
    first_group_stop = model.position.stop_loss
    second_group_actions = model.on_tick(
        bid=first_group_stop, ask=first_group_stop + 0.0002,
    )

    assert second_group_actions[2] == {
        "kind": "market", "direction": Direction.SELL, "lots": 0.02,
    }
    assert model.grid_lots == pytest.approx(0.02)

    model.fill_grid_pending()
    second_group_stop = model.position.stop_loss
    third_group_actions = model.on_tick(
        bid=second_group_stop - 0.0002, ask=second_group_stop,
    )

    assert third_group_actions[2] == {
        "kind": "market", "direction": Direction.SELL,
        "lots": pytest.approx(0.06),
    }
    assert model.grid_lots == pytest.approx(0.04)


def test_grid_count_is_number_of_intervals_and_outer_boundary_still_stops_group():
    model = StrategyModel(
        Direction.BUY, CycleMode.MODE_1, 0.01, 2.0, 500, 0.0001,
        grid_count=2,
    )

    model.on_tick(bid=1.1000, ask=1.1002)
    assert model.grid_pending.level == 1
    grid_actions = model.fill_grid_pending()
    assert grid_actions[0]["kind"] == "grid"
    assert model.grid_pending is None
    assert model.current_index == 0

    stop_actions = model.on_tick(
        bid=model.position.stop_loss,
        ask=model.position.stop_loss + 0.0002,
    )
    assert stop_actions[0] == {"kind": "delete_pending"}
    assert stop_actions[1] == {"kind": "close", "direction": Direction.BUY}
    assert stop_actions[2]["kind"] == "market"
    assert stop_actions[2]["direction"] is Direction.SELL


def test_favorable_grid_additions_are_disabled_by_default():
    model = StrategyModel(
        Direction.BUY, CycleMode.MODE_1, 0.01, 2.0, 500, 0.0001,
        grid_count=4,
    )

    actions = model.on_tick(bid=1.1000, ask=1.1002)

    assert [action for action in actions if action["kind"] == "favorable_grid_pending"] == []
    assert len([action for action in actions if action["kind"] == "grid_pending"]) == 3


@pytest.mark.parametrize(
    ("direction", "expected_order_type"),
    [(Direction.BUY, "BUY_STOP"), (Direction.SELL, "SELL_STOP")],
)
def test_favorable_grid_additions_use_the_same_grid_count_and_lot_size(
    direction, expected_order_type,
):
    model = StrategyModel(
        direction, CycleMode.MODE_1, 0.01, 2.0, 500, 0.0001,
        grid_count=4, favorable_grid_enable=1,
    )

    actions = model.on_tick(bid=1.1000, ask=1.1002)
    favorable = [
        action for action in actions if action["kind"] == "favorable_grid_pending"
    ]

    assert len(favorable) == 3
    assert all(action["direction"] is direction for action in favorable)
    assert all(action["order_type"] == expected_order_type for action in favorable)
    assert all(action["lots"] == pytest.approx(0.01) for action in favorable)


def test_favorable_grid_source_uses_a_chinese_visible_input_label():
    for source_name in ("NoMatterRiseFall_MT4.mq4", "NoMatterRiseFall_MT5.mq5"):
        source = (Path(__file__).parents[1] / source_name).read_text(encoding="utf-8")
        assert "input int            有利方向加单 = 0;" in source
        assert "FavorableGridEnable" in source
    mt5_source = (Path(__file__).parents[1] / "NoMatterRiseFall_MT5.mq5").read_text(
        encoding="utf-8",
    )
    assert "有利方向加单" in mt5_source
    assert "关闭" in mt5_source and "开启" in mt5_source


def test_favorable_grid_fill_keeps_group_take_profit():
    model = StrategyModel(
        Direction.BUY, CycleMode.MODE_1, 0.01, 2.0, 500, 0.0001,
        grid_count=4, favorable_grid_enable=1,
    )

    model.on_tick(bid=1.1000, ask=1.1002)
    initial_take_profit = model.position.take_profit
    fill_actions = model.fill_favorable_grid_pending(level=1)

    assert fill_actions[0]["kind"] == "favorable_grid"
    assert model.group_total_lots == pytest.approx(0.02)
    assert model.favorable_grid_filled_levels == 1
    assert model.position.take_profit == pytest.approx(initial_take_profit)


def test_adverse_grid_fill_moves_take_profit_without_moving_stop():
    model = StrategyModel(
        Direction.BUY, CycleMode.MODE_1, 0.01, 2.0, 500, 0.0001,
        grid_count=4, favorable_grid_enable=1, dynamic_stop_loss_enable=1,
    )
    model.on_tick(bid=1.1000, ask=1.1002)
    initial_stop = model.position.stop_loss
    initial_take_profit = model.position.take_profit

    model.fill_grid_pending(level=1)

    assert model.position.stop_loss == pytest.approx(initial_stop)
    assert model.position.take_profit < initial_take_profit


def test_adverse_fill_preserves_stop_already_raised_by_favorable_fill():
    model = StrategyModel(
        Direction.BUY, CycleMode.MODE_1, 0.01, 2.0, 500, 0.0001,
        grid_count=4, favorable_grid_enable=1, dynamic_stop_loss_enable=1,
    )
    model.on_tick(bid=1.1000, ask=1.1002)
    initial_take_profit = model.position.take_profit
    model.fill_favorable_grid_pending(level=1)
    raised_stop = model.position.stop_loss

    model.fill_grid_pending(level=1)

    assert model.position.stop_loss == pytest.approx(raised_stop)
    assert model.position.take_profit < initial_take_profit


def test_three_favorable_fills_keep_the_initial_take_profit():
    model = StrategyModel(
        Direction.BUY, CycleMode.MODE_1, 0.01, 2.0, 500, 0.00001,
        grid_count=4, favorable_grid_enable=1, dynamic_stop_loss_enable=1,
    )
    model.on_tick(bid=1.02268, ask=1.02270)

    for level in (1, 2, 3):
        model.fill_favorable_grid_pending(level=level)
        assert model.position.take_profit == pytest.approx(1.02770)

    assert model.position.stop_loss == pytest.approx(1.02145)


@pytest.mark.parametrize("source_name", ["NoMatterRiseFall_MT4.mq4", "NoMatterRiseFall_MT5.mq5"])
def test_favorable_grid_pending_and_fill_keep_group_take_profit(source_name):
    source = (Path(__file__).parents[1] / source_name).read_text(encoding="utf-8")
    single_pending = source.split("bool PlaceGridPending(", 1)[1].split(
        "bool PrepareGridPendingForCurrentStop(", 1,
    )[0]
    single_fill = source.split("bool HandleGridFill(", 1)[1].split(
        "void EnsureGridPending(", 1,
    )[0]
    multi_pending = source.split("bool MultiPlaceGridPending(", 1)[1].split(
        "MultiHandleGridFill(", 1,
    )[0]
    multi_fill = source.split("MultiHandleGridFill(", 1)[1].split(
        "bool MultiHandleReverseFill(", 1,
    )[0]

    assert "favorable ? GroupTakeProfitPrice(position_type)" in single_pending
    marker = ("if(FavorableGridEnable == 1)" if source_name.endswith("mq4")
              else "if(g_gui_applied_config.favorable_grid_enable == 1)")
    favorable_pending = multi_pending.split(marker, 1)[1]
    assert "MultiTakeProfitPrice(group, type)" in favorable_pending
    for fill in (single_fill, multi_fill):
        favorable_block = fill.split(marker, 1)[1]
        assert "latest_entry = fill_price;" not in favorable_block


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


def test_dynamic_stop_moves_sell_stop_down_for_favorable_grid_levels():
    model = StrategyModel(
        Direction.SELL, CycleMode.MODE_1, 0.01, 2.0, 500, 0.0001,
        grid_count=4, favorable_grid_enable=1, dynamic_stop_loss_enable=1,
    )

    model.on_tick(bid=1.1000, ask=1.1002)
    initial_stop = model.position.stop_loss
    spacing = 500 * 0.0001 / 4

    model.fill_favorable_grid_pending(level=1)
    assert model.position.stop_loss == pytest.approx(initial_stop - spacing)


def test_dynamic_stop_disabled_keeps_stop_fixed_after_favorable_fill():
    model = StrategyModel(
        Direction.BUY, CycleMode.MODE_1, 0.01, 2.0, 500, 0.0001,
        grid_count=4, favorable_grid_enable=1,
    )

    model.on_tick(bid=1.1000, ask=1.1002)
    initial_stop = model.position.stop_loss
    model.fill_favorable_grid_pending(level=1)

    assert model.position.stop_loss == pytest.approx(initial_stop)


def test_dynamic_stop_uses_highest_favorable_level_when_price_skips_a_level():
    model = StrategyModel(
        Direction.BUY, CycleMode.MODE_1, 0.01, 2.0, 500, 0.0001,

        grid_count=4, favorable_grid_enable=1, dynamic_stop_loss_enable=1,
    )

    model.on_tick(bid=1.1000, ask=1.1002)
    initial_stop = model.position.stop_loss
    spacing = 500 * 0.0001 / 4
    model.fill_favorable_grid_pending(level=2)

    assert model.position.stop_loss == pytest.approx(initial_stop + 2 * spacing)


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


def test_dynamic_stop_removes_adverse_grid_levels_at_or_beyond_new_stop():
    model = StrategyModel(
        Direction.BUY, CycleMode.MODE_1, 0.01, 2.0, 500, 0.0001,
        grid_count=4, favorable_grid_enable=1, dynamic_stop_loss_enable=1,
    )

    model.on_tick(bid=1.1000, ask=1.1002)
    model.fill_favorable_grid_pending(level=2)

    assert set(model.grid_pendings) == {1}
    assert all(pending.price > model.position.stop_loss
               for pending in model.grid_pendings.values())



@pytest.mark.parametrize("source_name", ["NoMatterRiseFall_MT4.mq4", "NoMatterRiseFall_MT5.mq5"])
def test_dynamic_stop_source_contract_is_present_for_both_platforms(source_name):
    source = (Path(__file__).parents[1] / source_name).read_text(encoding="utf-8")

    assert "input int            动态止损 = 0;" in source
    assert ("dynamic_stop_loss_enable" in source
            if source_name.endswith("MT5.mq5")
            else "DynamicStopLossEnable" in source)
    assert "动态止损必须为0或1" in source
    assert "favorable_grid_filled_mask" in source
    assert "GridLevelBit" in source
    assert "动态止损" in source
    assert "MultiStopPrice" in source
    if source_name.endswith("MT5.mq5"):
        assert "GuiConfigLegacyFingerprint" in source
        assert "Migrated legacy fingerprint after adding dynamic stop-loss" in source


def test_grid_count_is_bounded_by_grid_fill_mask_capacity():
    mt4_source = Path(__file__).parents[1].joinpath("NoMatterRiseFall_MT4.mq4").read_text(encoding="utf-8")
    mt5_source = Path(__file__).parents[1].joinpath("NoMatterRiseFall_MT5.mq5").read_text(encoding="utf-8")

    assert "#define MAX_GRID_COUNT 63" in mt4_source
    assert "#define MAX_GRID_COUNT 63" in mt5_source
    assert "InpGridCount > MAX_GRID_COUNT" in mt4_source
    assert "config.grid_count > MAX_GRID_COUNT" in mt5_source
    assert 'if(key == "grid_count" && parsed > MAX_GRID_COUNT)' in mt5_source


def test_grid_fill_mask_persistence_uses_exact_integer_parts():
    mt4_source = Path(__file__).parents[1].joinpath("NoMatterRiseFall_MT4.mq4").read_text(encoding="utf-8")
    mt5_source = Path(__file__).parents[1].joinpath("NoMatterRiseFall_MT5.mq5").read_text(encoding="utf-8")

    for source in (mt4_source, mt5_source):
        assert ".gridmask.low" in source
        assert ".gridmask.high" in source
        assert "mask = (high << 32) | low;" in source
        assert "SaveGridMask(prefix, g_grid_filled_mask);" in source
        assert "GlobalVariableSet(prefix + \".gridmask\", (double)" not in source


def test_take_profit_resets_loss_accumulation_for_the_next_cycle():
    model = StrategyModel(
        Direction.BUY, CycleMode.MODE_1, 0.01, 2.0, 500, 0.0001,
        grid_count=2,
    )

    model.on_tick(bid=1.1000, ask=1.1002)
    first_stop = model.position.stop_loss
    model.on_tick(bid=first_stop, ask=first_stop + 0.0002)
    second_take_profit = model.position.take_profit
    model.on_tick(bid=second_take_profit - 0.0002, ask=second_take_profit)

    new_actions = model.on_tick(bid=1.1000, ask=1.1002)
    assert new_actions[0] == {
        "kind": "market", "direction": Direction.BUY, "lots": 0.01,
    }


def test_take_profit_ends_cycle_and_removes_reverse_pending():
    model = StrategyModel(Direction.BUY, CycleMode.MODE_1, 0.01, 2.0, 500, 0.0001)
    model.on_tick(bid=1.1000, ask=1.1002)

    actions = model.on_tick(bid=1.1502, ask=1.1504)

    assert actions == [{"kind": "cancel_pending"}]
    assert model.position is None
    assert model.pending is None


@pytest.mark.parametrize("range_points", [499, 1001])
def test_candle_range_mode_skips_a_new_order_outside_inclusive_bounds(range_points):
    model = StrategyModel(
        Direction.BUY, CycleMode.MODE_1, 0.01, 2.0, 500, 0.0001,
        distance_mode=DistanceMode.CANDLE_RANGE,
        min_range_points=500,
        first_order_lot_type=1,
        max_range_points=1000,
    )

    actions = model.on_tick(
        bid=1.1000, ask=1.1002, candle_range_points=range_points,
        previous_high=1.1000, previous_low=1.0400,
    )

    assert actions == []
    assert model.position is None
    assert model.pending is None


@pytest.mark.parametrize("range_points", [500, 700, 1000])
def test_candle_range_mode_accepts_boundary_and_middle_values(range_points):
    model = StrategyModel(
        Direction.BUY, CycleMode.MODE_1, 0.01, 2.0, 500, 0.0001,
        distance_mode=DistanceMode.CANDLE_RANGE,
        min_range_points=500,
        max_range_points=1000,
        korder_type=1,
    )

    actions = model.on_tick(
        bid=1.1010, ask=1.1012, candle_range_points=range_points,
        previous_high=1.1000, previous_low=1.0400,
    )

    assert actions[0] == {"kind": "market", "direction": Direction.BUY, "lots": 0.01}
    assert model.position.stop_loss == pytest.approx(1.1012 - range_points * 0.0001)
    assert model.position.take_profit == pytest.approx(1.1012 + range_points * 0.0001)


def test_fixed_distance_mode_ignores_an_invalid_candle_range():
    model = StrategyModel(
        Direction.SELL, CycleMode.MODE_1, 0.01, 2.0, 500, 0.0001,
        distance_mode=DistanceMode.FIXED,
        min_range_points=500,
        max_range_points=1000,
    )

    actions = model.on_tick(bid=1.1000, ask=1.1002, candle_range_points=300)

    assert actions[0] == {"kind": "market", "direction": Direction.SELL, "lots": 0.01}


def test_average_candle_distances_uses_only_completed_candles_and_applies_multipliers():
    stop_points, take_profit_points = average_candle_distances(
        [100, 200, 300], candle_count=2, stop_multiplier=2.0,
        take_profit_multiplier=2.0,
    )

    assert stop_points == 300
    assert take_profit_points == 600


def test_zigzag_distance_uses_fourth_and_fifth_pivots_and_scales_stop():
    pivots = [
        ("high", 1.50), ("low", 1.10), ("high", 1.40),
        ("low", 1.00), ("high", 1.12),
    ]
    assert strategy_logic.zigzag_distances(
        pivots, point=0.0001, min_points=100, max_points=2000,
        stop_percent=50, take_profit_multiplier=1.5,
    ) == (600, 900)


@pytest.mark.parametrize("pivots", [
    [],
    [("high", 1.5)] * 4,
    [("high", 1.5)] * 5,
    [("high", 1.5)] * 3 + [("low", 1.0), ("low", 1.1)],
])
def test_zigzag_distance_rejects_missing_or_non_alternating_confirmed_pivots(pivots):
    assert strategy_logic.zigzag_distances(pivots, 0.0001, 100, 2000, 100, 1) is None


def test_zigzag_distance_filters_raw_swing_before_percentage():
    pivots = [("high", 1.5)] * 3 + [("low", 1.0), ("high", 1.12)]
    assert strategy_logic.zigzag_distances(pivots, 0.0001, 1200, 1200, 50, 1) == (600, 600)
    assert strategy_logic.zigzag_distances(pivots, 0.0001, 1201, 2000, 50, 1) is None
    assert strategy_logic.zigzag_distances(pivots, 0.0001, 100, 1199, 50, 1) is None


@pytest.mark.parametrize("point,minimum,maximum,percent,multiplier", [
    (0, 100, 2000, 100, 1), (0.0001, 0, 2000, 100, 1),
    (0.0001, 100, 99, 100, 1), (0.0001, 100, 2000, 0, 1),
    (0.0001, 100, 2000, 100, 0), (0.0001, 100, 2000, float("nan"), 1),
])
def test_zigzag_distance_rejects_bad_parameters(point, minimum, maximum, percent, multiplier):
    pivots = [("high", 1.5)] * 3 + [("low", 1.0), ("high", 1.12)]
    assert strategy_logic.zigzag_distances(pivots, point, minimum, maximum, percent, multiplier) is None


def test_zigzag_mode_waits_for_full_swing_breakout_before_opening_market():
    model = StrategyModel(
        Direction.BUY, CycleMode.MODE_1, 0.01, 2.0, 500, 0.0001,
        distance_mode=DistanceMode.ZIGZAG_RANGE,
        zigzag_min_points=100, zigzag_max_points=2000,
        zigzag_stop_percent=50, zigzag_take_profit_multiplier=1.5,
    )
    pivots = [
        ("high", 1.5), ("low", 1.1), ("high", 1.4),
        ("low", 1.0), ("high", 1.12),
    ]
    assert model.on_tick(bid=1.239, ask=1.2392, zigzag_pivots=pivots) == []
    actions = model.on_tick(bid=1.24, ask=1.2402, zigzag_pivots=pivots)
    assert actions[0] == {"kind": "market", "direction": Direction.BUY, "lots": 0.01}
    assert model.group_stop_points == 600
    assert model.group_take_profit_points == 900
    model.on_tick(bid=1.19, ask=1.1902, zigzag_pivots=[])
    assert model.group_stop_points == 600


@pytest.mark.parametrize(("bid", "ask", "order_type", "expected"), [
    (1.24, 1.2402, OrderType.FORWARD, Direction.BUY),
    (1.24, 1.2402, OrderType.REVERSE, Direction.SELL),
    (0.8798, 0.88, OrderType.FORWARD, Direction.SELL),
    (0.8798, 0.88, OrderType.REVERSE, Direction.BUY),
])
def test_zigzag_breakout_direction_uses_swing_extension_and_order_type(
        bid, ask, order_type, expected):
    pivots = [
        ("high", 1.5), ("low", 1.1), ("high", 1.4),
        ("low", 1.0), ("high", 1.12),
    ]
    assert strategy_logic.zigzag_breakout_direction(
        pivots, bid, ask, 0.0001, 100, 2000, order_type,
    ) is expected



def test_zigzag_breakout_does_not_trigger_inside_extended_swing_range():
    pivots = [
        ("high", 1.5), ("low", 1.1), ("high", 1.4),
        ("low", 1.0), ("high", 1.12),
    ]
    assert strategy_logic.zigzag_breakout_direction(
        pivots, 1.239, 1.2392, 0.0001, 100, 2000,
    ) is None

def test_zigzag_mode_waits_for_full_swing_breakout_before_opening_market():
    model = StrategyModel(
        Direction.BUY, CycleMode.MODE_1, 0.01, 2.0, 500, 0.0001,
        distance_mode=DistanceMode.ZIGZAG_RANGE,
        zigzag_min_points=100, zigzag_max_points=2000,
        zigzag_stop_percent=50, zigzag_take_profit_multiplier=1.5,
    )
    pivots = [
        ("high", 1.5), ("low", 1.1), ("high", 1.4),
        ("low", 1.0), ("high", 1.12),
    ]
    assert model.on_tick(bid=1.239, ask=1.2392, zigzag_pivots=pivots) == []
    actions = model.on_tick(bid=1.24, ask=1.2402, zigzag_pivots=pivots)
    assert actions[0] == {"kind": "market", "direction": Direction.BUY, "lots": 0.01}
    assert model.group_stop_points == 600
    assert model.group_take_profit_points == 900
    model.on_tick(bid=1.19, ask=1.1902, zigzag_pivots=[])
    assert model.group_stop_points == 600


@pytest.mark.parametrize(("bid", "ask", "order_type", "expected"), [
    (1.24, 1.2402, OrderType.FORWARD, Direction.BUY),
    (1.24, 1.2402, OrderType.REVERSE, Direction.SELL),
    (0.8798, 0.88, OrderType.FORWARD, Direction.SELL),
    (0.8798, 0.88, OrderType.REVERSE, Direction.BUY),
])
def test_zigzag_breakout_direction_uses_swing_extension_and_order_type(
        bid, ask, order_type, expected):
    pivots = [
        ("high", 1.5), ("low", 1.1), ("high", 1.4),
        ("low", 1.0), ("high", 1.12),
    ]
    assert strategy_logic.zigzag_breakout_direction(
        pivots, bid, ask, 0.0001, 100, 2000, order_type,
    ) is expected


@pytest.mark.parametrize("source_path", [MT4_SOURCE, MT5_SOURCE])
def test_zigzag_mode_is_wired_to_locked_group_distance(source_path):
    source = source_path.read_text(encoding="utf-8")
    assert "DISTANCE_ZIGZAG_RANGE = 5" in source
    for name in ("ZigZag深度", "ZigZag偏差", "ZigZag回退",
                 "ZigZag距离最小值", "ZigZag距离最大值",
                 "ZigZag止损百分比", "ZigZag止盈倍数"):
        assert name in source
    assert "bool GetZigZagDistancePoints(" in source
    assert "return GetZigZagDistancePoints(stop_loss_points, take_profit_points," in source
    assert "g_group_stop_points = initial_stop_points;" in source
    assert "g_group_take_profit_points = initial_take_profit_points;" in source
    assert "GetZigZagBreakoutDirection(breakout_high, breakout_low," in source

def test_zigzag_breakout_does_not_trigger_inside_extended_swing_range():
    pivots = [
        ("high", 1.5), ("low", 1.1), ("high", 1.4),
        ("low", 1.0), ("high", 1.12),
    ]
    assert strategy_logic.zigzag_breakout_direction(
        pivots, 1.239, 1.2392, 0.0001, 100, 2000,
    ) is None



@pytest.mark.parametrize("source_path", [MT4_SOURCE, MT5_SOURCE])
def test_zigzag_mode_is_wired_to_locked_group_distance(source_path):
    source = source_path.read_text(encoding="utf-8")
    assert "DISTANCE_ZIGZAG_RANGE = 5" in source
    for name in ("ZigZag深度", "ZigZag偏差", "ZigZag回退",
                 "ZigZag距离最小值", "ZigZag距离最大值",
                 "ZigZag止损百分比", "ZigZag止盈倍数"):
        assert name in source
    assert "bool GetZigZagDistancePoints(" in source
    assert "return GetZigZagDistancePoints(stop_loss_points, take_profit_points," in source
    assert "g_group_stop_points = initial_stop_points;" in source
    assert "g_group_take_profit_points = initial_take_profit_points;" in source
    assert "GetZigZagBreakoutDirection(breakout_high, breakout_low," in source

@pytest.mark.parametrize("source_path", [MT4_SOURCE, MT5_SOURCE])
def test_active_zigzag_group_never_recalculates_missing_locked_distance(source_path):
    source = source_path.read_text(encoding="utf-8")
    body = source.split("bool GetActiveDistancePoints(", 1)[1].split("\nint ", 1)[0]
    assert "DISTANCE_ZIGZAG_RANGE" in body
    assert re.search(r"if\([^)]*DISTANCE_ZIGZAG_RANGE[^)]*\)\s*return false;", body)



@pytest.mark.parametrize("source_path", [MT4_SOURCE, MT5_SOURCE])
def test_zigzag_entry_rejects_distance_below_broker_minimum(source_path):
    source = source_path.read_text(encoding="utf-8")
    assert "bool ZigZagBrokerDistanceValid(" in source
    assert "ZigZagBrokerDistanceValid(initial_stop_points, initial_take_profit_points)" in source


def test_mt5_existing_state_fingerprint_migrates_when_zigzag_fields_are_added():
    source = MT5_SOURCE.read_text(encoding="utf-8")
    assert "GuiConfigBeforeZigZagFingerprintText" in source
    assert "GuiConfigBeforeZigZagFingerprint(config)" in source
    assert "GuiConfigBeforeZigZagFingerprint2(config)" in source



def test_mt5_zigzag_requests_indicator_buffer_before_waiting_for_data():
    source = MT5_SOURCE.read_text(encoding="utf-8")
    body = source.split("bool GetZigZagDistancePoints(", 1)[1].split("\nbool ZigZagBrokerDistanceValid", 1)[0]
    assert body.index("CopyBuffer(g_zigzag_handle") < body.index("if(copied != bars)")
    assert "calculated < bars" not in body


@pytest.mark.parametrize(
    ("ranges", "candle_count", "stop_multiplier", "take_profit_multiplier"),
    [
        ([100], 2, 2.0, 2.0),
        ([100, 0], 2, 2.0, 2.0),
        ([100, -20], 2, 2.0, 2.0),
        ([100, 200], 2, 0.0, 2.0),
        ([100, 200], 2, 2.0, -1.0),
    ],
)
def test_average_candle_distances_rejects_invalid_inputs(
    ranges, candle_count, stop_multiplier, take_profit_multiplier,
):
    with pytest.raises(ValueError):
        average_candle_distances(
            ranges, candle_count=candle_count,
            stop_multiplier=stop_multiplier,
            take_profit_multiplier=take_profit_multiplier,
        )


def test_average_distance_mode_uses_market_entry_and_keeps_distances_for_group():
    model = StrategyModel(
        Direction.BUY, CycleMode.MODE_1, 0.01, 2.0, 500, 0.0001,
        distance_mode=DistanceMode.AVERAGE_CANDLE_RANGE,
        average_candle_count=3, average_stop_multiplier=2.0,
        average_take_profit_multiplier=2.0, korder_type=0,
    )

    actions = model.on_tick(
        bid=1.1000, ask=1.1002, previous_high=1.2000, previous_low=1.0000,
        average_candle_ranges=[100, 200, 300], candle_id=10,
    )

    assert actions[0] == {"kind": "market", "direction": Direction.BUY, "lots": 0.01}
    assert all(action["kind"] != "initial_pending" for action in actions)
    assert model.group_stop_points == 400
    assert model.group_take_profit_points == 800
    assert model.position.stop_loss == pytest.approx(1.1002 - 400 * 0.0001)
    assert model.position.take_profit == pytest.approx(1.1002 + 800 * 0.0001)


def test_average_distance_mode_does_not_use_single_candle_min_max_filter():
    model = StrategyModel(
        Direction.SELL, CycleMode.MODE_1, 0.01, 2.0, 500, 0.0001,
        distance_mode=DistanceMode.AVERAGE_CANDLE_RANGE,
        average_candle_count=2, average_stop_multiplier=1.0,
        average_take_profit_multiplier=1.0,
        min_range_points=500, max_range_points=1000,
    )

    actions = model.on_tick(
        bid=1.1000, ask=1.1002, candle_range_points=1,
        average_candle_ranges=[100, 200],
    )

    assert actions[0]["kind"] == "market"
    assert model.group_stop_points == 150


def test_long_candle_bullish_k1_opens_market_buy_with_fixed_distances():
    model = StrategyModel(
        Direction.SELL, CycleMode.MODE_1, 0.01, 2.0, 500, 0.0001,
        distance_mode=DistanceMode.LONG_CANDLE_MARKET,
    )


    actions = model.on_tick(
        bid=1.1000, ask=1.1002, candle_range_points=1000,
        k1_open=1.0000, k1_close=1.0100,
        long_candle_ranges=[900] * 20,
    )

    assert actions[0] == {"kind": "market", "direction": Direction.BUY, "lots": 0.01}
    assert model.group_stop_points == 500
    assert model.group_take_profit_points == 500
    assert model.sequence[0] is Direction.BUY


def test_long_candle_bearish_k1_opens_market_sell():
    model = StrategyModel(
        Direction.BUY, CycleMode.MODE_1, 0.01, 2.0, 500, 0.0001,
        distance_mode=DistanceMode.LONG_CANDLE_MARKET,
    )

    actions = model.on_tick(
        bid=1.1000, ask=1.1002, candle_range_points=1000,
        k1_open=1.0100, k1_close=1.0000,
        long_candle_ranges=[900] * 20,
    )

    assert actions[0]["direction"] is Direction.SELL
    assert model.sequence[0] is Direction.SELL


@pytest.mark.parametrize(
    ("k1_open", "k1_close", "k1_range", "prior_ranges"),
    [
        (1.0, 1.1, 900, [1000] + [900] * 19),
        (1.0, 1.0, 1000, [900] * 20),
        (1.0, 1.1, 1000, [900] * 19),
    ],
)
def test_long_candle_signal_requires_long_non_doji_k1(
    k1_open, k1_close, k1_range, prior_ranges,
):
    assert long_candle_direction(
        k1_open, k1_close, k1_range, prior_ranges,
    ) is None


def test_mt4_and_mt5_expose_matching_long_candle_market_contract():
    for source_path in (MT4_SOURCE, MT5_SOURCE):
        source = source_path.read_text(encoding="utf-8")
        assert "DISTANCE_LONG_CANDLE" in source
        assert "K1" in source
        assert "K2" in source or "shift = 2" in source
        assert "市价做多" in source or "ORDER_TYPE_BUY" in source or "OP_BUY" in source
        assert "市价做空" in source or "ORDER_TYPE_SELL" in source or "OP_SELL" in source


def test_mt4_and_mt5_expose_matching_average_distance_contract():
    mt4_source = MT4_SOURCE.read_text(encoding="utf-8")
    mt5_source = MT5_SOURCE.read_text(encoding="utf-8")
    for source in (mt4_source, mt5_source):
        assert "DISTANCE_AVERAGE_CANDLE_RANGE" in source
        assert "平均K线根数" in source
        assert "平均止损倍数" in source
        assert "平均止盈倍数" in source
        assert "for(int shift = 1; shift <=" in source
    assert 'config.distance_mode != DISTANCE_AVERAGE_CANDLE_RANGE' in mt5_source
    assert 'key == "average_candle_count"' in mt5_source


@pytest.mark.parametrize(
    ("order_type", "bid", "ask", "expected_first", "expected_cycle"),
    [
        (OrderType.FORWARD, 1.1010, 1.1012, Direction.BUY, CycleMode.MODE_1),
        (OrderType.REVERSE, 1.1010, 1.1012, Direction.SELL, CycleMode.MODE_2),
        (OrderType.FORWARD, 1.0390, 1.0392, Direction.SELL, CycleMode.MODE_1),
        (OrderType.REVERSE, 1.0390, 1.0392, Direction.BUY, CycleMode.MODE_2),
    ],
)
def test_candle_breakout_selects_first_direction_and_cycle_from_order_type(
    order_type, bid, ask, expected_first, expected_cycle,
):
    model = StrategyModel(
        Direction.BUY, CycleMode.MODE_1, 0.01, 2.0, 500, 0.0001,
        distance_mode=DistanceMode.CANDLE_RANGE,
        min_range_points=500,
        max_range_points=1000,
        order_type=order_type,
        korder_type=1,
    )

    actions = model.on_tick(
        bid=bid, ask=ask, candle_range_points=600,
        previous_high=1.1000, previous_low=1.0400,
    )

    assert actions[0] == {"kind": "market", "direction": expected_first, "lots": 0.01}
    assert model.cycle_mode is expected_cycle
    assert model.sequence[0] is expected_first


def test_candle_range_mode_waits_for_a_breakout_before_opening():
    model = StrategyModel(
        Direction.BUY, CycleMode.MODE_1, 0.01, 2.0, 500, 0.0001,
        distance_mode=DistanceMode.CANDLE_RANGE,
        min_range_points=500,
        max_range_points=1000,
        order_type=OrderType.FORWARD,
        korder_type=1,
    )

    actions = model.on_tick(
        bid=1.0700, ask=1.0702, candle_range_points=600,
        previous_high=1.1000, previous_low=1.0400,
    )

    assert actions == []
    assert model.position is None
    assert model.pending is None


def test_candle_once_places_buy_at_high_and_sell_at_low_without_market_entry():
    model = StrategyModel(
        Direction.BUY, CycleMode.MODE_1, 0.01, 2.0, 500, 0.0001,
        distance_mode=DistanceMode.CANDLE_RANGE,
        order_type=OrderType.FORWARD, korder_type=0,
    )

    actions = model.on_tick(
        bid=1.0500, ask=1.0502, candle_range_points=600,
        previous_high=1.1000, previous_low=1.0400, candle_id=10,
    )

    assert [action["kind"] for action in actions] == [
        "initial_pending", "initial_pending",
    ]
    assert {(action["direction"], action["price"]) for action in actions} == {
        (Direction.BUY, 1.1000), (Direction.SELL, 1.0400),
    }
    assert [pending.kind for pending in model.initial_pending] == [
        "initial_pending", "initial_pending",
    ]
    assert all(action["kind"] != "market" for action in actions)


def test_candle_once_reverse_places_sell_at_high_and_buy_at_low_once():
    model = StrategyModel(
        Direction.BUY, CycleMode.MODE_1, 0.01, 2.0, 500, 0.0001,
        distance_mode=DistanceMode.CANDLE_RANGE,
        order_type=OrderType.REVERSE, korder_type=0,
    )

    first = model.on_tick(
        bid=1.0500, ask=1.0502, candle_range_points=600,
        previous_high=1.1000, previous_low=1.0400, candle_id=10,
    )
    second = model.on_tick(
        bid=1.0500, ask=1.0502, candle_range_points=600,
        previous_high=1.1000, previous_low=1.0400, candle_id=10,
    )

    assert {(action["direction"], action["price"]) for action in first} == {
        (Direction.SELL, 1.1000), (Direction.BUY, 1.0400),
    }
    assert second == []


def test_candle_repeat_still_waits_for_breakout_and_opens_market_order():
    model = StrategyModel(
        Direction.BUY, CycleMode.MODE_1, 0.01, 2.0, 500, 0.0001,
        distance_mode=DistanceMode.CANDLE_RANGE,
        order_type=OrderType.FORWARD, korder_type=1,
    )

    actions = model.on_tick(
        bid=1.0500, ask=1.0502, candle_range_points=600,
        previous_high=1.1000, previous_low=1.0400, candle_id=10,
    )
    assert actions == []

    actions = model.on_tick(
        bid=1.1001, ask=1.1003, candle_range_points=600,
        previous_high=1.1000, previous_low=1.0400, candle_id=10,
    )
    assert actions[0]["kind"] == "market"
    assert all(action["kind"] != "initial_pending" for action in actions)


def test_initial_pending_fill_cancels_the_other_side_and_starts_group():
    model = StrategyModel(
        Direction.BUY, CycleMode.MODE_1, 0.01, 2.0, 500, 0.0001,
        distance_mode=DistanceMode.CANDLE_RANGE,
        order_type=OrderType.FORWARD, korder_type=0,
    )
    model.on_tick(
        bid=1.0500, ask=1.0502, candle_range_points=600,
        previous_high=1.1000, previous_low=1.0400, candle_id=10,
    )

    actions = model.fill_initial_pending(Direction.BUY, 1.1000)

    assert actions[0] == {"kind": "cancel_initial_pending", "direction": Direction.SELL}
    assert model.position.direction is Direction.BUY
    assert model.position.entry == 1.1000
    assert model.initial_pending == []


def test_candle_mode_ignores_user_first_direction_and_cycle_mode_inputs():
    forward_model = StrategyModel(
        Direction.SELL, CycleMode.MODE_2, 0.01, 2.0, 500, 0.0001,
        distance_mode=DistanceMode.CANDLE_RANGE,
        min_range_points=500,
        max_range_points=1000,
        order_type=OrderType.FORWARD,
        korder_type=1,
    )
    forward_actions = forward_model.on_tick(
        bid=1.1010, ask=1.1012, candle_range_points=600,
        previous_high=1.1000, previous_low=1.0400,
    )

    reverse_model = StrategyModel(
        Direction.BUY, CycleMode.MODE_3, 0.01, 2.0, 500, 0.0001,
        distance_mode=DistanceMode.CANDLE_RANGE,
        min_range_points=500,
        max_range_points=1000,
        order_type=OrderType.REVERSE,
        korder_type=1,
    )
    reverse_actions = reverse_model.on_tick(
        bid=1.0390, ask=1.0392, candle_range_points=600,
        previous_high=1.1000, previous_low=1.0400,
    )

    assert forward_actions[0]["direction"] is Direction.BUY
    assert forward_model.cycle_mode is CycleMode.MODE_1
    assert reverse_actions[0]["direction"] is Direction.BUY
    assert reverse_model.cycle_mode is CycleMode.MODE_2


def test_candle_range_mode_keeps_running_cycle_when_later_range_is_invalid():
    model = StrategyModel(
        Direction.BUY, CycleMode.MODE_1, 0.01, 2.0, 500, 0.0001,
        distance_mode=DistanceMode.CANDLE_RANGE,
        min_range_points=500,
        first_order_lot_type=1,
        max_range_points=1000,
        korder_type=1,
    )

    model.on_tick(
        bid=1.1010, ask=1.1012, candle_range_points=600,
        previous_high=1.1000, previous_low=1.0400,
    )
    for _ in range(3):
        pending = model.pending
        model.fill_pending(pending.price)
        model.on_tick(
            bid=model.position.entry,
            ask=model.position.entry + 0.0002,
            candle_range_points=600,
            previous_high=1.1000, previous_low=1.0400,
        )

    pending = model.pending
    model.fill_pending(pending.price)
    actions = model.on_tick(
        bid=model.position.entry,
        ask=model.position.entry + 0.0002,
        candle_range_points=300,
        previous_high=1.1000, previous_low=1.0700,
    )

    assert model.position.lots == pytest.approx(0.08)
    assert actions == []
    assert model.pending.direction is Direction.SELL
    assert model.pending.lots == pytest.approx(0.16)
    assert model.pending.price == pytest.approx(model.position.stop_loss)
    assert model.pending.order_type == "SELL_LIMIT"

    position = model.position
    stop_actions = model.on_tick(
        bid=position.stop_loss,
        ask=position.stop_loss + 0.0002,
        candle_range_points=300,
        previous_high=1.1000, previous_low=1.0700,
    )
    assert stop_actions[2] == {
        "kind": "market", "direction": Direction.SELL, "lots": 0.16,
    }


def test_candle_order_mode_zero_places_initial_pending_once_per_current_candle():
    model = StrategyModel(
        Direction.BUY, CycleMode.MODE_1, 0.01, 2.0, 500, 0.0001,
        distance_mode=DistanceMode.CANDLE_RANGE,
        order_type=OrderType.FORWARD,
        korder_type=0,
    )
    first = model.on_tick(
        bid=1.1002, ask=1.1004, candle_range_points=600,
        previous_high=1.1000, previous_low=1.0400, candle_id=10,
    )
    same_candle = model.on_tick(
        bid=1.2000, ask=1.2002, candle_range_points=600,
        previous_high=1.1000, previous_low=1.0400, candle_id=10,
    )

    assert [action["kind"] for action in first] == [
        "initial_pending", "initial_pending",
    ]
    assert same_candle == []
    assert model.position is None
    assert len(model.initial_pending) == 2


def test_candle_order_mode_one_allows_repeated_initial_entries_per_current_candle():
    model = StrategyModel(
        Direction.BUY, CycleMode.MODE_1, 0.01, 2.0, 500, 0.0001,
        distance_mode=DistanceMode.CANDLE_RANGE,
        order_type=OrderType.FORWARD,
        korder_type=1,
    )
    model.on_tick(
        bid=1.1002, ask=1.1004, candle_range_points=600,
        previous_high=1.1000, previous_low=1.0400, candle_id=10,
    )
    model.on_tick(
        bid=model.position.take_profit, ask=model.position.take_profit + 0.0002,
        candle_range_points=600, previous_high=1.1000, previous_low=1.0400,
        candle_id=10,
    )

    repeated = model.on_tick(
        bid=1.2000, ask=1.2002, candle_range_points=600,
        previous_high=1.1000, previous_low=1.0400, candle_id=10,
    )

    assert repeated[0]["kind"] == "market"


def test_candle_distance_is_locked_until_take_profit_starts_a_new_group():
    model = StrategyModel(
        Direction.BUY, CycleMode.MODE_1, 0.01, 2.0, 500, 0.0001,
        distance_mode=DistanceMode.CANDLE_RANGE,
        min_range_points=500,
        max_range_points=1000,
        korder_type=1,
    )

    first_actions = model.on_tick(
        bid=1.1010, ask=1.1012, candle_range_points=600,
        previous_high=1.1000, previous_low=1.0400,
    )
    first_stop = model.position.stop_loss
    first_take_profit = model.position.take_profit

    unchanged_actions = model.on_tick(
        bid=1.1010, ask=1.1012, candle_range_points=900,
        previous_high=1.1000, previous_low=1.0100,
    )

    assert unchanged_actions == []
    assert model.position.stop_loss == pytest.approx(first_stop)
    assert model.position.take_profit == pytest.approx(first_take_profit)
    assert model.pending.distance_points == pytest.approx(600)

    model.on_tick(bid=first_take_profit, ask=first_take_profit + 0.0002, candle_range_points=900)
    new_group_actions = model.on_tick(
        bid=1.1010, ask=1.1012, candle_range_points=900,
        previous_high=1.1000, previous_low=1.0100,
    )

    assert new_group_actions[0] == {
        "kind": "market", "direction": Direction.BUY, "lots": 0.01,
    }
    assert model.position.stop_loss == pytest.approx(1.1012 - 900 * 0.0001)
    assert model.position.take_profit == pytest.approx(1.1012 + 900 * 0.0001)
    assert model.pending.distance_points == pytest.approx(900)


@pytest.mark.parametrize(
    ("initial_direction", "cycle_mode"),
    [
        (Direction.BUY, CycleMode.MODE_1),
        (Direction.SELL, CycleMode.MODE_1),
        (Direction.BUY, CycleMode.MODE_2),
        (Direction.SELL, CycleMode.MODE_2),
        (Direction.BUY, CycleMode.MODE_3),
        (Direction.SELL, CycleMode.MODE_3),
    ],
)
def test_all_four_combinations_run_a_full_six_order_cycle(initial_direction, cycle_mode):
    model = StrategyModel(
        initial_direction, cycle_mode, 0.01, 2.0, 500, 0.0001,
        max_reversals=6, first_order_lot_type=1,
    )
    opened = []
    pending_types = []

    actions = model.on_tick(bid=1.1000, ask=1.1002)
    opened.append((actions[0]["direction"], actions[0]["lots"]))
    pending_types.append(actions[1]["order_type"])
    for _ in range(5):
        position = model.position
        if position.direction is Direction.BUY:
            bid, ask = position.stop_loss, position.stop_loss + 0.0002
        else:
            bid, ask = position.stop_loss - 0.0002, position.stop_loss
        actions = model.on_tick(bid=bid, ask=ask)
        opened.append((actions[2]["direction"], actions[2]["lots"]))
        pending_types.append(actions[3]["order_type"])

    expected = cycle_directions(initial_direction, cycle_mode)
    assert [direction for direction, _ in opened] == expected
    assert [lots for _, lots in opened] == pytest.approx([0.01, 0.01, 0.02, 0.04, 0.08, 0.16])
    expected_pending_types = []
    for current, following in zip(expected, expected[1:] + expected[:1]):
        if current is Direction.BUY and following is Direction.BUY:
            expected_pending_types.append("BUY_LIMIT")
        elif current is Direction.SELL and following is Direction.SELL:
            expected_pending_types.append("SELL_LIMIT")
        elif following is Direction.BUY:
            expected_pending_types.append("BUY_STOP")
        else:
            expected_pending_types.append("SELL_STOP")
    assert pending_types == expected_pending_types


@pytest.mark.parametrize("initial_direction", [Direction.BUY, Direction.SELL])
def test_cycle_mode_four_runs_a_full_seven_order_cycle(initial_direction):
    model = StrategyModel(
        initial_direction, CycleMode.MODE_4, 0.01, 2.0, 500, 0.0001,
        max_reversals=7, first_order_lot_type=1,
    )
    opened = []

    actions = model.on_tick(bid=1.1000, ask=1.1002)
    opened.append(actions[0]["direction"])
    for _ in range(6):
        position = model.position
        if position.direction is Direction.BUY:
            bid, ask = position.stop_loss, position.stop_loss + 0.0002
        else:
            bid, ask = position.stop_loss - 0.0002, position.stop_loss
        actions = model.on_tick(bid=bid, ask=ask)
        opened.append(actions[2]["direction"])

    assert opened == cycle_directions(initial_direction, CycleMode.MODE_4)


def test_no_money_closes_group_resets_state_and_restarts_on_next_tick():
    model = StrategyModel(
        Direction.BUY, CycleMode.MODE_1, 0.01, 2.0, 500, 0.0001,
        market_order_failures=1,
    )

    first = model.on_tick(bid=1.1000, ask=1.1002)
    assert first == [{"kind": "no_money"}]
    assert model.position is None
    assert model.pending is None
    assert model.cumulative_loss_lots == pytest.approx(0.0)
    assert model.current_index == 0

    second = model.on_tick(bid=1.1000, ask=1.1002)
    assert second[0] == {
        "kind": "market", "direction": Direction.BUY, "lots": pytest.approx(0.01),
    }


def test_no_money_after_stop_starts_a_fresh_base_lot_group():
    model = StrategyModel(
        Direction.BUY, CycleMode.MODE_1, 0.01, 2.0, 500, 0.0001,
        initial_lot_multiplier=2.0, grid_count=5,
    )
    model.on_tick(bid=1.1000, ask=1.1002)
    model.market_order_failures = 1
    stop_price = model.position.stop_loss

    failed = model.on_tick(bid=stop_price, ask=stop_price + 0.0002)

    assert failed == [{"kind": "no_money"}]
    assert model.position is None
    assert model.pending is None
    assert model.grid_pending is None
    assert model.cumulative_loss_lots == pytest.approx(0.0)

    restarted = model.on_tick(bid=1.1000, ask=1.1002)
    assert restarted[0]["lots"] == pytest.approx(0.01)


def test_no_money_dynamic_mode_rechecks_current_breakout_after_reset():
    model = StrategyModel(
        Direction.SELL, CycleMode.MODE_2, 0.01, 2.0, 500, 0.0001,
        distance_mode=DistanceMode.CANDLE_RANGE,
        min_range_points=500, max_range_points=1000,
        order_type=OrderType.FORWARD,
        market_order_failures=1,
        korder_type=1,
    )

    waiting = model.on_tick(
        bid=1.0700, ask=1.0702, candle_range_points=600,
        previous_high=1.1000, previous_low=1.0400,
    )
    assert waiting == []

    failed = model.on_tick(
        bid=1.1010, ask=1.1012, candle_range_points=600,
        previous_high=1.1000, previous_low=1.0400,
    )
    assert failed == [{"kind": "no_money"}]

    no_breakout = model.on_tick(
        bid=1.0700, ask=1.0702, candle_range_points=700,
        previous_high=1.1000, previous_low=1.0400,
    )
    assert no_breakout == []

    restarted = model.on_tick(
        bid=1.1010, ask=1.1012, candle_range_points=700,
        previous_high=1.1000, previous_low=1.0400,
    )
    assert restarted[0]["kind"] == "market"
    assert model.group_stop_points == pytest.approx(700)


def test_no_money_reset_does_not_open_again_on_the_same_tick():
    model = StrategyModel(
        Direction.BUY, CycleMode.MODE_1, 0.01, 2.0, 500, 0.0001,
        market_order_failures=1,
    )

    actions = model.on_tick(bid=1.1000, ask=1.1002)

    assert [action["kind"] for action in actions] == ["no_money"]


def test_no_money_reset_uses_fixed_mode_time_window_for_the_new_cycle():
    model = StrategyModel(
        Direction.BUY, CycleMode.MODE_1, 0.01, 2.0, 500, 0.0001,
        start_minute=8 * 60, end_minute=23 * 60,
    )
    model.on_tick(bid=1.1000, ask=1.1002, now_minute=8 * 60)
    model.market_order_failures = 1
    stop_price = model.position.stop_loss

    failed = model.on_tick(
        bid=stop_price, ask=stop_price + 0.0002,
        now_minute=23 * 60 + 30,
    )
    assert failed == [{"kind": "no_money"}]

    outside_window = model.on_tick(
        bid=1.1000, ask=1.1002, now_minute=23 * 60 + 30,
    )
    assert outside_window == []

    restarted = model.on_tick(
        bid=1.1000, ask=1.1002, now_minute=8 * 60,
    )
    assert restarted[0]["lots"] == pytest.approx(0.01)


def test_max_reversals_five_allows_five_switches_then_resets():
    model = StrategyModel(
        Direction.BUY, CycleMode.MODE_1, 0.01, 2.0, 500, 0.0001,
        max_reversals=5,
    )
    model.on_tick(bid=1.1000, ask=1.1002)

    for expected_count in range(1, 6):
        stop_price = model.position.stop_loss
        actions = model.on_tick(bid=stop_price, ask=stop_price + 0.0002)
        assert actions[2]["kind"] == "market"
        assert model.reversal_count == expected_count

    stop_price = model.position.stop_loss
    actions = model.on_tick(bid=stop_price, ask=stop_price + 0.0002)
    assert actions == [{"kind": "reset_max_reversals"}]
    assert model.position is None
    assert model.pending is None
    assert model.reversal_count == 0
    assert model.cumulative_loss_lots == pytest.approx(0.0)


def test_zero_max_reversals_resets_after_the_first_group_stop():
    model = StrategyModel(
        Direction.BUY, CycleMode.MODE_1, 0.01, 2.0, 500, 0.0001,
        max_reversals=0,
    )
    model.on_tick(bid=1.1000, ask=1.1002)
    stop_price = model.position.stop_loss

    actions = model.on_tick(bid=stop_price, ask=stop_price + 0.0002)

    assert actions == [{"kind": "reset_max_reversals"}]
    assert model.position is None
    assert model.pending is None


def test_max_reversals_counts_reverse_pending_fills_before_reset():
    model = StrategyModel(
        Direction.BUY, CycleMode.MODE_1, 0.01, 2.0, 500, 0.0001,
        max_reversals=2,
    )
    model.on_tick(bid=1.1000, ask=1.1002)

    for expected_count in (1, 2):
        pending_price = model.pending.price
        model.fill_pending(pending_price)
        assert model.reversal_count == expected_count

    assert model.pending is None
    stop_price = model.position.stop_loss
    actions = model.on_tick(bid=stop_price, ask=stop_price + 0.0002)

    assert actions == [{"kind": "reset_max_reversals"}]
    assert model.position is None
    assert model.reversal_count == 0


def test_filled_reverse_pending_is_the_only_stop_transition_action():
    model = StrategyModel(
        Direction.BUY, CycleMode.MODE_1, 0.01, 2.0, 500, 0.0001,
        first_order_lot_type=1,
    )
    model.on_tick(bid=1.1000, ask=1.1002)
    pending_price = model.pending.price

    actions = model.handle_stop_event(
        bid=pending_price, ask=pending_price + 0.0002, pending_filled=True,
    )

    assert actions == [{
        "kind": "pending_transition", "direction": Direction.SELL, "lots": 0.01,
    }]
    assert model.reversal_count == 1


def test_new_cycle_after_max_reversals_uses_base_lot_on_next_tick():
    model = StrategyModel(
        Direction.BUY, CycleMode.MODE_1, 0.01, 2.0, 500, 0.0001,
        max_reversals=0, initial_lot_multiplier=2.0,
    )
    model.on_tick(bid=1.1000, ask=1.1002)
    stop_price = model.position.stop_loss
    model.on_tick(bid=stop_price, ask=stop_price + 0.0002)

    actions = model.on_tick(bid=1.1000, ask=1.1002)

    assert actions[0]["kind"] == "market"
    assert actions[0]["lots"] == pytest.approx(0.01)


def dynamic_parallel_model(multiple, korder_type=1):
    return ParallelStrategyModel(
        Direction.BUY, CycleMode.MODE_1, 0.01, 2.0, 500, 0.0001,
        distance_mode=DistanceMode.CANDLE_RANGE,
        min_range_points=500, max_range_points=1000,
        order_type=OrderType.FORWARD, grid_count=2,
        korder_type=korder_type, kline_enable_multiple=multiple,
    )


def parallel_breakout(model, candle_id, range_points, bid=1.1010, ask=1.1012):
    return model.on_tick(
        bid=bid, ask=ask, candle_range_points=range_points,
        previous_high=1.1000, previous_low=1.0400,
        candle_id=candle_id,
    )


def test_kline_multiple_zero_blocks_new_group_while_existing_group_is_active():
    model = dynamic_parallel_model(0)
    assert parallel_breakout(model, 10, 600)[0]["kind"] == "market"
    assert parallel_breakout(model, 11, 900) == []
    assert len(model.groups) == 1


def test_kline_multiple_one_opens_independent_group_with_existing_group():
    model = dynamic_parallel_model(1)
    parallel_breakout(model, 10, 600)
    actions = parallel_breakout(model, 11, 900)
    assert actions[0]["kind"] == "market"
    assert len(model.groups) == 2
    assert [group.group_id for group in model.groups] == [1, 2]


def test_parallel_groups_keep_different_candle_distances():
    model = dynamic_parallel_model(1)
    parallel_breakout(model, 10, 600)
    parallel_breakout(model, 11, 900)
    assert [group.group_stop_points for group in model.groups] == [600, 900]
    assert [group.group_take_profit_points for group in model.groups] == [600, 900]


def test_take_profit_of_one_group_does_not_close_other_group():
    model = dynamic_parallel_model(1)
    parallel_breakout(model, 10, 600)
    parallel_breakout(model, 11, 900)
    first, second = model.groups
    actions = model.on_tick(
        bid=first.position.take_profit,
        ask=first.position.take_profit + 0.0002,
        candle_id=11,
    )
    assert actions[0]["group_id"] == first.group_id
    assert first.position is None
    assert second.position is not None
    assert second.pending is not None


def test_parallel_groups_keep_reverse_and_grid_pending_separate():
    model = dynamic_parallel_model(1)
    parallel_breakout(model, 10, 600)
    parallel_breakout(model, 11, 900)
    first, second = model.groups
    assert first.pending is not None and second.pending is not None
    assert first.grid_pending is not None and second.grid_pending is not None
    first_pending_price = first.pending.price
    model.fill_pending(first.group_id, first_pending_price)
    assert second.pending is not None
    assert second.grid_pending is not None


def test_parallel_multiple_groups_create_two_initial_pending_orders_per_candle():
    model = dynamic_parallel_model(1, korder_type=0)

    first = model.on_tick(
        bid=1.0500, ask=1.0502, candle_range_points=600,
        previous_high=1.1000, previous_low=1.0400, candle_id=10,
    )
    duplicate = model.on_tick(
        bid=1.0500, ask=1.0502, candle_range_points=600,
        previous_high=1.1000, previous_low=1.0400, candle_id=10,
    )
    second = model.on_tick(
        bid=1.0500, ask=1.0502, candle_range_points=700,
        previous_high=1.1100, previous_low=1.0400, candle_id=11,
    )

    assert [action["kind"] for action in first] == [
        "initial_pending", "initial_pending",
    ]
    assert duplicate == []
    assert [action["kind"] for action in second] == [
        "initial_pending", "initial_pending",
    ]
    assert len(model.groups) == 2
    assert all(len(group.initial_pending) == 2 for group in model.groups)


def test_parallel_repeat_mode_still_opens_market_order_after_breakout():
    model = dynamic_parallel_model(1, korder_type=1)

    actions = parallel_breakout(model, 10, 600)

    assert actions[0]["kind"] == "market"
    assert all(action["kind"] != "initial_pending" for action in actions)


def test_parallel_fill_initial_pending_forwards_group_action_and_keeps_followups():
    model = dynamic_parallel_model(1, korder_type=0)
    model.on_tick(
        bid=1.0500, ask=1.0502, candle_range_points=600,
        previous_high=1.1000, previous_low=1.0400, candle_id=10,
    )

    actions = model.fill_initial_pending(1, Direction.BUY, 1.1000)

    assert actions[0] == {
        "kind": "cancel_initial_pending", "direction": Direction.SELL,
        "group_id": 1,
    }
    assert model.groups[0].position.direction is Direction.BUY
    assert model.groups[0].pending is not None
    assert model.groups[0].grid_pending is not None


def test_parallel_group_stop_deletes_unfilled_pending_before_market_reversal():
    model = dynamic_parallel_model(1)
    parallel_breakout(model, 10, 600)
    group = model.groups[0]
    actions = model.on_tick(
        bid=group.position.stop_loss,
        ask=group.position.stop_loss + 0.0002,
        candle_id=10,
    )
    group_actions = [action for action in actions if action["group_id"] == group.group_id]
    assert group_actions[0]["kind"] == "delete_pending"
    assert group_actions[1] == {"kind": "close", "direction": Direction.BUY,
                                "group_id": group.group_id}
    assert group_actions[2]["kind"] == "market"
    assert group_actions[2]["direction"] is Direction.SELL


def test_same_scope_allows_only_one_execution_owner():
    registry = ExecutionOwnershipRegistry()
    scope = (111, "XAUUSD", 20260830)

    assert registry.acquire(scope, "chart-a") is True
    assert registry.acquire(scope, "chart-b") is False
    registry.release(scope, "chart-a")
    assert registry.acquire(scope, "chart-b") is True


def test_different_magic_numbers_have_independent_execution_owners():
    registry = ExecutionOwnershipRegistry()

    assert registry.acquire((111, "XAUUSD", 1), "chart-a") is True
    assert registry.acquire((111, "XAUUSD", 2), "chart-b") is True


def test_duplicate_reverse_pending_keeps_tracked_ticket_and_deletes_rest():
    orders = [
        PendingRecord(12, "reverse", Direction.SELL, 0.06, 4436.69),
        PendingRecord(10, "reverse", Direction.SELL, 0.06, 4436.69),
    ]

    result = normalize_pending_records(orders, tracked_ticket=12)

    assert result.keep_ticket == 12
    assert result.delete_tickets == [10]


def test_filled_tracked_reverse_deletes_all_still_active_duplicates():
    orders = [
        PendingRecord(12, "reverse", Direction.SELL, 0.06, 4436.69),
        PendingRecord(10, "reverse", Direction.SELL, 0.06, 4436.69),
    ]

    result = normalize_pending_records(
        orders, tracked_ticket=9, tracked_ticket_filled=True,
    )

    assert result.keep_ticket == 9
    assert result.delete_tickets == [10, 12]


def test_duplicate_grid_pending_without_tracked_ticket_keeps_lowest_ticket():
    orders = [
        PendingRecord(22, "grid", Direction.BUY, 0.04, 4437.69),
        PendingRecord(20, "grid", Direction.BUY, 0.04, 4437.69),
    ]

    result = normalize_pending_records(orders)

    assert result.keep_ticket == 20
    assert result.delete_tickets == [22]


def test_pending_reconciliation_keeps_matching_order_and_does_not_touch_other_category():
    orders = [
        PendingRecord(10, "reverse", Direction.BUY, 0.06, 4436.69),
        PendingRecord(12, "reverse", Direction.SELL, 0.06, 4436.69),
        PendingRecord(20, "grid", Direction.BUY, 0.04, 4437.69),
    ]

    result = normalize_pending_records(
        orders,
        kind="reverse",
        expected_direction=Direction.SELL,
        expected_lots=0.06,
        expected_price=4436.69,
    )

    assert result.keep_ticket == 12
    assert result.delete_tickets == [10]


def test_duplicate_base_positions_pause_new_risk_and_lot_growth():
    decision = exposure_guard(ExposureSnapshot(base_positions=2, duplicate_grid_levels=0))

    assert decision.pause_new_orders is True
    assert decision.cancel_pending is True
    assert decision.accumulate_loss_lots is False


def test_prepared_transition_reuses_existing_result_after_restart():
    transition = PreparedTransition(101, Direction.SELL, 0.26)

    result = recover_prepared_transition(
        transition, [{"direction": Direction.SELL, "lots": 0.26}],
    )

    assert result == {"phase": "complete", "market_orders": []}


def test_prepared_transition_sends_exactly_one_order_when_result_is_absent():
    transition = PreparedTransition(101, Direction.SELL, 0.26)

    result = recover_prepared_transition(transition, [])

    assert result["phase"] == "complete"
    assert result["market_orders"] == [{
        "direction": Direction.SELL, "lots": 0.26, "transition_id": 101,
    }]


@pytest.mark.parametrize("source_name", ["NoMatterRiseFall_MT5.mq5", "NoMatterRiseFall_MT4.mq4"])
def test_stop_transition_never_waits_for_an_unfilled_reverse_pending(source_name):
    source = (Path(__file__).parents[1] / source_name).read_text(encoding="utf-8")

    stop_handler = source.split("if(StopReached", 1)[1].split(
        "EnsureNextPending", 1,
    )[0]
    assert "&& !has_state_pending && g_pending_ticket" not in stop_handler

    multi_stop_handler = source.split(
        "if((type == POSITION_TYPE_BUY && SymbolInfoDouble(_Symbol, SYMBOL_BID) <= desired_stop_loss)",
        1,
    )[1] if source_name.endswith("MT5.mq5") else source.split(
        "if((type == OP_BUY && Bid <= desired_stop_loss)",
        1,
    )[1]
    assert "REVERSE_PENDING_UNKNOWN" not in multi_stop_handler.split(
        "if(!MultiStopsVerified", 1,
    )[0]


@pytest.mark.parametrize("source_name", ["NoMatterRiseFall_MT5.mq5", "NoMatterRiseFall_MT4.mq4"])
def test_broker_closed_stop_recovers_before_starting_a_base_lot_group(source_name):
    source = (Path(__file__).parents[1] / source_name).read_text(encoding="utf-8")
    manage = source.split("void Manage", 1)[1].split("struct MultiGroupState", 1)[0]

    assert "RecoverFlatGroupAfterBrokerStop" in source
    assert manage.index("RecoverFlatGroupAfterBrokerStop") < manage.index(
        "const bool has_pending = HasOurPending()",
    )


@pytest.mark.parametrize("source_name", ["NoMatterRiseFall_MT5.mq5", "NoMatterRiseFall_MT4.mq4"])
def test_multi_group_broker_stop_recovers_before_removing_the_group(source_name):
    source = (Path(__file__).parents[1] / source_name).read_text(encoding="utf-8")
    multi_manage = source.split("bool MultiManageGroup", 1)[1].split(
        "bool MultiTryOpenCandleGroup", 1,
    )[0]

    assert "MultiRecoverFlatGroupAfterBrokerStop" in source
    assert "MultiRecoverFlatGroupAfterBrokerStop(group)" in multi_manage
    no_position_branch = multi_manage.rsplit("if(!has_position)", 1)[1]
    assert no_position_branch.index("MultiRecoverFlatGroupAfterBrokerStop(group)") < no_position_branch.index(
        "group.active = false",
    )


@pytest.mark.parametrize("source_path", (MT5_SOURCE, *MT5_CORE_SOURCES))
def test_flat_multi_group_take_profit_cancels_its_remaining_pending_orders(source_path):
    source = source_path.read_text(encoding="utf-8")
    multi_manage = source.split("bool MultiManageGroup", 1)[1].split(
        "bool MultiTryOpenCandleGroup", 1,
    )[0]
    flat_branch = multi_manage.rsplit("if(!has_position)", 1)[1].split(
        "if(group.transition_target_lots", 1,
    )[0]
    take_profit_check = source.split("bool MultiGroupTakeProfitReached", 1)[1].split(
        "bool MultiRecoverFlatGroupAfterBrokerStop", 1,
    )[0]
    save_group = source.split("void MultiSaveGroup", 1)[1].split(
        "void MultiLoadGroups", 1,
    )[0]
    load_groups = source.split("void MultiLoadGroups", 1)[1].split(
        "int MultiPendingStatus", 1,
    )[0]

    assert "bool MultiGroupTakeProfitReached" in source
    assert "group.state != STATE_POSITION_ACTIVE" not in take_profit_check
    assert "group.first_lots <= 0.0" in take_profit_check
    assert "group.transition_target_lots > 0.0" in take_profit_check
    for field in ("firstlots", "anchor", "transitiontarget"):
        assert f'prefix + ".{field}"' in save_group
        assert f'prefix + ".{field}"' in load_groups
    assert "SymbolInfoDouble(_Symbol, SYMBOL_BID) >= take_profit" in take_profit_check
    assert "SymbolInfoDouble(_Symbol, SYMBOL_ASK) <= take_profit" in take_profit_check
    assert "MultiGroupTakeProfitReached(group)" in flat_branch
    assert flat_branch.index("MultiGroupTakeProfitReached(group)") < flat_branch.index(
        "MultiPendingStatus(",
    )
    assert "MultiDeletePending(group.id)" in flat_branch


@pytest.mark.parametrize("source_path", (MT5_SOURCE, *MT5_CORE_SOURCES))
def test_multi_group_comment_matching_rejects_numeric_prefix_collisions(source_path):
    source = source_path.read_text(encoding="utf-8")
    matcher = source.split("bool MultiCommentMatches", 1)[1].split(
        "bool MultiIsInitialPendingComment", 1,
    )[0]

    assert "StringSubstr(comment, 0, tag_length) == tag" in matcher
    assert "StringGetCharacter(comment, tag_length)" in matcher
    assert "next_character < '0' || next_character > '9'" in matcher
    assert "tag + g_gui_applied_config.order_comment" in matcher
    assert 'tag + ".Grid."' in matcher


@pytest.mark.parametrize("source_path", (MT5_SOURCE, *MT5_CORE_SOURCES))
def test_multi_group_new_order_comments_put_group_identity_first(source_path):
    source = source_path.read_text(encoding="utf-8")
    group_comment = source.split("string MultiGroupComment", 1)[1].split(
        "string MultiInitialPendingComment", 1,
    )[0]
    initial_comment = source.split("string MultiInitialPendingComment", 1)[1].split(
        "string MultiStatePrefix", 1,
    )[0]
    grids = source.split("bool MultiPlaceGridPending", 1)[1].split(
        "bool PrepareMultiGridPendingForCurrentStop", 1,
    )[0]

    assert 'MultiGroupTag(group_id) + "."' in group_comment
    assert re.search(
        r'MultiGroupTag\(group_id\)\s*\+\s*\(high\s*\?\s*"\.InitialHigh\."\s*:\s*"\.InitialLow\."\)',
        initial_comment,
    )
    assert 'MultiGroupTag(group.id) + ".Grid."' in grids
    assert 'MultiGroupTag(group.id) + ".Grid.F."' in grids


@pytest.mark.parametrize("source_name", ["NoMatterRiseFall_MT5.mq5", "NoMatterRiseFall_MT4.mq4"])
def test_multi_group_broker_stop_recovery_obeys_maximum_reversal_count(source_name):
    source = (Path(__file__).parents[1] / source_name).read_text(encoding="utf-8")
    recovery = source.split("bool MultiRecoverFlatGroupAfterBrokerStop", 1)[1].split(
        "bool MultiManageGroup", 1,
    )[0]

    limit_check = "group.reversal_count >= g_gui_applied_config.max_reversals" \
        if source_name.endswith("MT5.mq5") else "group.reversal_count >= 最大反手次数"
    assert limit_check in recovery
    assert recovery.index(limit_check) < recovery.index("const double next_group_lots")


@pytest.mark.parametrize("source_name", ["NoMatterRiseFall_MT5.mq5", "NoMatterRiseFall_MT4.mq4"])
def test_multi_group_manager_stops_after_reset_clears_group_array(source_name):
    source = (Path(__file__).parents[1] / source_name).read_text(encoding="utf-8")
    manager = source.split("void ManageMultipleCandleGroups", 1)[1].split(
        "bool MultiHasActiveGroups", 1,
    )[0]
    after_manage = manager.split("MultiManageGroup(g_multi_groups[index]);", 1)[1].split(
        "MultiStateChanged(before, g_multi_groups[index])", 1,
    )[0]

    assert "if(g_reset_pending" in after_manage


@pytest.mark.parametrize("source_name", ["NoMatterRiseFall_MT5.mq5", "NoMatterRiseFall_MT4.mq4"])
def test_reverse_fill_closes_the_previous_group_before_promoting_the_new_group(source_name):
    source = (Path(__file__).parents[1] / source_name).read_text(encoding="utf-8")
    manage = source.split("void Manage()", 1)[1].split(
        "void ManageMultipleCandleGroups", 1,
    )[0]
    pending_fill = manage.split("if(pending_filled)", 1)[1].split(
        "volume = Total", 1,
    )[0]

    assert "ClosePreviousGroupAfterReverseFill" in source
    assert pending_fill.index("ClosePreviousGroupAfterReverseFill") < pending_fill.index(
        "g_pending_index = -1",
    )

    multi_fill = source.split("bool MultiHandleReverseFill", 1)[1].split(
        "bool ResetOrderGroupAfterOversizedReversal", 1,
    )[0]
    assert "MultiClosePositionsExcept" in source
    assert multi_fill.index("MultiClosePositionsExcept") < multi_fill.index(
        "group.pending_index = -1",
    )


@pytest.mark.parametrize("source_name", ["NoMatterRiseFall_MT5.mq5", "NoMatterRiseFall_MT4.mq4"])
def test_filled_reverse_waits_for_the_market_position_before_starting_a_new_cycle(source_name):
    source = (Path(__file__).parents[1] / source_name).read_text(encoding="utf-8")
    manage = source.split("void Manage()", 1)[1].split(
        "void ManageMultipleCandleGroups", 1,
    )[0]
    flat_recovery = manage.split("if(RecoverFlatGroupAfterBrokerStop())", 1)[1]

    assert flat_recovery.index("GetReversePendingStatus()") < flat_recovery.index(
        "const bool has_pending = HasOurPending()",
    )
    assert "REVERSE_PENDING_FILLED" in flat_recovery.split(
        "const bool has_pending = HasOurPending()", 1,
    )[0]


@pytest.mark.parametrize("source_name", ["NoMatterRiseFall_MT5.mq5", "NoMatterRiseFall_MT4.mq4"])
def test_dedup_source_contract(source_name):
    source = (Path(__file__).parents[1] / source_name).read_text(encoding="utf-8")

    assert "AcquireExecutionOwnership" in source
    assert "ReleaseExecutionOwnership" in source
    assert "NormalizeSingleGroupPending" in source
    assert "HasDuplicateSingleGroupExposure" in source
    assert "ResumePreparedTransition" in source
    assert "ReconcileOrphanSingleGroupPending" in source
    assert '".transitionphase"' in source
    assert '".transitionid"' in source
    assert "if(!AcquireExecutionOwnership())" in source
    assert "ReleaseExecutionOwnership();" in source
    assert "NormalizeSingleGroupPending(false," in source
    assert "if(HasDuplicateSingleGroupExposure())" in source

    ensure_next = source.split("void EnsureNextPending", 1)[1].split("bool Transition", 1)[0]
    assert "if(!NormalizeSingleGroupPending(false," in ensure_next
    assert "DeleteAllPending();" not in ensure_next

    ensure_grid = source.split("void EnsureGridPending", 1)[1].split(
        "void EnsureNextPending", 1,
    )[0]
    assert "grid_filled_mask" in source
    assert "NormalizeGridPendingLevel" in source
    assert source.count("group.grid_filled_mask = 0;") >= 4
    assert "for(int level = 1; level <" in ensure_grid
    assert "g_grid_filled_levels + 1" not in ensure_grid
    multi_place = source.split("bool MultiPlaceGridPending", 1)[1].split(
        "bool MultiHandleGridFill", 1,
    )[0]
    assert "for(int level = 1; level <" in multi_place
    assert "MultiNormalizeGridPendingLevel" in multi_place
    assert "grid_filled_levels + 1" not in multi_place

    if source_name.endswith("MT5.mq5"):
        assert "retcode == TRADE_RETCODE_DONE" in source
        assert "TRADE_RETCODE_DONE_PARTIAL" in source
        assert "TRADE_RETCODE_PLACED" in source


def test_korder_type_zero_limits_parallel_initial_trigger_to_one_per_k0():
    model = dynamic_parallel_model(1, korder_type=0)
    parallel_breakout(model, 10, 600)
    assert parallel_breakout(model, 10, 600) == []
    assert len(model.groups) == 1


def test_korder_type_one_allows_parallel_initial_triggers_on_same_k0():
    model = dynamic_parallel_model(1, korder_type=1)
    parallel_breakout(model, 10, 600)
    assert parallel_breakout(model, 10, 600)[0]["kind"] == "market"
    assert len(model.groups) == 2


@pytest.mark.parametrize("source_name", ["NoMatterRiseFall_MT5.mq5", "NoMatterRiseFall_MT4.mq4"])
def test_candle_distance_mode_uses_user_selected_cycle_mode(source_name):
    source = (Path(__file__).parents[1] / source_name).read_text(encoding="utf-8")

    assert "g_active_cycle_mode = ordertype == ORDERTYPE_FORWARD" not in source
    assert "state.cycle_mode = ordertype == ORDERTYPE_FORWARD" not in source
    if source_name.endswith("_MT5.mq5"):
        assert "g_active_cycle_mode = g_gui_applied_config.cycle_mode" in source
        assert "state.cycle_mode = g_gui_applied_config.cycle_mode" in source
    else:
        assert "g_active_cycle_mode = InpCycleMode" in source
        assert "state.cycle_mode = InpCycleMode" in source


@pytest.mark.parametrize("source_name", ["NoMatterRiseFall_MT5.mq5", "NoMatterRiseFall_MT4.mq4"])
def test_cycle_mode_parameter_describes_each_direction_sequence(source_name):
    source = (Path(__file__).parents[1] / source_name).read_text(encoding="utf-8")

    assert "模式一：首单多=多空空多空空；首单空=空多多空多多" in source
    assert "模式二：首单多=多空多空多多；首单空=空多空多空空" in source
    assert "模式三：首单多=多空多多空多；首单空=空多空空多空" in source


@pytest.mark.parametrize("source_name", ["NoMatterRiseFall_MT5.mq5", "NoMatterRiseFall_MT4.mq4"])
def test_initial_pending_source_contract(source_name):
    source = (Path(__file__).parents[1] / source_name).read_text(encoding="utf-8")

    assert "PlaceInitialPendingPair" in source
    assert "HandleInitialPendingFill" in source
    assert "MultiPlaceInitialPendingPair" in source
    assert "MultiHandleInitialPendingFill" in source
    assert "initial_high_ticket" in source
    assert "initial_low_ticket" in source
    assert ".InitialHigh" in source
    assert ".InitialLow" in source
    assert "KORDER_ONCE_PER_BAR" in source


@pytest.mark.parametrize("source_name", ["NoMatterRiseFall_MT5.mq5", "NoMatterRiseFall_MT4.mq4"])
def test_group_take_profit_cleanup_does_not_skip_adjacent_pending_orders(source_name):
    source = (Path(__file__).parents[1] / source_name).read_text(encoding="utf-8")
    cleanup = source.split("bool MultiDeletePending", 1)[1].split(
        "int MultiInitialPendingStatus", 1,
    )[0]

    assert "for(int index = OrdersTotal() - 1; index >= 0; index--)" in cleanup


@pytest.mark.parametrize("source_name", ["NoMatterRiseFall_MT5.mq5", "NoMatterRiseFall_MT4.mq4"])
def test_take_profit_keeps_state_until_all_group_pending_orders_are_deleted(source_name):
    source = (Path(__file__).parents[1] / source_name).read_text(encoding="utf-8")

    single_take_profit = source.split("if(TakeProfitReached", 1)[1].split(
        "if(StopReached", 1,
    )[0]
    multi_take_profit = source.split("bool MultiManageGroup", 1)[1].split(
        "const double desired_take_profit", 1,
    )[1].split(
        "desired_stop_loss", 1,
    )[0]

    assert "if(!DeleteAllPending())" in single_take_profit
    assert "if(!MultiDeletePending(group.id))" in multi_take_profit


@pytest.mark.parametrize("source_name", ["NoMatterRiseFall_MT5.mq5", "NoMatterRiseFall_MT4.mq4"])
def test_multi_group_handles_initial_fill_before_position_management(source_name):
    source = (Path(__file__).parents[1] / source_name).read_text(encoding="utf-8")
    multi_manage = source.split("bool MultiManageGroup", 1)[1].split(
        "bool MultiTryOpenCandleGroup", 1,
    )[0]

    assert multi_manage.index("MultiHandleInitialPendingFill(group)") < multi_manage.index(
        "MultiFindPosition(group.id",
    )


@pytest.mark.parametrize("source_name", ["NoMatterRiseFall_MT5.mq5", "NoMatterRiseFall_MT4.mq4"])
def test_once_per_bar_reentry_cleans_stale_pending_only_on_a_new_candle(source_name):
    source = (Path(__file__).parents[1] / source_name).read_text(encoding="utf-8")
    manage = source.split("void Manage()", 1)[1].split("void ManageMultipleCandleGroups", 1)[0]
    prepare = source.split("bool PrepareCandleOnceEntry", 1)[1].split("void Manage()", 1)[0]

    assert "current_bar_time != g_last_candle_entry_bar_time" in manage
    assert manage.index("PrepareCandleOnceEntry") < manage.index("const bool has_pending")
    assert prepare.index("DeleteAllPending()") < prepare.index("ClearState()")
    assert "MarkCandleEntryBarProcessed" in manage
    assert manage.index("ClearState();") < manage.index("MarkCandleEntryBarProcessed")


@pytest.mark.parametrize("source_name", ["NoMatterRiseFall_MT5.mq5", "NoMatterRiseFall_MT4.mq4"])
def test_multi_once_per_bar_does_not_open_another_group_until_next_candle_after_tp(source_name):
    source = (Path(__file__).parents[1] / source_name).read_text(encoding="utf-8")
    multi_manage = source.split("bool MultiManageGroup", 1)[1].split(
        "bool MultiTryOpenCandleGroup", 1,
    )[0]

    assert "MarkMultiCandleTriggerBar" in multi_manage
    assert multi_manage.index("MultiClosePositions(group.id)") < multi_manage.rindex(
        "MarkMultiCandleTriggerBar"
    )

    orphan_start = "if(!has_position" if source_name.endswith(".mq5") else "bool has_position ="
    orphan_path = multi_manage.split(orphan_start, 1)[1].split(
        "if(MultiHandleReverseFill", 1,
    )[0]
    assert "if(!MultiDeletePending(group.id))" in orphan_path
    assert orphan_path.index("MultiDeletePending(group.id)") < orphan_path.index(
        "MarkMultiCandleTriggerBar"
    )


@pytest.mark.parametrize("source_name", ["NoMatterRiseFall_MT5.mq5", "NoMatterRiseFall_MT4.mq4"])
def test_pending_cleanup_ignores_stale_initial_ticket_tracking(source_name):
    source = (Path(__file__).parents[1] / source_name).read_text(encoding="utf-8")
    cleanup = source.split("bool DeleteAllPending", 1)[1].split(
        "int GetReversePendingStatus", 1,
    )[0]
    has_pending = source.split("bool HasOurPending", 1)[1].split(
        "void BeginFullReset", 1,
    )[0]

    assert "HasActiveInitialPending()" in has_pending
    assert "ResetInitialPendingTracking()" in cleanup
    assert cleanup.index("ResetInitialPendingTracking()") < cleanup.index("return deleted")


@pytest.mark.parametrize("source_name", ["NoMatterRiseFall_MT5.mq5", "NoMatterRiseFall_MT4.mq4"])
def test_initial_pending_pair_preserves_oco_cancel_on_fill(source_name):
    source = (Path(__file__).parents[1] / source_name).read_text(encoding="utf-8")
    fill_handler = source.split("bool HandleInitialPendingFill", 1)[1].split(
        "bool PlaceNextPending", 1,
    )[0]
    multi_fill_handler = source.split("bool MultiHandleInitialPendingFill", 1)[1].split(
        "bool MultiPlaceReversePending", 1,
    )[0]

    assert "Initial OCO delete" in fill_handler or "OrderDelete(other_ticket" in fill_handler
    assert "Multi initial OCO delete" in multi_fill_handler or "OrderDelete(other_ticket" in multi_fill_handler
    assert "FindPositionByPendingOrder(filled_ticket" in fill_handler or "FindPositionByTicket(filled_ticket" in fill_handler
    assert "FindPositionByPendingOrder(filled_ticket" in multi_fill_handler or "FindPositionByTicket(filled_ticket" in multi_fill_handler


@pytest.mark.parametrize("source_name", ["NoMatterRiseFall_MT5.mq5", "NoMatterRiseFall_MT4.mq4"])
def test_once_per_bar_cleanup_runs_before_initial_fill_short_circuit(source_name):
    source = (Path(__file__).parents[1] / source_name).read_text(encoding="utf-8")
    manage = source.split("void Manage()", 1)[1].split(
        "void ManageMultipleCandleGroups", 1,
    )[0]
    prepare = source.split("bool PrepareCandleOnceEntry", 1)[1].split(
        "void Manage()", 1,
    )[0]

    assert manage.index("PrepareCandleOnceEntry") < manage.index("HandleInitialPendingFill")
    assert "HasOurPosition()" in prepare


@pytest.mark.parametrize("source_name", ["NoMatterRiseFall_MT5.mq5", "NoMatterRiseFall_MT4.mq4"])
def test_initial_fill_requires_a_real_filled_side_before_promoting_position(source_name):
    source = (Path(__file__).parents[1] / source_name).read_text(encoding="utf-8")
    handler = source.split("bool HandleInitialPendingFill", 1)[1].split(
        "bool PlaceNextPending", 1,
    )[0]

    assert "const bool high_filled" in handler
    assert "const bool low_filled" in handler
    assert "if(high_filled || low_filled)" in handler
    assert "if(high_status == REVERSE_PENDING_UNKNOWN" in handler


@pytest.mark.parametrize("source_name", ["NoMatterRiseFall_MT5.mq5", "NoMatterRiseFall_MT4.mq4"])
def test_mt5_and_mt4_have_a_fast_initial_oco_event_path(source_name):
    source = (Path(__file__).parents[1] / source_name).read_text(encoding="utf-8")

    assert "void OnTimer()" in source
    if source_name.endswith(".mq5"):
        assert "void OnTradeTransaction" in source


def test_mt5_market_entry_has_a_transaction_confirmed_single_group_request_lock():
    source = (Path(__file__).parents[1] / "NoMatterRiseFall_MT5.mq5").read_text(
        encoding="utf-8",
    )

    assert "StrategyState" in source
    assert "g_trade_request_in_flight" in source
    assert "g_trade_request_signal_id" in source
    assert "g_trade_request_bar_time" in source
    assert "OnTradeTransaction" in source
    callback = source.split("void OnTradeTransaction", 1)[1].split(
        "void OnTimer", 1,
    )[0]
    assert "ConfirmTradeRequest" in callback

    manage = source.split("void Manage()", 1)[1].split(
        "struct MultiGroupState", 1,
    )[0]
    initial_entry = manage.split("if(OpenMarket(first_direction, initial_lots))", 1)[0]
    assert "g_trade_request_in_flight" in initial_entry


def test_mt5_stop_prices_are_tick_aligned_and_validated_against_live_constraints():
    source = (Path(__file__).parents[1] / "NoMatterRiseFall_MT5.mq5").read_text(
        encoding="utf-8",
    )

    assert "double NormalizePriceToTick" in source
    assert "bool ValidateStops" in source
    assert "SYMBOL_TRADE_STOPS_LEVEL" in source
    assert "SYMBOL_TRADE_FREEZE_LEVEL" in source
    assert "SYMBOL_TRADE_TICK_SIZE" in source
    assert "bool SetGroupStops" in source
    set_group_stops = source.split("bool SetGroupStops", 1)[1].split(
        "bool StopsVerified", 1,
    )[0]
    assert "ValidateStops" in set_group_stops

    for function_name, next_name in (
        ("bool PlaceInitialPendingOrder", "bool PlaceInitialPendingPair"),
        ("bool PlaceNextPending", "bool StopReached"),
        ("bool PlaceGridPending", "bool PrepareGridPendingForCurrentStop"),
    ):
        body = source.split(function_name, 1)[1].split(next_name, 1)[0]
        assert "ValidateStops" in body or "BuildStopsForEntry" in body, function_name


def test_mt5_grid_fill_lookup_does_not_scan_all_history_on_each_check():
    source = (Path(__file__).parents[1] / "NoMatterRiseFall_MT5.mq5").read_text(
        encoding="utf-8",
    )

    for function_name, next_name in (
        ("bool FindFilledGridOrder", "bool PlaceGridPending"),
        ("bool MultiFindFilledGridOrder", "void MultiSaveGroup"),
    ):
        body = source.split(function_name, 1)[1].split(next_name, 1)[0]
        assert "HistorySelect(0, TimeCurrent())" not in body, function_name
        assert "HistoryOrderSelect" in body or "GridFill" in body, function_name


def test_mt5_multi_group_persistence_is_dirty_guarded():
    source = (Path(__file__).parents[1] / "NoMatterRiseFall_MT5.mq5").read_text(
        encoding="utf-8",
    )

    struct = source.split("struct MultiGroupState", 1)[1].split("};", 1)[0]
    assert "dirty" in struct

    save = source.split("void MultiSaveGroup", 1)[1].split(
        "void MultiLoadGroup", 1,
    )[0]
    assert "if(!group.dirty)" in save
    assert "group.dirty = false" in save


def test_mt4_grid_fill_lookup_does_not_scan_all_history_on_each_check():
    source = (Path(__file__).parents[1] / "NoMatterRiseFall_MT4.mq4").read_text(
        encoding="utf-8",
    )

    for function_name, next_name in (
        ("bool FindFilledGridOrder", "bool PlaceGridPending"),
        ("bool MultiFindFilledGridOrder", "int MultiGridFilledLevelCount"),
    ):
        body = source.split(function_name, 1)[1].split(next_name, 1)[0]
        assert "OrdersHistoryTotal()" not in body, function_name
        assert "OrderSelect" in body
        assert "grid_order_ticket" in body or "MultiGridOrderTicket" in body


def test_mt4_multi_group_persistence_is_dirty_guarded():
    source = (Path(__file__).parents[1] / "NoMatterRiseFall_MT4.mq4").read_text(
        encoding="utf-8",
    )

    struct = source.split("struct MultiGroupState", 1)[1].split("};", 1)[0]
    assert "dirty" in struct

    save = source.split("void MultiSaveGroup", 1)[1].split(
        "void MultiLoadGroups", 1,
    )[0]
    assert "if(!group.dirty)" in save
    assert "group.dirty = false" in save


def test_mt5_duplicate_single_group_exposure_is_recovered_without_manual_lockout():
    source = (Path(__file__).parents[1] / "NoMatterRiseFall_MT5.mq5").read_text(
        encoding="utf-8",
    )

    assert "bool RecoverDuplicateSingleGroupExposure" in source
    manage = source.split("void Manage()", 1)[1].split(
        "struct MultiGroupState", 1,
    )[0]
    duplicate_branch = manage.split("if(HasDuplicateSingleGroupExposure())", 1)[1].split(
        "g_duplicate_exposure_logged = false;", 1,
    )[0]
    assert "RecoverDuplicateSingleGroupExposure" in duplicate_branch
    assert "PositionClose" in source
    assert "Resolve duplicate positions manually" not in duplicate_branch


def test_mt5_multi_group_market_requests_are_locked_and_confirmed_per_group():
    source = (Path(__file__).parents[1] / "NoMatterRiseFall_MT5.mq5").read_text(
        encoding="utf-8",
    )

    struct = source.split("struct MultiGroupState", 1)[1].split(
        "};", 1,
    )[0]
    for field in (
        "request_in_flight",
        "request_position_ticket",
        "request_signal_id",
        "signal_consumed",
        "StrategyState state",
    ):
        assert field in struct

    send = source.split("bool MultiSendMarketLeg", 1)[1].split(
        "bool MultiOpenMarket", 1,
    )[0]
    assert "group.request_in_flight" in send
    assert "MultiConfirmTradeRequest" in send

    manage = source.split("bool MultiManageGroup", 1)[1].split(
        "void ProcessInitialPendingFillEvent", 1,
    )[0]
    assert "group.request_in_flight" in manage


def test_mt5_has_a_periodic_watchdog_for_silent_state_lockout_diagnosis():
    source = (Path(__file__).parents[1] / "NoMatterRiseFall_MT5.mq5").read_text(
        encoding="utf-8",
    )

    assert "void EmitStrategyWatchdog" in source
    watchdog = source.split("void EmitStrategyWatchdog", 1)[1].split(
        "void OnTradeTransaction", 1,
    )[0]
    for field in ("OpenPositions", "PendingOrders", "PausedGroups", "LastTradeTime"):
        assert field in watchdog
    assert "EmitStrategyWatchdog();" in source


def test_mt5_in_flight_diagnostics_are_rate_limited():
    source = (Path(__file__).parents[1] / "NoMatterRiseFall_MT5.mq5").read_text(
        encoding="utf-8",
    )

    assert "g_last_single_request_wait_log" in source
    assert "g_last_multi_request_wait_log" in source
    assert "now - g_last_single_request_wait_log >= 10" in source
    assert "now - g_last_multi_request_wait_log >= 10" in source


def test_gui_draft_does_not_change_applied_config_until_apply():
    model = GuiStateModel(applied={"initial_lots": 0.01, "cycle_mode": "mode1"})

    model.edit("initial_lots", 0.05)

    assert model.applied["initial_lots"] == 0.01
    assert model.draft["initial_lots"] == 0.05
    assert model.has_unapplied_changes is True

    result = model.apply()

    assert result.ok is True
    assert model.applied["initial_lots"] == 0.05
    assert model.has_unapplied_changes is False

    model.edit("initial_lots", 0.10)

    assert model.applied["initial_lots"] == 0.05
    assert model.draft["initial_lots"] == 0.10
    assert model.has_unapplied_changes is True


def test_gui_pause_and_resume_only_controls_new_initial_entry():
    model = GuiStateModel(applied={"initial_lots": 0.01, "cycle_mode": "mode1"})
    applied_before = dict(model.applied)
    draft_before = dict(model.draft)
    unapplied_before = model.has_unapplied_changes

    model.pause_new_initial_entry()

    assert model.paused_new_initial_entry is True
    assert model.strategy_management_enabled is True
    assert model.pending_orders_are_preserved is True
    assert model.applied == applied_before
    assert model.draft == draft_before
    assert model.has_unapplied_changes is unapplied_before

    model.resume_new_initial_entry()

    assert model.paused_new_initial_entry is False
    assert model.should_force_market_order is False


def test_gui_close_all_requires_confirmation_and_reports_incomplete_cleanup():
    model = GuiStateModel(applied={"initial_lots": 0.01, "cycle_mode": "mode1"})

    request = model.request_close_all()
    result = model.confirm_close_all(close_ok=False, delete_ok=True)

    assert request.requires_confirmation is True
    assert result.status == "cleanup_incomplete"


def test_gui_close_all_reports_incomplete_cleanup_when_delete_fails():
    model = GuiStateModel(applied={"initial_lots": 0.01, "cycle_mode": "mode1"})

    model.request_close_all()

    assert model.confirm_close_all(close_ok=True, delete_ok=False).status == "cleanup_incomplete"


def test_gui_close_all_reports_closed_when_both_cleanup_operations_succeed():
    model = GuiStateModel(applied={"initial_lots": 0.01, "cycle_mode": "mode1"})

    model.request_close_all()

    assert model.confirm_close_all(close_ok=True, delete_ok=True).status == "closed"


def test_gui_close_all_cannot_confirm_without_a_pending_request():
    model = GuiStateModel(applied={"initial_lots": 0.01, "cycle_mode": "mode1"})
    state_before = {
        "applied": dict(model.applied),
        "draft": dict(model.draft),
        "has_unapplied_changes": model.has_unapplied_changes,
        "close_all_requested": model.close_all_requested,
        "cleanup_state": model.cleanup_state,
    }

    result = model.confirm_close_all(close_ok=True, delete_ok=True)

    assert result.status == "confirmation_required"
    assert model.applied == state_before["applied"]
    assert model.draft == state_before["draft"]
    assert model.has_unapplied_changes is state_before["has_unapplied_changes"]
    assert model.close_all_requested is state_before["close_all_requested"]
    assert model.cleanup_state == state_before["cleanup_state"]

    state_before_request = {
        "applied": dict(model.applied),
        "draft": dict(model.draft),
        "has_unapplied_changes": model.has_unapplied_changes,
        "close_all_requested": model.close_all_requested,
        "cleanup_state": model.cleanup_state,
    }
    model.request_close_all()
    state_before_cancel = {
        "applied": dict(model.applied),
        "draft": dict(model.draft),
        "has_unapplied_changes": model.has_unapplied_changes,
        "close_all_requested": model.close_all_requested,
        "cleanup_state": model.cleanup_state,
    }
    assert state_before_cancel["close_all_requested"] is True

    cancel_result = model.cancel_close_all()

    assert cancel_result.status == "cancelled"
    assert model.applied == state_before_cancel["applied"]
    assert model.draft == state_before_cancel["draft"]
    assert model.has_unapplied_changes is state_before_cancel["has_unapplied_changes"]
    assert model.cleanup_state == state_before_cancel["cleanup_state"]
    assert model.close_all_requested is state_before_request["close_all_requested"]
