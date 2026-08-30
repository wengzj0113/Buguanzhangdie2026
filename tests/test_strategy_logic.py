import pytest

from strategy_logic import CycleMode, Direction, DistanceMode, OrderType, StrategyModel, cycle_directions


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


def test_mode_one_buy_uses_sell_stop_then_sell_limit_for_the_two_sell_steps():
    model = StrategyModel(Direction.BUY, CycleMode.MODE_1, 0.01, 2.0, 500, 0.0001)

    first_actions = model.on_tick(bid=1.1000, ask=1.1002)
    second_actions = model.on_tick(bid=1.0502, ask=1.0504)

    assert first_actions[0] == {"kind": "market", "direction": Direction.BUY, "lots": 0.01}
    assert first_actions[1] == {
        "kind": "pending", "direction": Direction.SELL, "lots": 0.02,
        "price": 1.0502, "order_type": "SELL_STOP",
    }
    assert second_actions[0] == {"kind": "close", "direction": Direction.BUY}
    assert second_actions[1] == {"kind": "market", "direction": Direction.SELL, "lots": 0.02}
    assert second_actions[2] == {
        "kind": "pending", "direction": Direction.SELL, "lots": 0.04,
        "price": 1.1002, "order_type": "SELL_LIMIT",
    }


def test_mode_two_buy_reaches_buy_buy_and_wraps_after_six_orders():
    model = StrategyModel(Direction.BUY, CycleMode.MODE_2, 0.01, 2.0, 500, 0.0001)
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
        directions.append(actions[1]["direction"])

    assert directions == [
        Direction.BUY, Direction.SELL, Direction.BUY,
        Direction.SELL, Direction.BUY, Direction.BUY,
    ]
    assert model.current_index == 5

    position = model.position
    actions = model.on_tick(bid=position.stop_loss, ask=position.stop_loss + 0.0002)
    assert actions[1]["direction"] == Direction.BUY
    assert model.current_index == 0


def test_custom_multiplier_is_applied_to_each_new_order():
    model = StrategyModel(Direction.SELL, CycleMode.MODE_1, 0.03, 3.0, 500, 0.0001)

    first_actions = model.on_tick(bid=1.1000, ask=1.1002)
    next_actions = model.on_tick(bid=1.1500, ask=1.1502)

    assert first_actions[1]["lots"] == 0.09
    assert next_actions[1]["lots"] == 0.09
    assert next_actions[2]["lots"] == 0.27


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
    )

    actions = model.on_tick(
        bid=1.1010, ask=1.1012, candle_range_points=range_points,
        previous_high=1.1000, previous_low=1.0400,
    )

    assert actions[0] == {"kind": "market", "direction": Direction.BUY, "lots": 0.01}
    assert model.position.stop_loss == pytest.approx(1.1002 - range_points * 0.0001)
    assert model.position.take_profit == pytest.approx(1.1002 + range_points * 0.0001)


def test_fixed_distance_mode_ignores_an_invalid_candle_range():
    model = StrategyModel(
        Direction.SELL, CycleMode.MODE_1, 0.01, 2.0, 500, 0.0001,
        distance_mode=DistanceMode.FIXED,
        min_range_points=500,
        max_range_points=1000,
    )

    actions = model.on_tick(bid=1.1000, ask=1.1002, candle_range_points=300)

    assert actions[0] == {"kind": "market", "direction": Direction.SELL, "lots": 0.01}


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
    )

    actions = model.on_tick(
        bid=1.0700, ask=1.0702, candle_range_points=600,
        previous_high=1.1000, previous_low=1.0400,
    )

    assert actions == []
    assert model.position is None
    assert model.pending is None


def test_candle_mode_ignores_user_first_direction_and_cycle_mode_inputs():
    forward_model = StrategyModel(
        Direction.SELL, CycleMode.MODE_2, 0.01, 2.0, 500, 0.0001,
        distance_mode=DistanceMode.CANDLE_RANGE,
        min_range_points=500,
        max_range_points=1000,
        order_type=OrderType.FORWARD,
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
        max_range_points=1000,
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

    assert model.position.lots == pytest.approx(0.16)
    assert actions[0] == {
        "kind": "pending", "direction": Direction.BUY, "lots": 0.32,
        "price": model.position.stop_loss, "order_type": "BUY_LIMIT",
    }

    position = model.position
    stop_actions = model.on_tick(
        bid=position.stop_loss,
        ask=position.stop_loss + 0.0002,
        candle_range_points=300,
        previous_high=1.1000, previous_low=1.0700,
    )
    assert stop_actions[1] == {
        "kind": "market", "direction": Direction.BUY, "lots": 0.32,
    }


def test_candle_distance_is_locked_until_take_profit_starts_a_new_group():
    model = StrategyModel(
        Direction.BUY, CycleMode.MODE_1, 0.01, 2.0, 500, 0.0001,
        distance_mode=DistanceMode.CANDLE_RANGE,
        min_range_points=500,
        max_range_points=1000,
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
    assert model.position.stop_loss == pytest.approx(1.1002 - 900 * 0.0001)
    assert model.position.take_profit == pytest.approx(1.1002 + 900 * 0.0001)
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
    model = StrategyModel(initial_direction, cycle_mode, 0.01, 2.0, 500, 0.0001)
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
        opened.append((actions[1]["direction"], actions[1]["lots"]))
        pending_types.append(actions[2]["order_type"])

    expected = cycle_directions(initial_direction, cycle_mode)
    assert [direction for direction, _ in opened] == expected
    assert [lots for _, lots in opened] == pytest.approx([0.01, 0.02, 0.04, 0.08, 0.16, 0.32])
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
