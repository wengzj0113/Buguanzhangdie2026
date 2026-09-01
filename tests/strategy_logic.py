from dataclasses import dataclass
from enum import Enum


class Direction(Enum):
    BUY = "buy"
    SELL = "sell"


class CycleMode(Enum):
    MODE_1 = "mode1"
    MODE_2 = "mode2"
    MODE_3 = "mode3"


class DistanceMode(Enum):
    FIXED = "fixed"
    CANDLE_RANGE = "candle_range"


class OrderType(Enum):
    FORWARD = "forward"
    REVERSE = "reverse"


class TakeProfitMode(Enum):
    GRID = "grid"
    LINEAR = "linear"


@dataclass(frozen=True)
class GuiApplyResult:
    ok: bool


@dataclass(frozen=True)
class GuiCloseResult:
    status: str = ""
    requires_confirmation: bool = False


class GuiStateModel:
    def __init__(self, applied):
        self.applied = dict(applied)
        self.draft = dict(applied)
        self.paused_new_initial_entry = False
        self.should_force_market_order = False
        self.strategy_management_enabled = True
        self.pending_orders_are_preserved = True
        self._close_all_confirmation_requested = False
        self.cleanup_state = "idle"

    @property
    def has_unapplied_changes(self):
        return self.draft != self.applied

    def edit(self, key, value):
        self.draft[key] = value

    def apply(self):
        self.applied = dict(self.draft)
        return GuiApplyResult(ok=True)

    def pause_new_initial_entry(self):
        self.paused_new_initial_entry = True

    def resume_new_initial_entry(self):
        self.paused_new_initial_entry = False
        self.should_force_market_order = False

    def request_close_all(self):
        self._close_all_confirmation_requested = True
        return GuiCloseResult(requires_confirmation=True)

    @property
    def close_all_requested(self):
        return self._close_all_confirmation_requested

    def cancel_close_all(self):
        self._close_all_confirmation_requested = False
        return GuiCloseResult(status="cancelled")

    def confirm_close_all(self, close_ok, delete_ok):
        if not self._close_all_confirmation_requested:
            return GuiCloseResult(status="confirmation_required")
        self._close_all_confirmation_requested = False
        status = "closed" if close_ok and delete_ok else "cleanup_incomplete"
        self.cleanup_state = status
        return GuiCloseResult(status=status)


class ExecutionOwnershipRegistry:
    def __init__(self):
        self._owners = {}

    def acquire(self, scope, owner):
        current = self._owners.get(scope)
        if current is not None and current != owner:
            return False
        self._owners[scope] = owner
        return True

    def release(self, scope, owner):
        if self._owners.get(scope) == owner:
            del self._owners[scope]


@dataclass(frozen=True)
class PendingRecord:
    ticket: int
    kind: str
    direction: Direction
    lots: float
    price: float


@dataclass(frozen=True)
class PendingNormalization:
    keep_ticket: int | None
    delete_tickets: list[int]


def normalize_pending_records(records, tracked_ticket=None, tracked_ticket_filled=False,
                              kind=None, expected_direction=None, expected_lots=None,
                              expected_price=None):
    candidates = [record for record in records if kind is None or record.kind == kind]
    if tracked_ticket_filled:
        return PendingNormalization(
            tracked_ticket,
            sorted(record.ticket for record in candidates),
        )
    if not candidates:
        return PendingNormalization(None, [])
    if expected_direction is not None:
        matching = [
            record for record in candidates
            if record.direction is expected_direction
            and record.lots == expected_lots
            and record.price == expected_price
        ]
        keep_ticket = min((record.ticket for record in matching), default=None)
        return PendingNormalization(
            keep_ticket,
            sorted(record.ticket for record in candidates if record.ticket != keep_ticket),
        )
    tickets = {record.ticket for record in candidates}
    keep_ticket = tracked_ticket if tracked_ticket in tickets else min(tickets)
    return PendingNormalization(
        keep_ticket,
        sorted(ticket for ticket in tickets if ticket != keep_ticket),
    )


@dataclass(frozen=True)
class ExposureSnapshot:
    base_positions: int
    duplicate_grid_levels: int


@dataclass(frozen=True)
class ExposureDecision:
    pause_new_orders: bool
    cancel_pending: bool
    accumulate_loss_lots: bool


def exposure_guard(snapshot):
    duplicate_exposure = snapshot.base_positions > 1 or snapshot.duplicate_grid_levels > 0
    return ExposureDecision(
        pause_new_orders=duplicate_exposure,
        cancel_pending=duplicate_exposure,
        accumulate_loss_lots=not duplicate_exposure,
    )


@dataclass(frozen=True)
class PreparedTransition:
    transition_id: int
    direction: Direction
    lots: float


def recover_prepared_transition(transition, positions):
    matching = [
        position for position in positions
        if position["direction"] is transition.direction
        and position["lots"] == transition.lots
    ]
    if matching:
        return {"phase": "complete", "market_orders": []}
    return {
        "phase": "complete",
        "market_orders": [{
            "direction": transition.direction,
            "lots": transition.lots,
            "transition_id": transition.transition_id,
        }],
    }


def cycle_directions(initial_direction, cycle_mode):
    if cycle_mode is CycleMode.MODE_1:
        return ([Direction.BUY, Direction.SELL, Direction.SELL, Direction.BUY, Direction.SELL, Direction.SELL]
                if initial_direction is Direction.BUY
                else [Direction.SELL, Direction.BUY, Direction.BUY, Direction.SELL, Direction.BUY, Direction.BUY])
    if cycle_mode is CycleMode.MODE_2:
        return ([Direction.BUY, Direction.SELL, Direction.BUY, Direction.SELL, Direction.BUY, Direction.BUY]
                if initial_direction is Direction.BUY
                else [Direction.SELL, Direction.BUY, Direction.SELL, Direction.BUY, Direction.SELL, Direction.SELL])
    return ([Direction.BUY, Direction.SELL, Direction.BUY, Direction.BUY, Direction.SELL, Direction.BUY]
            if initial_direction is Direction.BUY
            else [Direction.SELL, Direction.BUY, Direction.SELL, Direction.SELL, Direction.BUY, Direction.SELL])


@dataclass
class Position:
    direction: Direction
    entry: float
    lots: float
    stop_loss: float
    take_profit: float


@dataclass
class Pending:
    direction: Direction
    lots: float
    price: float
    order_type: str
    distance_points: float
    kind: str = "reverse"
    level: int = 0


class StrategyModel:
    def __init__(self, initial_direction, cycle_mode, initial_lots, multiplier, distance, point,
                 distance_mode=DistanceMode.FIXED, min_range_points=500, max_range_points=1000,
                 order_type=OrderType.FORWARD, grid_count=0,
                 take_profit_mode=TakeProfitMode.GRID, initial_lot_multiplier=1.0,
                 start_minute=0, end_minute=24 * 60, market_order_failures=0,
                 max_reversals=5, korder_type=0):
        self.initial_direction = initial_direction
        self.cycle_mode = cycle_mode
        self.initial_lots = initial_lots
        self.multiplier = multiplier
        self.distance = distance
        self.point = point
        self.distance_mode = distance_mode
        self.min_range_points = min_range_points
        self.max_range_points = max_range_points
        self.order_type = order_type
        self.grid_count = grid_count
        self.take_profit_mode = take_profit_mode
        self.initial_lot_multiplier = initial_lot_multiplier
        self.start_minute = start_minute
        self.end_minute = end_minute
        self.market_order_failures = market_order_failures
        self.max_reversals = max_reversals
        self.korder_type = korder_type
        self.last_entry_candle_id = None
        self.position = None
        self.pending = None
        self.grid_pending = None
        self.current_index = 0
        self.reversal_count = 0
        self.sequence = cycle_directions(initial_direction, cycle_mode)
        self.cumulative_loss_lots = 0.0
        self.previous_grid_lots = None
        self.grid_lots = 0.0
        self.group_total_lots = 0.0
        self.grid_filled_levels = 0
        self.group_anchor_entry = None
        self.group_stop_points = None
        self.group_take_profit_points = None
        self.linear_extreme = None

    def _distance(self, candle_range_points):
        if self.distance_mode is DistanceMode.FIXED:
            return self.distance
        if candle_range_points is None or not (self.min_range_points <= candle_range_points <= self.max_range_points):
            return None
        return candle_range_points

    def _is_initial_entry_allowed(self, now_minute):
        if now_minute is None or self.start_minute == self.end_minute:
            return True
        if self.start_minute < self.end_minute:
            return self.start_minute <= now_minute < self.end_minute
        return now_minute >= self.start_minute or now_minute < self.end_minute

    def _active_distance(self):
        if self.group_take_profit_points is not None:
            return self.group_take_profit_points
        return self.distance

    def _levels(self, direction, entry, distance_points):
        distance = distance_points * self.point
        if direction is Direction.BUY:
            return round(entry - distance, 10), round(entry + distance, 10)
        return round(entry + distance, 10), round(entry - distance, 10)

    def _open(self, direction, entry, lots, distance_points, grid_lots=None):
        self.group_stop_points = distance_points
        self.group_take_profit_points = distance_points
        self.group_anchor_entry = entry
        self.linear_extreme = entry
        self.grid_filled_levels = 0
        self.grid_pending = None
        self.group_total_lots = lots
        if grid_lots is not None:
            self.grid_lots = grid_lots
        elif self.previous_grid_lots is None:
            self.grid_lots = lots
        else:
            self.grid_lots = self.previous_grid_lots * self.multiplier
        stop_loss, take_profit = self._levels(direction, entry, distance_points)
        self.position = Position(direction, entry, lots, stop_loss, take_profit)

    def _try_open(self, direction, entry, lots, distance_points):
        if self.market_order_failures > 0:
            self.market_order_failures -= 1
            return False
        self._open(direction, entry, lots, distance_points)
        return True

    def _reset_after_no_money(self):
        self.position = None
        self.pending = None
        self.grid_pending = None
        self.current_index = 0
        self.reversal_count = 0
        self.cumulative_loss_lots = 0.0
        self.previous_grid_lots = None
        self.grid_lots = 0.0
        self.group_total_lots = 0.0
        self.grid_filled_levels = 0
        self.group_anchor_entry = None
        self.group_stop_points = None
        self.group_take_profit_points = None
        self.linear_extreme = None

    def _reset_after_max_reversals(self):
        self._reset_after_no_money()

    def _update_linear_take_profit(self, bid, ask):
        if self.take_profit_mode is not TakeProfitMode.LINEAR or self.position is None:
            return False
        reference = ask if self.position.direction is Direction.BUY else bid
        if self.position.direction is Direction.BUY:
            if reference >= self.linear_extreme:
                return False
            self.linear_extreme = reference
            self.position.take_profit = round(
                self.linear_extreme + self.group_take_profit_points * self.point, 10,
            )
        else:
            if reference <= self.linear_extreme:
                return False
            self.linear_extreme = reference
            self.position.take_profit = round(
                self.linear_extreme - self.group_take_profit_points * self.point, 10,
            )
        return True

    def _next_pending(self, bid, ask, distance_points):
        if self.reversal_count >= self.max_reversals:
            self.pending = None
            return None
        direction = self.sequence[(self.current_index + 1) % len(self.sequence)]
        price = self.position.stop_loss
        if direction is Direction.BUY:
            order_type = "BUY_STOP" if price >= ask else "BUY_LIMIT"
        else:
            order_type = "SELL_STOP" if price <= bid else "SELL_LIMIT"
        next_group_lots = (self.cumulative_loss_lots + self.group_total_lots) * self.initial_lot_multiplier
        self.pending = Pending(direction, next_group_lots, price, order_type, distance_points)

    def _grid_pending_action(self):
        return {
            "kind": "grid_pending", "direction": self.grid_pending.direction,
            "lots": self.grid_pending.lots, "price": self.grid_pending.price,
            "order_type": self.grid_pending.order_type,
            "level": self.grid_pending.level,
        }

    def _ensure_grid_pending(self, bid, ask):
        if self.grid_count < 2 or self.grid_filled_levels >= self.grid_count - 1:
            self.grid_pending = None
            return None
        if self.grid_pending is not None:
            return self.grid_pending
        level = self.grid_filled_levels + 1
        price = self._grid_level(level)
        if self.position.direction is Direction.BUY:
            order_type = "BUY_STOP" if price >= ask else "BUY_LIMIT"
        else:
            order_type = "SELL_STOP" if price <= bid else "SELL_LIMIT"
        self.grid_pending = Pending(
            self.position.direction, self.grid_lots, price, order_type,
            self.group_stop_points, kind="grid", level=level,
        )
        return self.grid_pending

    def _pending_action(self):
        return {
            "kind": "pending", "direction": self.pending.direction,
            "lots": self.pending.lots, "price": self.pending.price,
            "order_type": self.pending.order_type,
        }

    def _grid_level(self, level):
        distance = self.group_stop_points * self.point * level / self.grid_count
        if self.position.direction is Direction.BUY:
            return round(self.group_anchor_entry - distance, 10)
        return round(self.group_anchor_entry + distance, 10)

    def fill_grid_pending(self, entry_price=None, bid=None, ask=None):
        pending = self.grid_pending
        if pending is None:
            return []
        self.grid_pending = None
        self.grid_filled_levels = pending.level
        self.group_total_lots += self.grid_lots
        self.position = Position(
            self.position.direction,
            self.position.entry,
            self.group_total_lots,
            self.position.stop_loss,
            self.position.take_profit,
        )
        entry = pending.price if entry_price is None else entry_price
        if bid is None:
            bid = entry - 0.0002 if self.position.direction is Direction.BUY else entry
        if ask is None:
            ask = entry if self.position.direction is Direction.BUY else entry + 0.0002
        if self.take_profit_mode is TakeProfitMode.GRID:
            _, moved_take_profit = self._levels(
                self.position.direction, entry, self.group_take_profit_points,
            )
            self.position.take_profit = moved_take_profit
        else:
            self._update_linear_take_profit(bid, ask)
        self._next_pending(bid, ask, self.group_stop_points)
        self._ensure_grid_pending(bid, ask)
        return [{
            "kind": "grid", "direction": self.position.direction,
            "lots": self.grid_lots, "price": entry,
        }]

    def _start_next_group(self, direction, entry, distance_points):
        self.cumulative_loss_lots += self.group_total_lots
        self.previous_grid_lots = self.grid_lots
        self.current_index = (self.current_index + 1) % len(self.sequence)
        self.reversal_count += 1
        next_lots = self.cumulative_loss_lots * self.initial_lot_multiplier
        if not self._try_open(direction, entry, next_lots, distance_points):
            self._reset_after_no_money()
            return False
        return True

    def _breakout_direction(self, bid, ask, previous_high, previous_low):
        if bid > previous_high:
            return Direction.BUY
        if ask < previous_low:
            return Direction.SELL
        return None

    def on_tick(self, bid, ask, candle_range_points=None, previous_high=None, previous_low=None,
                now_minute=None, candle_id=None):
        if self.position is None and self.pending is None:
            if not self._is_initial_entry_allowed(now_minute):
                return []
            distance_points = self._distance(candle_range_points)
            if distance_points is None:
                return []
            self.current_index = 0
            if self.distance_mode is DistanceMode.CANDLE_RANGE:
                if (self.korder_type == 0 and candle_id is not None
                        and self.last_entry_candle_id == candle_id):
                    return []
                if previous_high is None or previous_low is None:
                    return []
                breakout_direction = self._breakout_direction(
                    bid, ask, previous_high, previous_low,
                )
                if breakout_direction is None:
                    return []
                direction = (
                    breakout_direction
                    if self.order_type is OrderType.FORWARD
                    else (Direction.SELL if breakout_direction is Direction.BUY else Direction.BUY)
                )
                self.cycle_mode = (
                    CycleMode.MODE_1
                    if self.order_type is OrderType.FORWARD
                    else CycleMode.MODE_2
                )
                self.initial_direction = direction
                self.sequence = cycle_directions(direction, self.cycle_mode)
            else:
                direction = self.sequence[self.current_index]
            entry = ask if direction is Direction.BUY else bid
            opening_lots = self.initial_lots
            if not self._try_open(direction, entry, opening_lots, distance_points):
                self._reset_after_no_money()
                return [{"kind": "no_money"}]
            if self.distance_mode is DistanceMode.CANDLE_RANGE and self.korder_type == 0:
                self.last_entry_candle_id = candle_id
            self._next_pending(bid, ask, distance_points)
            actions = [{"kind": "market", "direction": direction, "lots": opening_lots}]
            if self.pending is not None:
                actions.append(self._pending_action())
            if self._ensure_grid_pending(bid, ask) is not None:
                actions.append(self._grid_pending_action())
            return actions

        if self.position is None:
            return []

        self._update_linear_take_profit(bid, ask)

        if ((self.position.direction is Direction.BUY and bid >= self.position.take_profit)
                or (self.position.direction is Direction.SELL and ask <= self.position.take_profit)):
            self.position = None
            self.pending = None
            self.grid_pending = None
            return [{"kind": "cancel_pending"}]

        if ((self.position.direction is Direction.BUY and bid <= self.position.stop_loss)
                or (self.position.direction is Direction.SELL and ask >= self.position.stop_loss)):
            old_direction = self.position.direction
            if self.reversal_count >= self.max_reversals:
                self._reset_after_max_reversals()
                return [{"kind": "reset_max_reversals"}]
            next_direction = self.sequence[(self.current_index + 1) % len(self.sequence)]
            next_entry = bid if next_direction is Direction.SELL else ask
            pending_distance = self.pending.distance_points if self.pending else None
            had_pending = self.pending is not None or self.grid_pending is not None
            self.pending = None
            self.grid_pending = None
            next_distance = pending_distance if pending_distance is not None else self._active_distance()
            if next_distance is None:
                self.position = None
                actions = []
                if had_pending:
                    actions.append({"kind": "delete_pending"})
                actions.append({"kind": "close", "direction": old_direction})
                self.position = None
                return actions
            if not self._start_next_group(next_direction, next_entry, next_distance):
                return [{"kind": "no_money"}]
            self._next_pending(bid, ask, next_distance)
            actions = []
            if had_pending:
                actions.append({"kind": "delete_pending"})
            actions.extend([
                {"kind": "close", "direction": old_direction},
                {"kind": "market", "direction": next_direction, "lots": self.position.lots},
            ])
            if self.pending is not None:
                actions.append(self._pending_action())
            if self._ensure_grid_pending(bid, ask) is not None:
                actions.append(self._grid_pending_action())
            return actions

        created_pending = self.pending is None and self.reversal_count < self.max_reversals
        if created_pending:
            distance_points = self._active_distance()
            self._next_pending(bid, ask, distance_points)
        self._ensure_grid_pending(bid, ask)
        return [self._pending_action()] if created_pending and self.pending is not None else []

        return []

    def fill_pending(self, entry_price):
        pending = self.pending
        self.pending = None
        self._start_next_group(pending.direction, entry_price, pending.distance_points)
        self._next_pending(
            entry_price - 0.0002 if pending.direction is Direction.BUY else entry_price,
            entry_price if pending.direction is Direction.BUY else entry_price + 0.0002,
            pending.distance_points,
        )
        self._ensure_grid_pending(
            entry_price - 0.0002 if pending.direction is Direction.BUY else entry_price,
            entry_price if pending.direction is Direction.BUY else entry_price + 0.0002,
        )

    def handle_stop_event(self, bid, ask, pending_filled=False):
        if pending_filled and self.pending is not None:
            pending = self.pending
            self.fill_pending(pending.price)
            return [{
                "kind": "pending_transition",
                "direction": self.position.direction,
                "lots": self.position.lots,
            }]
        return self.on_tick(bid, ask)


@dataclass
class ParallelOrderGroup:
    group_id: int
    strategy: StrategyModel

    def __getattr__(self, name):
        return getattr(self.strategy, name)


class ParallelStrategyModel:
    """Model the dynamic-mode multi-group entry and group-local lifecycle."""

    def __init__(self, initial_direction, cycle_mode, initial_lots, multiplier, distance, point,
                 distance_mode=DistanceMode.FIXED, min_range_points=500, max_range_points=1000,
                 order_type=OrderType.FORWARD, grid_count=0,
                 take_profit_mode=TakeProfitMode.GRID, initial_lot_multiplier=1.0,
                 start_minute=0, end_minute=24 * 60, market_order_failures=0,
                 max_reversals=5, korder_type=0, kline_enable_multiple=0):
        self._config = {
            "initial_direction": initial_direction,
            "cycle_mode": cycle_mode,
            "initial_lots": initial_lots,
            "multiplier": multiplier,
            "distance": distance,
            "point": point,
            "distance_mode": distance_mode,
            "min_range_points": min_range_points,
            "max_range_points": max_range_points,
            "order_type": order_type,
            "grid_count": grid_count,
            "take_profit_mode": take_profit_mode,
            "initial_lot_multiplier": initial_lot_multiplier,
            "start_minute": start_minute,
            "end_minute": end_minute,
            "market_order_failures": market_order_failures,
            "max_reversals": max_reversals,
            "korder_type": korder_type,
        }
        self.kline_enable_multiple = kline_enable_multiple
        self.korder_type = korder_type
        self.groups = []
        self._next_group_id = 1
        self._triggered_candles = set()

    @staticmethod
    def _with_group_id(actions, group_id):
        return [dict(action, group_id=group_id) for action in actions]

    def _new_group(self):
        strategy = StrategyModel(**self._config)
        group = ParallelOrderGroup(self._next_group_id, strategy)
        self._next_group_id += 1
        return group

    def _clear_all(self):
        self.groups.clear()
        self._next_group_id = 1
        self._triggered_candles.clear()

    def on_tick(self, bid, ask, candle_range_points=None, previous_high=None, previous_low=None,
                now_minute=None, candle_id=None):
        actions = []
        closed_group = False
        for group in list(self.groups):
            group_actions = group.strategy.on_tick(
                bid, ask, candle_range_points, previous_high, previous_low,
                now_minute, candle_id,
            )
            actions.extend(self._with_group_id(group_actions, group.group_id))
            if group.position is None:
                self.groups.remove(group)
                closed_group = True
            if any(action["kind"] in {"no_money", "reset_max_reversals"}
                   for action in group_actions):
                self._clear_all()
                return actions

        if closed_group:
            return actions
        if self.kline_enable_multiple == 0 and self.groups:
            return actions
        if now_minute is not None and self._config["start_minute"] != self._config["end_minute"]:
            start = self._config["start_minute"]
            end = self._config["end_minute"]
            allowed = start <= now_minute < end if start < end else now_minute >= start or now_minute < end
            if not allowed:
                return actions
        if candle_id is not None and self.korder_type == 0 and candle_id in self._triggered_candles:
            return actions

        group = self._new_group()
        group_actions = group.strategy.on_tick(
            bid, ask, candle_range_points, previous_high, previous_low,
            now_minute, candle_id,
        )
        if group.position is None:
            return actions
        self.groups.append(group)
        if candle_id is not None and self.korder_type == 0:
            self._triggered_candles.add(candle_id)
        actions.extend(self._with_group_id(group_actions, group.group_id))
        return actions

    def fill_pending(self, group_id, entry_price):
        for group in self.groups:
            if group.group_id == group_id:
                group.strategy.fill_pending(entry_price)
                return
        raise ValueError(f"unknown group_id: {group_id}")
