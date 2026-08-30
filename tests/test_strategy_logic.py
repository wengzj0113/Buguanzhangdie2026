from strategy_logic import Direction, StrategyModel


def test_idle_model_opens_configured_initial_order():
    model = StrategyModel(initial_direction=Direction.BUY, initial_lots=0.01, multiplier=2.0, distance=500, point=0.0001)

    actions = model.on_tick(bid=1.1000, ask=1.1002)

    assert actions == [
        {"kind": "market", "direction": Direction.BUY, "lots": 0.01},
        {"kind": "pending", "direction": Direction.SELL, "lots": 0.02, "price": 1.0502},
    ]


def test_reversal_is_opposite_and_doubles_from_the_current_volume():
    model = StrategyModel(initial_direction=Direction.SELL, initial_lots=0.01, multiplier=2.0, distance=500, point=0.0001)
    model.on_tick(bid=1.1000, ask=1.1002)
    model.fill_pending(entry_price=1.1500)

    actions = model.on_tick(bid=1.1500, ask=1.1502)

    assert actions == [
        {"kind": "pending", "direction": Direction.SELL, "lots": 0.04, "price": 1.1000},
    ]


def test_take_profit_ends_cycle_and_removes_reverse_pending():
    model = StrategyModel(initial_direction=Direction.BUY, initial_lots=0.01, multiplier=2.0, distance=500, point=0.0001)
    model.on_tick(bid=1.1000, ask=1.1002)

    actions = model.on_tick(bid=1.1502, ask=1.1504)

    assert actions == [{"kind": "cancel_pending"}]
    assert model.position is None
    assert model.pending is None


def test_stop_level_closes_current_trade_and_starts_the_next_doubled_trade():
    model = StrategyModel(initial_direction=Direction.BUY, initial_lots=0.01, multiplier=2.0, distance=500, point=0.0001)
    model.on_tick(bid=1.1000, ask=1.1002)

    actions = model.on_tick(bid=1.0502, ask=1.0504)

    assert actions == [
        {"kind": "close", "direction": Direction.BUY},
        {"kind": "market", "direction": Direction.SELL, "lots": 0.02},
        {"kind": "pending", "direction": Direction.BUY, "lots": 0.04, "price": 1.1002},
    ]
