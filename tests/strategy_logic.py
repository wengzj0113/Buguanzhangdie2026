from dataclasses import dataclass
from enum import Enum


class Direction(Enum):
    BUY = "buy"
    SELL = "sell"


class CycleMode(Enum):
    MODE_1 = "mode1"
    MODE_2 = "mode2"
    MODE_3 = "mode3"


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


class StrategyModel:
    def __init__(self, initial_direction, cycle_mode, initial_lots, multiplier, distance, point):
        self.initial_direction = initial_direction
        self.cycle_mode = cycle_mode
        self.initial_lots = initial_lots
        self.multiplier = multiplier
        self.distance = distance
        self.point = point
        self.position = None
        self.pending = None
        self.current_index = 0
        self.sequence = cycle_directions(initial_direction, cycle_mode)

    def _levels(self, direction, entry):
        distance = self.distance * self.point
        if direction is Direction.BUY:
            return round(entry - distance, 10), round(entry + distance, 10)
        return round(entry + distance, 10), round(entry - distance, 10)

    def _open(self, direction, entry, lots):
        stop_loss, take_profit = self._levels(direction, entry)
        self.position = Position(direction, entry, lots, stop_loss, take_profit)

    def _next_pending(self, bid, ask):
        direction = self.sequence[(self.current_index + 1) % len(self.sequence)]
        price = self.position.stop_loss
        if direction is Direction.BUY:
            order_type = "BUY_STOP" if price >= ask else "BUY_LIMIT"
        else:
            order_type = "SELL_STOP" if price <= bid else "SELL_LIMIT"
        self.pending = Pending(direction, self.position.lots * self.multiplier, price, order_type)

    def _pending_action(self):
        return {
            "kind": "pending", "direction": self.pending.direction,
            "lots": self.pending.lots, "price": self.pending.price,
            "order_type": self.pending.order_type,
        }

    def on_tick(self, bid, ask):
        if self.position is None and self.pending is None:
            self.current_index = 0
            direction = self.sequence[self.current_index]
            entry = ask if direction is Direction.BUY else bid
            self._open(direction, entry, self.initial_lots)
            self._next_pending(bid, ask)
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
            next_direction = Direction.SELL if old_direction is Direction.BUY else Direction.BUY
            next_direction = self.sequence[(self.current_index + 1) % len(self.sequence)]
            next_entry = bid if next_direction is Direction.SELL else ask
            next_lots = self.position.lots * self.multiplier
            self.position = None
            self.pending = None
            self.current_index = (self.current_index + 1) % len(self.sequence)
            self._open(next_direction, next_entry, next_lots)
            self._next_pending(bid, ask)
            return [
                {"kind": "close", "direction": old_direction},
                {"kind": "market", "direction": next_direction, "lots": next_lots},
                self._pending_action(),
            ]

        if self.pending is None:
            self._next_pending(bid, ask)
            return [self._pending_action()]

        return []

    def fill_pending(self, entry_price):
        pending = self.pending
        self.pending = None
        self.current_index = (self.current_index + 1) % len(self.sequence)
        self._open(pending.direction, entry_price, pending.lots)
