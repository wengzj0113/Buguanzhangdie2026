#property strict
#property version   "1.00"
#property description "不管涨跌：可选循环、网格和移动止盈策略"

#include <Trade/Trade.mqh>

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

enum CandleOrderMode
  {
   KORDER_ONCE_PER_BAR = 0,  // 同一根当前K线只触发一次首单
   KORDER_REPEAT_PER_BAR = 1  // 同一根当前K线允许重复触发首单
  };

enum TakeProfitMode
  {
   TAKE_PROFIT_GRID = 0,    // 网格移动止盈
   TAKE_PROFIT_LINEAR = 1   // 线性移动止盈
  };

enum ReversePendingStatus
  {
   REVERSE_PENDING_UNKNOWN = 0,
   REVERSE_PENDING_ACTIVE = 1,
   REVERSE_PENDING_FILLED = 2,
   REVERSE_PENDING_CANCELED = 3
  };

enum TransitionPhase
  {
   TRANSITION_NONE = 0,
   TRANSITION_PREPARED = 1,
   TRANSITION_COMPLETE = 2
  };

// 首单方向：做多或做空
input FirstDirection 首单方向 = FIRST_BUY;
// 固定距离模式下使用的循环模式
input CycleMode      循环模式 = CYCLE_MODE_1;
// 止盈止损距离来源：固定距离或上一根K线高度
input DistanceMode   距离模式 = DISTANCE_FIXED;
// K线高度模式下的正向或逆向开单方式
input OrderTypeMode  开单方式 = ORDERTYPE_FORWARD;
// K线高度模式下同一根当前K线的首单触发次数
input CandleOrderMode K线开单模式 = KORDER_ONCE_PER_BAR;
// K线高度模式是否允许多个订单组并行：0=单组，1=多组
input int            kline_enable_multiple = 0;
// 止盈移动方式：网格成交后移动或按价格线性移动
input TakeProfitMode  止盈移动模式 = TAKE_PROFIT_GRID;
// 首单手数
input double         首单手数 = 0.01;
// 首单手数倍数；订单组止损后下一组首单手数乘此倍数
input double         首单手数倍数 = 1.0;
// 止损后最多切换到下一订单组的次数；达到后清理并重新开始
input int            最大反手次数 = 5;
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
input ulong          订单识别编号 = 20260830;
// 订单注释；网格单会自动追加网格标记
input string         订单注释 = "不管涨跌";
// 允许开首单的开始时间，使用平台服务器时间，格式为 时:分
input string         开始时间 = "08:00";
// 允许开首单的结束时间，使用平台服务器时间，格式为 时:分
input string         结束时间 = "23:00";

// 内部兼容映射：以下名称不显示在参数设置中，仅用于保持既有逻辑代码兼容。
#define InpFirstDirection 首单方向
#define InpCycleMode 循环模式
#define InpDistanceMode 距离模式
#define ordertype 开单方式
#define Korder_type K线开单模式
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

CTrade g_trade;
bool   g_had_position = false;
long   g_last_position_type = POSITION_TYPE_BUY;
double g_last_take_profit = 0.0;
int    g_cycle_index = 0;
int    g_pending_index = -1;
int    g_reversal_count = 0;
ulong  g_pending_ticket = 0;
int    g_execution_lock_handle = INVALID_HANDLE;
bool   g_duplicate_exposure_logged = false;
int    g_transition_phase = TRANSITION_NONE;
long   g_transition_id = 0;
datetime g_last_candle_entry_bar_time = 0;
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
bool   g_reset_pending = false;
int    g_start_operation_minutes = 0;
int    g_end_operation_minutes = 24 * 60;

void MultiClearAll();

string StatePrefix()
  {
   return "NMR." + IntegerToString((long)AccountInfoInteger(ACCOUNT_LOGIN))
          + "." + _Symbol + "." + IntegerToString((long)InpMagicNumber);
  }

string SanitizeExecutionLockPart(string value)
  {
   StringReplace(value, "\\", "_");
   StringReplace(value, "/", "_");
   StringReplace(value, ":", "_");
   StringReplace(value, "*", "_");
   StringReplace(value, "?", "_");
   StringReplace(value, "\"", "_");
   StringReplace(value, "<", "_");
   StringReplace(value, ">", "_");
   StringReplace(value, "|", "_");
   StringReplace(value, " ", "_");
   return value;
  }

string ExecutionLockFileName()
  {
   string name = "NMR_lock_" + SanitizeExecutionLockPart(AccountInfoString(ACCOUNT_SERVER))
                 + "_" + IntegerToString((long)AccountInfoInteger(ACCOUNT_LOGIN))
                 + "_" + SanitizeExecutionLockPart(_Symbol)
                 + "_" + IntegerToString((long)InpMagicNumber);
   if(MQLInfoInteger(MQL_TESTER))
      name += "_tester_" + IntegerToString((long)ChartID());
   return name + ".lck";
  }

bool AcquireExecutionOwnership()
  {
   if(g_execution_lock_handle != INVALID_HANDLE)
      return true;

   ResetLastError();
   g_execution_lock_handle = FileOpen(ExecutionLockFileName(),
                                      FILE_COMMON | FILE_BIN | FILE_READ | FILE_WRITE);
   if(g_execution_lock_handle == INVALID_HANDLE)
     {
      PrintFormat("Execution ownership unavailable for account=%I64d, symbol=%s, magic=%I64u; "
                  "another EA instance is already managing this scope. error=%d",
                  AccountInfoInteger(ACCOUNT_LOGIN), _Symbol, InpMagicNumber, GetLastError());
      return false;
     }
   return true;
  }

void ReleaseExecutionOwnership()
  {
   if(g_execution_lock_handle == INVALID_HANDLE)
      return;
   FileClose(g_execution_lock_handle);
   g_execution_lock_handle = INVALID_HANDLE;
  }

void SaveState()
  {
   const string prefix = StatePrefix();
   GlobalVariableSet(prefix + ".index", (double)g_cycle_index);
   GlobalVariableSet(prefix + ".pending", (double)g_pending_index);
   GlobalVariableSet(prefix + ".reversals", (double)g_reversal_count);
   GlobalVariableSet(prefix + ".pendingticket", (double)g_pending_ticket);
   GlobalVariableSet(prefix + ".candleentrybar", (double)g_last_candle_entry_bar_time);
   GlobalVariableSet(prefix + ".meta", (double)(g_active_first_direction + g_active_cycle_mode * 2));
   GlobalVariableSet(prefix + ".slpoints", (double)g_group_stop_points);
   GlobalVariableSet(prefix + ".tppoints", (double)g_group_take_profit_points);
   GlobalVariableSet(prefix + ".cumlots", g_cumulative_loss_lots);
   GlobalVariableSet(prefix + ".prevgridlots", g_previous_grid_lots);
   GlobalVariableSet(prefix + ".gridlots", g_grid_lots);
   GlobalVariableSet(prefix + ".grouptotal", g_group_total_lots);
   GlobalVariableSet(prefix + ".anchor", g_group_anchor_price);
   GlobalVariableSet(prefix + ".lastentry", g_group_last_entry);
   GlobalVariableSet(prefix + ".linearextreme", g_group_linear_extreme);
   GlobalVariableSet(prefix + ".gridlevel", (double)g_grid_filled_levels);
   GlobalVariableSet(prefix + ".gridpendinglevel", (double)g_grid_pending_level);
   GlobalVariableSet(prefix + ".gridpendingprice", g_grid_pending_price);
   GlobalVariableSet(prefix + ".reset", g_reset_pending ? 1.0 : 0.0);
   GlobalVariableSet(prefix + ".transitionphase", (double)g_transition_phase);
   GlobalVariableSet(prefix + ".transitionid", (double)g_transition_id);
  }

void ClearState()
  {
   const string prefix = StatePrefix();
   GlobalVariableDel(prefix + ".index");
   GlobalVariableDel(prefix + ".pending");
   GlobalVariableDel(prefix + ".reversals");
   GlobalVariableDel(prefix + ".pendingticket");
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
   GlobalVariableDel(prefix + ".reset");
   GlobalVariableDel(prefix + ".transitionphase");
   GlobalVariableDel(prefix + ".transitionid");
   g_had_position = false;
   g_last_position_type = POSITION_TYPE_BUY;
   g_last_take_profit = 0.0;
   g_cycle_index = 0;
   g_pending_index = -1;
   g_reversal_count = 0;
   g_pending_ticket = 0;
   g_transition_phase = TRANSITION_NONE;
   g_transition_id = 0;
   g_reset_pending = false;
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
   if(GlobalVariableCheck(prefix + ".candleentrybar"))
      g_last_candle_entry_bar_time = (datetime)MathRound(GlobalVariableGet(prefix + ".candleentrybar"));
   if(!GlobalVariableCheck(prefix + ".index") || !GlobalVariableCheck(prefix + ".meta"))
      return;

   if(GlobalVariableCheck(prefix + ".reset"))
      g_reset_pending = GlobalVariableGet(prefix + ".reset") > 0.5;
   if(GlobalVariableCheck(prefix + ".transitionphase"))
      g_transition_phase = (int)MathRound(GlobalVariableGet(prefix + ".transitionphase"));
   if(GlobalVariableCheck(prefix + ".transitionid"))
      g_transition_id = (long)MathRound(GlobalVariableGet(prefix + ".transitionid"));

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
   if(GlobalVariableCheck(prefix + ".reversals"))
      g_reversal_count = (int)MathRound(GlobalVariableGet(prefix + ".reversals"));
   if(GlobalVariableCheck(prefix + ".pendingticket"))
      g_pending_ticket = (ulong)MathRound(GlobalVariableGet(prefix + ".pendingticket"));
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

int PriceDigits()
  {
   return (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
  }

double PriceNormalize(const double price)
  {
   return NormalizeDouble(price, PriceDigits());
  }

int ParseTimeMinutes(const string value)
  {
   const int separator = StringFind(value, ":");
   if(separator <= 0 || separator >= StringLen(value) - 1)
      return -1;
   const int hour = (int)StringToInteger(StringSubstr(value, 0, separator));
   const int minute = (int)StringToInteger(StringSubstr(value, separator + 1));
   if(hour < 0 || hour > 23 || minute < 0 || minute > 59)
      return -1;
   return hour * 60 + minute;
  }

bool IsInitialEntryAllowed()
  {
   MqlDateTime current_time;
   TimeToStruct(TimeCurrent(), current_time);
   const int current_minutes = current_time.hour * 60 + current_time.min;
   if(g_start_operation_minutes == g_end_operation_minutes)
      return true;
   if(g_start_operation_minutes < g_end_operation_minutes)
      return current_minutes >= g_start_operation_minutes
             && current_minutes < g_end_operation_minutes;
   return current_minutes >= g_start_operation_minutes
          || current_minutes < g_end_operation_minutes;
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

bool FindPositionByTicket(const ulong wanted_ticket, ulong &ticket, long &type,
                          double &volume, double &open_price, double &stop_loss,
                          double &take_profit)
  {
   if(!IsOurPosition(wanted_ticket))
      return false;
   ticket = wanted_ticket;
   type = PositionGetInteger(POSITION_TYPE);
   volume = PositionGetDouble(POSITION_VOLUME);
   open_price = PositionGetDouble(POSITION_PRICE_OPEN);
   stop_loss = PositionGetDouble(POSITION_SL);
   take_profit = PositionGetDouble(POSITION_TP);
   return true;
  }

bool FindPositionByPendingOrder(const ulong pending_order_ticket, ulong &ticket, long &type,
                                double &volume, double &open_price, double &stop_loss,
                                double &take_profit)
  {
   if(pending_order_ticket == 0 || !HistorySelect(0, TimeCurrent()))
      return false;
   for(int index = HistoryDealsTotal() - 1; index >= 0; index--)
     {
      const ulong deal_ticket = HistoryDealGetTicket(index);
      if(deal_ticket == 0
         || (ulong)HistoryDealGetInteger(deal_ticket, DEAL_ORDER) != pending_order_ticket
         || HistoryDealGetInteger(deal_ticket, DEAL_ENTRY) != DEAL_ENTRY_IN
         || HistoryDealGetString(deal_ticket, DEAL_SYMBOL) != _Symbol
         || (ulong)HistoryDealGetInteger(deal_ticket, DEAL_MAGIC) != InpMagicNumber)
         continue;
      const ulong position_ticket = (ulong)HistoryDealGetInteger(deal_ticket, DEAL_POSITION_ID);
      if(FindPositionByTicket(position_ticket, ticket, type, volume, open_price,
                              stop_loss, take_profit))
         return true;
     }
   return false;
  }

double TotalPositionVolume(const long position_type)
  {
   double total = 0.0;
   for(int index = PositionsTotal() - 1; index >= 0; index--)
     {
      const ulong candidate = PositionGetTicket(index);
      if(!IsOurPosition(candidate) || PositionGetInteger(POSITION_TYPE) != position_type)
         continue;
      total += PositionGetDouble(POSITION_VOLUME);
     }
   return total;
  }

bool CloseAllPositions(const long position_type)
  {
   bool closed = true;
   for(int index = PositionsTotal() - 1; index >= 0; index--)
     {
      const ulong candidate = PositionGetTicket(index);
      if(!IsOurPosition(candidate) || PositionGetInteger(POSITION_TYPE) != position_type)
         continue;
      if(!g_trade.PositionClose(candidate))
        {
         PrintFormat("PositionClose failed, ticket=%I64u, retcode=%u, %s",
                     candidate, g_trade.ResultRetcode(), g_trade.ResultRetcodeDescription());
         closed = false;
        }
     }
   return closed;
  }

bool HasOurPosition()
  {
   for(int index = 0; index < PositionsTotal(); index++)
      if(IsOurPosition(PositionGetTicket(index)))
         return true;
   return false;
  }

bool CloseAllOurPositions()
  {
   bool closed = true;
   for(int index = PositionsTotal() - 1; index >= 0; index--)
     {
      const ulong candidate = PositionGetTicket(index);
      if(!IsOurPosition(candidate))
         continue;
      if(!g_trade.PositionClose(candidate))
        {
         PrintFormat("Position close during reset failed, ticket=%I64u, retcode=%u, %s",
                     candidate, g_trade.ResultRetcode(), g_trade.ResultRetcodeDescription());
         closed = false;
        }
     }
   return closed && !HasOurPosition();
  }

bool IsReversePendingType(const long order_type)
  {
   return order_type == ORDER_TYPE_BUY_STOP || order_type == ORDER_TYPE_BUY_LIMIT
          || order_type == ORDER_TYPE_SELL_STOP || order_type == ORDER_TYPE_SELL_LIMIT;
  }

bool IsGridPendingComment(const string comment)
  {
   return StringFind(comment, ".Grid") >= 0;
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
         || !IsReversePendingType(OrderGetInteger(ORDER_TYPE))
         || IsGridPendingComment(OrderGetString(ORDER_COMMENT)))
         continue;

      ticket = candidate;
      type = OrderGetInteger(ORDER_TYPE);
      volume = OrderGetDouble(ORDER_VOLUME_CURRENT);
      price = OrderGetDouble(ORDER_PRICE_OPEN);
      return true;
     }
   return false;
  }

bool FindGridPending(ulong &ticket, long &type, double &volume, double &price)
  {
   for(int index = 0; index < OrdersTotal(); index++)
     {
      const ulong candidate = OrderGetTicket(index);
      if(candidate == 0)
         continue;
      if(OrderGetString(ORDER_SYMBOL) != _Symbol
         || (ulong)OrderGetInteger(ORDER_MAGIC) != InpMagicNumber
         || !IsReversePendingType(OrderGetInteger(ORDER_TYPE))
         || !IsGridPendingComment(OrderGetString(ORDER_COMMENT)))
         continue;

      ticket = candidate;
      type = OrderGetInteger(ORDER_TYPE);
      volume = OrderGetDouble(ORDER_VOLUME_CURRENT);
      price = OrderGetDouble(ORDER_PRICE_OPEN);
      return true;
     }
   return false;
  }

bool DeletePendingTicket(const ulong ticket, const string operation)
  {
   const bool requested = g_trade.OrderDelete(ticket);
   const uint retcode = g_trade.ResultRetcode();
   if(requested && retcode == TRADE_RETCODE_DONE)
      return true;
   PrintFormat("%s failed, ticket=%I64u, retcode=%u, %s",
               operation, ticket, retcode, g_trade.ResultRetcodeDescription());
   return false;
  }

bool NormalizeSingleGroupPending(const bool grid, const long expected_direction,
                                 const double expected_price,
                                 const double expected_volume, ulong &keep_ticket)
  {
   keep_ticket = 0;
   bool tracked_ticket_filled = false;
   if(!grid && g_pending_ticket > 0 && HistoryOrderSelect(g_pending_ticket))
      tracked_ticket_filled = HistoryOrderGetInteger(g_pending_ticket, ORDER_STATE)
                              == ORDER_STATE_FILLED;
   const double price_tolerance = _Point * 0.5;
   const double volume_tolerance = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP) * 0.5;
   for(int index = 0; index < OrdersTotal(); index++)
     {
      const ulong candidate = OrderGetTicket(index);
      if(candidate == 0
         || OrderGetString(ORDER_SYMBOL) != _Symbol
         || (ulong)OrderGetInteger(ORDER_MAGIC) != InpMagicNumber
         || !IsReversePendingType(OrderGetInteger(ORDER_TYPE))
         || IsGridPendingComment(OrderGetString(ORDER_COMMENT)) != grid)
         continue;
      if(!tracked_ticket_filled
         && PendingDirection(OrderGetInteger(ORDER_TYPE)) == expected_direction
         && MathAbs(OrderGetDouble(ORDER_PRICE_OPEN) - expected_price) <= price_tolerance
         && MathAbs(OrderGetDouble(ORDER_VOLUME_CURRENT) - expected_volume) <= volume_tolerance
         && (keep_ticket == 0 || candidate < keep_ticket))
         keep_ticket = candidate;
     }

   bool normalized = true;
   for(int index = OrdersTotal() - 1; index >= 0; index--)
     {
      const ulong candidate = OrderGetTicket(index);
      if(candidate == 0 || candidate == keep_ticket
         || OrderGetString(ORDER_SYMBOL) != _Symbol
         || (ulong)OrderGetInteger(ORDER_MAGIC) != InpMagicNumber
         || !IsReversePendingType(OrderGetInteger(ORDER_TYPE))
         || IsGridPendingComment(OrderGetString(ORDER_COMMENT)) != grid)
         continue;
      if(!DeletePendingTicket(candidate, "Pending reconciliation delete"))
         normalized = false;
     }

   if(!normalized)
      return false;
   if(!grid && tracked_ticket_filled)
      return false;
   if(!grid && g_pending_ticket != keep_ticket)
     {
      g_pending_ticket = keep_ticket;
      SaveState();
     }
   return normalized;
  }

bool HasDuplicateSingleGroupExposure()
  {
   int base_positions = 0;
   for(int index = 0; index < PositionsTotal(); index++)
     {
      const ulong ticket = PositionGetTicket(index);
      if(!IsOurPosition(ticket))
         continue;
      if(!IsGridPendingComment(PositionGetString(POSITION_COMMENT)))
        {
         base_positions++;
         if(base_positions > 1)
            return true;
        }
     }

   const double price_tolerance = _Point * 0.5;
   const double volume_tolerance = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP) * 0.5;
   for(int left = 0; left < PositionsTotal(); left++)
     {
      const ulong left_ticket = PositionGetTicket(left);
      if(!IsOurPosition(left_ticket)
         || !IsGridPendingComment(PositionGetString(POSITION_COMMENT)))
         continue;
      const long left_type = PositionGetInteger(POSITION_TYPE);
      const double left_price = PositionGetDouble(POSITION_PRICE_OPEN);
      const double left_volume = PositionGetDouble(POSITION_VOLUME);
      for(int right = left + 1; right < PositionsTotal(); right++)
        {
         const ulong right_ticket = PositionGetTicket(right);
         if(!IsOurPosition(right_ticket)
            || !IsGridPendingComment(PositionGetString(POSITION_COMMENT)))
            continue;
         if(PositionGetInteger(POSITION_TYPE) == left_type
            && MathAbs(PositionGetDouble(POSITION_PRICE_OPEN) - left_price) <= price_tolerance
            && MathAbs(PositionGetDouble(POSITION_VOLUME) - left_volume) <= volume_tolerance)
            return true;
        }
     }
   return false;
  }

bool DeleteAllPending()
  {
   const ulong tracked_ticket = g_pending_ticket;
   bool deleted = true;
   for(int index = OrdersTotal() - 1; index >= 0; index--)
     {
      const ulong ticket = OrderGetTicket(index);
      if(ticket == 0)
         continue;
      if(OrderGetString(ORDER_SYMBOL) == _Symbol
         && (ulong)OrderGetInteger(ORDER_MAGIC) == InpMagicNumber
         && IsReversePendingType(OrderGetInteger(ORDER_TYPE)))
        {
         if(!DeletePendingTicket(ticket, "Delete all pending"))
             deleted = false;
        }
     }
   ulong active_ticket = 0;
   long active_type = 0;
   double active_volume = 0.0;
   double active_price = 0.0;
   if(FindPending(active_ticket, active_type, active_volume, active_price))
      g_pending_ticket = active_ticket;
   else if(tracked_ticket > 0 && HistoryOrderSelect(tracked_ticket))
     {
      const long tracked_state = HistoryOrderGetInteger(tracked_ticket, ORDER_STATE);
      if(tracked_state == ORDER_STATE_CANCELED || tracked_state == ORDER_STATE_EXPIRED
         || tracked_state == ORDER_STATE_REJECTED)
         g_pending_ticket = 0;
     }
   return deleted && !HasOurPending();
  }

int GetReversePendingStatus()
  {
   if(g_pending_ticket == 0)
      return REVERSE_PENDING_UNKNOWN;

   if(OrderSelect(g_pending_ticket))
     {
      if(OrderGetString(ORDER_SYMBOL) == _Symbol
         && (ulong)OrderGetInteger(ORDER_MAGIC) == InpMagicNumber
         && IsReversePendingType(OrderGetInteger(ORDER_TYPE))
         && !IsGridPendingComment(OrderGetString(ORDER_COMMENT)))
         return REVERSE_PENDING_ACTIVE;
     }

   if(!HistoryOrderSelect(g_pending_ticket))
      return REVERSE_PENDING_UNKNOWN;
   const long state = HistoryOrderGetInteger(g_pending_ticket, ORDER_STATE);
   if(state == ORDER_STATE_FILLED)
      return REVERSE_PENDING_FILLED;
   if(state == ORDER_STATE_CANCELED || state == ORDER_STATE_EXPIRED
      || state == ORDER_STATE_REJECTED)
      return REVERSE_PENDING_CANCELED;
   return REVERSE_PENDING_UNKNOWN;
  }

bool HasOurPending()
  {
   ulong ticket = 0;
   long type = 0;
   double volume = 0.0;
   double price = 0.0;
   if(FindPending(ticket, type, volume, price))
      return true;
   if(FindGridPending(ticket, type, volume, price))
      return true;
   return false;
  }

void BeginFullReset(const string reason)
  {
   Print(reason);
   MultiClearAll();
   g_reset_pending = true;
   g_had_position = false;
   g_last_position_type = POSITION_TYPE_BUY;
   g_last_take_profit = 0.0;
   g_cycle_index = 0;
   g_pending_index = -1;
   g_reversal_count = 0;
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
   SaveState();
   DeleteAllPending();
   if(CloseAllOurPositions() && !HasOurPending())
      ClearState();
  }

void BeginResetAfterNoMoney()
  {
   BeginFullReset("Insufficient funds: clearing all EA positions and pending orders, then restarting from the next tick.");
  }

void BeginResetAfterMaxReversals()
  {
   BeginFullReset("Maximum reversal count reached: clearing all EA positions and pending orders, then restarting from the next tick.");
  }

bool ProcessReset()
  {
   DeleteAllPending();
   if(!CloseAllOurPositions() || HasOurPosition() || HasOurPending())
      return false;
   ClearState();
   return true;
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

double GroupStopPrice(const long type)
  {
   if(type == POSITION_TYPE_BUY)
      return PriceNormalize(g_group_anchor_price - g_group_stop_points * _Point);
   return PriceNormalize(g_group_anchor_price + g_group_stop_points * _Point);
  }

double GroupTakeProfitPrice(const long type)
  {
   double reference_price = g_group_last_entry;
   if(InpTakeProfitMode == TAKE_PROFIT_LINEAR && g_group_linear_extreme > 0.0)
      reference_price = g_group_linear_extreme;
   if(type == POSITION_TYPE_BUY)
      return PriceNormalize(reference_price + g_group_take_profit_points * _Point);
   return PriceNormalize(reference_price - g_group_take_profit_points * _Point);
   }

bool SetGroupStops(const long type)
  {
   const double stop_loss = GroupStopPrice(type);
   const double take_profit = GroupTakeProfitPrice(type);
   bool modified = true;
   for(int index = PositionsTotal() - 1; index >= 0; index--)
     {
      const ulong candidate = PositionGetTicket(index);
      if(!IsOurPosition(candidate) || PositionGetInteger(POSITION_TYPE) != type)
          continue;
       const double current_stop_loss = PositionGetDouble(POSITION_SL);
       const double current_take_profit = PositionGetDouble(POSITION_TP);
       if(MathAbs(current_stop_loss - stop_loss) <= _Point * 0.5
          && MathAbs(current_take_profit - take_profit) <= _Point * 0.5)
          continue;
       if(!g_trade.PositionModify(candidate, stop_loss, take_profit))
        {
         PrintFormat("Group PositionModify failed, ticket=%I64u, retcode=%u, %s",
                     candidate, g_trade.ResultRetcode(), g_trade.ResultRetcodeDescription());
         modified = false;
        }
     }
   g_last_take_profit = take_profit;
   return modified;
   }

bool UpdateLinearTakeProfit(const long type)
  {
   if(InpTakeProfitMode != TAKE_PROFIT_LINEAR
      || g_group_take_profit_points <= 0 || g_group_anchor_price <= 0.0)
      return false;

   const double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   const double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   const double reference_price = type == POSITION_TYPE_BUY ? ask : bid;
   bool extreme_changed = false;
   if(g_group_linear_extreme <= 0.0)
      {
       g_group_linear_extreme = g_group_anchor_price;
       extreme_changed = true;
      }
   if(type == POSITION_TYPE_BUY && reference_price < g_group_linear_extreme)
      {
       g_group_linear_extreme = reference_price;
       extreme_changed = true;
      }
   else if(type == POSITION_TYPE_SELL && reference_price > g_group_linear_extreme)
      {
       g_group_linear_extreme = reference_price;
       extreme_changed = true;
      }

   const double desired_stop_loss = GroupStopPrice(type);
   const double desired_take_profit = GroupTakeProfitPrice(type);
   bool needs_modify = extreme_changed;
   for(int index = PositionsTotal() - 1; index >= 0; index--)
      {
       const ulong candidate = PositionGetTicket(index);
       if(!IsOurPosition(candidate) || PositionGetInteger(POSITION_TYPE) != type)
          continue;
       if(MathAbs(PositionGetDouble(POSITION_SL) - desired_stop_loss) > _Point * 0.5
          || MathAbs(PositionGetDouble(POSITION_TP) - desired_take_profit) > _Point * 0.5)
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

   const uint retcode = g_trade.ResultRetcode();
   if(!sent || retcode == TRADE_RETCODE_NO_MONEY)
     {
      PrintFormat("Market order failed, retcode=%u, %s",
                  retcode, g_trade.ResultRetcodeDescription());
      if(retcode == TRADE_RETCODE_NO_MONEY)
         BeginResetAfterNoMoney();
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

bool PlaceNextPending(const long next_direction, const double stop_loss,
                      const double take_profit, const double current_volume)
  {
   if(g_reversal_count >= 最大反手次数 || stop_loss <= 0.0 || current_volume <= 0.0)
      return false;

   int stop_loss_points = 0;
   int take_profit_points = 0;
   if(!GetActiveDistancePoints(stop_loss, take_profit, stop_loss_points, take_profit_points))
      return false;

   const double volume = NextGroupLots(current_volume);
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
   g_pending_ticket = g_trade.ResultOrder();
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

double GridLevelPrice(const long position_type, const int level)
  {
   if(InpGridCount <= 0 || g_group_stop_points <= 0 || g_group_anchor_price <= 0.0)
      return 0.0;
   const double distance = g_group_stop_points * _Point * level / InpGridCount;
   if(position_type == POSITION_TYPE_BUY)
      return PriceNormalize(g_group_anchor_price - distance);
   return PriceNormalize(g_group_anchor_price + distance);
  }

bool PlaceGridPending(const long position_type, const int level)
  {
   if(InpGridCount < 2 || level <= 0 || level >= InpGridCount
      || g_grid_lots <= 0.0 || g_group_anchor_price <= 0.0)
      return false;

   const double entry = GridLevelPrice(position_type, level);
   const double stop_loss = GroupStopPrice(position_type);
   const double take_profit = position_type == POSITION_TYPE_BUY
                              ? PriceNormalize(entry + g_group_take_profit_points * _Point)
                              : PriceNormalize(entry - g_group_take_profit_points * _Point);
   const double volume = VolumeNormalize(g_grid_lots);
   const long pending_type = PendingTypeForDirection(position_type == POSITION_TYPE_BUY
                                                     ? ORDER_TYPE_BUY : ORDER_TYPE_SELL,
                                                     entry);
   const string grid_comment = InpOrderComment + ".Grid";
   bool sent = false;
   if(pending_type == ORDER_TYPE_BUY_STOP || pending_type == ORDER_TYPE_BUY_LIMIT)
     {
      if(pending_type == ORDER_TYPE_BUY_STOP)
         sent = g_trade.BuyStop(volume, entry, _Symbol, stop_loss, take_profit,
                                ORDER_TIME_GTC, 0, grid_comment);
      else
         sent = g_trade.BuyLimit(volume, entry, _Symbol, stop_loss, take_profit,
                                 ORDER_TIME_GTC, 0, grid_comment);
     }
   else
     {
      if(pending_type == ORDER_TYPE_SELL_STOP)
         sent = g_trade.SellStop(volume, entry, _Symbol, stop_loss, take_profit,
                                 ORDER_TIME_GTC, 0, grid_comment);
      else
         sent = g_trade.SellLimit(volume, entry, _Symbol, stop_loss, take_profit,
                                  ORDER_TIME_GTC, 0, grid_comment);
     }
   if(!sent)
     {
      PrintFormat("Grid pending failed, retcode=%u, %s",
                  g_trade.ResultRetcode(), g_trade.ResultRetcodeDescription());
      return false;
     }
   g_grid_pending_level = level;
   g_grid_pending_price = entry;
   SaveState();
   return true;
  }

bool HandleGridFill(const long position_type, const double previous_total_lots)
  {
   if(g_grid_pending_level <= 0)
      return false;
   ulong grid_ticket = 0;
   long grid_type = 0;
   double grid_volume = 0.0;
   double grid_price = 0.0;
   if(FindGridPending(grid_ticket, grid_type, grid_volume, grid_price))
      return false;

   const double current_total_lots = TotalPositionVolume(position_type);
   const double volume_tolerance = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP) * 0.5;
   if(current_total_lots <= previous_total_lots + volume_tolerance)
      return false;

   const int filled_level = g_grid_pending_level;
   const double pending_price = g_grid_pending_price;
   g_grid_filled_levels = filled_level;
   g_grid_pending_level = 0;
   g_grid_pending_price = 0.0;
   g_group_total_lots = current_total_lots;
   g_group_last_entry = pending_price > 0.0 ? pending_price : GridLevelPrice(position_type, filled_level);
   SetGroupStops(position_type);
   SaveState();
   return true;
  }

void EnsureGridPending(const long position_type)
  {
   if(InpGridCount < 2 || g_grid_filled_levels >= InpGridCount - 1)
      return;
   const int expected_level = g_grid_filled_levels + 1;
   const long expected_direction = position_type == POSITION_TYPE_BUY
                                   ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   const double expected_price = GridLevelPrice(position_type, expected_level);
   const double expected_volume = VolumeNormalize(g_grid_lots);
   ulong grid_ticket = 0;
   if(!NormalizeSingleGroupPending(true, expected_direction, expected_price,
                                   expected_volume, grid_ticket))
      return;
   if(grid_ticket > 0)
     {
      if(g_grid_pending_level != expected_level
         || MathAbs(g_grid_pending_price - expected_price) > _Point * 0.5)
        {
         g_grid_pending_level = expected_level;
         g_grid_pending_price = expected_price;
         SaveState();
        }
      return;
     }
   g_grid_pending_level = 0;
   g_grid_pending_price = 0.0;
   PlaceGridPending(position_type, expected_level);
  }

void EnsureNextPending(const long position_type, const double stop_loss,
                       const double take_profit, const double fallback_volume)
  {
   if(g_reversal_count >= 最大反手次数)
      return;

   const long expected_direction = SequenceDirection(NextCycleIndex());
   const double expected_volume = NextGroupLots(fallback_volume);
   const double expected_price = PriceNormalize(stop_loss);
   ulong active_pending = 0;
   if(!NormalizeSingleGroupPending(false, expected_direction, expected_price,
                                   expected_volume, active_pending))
      return;
   if(active_pending == 0)
      PlaceNextPending(expected_direction, stop_loss, take_profit, fallback_volume);
  }

bool Transition(const long position_type, const double volume,
                const double stop_loss, const double take_profit)
  {
   if(g_reversal_count >= 最大反手次数)
     {
      BeginResetAfterMaxReversals();
      return false;
     }

   const int next_index = NextCycleIndex();
   const long next_type = SequenceDirection(next_index);
   int next_stop_points = 0;
   int next_take_profit_points = 0;
   const bool can_open_next = GetActiveDistancePoints(stop_loss, take_profit,
                                                      next_stop_points, next_take_profit_points);
   if(!DeleteAllPending())
      return false;
   if(GetReversePendingStatus() == REVERSE_PENDING_FILLED)
      return false;
   if(HasDuplicateSingleGroupExposure())
      return false;
   g_cumulative_loss_lots += g_group_total_lots > 0.0 ? g_group_total_lots : volume;
   g_previous_grid_lots = g_grid_lots;
   if(!CloseAllPositions(position_type))
      return false;
   g_reversal_count++;
   g_cycle_index = next_index;
   g_pending_index = -1;
   g_group_stop_points = next_stop_points;
   g_group_take_profit_points = next_take_profit_points;
   g_transition_phase = TRANSITION_PREPARED;
   g_transition_id = (long)TimeCurrent() * 1000 + g_reversal_count;
   SaveState();
   if(!can_open_next)
      return true;
    const double next_group_lots = VolumeNormalize(g_cumulative_loss_lots * 首单手数倍数);
   if(!OpenMarket(next_type, next_group_lots))
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
    g_group_anchor_price = next_entry;
    g_group_last_entry = next_entry;
    g_group_linear_extreme = next_entry;
   g_group_total_lots = TotalPositionVolume(next_position_type);
   g_grid_filled_levels = 0;
   g_grid_pending_level = 0;
   g_grid_pending_price = 0.0;
   g_grid_lots = VolumeNormalize(g_previous_grid_lots * InpGridLotMultiplier);
   SetGroupStops(next_position_type);
   g_transition_phase = TRANSITION_COMPLETE;
   SaveState();
   Manage();
   return true;
  }

bool ResumePreparedTransition()
  {
   if(g_transition_phase != TRANSITION_PREPARED)
      return true;

   const long expected_direction = SequenceDirection(g_cycle_index);
   const double expected_volume = VolumeNormalize(g_cumulative_loss_lots * 首单手数倍数);
   ulong ticket = 0;
   long position_type = POSITION_TYPE_BUY;
   double volume = 0.0;
   double entry = 0.0;
   double stop_loss = 0.0;
   double take_profit = 0.0;
   bool found = FindPosition(ticket, position_type, volume, entry, stop_loss, take_profit);
   if(found)
     {
      const double total = TotalPositionVolume(position_type);
      const double tolerance = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP) * 0.5;
      if(position_type != expected_direction || MathAbs(total - expected_volume) > tolerance)
        {
         PrintFormat("Transition recovery conflict, id=%I64d, expected_type=%d, expected_volume=%.2f, "
                     "actual_type=%d, actual_volume=%.2f",
                     g_transition_id, expected_direction, expected_volume, position_type, total);
         return false;
        }
     }
   else
     {
      if(!OpenMarket(expected_direction, expected_volume))
         return false;
      if(!FindPosition(ticket, position_type, volume, entry, stop_loss, take_profit))
         return false;
     }

   g_group_anchor_price = entry;
   g_group_last_entry = entry;
   g_group_linear_extreme = entry;
   g_group_total_lots = TotalPositionVolume(position_type);
   g_grid_filled_levels = 0;
   g_grid_pending_level = 0;
   g_grid_pending_price = 0.0;
   g_grid_lots = VolumeNormalize(g_previous_grid_lots * InpGridLotMultiplier);
   SetGroupStops(position_type);
   g_transition_phase = TRANSITION_COMPLETE;
   SaveState();
   return true;
  }

void Manage()
  {
   if(g_reset_pending)
     {
      ProcessReset();
      return;
     }

   if(HasDuplicateSingleGroupExposure())
     {
      DeleteAllPending();
      if(!g_duplicate_exposure_logged)
        {
         Print("Duplicate single-group exposure detected: pending orders canceled and new orders paused. "
               "Resolve duplicate positions manually before restarting this strategy scope.");
         g_duplicate_exposure_logged = true;
        }
      return;
     }
   g_duplicate_exposure_logged = false;

   if(g_transition_phase == TRANSITION_PREPARED && !ResumePreparedTransition())
      return;
   if(g_transition_phase == TRANSITION_COMPLETE)
     {
      g_transition_phase = TRANSITION_NONE;
      SaveState();
     }

   ulong position_ticket = 0;
   long position_type = POSITION_TYPE_BUY;
   double volume = 0.0;
   double entry = 0.0;
   double stop_loss = 0.0;
   double take_profit = 0.0;

   const int reverse_pending_status = GetReversePendingStatus();
   bool pending_position_found = false;
   if(reverse_pending_status == REVERSE_PENDING_FILLED && g_pending_ticket > 0)
      pending_position_found = FindPositionByTicket(g_pending_ticket, position_ticket,
                                                    position_type, volume, entry,
                                                    stop_loss, take_profit)
                               || FindPositionByPendingOrder(g_pending_ticket, position_ticket,
                                                              position_type, volume, entry,
                                                              stop_loss, take_profit);
   const bool has_position = pending_position_found
                             || FindPosition(position_ticket, position_type, volume,
                                             entry, stop_loss, take_profit);
   if(has_position)
     {
      const double previous_group_total_lots = g_group_total_lots;
      const double previous_grid_lots = g_grid_lots;
      ulong state_pending_ticket = 0;
      long state_pending_type = 0;
      double state_pending_volume = 0.0;
      double state_pending_price = 0.0;
      const bool has_state_pending = FindPending(state_pending_ticket, state_pending_type,
                                                 state_pending_volume, state_pending_price);
      const bool pending_filled = !has_state_pending
                                  && g_pending_index >= 0
                                  && g_pending_index != g_cycle_index
                                  && (g_pending_ticket == 0
                                      || (reverse_pending_status == REVERSE_PENDING_FILLED
                                          && pending_position_found));
      if(!pending_filled)
         HandleGridFill(position_type, previous_group_total_lots);
      if(pending_filled)
        {
         if(g_reversal_count >= 最大反手次数)
           {
            BeginResetAfterMaxReversals();
            return;
           }
         g_reversal_count++;
         g_cumulative_loss_lots += previous_group_total_lots;
         g_previous_grid_lots = previous_grid_lots;
         g_cycle_index = g_pending_index;
         g_pending_index = -1;
         g_pending_ticket = 0;
          g_group_anchor_price = entry;
          g_group_last_entry = entry;
          g_group_linear_extreme = entry;
         g_grid_filled_levels = 0;
         g_grid_pending_level = 0;
         g_grid_pending_price = 0.0;
         g_grid_lots = VolumeNormalize(g_previous_grid_lots * InpGridLotMultiplier);
         g_transition_phase = TRANSITION_COMPLETE;
         g_transition_id = (long)TimeCurrent() * 1000 + g_reversal_count;
        }
      volume = TotalPositionVolume(position_type);
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

      if(pending_filled)
        {
         EnsureNextPending(position_type, GroupStopPrice(position_type),
                           GroupTakeProfitPrice(position_type), volume);
         EnsureGridPending(position_type);
         SaveState();
         return;
        }

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
         EnsureNextPending(position_type, GroupStopPrice(position_type),
                           GroupTakeProfitPrice(position_type), volume);
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
         const int latest_pending_status = GetReversePendingStatus();
         if(latest_pending_status == REVERSE_PENDING_FILLED)
            return;
         if(latest_pending_status == REVERSE_PENDING_UNKNOWN
            && !has_state_pending && g_pending_ticket > 0)
            return;
         Transition(position_type, volume, stop_loss, take_profit);
         return;
        }

      EnsureNextPending(position_type, GroupStopPrice(position_type),
                        GroupTakeProfitPrice(position_type), volume);
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

   ulong pending_ticket = 0;
   long pending_type = 0;
   double pending_volume = 0.0;
   double pending_price = 0.0;
   if(HasOurPending())
      return;
   if(!IsInitialEntryAllowed())
      return;
   if(InpDistanceMode == DISTANCE_CANDLE_RANGE && Korder_type == KORDER_ONCE_PER_BAR)
     {
      const datetime current_bar_time = iTime(_Symbol, _Period, 0);
      if(current_bar_time > 0 && current_bar_time == g_last_candle_entry_bar_time)
         return;
     }

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
   const double initial_lots = g_cumulative_loss_lots > 0.0
                               ? VolumeNormalize(g_cumulative_loss_lots)
                               : VolumeNormalize(InpInitialLots);
   if(OpenMarket(first_direction, initial_lots))
     {
      if(InpDistanceMode == DISTANCE_CANDLE_RANGE && Korder_type == KORDER_ONCE_PER_BAR)
        {
         const datetime current_bar_time = iTime(_Symbol, _Period, 0);
         if(current_bar_time > 0)
            g_last_candle_entry_bar_time = current_bar_time;
        }
      if(FindPosition(position_ticket, position_type, volume, entry,
                      stop_loss, take_profit))
        {
          g_group_anchor_price = entry;
          g_group_last_entry = entry;
          g_group_linear_extreme = entry;
          g_group_total_lots = TotalPositionVolume(position_type);
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

struct MultiGroupState
  {
   int      id;
   bool     active;
   int      first_direction;
   int      cycle_mode;
   int      cycle_index;
   int      pending_index;
   int      reversal_count;
   ulong    pending_ticket;
   ulong    grid_pending_ticket;
   int      stop_points;
   int      take_profit_points;
   double   cumulative_loss_lots;
   double   previous_grid_lots;
   double   grid_lots;
   double   total_lots;
   double   anchor_price;
   double   last_entry;
   double   linear_extreme;
   int      grid_filled_levels;
   int      grid_pending_level;
   double   grid_pending_price;
  };

MultiGroupState g_multi_groups[];
datetime g_multi_last_trigger_bar = 0;
int g_multi_next_id = 1;

string MultiGroupTag(const int group_id)
  {
   return ".G" + IntegerToString(group_id);
  }

string MultiGroupComment(const int group_id, const bool grid)
  {
   return InpOrderComment + MultiGroupTag(group_id) + (grid ? ".Grid" : "");
  }

string MultiStatePrefix(const int group_id)
  {
   return StatePrefix() + ".multi." + IntegerToString(group_id);
  }

void MultiDeleteState(const int group_id)
  {
   const string prefix = MultiStatePrefix(group_id);
   GlobalVariableDel(prefix + ".active");
   GlobalVariableDel(prefix + ".first");
   GlobalVariableDel(prefix + ".mode");
   GlobalVariableDel(prefix + ".index");
   GlobalVariableDel(prefix + ".pendingindex");
   GlobalVariableDel(prefix + ".reversals");
   GlobalVariableDel(prefix + ".pendingticket");
   GlobalVariableDel(prefix + ".gridticket");
   GlobalVariableDel(prefix + ".slpoints");
   GlobalVariableDel(prefix + ".tppoints");
   GlobalVariableDel(prefix + ".cumlots");
   GlobalVariableDel(prefix + ".prevgridlots");
   GlobalVariableDel(prefix + ".gridlots");
   GlobalVariableDel(prefix + ".totallots");
   GlobalVariableDel(prefix + ".anchor");
   GlobalVariableDel(prefix + ".lastentry");
   GlobalVariableDel(prefix + ".linearextreme");
   GlobalVariableDel(prefix + ".gridlevel");
   GlobalVariableDel(prefix + ".gridpendinglevel");
   GlobalVariableDel(prefix + ".gridpendingprice");
  }

bool MultiCommentMatches(const string comment, const int group_id)
  {
   return StringFind(comment, MultiGroupTag(group_id)) >= 0;
  }

int MultiFindGroupIndex(const int group_id)
  {
   for(int index = 0; index < ArraySize(g_multi_groups); index++)
      if(g_multi_groups[index].active && g_multi_groups[index].id == group_id)
         return index;
   return -1;
  }

void MultiResetState(MultiGroupState &group, const int group_id)
  {
   group.id = group_id;
   group.active = true;
   group.first_direction = FIRST_BUY;
   group.cycle_mode = CYCLE_MODE_1;
   group.cycle_index = 0;
   group.pending_index = -1;
   group.reversal_count = 0;
   group.pending_ticket = 0;
   group.grid_pending_ticket = 0;
   group.stop_points = 0;
   group.take_profit_points = 0;
   group.cumulative_loss_lots = 0.0;
   group.previous_grid_lots = 0.0;
   group.grid_lots = 0.0;
   group.total_lots = 0.0;
   group.anchor_price = 0.0;
   group.last_entry = 0.0;
   group.linear_extreme = 0.0;
   group.grid_filled_levels = 0;
   group.grid_pending_level = 0;
   group.grid_pending_price = 0.0;
  }

void MultiClearAll()
  {
   for(int id = 1; id < g_multi_next_id; id++)
      MultiDeleteState(id);
   ArrayResize(g_multi_groups, 0);
   g_multi_last_trigger_bar = 0;
   g_multi_next_id = 1;
   GlobalVariableDel(StatePrefix() + ".multi.nextid");
  }

void MultiRemoveGroup(const int index)
  {
   if(index < 0 || index >= ArraySize(g_multi_groups))
      return;
   MultiDeleteState(g_multi_groups[index].id);
   const int last = ArraySize(g_multi_groups) - 1;
   if(index != last)
      g_multi_groups[index] = g_multi_groups[last];
   ArrayResize(g_multi_groups, last);
  }

bool MultiIsOurPosition(const ulong ticket, const int group_id)
  {
   if(ticket == 0 || !PositionSelectByTicket(ticket))
      return false;
   return PositionGetString(POSITION_SYMBOL) == _Symbol
          && (ulong)PositionGetInteger(POSITION_MAGIC) == InpMagicNumber
          && MultiCommentMatches(PositionGetString(POSITION_COMMENT), group_id);
  }

bool MultiFindPosition(const int group_id, ulong &ticket, long &type, double &volume,
                       double &entry, double &stop_loss, double &take_profit)
  {
   volume = 0.0;
   bool found = false;
   for(int index = PositionsTotal() - 1; index >= 0; index--)
     {
      const ulong candidate = PositionGetTicket(index);
      if(!MultiIsOurPosition(candidate, group_id))
         continue;
      if(!found)
        {
         ticket = candidate;
         type = PositionGetInteger(POSITION_TYPE);
         entry = PositionGetDouble(POSITION_PRICE_OPEN);
         stop_loss = PositionGetDouble(POSITION_SL);
         take_profit = PositionGetDouble(POSITION_TP);
         found = true;
        }
      volume += PositionGetDouble(POSITION_VOLUME);
     }
   return found;
  }

bool MultiFindPending(const int group_id, const bool grid, ulong &ticket, long &type,
                      double &volume, double &price)
  {
   for(int index = 0; index < OrdersTotal(); index++)
     {
      const ulong candidate = OrderGetTicket(index);
      if(candidate == 0
         || OrderGetString(ORDER_SYMBOL) != _Symbol
         || (ulong)OrderGetInteger(ORDER_MAGIC) != InpMagicNumber
         || !IsReversePendingType(OrderGetInteger(ORDER_TYPE)))
         continue;
      const string comment = OrderGetString(ORDER_COMMENT);
      if(!MultiCommentMatches(comment, group_id) || IsGridPendingComment(comment) != grid)
         continue;
      ticket = candidate;
      type = OrderGetInteger(ORDER_TYPE);
      volume = OrderGetDouble(ORDER_VOLUME_CURRENT);
      price = OrderGetDouble(ORDER_PRICE_OPEN);
      return true;
     }
   return false;
  }

void MultiSaveGroup(const MultiGroupState &group)
  {
   const string prefix = MultiStatePrefix(group.id);
   GlobalVariableSet(prefix + ".active", group.active ? 1.0 : 0.0);
   GlobalVariableSet(prefix + ".first", (double)group.first_direction);
   GlobalVariableSet(prefix + ".mode", (double)group.cycle_mode);
   GlobalVariableSet(prefix + ".index", (double)group.cycle_index);
   GlobalVariableSet(prefix + ".pendingindex", (double)group.pending_index);
   GlobalVariableSet(prefix + ".reversals", (double)group.reversal_count);
   GlobalVariableSet(prefix + ".pendingticket", (double)group.pending_ticket);
   GlobalVariableSet(prefix + ".gridticket", (double)group.grid_pending_ticket);
   GlobalVariableSet(prefix + ".slpoints", (double)group.stop_points);
   GlobalVariableSet(prefix + ".tppoints", (double)group.take_profit_points);
   GlobalVariableSet(prefix + ".cumlots", group.cumulative_loss_lots);
   GlobalVariableSet(prefix + ".prevgridlots", group.previous_grid_lots);
   GlobalVariableSet(prefix + ".gridlots", group.grid_lots);
   GlobalVariableSet(prefix + ".totallots", group.total_lots);
   GlobalVariableSet(prefix + ".anchor", group.anchor_price);
   GlobalVariableSet(prefix + ".lastentry", group.last_entry);
   GlobalVariableSet(prefix + ".linearextreme", group.linear_extreme);
   GlobalVariableSet(prefix + ".gridlevel", (double)group.grid_filled_levels);
   GlobalVariableSet(prefix + ".gridpendinglevel", (double)group.grid_pending_level);
   GlobalVariableSet(prefix + ".gridpendingprice", group.grid_pending_price);
   GlobalVariableSet(StatePrefix() + ".multi.nextid", (double)g_multi_next_id);
  }

void MultiLoadGroups()
  {
   const string next_key = StatePrefix() + ".multi.nextid";
   if(!GlobalVariableCheck(next_key))
      return;
   g_multi_next_id = (int)MathMax(1.0, MathRound(GlobalVariableGet(next_key)));
   for(int id = 1; id < g_multi_next_id; id++)
     {
      const string prefix = MultiStatePrefix(id);
      if(!GlobalVariableCheck(prefix + ".active")
         || GlobalVariableGet(prefix + ".active") < 0.5)
         continue;
      const int index = ArraySize(g_multi_groups);
      if(ArrayResize(g_multi_groups, index + 1) != index + 1)
         break;
      MultiGroupState state;
      MultiResetState(state, id);
      state.first_direction = (int)MathRound(GlobalVariableGet(prefix + ".first"));
      state.cycle_mode = (int)MathRound(GlobalVariableGet(prefix + ".mode"));
      state.cycle_index = (int)MathRound(GlobalVariableGet(prefix + ".index"));
      state.pending_index = (int)MathRound(GlobalVariableGet(prefix + ".pendingindex"));
      state.reversal_count = (int)MathRound(GlobalVariableGet(prefix + ".reversals"));
      state.pending_ticket = (ulong)MathRound(GlobalVariableGet(prefix + ".pendingticket"));
      state.grid_pending_ticket = (ulong)MathRound(GlobalVariableGet(prefix + ".gridticket"));
      state.stop_points = (int)MathRound(GlobalVariableGet(prefix + ".slpoints"));
      state.take_profit_points = (int)MathRound(GlobalVariableGet(prefix + ".tppoints"));
      state.cumulative_loss_lots = GlobalVariableGet(prefix + ".cumlots");
      state.previous_grid_lots = GlobalVariableGet(prefix + ".prevgridlots");
      state.grid_lots = GlobalVariableGet(prefix + ".gridlots");
      state.total_lots = GlobalVariableGet(prefix + ".totallots");
      state.anchor_price = GlobalVariableGet(prefix + ".anchor");
      state.last_entry = GlobalVariableGet(prefix + ".lastentry");
      state.linear_extreme = GlobalVariableGet(prefix + ".linearextreme");
      state.grid_filled_levels = (int)MathRound(GlobalVariableGet(prefix + ".gridlevel"));
      state.grid_pending_level = (int)MathRound(GlobalVariableGet(prefix + ".gridpendinglevel"));
      state.grid_pending_price = GlobalVariableGet(prefix + ".gridpendingprice");
      g_multi_groups[index] = state;
     }
  }

int MultiPendingStatus(const ulong ticket, const int group_id, const bool grid)
  {
   if(ticket == 0)
      return REVERSE_PENDING_UNKNOWN;
   if(OrderSelect(ticket))
     {
      const string comment = OrderGetString(ORDER_COMMENT);
      if(OrderGetString(ORDER_SYMBOL) == _Symbol
         && (ulong)OrderGetInteger(ORDER_MAGIC) == InpMagicNumber
         && IsReversePendingType(OrderGetInteger(ORDER_TYPE))
         && MultiCommentMatches(comment, group_id)
         && IsGridPendingComment(comment) == grid)
         return REVERSE_PENDING_ACTIVE;
     }
   if(!HistoryOrderSelect(ticket))
      return REVERSE_PENDING_UNKNOWN;
   const long state = HistoryOrderGetInteger(ticket, ORDER_STATE);
   if(state == ORDER_STATE_FILLED)
      return REVERSE_PENDING_FILLED;
   if(state == ORDER_STATE_CANCELED || state == ORDER_STATE_EXPIRED
      || state == ORDER_STATE_REJECTED)
      return REVERSE_PENDING_CANCELED;
   return REVERSE_PENDING_UNKNOWN;
  }

double MultiTotalPositionVolume(const int group_id, const long type)
  {
   double total = 0.0;
   for(int index = PositionsTotal() - 1; index >= 0; index--)
     {
      const ulong candidate = PositionGetTicket(index);
      if(MultiIsOurPosition(candidate, group_id)
         && PositionGetInteger(POSITION_TYPE) == type)
         total += PositionGetDouble(POSITION_VOLUME);
     }
   return total;
  }

bool MultiClosePositions(const int group_id)
  {
   bool closed = true;
   for(int index = PositionsTotal() - 1; index >= 0; index--)
     {
      const ulong candidate = PositionGetTicket(index);
      if(!MultiIsOurPosition(candidate, group_id))
         continue;
      if(!g_trade.PositionClose(candidate))
        {
         PrintFormat("Multi group position close failed, group=%d, ticket=%I64u, retcode=%u, %s",
                     group_id, candidate, g_trade.ResultRetcode(),
                     g_trade.ResultRetcodeDescription());
         closed = false;
        }
     }
   return closed;
  }

bool MultiDeletePending(const int group_id)
  {
   bool deleted = true;
   for(int index = OrdersTotal() - 1; index >= 0; index--)
     {
      const ulong ticket = OrderGetTicket(index);
      if(ticket == 0 || OrderGetString(ORDER_SYMBOL) != _Symbol
         || (ulong)OrderGetInteger(ORDER_MAGIC) != InpMagicNumber
         || !IsReversePendingType(OrderGetInteger(ORDER_TYPE))
         || !MultiCommentMatches(OrderGetString(ORDER_COMMENT), group_id))
         continue;
      if(!g_trade.OrderDelete(ticket))
        {
         PrintFormat("Multi group pending delete failed, group=%d, ticket=%I64u, retcode=%u, %s",
                     group_id, ticket, g_trade.ResultRetcode(),
                     g_trade.ResultRetcodeDescription());
         deleted = false;
        }
     }
   ulong remaining_ticket = 0;
   long remaining_type = 0;
   double remaining_volume = 0.0;
   double remaining_price = 0.0;
   if(MultiFindPending(group_id, false, remaining_ticket, remaining_type,
                       remaining_volume, remaining_price)
      || MultiFindPending(group_id, true, remaining_ticket, remaining_type,
                          remaining_volume, remaining_price))
      return false;
   return deleted;
  }

long MultiSequenceDirection(const MultiGroupState &group, const int index)
  {
   const int normalized = ((index % 6) + 6) % 6;
   bool buy = false;
   if(group.cycle_mode == CYCLE_MODE_1)
      buy = normalized == 0 || normalized == 3;
   else if(group.cycle_mode == CYCLE_MODE_2)
      buy = normalized == 0 || normalized == 2 || normalized == 4 || normalized == 5;
   else
      buy = normalized == 0 || normalized == 2 || normalized == 3 || normalized == 5;
   if(group.first_direction == FIRST_SELL)
      buy = !buy;
   return buy ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
  }

double MultiStopPrice(const MultiGroupState &group, const long type)
  {
   if(type == POSITION_TYPE_BUY)
      return PriceNormalize(group.anchor_price - group.stop_points * _Point);
   return PriceNormalize(group.anchor_price + group.stop_points * _Point);
  }

double MultiTakeProfitPrice(const MultiGroupState &group, const long type)
  {
   double reference = group.last_entry;
   if(InpTakeProfitMode == TAKE_PROFIT_LINEAR && group.linear_extreme > 0.0)
      reference = group.linear_extreme;
   if(type == POSITION_TYPE_BUY)
      return PriceNormalize(reference + group.take_profit_points * _Point);
   return PriceNormalize(reference - group.take_profit_points * _Point);
  }

void MultiSetStops(const MultiGroupState &group, const long type)
  {
   const double stop_loss = MultiStopPrice(group, type);
   const double take_profit = MultiTakeProfitPrice(group, type);
   for(int index = PositionsTotal() - 1; index >= 0; index--)
     {
      const ulong ticket = PositionGetTicket(index);
      if(!MultiIsOurPosition(ticket, group.id)
         || PositionGetInteger(POSITION_TYPE) != type)
         continue;
      const double old_sl = PositionGetDouble(POSITION_SL);
      const double old_tp = PositionGetDouble(POSITION_TP);
      if(MathAbs(old_sl - stop_loss) <= _Point * 0.5
         && MathAbs(old_tp - take_profit) <= _Point * 0.5)
         continue;
      if(!g_trade.PositionModify(ticket, stop_loss, take_profit))
         PrintFormat("Multi group stops modify failed, group=%d, ticket=%I64u, retcode=%u, %s",
                     group.id, ticket, g_trade.ResultRetcode(),
                     g_trade.ResultRetcodeDescription());
     }
  }

bool MultiOpenMarket(MultiGroupState &group, const long type, const double volume)
  {
   const double normalized_volume = VolumeNormalize(volume);
   if(normalized_volume <= 0.0)
      return false;
   const string comment = MultiGroupComment(group.id, false);
   bool sent = type == ORDER_TYPE_BUY
               ? g_trade.Buy(normalized_volume, _Symbol, 0.0, 0.0, 0.0, comment)
               : g_trade.Sell(normalized_volume, _Symbol, 0.0, 0.0, 0.0, comment);
   if(!sent || g_trade.ResultRetcode() == TRADE_RETCODE_NO_MONEY)
     {
      PrintFormat("Multi group market order failed, group=%d, retcode=%u, %s",
                  group.id, g_trade.ResultRetcode(), g_trade.ResultRetcodeDescription());
      if(g_trade.ResultRetcode() == TRADE_RETCODE_NO_MONEY)
         BeginResetAfterNoMoney();
      return false;
     }
   return true;
  }

double MultiNextGroupLots(const MultiGroupState &group, const double fallback)
  {
   double requested = group.cumulative_loss_lots + group.total_lots;
   if(requested <= 0.0)
      requested = fallback;
   else
      requested *= 首单手数倍数;
   return VolumeNormalize(requested);
  }

bool MultiPlaceReversePending(MultiGroupState &group, const long current_type)
  {
   if(group.reversal_count >= 最大反手次数 || group.stop_points <= 0
      || group.take_profit_points <= 0 || group.total_lots <= 0.0)
      return false;
   ulong existing_ticket = 0;
   long existing_type = 0;
   double existing_volume = 0.0;
   double existing_price = 0.0;
   if(MultiFindPending(group.id, false, existing_ticket, existing_type,
                       existing_volume, existing_price))
     {
      group.pending_ticket = existing_ticket;
      return true;
     }
   const int next_index = (group.cycle_index + 1) % 6;
   const long next_direction = MultiSequenceDirection(group, next_index);
   const double entry = MultiStopPrice(group, current_type);
   const long pending_type = PendingTypeForDirection(next_direction, entry);
   const double volume = MultiNextGroupLots(group, group.total_lots);
   const double distance_sl = group.stop_points * _Point;
   const double distance_tp = group.take_profit_points * _Point;
   double pending_sl = 0.0;
   double pending_tp = 0.0;
   bool sent = false;
   const string comment = MultiGroupComment(group.id, false);
   if(pending_type == ORDER_TYPE_BUY_STOP || pending_type == ORDER_TYPE_BUY_LIMIT)
     {
      pending_sl = PriceNormalize(entry - distance_sl);
      pending_tp = PriceNormalize(entry + distance_tp);
      sent = pending_type == ORDER_TYPE_BUY_STOP
             ? g_trade.BuyStop(volume, entry, _Symbol, pending_sl, pending_tp,
                               ORDER_TIME_GTC, 0, comment)
             : g_trade.BuyLimit(volume, entry, _Symbol, pending_sl, pending_tp,
                                ORDER_TIME_GTC, 0, comment);
     }
   else
     {
      pending_sl = PriceNormalize(entry + distance_sl);
      pending_tp = PriceNormalize(entry - distance_tp);
      sent = pending_type == ORDER_TYPE_SELL_STOP
             ? g_trade.SellStop(volume, entry, _Symbol, pending_sl, pending_tp,
                                ORDER_TIME_GTC, 0, comment)
             : g_trade.SellLimit(volume, entry, _Symbol, pending_sl, pending_tp,
                                 ORDER_TIME_GTC, 0, comment);
     }
   if(!sent)
     {
      PrintFormat("Multi group reverse pending failed, group=%d, retcode=%u, %s",
                  group.id, g_trade.ResultRetcode(), g_trade.ResultRetcodeDescription());
      return false;
     }
   group.pending_ticket = g_trade.ResultOrder();
   group.pending_index = next_index;
   return true;
  }

double MultiGridLevelPrice(const MultiGroupState &group, const long type, const int level)
  {
   if(网格数量 <= 0 || group.stop_points <= 0 || group.anchor_price <= 0.0)
      return 0.0;
   const double distance = group.stop_points * _Point * level / 网格数量;
   return type == POSITION_TYPE_BUY
          ? PriceNormalize(group.anchor_price - distance)
          : PriceNormalize(group.anchor_price + distance);
  }

bool MultiPlaceGridPending(MultiGroupState &group, const long type)
  {
   if(网格数量 < 2 || group.grid_filled_levels >= 网格数量 - 1
      || group.grid_lots <= 0.0 || group.anchor_price <= 0.0)
      return false;
   ulong existing_ticket = 0;
   long existing_type = 0;
   double existing_volume = 0.0;
   double existing_price = 0.0;
   if(MultiFindPending(group.id, true, existing_ticket, existing_type,
                       existing_volume, existing_price))
     {
      group.grid_pending_ticket = existing_ticket;
      return true;
     }
   const int level = group.grid_filled_levels + 1;
   const double entry = MultiGridLevelPrice(group, type, level);
   const long pending_type = PendingTypeForDirection(type, entry);
   const double volume = VolumeNormalize(group.grid_lots);
   const double stop_loss = MultiStopPrice(group, type);
   const double take_profit = type == POSITION_TYPE_BUY
                              ? PriceNormalize(entry + group.take_profit_points * _Point)
                              : PriceNormalize(entry - group.take_profit_points * _Point);
   const string comment = MultiGroupComment(group.id, true);
   bool sent = false;
   if(pending_type == ORDER_TYPE_BUY_STOP || pending_type == ORDER_TYPE_BUY_LIMIT)
      sent = pending_type == ORDER_TYPE_BUY_STOP
             ? g_trade.BuyStop(volume, entry, _Symbol, stop_loss, take_profit,
                               ORDER_TIME_GTC, 0, comment)
             : g_trade.BuyLimit(volume, entry, _Symbol, stop_loss, take_profit,
                                ORDER_TIME_GTC, 0, comment);
   else
      sent = pending_type == ORDER_TYPE_SELL_STOP
             ? g_trade.SellStop(volume, entry, _Symbol, stop_loss, take_profit,
                                ORDER_TIME_GTC, 0, comment)
             : g_trade.SellLimit(volume, entry, _Symbol, stop_loss, take_profit,
                                 ORDER_TIME_GTC, 0, comment);
   if(!sent)
     {
      PrintFormat("Multi group grid pending failed, group=%d, retcode=%u, %s",
                  group.id, g_trade.ResultRetcode(), g_trade.ResultRetcodeDescription());
      return false;
     }
   group.grid_pending_ticket = g_trade.ResultOrder();
   group.grid_pending_level = level;
   group.grid_pending_price = entry;
   return true;
  }

bool MultiHandleGridFill(MultiGroupState &group, const long type, const double current_total)
  {
   if(group.grid_pending_level <= 0 || group.grid_pending_ticket == 0)
      return false;
   const int status = MultiPendingStatus(group.grid_pending_ticket, group.id, true);
   if(status == REVERSE_PENDING_ACTIVE)
      return false;
   if(status == REVERSE_PENDING_FILLED
      && current_total > group.total_lots
      + SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP) * 0.5)
     {
      group.grid_filled_levels = group.grid_pending_level;
      group.grid_pending_level = 0;
      group.grid_pending_ticket = 0;
      group.total_lots = current_total;
      group.last_entry = group.grid_pending_price;
      MultiSetStops(group, type);
      return true;
     }
   if(status == REVERSE_PENDING_CANCELED)
     {
      group.grid_pending_level = 0;
      group.grid_pending_ticket = 0;
      group.grid_pending_price = 0.0;
     }
   return false;
  }

bool MultiHandleReverseFill(MultiGroupState &group, const long type, const double entry,
                            const double current_total)
  {
   if(group.pending_ticket == 0 || group.pending_index < 0
      || group.pending_index == group.cycle_index)
      return false;
   const int status = MultiPendingStatus(group.pending_ticket, group.id, false);
   if(status != REVERSE_PENDING_FILLED)
      return false;
   if(group.reversal_count >= 最大反手次数)
     {
      BeginResetAfterMaxReversals();
      return true;
     }
   group.cumulative_loss_lots += group.total_lots;
   group.previous_grid_lots = group.grid_lots;
   group.reversal_count++;
   group.cycle_index = group.pending_index;
   group.pending_index = -1;
   group.pending_ticket = 0;
   group.anchor_price = entry;
   group.last_entry = entry;
   group.linear_extreme = entry;
   group.total_lots = current_total;
   group.grid_filled_levels = 0;
   group.grid_pending_level = 0;
   group.grid_pending_ticket = 0;
   group.grid_pending_price = 0.0;
   group.grid_lots = group.previous_grid_lots > 0.0
                     ? VolumeNormalize(group.previous_grid_lots * 网格手数倍数)
                     : current_total;
   MultiSetStops(group, type);
   return true;
  }

bool MultiManageGroup(MultiGroupState &group)
  {
   ulong ticket = 0;
   long type = POSITION_TYPE_BUY;
   double total = 0.0;
   double entry = 0.0;
   double stop_loss = 0.0;
   double take_profit = 0.0;
   const bool has_position = MultiFindPosition(group.id, ticket, type, total, entry,
                                               stop_loss, take_profit);
   if(!has_position)
     {
      const int pending_status = MultiPendingStatus(group.pending_ticket, group.id, false);
      if(pending_status == REVERSE_PENDING_ACTIVE
         || pending_status == REVERSE_PENDING_FILLED)
         return true;
      MultiDeletePending(group.id);
      group.active = false;
      return false;
     }

   if(MultiHandleReverseFill(group, type, entry, total))
     {
      if(g_reset_pending)
         return false;
      MultiPlaceReversePending(group, type);
      MultiPlaceGridPending(group, type);
      return true;
     }

   if(group.stop_points <= 0 || group.take_profit_points <= 0)
     {
      const int inferred = (int)MathRound(MathAbs(take_profit - stop_loss)
                                          / (2.0 * _Point));
      if(inferred <= 0)
         return true;
      group.stop_points = inferred;
      group.take_profit_points = inferred;
      group.anchor_price = entry;
      group.last_entry = entry;
      group.linear_extreme = entry;
     }
   if(group.anchor_price <= 0.0)
      group.anchor_price = entry;
   if(group.last_entry <= 0.0)
      group.last_entry = entry;
   if(group.linear_extreme <= 0.0)
      group.linear_extreme = entry;
   group.total_lots = total;
   if(group.grid_lots <= 0.0)
      group.grid_lots = total;

   if(InpTakeProfitMode == TAKE_PROFIT_LINEAR)
     {
      const double reference = type == POSITION_TYPE_BUY
                               ? SymbolInfoDouble(_Symbol, SYMBOL_ASK)
                               : SymbolInfoDouble(_Symbol, SYMBOL_BID);
      if((type == POSITION_TYPE_BUY && reference < group.linear_extreme)
         || (type == POSITION_TYPE_SELL && reference > group.linear_extreme))
        {
         group.linear_extreme = reference;
         MultiSetStops(group, type);
        }
     }

   const double desired_stop_loss = MultiStopPrice(group, type);
   const double desired_take_profit = MultiTakeProfitPrice(group, type);
   if((type == POSITION_TYPE_BUY && SymbolInfoDouble(_Symbol, SYMBOL_BID) >= desired_take_profit)
      || (type == POSITION_TYPE_SELL && SymbolInfoDouble(_Symbol, SYMBOL_ASK) <= desired_take_profit))
     {
      MultiDeletePending(group.id);
      if(MultiClosePositions(group.id))
         group.active = false;
      return false;
     }

   if((type == POSITION_TYPE_BUY && SymbolInfoDouble(_Symbol, SYMBOL_BID) <= desired_stop_loss)
      || (type == POSITION_TYPE_SELL && SymbolInfoDouble(_Symbol, SYMBOL_ASK) >= desired_stop_loss))
     {
      const int pending_status = MultiPendingStatus(group.pending_ticket, group.id, false);
      ulong active_reverse_ticket = 0;
      long active_reverse_type = 0;
      double active_reverse_volume = 0.0;
      double active_reverse_price = 0.0;
      const bool has_active_reverse = MultiFindPending(group.id, false,
                                                        active_reverse_ticket,
                                                        active_reverse_type,
                                                        active_reverse_volume,
                                                        active_reverse_price);
      if(pending_status == REVERSE_PENDING_FILLED)
         return true;
      if(pending_status == REVERSE_PENDING_UNKNOWN
         && !has_active_reverse && group.pending_ticket > 0)
         return true;
      if(group.reversal_count >= 最大反手次数)
        {
         BeginResetAfterMaxReversals();
         return false;
        }
      if(!MultiDeletePending(group.id))
         return true;
      group.cumulative_loss_lots += group.total_lots;
      group.previous_grid_lots = group.grid_lots;
      if(!MultiClosePositions(group.id))
         return false;
      const int next_index = (group.cycle_index + 1) % 6;
      const long next_type = MultiSequenceDirection(group, next_index);
      group.reversal_count++;
      group.cycle_index = next_index;
      group.pending_index = -1;
      group.pending_ticket = 0;
      const double next_lots = VolumeNormalize(group.cumulative_loss_lots * 首单手数倍数);
      if(!MultiOpenMarket(group, next_type, next_lots))
         return false;
      if(!MultiFindPosition(group.id, ticket, type, total, entry, stop_loss, take_profit))
         return false;
      group.anchor_price = entry;
      group.last_entry = entry;
      group.linear_extreme = entry;
      group.total_lots = total;
      group.grid_filled_levels = 0;
      group.grid_pending_level = 0;
      group.grid_pending_ticket = 0;
      group.grid_pending_price = 0.0;
      group.grid_lots = group.previous_grid_lots > 0.0
                        ? VolumeNormalize(group.previous_grid_lots * 网格手数倍数)
                        : total;
      MultiSetStops(group, type);
      MultiPlaceReversePending(group, type);
      MultiPlaceGridPending(group, type);
      return true;
     }

   MultiHandleGridFill(group, type, total);
   MultiPlaceReversePending(group, type);
   MultiPlaceGridPending(group, type);
   return true;
  }

bool MultiTryOpenCandleGroup()
  {
   if(!IsInitialEntryAllowed())
      return false;
   double previous_high = 0.0;
   double previous_low = 0.0;
   int range_points = 0;
   long first_direction = ORDER_TYPE_BUY;
   if(!GetPreviousCandleRange(previous_high, previous_low, range_points)
      || !GetBreakoutDirection(previous_high, previous_low, first_direction))
      return false;
   const datetime current_bar = iTime(_Symbol, _Period, 0);
   if(Korder_type == KORDER_ONCE_PER_BAR && current_bar > 0
      && current_bar == g_multi_last_trigger_bar)
      return false;

   const int new_index = ArraySize(g_multi_groups);
   if(ArrayResize(g_multi_groups, new_index + 1) != new_index + 1)
     {
      Print("Unable to allocate another candle order group.");
      return false;
     }
   MultiGroupState state;
   const int new_group_id = g_multi_next_id++;
   MultiResetState(state, new_group_id);
   state.first_direction = first_direction == ORDER_TYPE_BUY ? FIRST_BUY : FIRST_SELL;
   state.cycle_mode = ordertype == ORDERTYPE_FORWARD ? CYCLE_MODE_1 : CYCLE_MODE_2;
   state.stop_points = range_points;
   state.take_profit_points = range_points;
   if(!MultiOpenMarket(state, first_direction, 首单手数))
     {
      MultiRemoveGroup(new_index);
      return false;
     }
   ulong ticket = 0;
   long type = POSITION_TYPE_BUY;
   double total = 0.0;
   double entry = 0.0;
   double stop_loss = 0.0;
   double take_profit = 0.0;
   if(!MultiFindPosition(state.id, ticket, type, total, entry, stop_loss, take_profit))
     {
      MultiRemoveGroup(new_index);
      return false;
     }
   state.anchor_price = entry;
   state.last_entry = entry;
   state.linear_extreme = entry;
   state.total_lots = total;
   state.grid_lots = total;
   MultiSetStops(state, type);
   MultiPlaceReversePending(state, type);
   MultiPlaceGridPending(state, type);
   g_multi_groups[new_index] = state;
   MultiSaveGroup(g_multi_groups[new_index]);
   if(Korder_type == KORDER_ONCE_PER_BAR && current_bar > 0)
      g_multi_last_trigger_bar = current_bar;
   return true;
  }

void ManageMultipleCandleGroups()
  {
   if(g_reset_pending)
     {
      ProcessReset();
      return;
     }
   bool closed_group = false;
   for(int index = ArraySize(g_multi_groups) - 1; index >= 0; index--)
     {
      const bool was_active = g_multi_groups[index].active;
      MultiManageGroup(g_multi_groups[index]);
      if(was_active && !g_multi_groups[index].active)
        {
         MultiRemoveGroup(index);
         closed_group = true;
        }
      else if(g_multi_groups[index].active)
         MultiSaveGroup(g_multi_groups[index]);
      if(g_reset_pending)
         return;
     }
   if(closed_group)
      return;
   MultiTryOpenCandleGroup();
  }

int OnInit()
  {
   g_start_operation_minutes = ParseTimeMinutes(开始时间);
   g_end_operation_minutes = ParseTimeMinutes(结束时间);
   if(InpInitialLots <= 0.0 || 首单手数倍数 <= 0.0
      || InpGridCount < 0 || InpGridLotMultiplier <= 0.0
      || InpStopLossDistancePoints <= 0 || InpTakeProfitDistancePoints <= 0
       || InpCandleMinRangePoints <= 0 || InpCandleMaxRangePoints < InpCandleMinRangePoints
       || 最大反手次数 < 0
       || (kline_enable_multiple != 0 && kline_enable_multiple != 1)
       || (Korder_type != KORDER_ONCE_PER_BAR && Korder_type != KORDER_REPEAT_PER_BAR)
      || g_start_operation_minutes < 0 || g_end_operation_minutes < 0)
      return INIT_PARAMETERS_INCORRECT;

   if(!AcquireExecutionOwnership())
      return INIT_FAILED;

   g_active_first_direction = InpFirstDirection;
   g_active_cycle_mode = InpCycleMode;
   LoadState();
   if(InpDistanceMode == DISTANCE_CANDLE_RANGE && kline_enable_multiple == 1)
      MultiLoadGroups();
   g_trade.SetExpertMagicNumber(InpMagicNumber);
   g_trade.SetTypeFillingBySymbol(_Symbol);
   return INIT_SUCCEEDED;
  }

void OnTick()
  {
   if(!AcquireExecutionOwnership())
      return;
   if(InpDistanceMode == DISTANCE_CANDLE_RANGE && kline_enable_multiple == 1)
      ManageMultipleCandleGroups();
   else
      Manage();
  }

void OnDeinit(const int reason)
  {
   ReleaseExecutionOwnership();
  }
