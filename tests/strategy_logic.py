from dataclasses import dataclass
from datetime import timedelta
from enum import Enum
import math


class Direction(Enum):
    BUY = "buy"
    SELL = "sell"


def basket_directions(first_direction, basket_count=1):
    """Resolve one original basket or a pair of opposite-direction baskets."""
    if basket_count not in (1, 2, 3):
        raise ValueError("basket count must be 1, 2 or 3")
    if first_direction not in (Direction.BUY, Direction.SELL):
        raise ValueError("first direction must be BUY or SELL")
    if basket_count == 1:
        return (first_direction,)
    opposite = Direction.SELL if first_direction is Direction.BUY else Direction.BUY
    return first_direction, opposite


@dataclass(frozen=True)
class InitialBasketLeg:
    group_id: int
    direction: Direction
    lots: float
    stop_points: int
    take_profit_points: int


@dataclass(frozen=True)
class InitialBasketLaunch:
    event_id: int
    primary: InitialBasketLeg
    opposite: InitialBasketLeg | None


def plan_initial_basket_launch(event_id, primary_group_id, opposite_group_id,
                               direction, basket_count, lots,
                               stop_points, take_profit_points,
                               visible_group_ids=()):
    """Return only missing legs, and never return the opposite before primary exists."""
    directions = basket_directions(direction, basket_count)
    if event_id <= 0 or primary_group_id <= 0 or lots <= 0:
        raise ValueError("event ID, primary group ID, and lots must be positive")
    if basket_count in (2, 3) and opposite_group_id <= 0:
        raise ValueError("opposite group ID must be positive for two baskets")
    if stop_points <= 0 or take_profit_points <= 0:
        raise ValueError("stop and take-profit distances must be positive")
    visible = set(visible_group_ids)
    primary = InitialBasketLeg(primary_group_id, directions[0], lots,
                               stop_points, take_profit_points)
    opposite = None
    if basket_count in (2, 3):
        opposite = InitialBasketLeg(opposite_group_id, directions[1], lots,
                                     stop_points, take_profit_points)
    missing = []
    if primary.group_id not in visible:
        missing.append(primary)
    elif opposite is not None and opposite.group_id not in visible:
        missing.append(opposite)
    return InitialBasketLaunch(event_id, primary, opposite), tuple(missing)


class FirstDirectionMode(Enum):
    PRESET = "preset"
    BOLLINGER = "bollinger"


def resolve_first_direction(mode, preset_direction, current_price, bollinger_middle):
    """Resolve a market entry direction without opening on a middle-band tie."""
    if mode is FirstDirectionMode.PRESET:
        return preset_direction
    if mode is not FirstDirectionMode.BOLLINGER:
        raise ValueError(f"unsupported first direction mode: {mode}")
    if current_price > bollinger_middle:
        return Direction.BUY
    if current_price < bollinger_middle:
        return Direction.SELL
    return None


def bollinger_touch_direction(price, upper, lower, point, order_type=0):
    """Map outer-band touches through the shared forward/reverse order setting."""
    if not all(math.isfinite(value) for value in (price, upper, lower, point)):
        return None
    if point <= 0 or upper <= lower or order_type not in (0, 1):
        return None
    tolerance = point * 0.5
    if price >= upper - tolerance:
        return Direction.BUY if order_type == 0 else Direction.SELL
    if price <= lower + tolerance:
        return Direction.SELL if order_type == 0 else Direction.BUY
    return None


def bollinger_stop_distance_points(upper, lower, point, min_points=None, max_points=None, percent=25.0):
    """Return the MT-style rounded percentage of band width, or None if invalid."""
    if not all(math.isfinite(value) for value in (upper, lower, point, percent)):
        return None

    if point <= 0 or upper <= lower or percent <= 0:
        return None
    distance_points = (upper - lower) / point * percent / 100.0
    if not math.isfinite(distance_points) or distance_points > 2147483647:
        return None
    rounded = math.floor(distance_points + 0.5)
    if rounded <= 0:
        return None
    if min_points is not None and rounded < min_points:
        return None
    if max_points is not None and rounded > max_points:
        return None
    return rounded


class CycleMode(Enum):
    MODE_1 = "mode1"
    MODE_2 = "mode2"
    MODE_3 = "mode3"
    MODE_4 = "mode4"


class BoxRangeMode(Enum):
    ROLLING = "rolling"
    DAILY_SESSION = "daily_session"


class DistanceMode(Enum):
    FIXED = "fixed"
    CANDLE_RANGE = "candle_range"
    AVERAGE_CANDLE_RANGE = "average_candle_range"
    LONG_CANDLE_MARKET = "long_candle_market"
    BOLLINGER_RANGE = "bollinger_range"
    ZIGZAG_RANGE = "zigzag_range"
    BOX_RANGE = "box_range"
    BOX_BREAKOUT = "box_breakout"


@dataclass(frozen=True)
class BoxBreakoutConfig:
    lookback_bars: int = 60
    atr_period: int = 14
    touch_atr_multiplier: float = 0.2
    min_upper_touches: int = 2
    min_lower_touches: int = 2
    min_round_trips: int = 2
    min_touch_spacing_bars: int = 3
    min_width_points: int = 500
    max_width_points: int = 1000
    breakout_buffer_atr_multiplier: float = 0.2
    order_type: object = "forward"


@dataclass
class ConfirmedBox:
    upper: float
    lower: float
    width_points: int
    atr: float
    breakout_buffer: float
    upper_touches: int
    lower_touches: int
    round_trips: int
    confirmation_time: object
    order_type: object = "forward"
    last_processed_time: object = None
    upper_breakout_count: int = 0
    lower_breakout_count: int = 0
    age_bars: int = 0
    pending_signal_id: str = ""
    pending_direction: object = None
    pending_signal_time: object = None
    request_state: str = "idle"


def _valid_box_config(config):
    integer_fields = (
        config.lookback_bars, config.atr_period, config.min_upper_touches,
        config.min_lower_touches, config.min_round_trips,
        config.min_touch_spacing_bars, config.min_width_points,
        config.max_width_points,
    )
    numeric_fields = (config.touch_atr_multiplier,
                      config.breakout_buffer_atr_multiplier)
    return (
        all(isinstance(value, int) and not isinstance(value, bool) and value > 0
            for value in integer_fields)
        and config.max_width_points >= config.min_width_points
        and all(isinstance(value, (int, float)) and math.isfinite(value) and value > 0
                for value in numeric_fields)
    )


def _box_rates_values(rate):
    try:
        if len(rate) != 5:
            return None
        time, open_price, high, low, close = rate
        values = tuple(float(value) for value in (open_price, high, low, close))
    except (TypeError, ValueError, OverflowError):
        return None
    if (any(not math.isfinite(value) for value in values)
            or high < low or open_price < low or open_price > high
            or close < low or close > high):
        return None
    return time, values


def _wilder_atr(rates, period):
    true_ranges = []
    previous_close = None
    for rate in rates:
        parsed = _box_rates_values(rate)
        if parsed is None:
            return None
        _, (_, high, low, close) = parsed
        true_range = high - low if previous_close is None else max(
            high - low, abs(high - previous_close), abs(low - previous_close),
        )
        true_ranges.append(true_range)
        previous_close = close
    atr_values = [None] * len(true_ranges)
    if len(true_ranges) < period:
        return atr_values
    atr = sum(true_ranges[:period]) / period
    atr_values[period - 1] = atr
    for index in range(period, len(true_ranges)):
        atr = ((atr * (period - 1)) + true_ranges[index]) / period
        atr_values[index] = atr
    return atr_values


def _round_trip_count(events):
    count = 0
    index = 2
    while index < len(events):
        if events[index] == events[index - 2] and events[index] != events[index - 1]:
            count += 1
            index += 2
        else:
            index += 1
    return count


def find_confirmed_box(rates, config, point):
    """Confirm a range from chronological closed OHLC bars and frozen ATR."""
    if (not _valid_box_config(config) or not isinstance(point, (int, float))
            or not math.isfinite(point) or point <= 0):
        return None
    try:
        rates = list(rates)
        parsed_rates = [_box_rates_values(rate) for rate in rates]
    except TypeError:
        return None
    if len(parsed_rates) < config.lookback_bars or any(rate is None for rate in parsed_rates):
        return None
    atr_values = _wilder_atr(rates, config.atr_period)
    if atr_values is None:
        return None
    start = len(parsed_rates) - config.lookback_bars
    window = parsed_rates[start:]
    upper = max(parsed[1][1] for parsed in window)
    lower = min(parsed[1][2] for parsed in window)
    width_points = int(math.floor(((upper - lower) / point) + 0.5))
    if not (config.min_width_points <= width_points <= config.max_width_points):
        return None

    events = []
    last_touch = {"upper": None, "lower": None}
    upper_touches = 0
    lower_touches = 0
    for index in range(start, len(parsed_rates)):
        atr = atr_values[index]
        if atr is None or not math.isfinite(atr) or atr <= 0:
            continue
        _, (_, high, low, _) = parsed_rates[index]
        tolerance = config.touch_atr_multiplier * atr
        upper_hit = upper - high <= tolerance
        lower_hit = low - lower <= tolerance
        if upper_hit and lower_hit:
            continue
        side = "upper" if upper_hit else "lower" if lower_hit else None
        if side is None:
            continue
        previous_index = last_touch[side]
        if previous_index is not None and index - previous_index < config.min_touch_spacing_bars:
            continue
        last_touch[side] = index
        events.append("U" if side == "upper" else "L")
        if side == "upper":
            upper_touches += 1
        else:
            lower_touches += 1

    round_trips = _round_trip_count(events)
    if (upper_touches < config.min_upper_touches
            or lower_touches < config.min_lower_touches
            or round_trips < config.min_round_trips):
        return None
    confirmation_atr = atr_values[-1]
    if confirmation_atr is None or confirmation_atr <= 0:
        return None
    return ConfirmedBox(
        upper=upper, lower=lower, width_points=width_points,
        atr=confirmation_atr,
        breakout_buffer=config.breakout_buffer_atr_multiplier * confirmation_atr,
        upper_touches=upper_touches, lower_touches=lower_touches,
        round_trips=round_trips, confirmation_time=parsed_rates[-1][0],
        order_type=config.order_type,
        last_processed_time=parsed_rates[-1][0],
    )


def advance_box_breakout(box_state, closed_bar, point):
    """Advance a frozen box once for a closed (time, close) bar."""
    try:
        bar_time, close = closed_bar
        close = float(close)
    except (TypeError, ValueError, OverflowError):
        return "wait"
    if (not isinstance(point, (int, float)) or not math.isfinite(point) or point <= 0
            or not math.isfinite(close)):
        return "wait"
    if bar_time == box_state.last_processed_time:
        return "wait"
    box_state.last_processed_time = bar_time
    box_state.age_bars += 1
    upper_line = box_state.upper + box_state.breakout_buffer
    lower_line = box_state.lower - box_state.breakout_buffer
    if close > upper_line:
        box_state.upper_breakout_count += 1
        box_state.lower_breakout_count = 0
        if box_state.upper_breakout_count >= 2:
            reverse = box_state.order_type in ("reverse", OrderType.REVERSE)
            return "sell" if reverse else "buy"
        return "wait"
    if close < lower_line:
        box_state.lower_breakout_count += 1
        box_state.upper_breakout_count = 0
        if box_state.lower_breakout_count >= 2:
            reverse = box_state.order_type in ("reverse", OrderType.REVERSE)
            return "buy" if reverse else "sell"
        return "wait"
    had_count = box_state.upper_breakout_count or box_state.lower_breakout_count
    box_state.upper_breakout_count = 0
    box_state.lower_breakout_count = 0
    return "reset" if had_count else "wait"



def _clock_minutes(value):
    try:
        hour_text, minute_text = value.split(":", 1)
        hour = int(hour_text)
        minute = int(minute_text)
    except (AttributeError, TypeError, ValueError):
        return None
    if hour < 0 or hour > 23 or minute < 0 or minute > 59:
        return None
    return hour * 60 + minute


def box_range_window(now, mode, lookback_hours=12,
                     session_start="01:00", session_end="12:00"):
    """Return the rolling or latest completed daily box window."""
    if not hasattr(now, "tzinfo"):
        return None
    if mode in (BoxRangeMode.ROLLING, "rolling"):
        if not isinstance(lookback_hours, int) or not 1 <= lookback_hours <= 720:
            return None
        return now - timedelta(hours=lookback_hours), now
    if mode not in (BoxRangeMode.DAILY_SESSION, "daily_session"):
        return None
    start_minutes = _clock_minutes(session_start)
    end_minutes = _clock_minutes(session_end)
    if start_minutes is None or end_minutes is None or start_minutes == end_minutes:
        return None
    midnight = now.replace(hour=0, minute=0, second=0, microsecond=0)
    start = midnight + timedelta(minutes=start_minutes)
    end = midnight + timedelta(minutes=end_minutes)
    if end <= start:
        end += timedelta(days=1)
    if now < end:
        start -= timedelta(days=1)
        end -= timedelta(days=1)
    return start, end


def box_range_points(rates, start, end, point, min_points, max_points):
    """Return rounded M1 high-low points when the sampled range is valid."""
    if (not hasattr(start, "tzinfo") or not hasattr(end, "tzinfo")
            or end <= start or not math.isfinite(point) or point <= 0
            or not isinstance(min_points, int) or min_points <= 0
            or not isinstance(max_points, int) or max_points < min_points):
        return None
    highs = []
    lows = []
    for rate in rates:
        try:
            bar_time, high, low = rate
        except (TypeError, ValueError):
            return None
        if not hasattr(bar_time, "tzinfo"):
            return None
        if not start <= bar_time < end:
            continue
        if (not math.isfinite(high) or not math.isfinite(low)
                or high <= 0 or low <= 0 or high < low):
            return None
        highs.append(high)
        lows.append(low)
    if not highs:
        return None
    height_points = math.floor((max(highs) - min(lows)) / point + 0.5)
    if min_points <= height_points <= max_points:
        return height_points
    return None


class OrderType(Enum):
    FORWARD = "forward"
    REVERSE = "reverse"


class TakeProfitMode(Enum):
    GRID = "grid"
    LINEAR = "linear"


@dataclass(frozen=True)
class ReversalLotPlan:
    status: str
    lots: tuple[float, ...]


def plan_reversal_lots(total_lots, max_single_lot=100.0, group_restart_lot=200.0):
    """Return the executable reversal legs before broker step normalization."""
    if total_lots <= 0:
        raise ValueError("reversal lots must be positive")
    if total_lots >= group_restart_lot:
        return ReversalLotPlan("restart_group", ())
    if total_lots <= max_single_lot:
        return ReversalLotPlan("single", (total_lots,))
    half = total_lots / 2.0
    return ReversalLotPlan("split", (half, half))


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
    if cycle_mode is CycleMode.MODE_3:
        return ([Direction.BUY, Direction.SELL, Direction.BUY, Direction.BUY, Direction.SELL, Direction.BUY]
                if initial_direction is Direction.BUY
                else [Direction.SELL, Direction.BUY, Direction.SELL, Direction.SELL, Direction.BUY, Direction.SELL])
    return ([Direction.BUY, Direction.SELL, Direction.SELL, Direction.BUY,
             Direction.BUY, Direction.SELL, Direction.SELL]
            if initial_direction is Direction.BUY
            else [Direction.SELL, Direction.BUY, Direction.BUY, Direction.SELL,
                  Direction.SELL, Direction.BUY, Direction.BUY])


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


def zigzag_distances(pivots, point, min_points, max_points, stop_percent,
                     take_profit_multiplier):
    """Use the first swing behind the standard indicator's three mutable extrema."""
    values = (point, min_points, max_points, stop_percent, take_profit_multiplier)
    if (not all(math.isfinite(value) for value in values) or point <= 0
            or min_points <= 0 or max_points < min_points
            or stop_percent <= 0 or take_profit_multiplier <= 0
            or len(pivots) < 5):
        return None
    (first_kind, first_price), (second_kind, second_price) = pivots[3:5]
    if (first_kind not in ("high", "low") or second_kind not in ("high", "low")
            or first_kind == second_kind
            or not all(math.isfinite(price) and price > 0
                       for price in (first_price, second_price))
            or (first_kind == "high" and first_price <= second_price)
            or (first_kind == "low" and first_price >= second_price)):
        return None
    raw = abs(first_price - second_price) / point
    if not math.isfinite(raw) or raw > 2_147_483_647:
        return None
    raw_points = math.floor(raw + 0.5)
    if raw_points < min_points or raw_points > max_points:
        return None
    stop = raw_points * stop_percent / 100
    if not math.isfinite(stop) or stop > 2_147_483_647:
        return None
    stop_points = math.floor(stop + 0.5)
    take_profit = stop_points * take_profit_multiplier
    if not math.isfinite(take_profit) or take_profit > 2_147_483_647:
        return None
    take_profit_points = math.floor(take_profit + 0.5)
    if stop_points <= 0 or take_profit_points <= 0:
        return None
    return stop_points, take_profit_points


def zigzag_breakout_direction(pivots, bid, ask, point, min_points, max_points,
                              order_type=OrderType.FORWARD):
    """Return direction only after price clears the stable swing by its height."""
    if zigzag_distances(pivots, point, min_points, max_points, 100, 1) is None:
        return None
    if not all(math.isfinite(value) for value in (bid, ask, point)) or point <= 0:
        return None
    older, newer = pivots[3], pivots[4]
    swing_points = zigzag_distances(
        pivots, point, min_points, max_points, 100, 1,
    )[0]
    swing = swing_points * point
    upper = max(older[1], newer[1]) + swing
    lower = min(older[1], newer[1]) - swing
    tolerance = point * 0.5
    if bid >= upper - tolerance:
        breakout = Direction.BUY
    elif ask <= lower + tolerance:
        breakout = Direction.SELL
    else:
        return None
    if order_type is OrderType.REVERSE:
        return Direction.SELL if breakout is Direction.BUY else Direction.BUY
    return breakout


def average_double_candle_signal(k1_open, k1_close, k1_range_points, prior_ranges,
                                comparison_count=20, distance_percent=50,
                                trigger_multiplier=2, order_type=0):
    """Reference for a configurable K1/mean trigger and signal direction mapping."""
    if (not isinstance(comparison_count, int) or not 1 <= comparison_count <= 10000
            or len(prior_ranges) < comparison_count):
        return None
    values = [k1_open, k1_close, k1_range_points, distance_percent, trigger_multiplier]
    ranges = list(prior_ranges[:comparison_count])
    if any(value is None or not math.isfinite(value) or value <= 0
           for value in values + ranges):
        return None
    average = sum(ranges) / comparison_count
    if not math.isfinite(average) or k1_range_points + 1e-6 < trigger_multiplier * average:
        return None
    distance = k1_range_points * distance_percent / 100
    if not math.isfinite(distance) or distance > 2147483647:
        return None
    distance = math.floor(distance + 0.5)
    if distance < 1 or k1_open == k1_close:
        return None
    direction = Direction.BUY if k1_close > k1_open else Direction.SELL
    if order_type == 1:
        direction = Direction.SELL if direction is Direction.BUY else Direction.BUY
    elif order_type != 0:
        return None
    return direction, distance


def long_candle_direction(k1_open, k1_close, k1_range_points, prior_ranges,
                          comparison_count=20):
    """Return K1's body direction when K1 is at least as long as K2..K21."""
    if (comparison_count <= 0 or k1_open is None or k1_close is None
            or k1_range_points is None or len(prior_ranges) < comparison_count):
        return None
    if k1_range_points <= 0:
        return None
    ranges = list(prior_ranges[:comparison_count])
    if any(candle_range <= 0 for candle_range in ranges):
        return None
    if k1_range_points < max(ranges):
        return None
    if k1_close > k1_open:
        return Direction.BUY
    if k1_close < k1_open:
        return Direction.SELL
    return None


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


def is_operation_window_active(now_minute, start_minute, end_minute):
    if (start_minute, end_minute) == (0, 0):
        return False
    if start_minute == end_minute:
        return True
    if start_minute < end_minute:
        return start_minute <= now_minute < end_minute
    return now_minute >= start_minute or now_minute < end_minute


def is_initial_entry_allowed(now_minute, operation_windows):
    return now_minute is None or any(
        is_operation_window_active(now_minute, start, end)
        for start, end in operation_windows
    )


def is_initial_spread_allowed(spread_points, maximum_points):
    if spread_points < 0 or maximum_points < 0:
        return False
    return maximum_points == 0 or spread_points <= maximum_points


def initial_pending_spread_action(has_pending, signal_valid, spread_points, maximum_points):
    allowed = is_initial_spread_allowed(spread_points, maximum_points)
    if has_pending and not allowed:
        return "cancel"
    if not has_pending and signal_valid and allowed:
        return "place"
    if has_pending:
        return "keep"
    return "wait"


class StrategyModel:
    def __init__(self, initial_direction, cycle_mode, initial_lots, multiplier, distance, point,
                 distance_mode=DistanceMode.FIXED, min_range_points=500, max_range_points=1000,
                 order_type=OrderType.FORWARD, grid_count=0,
                 take_profit_mode=TakeProfitMode.GRID, initial_lot_multiplier=1.0,
                 start_minute=0, end_minute=24 * 60, market_order_failures=0,
                 operation_windows=None,
                 max_reversals=5, korder_type=0, average_candle_count=20,
                 average_stop_multiplier=2.0, average_take_profit_multiplier=2.0,
                 first_order_lot_type=2, first_order_mult=2.0,
                 stop_first_order_lots=0.01,
                 box_height_points=None, box_min_height_points=500,
                 box_max_height_points=1000,
                 box_breakout_config=None,

                 favorable_grid_enable=0, dynamic_stop_loss_enable=0,
                 zigzag_min_points=100, zigzag_max_points=10000,
                 zigzag_stop_percent=100.0, zigzag_take_profit_multiplier=1.0):
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
        self.operation_windows = tuple(operation_windows or (
            (start_minute, end_minute), (0, 0), (0, 0),
        ))
        self.market_order_failures = market_order_failures
        self.max_reversals = max_reversals
        self.korder_type = korder_type
        self.average_candle_count = average_candle_count
        self.average_stop_multiplier = average_stop_multiplier
        self.average_take_profit_multiplier = average_take_profit_multiplier
        self.first_order_lot_type = first_order_lot_type
        self.first_order_mult = first_order_mult
        self.stop_first_order_lots = stop_first_order_lots
        self.box_height_points = box_height_points
        self.box_min_height_points = box_min_height_points
        self.box_max_height_points = box_max_height_points
        self.box_breakout_config = box_breakout_config or BoxBreakoutConfig()
        self.box_state = None
        self.box_consumed_signal_id = ""

        self.favorable_grid_enable = favorable_grid_enable
        self.dynamic_stop_loss_enable = dynamic_stop_loss_enable
        self.zigzag_min_points = zigzag_min_points
        self.zigzag_max_points = zigzag_max_points
        self.zigzag_stop_percent = zigzag_stop_percent
        self.zigzag_take_profit_multiplier = zigzag_take_profit_multiplier
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

    def _distance(self, candle_range_points, average_candle_ranges=None,
                  zigzag_pivots=None):
        if self.distance_mode is DistanceMode.FIXED:
            return self.distance, self.distance
        if self.distance_mode is DistanceMode.LONG_CANDLE_MARKET:
            return self.distance, self.distance
        if self.distance_mode is DistanceMode.ZIGZAG_RANGE:
            return zigzag_distances(
                zigzag_pivots or [], self.point, self.zigzag_min_points,
                self.zigzag_max_points, self.zigzag_stop_percent,
                self.zigzag_take_profit_multiplier,
            )
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
        if self.distance_mode is DistanceMode.BOX_RANGE:
            height = self.box_height_points
            if (height is None or not isinstance(height, int)
                    or height < self.box_min_height_points
                    or height > self.box_max_height_points):
                return None
            return height, height
        if self.distance_mode is DistanceMode.BOX_BREAKOUT:
            if self.box_state is None:
                return None
            return self.box_state.width_points, self.box_state.width_points

        if candle_range_points is None or not (self.min_range_points <= candle_range_points <= self.max_range_points):
            return None
        return candle_range_points, candle_range_points

    def _is_initial_entry_allowed(self, now_minute):
        return is_initial_entry_allowed(now_minute, self.operation_windows)

    def _active_distances(self):
        if self.group_take_profit_points is not None:
            return self.group_stop_points, self.group_take_profit_points
        return self.distance, self.distance

    def _levels(self, direction, entry, distance_points):
        distance = distance_points * self.point
        if direction is Direction.BUY:
            return round(entry - distance, 10), round(entry + distance, 10)
        return round(entry + distance, 10), round(entry - distance, 10)

    def _group_stop_loss(self):
        base_stop = self._levels(
            self.position.direction, self.group_anchor_entry, self.group_stop_points,
        )[0]
        if self.dynamic_stop_loss_enable != 1 or self.grid_count < 2:
            return base_stop
        favorable_mask = self.favorable_grid_filled_mask
        if favorable_mask == 0:
            return base_stop
        highest_level = max(
            level for level in range(1, self.grid_count)
            if favorable_mask & (1 << (level - 1))
        )
        spacing = self.group_stop_points * self.point / self.grid_count
        offset = highest_level * spacing
        return round(
            base_stop + offset if self.position.direction is Direction.BUY
            else base_stop - offset,
            10,
        )

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
        if (self.first_order_lot_type == 2
                and self.first_order_mult == self.multiplier):
            self.grid_lots = lots
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
        if self.first_order_lot_type == 3:
            return self.stop_first_order_lots
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
        if self.dynamic_stop_loss_enable == 1:
            stop_loss = self._group_stop_loss()
            if self.position.direction is Direction.BUY:
                self.grid_pendings = {
                    level: pending for level, pending in self.grid_pendings.items()
                    if pending.price > stop_loss + self.point * 0.5
                }
            else:
                self.grid_pendings = {
                    level: pending for level, pending in self.grid_pendings.items()
                    if pending.price < stop_loss - self.point * 0.5
                }
        created = []
        for level in range(1, self.grid_count):
            if self.grid_filled_mask & (1 << (level - 1)):
                continue
            price = self._grid_level(level)
            stop_loss = self._group_stop_loss()
            if self.dynamic_stop_loss_enable == 1 and (
                (self.position.direction is Direction.BUY
                 and price <= stop_loss + self.point * 0.5)
                or (self.position.direction is Direction.SELL
                    and price >= stop_loss - self.point * 0.5)
            ):
                continue
            if level in self.grid_pendings:
                continue
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
        self.position.stop_loss = self._group_stop_loss()
        entry = pending.price if entry_price is None else entry_price
        if bid is None:
            bid = entry - 0.0002 if self.position.direction is Direction.BUY else entry
        if ask is None:
            ask = entry if self.position.direction is Direction.BUY else entry + 0.0002
        if self.take_profit_mode is TakeProfitMode.GRID and not favorable:
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
        if self.first_order_lot_type == 3:
            next_lots = self.stop_first_order_lots
        elif self.first_order_lot_type == 2:
            next_lots = self.group_first_lots * self.first_order_mult
        else:
            next_lots = self.cumulative_loss_lots * self.initial_lot_multiplier
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

    def save_box_state(self):
        return None if self.box_state is None else dict(vars(self.box_state))

    def restore_box_state(self, snapshot):
        self.box_state = None if snapshot is None else ConfirmedBox(**snapshot)

    def _box_breakout_tick(self, bid, ask, now_minute, box_rates, box_closed_bar):
        if self.box_state is None:
            if box_rates is None:
                return []
            self.box_state = find_confirmed_box(
                box_rates, self.box_breakout_config, self.point,
            )
            return []

        box = self.box_state
        if box.pending_signal_id:
            if box_closed_bar is not None:
                try:
                    bar_time, _ = box_closed_bar
                except (TypeError, ValueError):
                    bar_time = box.last_processed_time
                if bar_time != box.last_processed_time:
                    box.last_processed_time = bar_time
                    box.age_bars += 1
                    if box.age_bars >= self.box_breakout_config.lookback_bars:
                        self.box_state = None
                        return []
            direction = box.pending_direction
        else:
            if box_closed_bar is None:
                return []
            signal = advance_box_breakout(box, box_closed_bar, self.point)
            direction = (Direction.BUY if signal == "buy" else
                         Direction.SELL if signal == "sell" else None)
            if direction is not None:
                signal_time = box_closed_bar[0]
                signal_id = f"{signal_time}:{direction.value}"
                if signal_id == self.box_consumed_signal_id:
                    return []
                box.pending_signal_id = signal_id
                box.pending_direction = direction
                box.pending_signal_time = signal_time
                box.request_state = "ready"
            elif box.age_bars >= self.box_breakout_config.lookback_bars:
                self.box_state = None
                return []
            else:
                return []

        if not self._is_initial_entry_allowed(now_minute):
            return []
        stop_points = take_profit_points = box.width_points
        entry = ask if direction is Direction.BUY else bid
        if not self._try_open(direction, entry, self.initial_lots,
                              stop_points, take_profit_points):
            box.request_state = "retry"
            return [{"kind": "market_retry", "signal_id": box.pending_signal_id,
                     "direction": direction}]
        box.request_state = "consumed"
        self.box_consumed_signal_id = box.pending_signal_id
        self.current_index = 0
        self.initial_direction = direction
        self.sequence = cycle_directions(direction, self.cycle_mode)
        self._next_pending(bid, ask, stop_points, take_profit_points)
        self.box_state = None
        actions = [{"kind": "market", "direction": direction,
                    "lots": self.initial_lots,
                    "signal_id": self.box_consumed_signal_id}]
        if self.pending is not None:
            actions.append(self._pending_action())
        actions.extend(self._grid_pending_action(pending)
                       for pending in self._ensure_grid_pending(bid, ask))
        return actions


    def on_tick(self, bid, ask, candle_range_points=None, previous_high=None, previous_low=None,
                now_minute=None, candle_id=None, average_candle_ranges=None,
                k1_open=None, k1_close=None, long_candle_ranges=None,
                zigzag_pivots=None, box_rates=None, box_closed_bar=None):
        if (self.distance_mode is DistanceMode.BOX_BREAKOUT
                and self.position is None and self.pending is None):
            return self._box_breakout_tick(
                bid, ask, now_minute, box_rates, box_closed_bar,
            )

        if self.position is None and self.pending is None:
            if self.initial_pending:
                return []
            if not self._is_initial_entry_allowed(now_minute):
                return []
            distances = self._distance(candle_range_points, average_candle_ranges,
                                       zigzag_pivots)
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
            elif self.distance_mode is DistanceMode.ZIGZAG_RANGE:
                direction = zigzag_breakout_direction(
                    zigzag_pivots or [], bid, ask, self.point,
                    self.zigzag_min_points, self.zigzag_max_points,
                    self.order_type,
                )
                if direction is None:
                    return []
                self.initial_direction = direction
                self.sequence = cycle_directions(direction, self.cycle_mode)
            elif self.distance_mode is DistanceMode.LONG_CANDLE_MARKET:
                direction = long_candle_direction(
                    k1_open, k1_close, candle_range_points,
                    long_candle_ranges or [],
                )
                if direction is None:
                    return []
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
                 operation_windows=None,
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
            "operation_windows": tuple(operation_windows or (
                (start_minute, end_minute), (0, 0), (0, 0),
            )),
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
        if not is_initial_entry_allowed(now_minute, self._config["operation_windows"]):
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


def bollinger_expansion_signal(width, prior_widths, comparison_count=20,
                               distance_percent=25, distance_mode=0,
                               fixed_stop=500, fixed_take_profit=500,
                               trigger_multiplier=2):
    import math
    if not 1 <= comparison_count <= 10000 or len(prior_widths) < comparison_count:
        return None
    values = [width, trigger_multiplier, *prior_widths[:comparison_count]]
    if any(not math.isfinite(value) or value <= 0 for value in values):
        return None
    average = sum(prior_widths[:comparison_count]) / comparison_count
    if not math.isfinite(average) or width + 0.000001 < trigger_multiplier * average:
        return None
    if distance_mode == 1:
        if any(not isinstance(v, int) or not 1 <= v <= 2147483647 for v in (fixed_stop, fixed_take_profit)):
            return None
        return fixed_stop, fixed_take_profit
    if distance_mode != 0 or not math.isfinite(distance_percent) or distance_percent <= 0:
        return None
    points = width * distance_percent / 100
    if not math.isfinite(points) or points > 2147483647 or math.floor(points + .5) < 1:
        return None
    return (math.floor(points + .5),) * 2


def mode3_companion_action(*, mode, peer_state, primary_confirmed,
                           primary_alive, protected, source_stage_matches,
                           event_consumed, reset, child_status,
                           actual_direction, actual_first_lots):
    if mode != 3 or reset or event_consumed:
        return ("none", None, 0.0)
    if not primary_alive or not source_stage_matches:
        return ("cancel", None, 0.0)
    if peer_state == "unknown" or not primary_confirmed or not protected:
        return ("wait", None, 0.0)
    if peer_state != "ended":
        return ("none", None, 0.0)
    if child_status == "confirmed":
        return ("adopt", None, 0.0)
    if child_status in ("in_flight", "unknown", "partial"):
        return ("reconcile", None, 0.0)
    if child_status != "absent":
        return ("none", None, 0.0)
    if actual_direction not in (Direction.BUY, Direction.SELL):
        raise ValueError("invalid actual first-order direction")
    if not math.isfinite(actual_first_lots) or actual_first_lots <= 0:
        raise ValueError("invalid actual first-order volume")
    opposite = Direction.SELL if actual_direction is Direction.BUY else Direction.BUY
    return ("create", opposite, actual_first_lots)
