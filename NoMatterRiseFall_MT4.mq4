#property strict
#property version   "1.00"
#property description "No Matter Rise Fall - alternating reverse stop strategy"

enum FirstDirection
  {
   FIRST_BUY = 0,
   FIRST_SELL = 1
  };

input FirstDirection InpFirstDirection = FIRST_BUY;
input double         InpInitialLots = 0.01;
input double         InpReverseMultiplier = 2.0;
input int            InpStopLossDistancePoints = 500;
input int            InpTakeProfitDistancePoints = 500;
input int            InpMagicNumber = 20260830;
input string         InpOrderComment = "NoMatterRiseFall";

bool   g_had_position = false;
int    g_last_position_type = OP_BUY;
double g_last_take_profit = 0.0;

double PriceNormalize(const double price)
  {
   return NormalizeDouble(price, Digits);
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
          && (OrderType() == OP_BUYSTOP || OrderType() == OP_SELLSTOP);
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

bool PlaceReversePending(const int position_type, const double stop_loss, const double current_volume)
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
   int pending_type = OP_SELLSTOP;

   if(position_type == OP_BUY)
     {
      pending_type = OP_SELLSTOP;
      pending_sl = PriceNormalize(entry + distance_sl);
      pending_tp = PriceNormalize(entry - distance_tp);
     }
   else
     {
      pending_type = OP_BUYSTOP;
      pending_sl = PriceNormalize(entry - distance_sl);
      pending_tp = PriceNormalize(entry + distance_tp);
     }

   const int ticket = OrderSend(Symbol(), pending_type, volume, entry, 0,
                                pending_sl, pending_tp, InpOrderComment,
                                InpMagicNumber, 0, clrOrange);
   if(ticket < 0)
     {
      Print("Reverse pending failed, error=", GetLastError());
      return false;
     }
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
   const int next_type = position_type == OP_BUY ? OP_SELL : OP_BUY;
   const double close_price = position_type == OP_BUY ? Bid : Ask;
   DeleteAllPending();
   if(!OrderSelect(position_ticket, SELECT_BY_TICKET, MODE_TRADES)
      || !OrderClose(position_ticket, OrderLots(), close_price, 0, clrRed))
     {
      Print("Position close failed, ticket=", position_ticket, ", error=", GetLastError());
      return false;
     }
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
            PlaceReversePending(position_type, calculated_stop, volume);
         return;
        }

      if(TakeProfitReached(position_type, take_profit))
        {
         DeleteAllPending();
         RefreshRates();
         const double close_price = position_type == OP_BUY ? Bid : Ask;
         if(!OrderClose(position_ticket, volume, close_price, 0, clrGreen))
            Print("TP close failed, ticket=", position_ticket, ", error=", GetLastError());
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
         PlaceReversePending(position_type, stop_loss, volume);
      return;
     }

   if(PastLastTakeProfit())
     {
      DeleteAllPending();
      g_had_position = false;
      g_last_take_profit = 0.0;
      return;
     }

   int pending_ticket = -1;
   int pending_type = OP_SELLSTOP;
   double pending_volume = 0.0;
   double pending_price = 0.0;
   if(FindPending(pending_ticket, pending_type, pending_volume, pending_price))
      return;

   g_had_position = false;
   if(OpenMarket(InpFirstDirection == FIRST_BUY ? OP_BUY : OP_SELL, InpInitialLots))
      Manage();
  }

int OnInit()
  {
   if(InpInitialLots <= 0.0 || InpReverseMultiplier <= 0.0
      || InpStopLossDistancePoints <= 0 || InpTakeProfitDistancePoints <= 0)
      return INIT_PARAMETERS_INCORRECT;
   return INIT_SUCCEEDED;
  }

void OnTick()
  {
   Manage();
  }
