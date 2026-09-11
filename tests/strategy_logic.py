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
    AVERAGE_CANDLE_RANGE = "average_candle_range"


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


def average_candle_distances(candle_ranges, candle_count=20, stop_multiplier=2.0,
                             take_profit_multiplier=2.0):
    if candle_count <= 0 or stop_multiplier <= 0 or take_profit_multiplier <= 0:
        raise ValueError("average candle count and multipliers must be positive")
    if len(candle_ranges) < candle_count:
        raise ValueError("not enough completed candles")
    completed_ranges = list(candle_ranges[:candle_count])
    if any(candle_range <= 0 for candle_range in completed_ranges):
        raise ValueError("candle ranges must be positive")
    average_range_points = round(sum(completed_ranges) / candle_count)
    stop_points = round(average_range_points * stop_multiplier)
    take_profit_points = round(stop_points * take_profit_multiplier)
    if stop_points <= 0 or take_profit_points <= 0:
        raise ValueError("calculated distances must be positive")
    return stop_points, take_profit_points


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
    take_profit_distance_points: float | None = None
    side: str = "adverse"


class StrategyModel:
    def __init__(self, initial_direction, cycle_mode, initial_lots, multiplier, distance, point,
                 distance_mode=DistanceMode.FIXED, min_range_points=500, max_range_points=1000,
                 order_type=OrderType.FORWARD, grid_count=0,
                 take_profit_mode=TakeProfitMode.GRID, initial_lot_multiplier=1.0,
                 start_minute=0, end_minute=24 * 60, market_order_failures=0,
                 max_reversals=5, korder_type=0, average_candle_count=20,
                 average_stop_multiplier=2.0, average_take_profit_multiplier=2.0,
                 first_order_lot_type=2, first_order_mult=2.0,
                 favorable_grid_enable=0):
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
        self.average_candle_count = average_candle_count
        self.average_stop_multiplier = average_stop_multiplier
        self.average_take_profit_multiplier = average_take_profit_multiplier
        self.first_order_lot_type = first_order_lot_type
        self.first_order_mult = first_order_mult
        self.favorable_grid_enable = favorable_grid_enable
        self.last_entry_candle_id = None
        self.position = None
        self.pending = None
        self.initial_pending = []
        self.grid_pendings = {}
        self.favorable_grid_pendings = {}
        self.current_index = 0
        self.reversal_count = 0
        self.sequence = cycle_directions(initial_direction, cycle_mode)
        self.cumulative_loss_lots = 0.0
        self.group_first_lots = 0.0
        self.previous_grid_lots = None
        self.grid_lots = 0.0
        self.group_total_lots = 0.0
        self.grid_filled_levels = 0
        self.grid_filled_mask = 0
        self.favorable_grid_filled_mask = 0
        self.group_anchor_entry = None
        self.group_stop_points = None
        self.group_take_profit_points = None
        self.linear_extreme = None

    @property
    def grid_pending(self):
        if not self.grid_pendings:
            return None
        return self.grid_pendings[min(self.grid_pendings)]

    @grid_pending.setter
    def grid_pending(self, pending):
        self.grid_pendings.clear()
        if pending is not None:
            self.grid_pendings[pending.level] = pending

    @property
    def favorable_grid_pending(self):
        if not self.favorable_grid_pendings:
            return None
        return self.favorable_grid_pendings[min(self.favorable_grid_pendings)]

    def _distance(self, candle_range_points, average_candle_ranges=None):
        if self.distance_mode is DistanceMode.FIXED:
            return self.distance, self.distance
        if self.distance_mode is DistanceMode.AVERAGE_CANDLE_RANGE:
            if average_candle_ranges is None:
                return None
            try:
                return average_candle_distances(
                    average_candle_ranges, self.average_candle_count,
                    self.average_stop_multiplier,
                    self.average_take_profit_multiplier,
                )
            except ValueError:
                return None
        if candle_range_points is None or not (self.min_range_points <= candle_range_points <= self.max_range_points):
            return None
        return candle_range_points, candle_range_points

    def _is_initial_entry_allowed(self, now_minute):
        if now_minute is None or self.start_minute == self.end_minute:
            return True
        if self.start_minute < self.end_minute:
            return self.start_minute <= now_minute < self.end_minute
        return now_minute >= self.start_minute or now_minute < self.end_minute

    def _active_distances(self):
        if self.group_take_profit_points is not None:
            return self.group_stop_points, self.group_take_profit_points
        return self.distance, self.distance

    def _levels(self, direction, entry, distance_points):
        distance = distance_points * self.point
        if direction is Direction.BUY:
            return round(entry - distance, 10), round(entry + distance, 10)
        return round(entry + distance, 10), round(entry - distance, 10)

    def _open(self, direction, entry, lots, distance_points,
              take_profit_distance_points=None, grid_lots=None):
        self.group_stop_points = distance_points
        self.group_take_profit_points = (
            distance_points if take_profit_distance_points is None
            else take_profit_distance_points
        )
        self.group_anchor_entry = entry
        self.linear_extreme = entry
        self.grid_filled_levels = 0
        self.grid_filled_mask = 0
        self.favorable_grid_filled_mask = 0
        self.grid_pendings.clear()
        self.favorable_grid_pendings.clear()
        self.group_total_lots = lots
        self.group_first_lots = lots
        if grid_lots is not None:
            self.grid_lots = grid_lots
        elif self.previous_grid_lots is None:
            self.grid_lots = lots
        else:
            self.grid_lots = self.previous_grid_lots * self.multiplier
        stop_loss, _ = self._levels(direction, entry, distance_points)
        _, take_profit = self._levels(direction, entry, self.group_take_profit_points)
        self.position = Position(direction, entry, lots, stop_loss, take_profit)

    def _try_open(self, direction, entry, lots, distance_points,
                  take_profit_distance_points=None):
        if self.market_order_failures > 0:
            self.market_order_failures -= 1
            return False
        self._open(direction, entry, lots, distance_points, take_profit_distance_points)
        return True

    def _reset_after_no_money(self):
        self.position = None
        self.pending = None
        self.initial_pending = []
        self.grid_pendings.clear()
        self.favorable_grid_pendings.clear()
        self.current_index = 0
        self.reversal_count = 0
        self.cumulative_loss_lots = 0.0
        self.previous_grid_lots = None
        self.grid_lots = 0.0
        self.group_total_lots = 0.0
        self.group_first_lots = 0.0
        self.grid_filled_levels = 0
        self.grid_filled_mask = 0
        self.favorable_grid_filled_mask = 0
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

    def _next_pending(self, bid, ask, distance_points, take_profit_distance_points=None):
        if self.reversal_count >= self.max_reversals:
            self.pending = None
            return None
        direction = self.sequence[(self.current_index + 1) % len(self.sequence)]
        price = self.position.stop_loss
        if direction is Direction.BUY:
            order_type = "BUY_STOP" if price >= ask else "BUY_LIMIT"
        else:
            order_type = "SELL_STOP" if price <= bid else "SELL_LIMIT"
        next_group_lots = self._next_first_order_lots()
        self.pending = Pending(
            direction, next_group_lots, price, order_type, distance_points,
            take_profit_distance_points=take_profit_distance_points,
        )

    def _next_first_order_lots(self):
        if self.first_order_lot_type == 2:
            return self.group_first_lots * self.first_order_mult
        return (self.cumulative_loss_lots + self.group_total_lots) * self.initial_lot_multiplier

    def _grid_pending_action(self, pending=None):
        if pending is None:
            pending = self.grid_pending
        return {
            "kind": ("favorable_grid_pending"
                      if pending.side == "favorable" else "grid_pending"),
            "direction": pending.direction,
            "lots": pending.lots, "price": pending.price,
            "order_type": pending.order_type,
            "level": pending.level,
        }

    def _ensure_grid_pending(self, bid, ask):
        if self.grid_count < 2:
            self.grid_pendings.clear()
            self.favorable_grid_pendings.clear()
            return []
        created = []
        for level in range(1, self.grid_count):
            if self.grid_filled_mask & (1 << (level - 1)):
                continue
            if level in self.grid_pendings:
                continue
            price = self._grid_level(level)
            if self.position.direction is Direction.BUY:
                order_type = "BUY_STOP" if price >= ask else "BUY_LIMIT"
            else:
                order_type = "SELL_STOP" if price <= bid else "SELL_LIMIT"
            pending = Pending(
                self.position.direction, self.grid_lots, price, order_type,
                self.group_stop_points, kind="grid", level=level,
            )
            self.grid_pendings[level] = pending
            created.append(pending)
        if self.favorable_grid_enable != 1:
            self.favorable_grid_pendings.clear()
            return created
        for level in range(1, self.grid_count):
            if self.favorable_grid_filled_mask & (1 << (level - 1)):
                continue
            if level in self.favorable_grid_pendings:
                continue
            price = self._favorable_grid_level(level)
            if self.position.direction is Direction.BUY:
                order_type = "BUY_STOP" if price >= ask else "BUY_LIMIT"
            else:
                order_type = "SELL_STOP" if price <= bid else "SELL_LIMIT"
            pending = Pending(
                self.position.direction, self.grid_lots, price, order_type,
                self.group_stop_points, kind="grid", level=level,
                side="favorable",
            )
            self.favorable_grid_pendings[level] = pending
            created.append(pending)
        return created

    def _pending_action(self):
        return {
            "kind": "pending", "direction": self.pending.direction,
            "lots": self.pending.lots, "price": self.pending.price,
            "order_type": self.pending.order_type,
        }

    def _initial_pending_directions(self):
        if self.order_type is OrderType.FORWARD:
            return Direction.BUY, Direction.SELL
        return Direction.SELL, Direction.BUY

    @staticmethod
    def _initial_pending_order_type(direction, price, bid, ask):
        if direction is Direction.BUY:
            return "BUY_STOP" if price >= ask else "BUY_LIMIT"
        return "SELL_STOP" if price <= bid else "SELL_LIMIT"

    @staticmethod
    def _initial_pending_action(pending):
        return {
            "kind": "initial_pending", "direction": pending.direction,
            "lots": pending.lots, "price": pending.price,
            "order_type": pending.order_type,
        }

    def _grid_level(self, level):
        distance = self.group_stop_points * self.point * level / self.grid_count
        if self.position.direction is Direction.BUY:
            return round(self.group_anchor_entry - distance, 10)
        return round(self.group_anchor_entry + distance, 10)

    def _favorable_grid_level(self, level):
        distance = self.group_stop_points * self.point * level / self.grid_count
        if self.position.direction is Direction.BUY:
            return round(self.group_anchor_entry + distance, 10)
        return round(self.group_anchor_entry - distance, 10)

    def fill_grid_pending(self, entry_price=None, bid=None, ask=None, level=None,
                          favorable=False):
        pendings = self.favorable_grid_pendings if favorable else self.grid_pendings
        if level is None:
            pending = self.favorable_grid_pending if favorable else self.grid_pending
        else:
            pending = pendings.get(level)
        if pending is None:
            return []
        pendings.pop(pending.level, None)
        if favorable:
            self.favorable_grid_filled_mask |= 1 << (pending.level - 1)
            self.favorable_grid_filled_levels = self.favorable_grid_filled_mask.bit_count()
        else:
            self.grid_filled_mask |= 1 << (pending.level - 1)
            self.grid_filled_levels = self.grid_filled_mask.bit_count()
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
        self._next_pending(
            bid, ask, self.group_stop_points, self.group_take_profit_points,
        )
        self._ensure_grid_pending(bid, ask)
        return [{
            "kind": "favorable_grid" if favorable else "grid",
            "direction": self.position.direction,
            "lots": self.grid_lots, "price": entry,
        }]

    def fill_favorable_grid_pending(self, entry_price=None, bid=None, ask=None, level=None):
        return self.fill_grid_pending(entry_price, bid, ask, level, favorable=True)

    def _start_next_group(self, direction, entry, distance_points,
                          take_profit_distance_points=None):
        self.cumulative_loss_lots += self.group_total_lots
        self.previous_grid_lots = self.grid_lots
        self.current_index = (self.current_index + 1) % len(self.sequence)
        self.reversal_count += 1
        next_lots = (
            self.group_first_lots * self.first_order_mult
            if self.first_order_lot_type == 2
            else self.cumulative_loss_lots * self.initial_lot_multiplier
        )
        if not self._try_open(direction, entry, next_lots, distance_points,
                              take_profit_distance_points):
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
                now_minute=None, candle_id=None, average_candle_ranges=None):
        if self.position is None and self.pending is None:
            if self.initial_pending:
                return []
            if not self._is_initial_entry_allowed(now_minute):
                return []
            distances = self._distance(candle_range_points, average_candle_ranges)
            if distances is None:
                return []
            stop_points, take_profit_points = distances
            self.current_index = 0
            if self.distance_mode is DistanceMode.CANDLE_RANGE:
                if (self.korder_type == 0 and candle_id is not None
                        and self.last_entry_candle_id == candle_id):
                    return []
                if previous_high is None or previous_low is None:
                    return []
                if self.korder_type == 0:
                    high_direction, low_direction = self._initial_pending_directions()
                    self.initial_pending = [
                        Pending(
                            high_direction, self.initial_lots, previous_high,
                            self._initial_pending_order_type(
                                high_direction, previous_high, bid, ask,
                            ), stop_points, kind="initial_pending",
                        ),
                        Pending(
                            low_direction, self.initial_lots, previous_low,
                            self._initial_pending_order_type(
                                low_direction, previous_low, bid, ask,
                            ), stop_points, kind="initial_pending",
                        ),
                    ]
                    self.last_entry_candle_id = candle_id
                    return [
                        self._initial_pending_action(pending)
                        for pending in self.initial_pending
                    ]
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
            if not self._try_open(direction, entry, opening_lots, stop_points,
                                  take_profit_points):
                self._reset_after_no_money()
                return [{"kind": "no_money"}]
            if self.distance_mode is DistanceMode.CANDLE_RANGE and self.korder_type == 0:
                self.last_entry_candle_id = candle_id
            self._next_pending(bid, ask, stop_points, take_profit_points)
            actions = [{"kind": "market", "direction": direction, "lots": opening_lots}]
            if self.pending is not None:
                actions.append(self._pending_action())
            grid_pendings = self._ensure_grid_pending(bid, ask)
            actions.extend(self._grid_pending_action(pending)
                           for pending in grid_pendings)
            return actions

        if self.position is None:
            return []

        self._update_linear_take_profit(bid, ask)

        if ((self.position.direction is Direction.BUY and bid >= self.position.take_profit)
                or (self.position.direction is Direction.SELL and ask <= self.position.take_profit)):
            self.position = None
            self.pending = None
            self.grid_pendings.clear()
            self.favorable_grid_pendings.clear()
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
            pending_take_profit_distance = (
                self.pending.take_profit_distance_points if self.pending else None
            )
            had_pending = (self.pending is not None or bool(self.grid_pendings)
                           or bool(self.favorable_grid_pendings))
            self.pending = None
            self.grid_pendings.clear()
            self.favorable_grid_pendings.clear()
            next_distances = (
                (pending_distance, pending_take_profit_distance)
                if pending_distance is not None else self._active_distances()
            )
            if next_distances is None:
                self.position = None
                actions = []
                if had_pending:
                    actions.append({"kind": "delete_pending"})
                actions.append({"kind": "close", "direction": old_direction})
                self.position = None
                return actions
            next_stop_points, next_take_profit_points = next_distances
            if not self._start_next_group(
                    next_direction, next_entry, next_stop_points,
                    next_take_profit_points):
                return [{"kind": "no_money"}]
            self._next_pending(bid, ask, next_stop_points, next_take_profit_points)
            actions = []
            if had_pending:
                actions.append({"kind": "delete_pending"})
            actions.extend([
                {"kind": "close", "direction": old_direction},
                {"kind": "market", "direction": next_direction, "lots": self.position.lots},
            ])
            if self.pending is not None:
                actions.append(self._pending_action())
            grid_pendings = self._ensure_grid_pending(bid, ask)
            actions.extend(self._grid_pending_action(pending)
                           for pending in grid_pendings)
            return actions

        created_pending = self.pending is None and self.reversal_count < self.max_reversals
        if created_pending:
            stop_points, take_profit_points = self._active_distances()
            self._next_pending(bid, ask, stop_points, take_profit_points)
        self._ensure_grid_pending(bid, ask)
        return [self._pending_action()] if created_pending and self.pending is not None else []

        return []

    def fill_pending(self, entry_price):
        pending = self.pending
        self.pending = None
        self._start_next_group(
            pending.direction, entry_price, pending.distance_points,
            pending.take_profit_distance_points,
        )
        self._next_pending(
            entry_price - 0.0002 if pending.direction is Direction.BUY else entry_price,
            entry_price if pending.direction is Direction.BUY else entry_price + 0.0002,
            pending.distance_points, pending.take_profit_distance_points,
        )
        self._ensure_grid_pending(
            entry_price - 0.0002 if pending.direction is Direction.BUY else entry_price,
            entry_price if pending.direction is Direction.BUY else entry_price + 0.0002,
        )

    def fill_initial_pending(self, direction, entry_price):
        pending = next(
            (pending for pending in self.initial_pending
             if pending.direction is direction),
            None,
        )
        if pending is None:
            return []
        other_direction = (
            Direction.SELL if direction is Direction.BUY else Direction.BUY
        )
        self.initial_pending = []
        self.initial_direction = direction
        self.cycle_mode = (
            CycleMode.MODE_1
            if self.order_type is OrderType.FORWARD
            else CycleMode.MODE_2
        )
        self.sequence = cycle_directions(direction, self.cycle_mode)
        self.current_index = 0
        self._open(
            direction, entry_price, pending.lots, pending.distance_points,
            pending.take_profit_distance_points,
        )
        bid = entry_price - 0.0002 if direction is Direction.BUY else entry_price
        ask = entry_price if direction is Direction.BUY else entry_price + 0.0002
        self._next_pending(
            bid, ask, pending.distance_points, pending.take_profit_distance_points,
        )
        self._ensure_grid_pending(bid, ask)
        actions = [{
            "kind": "cancel_initial_pending", "direction": other_direction,
        }]
        if self.pending is not None:
            actions.append(self._pending_action())
        actions.extend(self._grid_pending_action(pending)
                       for pending in self.grid_pendings.values())
        return actions

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
                 max_reversals=5, korder_type=0, kline_enable_multiple=0,
                 average_candle_count=20, average_stop_multiplier=2.0,
                 average_take_profit_multiplier=2.0):
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
            "average_candle_count": average_candle_count,
            "average_stop_multiplier": average_stop_multiplier,
            "average_take_profit_multiplier": average_take_profit_multiplier,
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
                now_minute=None, candle_id=None, average_candle_ranges=None):
        actions = []
        closed_group = False
        for group in list(self.groups):
            group_actions = group.strategy.on_tick(
                bid, ask, candle_range_points, previous_high, previous_low,
                now_minute, candle_id, average_candle_ranges,
            )
            actions.extend(self._with_group_id(group_actions, group.group_id))
            if group.position is None and not group.initial_pending:
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
            now_minute, candle_id, average_candle_ranges,
        )
        if group.position is None and not group.initial_pending:
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

    def fill_initial_pending(self, group_id, direction, entry_price):
        for group in self.groups:
            if group.group_id == group_id:
                actions = group.strategy.fill_initial_pending(direction, entry_price)
                return self._with_group_id(actions, group_id)
        raise ValueError(f"unknown group_id: {group_id}")
