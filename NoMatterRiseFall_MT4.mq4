#property strict
#property version   "1.00"
#property description "不管涨跌：可选循环、网格和移动止盈策略"

enum FirstDirection
  {
   FIRST_BUY = 0,  // 首单做多
   FIRST_SELL = 1  // 首单做空
  };

enum CycleMode
  {
   CYCLE_MODE_1 = 0,  // 循环模式一
   CYCLE_MODE_2 = 1,  // 循环模式二
   CYCLE_MODE_3 = 2   // 循环模式三
  };

enum DistanceMode
  {
   DISTANCE_FIXED = 0,         // 固定止盈止损距离
   DISTANCE_CANDLE_RANGE = 1   // 上一根K线高度
  };

enum OrderTypeMode
  {
   ORDERTYPE_FORWARD = 0,  // 正向开单
   ORDERTYPE_REVERSE = 1   // 逆向开单
  };

enum TakeProfitMode
  {
   TAKE_PROFIT_GRID = 0,    // 网格移动止盈
   TAKE_PROFIT_LINEAR = 1   // 线性移动止盈
  };

// 首单方向：做多或做空
input FirstDirection 首单方向 = FIRST_BUY;
// 固定距离模式下使用的循环模式
input CycleMode      循环模式 = CYCLE_MODE_1;
// 止盈止损距离来源：固定距离或上一根K线高度
input DistanceMode   距离模式 = DISTANCE_FIXED;
// K线高度模式下的正向或逆向开单方式
input OrderTypeMode  开单方式 = ORDERTYPE_FORWARD;
// 止盈移动方式：网格成交后移动或按价格线性移动
input TakeProfitMode  止盈移动模式 = TAKE_PROFIT_GRID;
// 首单手数
input double         首单手数 = 0.01;
// 首单手数倍数；订单组止损后下一组首单手数乘此倍数
input double         首单手数倍数 = 1.0;
// 止损区间分成的格数；内部格数为总格数减一
input int            网格数量 = 2;
// 下一订单组网格手数相对上一组的倍数
input double         网格手数倍数 = 2.0;
// 固定距离模式下的止损点数
input int            固定止损距离 = 500;
// 固定距离模式下的止盈点数
input int            固定止盈距离 = 500;
// 上一根K线允许使用的最小高度点数
input int            K线最小高度 = 500;
// 上一根K线允许使用的最大高度点数
input int            K线最大高度 = 1000;
// 用于识别本EA订单的唯一编号
input int            订单识别编号 = 20260830;
// 订单注释；网格单会自动追加网格标记
input string         订单注释 = "不管涨跌";

// 内部兼容映射：以下名称不显示在参数设置中，仅用于保持既有逻辑代码兼容。
#define InpFirstDirection 首单方向
#define InpCycleMode 循环模式
#define InpDistanceMode 距离模式
#define ordertype 开单方式
#define InpTakeProfitMode 止盈移动模式
#define InpInitialLots 首单手数
#define InpGridCount 网格数量
#define InpGridLotMultiplier 网格手数倍数
#define InpStopLossDistancePoints 固定止损距离
#define InpTakeProfitDistancePoints 固定止盈距离
#define InpCandleMinRangePoints K线最小高度
#define InpCandleMaxRangePoints K线最大高度
#define InpMagicNumber 订单识别编号
#define InpOrderComment 订单注释

bool   g_had_position = false;
int    g_last_position_type = OP_BUY;
double g_last_take_profit = 0.0;
int    g_cycle_index = 0;
int    g_pending_index = -1;
int    g_active_first_direction = FIRST_BUY;
int    g_active_cycle_mode = CYCLE_MODE_1;
int    g_group_stop_points = 0;
int    g_group_take_profit_points = 0;
double g_cumulative_loss_lots = 0.0;
double g_previous_grid_lots = 0.0;
double g_grid_lots = 0.0;
double g_group_total_lots = 0.0;
double g_group_anchor_price = 0.0;
double g_group_last_entry = 0.0;
double g_group_linear_extreme = 0.0;
int    g_grid_filled_levels = 0;
int    g_grid_pending_level = 0;
double g_grid_pending_price = 0.0;

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
   GlobalVariableSet(prefix + ".slpoints", g_group_stop_points);
   GlobalVariableSet(prefix + ".tppoints", g_group_take_profit_points);
   GlobalVariableSet(prefix + ".cumlots", g_cumulative_loss_lots);
   GlobalVariableSet(prefix + ".prevgridlots", g_previous_grid_lots);
   GlobalVariableSet(prefix + ".gridlots", g_grid_lots);
   GlobalVariableSet(prefix + ".grouptotal", g_group_total_lots);
   GlobalVariableSet(prefix + ".anchor", g_group_anchor_price);
   GlobalVariableSet(prefix + ".lastentry", g_group_last_entry);
   GlobalVariableSet(prefix + ".linearextreme", g_group_linear_extreme);
   GlobalVariableSet(prefix + ".gridlevel", g_grid_filled_levels);
   GlobalVariableSet(prefix + ".gridpendinglevel", g_grid_pending_level);
   GlobalVariableSet(prefix + ".gridpendingprice", g_grid_pending_price);
  }

void ClearState()
  {
   const string prefix = StatePrefix();
   GlobalVariableDel(prefix + ".index");
   GlobalVariableDel(prefix + ".pending");
   GlobalVariableDel(prefix + ".meta");
   GlobalVariableDel(prefix + ".slpoints");
   GlobalVariableDel(prefix + ".tppoints");
   GlobalVariableDel(prefix + ".cumlots");
   GlobalVariableDel(prefix + ".prevgridlots");
   GlobalVariableDel(prefix + ".gridlots");
   GlobalVariableDel(prefix + ".grouptotal");
   GlobalVariableDel(prefix + ".anchor");
   GlobalVariableDel(prefix + ".lastentry");
   GlobalVariableDel(prefix + ".linearextreme");
   GlobalVariableDel(prefix + ".gridlevel");
   GlobalVariableDel(prefix + ".gridpendinglevel");
   GlobalVariableDel(prefix + ".gridpendingprice");
   g_group_stop_points = 0;
   g_group_take_profit_points = 0;
   g_cumulative_loss_lots = 0.0;
   g_previous_grid_lots = 0.0;
   g_grid_lots = 0.0;
   g_group_total_lots = 0.0;
   g_group_anchor_price = 0.0;
   g_group_last_entry = 0.0;
   g_group_linear_extreme = 0.0;
   g_grid_filled_levels = 0;
   g_grid_pending_level = 0;
   g_grid_pending_price = 0.0;
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
   if(GlobalVariableCheck(prefix + ".cumlots"))
      g_cumulative_loss_lots = GlobalVariableGet(prefix + ".cumlots");
   if(GlobalVariableCheck(prefix + ".prevgridlots"))
      g_previous_grid_lots = GlobalVariableGet(prefix + ".prevgridlots");
   if(GlobalVariableCheck(prefix + ".gridlots"))
      g_grid_lots = GlobalVariableGet(prefix + ".gridlots");
   if(GlobalVariableCheck(prefix + ".grouptotal"))
      g_group_total_lots = GlobalVariableGet(prefix + ".grouptotal");
   if(GlobalVariableCheck(prefix + ".anchor"))
      g_group_anchor_price = GlobalVariableGet(prefix + ".anchor");
   if(GlobalVariableCheck(prefix + ".lastentry"))
      g_group_last_entry = GlobalVariableGet(prefix + ".lastentry");
   if(GlobalVariableCheck(prefix + ".linearextreme"))
      g_group_linear_extreme = GlobalVariableGet(prefix + ".linearextreme");
   if(GlobalVariableCheck(prefix + ".gridlevel"))
      g_grid_filled_levels = (int)MathRound(GlobalVariableGet(prefix + ".gridlevel"));
   if(GlobalVariableCheck(prefix + ".gridpendinglevel"))
      g_grid_pending_level = (int)MathRound(GlobalVariableGet(prefix + ".gridpendinglevel"));
   if(GlobalVariableCheck(prefix + ".gridpendingprice"))
      g_grid_pending_price = GlobalVariableGet(prefix + ".gridpendingprice");
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

bool GetPreviousCandleRange(double &previous_high, double &previous_low,
                            int &range_points)
  {
   previous_high = iHigh(Symbol(), Period(), 1);
   previous_low = iLow(Symbol(), Period(), 1);
   if(previous_high <= 0.0 || previous_low <= 0.0 || previous_high <= previous_low)
      return false;

   range_points = (int)MathRound((previous_high - previous_low) / Point);
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
                          int &first_direction)
  {
   RefreshRates();
   if(Bid > previous_high)
     {
      first_direction = ordertype == ORDERTYPE_FORWARD ? OP_BUY : OP_SELL;
      return true;
     }
   if(Ask < previous_low)
     {
      first_direction = ordertype == ORDERTYPE_FORWARD ? OP_SELL : OP_BUY;
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
                                                     / (2.0 * Point));
      if(active_range_points > 0)
        {
         stop_loss_points = active_range_points;
         take_profit_points = active_range_points;
         return true;
        }
     }
   return GetDistancePoints(stop_loss_points, take_profit_points);
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

double TotalPositionLots(const int position_type)
  {
   double total = 0.0;
   for(int index = OrdersTotal() - 1; index >= 0; index--)
     {
      if(!OrderSelect(index, SELECT_BY_POS, MODE_TRADES) || !IsOurMarketOrder()
         || OrderType() != position_type)
         continue;
      total += OrderLots();
     }
   return total;
  }

bool CloseAllPositions(const int position_type)
  {
   bool closed = true;
   RefreshRates();
   for(int index = OrdersTotal() - 1; index >= 0; index--)
     {
      if(!OrderSelect(index, SELECT_BY_POS, MODE_TRADES) || !IsOurMarketOrder()
         || OrderType() != position_type)
         continue;
      const int ticket = OrderTicket();
      const double close_price = position_type == OP_BUY ? Bid : Ask;
      if(!OrderClose(ticket, OrderLots(), close_price, 0, clrRed))
        {
         Print("Position close failed, ticket=", ticket, ", error=", GetLastError());
         closed = false;
        }
     }
   return closed;
  }

bool IsOurPendingOrder()
  {
   return OrderSymbol() == Symbol() && OrderMagicNumber() == InpMagicNumber
          && (OrderType() == OP_BUYSTOP || OrderType() == OP_BUYLIMIT
              || OrderType() == OP_SELLSTOP || OrderType() == OP_SELLLIMIT);
  }

bool IsGridPendingComment()
  {
   return StringFind(OrderComment(), ".Grid", 0) >= 0;
  }

bool FindPending(int &ticket, int &type, double &volume, double &price)
  {
   for(int index = OrdersTotal() - 1; index >= 0; index--)
     {
       if(!OrderSelect(index, SELECT_BY_POS, MODE_TRADES) || !IsOurPendingOrder()
          || IsGridPendingComment())
         continue;
      ticket = OrderTicket();
      type = OrderType();
      volume = OrderLots();
      price = OrderOpenPrice();
      return true;
     }
   return false;
  }

bool FindGridPending(int &ticket, int &type, double &volume, double &price)
  {
   for(int index = OrdersTotal() - 1; index >= 0; index--)
     {
      if(!OrderSelect(index, SELECT_BY_POS, MODE_TRADES) || !IsOurPendingOrder()
         || !IsGridPendingComment())
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

void SetStops(const int ticket, const int type, const double entry,
              const int stop_loss_points, const int take_profit_points)
  {
   const double distance_sl = stop_loss_points * Point;
   const double distance_tp = take_profit_points * Point;
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

double GroupStopPrice(const int type)
  {
   if(type == OP_BUY)
      return PriceNormalize(g_group_anchor_price - g_group_stop_points * Point);
   return PriceNormalize(g_group_anchor_price + g_group_stop_points * Point);
  }

double GroupTakeProfitPrice(const int type)
  {
   double reference_price = g_group_last_entry;
   if(InpTakeProfitMode == TAKE_PROFIT_LINEAR && g_group_linear_extreme > 0.0)
      reference_price = g_group_linear_extreme;
   if(type == OP_BUY)
      return PriceNormalize(reference_price + g_group_take_profit_points * Point);
   return PriceNormalize(reference_price - g_group_take_profit_points * Point);
   }

bool SetGroupStops(const int type)
  {
   const double stop_loss = GroupStopPrice(type);
   const double take_profit = GroupTakeProfitPrice(type);
   bool modified = true;
   for(int index = OrdersTotal() - 1; index >= 0; index--)
     {
      if(!OrderSelect(index, SELECT_BY_POS, MODE_TRADES) || !IsOurMarketOrder()
         || OrderType() != type)
         continue;
      if(MathAbs(OrderStopLoss() - stop_loss) <= Point * 0.5
         && MathAbs(OrderTakeProfit() - take_profit) <= Point * 0.5)
         continue;
      if(!OrderModify(OrderTicket(), OrderOpenPrice(), stop_loss, take_profit,
                      0, clrNONE))
        {
         Print("Group OrderModify failed, ticket=", OrderTicket(),
               ", error=", GetLastError());
         modified = false;
        }
     }
   g_last_take_profit = take_profit;
   return modified;
   }

bool UpdateLinearTakeProfit(const int type)
  {
   if(InpTakeProfitMode != TAKE_PROFIT_LINEAR
      || g_group_take_profit_points <= 0 || g_group_anchor_price <= 0.0)
      return false;

   RefreshRates();
   const double reference_price = type == OP_BUY ? Ask : Bid;
   bool extreme_changed = false;
   if(g_group_linear_extreme <= 0.0)
      {
       g_group_linear_extreme = g_group_anchor_price;
       extreme_changed = true;
      }
   if(type == OP_BUY && reference_price < g_group_linear_extreme)
      {
       g_group_linear_extreme = reference_price;
       extreme_changed = true;
      }
   else if(type == OP_SELL && reference_price > g_group_linear_extreme)
      {
       g_group_linear_extreme = reference_price;
       extreme_changed = true;
      }

   const double desired_stop_loss = GroupStopPrice(type);
   const double desired_take_profit = GroupTakeProfitPrice(type);
   bool needs_modify = extreme_changed;
   for(int index = OrdersTotal() - 1; index >= 0; index--)
      {
       if(!OrderSelect(index, SELECT_BY_POS, MODE_TRADES) || !IsOurMarketOrder()
          || OrderType() != type)
          continue;
       if(MathAbs(OrderStopLoss() - desired_stop_loss) > Point * 0.5
          || MathAbs(OrderTakeProfit() - desired_take_profit) > Point * 0.5)
          {
           needs_modify = true;
           break;
          }
      }
   if(needs_modify)
      {
       SetGroupStops(type);
       SaveState();
       return true;
      }
   return false;
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

double NextGroupLots(const double fallback_volume)
  {
   double requested = g_cumulative_loss_lots + g_group_total_lots;
   if(requested <= 0.0)
      requested = fallback_volume;
   else
      requested *= 首单手数倍数;
   return VolumeNormalize(requested);
  }

bool PlaceNextPending(const int next_direction, const double stop_loss,
                      const double take_profit, const double current_volume)
  {
   if(stop_loss <= 0.0 || current_volume <= 0.0)
      return false;

   int stop_loss_points = 0;
   int take_profit_points = 0;
   if(!GetActiveDistancePoints(stop_loss, take_profit, stop_loss_points, take_profit_points))
      return false;

   RefreshRates();
    const double volume = NextGroupLots(current_volume);
   const double entry = PriceNormalize(stop_loss);
   const double distance_sl = stop_loss_points * Point;
   const double distance_tp = take_profit_points * Point;
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

double GridLevelPrice(const int position_type, const int level)
  {
   if(InpGridCount <= 0 || g_group_stop_points <= 0 || g_group_anchor_price <= 0.0)
      return 0.0;
   const double distance = g_group_stop_points * Point * level / InpGridCount;
   if(position_type == OP_BUY)
      return PriceNormalize(g_group_anchor_price - distance);
   return PriceNormalize(g_group_anchor_price + distance);
  }

bool PlaceGridPending(const int position_type, const int level)
  {
   if(InpGridCount < 2 || level <= 0 || level >= InpGridCount
      || g_grid_lots <= 0.0 || g_group_anchor_price <= 0.0)
      return false;

   const double entry = GridLevelPrice(position_type, level);
   const double stop_loss = GroupStopPrice(position_type);
   const double take_profit = position_type == OP_BUY
                              ? PriceNormalize(entry + g_group_take_profit_points * Point)
                              : PriceNormalize(entry - g_group_take_profit_points * Point);
   const double volume = VolumeNormalize(g_grid_lots);
   const int pending_type = PendingTypeForDirection(position_type, entry);
   const string grid_comment = InpOrderComment + ".Grid";
   RefreshRates();
   const int ticket = OrderSend(Symbol(), pending_type, volume, entry, 0,
                                stop_loss, take_profit, grid_comment,
                                InpMagicNumber, 0, clrOrange);
   if(ticket < 0)
     {
      Print("Grid pending failed, error=", GetLastError());
      return false;
     }
   g_grid_pending_level = level;
   g_grid_pending_price = entry;
   SaveState();
   return true;
  }

bool HandleGridFill(const int position_type, const double previous_total_lots)
  {
   if(g_grid_pending_level <= 0)
      return false;
   int grid_ticket = -1;
   int grid_type = OP_BUY;
   double grid_volume = 0.0;
   double grid_price = 0.0;
   if(FindGridPending(grid_ticket, grid_type, grid_volume, grid_price))
      return false;

   const double current_total_lots = TotalPositionLots(position_type);
   const double volume_tolerance = MarketInfo(Symbol(), MODE_LOTSTEP) * 0.5;
   if(current_total_lots <= previous_total_lots + volume_tolerance)
      return false;

   const int filled_level = g_grid_pending_level;
   const double pending_price = g_grid_pending_price;
   g_grid_filled_levels = filled_level;
   g_grid_pending_level = 0;
   g_grid_pending_price = 0.0;
   g_group_total_lots = current_total_lots;
   g_group_last_entry = pending_price > 0.0 ? pending_price
                                           : GridLevelPrice(position_type, filled_level);
   SetGroupStops(position_type);
   SaveState();
   return true;
  }

void EnsureGridPending(const int position_type)
  {
   if(InpGridCount < 2 || g_grid_filled_levels >= InpGridCount - 1)
      return;
   int grid_ticket = -1;
   int grid_type = OP_BUY;
   double grid_volume = 0.0;
   double grid_price = 0.0;
   if(FindGridPending(grid_ticket, grid_type, grid_volume, grid_price))
      return;
   if(g_grid_pending_level > 0)
      return;
   PlaceGridPending(position_type, g_grid_filled_levels + 1);
  }

void EnsureNextPending(const double stop_loss, const double take_profit,
                       const double fallback_volume)
  {
   int active_pending = -1;
   int active_pending_type = OP_SELLSTOP;
   double active_pending_volume = 0.0;
   double active_pending_price = 0.0;
   const bool has_active_pending = FindPending(active_pending, active_pending_type,
                                               active_pending_volume, active_pending_price);
   const int expected_direction = SequenceDirection(NextCycleIndex());
   const double expected_volume = NextGroupLots(fallback_volume);
   const double price_tolerance = Point * 0.5;
   const double volume_tolerance = MarketInfo(Symbol(), MODE_LOTSTEP) * 0.5;
   if(has_active_pending
      && (PendingDirection(active_pending_type) != expected_direction
          || MathAbs(active_pending_price - PriceNormalize(stop_loss)) > price_tolerance
          || MathAbs(active_pending_volume - expected_volume) > volume_tolerance))
     {
      DeleteAllPending();
      g_pending_index = -1;
      PlaceNextPending(expected_direction, stop_loss, take_profit, fallback_volume);
      return;
     }
   if(!has_active_pending)
      PlaceNextPending(expected_direction, stop_loss, take_profit, fallback_volume);
  }

bool Transition(const int position_type, const double volume,
                const double stop_loss, const double take_profit)
  {
   RefreshRates();
   const int next_index = NextCycleIndex();
   const int next_type = SequenceDirection(next_index);
   int next_stop_points = 0;
   int next_take_profit_points = 0;
   const bool can_open_next = GetActiveDistancePoints(stop_loss, take_profit,
                                                      next_stop_points, next_take_profit_points);
   DeleteAllPending();
   g_cumulative_loss_lots += g_group_total_lots > 0.0 ? g_group_total_lots : volume;
   g_previous_grid_lots = g_grid_lots;
   if(!CloseAllPositions(position_type))
      return false;
   g_cycle_index = next_index;
   g_pending_index = -1;
   SaveState();
   if(!can_open_next)
      return true;
    if(!OpenMarket(next_type, VolumeNormalize(g_cumulative_loss_lots * 首单手数倍数)))
      return false;
   int next_ticket = -1;
   int next_position_type = OP_BUY;
   double next_volume = 0.0;
   double next_entry = 0.0;
   double next_stop_loss = 0.0;
   double next_take_profit = 0.0;
   if(!FindPosition(next_ticket, next_position_type, next_volume, next_entry,
                    next_stop_loss, next_take_profit))
      return false;
    g_group_anchor_price = next_entry;
    g_group_last_entry = next_entry;
    g_group_linear_extreme = next_entry;
   g_group_total_lots = TotalPositionLots(next_position_type);
   g_grid_filled_levels = 0;
   g_grid_pending_level = 0;
   g_grid_pending_price = 0.0;
   g_grid_lots = VolumeNormalize(g_previous_grid_lots * InpGridLotMultiplier);
   g_group_stop_points = next_stop_points;
   g_group_take_profit_points = next_take_profit_points;
   SetGroupStops(next_position_type);
   SaveState();
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
      const double previous_group_total_lots = g_group_total_lots;
      const double previous_grid_lots = g_grid_lots;
      int state_pending_ticket = -1;
      int state_pending_type = OP_SELLSTOP;
      double state_pending_volume = 0.0;
      double state_pending_price = 0.0;
      const bool has_state_pending = FindPending(state_pending_ticket, state_pending_type,
                                                 state_pending_volume, state_pending_price);
      const bool pending_filled = !has_state_pending
                                  && g_pending_index >= 0
                                  && g_pending_index != g_cycle_index;
      if(!pending_filled)
         HandleGridFill(position_type, previous_group_total_lots);
      if(pending_filled)
        {
         g_cumulative_loss_lots += previous_group_total_lots;
         g_previous_grid_lots = previous_grid_lots;
         g_cycle_index = g_pending_index;
         g_pending_index = -1;
         g_group_anchor_price = entry;
         g_group_last_entry = entry;
          g_group_linear_extreme = entry;
         g_grid_filled_levels = 0;
         g_grid_pending_level = 0;
         g_grid_pending_price = 0.0;
         g_grid_lots = VolumeNormalize(g_previous_grid_lots * InpGridLotMultiplier);
        }
      volume = TotalPositionLots(position_type);
      if(g_group_anchor_price <= 0.0)
         g_group_anchor_price = entry;
       if(g_group_last_entry <= 0.0)
          g_group_last_entry = entry;
       if(g_group_linear_extreme <= 0.0)
          g_group_linear_extreme = g_group_anchor_price;
      g_group_total_lots = volume;
      if(g_grid_lots <= 0.0)
         g_grid_lots = g_previous_grid_lots > 0.0
                       ? VolumeNormalize(g_previous_grid_lots * InpGridLotMultiplier)
                       : volume;
      const bool missing_stops = stop_loss <= 0.0 || take_profit <= 0.0;
      g_had_position = true;
      g_last_position_type = position_type;
      if(g_group_stop_points > 0 && g_group_take_profit_points > 0)
        {
         stop_loss = GroupStopPrice(position_type);
         take_profit = GroupTakeProfitPrice(position_type);
        }
      g_last_take_profit = take_profit;

      if(pending_filled)
         SetGroupStops(position_type);

      if(missing_stops)
        {
         int stop_loss_points = 0;
         int take_profit_points = 0;
         if(!GetActiveDistancePoints(stop_loss, take_profit,
                                     stop_loss_points, take_profit_points))
            return;
         g_group_stop_points = stop_loss_points;
         g_group_take_profit_points = take_profit_points;
          g_group_anchor_price = entry;
          g_group_last_entry = entry;
          g_group_linear_extreme = entry;
          SetGroupStops(position_type);
         EnsureNextPending(GroupStopPrice(position_type), GroupTakeProfitPrice(position_type),
                           volume);
         EnsureGridPending(position_type);
         SaveState();
          return;
         }

       UpdateLinearTakeProfit(position_type);
       if(InpTakeProfitMode == TAKE_PROFIT_LINEAR)
          {
           take_profit = GroupTakeProfitPrice(position_type);
           g_last_take_profit = take_profit;
          }

       if(TakeProfitReached(position_type, take_profit))
        {
         DeleteAllPending();
         if(CloseAllPositions(position_type))
           {
            g_pending_index = -1;
            ClearState();
           }
         return;
        }

      if(StopReached(position_type, stop_loss))
        {
         Transition(position_type, volume, stop_loss, take_profit);
         return;
        }

      EnsureNextPending(GroupStopPrice(position_type), GroupTakeProfitPrice(position_type),
                        volume);
      EnsureGridPending(position_type);
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

   int initial_stop_points = 0;
   int initial_take_profit_points = 0;
   int first_direction = OP_BUY;
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
      g_active_first_direction = first_direction;
      g_active_cycle_mode = ordertype == ORDERTYPE_FORWARD ? CYCLE_MODE_1 : CYCLE_MODE_2;
     }
   else
     {
      g_active_first_direction = InpFirstDirection;
      g_active_cycle_mode = InpCycleMode;
      first_direction = InpFirstDirection == FIRST_BUY ? OP_BUY : OP_SELL;
      if(!GetDistancePoints(initial_stop_points, initial_take_profit_points))
         return;
     }
   g_had_position = false;
   g_cycle_index = 0;
   g_pending_index = -1;
   g_group_stop_points = initial_stop_points;
   g_group_take_profit_points = initial_take_profit_points;
   const double initial_lots = g_cumulative_loss_lots > 0.0
                               ? VolumeNormalize(g_cumulative_loss_lots)
                               : VolumeNormalize(InpInitialLots);
   if(OpenMarket(first_direction, initial_lots))
     {
      if(FindPosition(position_ticket, position_type, volume, entry,
                      stop_loss, take_profit))
        {
         g_group_anchor_price = entry;
         g_group_last_entry = entry;
          g_group_linear_extreme = entry;
         g_group_total_lots = TotalPositionLots(position_type);
         g_grid_filled_levels = 0;
         g_grid_pending_level = 0;
         g_grid_pending_price = 0.0;
         g_grid_lots = g_previous_grid_lots > 0.0
                       ? VolumeNormalize(g_previous_grid_lots * InpGridLotMultiplier)
                       : g_group_total_lots;
        }
      SaveState();
      Manage();
     }
  }

int OnInit()
  {
   if(InpInitialLots <= 0.0 || 首单手数倍数 <= 0.0
      || InpGridCount < 0 || InpGridLotMultiplier <= 0.0
      || InpStopLossDistancePoints <= 0 || InpTakeProfitDistancePoints <= 0
      || InpCandleMinRangePoints <= 0 || InpCandleMaxRangePoints < InpCandleMinRangePoints)
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
