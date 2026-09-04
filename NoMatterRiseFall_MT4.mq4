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
   CYCLE_MODE_1 = 0,  // 模式一：首单多=多空空多空空；首单空=空多多空多多
   CYCLE_MODE_2 = 1,  // 模式二：首单多=多空多空多多；首单空=空多空多空空
   CYCLE_MODE_3 = 2   // 模式三：首单多=多空多多空多；首单空=空多空空多空
  };

enum DistanceMode
  {
   DISTANCE_FIXED = 0,         // 固定止盈止损距离
   DISTANCE_CANDLE_RANGE = 1,  // 上一根K线高度
   DISTANCE_AVERAGE_CANDLE_RANGE = 2 // 过去N根K线平均高度
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
// 固定距离和K线高度模式均使用用户选择的循环模式
input CycleMode      循环模式 = CYCLE_MODE_1;
// 止盈止损距离来源：固定距离、上一根K线高度或过去N根K线平均高度
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
// 平均K线模式使用的已完成K线根数
input int            平均K线根数 = 20;
// 平均K线高度计算的止损倍数
input double         平均止损倍数 = 2.0;
// 平均K线模式中止盈距离相对止损距离的倍数
input double         平均止盈倍数 = 2.0;
// 用于识别本EA订单的唯一编号
input int            订单识别编号 = 20260830;
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
#define InpAverageCandleCount 平均K线根数
#define InpAverageStopMultiplier 平均止损倍数
#define InpAverageTakeProfitMultiplier 平均止盈倍数
#define InpMagicNumber 订单识别编号
#define InpOrderComment 订单注释

bool   g_had_position = false;
int    g_last_position_type = OP_BUY;
double g_last_take_profit = 0.0;
int    g_cycle_index = 0;
int    g_pending_index = -1;
int    g_reversal_count = 0;
int    g_pending_ticket = -1;
int    g_initial_high_ticket = -1;
int    g_initial_low_ticket = -1;
double g_initial_high_price = 0.0;
double g_initial_low_price = 0.0;
int    g_initial_high_direction = OP_BUY;
int    g_initial_low_direction = OP_SELL;
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
long   g_grid_filled_mask = 0;
int    g_grid_pending_level = 0;
double g_grid_pending_price = 0.0;
bool   g_reset_pending = false;
int    g_start_operation_minutes = 0;
int    g_end_operation_minutes = 24 * 60;

void MultiClearAll();

string StatePrefix()
  {
   return "NMR." + IntegerToString(AccountNumber())
          + "." + Symbol() + "." + IntegerToString(InpMagicNumber);
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
   string name = "NMR_lock_" + SanitizeExecutionLockPart(AccountServer())
                 + "_" + IntegerToString(AccountNumber())
                 + "_" + SanitizeExecutionLockPart(Symbol())
                 + "_" + IntegerToString(InpMagicNumber);
   if(IsTesting())
      name += "_tester_" + IntegerToString((int)ChartID());
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
      Print("Execution ownership unavailable for account=", AccountNumber(),
            ", symbol=", Symbol(), ", magic=", InpMagicNumber,
            "; another EA instance is already managing this scope. error=", GetLastError());
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
   GlobalVariableSet(prefix + ".index", g_cycle_index);
   GlobalVariableSet(prefix + ".pending", g_pending_index);
   GlobalVariableSet(prefix + ".reversals", g_reversal_count);
   GlobalVariableSet(prefix + ".pendingticket", g_pending_ticket);
   GlobalVariableSet(prefix + ".initial_high_ticket", g_initial_high_ticket);
   GlobalVariableSet(prefix + ".initial_low_ticket", g_initial_low_ticket);
   GlobalVariableSet(prefix + ".initial_high_price", g_initial_high_price);
   GlobalVariableSet(prefix + ".initial_low_price", g_initial_low_price);
   GlobalVariableSet(prefix + ".initial_high_direction", g_initial_high_direction);
   GlobalVariableSet(prefix + ".initial_low_direction", g_initial_low_direction);
   GlobalVariableSet(prefix + ".candleentrybar", g_last_candle_entry_bar_time);
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
   GlobalVariableSet(prefix + ".gridmask", (double)g_grid_filled_mask);
   GlobalVariableSet(prefix + ".gridpendinglevel", g_grid_pending_level);
   GlobalVariableSet(prefix + ".gridpendingprice", g_grid_pending_price);
   GlobalVariableSet(prefix + ".reset", g_reset_pending ? 1.0 : 0.0);
   GlobalVariableSet(prefix + ".transitionphase", g_transition_phase);
   GlobalVariableSet(prefix + ".transitionid", (double)g_transition_id);
  }

void ClearState()
  {
   const string prefix = StatePrefix();
   GlobalVariableDel(prefix + ".index");
   GlobalVariableDel(prefix + ".pending");
   GlobalVariableDel(prefix + ".reversals");
   GlobalVariableDel(prefix + ".pendingticket");
   GlobalVariableDel(prefix + ".initial_high_ticket");
   GlobalVariableDel(prefix + ".initial_low_ticket");
   GlobalVariableDel(prefix + ".initial_high_price");
   GlobalVariableDel(prefix + ".initial_low_price");
   GlobalVariableDel(prefix + ".initial_high_direction");
   GlobalVariableDel(prefix + ".initial_low_direction");
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
   GlobalVariableDel(prefix + ".gridmask");
   GlobalVariableDel(prefix + ".gridpendinglevel");
   GlobalVariableDel(prefix + ".gridpendingprice");
   GlobalVariableDel(prefix + ".reset");
   GlobalVariableDel(prefix + ".transitionphase");
   GlobalVariableDel(prefix + ".transitionid");
   g_had_position = false;
   g_last_position_type = OP_BUY;
   g_last_take_profit = 0.0;
   g_cycle_index = 0;
   g_pending_index = -1;
   g_reversal_count = 0;
   g_pending_ticket = -1;
   g_initial_high_ticket = -1;
   g_initial_low_ticket = -1;
   g_initial_high_price = 0.0;
   g_initial_low_price = 0.0;
   g_initial_high_direction = OP_BUY;
   g_initial_low_direction = OP_SELL;
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
   g_grid_filled_mask = 0;
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
      g_pending_ticket = (int)MathRound(GlobalVariableGet(prefix + ".pendingticket"));
   if(GlobalVariableCheck(prefix + ".initial_high_ticket"))
      g_initial_high_ticket = (int)MathRound(GlobalVariableGet(prefix + ".initial_high_ticket"));
   if(GlobalVariableCheck(prefix + ".initial_low_ticket"))
      g_initial_low_ticket = (int)MathRound(GlobalVariableGet(prefix + ".initial_low_ticket"));
   if(GlobalVariableCheck(prefix + ".initial_high_price"))
      g_initial_high_price = GlobalVariableGet(prefix + ".initial_high_price");
   if(GlobalVariableCheck(prefix + ".initial_low_price"))
      g_initial_low_price = GlobalVariableGet(prefix + ".initial_low_price");
   if(GlobalVariableCheck(prefix + ".initial_high_direction"))
      g_initial_high_direction = (int)MathRound(GlobalVariableGet(prefix + ".initial_high_direction"));
   if(GlobalVariableCheck(prefix + ".initial_low_direction"))
      g_initial_low_direction = (int)MathRound(GlobalVariableGet(prefix + ".initial_low_direction"));
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
   if(GlobalVariableCheck(prefix + ".gridmask"))
      g_grid_filled_mask = (long)MathRound(GlobalVariableGet(prefix + ".gridmask"));
   else if(g_grid_filled_levels > 0)
      g_grid_filled_mask = ((long)1 << g_grid_filled_levels) - 1;
   if(GlobalVariableCheck(prefix + ".gridpendinglevel"))
      g_grid_pending_level = (int)MathRound(GlobalVariableGet(prefix + ".gridpendinglevel"));
   if(GlobalVariableCheck(prefix + ".gridpendingprice"))
      g_grid_pending_price = GlobalVariableGet(prefix + ".gridpendingprice");
  }

double PriceNormalize(const double price)
  {
   return NormalizeDouble(price, Digits);
  }

int ParseTimeMinutes(const string value)
  {
   const int separator = StringFind(value, ":", 0);
   if(separator <= 0 || separator >= StringLen(value) - 1)
      return -1;
   const int hour = (int)StrToInteger(StringSubstr(value, 0, separator));
   const int minute = (int)StrToInteger(StringSubstr(value, separator + 1));
   if(hour < 0 || hour > 23 || minute < 0 || minute > 59)
      return -1;
   return hour * 60 + minute;
  }

bool IsInitialEntryAllowed()
  {
   const datetime current_time = TimeCurrent();
   const int current_minutes = TimeHour(current_time) * 60 + TimeMinute(current_time);
   if(g_start_operation_minutes == g_end_operation_minutes)
      return true;
   if(g_start_operation_minutes < g_end_operation_minutes)
      return current_minutes >= g_start_operation_minutes
             && current_minutes < g_end_operation_minutes;
   return current_minutes >= g_start_operation_minutes
          || current_minutes < g_end_operation_minutes;
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

bool PreviousCandleDataReady()
  {
   if(iBars(Symbol(), Period()) < 2)
      return false;
   return iHigh(Symbol(), Period(), 1) > 0.0
          && iLow(Symbol(), Period(), 1) > 0.0;
  }

bool GetAverageCandleRangePoints(int &average_range_points)
  {
   if(InpAverageCandleCount <= 0
      || iBars(Symbol(), Period()) < InpAverageCandleCount + 1)
      return false;
   double total_range_points = 0.0;
   for(int shift = 1; shift <= InpAverageCandleCount; shift++)
     {
      const double high = iHigh(Symbol(), Period(), shift);
      const double low = iLow(Symbol(), Period(), shift);
      if(high <= 0.0 || low <= 0.0 || high <= low)
         return false;
      total_range_points += (high - low) / Point;
     }
   average_range_points = (int)MathRound(total_range_points / InpAverageCandleCount);
   return average_range_points > 0;
  }

bool GetDistancePoints(int &stop_loss_points, int &take_profit_points)
  {
   if(InpDistanceMode == DISTANCE_FIXED)
     {
      stop_loss_points = InpStopLossDistancePoints;
      take_profit_points = InpTakeProfitDistancePoints;
      return stop_loss_points > 0 && take_profit_points > 0;
     }

   if(InpDistanceMode == DISTANCE_AVERAGE_CANDLE_RANGE)
     {
      int average_range_points = 0;
      if(!GetAverageCandleRangePoints(average_range_points)
         || InpAverageStopMultiplier <= 0.0
         || InpAverageTakeProfitMultiplier <= 0.0)
         return false;
      stop_loss_points = (int)MathRound(average_range_points
                                        * InpAverageStopMultiplier);
      take_profit_points = (int)MathRound(stop_loss_points
                                          * InpAverageTakeProfitMultiplier);
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

bool FindPositionByTicket(const int wanted_ticket, int &ticket, int &type,
                          double &volume, double &open_price, double &stop_loss,
                          double &take_profit)
  {
   if(wanted_ticket <= 0 || !OrderSelect(wanted_ticket, SELECT_BY_TICKET, MODE_TRADES)
      || !IsOurMarketOrder())
      return false;
   ticket = wanted_ticket;
   type = OrderType();
   volume = OrderLots();
   open_price = OrderOpenPrice();
   stop_loss = OrderStopLoss();
   take_profit = OrderTakeProfit();
   return true;
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

bool HasOurPosition()
  {
   for(int index = OrdersTotal() - 1; index >= 0; index--)
      if(OrderSelect(index, SELECT_BY_POS, MODE_TRADES)
         && IsOurMarketOrder())
         return true;
   return false;
  }

bool CloseAllOurPositions()
  {
   bool closed = true;
   RefreshRates();
   for(int index = OrdersTotal() - 1; index >= 0; index--)
     {
      if(!OrderSelect(index, SELECT_BY_POS, MODE_TRADES) || !IsOurMarketOrder())
         continue;
      const int ticket = OrderTicket();
      const double close_price = OrderType() == OP_BUY ? Bid : Ask;
      if(!OrderClose(ticket, OrderLots(), close_price, 0, clrRed))
        {
         const int error = GetLastError();
         Print("Position close during reset failed, ticket=", ticket,
               ", error=", error);
         closed = false;
        }
     }
   return closed && !HasOurPosition();
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

bool IsInitialPendingComment()
  {
   return StringFind(OrderComment(), ".InitialHigh", 0) >= 0
          || StringFind(OrderComment(), ".InitialLow", 0) >= 0;
  }

bool FindPending(int &ticket, int &type, double &volume, double &price)
  {
   for(int index = OrdersTotal() - 1; index >= 0; index--)
     {
       if(!OrderSelect(index, SELECT_BY_POS, MODE_TRADES) || !IsOurPendingOrder()
          || IsGridPendingComment() || IsInitialPendingComment())
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
         || !IsGridPendingComment() || IsInitialPendingComment())
         continue;
      ticket = OrderTicket();
      type = OrderType();
      volume = OrderLots();
      price = OrderOpenPrice();
      return true;
     }
   return false;
  }

bool HasActiveInitialPending()
  {
   for(int index = OrdersTotal() - 1; index >= 0; index--)
      if(OrderSelect(index, SELECT_BY_POS, MODE_TRADES)
         && IsOurPendingOrder() && IsInitialPendingComment())
         return true;
   return false;
  }

void ResetInitialPendingTracking()
  {
   g_initial_high_ticket = -1;
   g_initial_low_ticket = -1;
   g_initial_high_price = 0.0;
   g_initial_low_price = 0.0;
   g_initial_high_direction = OP_BUY;
   g_initial_low_direction = OP_SELL;
  }

bool NormalizeSingleGroupPending(const bool grid, const int expected_direction,
                                 const double expected_price,
                                 const double expected_volume, int &keep_ticket)
  {
   keep_ticket = -1;
   bool tracked_ticket_filled = false;
   if(!grid && g_pending_ticket > 0)
     {
      if(OrderSelect(g_pending_ticket, SELECT_BY_TICKET, MODE_TRADES)
         && IsOurMarketOrder())
         tracked_ticket_filled = true;
      else if(OrderSelect(g_pending_ticket, SELECT_BY_TICKET, MODE_HISTORY)
              && IsOurMarketOrder())
         tracked_ticket_filled = true;
     }
   const double price_tolerance = Point * 0.5;
   const double volume_tolerance = MarketInfo(Symbol(), MODE_LOTSTEP) * 0.5;
   for(int index = OrdersTotal() - 1; index >= 0; index--)
     {
      if(!OrderSelect(index, SELECT_BY_POS, MODE_TRADES) || !IsOurPendingOrder()
         || IsGridPendingComment() != grid || IsInitialPendingComment())
         continue;
      const int candidate = OrderTicket();
      if(!tracked_ticket_filled
         && PendingDirection(OrderType()) == expected_direction
         && MathAbs(OrderOpenPrice() - expected_price) <= price_tolerance
         && MathAbs(OrderLots() - expected_volume) <= volume_tolerance
         && (keep_ticket <= 0 || candidate < keep_ticket))
         keep_ticket = candidate;
     }

   bool normalized = true;
   for(int index = OrdersTotal() - 1; index >= 0; index--)
     {
      if(!OrderSelect(index, SELECT_BY_POS, MODE_TRADES) || !IsOurPendingOrder()
         || IsGridPendingComment() != grid || IsInitialPendingComment()
         || OrderTicket() == keep_ticket)
         continue;
      const int candidate = OrderTicket();
      if(!OrderDelete(candidate, clrRed))
        {
         Print("Duplicate pending delete failed, ticket=", candidate,
               ", error=", GetLastError());
         normalized = false;
        }
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
   for(int index = OrdersTotal() - 1; index >= 0; index--)
     {
      if(!OrderSelect(index, SELECT_BY_POS, MODE_TRADES) || !IsOurMarketOrder())
         continue;
      if(StringFind(OrderComment(), ".Grid", 0) < 0)
        {
         base_positions++;
         if(base_positions > 1)
            return true;
        }
     }

   const double price_tolerance = Point * 0.5;
   const double volume_tolerance = MarketInfo(Symbol(), MODE_LOTSTEP) * 0.5;
   for(int left = OrdersTotal() - 1; left >= 0; left--)
     {
      if(!OrderSelect(left, SELECT_BY_POS, MODE_TRADES) || !IsOurMarketOrder()
         || StringFind(OrderComment(), ".Grid", 0) < 0)
         continue;
      const int left_ticket = OrderTicket();
      const int left_type = OrderType();
      const double left_price = OrderOpenPrice();
      const double left_volume = OrderLots();
      for(int right = left - 1; right >= 0; right--)
        {
         if(!OrderSelect(right, SELECT_BY_POS, MODE_TRADES) || !IsOurMarketOrder()
            || StringFind(OrderComment(), ".Grid", 0) < 0
            || OrderTicket() == left_ticket)
            continue;
         if(OrderType() == left_type
            && MathAbs(OrderOpenPrice() - left_price) <= price_tolerance
            && MathAbs(OrderLots() - left_volume) <= volume_tolerance)
            return true;
        }
     }
   return false;
  }

bool DeleteAllPending()
  {
   const int tracked_ticket = g_pending_ticket;
   bool deleted = true;
   for(int index = OrdersTotal() - 1; index >= 0; index--)
     {
      if(!OrderSelect(index, SELECT_BY_POS, MODE_TRADES) || !IsOurPendingOrder())
         continue;
      const int ticket = OrderTicket();
      if(!OrderDelete(ticket, clrRed))
        {
         Print("OrderDelete failed, ticket=", ticket, ", error=", GetLastError());
         deleted = false;
        }
     }
   int active_ticket = -1;
   int active_type = OP_BUY;
   double active_volume = 0.0;
   double active_price = 0.0;
   if(FindPending(active_ticket, active_type, active_volume, active_price))
      g_pending_ticket = active_ticket;
   else if(tracked_ticket > 0
           && OrderSelect(tracked_ticket, SELECT_BY_TICKET, MODE_HISTORY)
           && IsOurPendingOrder())
      g_pending_ticket = -1;
   if(!HasActiveInitialPending())
      ResetInitialPendingTracking();
   return deleted && !HasOurPending();
  }

int GetReversePendingStatus()
  {
   if(g_pending_ticket <= 0)
      return REVERSE_PENDING_UNKNOWN;

   if(OrderSelect(g_pending_ticket, SELECT_BY_TICKET, MODE_TRADES))
     {
      if(IsOurPendingOrder() && !IsGridPendingComment())
         return REVERSE_PENDING_ACTIVE;
      if(IsOurMarketOrder())
         return REVERSE_PENDING_FILLED;
     }

   if(OrderSelect(g_pending_ticket, SELECT_BY_TICKET, MODE_HISTORY))
     {
      if(IsOurMarketOrder())
         return REVERSE_PENDING_FILLED;
      if(IsOurPendingOrder())
         return REVERSE_PENDING_CANCELED;
     }
   return REVERSE_PENDING_UNKNOWN;
  }

bool HasOurPending()
  {
   for(int index = OrdersTotal() - 1; index >= 0; index--)
      if(OrderSelect(index, SELECT_BY_POS, MODE_TRADES)
         && IsOurPendingOrder())
         return true;
   if(HasActiveInitialPending())
      return true;
   return false;
  }

void BeginFullReset(const string reason)
  {
   Print(reason);
   MultiClearAll();
   g_reset_pending = true;
   g_had_position = false;
   g_last_position_type = OP_BUY;
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
   g_grid_filled_mask = 0;
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
      const int error = GetLastError();
      Print("Market order failed, error=", error);
      if(error == ERR_NOT_ENOUGH_MONEY)
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

bool PlaceInitialPendingOrder(const int direction, const double entry,
                              const int distance_points, const double volume,
                              const string comment, int &ticket)
  {
   ticket = -1;
   const int pending_type = PendingTypeForDirection(direction, entry);
   const double normalized_entry = PriceNormalize(entry);
   const double distance = distance_points * Point;
   double stop_loss = 0.0;
   double take_profit = 0.0;
   if(direction == OP_BUY)
     {
      stop_loss = PriceNormalize(normalized_entry - distance);
      take_profit = PriceNormalize(normalized_entry + distance);
     }
   else
     {
      stop_loss = PriceNormalize(normalized_entry + distance);
      take_profit = PriceNormalize(normalized_entry - distance);
     }
   RefreshRates();
   ticket = OrderSend(Symbol(), pending_type, VolumeNormalize(volume), normalized_entry, 0,
                      stop_loss, take_profit, comment, InpMagicNumber, 0, clrOrange);
   if(ticket < 0)
     {
      Print("Initial pending failed, error=", GetLastError());
      return false;
     }
   return true;
  }

bool PlaceInitialPendingPair(const double previous_high, const double previous_low,
                             const int range_points, const double volume)
  {
   if(g_initial_high_ticket >= 0 || g_initial_low_ticket >= 0
      || range_points <= 0 || volume <= 0.0)
      return false;
   const int high_direction = ordertype == ORDERTYPE_FORWARD ? OP_BUY : OP_SELL;
   const int low_direction = ordertype == ORDERTYPE_FORWARD ? OP_SELL : OP_BUY;
   int high_ticket = -1;
   int low_ticket = -1;
   if(!PlaceInitialPendingOrder(high_direction, previous_high, range_points, volume,
                                InpOrderComment + ".InitialHigh", high_ticket))
      return false;
   if(!PlaceInitialPendingOrder(low_direction, previous_low, range_points, volume,
                                InpOrderComment + ".InitialLow", low_ticket))
     {
      if(high_ticket > 0)
         OrderDelete(high_ticket, clrRed);
      return false;
     }
   g_initial_high_ticket = high_ticket;
   g_initial_low_ticket = low_ticket;
   g_initial_high_price = PriceNormalize(previous_high);
   g_initial_low_price = PriceNormalize(previous_low);
   g_initial_high_direction = high_direction;
   g_initial_low_direction = low_direction;
   g_group_stop_points = range_points;
   g_group_take_profit_points = range_points;
   SaveState();
   return true;
  }

int InitialPendingStatus(const int ticket)
  {
   if(ticket < 0)
      return REVERSE_PENDING_UNKNOWN;
   if(OrderSelect(ticket, SELECT_BY_TICKET, MODE_TRADES))
     {
      if(IsOurPendingOrder() && IsInitialPendingComment())
         return REVERSE_PENDING_ACTIVE;
      if(IsOurMarketOrder())
         return REVERSE_PENDING_FILLED;
     }
   if(OrderSelect(ticket, SELECT_BY_TICKET, MODE_HISTORY))
     {
      if(IsOurMarketOrder())
         return REVERSE_PENDING_FILLED;
      if(IsOurPendingOrder())
         return REVERSE_PENDING_CANCELED;
     }
   return REVERSE_PENDING_UNKNOWN;
  }

bool HandleInitialPendingFill()
  {
   // The two initial orders form one OCO pair: once either side fills,
   // cancel the still-active opposite order before managing the position.
   if(g_initial_high_ticket < 0 && g_initial_low_ticket < 0)
      return false;
   const int high_status = InitialPendingStatus(g_initial_high_ticket);
   const int low_status = InitialPendingStatus(g_initial_low_ticket);
   const bool high_filled = high_status == REVERSE_PENDING_FILLED;
   const bool low_filled = low_status == REVERSE_PENDING_FILLED;
   if(high_status == REVERSE_PENDING_ACTIVE && low_status == REVERSE_PENDING_ACTIVE)
      return true;
   if(high_filled || low_filled)
     {
      const int filled_ticket = high_filled ? g_initial_high_ticket : g_initial_low_ticket;
      const int other_ticket = filled_ticket == g_initial_high_ticket
                               ? g_initial_low_ticket : g_initial_high_ticket;
      const int other_status = high_filled ? low_status : high_status;
      if(other_status == REVERSE_PENDING_UNKNOWN)
         return true;
      if(other_ticket > 0 && other_status == REVERSE_PENDING_ACTIVE)
        {
         if(!OrderDelete(other_ticket, clrRed))
            return true;
        }
      int position_ticket = -1;
      int position_type = OP_BUY;
      double volume = 0.0;
      double entry = 0.0;
      double stop_loss = 0.0;
      double take_profit = 0.0;
      if(!FindPositionByTicket(filled_ticket, position_ticket, position_type, volume,
                               entry, stop_loss, take_profit))
         return true;
      g_active_first_direction = position_type == OP_BUY ? FIRST_BUY : FIRST_SELL;
      g_active_cycle_mode = InpCycleMode;
      g_cycle_index = 0;
      g_pending_index = -1;
      g_pending_ticket = -1;
      g_group_anchor_price = entry;
      g_group_last_entry = entry;
      g_group_linear_extreme = entry;
      g_group_total_lots = volume;
      g_grid_filled_levels = 0;
      g_grid_filled_mask = 0;
      g_grid_pending_level = 0;
      g_grid_pending_price = 0.0;
      g_grid_lots = g_previous_grid_lots > 0.0
                    ? VolumeNormalize(g_previous_grid_lots * InpGridLotMultiplier)
                    : volume;
      g_had_position = true;
      g_last_position_type = position_type;
      g_initial_high_ticket = -1;
      g_initial_low_ticket = -1;
      g_initial_high_price = 0.0;
      g_initial_low_price = 0.0;
      SetGroupStops(position_type);
      EnsureNextPending(GroupStopPrice(position_type), GroupTakeProfitPrice(position_type),
                        g_group_total_lots);
      EnsureGridPending(position_type);
      SaveState();
      return true;
     }
   if(high_status == REVERSE_PENDING_UNKNOWN || low_status == REVERSE_PENDING_UNKNOWN)
      return true;
   if(high_status == REVERSE_PENDING_ACTIVE || low_status == REVERSE_PENDING_ACTIVE)
     {
      const int active_ticket = high_status == REVERSE_PENDING_ACTIVE
                                ? g_initial_high_ticket : g_initial_low_ticket;
      if(active_ticket > 0 && !OrderDelete(active_ticket, clrRed))
         return true;
     }
   if(!HasActiveInitialPending())
     {
      ResetInitialPendingTracking();
      SaveState();
      return false;
     }
   return true;
  }

bool PlaceNextPending(const int next_direction, const double stop_loss,
                      const double take_profit, const double current_volume)
  {
   if(g_reversal_count >= 最大反手次数 || stop_loss <= 0.0 || current_volume <= 0.0)
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
   g_pending_ticket = ticket;
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

long GridLevelBit(const int level)
  {
   if(level <= 0 || level > 62)
      return 0;
   return ((long)1 << (level - 1));
  }

int GridFilledLevelCount()
  {
   int count = 0;
   for(int level = 1; level < InpGridCount; level++)
      if((g_grid_filled_mask & GridLevelBit(level)) != 0)
         count++;
   return count;
  }

int GridPendingLevelFromComment(const string comment)
  {
   const int marker = StringFind(comment, ".Grid.", 0);
   if(marker < 0)
      return 0;
   return (int)StrToInteger(StringSubstr(comment, marker + 6));
  }

bool IsGridPendingAtLevel(const int expected_direction, const int expected_level,
                          const double expected_price, const double expected_volume)
  {
   if(!IsOurPendingOrder() || !IsGridPendingComment() || IsInitialPendingComment())
      return false;
   const int comment_level = GridPendingLevelFromComment(OrderComment());
   if(comment_level > 0 && comment_level != expected_level)
      return false;
   return PendingDirection(OrderType()) == expected_direction
          && MathAbs(OrderOpenPrice() - expected_price) <= Point * 0.5
          && MathAbs(OrderLots() - expected_volume)
             <= MarketInfo(Symbol(), MODE_LOTSTEP) * 0.5;
  }

bool NormalizeGridPendingLevel(const int expected_direction, const int expected_level,
                               const double expected_price, const double expected_volume,
                               int &keep_ticket)
  {
   keep_ticket = -1;
   for(int index = OrdersTotal() - 1; index >= 0; index--)
     {
      if(!OrderSelect(index, SELECT_BY_POS, MODE_TRADES)
         || !IsGridPendingAtLevel(expected_direction, expected_level,
                                  expected_price, expected_volume))
         continue;
      const int candidate = OrderTicket();
      if(keep_ticket <= 0 || candidate < keep_ticket)
         keep_ticket = candidate;
     }

   bool normalized = true;
   for(int index = OrdersTotal() - 1; index >= 0; index--)
     {
      if(!OrderSelect(index, SELECT_BY_POS, MODE_TRADES)
         || !IsGridPendingAtLevel(expected_direction, expected_level,
                                  expected_price, expected_volume)
         || OrderTicket() == keep_ticket)
         continue;
      const int candidate = OrderTicket();
      if(!OrderDelete(candidate, clrRed))
        {
         Print("Grid level duplicate delete failed, level=", expected_level,
               ", ticket=", candidate, ", error=", GetLastError());
         normalized = false;
        }
     }
   return normalized;
  }

bool FindFilledGridOrder(const int position_type, const int level,
                         const double expected_price, double &fill_price)
  {
   for(int index = OrdersHistoryTotal() - 1; index >= 0; index--)
     {
      if(!OrderSelect(index, SELECT_BY_POS, MODE_HISTORY)
         || OrderSymbol() != Symbol() || OrderMagicNumber() != InpMagicNumber
         || (OrderType() != OP_BUY && OrderType() != OP_SELL)
         || !IsGridPendingComment())
         continue;
      const int comment_level = GridPendingLevelFromComment(OrderComment());
      if((comment_level > 0 && comment_level != level)
         || PendingDirection(OrderType()) != position_type
         || MathAbs(OrderOpenPrice() - expected_price) > Point * 10.0)
         continue;
      fill_price = OrderOpenPrice();
      return true;
     }
   return false;
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
   const string grid_comment = InpOrderComment + ".Grid."
                               + IntegerToString(level);
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
   if(InpGridCount < 2 || g_group_anchor_price <= 0.0)
      return false;
   const double current_total_lots = TotalPositionLots(position_type);
   const double volume_tolerance = MarketInfo(Symbol(), MODE_LOTSTEP) * 0.5;
   if(current_total_lots <= previous_total_lots + volume_tolerance)
      return false;

   bool changed = false;
   double latest_entry = 0.0;
   for(int level = 1; level < InpGridCount; level++)
     {
      const long level_bit = GridLevelBit(level);
      if(level_bit == 0 || (g_grid_filled_mask & level_bit) != 0)
         continue;
      double fill_price = 0.0;
      if(FindFilledGridOrder(position_type, level, GridLevelPrice(position_type, level),
                             fill_price))
        {
         g_grid_filled_mask |= level_bit;
         latest_entry = fill_price;
         changed = true;
        }
     }
   if(!changed)
      return false;

   g_grid_filled_levels = GridFilledLevelCount();
   g_grid_pending_level = 0;
   g_grid_pending_price = 0.0;
   g_group_total_lots = current_total_lots;
   if(latest_entry > 0.0)
      g_group_last_entry = latest_entry;
   SetGroupStops(position_type);
   SaveState();
   return true;
  }

void EnsureGridPending(const int position_type)
  {
   if(InpGridCount < 2)
     {
      g_grid_pending_level = 0;
      g_grid_pending_price = 0.0;
      return;
     }
   g_grid_pending_level = 0;
   g_grid_pending_price = 0.0;
   const double expected_volume = VolumeNormalize(g_grid_lots);
   for(int level = 1; level < InpGridCount; level++)
     {
      if((g_grid_filled_mask & GridLevelBit(level)) != 0)
         continue;
      const double expected_price = GridLevelPrice(position_type, level);
      int grid_ticket = -1;
      if(!NormalizeGridPendingLevel(position_type, level, expected_price,
                                    expected_volume, grid_ticket))
         continue;
      if(grid_ticket <= 0)
         PlaceGridPending(position_type, level);
      if(grid_ticket > 0 || g_grid_pending_level == level)
        {
         g_grid_pending_level = level;
         g_grid_pending_price = expected_price;
        }
     }
   g_grid_filled_levels = GridFilledLevelCount();
   SaveState();
  }

void EnsureNextPending(const double stop_loss, const double take_profit,
                       const double fallback_volume)
  {
   if(g_reversal_count >= 最大反手次数)
      return;

   const int expected_direction = SequenceDirection(NextCycleIndex());
   const double expected_volume = NextGroupLots(fallback_volume);
   const double expected_price = PriceNormalize(stop_loss);
   int active_pending = -1;
   if(!NormalizeSingleGroupPending(false, expected_direction, expected_price,
                                   expected_volume, active_pending))
      return;
   if(active_pending <= 0)
      PlaceNextPending(expected_direction, stop_loss, take_profit, fallback_volume);
  }

bool ReconcileOrphanSingleGroupPending()
  {
   if(g_group_stop_points <= 0 || g_group_take_profit_points <= 0
      || g_group_anchor_price <= 0.0)
     {
      Print("Orphan pending orders detected without recoverable group state; deleting them and restarting next tick.");
      if(!DeleteAllPending())
         return false;
      ClearState();
      return true;
     }

   const int current_direction = SequenceDirection(g_cycle_index);
   const int reverse_direction = g_pending_index >= 0
                                 ? SequenceDirection(g_pending_index)
                                 : SequenceDirection(NextCycleIndex());
   const double reverse_price = GroupStopPrice(current_direction);
   const double reverse_volume = NextGroupLots(g_group_total_lots > 0.0
                                                ? g_group_total_lots : InpInitialLots);
   int reverse_ticket = -1;
   if(!NormalizeSingleGroupPending(false, reverse_direction, reverse_price,
                                   reverse_volume, reverse_ticket))
      return false;

   EnsureGridPending(current_direction);
   return true;
  }

bool Transition(const int position_type, const double volume,
                const double stop_loss, const double take_profit)
  {
   if(g_reversal_count >= 最大反手次数)
     {
      BeginResetAfterMaxReversals();
      return false;
     }

   RefreshRates();
   const int next_index = NextCycleIndex();
   const int next_type = SequenceDirection(next_index);
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
   if(!can_open_next)
     {
      g_transition_phase = TRANSITION_NONE;
      SaveState();
      return true;
     }
   g_transition_phase = TRANSITION_PREPARED;
   g_transition_id = (long)TimeCurrent() * 1000 + g_reversal_count;
   SaveState();
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
   g_grid_filled_mask = 0;
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

   const int expected_direction = SequenceDirection(g_cycle_index);
   const double expected_volume = VolumeNormalize(g_cumulative_loss_lots * 首单手数倍数);
   int ticket = -1;
   int position_type = OP_BUY;
   double volume = 0.0;
   double entry = 0.0;
   double stop_loss = 0.0;
   double take_profit = 0.0;
   bool found = FindPosition(ticket, position_type, volume, entry, stop_loss, take_profit);
   if(found)
     {
      const double total = TotalPositionLots(position_type);
      const double tolerance = MarketInfo(Symbol(), MODE_LOTSTEP) * 0.5;
      if(position_type != expected_direction || MathAbs(total - expected_volume) > tolerance)
        {
         Print("Transition recovery conflict, id=", g_transition_id,
               ", expected_type=", expected_direction,
               ", expected_volume=", expected_volume,
               ", actual_type=", position_type, ", actual_volume=", total);
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
   g_group_total_lots = TotalPositionLots(position_type);
   g_grid_filled_levels = 0;
   g_grid_filled_mask = 0;
   g_grid_pending_level = 0;
   g_grid_pending_price = 0.0;
   g_grid_lots = VolumeNormalize(g_previous_grid_lots * InpGridLotMultiplier);
   SetGroupStops(position_type);
   g_transition_phase = TRANSITION_COMPLETE;
   SaveState();
   return true;
  }

bool PrepareCandleOnceEntry(const datetime current_bar_time)
  {
   if(current_bar_time <= 0 || current_bar_time == g_last_candle_entry_bar_time)
      return true;
   if(HasOurPosition())
      return true;
   if(!HasOurPending())
      return true;
   if(!DeleteAllPending())
      return false;
   ClearState();
   return true;
  }

void MarkCandleEntryBarProcessed(const datetime current_bar_time)
  {
   if(current_bar_time <= 0)
      return;
   g_last_candle_entry_bar_time = current_bar_time;
   GlobalVariableSet(StatePrefix() + ".candleentrybar", (double)g_last_candle_entry_bar_time);
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

   const bool candle_once_mode = InpDistanceMode == DISTANCE_CANDLE_RANGE
                                 && Korder_type == KORDER_ONCE_PER_BAR;
   const datetime current_bar_time = candle_once_mode ? iTime(Symbol(), Period(), 0) : 0;
   if(candle_once_mode && current_bar_time > 0
      && current_bar_time != g_last_candle_entry_bar_time
      && !PrepareCandleOnceEntry(current_bar_time))
      return;

   if(HandleInitialPendingFill())
      return;

   int position_ticket = -1;
   int position_type = OP_BUY;
   double volume = 0.0;
   double entry = 0.0;
   double stop_loss = 0.0;
   double take_profit = 0.0;

   const int reverse_pending_status = GetReversePendingStatus();
   bool pending_position_found = false;
   if(reverse_pending_status == REVERSE_PENDING_FILLED && g_pending_ticket > 0)
      pending_position_found = FindPositionByTicket(g_pending_ticket, position_ticket,
                                                     position_type, volume, entry,
                                                     stop_loss, take_profit);
   const bool has_position = pending_position_found
                             || FindPosition(position_ticket, position_type, volume,
                                             entry, stop_loss, take_profit);
   if(has_position)
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
                                  && g_pending_index != g_cycle_index
                                  && (g_pending_ticket <= 0
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
         g_pending_ticket = -1;
         g_group_anchor_price = entry;
         g_group_last_entry = entry;
          g_group_linear_extreme = entry;
         g_grid_filled_levels = 0;
         g_grid_filled_mask = 0;
         g_grid_pending_level = 0;
         g_grid_pending_price = 0.0;
         g_grid_lots = VolumeNormalize(g_previous_grid_lots * InpGridLotMultiplier);
         g_transition_phase = TRANSITION_COMPLETE;
         g_transition_id = (long)TimeCurrent() * 1000 + g_reversal_count;
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

      if(pending_filled)
        {
         EnsureNextPending(GroupStopPrice(position_type), GroupTakeProfitPrice(position_type),
                           volume);
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
         if(!DeleteAllPending())
            return;
         if(CloseAllPositions(position_type))
           {
            const datetime completed_bar_time = iTime(Symbol(), Period(), 0);
            g_pending_index = -1;
            ClearState();
            MarkCandleEntryBarProcessed(completed_bar_time);
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

      EnsureNextPending(GroupStopPrice(position_type), GroupTakeProfitPrice(position_type),
                        volume);
      EnsureGridPending(position_type);
      return;
     }

   if(PastLastTakeProfit())
     {
      if(!DeleteAllPending())
         return;
      const datetime completed_bar_time = iTime(Symbol(), Period(), 0);
      g_had_position = false;
      g_last_take_profit = 0.0;
      g_pending_index = -1;
      ClearState();
      MarkCandleEntryBarProcessed(completed_bar_time);
      return;
     }

   const bool has_pending = HasOurPending();
   if(has_pending)
     {
      ReconcileOrphanSingleGroupPending();
      return;
     }
   if(!IsInitialEntryAllowed())
      return;
   if(candle_once_mode)
     {
      if(current_bar_time > 0 && current_bar_time == g_last_candle_entry_bar_time)
         return;
      double previous_high = 0.0;
      double previous_low = 0.0;
      int range_points = 0;
      if(!GetPreviousCandleRange(previous_high, previous_low, range_points))
        {
         if(PreviousCandleDataReady())
            MarkCandleEntryBarProcessed(current_bar_time);
         return;
        }
      const double initial_lots = g_cumulative_loss_lots > 0.0
                                  ? VolumeNormalize(g_cumulative_loss_lots)
                                  : VolumeNormalize(InpInitialLots);
      if(PlaceInitialPendingPair(previous_high, previous_low, range_points, initial_lots))
         MarkCandleEntryBarProcessed(current_bar_time);
      return;
     }

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
      g_active_cycle_mode = InpCycleMode;
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
      if(InpDistanceMode == DISTANCE_CANDLE_RANGE && Korder_type == KORDER_ONCE_PER_BAR)
        {
         const datetime market_entry_bar_time = iTime(Symbol(), Period(), 0);
         if(market_entry_bar_time > 0)
            g_last_candle_entry_bar_time = market_entry_bar_time;
        }
      if(FindPosition(position_ticket, position_type, volume, entry,
                      stop_loss, take_profit))
        {
         g_group_anchor_price = entry;
         g_group_last_entry = entry;
          g_group_linear_extreme = entry;
         g_group_total_lots = TotalPositionLots(position_type);
         g_grid_filled_levels = 0;
         g_grid_filled_mask = 0;
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
   int      pending_ticket;
   int      initial_high_ticket;
   int      initial_low_ticket;
   double   initial_high_price;
   double   initial_low_price;
   int      initial_high_direction;
   int      initial_low_direction;
   int      grid_pending_ticket;
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
   long     grid_filled_mask;
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

string MultiInitialPendingComment(const int group_id, const bool high)
  {
   return InpOrderComment + MultiGroupTag(group_id)
          + (high ? ".InitialHigh" : ".InitialLow");
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
   GlobalVariableDel(prefix + ".initial_high_ticket");
   GlobalVariableDel(prefix + ".initial_low_ticket");
   GlobalVariableDel(prefix + ".initial_high_price");
   GlobalVariableDel(prefix + ".initial_low_price");
   GlobalVariableDel(prefix + ".initial_high_direction");
   GlobalVariableDel(prefix + ".initial_low_direction");
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
   GlobalVariableDel(prefix + ".gridmask");
   GlobalVariableDel(prefix + ".gridpendinglevel");
   GlobalVariableDel(prefix + ".gridpendingprice");
  }

bool MultiCommentMatches(const string comment, const int group_id)
  {
   return StringFind(comment, MultiGroupTag(group_id)) >= 0;
  }

bool MultiIsInitialPendingComment()
  {
   return StringFind(OrderComment(), ".InitialHigh", 0) >= 0
          || StringFind(OrderComment(), ".InitialLow", 0) >= 0;
  }

bool MultiIsGridSelectedOrder()
  {
   return StringFind(OrderComment(), ".Grid", 0) >= 0;
  }

void MultiClearAll()
  {
   for(int id = 1; id < g_multi_next_id; id++)
      MultiDeleteState(id);
   ArrayResize(g_multi_groups, 0);
   g_multi_last_trigger_bar = 0;
   g_multi_next_id = 1;
   GlobalVariableDel(StatePrefix() + ".multi.nextid");
   GlobalVariableDel(StatePrefix() + ".multi.lasttriggerbar");
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

void MultiResetState(MultiGroupState &group, const int group_id)
  {
   group.id = group_id;
   group.active = true;
   group.first_direction = FIRST_BUY;
   group.cycle_mode = CYCLE_MODE_1;
   group.cycle_index = 0;
   group.pending_index = -1;
   group.reversal_count = 0;
   group.pending_ticket = -1;
   group.initial_high_ticket = -1;
   group.initial_low_ticket = -1;
   group.initial_high_price = 0.0;
   group.initial_low_price = 0.0;
   group.initial_high_direction = OP_BUY;
   group.initial_low_direction = OP_SELL;
   group.grid_pending_ticket = -1;
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
   group.grid_filled_mask = 0;
   group.grid_pending_level = 0;
   group.grid_pending_price = 0.0;
  }

bool MultiFindPosition(const int group_id, int &ticket, int &type, double &volume,
                       double &entry, double &stop_loss, double &take_profit)
  {
   volume = 0.0;
   bool found = false;
   for(int index = OrdersTotal() - 1; index >= 0; index--)
     {
      if(!OrderSelect(index, SELECT_BY_POS, MODE_TRADES)
         || OrderSymbol() != Symbol() || OrderMagicNumber() != InpMagicNumber
         || (OrderType() != OP_BUY && OrderType() != OP_SELL)
         || !MultiCommentMatches(OrderComment(), group_id))
         continue;
      if(!found)
        {
         ticket = OrderTicket();
         type = OrderType();
         entry = OrderOpenPrice();
         stop_loss = OrderStopLoss();
         take_profit = OrderTakeProfit();
         found = true;
        }
      volume += OrderLots();
     }
   return found;
  }

bool MultiFindPending(const int group_id, const bool grid, int &ticket, int &type,
                      double &volume, double &price)
  {
   for(int index = OrdersTotal() - 1; index >= 0; index--)
     {
       if(!OrderSelect(index, SELECT_BY_POS, MODE_TRADES)
          || OrderSymbol() != Symbol() || OrderMagicNumber() != InpMagicNumber
          || !IsOurPendingOrder() || !MultiCommentMatches(OrderComment(), group_id)
          || MultiIsGridSelectedOrder() != grid || MultiIsInitialPendingComment())
         continue;
      ticket = OrderTicket();
      type = OrderType();
      volume = OrderLots();
      price = OrderOpenPrice();
      return true;
     }
   return false;
  }

bool MultiIsGridPendingAtLevel(const MultiGroupState &group, const int expected_direction,
                               const int expected_level, const double expected_price,
                               const double expected_volume)
  {
   if(!IsOurPendingOrder() || !MultiCommentMatches(OrderComment(), group.id)
      || !MultiIsGridSelectedOrder() || MultiIsInitialPendingComment())
      return false;
   const int comment_level = GridPendingLevelFromComment(OrderComment());
   if(comment_level > 0 && comment_level != expected_level)
      return false;
   return PendingDirection(OrderType()) == expected_direction
          && MathAbs(OrderOpenPrice() - expected_price) <= Point * 0.5
          && MathAbs(OrderLots() - expected_volume)
             <= MarketInfo(Symbol(), MODE_LOTSTEP) * 0.5;
  }

bool MultiNormalizeGridPendingLevel(const MultiGroupState &group,
                                    const int expected_direction, const int expected_level,
                                    const double expected_price, const double expected_volume,
                                    int &keep_ticket)
  {
   keep_ticket = -1;
   for(int index = OrdersTotal() - 1; index >= 0; index--)
     {
      if(!OrderSelect(index, SELECT_BY_POS, MODE_TRADES)
         || !MultiIsGridPendingAtLevel(group, expected_direction, expected_level,
                                       expected_price, expected_volume))
         continue;
      const int candidate = OrderTicket();
      if(keep_ticket <= 0 || candidate < keep_ticket)
         keep_ticket = candidate;
     }
   bool normalized = true;
   for(int index = OrdersTotal() - 1; index >= 0; index--)
     {
      if(!OrderSelect(index, SELECT_BY_POS, MODE_TRADES)
         || !MultiIsGridPendingAtLevel(group, expected_direction, expected_level,
                                       expected_price, expected_volume)
         || OrderTicket() == keep_ticket)
         continue;
      const int candidate = OrderTicket();
      if(!OrderDelete(candidate, clrRed))
        {
         Print("Multi grid level duplicate delete failed, group=", group.id,
               ", level=", expected_level, ", ticket=", candidate,
               ", error=", GetLastError());
         normalized = false;
        }
     }
   return normalized;
  }

bool MultiFindFilledGridOrder(const MultiGroupState &group, const int position_type,
                              const int level, const double expected_price,
                              double &fill_price)
  {
   for(int index = OrdersHistoryTotal() - 1; index >= 0; index--)
     {
      if(!OrderSelect(index, SELECT_BY_POS, MODE_HISTORY)
         || OrderSymbol() != Symbol() || OrderMagicNumber() != InpMagicNumber
         || (OrderType() != OP_BUY && OrderType() != OP_SELL)
         || !MultiCommentMatches(OrderComment(), group.id)
         || !MultiIsGridSelectedOrder())
         continue;
      const int comment_level = GridPendingLevelFromComment(OrderComment());
      if((comment_level > 0 && comment_level != level)
         || PendingDirection(OrderType()) != position_type
         || MathAbs(OrderOpenPrice() - expected_price) > Point * 10.0)
         continue;
      fill_price = OrderOpenPrice();
      return true;
     }
   return false;
  }

int MultiGridFilledLevelCount(const MultiGroupState &group)
  {
   int count = 0;
   for(int level = 1; level < 网格数量; level++)
      if((group.grid_filled_mask & GridLevelBit(level)) != 0)
         count++;
   return count;
  }

void MultiSaveGroup(const MultiGroupState &group)
  {
   const string prefix = MultiStatePrefix(group.id);
   GlobalVariableSet(prefix + ".active", group.active ? 1.0 : 0.0);
   GlobalVariableSet(prefix + ".first", group.first_direction);
   GlobalVariableSet(prefix + ".mode", group.cycle_mode);
   GlobalVariableSet(prefix + ".index", group.cycle_index);
   GlobalVariableSet(prefix + ".pendingindex", group.pending_index);
   GlobalVariableSet(prefix + ".reversals", group.reversal_count);
   GlobalVariableSet(prefix + ".pendingticket", group.pending_ticket);
   GlobalVariableSet(prefix + ".initial_high_ticket", group.initial_high_ticket);
   GlobalVariableSet(prefix + ".initial_low_ticket", group.initial_low_ticket);
   GlobalVariableSet(prefix + ".initial_high_price", group.initial_high_price);
   GlobalVariableSet(prefix + ".initial_low_price", group.initial_low_price);
   GlobalVariableSet(prefix + ".initial_high_direction", group.initial_high_direction);
   GlobalVariableSet(prefix + ".initial_low_direction", group.initial_low_direction);
   GlobalVariableSet(prefix + ".gridticket", group.grid_pending_ticket);
   GlobalVariableSet(prefix + ".slpoints", group.stop_points);
   GlobalVariableSet(prefix + ".tppoints", group.take_profit_points);
   GlobalVariableSet(prefix + ".cumlots", group.cumulative_loss_lots);
   GlobalVariableSet(prefix + ".prevgridlots", group.previous_grid_lots);
   GlobalVariableSet(prefix + ".gridlots", group.grid_lots);
   GlobalVariableSet(prefix + ".totallots", group.total_lots);
   GlobalVariableSet(prefix + ".anchor", group.anchor_price);
   GlobalVariableSet(prefix + ".lastentry", group.last_entry);
   GlobalVariableSet(prefix + ".linearextreme", group.linear_extreme);
   GlobalVariableSet(prefix + ".gridlevel", group.grid_filled_levels);
   GlobalVariableSet(prefix + ".gridmask", (double)group.grid_filled_mask);
   GlobalVariableSet(prefix + ".gridpendinglevel", group.grid_pending_level);
   GlobalVariableSet(prefix + ".gridpendingprice", group.grid_pending_price);
   GlobalVariableSet(StatePrefix() + ".multi.nextid", g_multi_next_id);
  }

void MultiLoadGroups()
  {
   const string next_key = StatePrefix() + ".multi.nextid";
   const string last_trigger_key = StatePrefix() + ".multi.lasttriggerbar";
   if(GlobalVariableCheck(last_trigger_key))
      g_multi_last_trigger_bar = (datetime)MathRound(GlobalVariableGet(last_trigger_key));
   if(!GlobalVariableCheck(next_key)) return;
   g_multi_next_id = MathMax(1, (int)MathRound(GlobalVariableGet(next_key)));
   for(int id = 1; id < g_multi_next_id; id++)
     {
      const string prefix = MultiStatePrefix(id);
      if(!GlobalVariableCheck(prefix + ".active")
         || GlobalVariableGet(prefix + ".active") < 0.5)
         continue;
      const int index = ArraySize(g_multi_groups);
      if(ArrayResize(g_multi_groups, index + 1) != index + 1) break;
      MultiGroupState state;
      MultiResetState(state, id);
      state.first_direction = (int)MathRound(GlobalVariableGet(prefix + ".first"));
      state.cycle_mode = (int)MathRound(GlobalVariableGet(prefix + ".mode"));
      state.cycle_index = (int)MathRound(GlobalVariableGet(prefix + ".index"));
      state.pending_index = (int)MathRound(GlobalVariableGet(prefix + ".pendingindex"));
      state.reversal_count = (int)MathRound(GlobalVariableGet(prefix + ".reversals"));
      state.pending_ticket = (int)MathRound(GlobalVariableGet(prefix + ".pendingticket"));
      if(GlobalVariableCheck(prefix + ".initial_high_ticket"))
         state.initial_high_ticket = (int)MathRound(GlobalVariableGet(prefix + ".initial_high_ticket"));
      if(GlobalVariableCheck(prefix + ".initial_low_ticket"))
         state.initial_low_ticket = (int)MathRound(GlobalVariableGet(prefix + ".initial_low_ticket"));
      if(GlobalVariableCheck(prefix + ".initial_high_price"))
         state.initial_high_price = GlobalVariableGet(prefix + ".initial_high_price");
      if(GlobalVariableCheck(prefix + ".initial_low_price"))
         state.initial_low_price = GlobalVariableGet(prefix + ".initial_low_price");
      if(GlobalVariableCheck(prefix + ".initial_high_direction"))
         state.initial_high_direction = (int)MathRound(GlobalVariableGet(prefix + ".initial_high_direction"));
      if(GlobalVariableCheck(prefix + ".initial_low_direction"))
         state.initial_low_direction = (int)MathRound(GlobalVariableGet(prefix + ".initial_low_direction"));
      state.grid_pending_ticket = (int)MathRound(GlobalVariableGet(prefix + ".gridticket"));
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
      if(GlobalVariableCheck(prefix + ".gridmask"))
         state.grid_filled_mask = (long)MathRound(GlobalVariableGet(prefix + ".gridmask"));
      else if(state.grid_filled_levels > 0)
         state.grid_filled_mask = ((long)1 << state.grid_filled_levels) - 1;
      state.grid_pending_level = (int)MathRound(GlobalVariableGet(prefix + ".gridpendinglevel"));
      state.grid_pending_price = GlobalVariableGet(prefix + ".gridpendingprice");
      g_multi_groups[index] = state;
     }
  }

int MultiPendingStatus(const int ticket, const int group_id, const bool grid)
  {
   if(ticket < 0)
      return REVERSE_PENDING_UNKNOWN;
   if(OrderSelect(ticket, SELECT_BY_TICKET, MODE_TRADES))
     {
      if(OrderSymbol() == Symbol() && OrderMagicNumber() == InpMagicNumber
         && IsOurPendingOrder() && MultiCommentMatches(OrderComment(), group_id)
         && MultiIsGridSelectedOrder() == grid)
         return REVERSE_PENDING_ACTIVE;
     }
   if(!OrderSelect(ticket, SELECT_BY_TICKET, MODE_HISTORY))
      return REVERSE_PENDING_UNKNOWN;
   if(OrderSymbol() != Symbol() || OrderMagicNumber() != InpMagicNumber
      || !MultiCommentMatches(OrderComment(), group_id))
      return REVERSE_PENDING_UNKNOWN;
   if(OrderType() == OP_BUY || OrderType() == OP_SELL)
      return REVERSE_PENDING_FILLED;
   if(IsOurPendingOrder())
      return REVERSE_PENDING_CANCELED;
   return REVERSE_PENDING_UNKNOWN;
  }

double MultiTotalLots(const int group_id, const int type)
  {
   double total = 0.0;
   for(int index = OrdersTotal() - 1; index >= 0; index--)
      if(OrderSelect(index, SELECT_BY_POS, MODE_TRADES)
         && OrderSymbol() == Symbol() && OrderMagicNumber() == InpMagicNumber
         && OrderType() == type && MultiCommentMatches(OrderComment(), group_id))
         total += OrderLots();
   return total;
  }

bool MultiClosePositions(const int group_id)
  {
   bool closed = true;
   RefreshRates();
   for(int index = OrdersTotal() - 1; index >= 0; index--)
     {
      if(!OrderSelect(index, SELECT_BY_POS, MODE_TRADES)
         || OrderSymbol() != Symbol() || OrderMagicNumber() != InpMagicNumber
         || (OrderType() != OP_BUY && OrderType() != OP_SELL)
         || !MultiCommentMatches(OrderComment(), group_id))
         continue;
      const int ticket = OrderTicket();
      const double price = OrderType() == OP_BUY ? Bid : Ask;
      if(!OrderClose(ticket, OrderLots(), price, 0, clrRed))
        {
         Print("Multi group close failed, group=", group_id, ", ticket=", ticket,
               ", error=", GetLastError());
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
      if(!OrderSelect(index, SELECT_BY_POS, MODE_TRADES)
         || OrderSymbol() != Symbol() || OrderMagicNumber() != InpMagicNumber
         || !IsOurPendingOrder() || !MultiCommentMatches(OrderComment(), group_id))
         continue;
      if(!OrderDelete(OrderTicket(), clrRed))
        {
         Print("Multi pending delete failed, group=", group_id,
               ", ticket=", OrderTicket(), ", error=", GetLastError());
         deleted = false;
        }
     }
   int remaining_ticket = -1;
   int remaining_type = OP_BUY;
   double remaining_volume = 0.0;
   double remaining_price = 0.0;
   if(MultiFindPending(group_id, false, remaining_ticket, remaining_type,
                       remaining_volume, remaining_price)
      || MultiFindPending(group_id, true, remaining_ticket, remaining_type,
                          remaining_volume, remaining_price))
      return false;
   return deleted;
  }

int MultiSequenceDirection(const MultiGroupState &group, const int index)
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
   return buy ? OP_BUY : OP_SELL;
  }

double MultiStopPrice(const MultiGroupState &group, const int type)
  {
   return type == OP_BUY
          ? PriceNormalize(group.anchor_price - group.stop_points * Point)
          : PriceNormalize(group.anchor_price + group.stop_points * Point);
  }

double MultiTakeProfitPrice(const MultiGroupState &group, const int type)
  {
   double reference = group.last_entry;
   if(InpTakeProfitMode == TAKE_PROFIT_LINEAR && group.linear_extreme > 0.0)
      reference = group.linear_extreme;
   return type == OP_BUY
          ? PriceNormalize(reference + group.take_profit_points * Point)
          : PriceNormalize(reference - group.take_profit_points * Point);
  }

void MultiSetStops(const MultiGroupState &group, const int type)
  {
   const double stop_loss = MultiStopPrice(group, type);
   const double take_profit = MultiTakeProfitPrice(group, type);
   for(int index = OrdersTotal() - 1; index >= 0; index--)
     {
      if(!OrderSelect(index, SELECT_BY_POS, MODE_TRADES)
         || OrderSymbol() != Symbol() || OrderMagicNumber() != InpMagicNumber
         || OrderType() != type || !MultiCommentMatches(OrderComment(), group.id))
         continue;
      if(MathAbs(OrderStopLoss() - stop_loss) <= Point * 0.5
         && MathAbs(OrderTakeProfit() - take_profit) <= Point * 0.5)
         continue;
      if(!OrderModify(OrderTicket(), OrderOpenPrice(), stop_loss, take_profit, 0, clrNONE))
         Print("Multi stops modify failed, group=", group.id,
               ", ticket=", OrderTicket(), ", error=", GetLastError());
     }
  }

bool MultiOpenMarket(MultiGroupState &group, const int type, const double requested_volume)
  {
   RefreshRates();
   const double volume = VolumeNormalize(requested_volume);
   if(volume <= 0.0)
      return false;
   const double price = type == OP_BUY ? Ask : Bid;
   const int ticket = OrderSend(Symbol(), type, volume, price, 0, 0.0, 0.0,
                                MultiGroupComment(group.id, false), InpMagicNumber,
                                0, clrBlue);
   if(ticket < 0)
     {
      const int error = GetLastError();
      Print("Multi market order failed, group=", group.id, ", error=", error);
      if(error == ERR_NOT_ENOUGH_MONEY)
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

int MultiInitialPendingStatus(const int ticket, const int group_id)
  {
   if(ticket < 0)
      return REVERSE_PENDING_UNKNOWN;
   if(OrderSelect(ticket, SELECT_BY_TICKET, MODE_TRADES))
     {
      if(IsOurPendingOrder() && MultiCommentMatches(OrderComment(), group_id)
         && MultiIsInitialPendingComment())
         return REVERSE_PENDING_ACTIVE;
      if(IsOurMarketOrder() && MultiCommentMatches(OrderComment(), group_id))
         return REVERSE_PENDING_FILLED;
     }
   if(OrderSelect(ticket, SELECT_BY_TICKET, MODE_HISTORY))
     {
      if(IsOurMarketOrder() && MultiCommentMatches(OrderComment(), group_id))
         return REVERSE_PENDING_FILLED;
      if(IsOurPendingOrder() && MultiCommentMatches(OrderComment(), group_id))
         return REVERSE_PENDING_CANCELED;
     }
   return REVERSE_PENDING_UNKNOWN;
  }

bool MultiPlaceInitialPendingPair(MultiGroupState &group, const double previous_high,
                                  const double previous_low, const int range_points,
                                  const double volume)
  {
   if(group.initial_high_ticket >= 0 || group.initial_low_ticket >= 0)
      return true;
   const int high_direction = ordertype == ORDERTYPE_FORWARD ? OP_BUY : OP_SELL;
   const int low_direction = ordertype == ORDERTYPE_FORWARD ? OP_SELL : OP_BUY;
   int high_ticket = -1;
   int low_ticket = -1;
   if(!PlaceInitialPendingOrder(high_direction, previous_high, range_points, volume,
                                MultiInitialPendingComment(group.id, true), high_ticket))
      return false;
   if(!PlaceInitialPendingOrder(low_direction, previous_low, range_points, volume,
                                MultiInitialPendingComment(group.id, false), low_ticket))
     {
      if(high_ticket > 0)
         OrderDelete(high_ticket, clrRed);
      return false;
     }
   group.initial_high_ticket = high_ticket;
   group.initial_low_ticket = low_ticket;
   group.initial_high_price = PriceNormalize(previous_high);
   group.initial_low_price = PriceNormalize(previous_low);
   group.initial_high_direction = high_direction;
   group.initial_low_direction = low_direction;
   group.stop_points = range_points;
   group.take_profit_points = range_points;
   return true;
  }

bool MultiHandleInitialPendingFill(MultiGroupState &group)
  {
   if(group.initial_high_ticket < 0 && group.initial_low_ticket < 0)
      return false;
   const int high_status = MultiInitialPendingStatus(group.initial_high_ticket, group.id);
   const int low_status = MultiInitialPendingStatus(group.initial_low_ticket, group.id);
   const bool high_filled = high_status == REVERSE_PENDING_FILLED;
   const bool low_filled = low_status == REVERSE_PENDING_FILLED;
   if(high_status == REVERSE_PENDING_ACTIVE && low_status == REVERSE_PENDING_ACTIVE)
      return true;
   if(high_filled || low_filled)
     {
      const int filled_ticket = high_filled ? group.initial_high_ticket : group.initial_low_ticket;
      const int other_ticket = filled_ticket == group.initial_high_ticket
                               ? group.initial_low_ticket : group.initial_high_ticket;
      const int other_status = high_filled ? low_status : high_status;
      if(other_status == REVERSE_PENDING_UNKNOWN)
         return true;
      if(other_ticket > 0 && other_status == REVERSE_PENDING_ACTIVE
         && !OrderDelete(other_ticket, clrRed))
         return true;
      int position_ticket = -1;
      int position_type = OP_BUY;
      double volume = 0.0;
      double entry = 0.0;
      double stop_loss = 0.0;
      double take_profit = 0.0;
      if(!FindPositionByTicket(filled_ticket, position_ticket, position_type, volume,
                               entry, stop_loss, take_profit))
         return true;
      group.first_direction = position_type == OP_BUY ? FIRST_BUY : FIRST_SELL;
      group.cycle_index = 0;
      group.pending_index = -1;
      group.pending_ticket = -1;
      group.anchor_price = entry;
      group.last_entry = entry;
      group.linear_extreme = entry;
      group.total_lots = volume;
      group.grid_filled_levels = 0;
      group.grid_filled_mask = 0;
      group.grid_pending_level = 0;
      group.grid_pending_price = 0.0;
      group.grid_lots = group.previous_grid_lots > 0.0
                        ? VolumeNormalize(group.previous_grid_lots * InpGridLotMultiplier)
                        : volume;
      group.initial_high_ticket = -1;
      group.initial_low_ticket = -1;
      group.initial_high_price = 0.0;
      group.initial_low_price = 0.0;
      MultiSetStops(group, position_type);
      MultiPlaceReversePending(group, position_type);
      MultiPlaceGridPending(group, position_type);
      return true;
     }
   if(high_status == REVERSE_PENDING_UNKNOWN || low_status == REVERSE_PENDING_UNKNOWN)
      return true;
   if(high_status == REVERSE_PENDING_ACTIVE || low_status == REVERSE_PENDING_ACTIVE)
     {
      const int active_ticket = high_status == REVERSE_PENDING_ACTIVE
                                ? group.initial_high_ticket : group.initial_low_ticket;
      if(active_ticket > 0 && !OrderDelete(active_ticket, clrRed))
         return true;
     }
   if(MultiInitialPendingStatus(group.initial_high_ticket, group.id) != REVERSE_PENDING_ACTIVE
      && MultiInitialPendingStatus(group.initial_low_ticket, group.id) != REVERSE_PENDING_ACTIVE)
     {
      group.initial_high_ticket = -1;
      group.initial_low_ticket = -1;
      group.initial_high_price = 0.0;
      group.initial_low_price = 0.0;
      return false;
     }
   return true;
  }

bool MultiPlaceReversePending(MultiGroupState &group, const int current_type)
  {
   if(group.reversal_count >= 最大反手次数 || group.stop_points <= 0
      || group.take_profit_points <= 0 || group.total_lots <= 0.0)
      return false;
   int existing_ticket = -1;
   int existing_type = OP_BUY;
   double existing_volume = 0.0;
   double existing_price = 0.0;
   if(MultiFindPending(group.id, false, existing_ticket, existing_type,
                       existing_volume, existing_price))
     {
      group.pending_ticket = existing_ticket;
      return true;
     }
   const int next_index = (group.cycle_index + 1) % 6;
   const int next_direction = MultiSequenceDirection(group, next_index);
   const double entry = MultiStopPrice(group, current_type);
   const int pending_type = PendingTypeForDirection(next_direction, entry);
   const double volume = MultiNextGroupLots(group, group.total_lots);
   const double sl_distance = group.stop_points * Point;
   const double tp_distance = group.take_profit_points * Point;
   double pending_sl = 0.0;
   double pending_tp = 0.0;
   if(pending_type == OP_BUYSTOP || pending_type == OP_BUYLIMIT)
     {
      pending_sl = PriceNormalize(entry - sl_distance);
      pending_tp = PriceNormalize(entry + tp_distance);
     }
   else
     {
      pending_sl = PriceNormalize(entry + sl_distance);
      pending_tp = PriceNormalize(entry - tp_distance);
     }
   RefreshRates();
   const int ticket = OrderSend(Symbol(), pending_type, volume, entry, 0,
                                pending_sl, pending_tp,
                                MultiGroupComment(group.id, false), InpMagicNumber,
                                0, clrOrange);
   if(ticket < 0)
     {
      Print("Multi reverse pending failed, group=", group.id,
            ", error=", GetLastError());
      return false;
     }
   group.pending_ticket = ticket;
   group.pending_index = next_index;
   return true;
  }

double MultiGridLevelPrice(const MultiGroupState &group, const int type, const int level)
  {
   if(网格数量 <= 0 || group.stop_points <= 0 || group.anchor_price <= 0.0)
      return 0.0;
   const double distance = group.stop_points * Point * level / 网格数量;
   return type == OP_BUY
          ? PriceNormalize(group.anchor_price - distance)
          : PriceNormalize(group.anchor_price + distance);
  }

string MultiGridComment(const int group_id, const int level)
  {
   return InpOrderComment + MultiGroupTag(group_id) + ".Grid."
          + IntegerToString(level);
  }

bool MultiPlaceGridPending(MultiGroupState &group, const int type)
  {
   if(网格数量 < 2 || group.grid_lots <= 0.0 || group.anchor_price <= 0.0)
      return false;
   bool placed = false;
   const double volume = VolumeNormalize(group.grid_lots);
   for(int level = 1; level < 网格数量; level++)
     {
      if((group.grid_filled_mask & GridLevelBit(level)) != 0)
         continue;
      const double entry = MultiGridLevelPrice(group, type, level);
      int existing_ticket = -1;
      if(!MultiNormalizeGridPendingLevel(group, type, level, entry, volume,
                                         existing_ticket))
         continue;
      if(existing_ticket <= 0)
        {
         const int pending_type = PendingTypeForDirection(type, entry);
         const double stop_loss = MultiStopPrice(group, type);
         const double take_profit = type == OP_BUY
                                    ? PriceNormalize(entry + group.take_profit_points * Point)
                                    : PriceNormalize(entry - group.take_profit_points * Point);
         RefreshRates();
         existing_ticket = OrderSend(Symbol(), pending_type, volume, entry, 0,
                                     stop_loss, take_profit,
                                     MultiGridComment(group.id, level), InpMagicNumber,
                                     0, clrOrange);
         if(existing_ticket < 0)
           {
            Print("Multi grid pending failed, group=", group.id,
                  ", level=", level, ", error=", GetLastError());
            continue;
           }
        }
      group.grid_pending_ticket = existing_ticket;
      group.grid_pending_level = level;
      group.grid_pending_price = entry;
      placed = true;
     }
   group.grid_filled_levels = MultiGridFilledLevelCount(group);
   return placed;
  }

void MultiHandleGridFill(MultiGroupState &group, const int type, const double current_total)
  {
   if(网格数量 < 2 || group.anchor_price <= 0.0)
      return;
   if(current_total <= group.total_lots + MarketInfo(Symbol(), MODE_LOTSTEP) * 0.5)
      return;
   bool changed = false;
   double latest_entry = 0.0;
   for(int level = 1; level < 网格数量; level++)
     {
      const long level_bit = GridLevelBit(level);
      if(level_bit == 0 || (group.grid_filled_mask & level_bit) != 0)
         continue;
      double fill_price = 0.0;
      if(MultiFindFilledGridOrder(group, type, level,
                                  MultiGridLevelPrice(group, type, level), fill_price))
        {
         group.grid_filled_mask |= level_bit;
         latest_entry = fill_price;
         changed = true;
        }
     }
   if(!changed)
      return;
   group.grid_filled_levels = MultiGridFilledLevelCount(group);
   group.grid_pending_level = 0;
   group.grid_pending_ticket = -1;
   group.grid_pending_price = 0.0;
   group.total_lots = current_total;
   if(latest_entry > 0.0)
      group.last_entry = latest_entry;
   MultiSetStops(group, type);
  }

bool MultiHandleReverseFill(MultiGroupState &group, const int type, const double entry,
                            const double current_total)
  {
   if(group.pending_ticket < 0 || group.pending_index < 0
      || group.pending_index == group.cycle_index
      || MultiPendingStatus(group.pending_ticket, group.id, false) != REVERSE_PENDING_FILLED)
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
   group.pending_ticket = -1;
   group.anchor_price = entry;
   group.last_entry = entry;
   group.linear_extreme = entry;
   group.total_lots = current_total;
   group.grid_filled_levels = 0;
   group.grid_filled_mask = 0;
   group.grid_pending_level = 0;
   group.grid_pending_ticket = -1;
   group.grid_pending_price = 0.0;
   group.grid_lots = group.previous_grid_lots > 0.0
                     ? VolumeNormalize(group.previous_grid_lots * 网格手数倍数)
                     : current_total;
   MultiSetStops(group, type);
   return true;
  }

bool MultiManageGroup(MultiGroupState &group)
  {
   if(MultiHandleInitialPendingFill(group))
      return true;
   int ticket = -1;
   int type = OP_BUY;
   double total = 0.0;
   double entry = 0.0;
   double stop_loss = 0.0;
   double take_profit = 0.0;
   if(!MultiFindPosition(group.id, ticket, type, total, entry, stop_loss, take_profit))
     {
      const int status = MultiPendingStatus(group.pending_ticket, group.id, false);
      if(status == REVERSE_PENDING_ACTIVE || status == REVERSE_PENDING_FILLED)
         return true;
      if(!MultiDeletePending(group.id))
         return true;
      group.active = false;
      MarkMultiCandleTriggerBar();
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
      const int inferred = (int)MathRound(MathAbs(take_profit - stop_loss) / (2.0 * Point));
      if(inferred <= 0)
         return true;
      group.stop_points = inferred;
      group.take_profit_points = inferred;
      group.anchor_price = entry;
      group.last_entry = entry;
      group.linear_extreme = entry;
     }
   if(group.anchor_price <= 0.0) group.anchor_price = entry;
   if(group.last_entry <= 0.0) group.last_entry = entry;
   if(group.linear_extreme <= 0.0) group.linear_extreme = entry;
   group.total_lots = total;
   if(group.grid_lots <= 0.0) group.grid_lots = total;

   RefreshRates();
   if(InpTakeProfitMode == TAKE_PROFIT_LINEAR)
     {
      const double reference = type == OP_BUY ? Ask : Bid;
      if((type == OP_BUY && reference < group.linear_extreme)
         || (type == OP_SELL && reference > group.linear_extreme))
        {
         group.linear_extreme = reference;
         MultiSetStops(group, type);
        }
     }
   const double desired_stop_loss = MultiStopPrice(group, type);
   const double desired_take_profit = MultiTakeProfitPrice(group, type);
   if((type == OP_BUY && Bid >= desired_take_profit)
      || (type == OP_SELL && Ask <= desired_take_profit))
     {
      if(!MultiDeletePending(group.id))
         return true;
      if(MultiClosePositions(group.id))
        {
         group.active = false;
         MarkMultiCandleTriggerBar();
        }
      return false;
     }
   if((type == OP_BUY && Bid <= desired_stop_loss)
      || (type == OP_SELL && Ask >= desired_stop_loss))
     {
      const int status = MultiPendingStatus(group.pending_ticket, group.id, false);
      int active_reverse_ticket = -1;
      int active_reverse_type = OP_BUY;
      double active_reverse_volume = 0.0;
      double active_reverse_price = 0.0;
      const bool has_active_reverse = MultiFindPending(group.id, false,
                                                        active_reverse_ticket,
                                                        active_reverse_type,
                                                        active_reverse_volume,
                                                        active_reverse_price);
      if(status == REVERSE_PENDING_FILLED)
         return true;
      if(status == REVERSE_PENDING_UNKNOWN
         && !has_active_reverse && group.pending_ticket >= 0)
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
      if(!MultiClosePositions(group.id)) return false;
      const int next_index = (group.cycle_index + 1) % 6;
      const int next_type = MultiSequenceDirection(group, next_index);
      group.reversal_count++;
      group.cycle_index = next_index;
      group.pending_index = -1;
      group.pending_ticket = -1;
      if(!MultiOpenMarket(group, next_type,
                          VolumeNormalize(group.cumulative_loss_lots * 首单手数倍数)))
         return false;
      if(!MultiFindPosition(group.id, ticket, type, total, entry, stop_loss, take_profit))
         return false;
      group.anchor_price = entry;
      group.last_entry = entry;
      group.linear_extreme = entry;
      group.total_lots = total;
      group.grid_filled_levels = 0;
      group.grid_filled_mask = 0;
      group.grid_pending_level = 0;
      group.grid_pending_ticket = -1;
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

void ProcessInitialPendingFillEvent()
  {
   if(g_reset_pending)
      return;
   if(InpDistanceMode == DISTANCE_CANDLE_RANGE && kline_enable_multiple == 1)
     {
      for(int index = ArraySize(g_multi_groups) - 1; index >= 0; index--)
         if(g_multi_groups[index].active
            && MultiHandleInitialPendingFill(g_multi_groups[index]))
            MultiSaveGroup(g_multi_groups[index]);
      return;
     }
   HandleInitialPendingFill();
  }

bool MultiTryOpenCandleGroup()
  {
   if(!IsInitialEntryAllowed()) return false;
   double previous_high = 0.0;
   double previous_low = 0.0;
   int range_points = 0;
   int first_direction = OP_BUY;
   if(!GetPreviousCandleRange(previous_high, previous_low, range_points))
      return false;
   const datetime current_bar = iTime(Symbol(), Period(), 0);
   if(Korder_type == KORDER_ONCE_PER_BAR && current_bar > 0
      && current_bar == g_multi_last_trigger_bar)
      return false;
   const int new_index = ArraySize(g_multi_groups);
   if(ArrayResize(g_multi_groups, new_index + 1) != new_index + 1)
      return false;
   MultiGroupState state;
   const int new_group_id = g_multi_next_id++;
   MultiResetState(state, new_group_id);
   state.first_direction = first_direction == OP_BUY ? FIRST_BUY : FIRST_SELL;
   state.cycle_mode = InpCycleMode;
   state.stop_points = range_points;
   state.take_profit_points = range_points;
   if(Korder_type == KORDER_ONCE_PER_BAR)
     {
      if(!MultiPlaceInitialPendingPair(state, previous_high, previous_low,
                                       range_points, 首单手数))
        {
         MultiRemoveGroup(new_index);
         return false;
        }
      g_multi_groups[new_index] = state;
      MultiSaveGroup(g_multi_groups[new_index]);
      if(current_bar > 0)
         MarkMultiCandleTriggerBar();
      return true;
     }
   if(!GetBreakoutDirection(previous_high, previous_low, first_direction))
     {
      MultiRemoveGroup(new_index);
      return false;
     }
   state.first_direction = first_direction == OP_BUY ? FIRST_BUY : FIRST_SELL;
   if(!MultiOpenMarket(state, first_direction, 首单手数))
     {
      MultiRemoveGroup(new_index);
      return false;
     }
   int ticket = -1;
   int type = OP_BUY;
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

void MarkMultiCandleTriggerBar()
  {
   if(Korder_type != KORDER_ONCE_PER_BAR)
      return;
   const datetime current_bar = iTime(Symbol(), Period(), 0);
   if(current_bar > 0)
      g_multi_last_trigger_bar = current_bar;
   GlobalVariableSet(StatePrefix() + ".multi.lasttriggerbar", (double)g_multi_last_trigger_bar);
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
      if(g_reset_pending) return;
     }
   if(closed_group) return;
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
       || InpAverageCandleCount <= 0 || InpAverageStopMultiplier <= 0.0
       || InpAverageTakeProfitMultiplier <= 0.0
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
   if(!EventSetTimer(1))
      Print("Unable to start the initial pending OCO timer.");
   return INIT_SUCCEEDED;
  }

void OnTimer()
  {
   ProcessInitialPendingFillEvent();
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
   EventKillTimer();
   ReleaseExecutionOwnership();
  }
