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


class StrategyModel:
    def __init__(self, initial_direction, cycle_mode, initial_lots, multiplier, distance, point,
                 distance_mode=DistanceMode.FIXED, min_range_points=500, max_range_points=1000,
                 order_type=OrderType.FORWARD):
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
        self.position = None
        self.pending = None
        self.current_index = 0
        self.sequence = cycle_directions(initial_direction, cycle_mode)

    def _distance(self, candle_range_points):
        if self.distance_mode is DistanceMode.FIXED:
            return self.distance
        if candle_range_points is None or not (self.min_range_points <= candle_range_points <= self.max_range_points):
            return None
        return candle_range_points

    def _active_distance(self):
        if self.distance_mode is DistanceMode.FIXED:
            return self.distance
        return abs(self.position.take_profit - self.position.stop_loss) / (2 * self.point)

    def _levels(self, direction, entry, distance_points):
        distance = distance_points * self.point
        if direction is Direction.BUY:
            return round(entry - distance, 10), round(entry + distance, 10)
        return round(entry + distance, 10), round(entry - distance, 10)

    def _open(self, direction, entry, lots, distance_points):
        stop_loss, take_profit = self._levels(direction, entry, distance_points)
        self.position = Position(direction, entry, lots, stop_loss, take_profit)

    def _next_pending(self, bid, ask, distance_points):
        direction = self.sequence[(self.current_index + 1) % len(self.sequence)]
        price = self.position.stop_loss
        if direction is Direction.BUY:
            order_type = "BUY_STOP" if price >= ask else "BUY_LIMIT"
        else:
            order_type = "SELL_STOP" if price <= bid else "SELL_LIMIT"
        self.pending = Pending(direction, self.position.lots * self.multiplier, price, order_type, distance_points)

    def _pending_action(self):
        return {
            "kind": "pending", "direction": self.pending.direction,
            "lots": self.pending.lots, "price": self.pending.price,
            "order_type": self.pending.order_type,
        }

    def _breakout_direction(self, bid, ask, previous_high, previous_low):
        if bid > previous_high:
            return Direction.BUY
        if ask < previous_low:
            return Direction.SELL
        return None

    def on_tick(self, bid, ask, candle_range_points=None, previous_high=None, previous_low=None):
        if self.position is None and self.pending is None:
            distance_points = self._distance(candle_range_points)
            if distance_points is None:
                return []
            self.current_index = 0
            if self.distance_mode is DistanceMode.CANDLE_RANGE:
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
            self._open(direction, entry, self.initial_lots, distance_points)
            self._next_pending(bid, ask, distance_points)
            return [
                {"kind": "market", "direction": direction, "lots": self.initial_lots},
                self._pending_action(),
            ]

        if self.position is None:
            return []

        if ((self.position.direction is Direction.BUY and bid >= self.position.take_profit)
                or (self.position.direction is Direction.SELL and ask <= self.position.take_profit)):
            self.position = None
            self.pending = None
            return [{"kind": "cancel_pending"}]

        if ((self.position.direction is Direction.BUY and bid <= self.position.stop_loss)
                or (self.position.direction is Direction.SELL and ask >= self.position.stop_loss)):
            old_direction = self.position.direction
            next_direction = self.sequence[(self.current_index + 1) % len(self.sequence)]
            next_entry = bid if next_direction is Direction.SELL else ask
            next_lots = self.position.lots * self.multiplier
            next_distance = self.pending.distance_points if self.pending else self._active_distance()
            self.position = None
            self.pending = None
            self.current_index = (self.current_index + 1) % len(self.sequence)
            if next_distance is None:
                return [{"kind": "close", "direction": old_direction}]
            self._open(next_direction, next_entry, next_lots, next_distance)
            self._next_pending(bid, ask, next_distance)
            return [
                {"kind": "close", "direction": old_direction},
                {"kind": "market", "direction": next_direction, "lots": next_lots},
                self._pending_action(),
            ]

        if self.pending is None:
            distance_points = self._active_distance()
            self._next_pending(bid, ask, distance_points)
            return [self._pending_action()]

        return []

    def fill_pending(self, entry_price):
        pending = self.pending
        self.pending = None
        self.current_index = (self.current_index + 1) % len(self.sequence)
        self._open(pending.direction, entry_price, pending.lots, pending.distance_points)
