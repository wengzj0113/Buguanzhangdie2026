from pathlib import Path

import pytest

from strategy_logic import (
    CycleMode, Direction, DistanceMode, ExecutionOwnershipRegistry,
    ExposureSnapshot, GuiStateModel, OrderType, ParallelStrategyModel, PendingRecord,
    PreparedTransition, StrategyModel, TakeProfitMode, exposure_guard,
    normalize_pending_records, recover_prepared_transition, cycle_directions,
)


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
                          grid_count=2)

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
        grid_count=2, initial_lot_multiplier=1.5,
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


def test_first_group_grid_add_uses_initial_lot_and_moves_tp_and_next_group_lot():
    model = StrategyModel(
        Direction.BUY, CycleMode.MODE_1, 0.01, 2.0, 500, 0.0001,
        grid_count=5,
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
        grid_count=5,
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


def test_candle_order_mode_zero_allows_only_one_initial_entry_per_current_candle():
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
    model.on_tick(
        bid=model.position.take_profit, ask=model.position.take_profit + 0.0002,
        candle_range_points=600, previous_high=1.1000, previous_low=1.0400,
        candle_id=10,
    )

    same_candle = model.on_tick(
        bid=1.2000, ask=1.2002, candle_range_points=600,
        previous_high=1.1000, previous_low=1.0400, candle_id=10,
    )
    next_candle = model.on_tick(
        bid=1.2000, ask=1.2002, candle_range_points=600,
        previous_high=1.1000, previous_low=1.0400, candle_id=11,
    )

    assert first[0]["kind"] == "market"
    assert same_candle == []
    assert next_candle[0]["kind"] == "market"


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
        max_reversals=6,
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
    model = StrategyModel(Direction.BUY, CycleMode.MODE_1, 0.01, 2.0, 500, 0.0001)
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


def dynamic_parallel_model(multiple, korder_type=0):
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
    assert "NormalizeSingleGroupPending(true," in source
    assert "if(HasDuplicateSingleGroupExposure())" in source

    ensure_next = source.split("void EnsureNextPending", 1)[1].split("bool Transition", 1)[0]
    assert "if(!NormalizeSingleGroupPending(false," in ensure_next
    assert "DeleteAllPending();" not in ensure_next

    ensure_grid = source.split("void EnsureGridPending", 1)[1].split(
        "void EnsureNextPending", 1,
    )[0]
    assert "if(!NormalizeSingleGroupPending(true," in ensure_grid

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
