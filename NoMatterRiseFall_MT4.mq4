#property strict
#property version   "1.00"
#property description "No Matter Rise Fall - selectable six-order cycle strategy"

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

input FirstDirection InpFirstDirection = FIRST_BUY;
input CycleMode      InpCycleMode = CYCLE_MODE_1;
input double         InpInitialLots = 0.01;
input double         InpReverseMultiplier = 2.0;
input int            InpStopLossDistancePoints = 500;
input int            InpTakeProfitDistancePoints = 500;
input int            InpMagicNumber = 20260830;
input string         InpOrderComment = "NoMatterRiseFall";

bool   g_had_position = false;
int    g_last_position_type = OP_BUY;
double g_last_take_profit = 0.0;
int    g_cycle_index = 0;
int    g_pending_index = -1;
int    g_active_first_direction = FIRST_BUY;
int    g_active_cycle_mode = CYCLE_MODE_1;

string StatePrefix()
  {
   return "NMR." + IntegerToString(AccountNumber())
          + "." + Symbol() + "." + IntegerToString(InpMagicNumber);
  }

void SaveState()
  {
   const string prefix = StatePrefix();
   GlobalVariableSet(prefix + ".index", g_cycle_index);
   GlobalVariableSet(prefix + ".pending", g_pending_index);
   GlobalVariableSet(prefix + ".meta", g_active_first_direction + g_active_cycle_mode * 2);
  }

void ClearState()
  {
   const string prefix = StatePrefix();
   GlobalVariableDel(prefix + ".index");
   GlobalVariableDel(prefix + ".pending");
   GlobalVariableDel(prefix + ".meta");
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
     }
   if(GlobalVariableCheck(prefix + ".pending"))
      g_pending_index = (int)MathRound(GlobalVariableGet(prefix + ".pending"));
  }

double PriceNormalize(const double price)
  {
   return NormalizeDouble(price, Digits);
  }

int SequenceDirection(const int index)
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
   return buy_direction ? OP_BUY : OP_SELL;
  }

int NextCycleIndex()
  {
   return (g_cycle_index + 1) % 6;
  }

int PendingTypeForDirection(const int direction, const double entry)
  {
   RefreshRates();
   if(direction == OP_BUY)
      return entry >= Ask ? OP_BUYSTOP : OP_BUYLIMIT;
   return entry <= Bid ? OP_SELLSTOP : OP_SELLLIMIT;
  }

int PendingDirection(const int pending_type)
  {
   return (pending_type == OP_BUYSTOP || pending_type == OP_BUYLIMIT) ? OP_BUY : OP_SELL;
  }

int LotDigits()
  {
   double step = MarketInfo(Symbol(), MODE_LOTSTEP);
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
   const double minimum = MarketInfo(Symbol(), MODE_MINLOT);
   const double maximum = MarketInfo(Symbol(), MODE_MAXLOT);
   const double step = MarketInfo(Symbol(), MODE_LOTSTEP);
   if(step <= 0.0)
      return 0.0;

   volume = MathMax(minimum, MathMin(maximum, volume));
   volume = MathRound(volume / step) * step;
   volume = MathMax(minimum, MathMin(maximum, volume));
   return NormalizeDouble(volume, LotDigits());
  }

bool IsOurMarketOrder()
  {
   return OrderSymbol() == Symbol() && OrderMagicNumber() == InpMagicNumber
          && (OrderType() == OP_BUY || OrderType() == OP_SELL);
  }

bool FindPosition(int &ticket, int &type, double &volume, double &open_price,
                  double &stop_loss, double &take_profit)
  {
   for(int index = OrdersTotal() - 1; index >= 0; index--)
     {
      if(!OrderSelect(index, SELECT_BY_POS, MODE_TRADES) || !IsOurMarketOrder())
         continue;
      ticket = OrderTicket();
      type = OrderType();
      volume = OrderLots();
      open_price = OrderOpenPrice();
      stop_loss = OrderStopLoss();
      take_profit = OrderTakeProfit();
      return true;
     }
   return false;
  }

bool IsOurPendingOrder()
  {
   return OrderSymbol() == Symbol() && OrderMagicNumber() == InpMagicNumber
          && (OrderType() == OP_BUYSTOP || OrderType() == OP_BUYLIMIT
              || OrderType() == OP_SELLSTOP || OrderType() == OP_SELLLIMIT);
  }

bool FindPending(int &ticket, int &type, double &volume, double &price)
  {
   for(int index = OrdersTotal() - 1; index >= 0; index--)
     {
      if(!OrderSelect(index, SELECT_BY_POS, MODE_TRADES) || !IsOurPendingOrder())
         continue;
      ticket = OrderTicket();
      type = OrderType();
      volume = OrderLots();
      price = OrderOpenPrice();
      return true;
     }
   return false;
  }

void DeleteAllPending()
  {
   for(int index = OrdersTotal() - 1; index >= 0; index--)
     {
      if(!OrderSelect(index, SELECT_BY_POS, MODE_TRADES) || !IsOurPendingOrder())
         continue;
      const int ticket = OrderTicket();
      if(!OrderDelete(ticket, clrRed))
         Print("OrderDelete failed, ticket=", ticket, ", error=", GetLastError());
     }
  }

void SetStops(const int ticket, const int type, const double entry)
  {
   const double distance_sl = InpStopLossDistancePoints * Point;
   const double distance_tp = InpTakeProfitDistancePoints * Point;
   double stop_loss = 0.0;
   double take_profit = 0.0;
   if(type == OP_BUY)
     {
      stop_loss = PriceNormalize(entry - distance_sl);
      take_profit = PriceNormalize(entry + distance_tp);
     }
   else
     {
      stop_loss = PriceNormalize(entry + distance_sl);
      take_profit = PriceNormalize(entry - distance_tp);
     }

   if(!OrderModify(ticket, OrderOpenPrice(), stop_loss, take_profit, 0, clrNONE))
      Print("OrderModify failed, ticket=", ticket, ", error=", GetLastError());
  }

bool OpenMarket(const int type, const double requested_volume)
  {
   RefreshRates();
   const double volume = VolumeNormalize(requested_volume);
   if(volume <= 0.0)
      return false;

   const double price = type == OP_BUY ? Ask : Bid;
   const int ticket = OrderSend(Symbol(), type, volume, price, 0,
                                0.0, 0.0, InpOrderComment, InpMagicNumber,
                                0, clrBlue);
   if(ticket < 0)
     {
      Print("Market order failed, error=", GetLastError());
      return false;
     }
   return true;
  }

bool PlaceNextPending(const int next_direction, const double stop_loss, const double current_volume)
  {
   if(stop_loss <= 0.0 || current_volume <= 0.0)
      return false;

   RefreshRates();
   const double volume = VolumeNormalize(current_volume * InpReverseMultiplier);
   const double entry = PriceNormalize(stop_loss);
   const double distance_sl = InpStopLossDistancePoints * Point;
   const double distance_tp = InpTakeProfitDistancePoints * Point;
   double pending_sl = 0.0;
   double pending_tp = 0.0;
   const int pending_type = PendingTypeForDirection(next_direction, entry);

   if(pending_type == OP_BUYSTOP || pending_type == OP_BUYLIMIT)
     {
      pending_sl = PriceNormalize(entry - distance_sl);
      pending_tp = PriceNormalize(entry + distance_tp);
     }
   else
     {
      pending_sl = PriceNormalize(entry + distance_sl);
      pending_tp = PriceNormalize(entry - distance_tp);
     }

   const int ticket = OrderSend(Symbol(), pending_type, volume, entry, 0,
                                pending_sl, pending_tp, InpOrderComment,
                                InpMagicNumber, 0, clrOrange);
   if(ticket < 0)
     {
      Print("Reverse pending failed, error=", GetLastError());
      return false;
     }
   g_pending_index = (g_cycle_index + 1) % 6;
   SaveState();
   return true;
  }

bool StopReached(const int position_type, const double stop_loss)
  {
   if(stop_loss <= 0.0)
      return false;
   RefreshRates();
   return position_type == OP_BUY ? Bid <= stop_loss : Ask >= stop_loss;
  }

bool TakeProfitReached(const int position_type, const double take_profit)
  {
   if(take_profit <= 0.0)
      return false;
   RefreshRates();
   return position_type == OP_BUY ? Bid >= take_profit : Ask <= take_profit;
  }

bool PastLastTakeProfit()
  {
   if(!g_had_position || g_last_take_profit <= 0.0)
      return false;
   RefreshRates();
   return g_last_position_type == OP_BUY ? Bid >= g_last_take_profit
                                         : Ask <= g_last_take_profit;
  }

bool Transition(const int position_ticket, const int position_type, const double volume)
  {
   RefreshRates();
   const int next_index = NextCycleIndex();
   const int next_type = SequenceDirection(next_index);
   const double close_price = position_type == OP_BUY ? Bid : Ask;
   DeleteAllPending();
   if(!OrderSelect(position_ticket, SELECT_BY_TICKET, MODE_TRADES)
      || !OrderClose(position_ticket, OrderLots(), close_price, 0, clrRed))
     {
      Print("Position close failed, ticket=", position_ticket, ", error=", GetLastError());
      return false;
     }
   g_cycle_index = next_index;
   g_pending_index = -1;
   SaveState();
   if(!OpenMarket(next_type, volume * InpReverseMultiplier))
      return false;
   Manage();
   return true;
  }

void Manage()
  {
   int position_ticket = -1;
   int position_type = OP_BUY;
   double volume = 0.0;
   double entry = 0.0;
   double stop_loss = 0.0;
   double take_profit = 0.0;

   if(FindPosition(position_ticket, position_type, volume, entry, stop_loss, take_profit))
     {
      g_had_position = true;
      g_last_position_type = position_type;
      g_last_take_profit = take_profit;

      int active_pending = -1;
      int active_pending_type = OP_SELLSTOP;
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
         const int expected_direction = SequenceDirection(NextCycleIndex());
         const int expected_type = PendingTypeForDirection(expected_direction, stop_loss);
         const double expected_volume = VolumeNormalize(volume * InpReverseMultiplier);
         const double price_tolerance = Point * 0.5;
         const double volume_tolerance = MarketInfo(Symbol(), MODE_LOTSTEP) * 0.5;
         if(PendingDirection(active_pending_type) != expected_direction
            || MathAbs(active_pending_price - PriceNormalize(stop_loss)) > price_tolerance
            || MathAbs(active_pending_volume - expected_volume) > volume_tolerance)
           {
            DeleteAllPending();
            g_pending_index = -1;
            PlaceNextPending(expected_direction, stop_loss, volume);
           }
        }

      if(stop_loss <= 0.0 || take_profit <= 0.0)
        {
         SetStops(position_ticket, position_type, entry);
         const double calculated_stop = position_type == OP_BUY
                                        ? PriceNormalize(entry - InpStopLossDistancePoints * Point)
                                        : PriceNormalize(entry + InpStopLossDistancePoints * Point);
         int existing_pending = -1;
         int existing_type = OP_SELLSTOP;
         double existing_volume = 0.0;
         double existing_price = 0.0;
         if(!FindPending(existing_pending, existing_type, existing_volume, existing_price))
            PlaceNextPending(SequenceDirection(NextCycleIndex()), calculated_stop, volume);
         return;
        }

      if(TakeProfitReached(position_type, take_profit))
        {
         DeleteAllPending();
         RefreshRates();
         const double close_price = position_type == OP_BUY ? Bid : Ask;
         if(!OrderClose(position_ticket, volume, close_price, 0, clrGreen))
            Print("TP close failed, ticket=", position_ticket, ", error=", GetLastError());
         else
           {
            g_pending_index = -1;
            ClearState();
           }
         return;
        }

      if(StopReached(position_type, stop_loss))
        {
         Transition(position_ticket, position_type, volume);
         return;
        }

      int pending_ticket = -1;
      int pending_type = OP_SELLSTOP;
      double pending_volume = 0.0;
      double pending_price = 0.0;
      if(!FindPending(pending_ticket, pending_type, pending_volume, pending_price))
         PlaceNextPending(SequenceDirection(NextCycleIndex()), stop_loss, volume);
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

   int pending_ticket = -1;
   int pending_type = OP_SELLSTOP;
   double pending_volume = 0.0;
   double pending_price = 0.0;
   if(FindPending(pending_ticket, pending_type, pending_volume, pending_price))
      return;

   g_had_position = false;
   g_cycle_index = 0;
   g_pending_index = -1;
   g_active_first_direction = InpFirstDirection;
   g_active_cycle_mode = InpCycleMode;
   SaveState();
   if(OpenMarket(InpFirstDirection == FIRST_BUY ? OP_BUY : OP_SELL, InpInitialLots))
      Manage();
  }

int OnInit()
  {
   if(InpInitialLots <= 0.0 || InpReverseMultiplier <= 0.0
      || InpStopLossDistancePoints <= 0 || InpTakeProfitDistancePoints <= 0)
      return INIT_PARAMETERS_INCORRECT;
   g_active_first_direction = InpFirstDirection;
   g_active_cycle_mode = InpCycleMode;
   LoadState();
   return INIT_SUCCEEDED;
  }

void OnTick()
  {
   Manage();
  }
