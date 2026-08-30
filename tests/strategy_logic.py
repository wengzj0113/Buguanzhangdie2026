from dataclasses import dataclass
from enum import Enum


class Direction(Enum):
    BUY = "buy"
    SELL = "sell"


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


class StrategyModel:
    def __init__(self, initial_direction, initial_lots, multiplier, distance, point):
        self.initial_direction = initial_direction
        self.initial_lots = initial_lots
        self.multiplier = multiplier
        self.distance = distance
        self.point = point
        self.position = None
        self.pending = None

    def _levels(self, direction, entry):
        distance = self.distance * self.point
        if direction is Direction.BUY:
            return round(entry - distance, 10), round(entry + distance, 10)
        return round(entry + distance, 10), round(entry - distance, 10)

    def _open(self, direction, entry, lots):
        stop_loss, take_profit = self._levels(direction, entry)
        self.position = Position(direction, entry, lots, stop_loss, take_profit)

    def _opposite_pending(self):
        direction = Direction.SELL if self.position.direction is Direction.BUY else Direction.BUY
        self.pending = Pending(direction, self.position.lots * self.multiplier, self.position.stop_loss)

    def on_tick(self, bid, ask):
        if self.position is None and self.pending is None:
            direction = self.initial_direction
            entry = ask if direction is Direction.BUY else bid
            self._open(direction, entry, self.initial_lots)
            self._opposite_pending()
            return [
                {"kind": "market", "direction": direction, "lots": self.initial_lots},
                {"kind": "pending", "direction": self.pending.direction, "lots": self.pending.lots, "price": self.pending.price},
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
            next_entry = bid if next_direction is Direction.SELL else ask
            next_lots = self.position.lots * self.multiplier
            self.position = None
            self.pending = None
            self._open(next_direction, next_entry, next_lots)
            self._opposite_pending()
            return [
                {"kind": "close", "direction": old_direction},
                {"kind": "market", "direction": next_direction, "lots": next_lots},
                {"kind": "pending", "direction": self.pending.direction, "lots": self.pending.lots, "price": self.pending.price},
            ]

        if self.pending is None:
            self._opposite_pending()
            return [{"kind": "pending", "direction": self.pending.direction, "lots": self.pending.lots, "price": self.pending.price}]

        return []

    def fill_pending(self, entry_price):
        pending = self.pending
        self.pending = None
        self._open(pending.direction, entry_price, pending.lots)
