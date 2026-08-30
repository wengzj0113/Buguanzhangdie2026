#property strict
#property version   "1.00"
#property description "No Matter Rise Fall - selectable six-order cycle strategy"

#include <Trade/Trade.mqh>

enum FirstDirection
  {
   FIRST_BUY = 0,
   FIRST_SELL = 1
  };

enum CycleMode
  {
   CYCLE_MODE_1 = 0,
   CYCLE_MODE_2 = 1,
   CYCLE_MODE_3 = 2
  };

enum DistanceMode
  {
   DISTANCE_FIXED = 0,
   DISTANCE_CANDLE_RANGE = 1
  };

enum OrderTypeMode
  {
   ORDERTYPE_FORWARD = 0,
   ORDERTYPE_REVERSE = 1
  };

input FirstDirection InpFirstDirection = FIRST_BUY;
input CycleMode      InpCycleMode = CYCLE_MODE_1;
input DistanceMode   InpDistanceMode = DISTANCE_FIXED;
input OrderTypeMode  ordertype = ORDERTYPE_FORWARD;
input double         InpInitialLots = 0.01;
input double         InpReverseMultiplier = 2.0;
input int            InpStopLossDistancePoints = 500;
input int            InpTakeProfitDistancePoints = 500;
input int            InpCandleMinRangePoints = 500;
input int            InpCandleMaxRangePoints = 1000;
input ulong          InpMagicNumber = 20260830;
input string         InpOrderComment = "NoMatterRiseFall";

CTrade g_trade;
bool   g_had_position = false;
long   g_last_position_type = POSITION_TYPE_BUY;
double g_last_take_profit = 0.0;
int    g_cycle_index = 0;
int    g_pending_index = -1;
int    g_active_first_direction = FIRST_BUY;
int    g_active_cycle_mode = CYCLE_MODE_1;
int    g_group_stop_points = 0;
int    g_group_take_profit_points = 0;

string StatePrefix()
  {
   return "NMR." + IntegerToString((long)AccountInfoInteger(ACCOUNT_LOGIN))
          + "." + _Symbol + "." + IntegerToString((long)InpMagicNumber);
  }

void SaveState()
  {
   const string prefix = StatePrefix();
   GlobalVariableSet(prefix + ".index", (double)g_cycle_index);
   GlobalVariableSet(prefix + ".pending", (double)g_pending_index);
   GlobalVariableSet(prefix + ".meta", (double)(g_active_first_direction + g_active_cycle_mode * 2));
   GlobalVariableSet(prefix + ".slpoints", (double)g_group_stop_points);
   GlobalVariableSet(prefix + ".tppoints", (double)g_group_take_profit_points);
  }

void ClearState()
  {
   const string prefix = StatePrefix();
   GlobalVariableDel(prefix + ".index");
   GlobalVariableDel(prefix + ".pending");
   GlobalVariableDel(prefix + ".meta");
   GlobalVariableDel(prefix + ".slpoints");
   GlobalVariableDel(prefix + ".tppoints");
   g_group_stop_points = 0;
   g_group_take_profit_points = 0;
  }

void LoadState()
  {
   const string prefix = StatePrefix();
   if(!GlobalVariableCheck(prefix + ".index") || !GlobalVariableCheck(prefix + ".meta"))
      return;

   const int saved_index = (int)MathRound(GlobalVariableGet(prefix + ".index"));
   const int saved_meta = (int)MathRound(GlobalVariableGet(prefix + ".meta"));
   const int saved_first = saved_meta % 2;
   const int saved_mode = saved_meta / 2;
   if(saved_index >= 0 && saved_index < 6
      && (saved_first == FIRST_BUY || saved_first == FIRST_SELL)
      && (saved_mode == CYCLE_MODE_1 || saved_mode == CYCLE_MODE_2 || saved_mode == CYCLE_MODE_3))
     {
      g_cycle_index = saved_index;
      g_active_first_direction = saved_first;
      g_active_cycle_mode = saved_mode;
      g_group_stop_points = 0;
      g_group_take_profit_points = 0;
      if(GlobalVariableCheck(prefix + ".slpoints") && GlobalVariableCheck(prefix + ".tppoints"))
        {
         const int saved_stop_points = (int)MathRound(GlobalVariableGet(prefix + ".slpoints"));
         const int saved_take_profit_points = (int)MathRound(GlobalVariableGet(prefix + ".tppoints"));
         if(saved_stop_points > 0 && saved_take_profit_points > 0)
           {
            g_group_stop_points = saved_stop_points;
            g_group_take_profit_points = saved_take_profit_points;
           }
        }
     }
   if(GlobalVariableCheck(prefix + ".pending"))
      g_pending_index = (int)MathRound(GlobalVariableGet(prefix + ".pending"));
  }

int PriceDigits()
  {
   return (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
  }

double PriceNormalize(const double price)
  {
   return NormalizeDouble(price, PriceDigits());
  }

long SequenceDirection(const int index)
  {
   const int normalized_index = ((index % 6) + 6) % 6;
   bool buy_direction = false;
   if(g_active_cycle_mode == CYCLE_MODE_1)
      buy_direction = normalized_index == 0 || normalized_index == 3;
   else if(g_active_cycle_mode == CYCLE_MODE_2)
      buy_direction = normalized_index == 0 || normalized_index == 2
                      || normalized_index == 4 || normalized_index == 5;
   else
      buy_direction = normalized_index == 0 || normalized_index == 2
                      || normalized_index == 3 || normalized_index == 5;

   if(g_active_first_direction == FIRST_SELL)
      buy_direction = !buy_direction;
   return buy_direction ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
  }

int NextCycleIndex()
  {
   return (g_cycle_index + 1) % 6;
  }

long PendingTypeForDirection(const long direction, const double entry)
  {
   const double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   const double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   if(direction == ORDER_TYPE_BUY)
      return entry >= ask ? ORDER_TYPE_BUY_STOP : ORDER_TYPE_BUY_LIMIT;
   return entry <= bid ? ORDER_TYPE_SELL_STOP : ORDER_TYPE_SELL_LIMIT;
  }

long PendingDirection(const long pending_type)
  {
   return (pending_type == ORDER_TYPE_BUY_STOP || pending_type == ORDER_TYPE_BUY_LIMIT)
          ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
  }

bool GetPreviousCandleRange(double &previous_high, double &previous_low,
                            int &range_points)
  {
   previous_high = iHigh(_Symbol, _Period, 1);
   previous_low = iLow(_Symbol, _Period, 1);
   if(previous_high <= 0.0 || previous_low <= 0.0 || previous_high <= previous_low)
      return false;

   range_points = (int)MathRound((previous_high - previous_low) / _Point);
   if(range_points < InpCandleMinRangePoints || range_points > InpCandleMaxRangePoints)
      return false;

   return true;
  }

bool GetDistancePoints(int &stop_loss_points, int &take_profit_points)
  {
   if(InpDistanceMode == DISTANCE_FIXED)
     {
      stop_loss_points = InpStopLossDistancePoints;
      take_profit_points = InpTakeProfitDistancePoints;
      return stop_loss_points > 0 && take_profit_points > 0;
     }

   double previous_high = 0.0;
   double previous_low = 0.0;
   int range_points = 0;
   if(!GetPreviousCandleRange(previous_high, previous_low, range_points))
      return false;

   stop_loss_points = range_points;
   take_profit_points = range_points;
   return true;
  }

bool GetBreakoutDirection(const double previous_high, const double previous_low,
                          long &first_direction)
  {
   const double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   const double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   if(bid > previous_high)
     {
      first_direction = ordertype == ORDERTYPE_FORWARD ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
      return true;
     }
   if(ask < previous_low)
     {
      first_direction = ordertype == ORDERTYPE_FORWARD ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
      return true;
     }
   return false;
  }

bool GetActiveDistancePoints(const double stop_loss, const double take_profit,
                            int &stop_loss_points, int &take_profit_points)
  {
   if(g_group_stop_points > 0 && g_group_take_profit_points > 0)
     {
      stop_loss_points = g_group_stop_points;
      take_profit_points = g_group_take_profit_points;
      return true;
     }
   if(InpDistanceMode == DISTANCE_CANDLE_RANGE && stop_loss > 0.0 && take_profit > 0.0)
     {
      const int active_range_points = (int)MathRound(MathAbs(take_profit - stop_loss)
                                                     / (2.0 * _Point));
      if(active_range_points > 0)
        {
         stop_loss_points = active_range_points;
         take_profit_points = active_range_points;
         return true;
        }
     }
   return GetDistancePoints(stop_loss_points, take_profit_points);
  }

int VolumeDigits()
  {
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   int digits = 0;
   while(step < 1.0 && digits < 8)
     {
      step *= 10.0;
      digits++;
     }
   return digits;
  }

double VolumeNormalize(double volume)
  {
   const double minimum = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   const double maximum = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   const double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(step <= 0.0)
      return 0.0;

   volume = MathMax(minimum, MathMin(maximum, volume));
   volume = MathRound(volume / step) * step;
   volume = MathMax(minimum, MathMin(maximum, volume));
   return NormalizeDouble(volume, VolumeDigits());
  }

bool IsOurPosition(const ulong ticket)
  {
   if(ticket == 0 || !PositionSelectByTicket(ticket))
      return false;
   return PositionGetString(POSITION_SYMBOL) == _Symbol
          && (ulong)PositionGetInteger(POSITION_MAGIC) == InpMagicNumber;
  }

bool FindPosition(ulong &ticket, long &type, double &volume, double &open_price,
                  double &stop_loss, double &take_profit)
  {
   for(int index = 0; index < PositionsTotal(); index++)
     {
      const ulong candidate = PositionGetTicket(index);
      if(!IsOurPosition(candidate))
         continue;

      ticket = candidate;
      type = PositionGetInteger(POSITION_TYPE);
      volume = PositionGetDouble(POSITION_VOLUME);
      open_price = PositionGetDouble(POSITION_PRICE_OPEN);
      stop_loss = PositionGetDouble(POSITION_SL);
      take_profit = PositionGetDouble(POSITION_TP);
      return true;
     }
   return false;
  }

bool IsReversePendingType(const long order_type)
  {
   return order_type == ORDER_TYPE_BUY_STOP || order_type == ORDER_TYPE_BUY_LIMIT
          || order_type == ORDER_TYPE_SELL_STOP || order_type == ORDER_TYPE_SELL_LIMIT;
  }

bool FindPending(ulong &ticket, long &type, double &volume, double &price)
  {
   for(int index = 0; index < OrdersTotal(); index++)
     {
      const ulong candidate = OrderGetTicket(index);
      if(candidate == 0)
         continue;
      if(OrderGetString(ORDER_SYMBOL) != _Symbol
         || (ulong)OrderGetInteger(ORDER_MAGIC) != InpMagicNumber
         || !IsReversePendingType(OrderGetInteger(ORDER_TYPE)))
         continue;

      ticket = candidate;
      type = OrderGetInteger(ORDER_TYPE);
      volume = OrderGetDouble(ORDER_VOLUME_CURRENT);
      price = OrderGetDouble(ORDER_PRICE_OPEN);
      return true;
     }
   return false;
  }

void DeleteAllPending()
  {
   for(int index = OrdersTotal() - 1; index >= 0; index--)
     {
      const ulong ticket = OrderGetTicket(index);
      if(ticket == 0)
         continue;
      if(OrderGetString(ORDER_SYMBOL) == _Symbol
         && (ulong)OrderGetInteger(ORDER_MAGIC) == InpMagicNumber
         && IsReversePendingType(OrderGetInteger(ORDER_TYPE)))
        {
         if(!g_trade.OrderDelete(ticket))
            PrintFormat("OrderDelete failed, ticket=%I64u, retcode=%u, %s",
                        ticket, g_trade.ResultRetcode(), g_trade.ResultRetcodeDescription());
        }
     }
  }

void SetStops(const ulong position_ticket, const long type, const double entry,
              const int stop_loss_points, const int take_profit_points)
  {
   const double distance_sl = stop_loss_points * _Point;
   const double distance_tp = take_profit_points * _Point;
   double stop_loss = 0.0;
   double take_profit = 0.0;
   if(type == POSITION_TYPE_BUY)
     {
      stop_loss = PriceNormalize(entry - distance_sl);
      take_profit = PriceNormalize(entry + distance_tp);
     }
   else
     {
      stop_loss = PriceNormalize(entry + distance_sl);
      take_profit = PriceNormalize(entry - distance_tp);
     }

   if(!g_trade.PositionModify(position_ticket, stop_loss, take_profit))
      PrintFormat("PositionModify failed, ticket=%I64u, retcode=%u, %s",
                  position_ticket, g_trade.ResultRetcode(), g_trade.ResultRetcodeDescription());
  }

bool OpenMarket(const long order_type, const double requested_volume)
  {
   const double volume = VolumeNormalize(requested_volume);
   if(volume <= 0.0)
      return false;

   bool sent = false;
   if(order_type == ORDER_TYPE_BUY)
      sent = g_trade.Buy(volume, _Symbol, 0.0, 0.0, 0.0, InpOrderComment);
   else if(order_type == ORDER_TYPE_SELL)
      sent = g_trade.Sell(volume, _Symbol, 0.0, 0.0, 0.0, InpOrderComment);

   if(!sent)
     {
      PrintFormat("Market order failed, retcode=%u, %s",
                  g_trade.ResultRetcode(), g_trade.ResultRetcodeDescription());
      return false;
     }
   return true;
  }

bool PlaceNextPending(const long next_direction, const double stop_loss,
                      const double take_profit, const double current_volume)
  {
   if(stop_loss <= 0.0 || current_volume <= 0.0)
      return false;

   int stop_loss_points = 0;
   int take_profit_points = 0;
   if(!GetActiveDistancePoints(stop_loss, take_profit, stop_loss_points, take_profit_points))
      return false;

   const double volume = VolumeNormalize(current_volume * InpReverseMultiplier);
   const double entry = PriceNormalize(stop_loss);
   const double distance_sl = stop_loss_points * _Point;
   const double distance_tp = take_profit_points * _Point;
   double pending_sl = 0.0;
   double pending_tp = 0.0;
   const long pending_type = PendingTypeForDirection(next_direction, entry);
   bool sent = false;

   if(pending_type == ORDER_TYPE_BUY_STOP || pending_type == ORDER_TYPE_BUY_LIMIT)
     {
      pending_sl = PriceNormalize(entry - distance_sl);
      pending_tp = PriceNormalize(entry + distance_tp);
      if(pending_type == ORDER_TYPE_BUY_STOP)
         sent = g_trade.BuyStop(volume, entry, _Symbol, pending_sl, pending_tp,
                                ORDER_TIME_GTC, 0, InpOrderComment);
      else
         sent = g_trade.BuyLimit(volume, entry, _Symbol, pending_sl, pending_tp,
                                 ORDER_TIME_GTC, 0, InpOrderComment);
     }
   else
     {
      pending_sl = PriceNormalize(entry + distance_sl);
      pending_tp = PriceNormalize(entry - distance_tp);
      if(pending_type == ORDER_TYPE_SELL_STOP)
         sent = g_trade.SellStop(volume, entry, _Symbol, pending_sl, pending_tp,
                                 ORDER_TIME_GTC, 0, InpOrderComment);
      else
         sent = g_trade.SellLimit(volume, entry, _Symbol, pending_sl, pending_tp,
                                  ORDER_TIME_GTC, 0, InpOrderComment);
     }

   if(!sent)
     {
      PrintFormat("Reverse pending failed, retcode=%u, %s",
                  g_trade.ResultRetcode(), g_trade.ResultRetcodeDescription());
      return false;
     }
   g_pending_index = (g_cycle_index + 1) % 6;
   SaveState();
   return true;
  }

bool StopReached(const long position_type, const double stop_loss)
  {
   if(stop_loss <= 0.0)
      return false;
   const double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   const double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   return position_type == POSITION_TYPE_BUY ? bid <= stop_loss : ask >= stop_loss;
  }

bool TakeProfitReached(const long position_type, const double take_profit)
  {
   if(take_profit <= 0.0)
      return false;
   const double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   const double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   return position_type == POSITION_TYPE_BUY ? bid >= take_profit : ask <= take_profit;
  }

bool PastLastTakeProfit()
  {
   if(!g_had_position || g_last_take_profit <= 0.0)
      return false;
   const double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   const double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   return g_last_position_type == POSITION_TYPE_BUY ? bid >= g_last_take_profit
                                                    : ask <= g_last_take_profit;
  }

bool Transition(const ulong position_ticket, const long position_type, const double volume,
                const double stop_loss, const double take_profit)
  {
   const int next_index = NextCycleIndex();
   const long next_type = SequenceDirection(next_index);
   int next_stop_points = 0;
   int next_take_profit_points = 0;
   const bool can_open_next = GetActiveDistancePoints(stop_loss, take_profit,
                                                      next_stop_points, next_take_profit_points);
   DeleteAllPending();
   if(!g_trade.PositionClose(position_ticket))
     {
      PrintFormat("PositionClose failed, ticket=%I64u, retcode=%u, %s",
                  position_ticket, g_trade.ResultRetcode(), g_trade.ResultRetcodeDescription());
      return false;
     }
   g_cycle_index = next_index;
   g_pending_index = -1;
   SaveState();
   if(!can_open_next)
      return true;
   if(!OpenMarket(next_type, volume * InpReverseMultiplier))
      return false;
   ulong next_ticket = 0;
   long next_position_type = POSITION_TYPE_BUY;
   double next_volume = 0.0;
   double next_entry = 0.0;
   double next_stop_loss = 0.0;
   double next_take_profit = 0.0;
   if(!FindPosition(next_ticket, next_position_type, next_volume, next_entry,
                    next_stop_loss, next_take_profit))
      return false;
   SetStops(next_ticket, next_position_type, next_entry,
            next_stop_points, next_take_profit_points);
   Manage();
   return true;
  }

void Manage()
  {
   ulong position_ticket = 0;
   long position_type = POSITION_TYPE_BUY;
   double volume = 0.0;
   double entry = 0.0;
   double stop_loss = 0.0;
   double take_profit = 0.0;

   if(FindPosition(position_ticket, position_type, volume, entry, stop_loss, take_profit))
     {
      g_had_position = true;
      g_last_position_type = position_type;
      g_last_take_profit = take_profit;

      ulong active_pending = 0;
      long active_pending_type = 0;
      double active_pending_volume = 0.0;
      double active_pending_price = 0.0;
      const bool has_active_pending = FindPending(active_pending, active_pending_type,
                                                  active_pending_volume, active_pending_price);
      if(!has_active_pending && g_pending_index >= 0 && g_pending_index != g_cycle_index)
        {
         g_cycle_index = g_pending_index;
         g_pending_index = -1;
         SaveState();
        }

      if(has_active_pending && stop_loss > 0.0)
        {
         const long expected_direction = SequenceDirection(NextCycleIndex());
         const long expected_type = PendingTypeForDirection(expected_direction, stop_loss);
         const double expected_volume = VolumeNormalize(volume * InpReverseMultiplier);
         const double price_tolerance = _Point * 0.5;
         const double volume_tolerance = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP) * 0.5;
         if(PendingDirection(active_pending_type) != expected_direction
            || MathAbs(active_pending_price - PriceNormalize(stop_loss)) > price_tolerance
            || MathAbs(active_pending_volume - expected_volume) > volume_tolerance)
           {
            DeleteAllPending();
            g_pending_index = -1;
             PlaceNextPending(expected_direction, stop_loss, take_profit, volume);
           }
        }

      if(stop_loss <= 0.0 || take_profit <= 0.0)
        {
         int stop_loss_points = 0;
         int take_profit_points = 0;
         if(!GetActiveDistancePoints(stop_loss, take_profit,
                                     stop_loss_points, take_profit_points))
            return;
         SetStops(position_ticket, position_type, entry, stop_loss_points, take_profit_points);
         const double calculated_stop = position_type == POSITION_TYPE_BUY
                                        ? PriceNormalize(entry - stop_loss_points * _Point)
                                        : PriceNormalize(entry + stop_loss_points * _Point);
         const double calculated_take_profit = position_type == POSITION_TYPE_BUY
                                               ? PriceNormalize(entry + take_profit_points * _Point)
                                               : PriceNormalize(entry - take_profit_points * _Point);
         ulong existing_pending = 0;
         long existing_type = 0;
         double existing_volume = 0.0;
         double existing_price = 0.0;
          if(!FindPending(existing_pending, existing_type, existing_volume, existing_price))
             PlaceNextPending(SequenceDirection(NextCycleIndex()), calculated_stop,
                              calculated_take_profit, volume);
         return;
        }

      if(TakeProfitReached(position_type, take_profit))
        {
         DeleteAllPending();
         if(!g_trade.PositionClose(position_ticket))
            PrintFormat("TP close failed, ticket=%I64u, retcode=%u, %s",
                        position_ticket, g_trade.ResultRetcode(), g_trade.ResultRetcodeDescription());
         else
           {
            g_pending_index = -1;
            ClearState();
           }
         return;
        }

      if(StopReached(position_type, stop_loss))
        {
         Transition(position_ticket, position_type, volume, stop_loss, take_profit);
         return;
        }

      ulong pending_ticket = 0;
      long pending_type = 0;
      double pending_volume = 0.0;
      double pending_price = 0.0;
      if(!FindPending(pending_ticket, pending_type, pending_volume, pending_price))
         PlaceNextPending(SequenceDirection(NextCycleIndex()), stop_loss, take_profit, volume);
      return;
     }

   if(PastLastTakeProfit())
     {
      DeleteAllPending();
      g_had_position = false;
      g_last_take_profit = 0.0;
      g_pending_index = -1;
      ClearState();
      return;
     }

   ulong pending_ticket = 0;
   long pending_type = 0;
   double pending_volume = 0.0;
   double pending_price = 0.0;
   if(FindPending(pending_ticket, pending_type, pending_volume, pending_price))
      return;

   int initial_stop_points = 0;
   int initial_take_profit_points = 0;
   long first_direction = ORDER_TYPE_BUY;
   if(InpDistanceMode == DISTANCE_CANDLE_RANGE)
     {
      double previous_high = 0.0;
      double previous_low = 0.0;
      int range_points = 0;
      if(!GetPreviousCandleRange(previous_high, previous_low, range_points)
         || !GetBreakoutDirection(previous_high, previous_low, first_direction))
         return;
      initial_stop_points = range_points;
      initial_take_profit_points = range_points;
      g_active_first_direction = (int)first_direction;
      g_active_cycle_mode = ordertype == ORDERTYPE_FORWARD ? CYCLE_MODE_1 : CYCLE_MODE_2;
     }
   else
     {
      g_active_first_direction = InpFirstDirection;
      g_active_cycle_mode = InpCycleMode;
      first_direction = InpFirstDirection == FIRST_BUY ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
      if(!GetDistancePoints(initial_stop_points, initial_take_profit_points))
         return;
     }
   g_had_position = false;
   g_cycle_index = 0;
   g_pending_index = -1;
   g_group_stop_points = initial_stop_points;
   g_group_take_profit_points = initial_take_profit_points;
   SaveState();
   if(OpenMarket(first_direction, InpInitialLots))
      Manage();
  }

int OnInit()
  {
   if(InpInitialLots <= 0.0 || InpReverseMultiplier <= 0.0
      || InpStopLossDistancePoints <= 0 || InpTakeProfitDistancePoints <= 0
      || InpCandleMinRangePoints <= 0 || InpCandleMaxRangePoints < InpCandleMinRangePoints)
      return INIT_PARAMETERS_INCORRECT;

   g_active_first_direction = InpFirstDirection;
   g_active_cycle_mode = InpCycleMode;
   LoadState();
   g_trade.SetExpertMagicNumber(InpMagicNumber);
   g_trade.SetTypeFillingBySymbol(_Symbol);
   return INIT_SUCCEEDED;
  }

void OnTick()
  {
   Manage();
  }
