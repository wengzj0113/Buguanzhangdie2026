#property strict
#property version   "2.10"
#property description "XAUUSD Net RR v2.10: optional cash cost gate and virtual entries"

enum FirstDirection
  {
   FIRST_BUY = 0,  // 首单做多
   FIRST_SELL = 1  // 首单做空
  };

enum FirstDirectionMode
  {
   FIRST_DIRECTION_PRESET = 0,     // 使用预设首单方向
   FIRST_DIRECTION_BOLLINGER = 1   // 按布林带中轨判断首单方向
  };

enum CycleMode
  {
   CYCLE_MODE_1 = 0,  // 模式一：首单多=多空空多空空；首单空=空多多空多多
   CYCLE_MODE_2 = 1,  // 模式二：首单多=多空多空多多；首单空=空多空多空空
   CYCLE_MODE_3 = 2,  // 模式三：首单多=多空多多空多；首单空=空多空空多空
   CYCLE_MODE_4 = 3   // 模式四：首单多=多空空多多空空；首单空=空多多空空多多
  };

enum DistanceMode
  {
   DISTANCE_FIXED = 0,         // 固定止盈止损距离
   DISTANCE_CANDLE_RANGE = 1,  // 上一根K线高度
   DISTANCE_AVERAGE_CANDLE_RANGE = 2, // 过去N根K线平均高度
   DISTANCE_LONG_CANDLE = 3,   // 长K线方向市价入场，距离使用固定值
   DISTANCE_BOLLINGER_RANGE = 4 // 当前布林带上下轨距离的四分之一作为止损和止盈
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

// ===== 策略与首单 =====
// 首单方向：做多或做空
input FirstDirection 首单方向 = FIRST_BUY; // [方向]首单做多或做空
// 首单方向确定方式：预设方向或按当前价格相对布林带中轨判断
input FirstDirectionMode 首单方向确定方式 = FIRST_DIRECTION_PRESET; // [方向]预设方向或按布林中轨判断
// 固定距离、平均K线高度和长K线模式均使用用户选择的循环模式
input CycleMode      循环模式 = CYCLE_MODE_1; // [策略]订单组循环方向序列

// ===== 入场信号 =====
// 入场/止盈止损距离模式：固定距离、K线高度、平均K线高度、长K线市价或布林带区间
input DistanceMode   距离模式 = DISTANCE_FIXED; // [策略]止损和止盈距离来源
// K线高度模式下的正向或逆向开单方式
input OrderTypeMode  开单方式 = ORDERTYPE_FORWARD; // [开单]信号方向正向或反向
// K线高度模式下同一根当前K线的首单触发次数
input CandleOrderMode K线开单模式 = KORDER_ONCE_PER_BAR; // [开单]每根K线触发一次或重复触发
// K线高度模式是否允许多个订单组并行：0=单组，1=多组
input int            K线多组 = 0; // [开单]0=单组，1=允许多组
input int            篮子数量 = 1; // [开单]1=单篮子，2=反向双篮子
// 首单方向判断使用的布林带周期（标准值为20）
input int            布林带周期 = 20; // [布林带]计算周期（K线根数）
// 首单方向判断使用的布林带标准差倍数（标准值为2.0）
input double         布林带标准差 = 2.0; // [布林带]上下轨标准差倍数

// ===== 手数与风险 =====
// 首单手数
input double         首单手数 = 0.01; // [手数]首轮首单交易手数
// 首单手数倍数；订单组止损后下一组首单手数乘此倍数
input double         首单手数倍数 = 1.0; // [手数]类型1止损后首单手数倍数
// 止损后首单手数计算类型：1=累计订单组总手数，2=上一组首单手数
input int            止损首单类型 = 2; // [手数]止损后算法：1累计组手数，2首单倍数，3固定手数
// 首单手数类型2的倍数
input double         首单类型2倍数 = 2.0; // [手数]类型2使用的上一组首单倍数
// 止损后最多切换到下一订单组的次数；达到后清理并重新开始
input int            最大反手次数 = 5; // [风险]止损后最多更换订单组次数

// ===== 网格与止盈 =====
// 止盈移动方式：网格成交后移动或按价格线性移动
input TakeProfitMode  止盈移动模式 = TAKE_PROFIT_GRID; // [止盈]网格移动或线性移动
// 止损区间分成的格数；内部格数为总格数减一
input int            网格数量 = 2; // [网格]止损区间等分格数
// 价格向有利方向移动时是否网格加单：0=关闭，1=开启
input int            有利方向加单 = 0; // [网格]0=关闭，1=有利方向加单
// 有利方向网格成交后是否同步移动止损：0=关闭，1=开启
input int            动态止损 = 0; // [网格]0=关闭，1=随有利网格移动止损
// 下一订单组网格手数相对上一组的倍数
input double         网格手数倍数 = 2.0; // [网格]下一订单组网格手数倍数
// 可视化界面开关：0=关闭，1=开启
input int            v_enable = 0; // [界面]0=关闭，1=显示参数面板

// ===== 止盈止损距离 =====
// 固定距离模式下的止损点数
input int            固定止损距离 = 500; // [距离]固定模式止损距离（点）
// 固定距离模式下的止盈点数
input int            固定止盈距离 = 500; // [距离]固定模式止盈距离（点）
// 上一根K线允许使用的最小高度点数
input int            K线最小高度 = 500; // [距离]上一根K线最小高度（点）
// 上一根K线允许使用的最大高度点数
input int            K线最大高度 = 1000; // [距离]上一根K线最大高度（点）
// 平均K线模式使用的已完成K线根数
input int            平均K线根数 = 20; // [距离]计算平均高度的已完成K线数
// 平均K线高度计算的止损倍数
input double         平均止损倍数 = 2.0; // [距离]平均K线高度止损倍数
// 平均K线模式中止盈距离相对止损距离的倍数
input double         平均止盈倍数 = 2.0; // [距离]止盈距离相对止损距离倍数

// ===== 订单识别 =====
// 用于识别本EA订单的唯一编号
input int            订单识别编号 = 20260830; // [订单]识别本EA订单的编号
// 订单注释；网格单会自动追加网格标记
input string         订单注释 = "不管涨跌"; // [订单]发送到平台的订单备注

// ===== 交易时段 =====
// 允许开首单的开始时间，使用平台服务器时间，格式为 时:分
input string         开始时间 = "08:00"; // [时段]时段1开始（服务器时间）
// 允许开首单的结束时间，使用平台服务器时间，格式为 时:分
input string         结束时间 = "23:00"; // [时段]时段1结束（服务器时间）
// 时段2允许开首单的开始时间；00:00-00:00表示关闭
input string         时段2开始时间 = "00:00"; // [时段]时段2开始；00:00-00:00关闭
// 时段2允许开首单的结束时间；支持跨午夜
input string         时段2结束时间 = "00:00"; // [时段]时段2结束；支持跨午夜
// 时段3允许开首单的开始时间；00:00-00:00表示关闭
input string         时段3开始时间 = "00:00"; // [时段]时段3开始；00:00-00:00关闭
// 时段3允许开首单的结束时间；支持跨午夜
input string         时段3结束时间 = "00:00"; // [时段]时段3结束；支持跨午夜

// ===== 净盈亏比与交易成本 =====

// XAUUSD 现金成本模式。零预算不得用于启用；点差已包含在实际 Bid/Ask 成交价中。
input bool   启用XAU净盈亏比 = false; // [成本]0=关闭，1=启用成本校正
input double 目标净盈亏比 = 0.0;  // [成本]目标净盈亏比；0=保留初始止盈/止损距离比
input double 最大开仓点差点数 = 0.0; // [成本]开仓最大点差（点）；0=不限
input double 最大点差占止损比例 = 0.0; // [成本]点差/止损最大比例（%）；0=不限
input int    最大开仓滑点点数 = 0; // [成本]开仓最大滑点（点）；0=不限制
input int    预计平仓滑点点数 = 0; // [成本]预计平仓滑点（点）；0=不计入
input double 每手往返佣金费用预算 = 0.0; // [成本]每手开平仓佣金预算；0=不计入
input int    最大止盈补偿点数 = 0; // [成本]止盈成本补偿上限（点）；0=不限
input double 最大止盈补偿比例 = 0.0; // [成本]止盈成本补偿比例上限（%）；0=不限
input double 单轮最大预计亏损权益比例 = 0.0; // [成本]单轮预计亏损占权益上限（%）；0=不限
input double 全部轮次最大预计亏损权益比例 = 0.0; // [成本]全轮预计亏损占权益上限（%）；0=不限
input int    最长报价延迟毫秒 = 0; // [成本]允许报价延迟上限（毫秒）；0=不限

// 内部兼容映射：以下名称不显示在参数设置中，仅用于保持既有逻辑代码兼容。
#define InpFirstDirection 首单方向
#define InpCycleMode 循环模式
#define InpDistanceMode 距离模式
#define ordertype 开单方式
#define Korder_type K线开单模式
#define InpTakeProfitMode 止盈移动模式
#define InpInitialLots 首单手数
#define kline_enable_multiple K线多组
#define FirstOrderLotType 止损首单类型
#define FirstOrderMult 首单类型2倍数
#define InpGridCount 网格数量
#define FavorableGridEnable 有利方向加单
#define DynamicStopLossEnable 动态止损
#define MAX_GRID_COUNT 63
#define MAX_SINGLE_REVERSAL_LOTS 100.0
#define MAX_GROUP_REVERSAL_LOTS 200.0

enum ReversalLotPlanStatus
  {
   REVERSAL_LOT_SINGLE = 0,
   REVERSAL_LOT_SPLIT = 1,
   REVERSAL_LOT_RESTART_GROUP = 2
  };

struct ReversalLotPlan
  {
   int    status;
   int    count;
   double first_lots;
   double second_lots;
  };

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
#define MAX_OPERATION_WINDOWS 3

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
double g_group_first_lots = 0.0;
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
int    g_favorable_grid_filled_levels = 0;
long   g_favorable_grid_filled_mask = 0;
int    g_favorable_grid_pending_level = 0;
double g_favorable_grid_pending_price = 0.0;
int    g_grid_order_tickets[MAX_GRID_COUNT];
int    g_favorable_grid_order_tickets[MAX_GRID_COUNT];
bool   g_reset_pending = false;
bool   g_cost_wait_flat = false;
bool   g_cost_active = false;
bool   g_cost_frozen = false;
datetime g_cost_cycle_start = 0;
long g_cost_cycle_id = 0;
double g_cost_target = 0.0;
double g_cost_tp = 0.0;
double g_cost_high = 0.0;
double g_cost_low = 0.0;
datetime g_cost_trigger_bar = 0;
int g_cost_good_quotes = 0;
int g_cost_last_ticket = -1;
int g_cost_last_type = OP_BUY;
double g_cost_last_stop = 0.0;
int g_cost_last_closed_handled = -1;
int    g_start_operation_minutes[MAX_OPERATION_WINDOWS];
int    g_end_operation_minutes[MAX_OPERATION_WINDOWS];

void ClearGridOrderTicketCache()
  {
   for(int level = 0; level < MAX_GRID_COUNT; level++)
     {
      g_grid_order_tickets[level] = -1;
      g_favorable_grid_order_tickets[level] = -1;
     }
  }

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

long GridMaskLowPart(const long mask)
  {
   return mask & 0xFFFFFFFF;
  }

long GridMaskHighPart(const long mask)
  {
   return (mask >> 32) & 0xFFFFFFFF;
  }

void SaveGridMask(const string prefix, const long mask)
  {
   GlobalVariableSet(prefix + ".gridmask.low", (double)GridMaskLowPart(mask));
   GlobalVariableSet(prefix + ".gridmask.high", (double)GridMaskHighPart(mask));
   GlobalVariableDel(prefix + ".gridmask");
  }

bool LoadGridMask(const string prefix, long &mask)
  {
   const string low_key = prefix + ".gridmask.low";
   const string high_key = prefix + ".gridmask.high";
   if(!GlobalVariableCheck(low_key) || !GlobalVariableCheck(high_key))
      return false;
   const long low = (long)MathRound(GlobalVariableGet(low_key));
   const long high = (long)MathRound(GlobalVariableGet(high_key));
   mask = (high << 32) | low;
   return true;
  }

void DeleteGridMask(const string prefix)
  {
   GlobalVariableDel(prefix + ".gridmask.low");
   GlobalVariableDel(prefix + ".gridmask.high");
   GlobalVariableDel(prefix + ".gridmask");
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
   GlobalVariableSet(prefix + ".groupfirstlots", g_group_first_lots);
   GlobalVariableSet(prefix + ".prevgridlots", g_previous_grid_lots);
   GlobalVariableSet(prefix + ".gridlots", g_grid_lots);
   GlobalVariableSet(prefix + ".grouptotal", g_group_total_lots);
   GlobalVariableSet(prefix + ".anchor", g_group_anchor_price);
   GlobalVariableSet(prefix + ".lastentry", g_group_last_entry);
   GlobalVariableSet(prefix + ".linearextreme", g_group_linear_extreme);
    GlobalVariableSet(prefix + ".gridlevel", g_grid_filled_levels);
    SaveGridMask(prefix, g_grid_filled_mask);
    GlobalVariableSet(prefix + ".gridpendinglevel", g_grid_pending_level);
    GlobalVariableSet(prefix + ".gridpendingprice", g_grid_pending_price);
    GlobalVariableSet(prefix + ".favorablegridlevel", g_favorable_grid_filled_levels);
    SaveGridMask(prefix + ".favorable", g_favorable_grid_filled_mask);
    GlobalVariableSet(prefix + ".favorablegridpendinglevel", g_favorable_grid_pending_level);
    GlobalVariableSet(prefix + ".favorablegridpendingprice", g_favorable_grid_pending_price);
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
   GlobalVariableDel(prefix + ".groupfirstlots");
   GlobalVariableDel(prefix + ".prevgridlots");
   GlobalVariableDel(prefix + ".gridlots");
   GlobalVariableDel(prefix + ".grouptotal");
   GlobalVariableDel(prefix + ".anchor");
   GlobalVariableDel(prefix + ".lastentry");
   GlobalVariableDel(prefix + ".linearextreme");
   GlobalVariableDel(prefix + ".gridlevel");
    DeleteGridMask(prefix);
    GlobalVariableDel(prefix + ".gridpendinglevel");
    GlobalVariableDel(prefix + ".gridpendingprice");
    GlobalVariableDel(prefix + ".favorablegridlevel");
    DeleteGridMask(prefix + ".favorable");
    GlobalVariableDel(prefix + ".favorablegridpendinglevel");
    GlobalVariableDel(prefix + ".favorablegridpendingprice");
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
   g_group_first_lots = 0.0;
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
    g_favorable_grid_filled_levels = 0;
    g_favorable_grid_filled_mask = 0;
    g_favorable_grid_pending_level = 0;
    g_favorable_grid_pending_price = 0.0;
   ClearGridOrderTicketCache();
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
   if(saved_index >= 0
      && saved_index < (saved_mode == CYCLE_MODE_4 ? 7 : 6)
      && (saved_first == FIRST_BUY || saved_first == FIRST_SELL)
      && (saved_mode == CYCLE_MODE_1 || saved_mode == CYCLE_MODE_2
          || saved_mode == CYCLE_MODE_3 || saved_mode == CYCLE_MODE_4))
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
   if(GlobalVariableCheck(prefix + ".groupfirstlots"))
      g_group_first_lots = GlobalVariableGet(prefix + ".groupfirstlots");
   if(GlobalVariableCheck(prefix + ".prevgridlots"))
      g_previous_grid_lots = GlobalVariableGet(prefix + ".prevgridlots");
   if(GlobalVariableCheck(prefix + ".gridlots"))
      g_grid_lots = GlobalVariableGet(prefix + ".gridlots");
   if(GlobalVariableCheck(prefix + ".grouptotal"))
      g_group_total_lots = GlobalVariableGet(prefix + ".grouptotal");
   if(g_group_first_lots <= 0.0 && g_group_total_lots > 0.0)
      g_group_first_lots = g_group_total_lots;
   if(GlobalVariableCheck(prefix + ".anchor"))
      g_group_anchor_price = GlobalVariableGet(prefix + ".anchor");
   if(GlobalVariableCheck(prefix + ".lastentry"))
      g_group_last_entry = GlobalVariableGet(prefix + ".lastentry");
   if(GlobalVariableCheck(prefix + ".linearextreme"))
      g_group_linear_extreme = GlobalVariableGet(prefix + ".linearextreme");
   if(GlobalVariableCheck(prefix + ".gridlevel"))
      g_grid_filled_levels = (int)MathRound(GlobalVariableGet(prefix + ".gridlevel"));
   if(!LoadGridMask(prefix, g_grid_filled_mask)
      && GlobalVariableCheck(prefix + ".gridmask"))
      g_grid_filled_mask = (long)MathRound(GlobalVariableGet(prefix + ".gridmask"));
   else if(g_grid_filled_levels > 0)
      g_grid_filled_mask = ((long)1 << g_grid_filled_levels) - 1;
   if(GlobalVariableCheck(prefix + ".gridpendinglevel"))
      g_grid_pending_level = (int)MathRound(GlobalVariableGet(prefix + ".gridpendinglevel"));
    if(GlobalVariableCheck(prefix + ".gridpendingprice"))
       g_grid_pending_price = GlobalVariableGet(prefix + ".gridpendingprice");
    if(GlobalVariableCheck(prefix + ".favorablegridlevel"))
       g_favorable_grid_filled_levels = (int)MathRound(GlobalVariableGet(prefix + ".favorablegridlevel"));
    if(!LoadGridMask(prefix + ".favorable", g_favorable_grid_filled_mask)
       && GlobalVariableCheck(prefix + ".favorable.gridmask"))
       g_favorable_grid_filled_mask = (long)MathRound(GlobalVariableGet(prefix + ".favorable.gridmask"));
    else if(g_favorable_grid_filled_levels > 0)
       g_favorable_grid_filled_mask = ((long)1 << g_favorable_grid_filled_levels) - 1;
    if(GlobalVariableCheck(prefix + ".favorablegridpendinglevel"))
       g_favorable_grid_pending_level = (int)MathRound(GlobalVariableGet(prefix + ".favorablegridpendinglevel"));
    if(GlobalVariableCheck(prefix + ".favorablegridpendingprice"))
       g_favorable_grid_pending_price = GlobalVariableGet(prefix + ".favorablegridpendingprice");
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

bool IsOperationWindowActive(const int current_minutes, const int start_minutes,
                             const int end_minutes)
  {
   if(start_minutes == 0 && end_minutes == 0)
      return false;
   if(start_minutes == end_minutes)
      return true;
   if(start_minutes < end_minutes)
      return current_minutes >= start_minutes && current_minutes < end_minutes;
   return current_minutes >= start_minutes || current_minutes < end_minutes;
  }

bool IsInitialEntryAllowed()
  {
   // Finish an existing legacy cycle before creating any cost-mode exposure.
   if(g_cost_wait_flat) return false;
   const datetime current_time = TimeCurrent();
   const int current_minutes = TimeHour(current_time) * 60 + TimeMinute(current_time);
   for(int window = 0; window < MAX_OPERATION_WINDOWS; window++)
     {
      if(IsOperationWindowActive(current_minutes, g_start_operation_minutes[window],
                                 g_end_operation_minutes[window]))
         return true;
     }
   return false;
  }

bool IsInitialSpreadAllowed()
  {
   if(!CostMode())
      return true;
   RefreshRates();
   if(Point <= 0.0 || Bid <= 0.0 || Ask <= Bid)
      return false;
   return (Ask-Bid)/Point <= 最大开仓点差点数;
  }

int CycleLength(const int cycle_mode)
  {
   return cycle_mode == CYCLE_MODE_4 ? 7 : 6;
  }

int SequenceDirection(const int index)
  {
   const int cycle_length = CycleLength(g_active_cycle_mode);
   const int normalized_index = ((index % cycle_length) + cycle_length) % cycle_length;
   bool buy_direction = false;
   if(g_active_cycle_mode == CYCLE_MODE_1)
      buy_direction = normalized_index == 0 || normalized_index == 3;
   else if(g_active_cycle_mode == CYCLE_MODE_2)
      buy_direction = normalized_index == 0 || normalized_index == 2
                      || normalized_index == 4 || normalized_index == 5;
   else if(g_active_cycle_mode == CYCLE_MODE_3)
      buy_direction = normalized_index == 0 || normalized_index == 2
                      || normalized_index == 3 || normalized_index == 5;
   else
      buy_direction = normalized_index == 0 || normalized_index == 3
                      || normalized_index == 4;

   if(g_active_first_direction == FIRST_SELL)
      buy_direction = !buy_direction;
   return buy_direction ? OP_BUY : OP_SELL;
  }

int NextCycleIndex()
  {
   return (g_cycle_index + 1) % CycleLength(g_active_cycle_mode);
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

bool GetLongCandleDirection(int &first_direction)
  {
   // K1 使用上一根已完成K线；K2～K21为用于比较的前20根K线。
   if(iBars(Symbol(), Period()) < 22)
      return false;

   const double k1_open = iOpen(Symbol(), Period(), 1);
   const double k1_close = iClose(Symbol(), Period(), 1);
   const double k1_high = iHigh(Symbol(), Period(), 1);
   const double k1_low = iLow(Symbol(), Period(), 1);
   if(k1_open <= 0.0 || k1_close <= 0.0 || k1_high <= k1_low)
      return false;

   const double k1_range = k1_high - k1_low;
   double max_prior_range = 0.0;
   for(int shift = 2; shift <= 21; shift++)
     {
      const double high = iHigh(Symbol(), Period(), shift);
      const double low = iLow(Symbol(), Period(), shift);
      if(high <= 0.0 || low <= 0.0 || high <= low)
         return false;
      max_prior_range = MathMax(max_prior_range, high - low);
     }
   if(k1_range < max_prior_range)
      return false;

   if(k1_close > k1_open)
      first_direction = OP_BUY;
   else if(k1_close < k1_open)
      first_direction = OP_SELL;
   else
      return false;
   return true;
  }

bool GetBollingerFirstDirection(int &first_direction)
  {
   if(布林带周期 <= 0 || 布林带标准差 <= 0.0
      || iBars(Symbol(), Period()) < 布林带周期)
      return false;
   RefreshRates();
   const double middle = iBands(Symbol(), Period(), 布林带周期,
                                布林带标准差, 0, PRICE_CLOSE,
                                MODE_MAIN, 0);
   if(middle == EMPTY_VALUE || middle <= 0.0 || Bid <= 0.0 || Ask <= 0.0)
      return false;
   const double price = (Bid + Ask) * 0.5;
   const double epsilon = Point * 0.5;
   if(MathAbs(price - middle) <= epsilon)
      return false;
   if(price > middle)
      first_direction = OP_BUY;
   else
      first_direction = OP_SELL;
   return true;
  }

bool GetBollingerDistancePoints(int &stop_loss_points, int &take_profit_points)
  {
   if(布林带周期 <= 0 || 布林带标准差 <= 0.0)
      return false;
   RefreshRates();
   const double upper = iBands(Symbol(), Period(), 布林带周期,
                               布林带标准差, 0, PRICE_CLOSE,
                               MODE_UPPER, 0);
   const double lower = iBands(Symbol(), Period(), 布林带周期,
                               布林带标准差, 0, PRICE_CLOSE,
                               MODE_LOWER, 0);
   if(upper == EMPTY_VALUE || lower == EMPTY_VALUE || upper <= lower)
      return false;
   const double width_points = (upper - lower) / Point;
   stop_loss_points = (int)MathRound(width_points / 4.0);
   take_profit_points = stop_loss_points;
   return stop_loss_points > 0 && take_profit_points > 0;
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

   if(InpDistanceMode == DISTANCE_LONG_CANDLE)
     {
      stop_loss_points = InpStopLossDistancePoints;
      take_profit_points = InpTakeProfitDistancePoints;
      return stop_loss_points > 0 && take_profit_points > 0;
     }

   if(InpDistanceMode == DISTANCE_BOLLINGER_RANGE)
      return GetBollingerDistancePoints(stop_loss_points, take_profit_points);

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

bool BuildReversalLotPlan(const double requested_volume, ReversalLotPlan &plan)
  {
   plan.status = REVERSAL_LOT_RESTART_GROUP;
   plan.count = 0;
   plan.first_lots = 0.0;
   plan.second_lots = 0.0;
   if(!MathIsValidNumber(requested_volume) || requested_volume <= 0.0)
      return false;
   if(requested_volume >= MAX_GROUP_REVERSAL_LOTS)
      return true;
   if(requested_volume <= MAX_SINGLE_REVERSAL_LOTS)
     {
      plan.status = REVERSAL_LOT_SINGLE;
      plan.count = 1;
      plan.first_lots = requested_volume;
      return true;
     }
   plan.status = REVERSAL_LOT_SPLIT;
   plan.count = 2;
   plan.first_lots = requested_volume / 2.0;
   plan.second_lots = requested_volume - plan.first_lots;
   return true;
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

bool ClosePreviousGroupAfterReverseFill(const int keep_ticket)
  {
   if(keep_ticket <= 0 || !OrderSelect(keep_ticket, SELECT_BY_TICKET, MODE_TRADES)
      || !IsOurMarketOrder())
      return false;
   bool closed = true;
   RefreshRates();
   for(int index = OrdersTotal() - 1; index >= 0; index--)
     {
      if(!OrderSelect(index, SELECT_BY_POS, MODE_TRADES)
         || !IsOurMarketOrder() || OrderTicket() == keep_ticket)
         continue;
      const int ticket = OrderTicket();
      const int type = OrderType();
      const double close_price = type == OP_BUY ? Bid : Ask;
      if(!OrderClose(ticket, OrderLots(), close_price, 0, clrRed))
        {
         Print("Previous group close failed after reverse fill, ticket=", ticket,
               ", error=", GetLastError());
         closed = false;
        }
     }
   for(int index = OrdersTotal() - 1; index >= 0; index--)
     {
      if(OrderSelect(index, SELECT_BY_POS, MODE_TRADES)
         && IsOurMarketOrder() && OrderTicket() != keep_ticket)
         closed = false;
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

bool ResetOrderGroupAfterOversizedReversal()
  {
   Print("Oversized reversal stopped this order group; start a fresh base-lot group on the next tick.");
   if(!DeleteAllPending() || !CloseAllOurPositions())
      return false;
   ClearState();
   return true;
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
   g_group_first_lots = 0.0;
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
   g_favorable_grid_filled_levels = 0;
   g_favorable_grid_filled_mask = 0;
   g_favorable_grid_pending_level = 0;
   g_favorable_grid_pending_price = 0.0;
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
   double stop_loss = type == OP_BUY
                      ? g_group_anchor_price - g_group_stop_points * Point
                      : g_group_anchor_price + g_group_stop_points * Point;
   if(DynamicStopLossEnable == 1 && InpGridCount >= 2)
     {
      const int level = HighestFavorableGridLevel(g_favorable_grid_filled_mask);
      const double grid_spacing = g_group_stop_points * Point / InpGridCount;
      if(type == OP_BUY)
         stop_loss += level * grid_spacing;
      else
         stop_loss -= level * grid_spacing;
     }
   return PriceNormalize(stop_loss);
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
   return modified && StopsVerified(type);
   }

bool StopsVerified(const int type)
  {
   bool found = false;
   const double stop_loss = GroupStopPrice(type);
   const double take_profit = GroupTakeProfitPrice(type);
   for(int index = OrdersTotal() - 1; index >= 0; index--)
     {
      if(!OrderSelect(index, SELECT_BY_POS, MODE_TRADES) || !IsOurMarketOrder()
         || OrderType() != type)
         continue;
      found = true;
      if(OrderStopLoss() <= 0.0 || OrderTakeProfit() <= 0.0
         || MathAbs(OrderStopLoss() - stop_loss) > Point * 0.5
         || MathAbs(OrderTakeProfit() - take_profit) > Point * 0.5)
         return false;
     }
   return found;
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

bool SendMarketLeg(const int type, const double requested_volume)
  {
   if(启用XAU净盈亏比 && !g_cost_wait_flat) return false;
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

bool OpenMarket(const int type, const double requested_volume)
  {
   ReversalLotPlan plan;
   if(!BuildReversalLotPlan(requested_volume, plan))
      return false;
   if(plan.status == REVERSAL_LOT_RESTART_GROUP)
     {
      PrintFormat("Reversal volume %.2f reaches %.2f lots; stop this group and restart from base lot on the next tick.",
                  requested_volume, MAX_GROUP_REVERSAL_LOTS);
      return false;
     }
   const double step = MarketInfo(Symbol(), MODE_LOTSTEP);
   const double tolerance = step > 0.0 ? step * 0.5 : 0.0000001;
   const double target = plan.first_lots
                         + (plan.count == 2 ? plan.second_lots : 0.0);
   double current = TotalPositionLots(type);
   for(int leg = 0; leg < plan.count && current + tolerance < target; leg++)
     {
      const double leg_target = leg == 0 ? plan.first_lots : plan.second_lots;
      const double remaining = target - current;
      const double leg_volume = MathMin(leg_target, remaining);
      if(leg_volume <= tolerance)
         continue;
      if(!SendMarketLeg(type, leg_volume))
         return false;
      current = TotalPositionLots(type);
     }
   if(current + tolerance < target)
     {
      PrintFormat("Reversal volume incomplete: target=%.2f, actual=%.2f; retrying missing leg on the next tick.",
                  target, current);
      return false;
     }
   return true;
  }

double NextGroupLotsRaw(const double fallback_volume)
   {
    if(FirstOrderLotType == 2)
      {
       const double base = g_group_first_lots > 0.0
                           ? g_group_first_lots : fallback_volume;
       return base * FirstOrderMult;
      }
    double requested = g_cumulative_loss_lots + g_group_total_lots;
   if(requested <= 0.0)
      requested = fallback_volume;
   else
      requested *= 首单手数倍数;
    return requested;
   }

double NextGroupLots(const double fallback_volume)
   {
    return VolumeNormalize(NextGroupLotsRaw(fallback_volume));
   }

double NextGroupLotsAfterStopRaw(const double fallback_volume)
   {
    if(FirstOrderLotType == 2)
      {
       const double base = g_group_first_lots > 0.0
                           ? g_group_first_lots : fallback_volume;
       return base * FirstOrderMult;
      }
    const double requested = g_cumulative_loss_lots > 0.0
                             ? g_cumulative_loss_lots : fallback_volume;
    return requested * 首单手数倍数;
   }

double NextGroupLotsAfterStop(const double fallback_volume)
   {
    return VolumeNormalize(NextGroupLotsAfterStopRaw(fallback_volume));
   }

bool PlaceInitialPendingOrder(const int direction, const double entry,
                              const int distance_points, const double volume,
                              const string comment, int &ticket)
  {
   if(启用XAU净盈亏比 && !g_cost_wait_flat) return false;
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
      g_multi_last_send_error=GetLastError();
      Print("Initial pending failed, error=", g_multi_last_send_error);
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
        {
         if(!OrderDelete(high_ticket, clrRed))
            Print("Initial pending rollback failed, ticket=", high_ticket,
                  ", error=", GetLastError());
        }
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
       if(high_filled && low_filled)
         {
          int other_position_ticket = -1;
          int other_position_type = OP_BUY;
          double other_volume = 0.0;
          double other_entry = 0.0;
          double other_stop_loss = 0.0;
          double other_take_profit = 0.0;
          if(!FindPositionByTicket(other_ticket, other_position_ticket,
                                   other_position_type, other_volume, other_entry,
                                   other_stop_loss, other_take_profit))
             return true;
          if(!ClosePreviousGroupAfterReverseFill(position_ticket))
             return true;
         }
       g_active_first_direction = position_type == OP_BUY ? FIRST_BUY : FIRST_SELL;
      g_active_cycle_mode = InpCycleMode;
      g_cycle_index = 0;
      g_pending_index = -1;
      g_pending_ticket = -1;
      g_group_anchor_price = entry;
      g_group_last_entry = entry;
      g_group_linear_extreme = entry;
      g_group_first_lots = volume;
      g_group_total_lots = volume;
      g_grid_filled_levels = 0;
      g_grid_filled_mask = 0;
      ClearGridOrderTicketCache();
      g_grid_pending_level = 0;
      g_grid_pending_price = 0.0;
      g_favorable_grid_filled_levels = 0;
      g_favorable_grid_filled_mask = 0;
      g_favorable_grid_pending_level = 0;
      g_favorable_grid_pending_price = 0.0;
      g_grid_lots = g_previous_grid_lots > 0.0
                    ? VolumeNormalize(g_previous_grid_lots * InpGridLotMultiplier)
                    : volume;
      g_had_position = true;
      g_last_position_type = position_type;
      g_initial_high_ticket = -1;
      g_initial_low_ticket = -1;
      g_initial_high_price = 0.0;
      g_initial_low_price = 0.0;
      if(!SetGroupStops(position_type) || !StopsVerified(position_type))
        {
         Print("Initial fill protection is not verified; follow-up orders are paused.");
         SaveState();
         return true;
        }
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
   if(启用XAU净盈亏比 && !g_cost_wait_flat) return false;
   if(g_reversal_count >= 最大反手次数 || stop_loss <= 0.0 || current_volume <= 0.0)
      return false;

   int stop_loss_points = 0;
   int take_profit_points = 0;
   if(!GetActiveDistancePoints(stop_loss, take_profit, stop_loss_points, take_profit_points))
      return false;

   RefreshRates();
   ReversalLotPlan plan;
   if(!BuildReversalLotPlan(NextGroupLotsRaw(current_volume), plan)
      || plan.status != REVERSAL_LOT_SINGLE)
      return false;
   const double volume = VolumeNormalize(plan.first_lots);
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
   g_pending_index = (g_cycle_index + 1) % CycleLength(g_active_cycle_mode);
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

double FavorableGridLevelPrice(const int position_type, const int level)
  {
   if(InpGridCount <= 0 || g_group_stop_points <= 0 || g_group_anchor_price <= 0.0)
      return 0.0;
   const double distance = g_group_stop_points * Point * level / InpGridCount;
   if(position_type == OP_BUY)
      return PriceNormalize(g_group_anchor_price + distance);
   return PriceNormalize(g_group_anchor_price - distance);
  }

long GridLevelBit(const int level)
  {
   if(level <= 0 || level > 62)
      return 0;
   return ((long)1 << (level - 1));
  }

int GridFilledLevelCountForMask(const long mask)
  {
   int count = 0;
   for(int level = 1; level < InpGridCount; level++)
      if((mask & GridLevelBit(level)) != 0)
         count++;
   return count;
  }

int HighestFavorableGridLevel(const long mask)
  {
   for(int level = InpGridCount - 1; level >= 1; level--)
      if((mask & GridLevelBit(level)) != 0)
         return level;
   return 0;
  }

int GridFilledLevelCount()
  {
   return GridFilledLevelCountForMask(g_grid_filled_mask);
  }

int GridPendingLevelFromComment(const string comment)
  {
   const int favorable_marker = StringFind(comment, ".Grid.F.", 0);
   if(favorable_marker >= 0)
      return (int)StrToInteger(StringSubstr(comment, favorable_marker + 8));
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
   bool keep_favorable = false;
   for(int index = OrdersTotal() - 1; index >= 0; index--)
     {
      if(!OrderSelect(index, SELECT_BY_POS, MODE_TRADES)
         || !IsGridPendingAtLevel(expected_direction, expected_level,
                                  expected_price, expected_volume))
         continue;
      const int candidate = OrderTicket();
      if(keep_ticket <= 0 || candidate < keep_ticket)
        {
         keep_ticket = candidate;
         keep_favorable = StringFind(OrderComment(), ".Grid.F.", 0) >= 0;
        }
     }
   if(expected_level > 0 && expected_level < MAX_GRID_COUNT)
     {
      if(keep_favorable)
         g_favorable_grid_order_tickets[expected_level] = keep_ticket;
      else
         g_grid_order_tickets[expected_level] = keep_ticket;
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

bool FindFilledGridPosition(const int position_type, const int level,
                            const bool favorable, double &fill_price)
  {
   for(int index = OrdersTotal() - 1; index >= 0; index--)
     {
      if(!OrderSelect(index, SELECT_BY_POS, MODE_TRADES) || !IsOurMarketOrder()
         || OrderType() != position_type || !IsGridPendingComment()
         || GridPendingLevelFromComment(OrderComment()) != level
         || (StringFind(OrderComment(), ".Grid.F.", 0) >= 0) != favorable)
         continue;
      fill_price = OrderOpenPrice();
      return true;
     }
   return false;
  }

bool FindFilledGridOrder(const int position_type, const int level,
                         const double expected_price, const bool favorable,
                         double &fill_price)
  {
   if(level <= 0 || level >= MAX_GRID_COUNT)
      return false;
   if(FindFilledGridPosition(position_type, level, favorable, fill_price))
      return true;
   const int ticket = favorable ? g_favorable_grid_order_tickets[level]
                                : g_grid_order_tickets[level];
   if(ticket <= 0 || !OrderSelect(ticket, SELECT_BY_TICKET, MODE_HISTORY))
      return false;
   if(OrderSymbol() == Symbol() && OrderMagicNumber() == InpMagicNumber
      && (OrderType() == OP_BUY || OrderType() == OP_SELL)
      && IsGridPendingComment()
      && GridPendingLevelFromComment(OrderComment()) == level
      && PendingDirection(OrderType()) == position_type
      && MathAbs(OrderOpenPrice() - expected_price) <= Point * 10.0)
     {
      fill_price = OrderOpenPrice();
      return true;
     }
   return false;
  }

bool PlaceGridPending(const int position_type, const int level, const bool favorable)
  {
   if(启用XAU净盈亏比 && !g_cost_wait_flat) return false;
   if(InpGridCount < 2 || level <= 0 || level >= InpGridCount
      || g_grid_lots <= 0.0 || g_group_anchor_price <= 0.0)
      return false;

   const double entry = favorable ? FavorableGridLevelPrice(position_type, level)
                                  : GridLevelPrice(position_type, level);
   const double stop_loss = GroupStopPrice(position_type);
   const double take_profit = favorable ? GroupTakeProfitPrice(position_type)
                              : position_type == OP_BUY
                                ? PriceNormalize(entry + g_group_take_profit_points * Point)
                                : PriceNormalize(entry - g_group_take_profit_points * Point);
   const double volume = VolumeNormalize(g_grid_lots);
   const int pending_type = PendingTypeForDirection(position_type, entry);
   const string grid_comment = InpOrderComment + (favorable ? ".Grid.F." : ".Grid.")
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
    if(favorable)
      {
       g_favorable_grid_pending_level = level;
       g_favorable_grid_pending_price = entry;
       g_favorable_grid_order_tickets[level] = ticket;
      }
    else
      {
       g_grid_pending_level = level;
       g_grid_pending_price = entry;
       g_grid_order_tickets[level] = ticket;
      }
   SaveState();
   return true;
  }

bool PrepareGridPendingForCurrentStop(const int position_type, const double entry,
                                      const bool favorable, int &ticket)
  {
   if(ticket <= 0)
      return true;
   const double stop_loss = GroupStopPrice(position_type);
   const double tolerance = Point * 0.5;
   const bool adverse_level_invalid = !favorable
                                      && ((position_type == OP_BUY
                                           && entry <= stop_loss + tolerance)
                                          || (position_type == OP_SELL
                                              && entry >= stop_loss - tolerance));
   if(!OrderSelect(ticket, SELECT_BY_TICKET, MODE_TRADES))
     {
      ticket = -1;
      return true;
     }
   const double expected_take_profit = GroupTakeProfitPrice(position_type);
   const bool wrong_take_profit = favorable
                                  && MathAbs(OrderTakeProfit() - expected_take_profit) > tolerance;
   if(!adverse_level_invalid
      && (DynamicStopLossEnable != 1
          || MathAbs(OrderStopLoss() - stop_loss) <= tolerance)
      && !wrong_take_profit)
      return true;
   if(!OrderDelete(ticket, clrRed))
     {
      Print("Dynamic grid pending cleanup failed, ticket=", ticket,
            ", error=", GetLastError());
      return false;
     }
   ticket = -1;
   return true;
  }

bool HandleGridFill(const int position_type)
  {
   if(InpGridCount < 2 || g_group_anchor_price <= 0.0)
      return false;
   const double current_total_lots = TotalPositionLots(position_type);

   bool changed = false;
   double latest_entry = 0.0;
    for(int level = 1; level < InpGridCount; level++)
     {
      const long level_bit = GridLevelBit(level);
      if(level_bit == 0 || (g_grid_filled_mask & level_bit) != 0)
         continue;
      double fill_price = 0.0;
      if(FindFilledGridOrder(position_type, level, GridLevelPrice(position_type, level),
                             false, fill_price))
        {
         g_grid_filled_mask |= level_bit;
         latest_entry = fill_price;
         changed = true;
         }
      }
    if(FavorableGridEnable == 1)
      for(int level = 1; level < InpGridCount; level++)
        {
         const long level_bit = GridLevelBit(level);
         if(level_bit == 0 || (g_favorable_grid_filled_mask & level_bit) != 0)
            continue;
         double fill_price = 0.0;
         if(FindFilledGridOrder(position_type, level,
                                FavorableGridLevelPrice(position_type, level), true,
                                fill_price))
           {
            g_favorable_grid_filled_mask |= level_bit;
            changed = true;
           }
        }
   if(!changed)
      return false;

    g_grid_filled_levels = GridFilledLevelCount();
    g_grid_pending_level = 0;
    g_grid_pending_price = 0.0;
    g_favorable_grid_filled_levels = GridFilledLevelCountForMask(g_favorable_grid_filled_mask);
    g_favorable_grid_pending_level = 0;
    g_favorable_grid_pending_price = 0.0;
   g_group_total_lots = current_total_lots;
   if(latest_entry > 0.0)
      g_group_last_entry = latest_entry;
   SetGroupStops(position_type);
   SaveState();
   return true;
  }

double GridLotsForNewGroup(const double first_lots, const double calculated_grid_lots)
  {
   if(FirstOrderLotType == 2 && first_lots > 0.0
      && MathAbs(FirstOrderMult - InpGridLotMultiplier) < 0.00000001)
      return VolumeNormalize(first_lots);
   return calculated_grid_lots;
  }

void EnsureGridPending(const int position_type)
  {
   g_grid_lots = GridLotsForNewGroup(g_group_first_lots, g_grid_lots);
    if(InpGridCount < 2)
      {
      g_grid_pending_level = 0;
       g_grid_pending_price = 0.0;
       g_favorable_grid_pending_level = 0;
       g_favorable_grid_pending_price = 0.0;
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
       if(!PrepareGridPendingForCurrentStop(position_type, expected_price, false,
                                            grid_ticket))
          return;
       if(grid_ticket <= 0
          && ((position_type == OP_BUY
               && expected_price <= GroupStopPrice(position_type) + Point * 0.5)
              || (position_type == OP_SELL
                  && expected_price >= GroupStopPrice(position_type) - Point * 0.5)))
          continue;
       if(grid_ticket <= 0)
          PlaceGridPending(position_type, level, false);
      if(grid_ticket > 0 || g_grid_pending_level == level)
        {
         g_grid_pending_level = level;
         g_grid_pending_price = expected_price;
        }
      }
    g_favorable_grid_pending_level = 0;
    g_favorable_grid_pending_price = 0.0;
    if(FavorableGridEnable == 1)
      for(int level = 1; level < InpGridCount; level++)
        {
         if((g_favorable_grid_filled_mask & GridLevelBit(level)) != 0)
            continue;
         const double expected_price = FavorableGridLevelPrice(position_type, level);
         int grid_ticket = -1;
          if(!NormalizeGridPendingLevel(position_type, level, expected_price,
                                        expected_volume, grid_ticket))
             continue;
          if(!PrepareGridPendingForCurrentStop(position_type, expected_price, true,
                                               grid_ticket))
             return;
          if(grid_ticket <= 0)
             PlaceGridPending(position_type, level, true);
         if(grid_ticket > 0 || g_favorable_grid_pending_level == level)
           {
            g_favorable_grid_pending_level = level;
            g_favorable_grid_pending_price = expected_price;
           }
        }
    g_grid_filled_levels = GridFilledLevelCount();
    g_favorable_grid_filled_levels = GridFilledLevelCountForMask(g_favorable_grid_filled_mask);
   SaveState();
  }

void EnsureNextPending(const double stop_loss, const double take_profit,
                       const double fallback_volume)
  {
   if(g_reversal_count >= 最大反手次数)
      return;

   const int expected_direction = SequenceDirection(NextCycleIndex());
   ReversalLotPlan plan;
   if(!BuildReversalLotPlan(NextGroupLotsRaw(fallback_volume), plan)
      || plan.status != REVERSAL_LOT_SINGLE)
      return;
   const double expected_volume = VolumeNormalize(plan.first_lots);
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
   // A stop transition is a market-order transition.  Any reverse pending
   // order from the stopped group is stale now, including a stale ticket
   // whose history status can no longer be trusted.
   g_pending_ticket = -1;
   g_pending_index = -1;
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
   const double next_group_lots = NextGroupLotsAfterStopRaw(volume);
   ReversalLotPlan reversal_plan;
   if(!BuildReversalLotPlan(next_group_lots, reversal_plan))
      return false;
   if(reversal_plan.status == REVERSAL_LOT_RESTART_GROUP)
     {
      ResetOrderGroupAfterOversizedReversal();
      return false;
     }
   if(!OpenMarket(next_type, next_group_lots))
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
     g_group_first_lots = g_group_total_lots;
   g_grid_filled_levels = 0;
   g_grid_filled_mask = 0;
   ClearGridOrderTicketCache();
   g_grid_pending_level = 0;
   g_grid_pending_price = 0.0;
   g_favorable_grid_filled_levels = 0;
   g_favorable_grid_filled_mask = 0;
   g_favorable_grid_pending_level = 0;
   g_favorable_grid_pending_price = 0.0;
   g_grid_lots = VolumeNormalize(g_previous_grid_lots * InpGridLotMultiplier);
   if(!SetGroupStops(next_position_type) || !StopsVerified(next_position_type))
     {
      Print("Transition protection is not verified; follow-up orders are paused.");
      SaveState();
      return false;
     }
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
   const double expected_volume = NextGroupLotsAfterStopRaw(g_group_first_lots);
   ReversalLotPlan recovery_plan;
   if(!BuildReversalLotPlan(expected_volume, recovery_plan))
      return false;
   if(recovery_plan.status == REVERSAL_LOT_RESTART_GROUP)
     {
      ResetOrderGroupAfterOversizedReversal();
      return false;
     }
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
      if(position_type != expected_direction || total > expected_volume + tolerance)
        {
         Print("Transition recovery conflict, id=", g_transition_id,
               ", expected_type=", expected_direction,
               ", expected_volume=", expected_volume,
               ", actual_type=", position_type, ", actual_volume=", total);
         return false;
        }
      if(total + tolerance < expected_volume)
        {
         if(!OpenMarket(expected_direction, expected_volume))
            return false;
         if(!FindPosition(ticket, position_type, volume, entry, stop_loss, take_profit)
            || position_type != expected_direction
            || TotalPositionLots(position_type) + tolerance < expected_volume)
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
       g_group_first_lots = g_group_total_lots;
   g_grid_filled_levels = 0;
   g_grid_filled_mask = 0;
   ClearGridOrderTicketCache();
   g_grid_pending_level = 0;
   g_grid_pending_price = 0.0;
   g_favorable_grid_filled_levels = 0;
   g_favorable_grid_filled_mask = 0;
   g_favorable_grid_pending_level = 0;
   g_favorable_grid_pending_price = 0.0;
   g_grid_lots = VolumeNormalize(g_previous_grid_lots * InpGridLotMultiplier);
   if(!SetGroupStops(position_type) || !StopsVerified(position_type))
     {
      Print("Transition recovery protection is not verified; follow-up orders are paused.");
      SaveState();
      return false;
     }
   g_transition_phase = TRANSITION_COMPLETE;
   SaveState();
   return true;
  }

bool RecoverFlatGroupAfterBrokerStop()
  {
   if(!g_had_position || g_transition_phase != TRANSITION_NONE
      || g_group_first_lots <= 0.0 || g_group_stop_points <= 0
      || g_group_take_profit_points <= 0)
      return false;

   const int position_type = g_last_position_type;
   const double stop_loss = GroupStopPrice(position_type);
   const double take_profit = GroupTakeProfitPrice(position_type);
   if(PastLastTakeProfit() || !StopReached(position_type, stop_loss))
      return false;

   const double stopped_group_volume = g_group_total_lots > 0.0
                                      ? g_group_total_lots
                                      : g_group_first_lots;
   PrintFormat("Broker stop closed the group before EA processing; recovering the reverse market order. "
               "first_lots=%.2f, group_lots=%.2f, next_lots=%.2f",
               g_group_first_lots, stopped_group_volume,
               NextGroupLotsAfterStopRaw(stopped_group_volume));
   Transition(position_type, stopped_group_volume, stop_loss, take_profit);
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
          HandleGridFill(position_type);
       if(pending_filled)
         {
          if(!DeleteAllPending())
            {
             Print("Reverse fill detected, but old grid pending orders remain; retrying.");
             SaveState();
             return;
            }
          if(!ClosePreviousGroupAfterReverseFill(position_ticket))
            {
             Print("Reverse fill detected, but the previous order group is not fully closed; retrying.");
             SaveState();
             return;
            }
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
          g_group_first_lots = volume;
         g_grid_filled_levels = 0;
         g_grid_filled_mask = 0;
         ClearGridOrderTicketCache();
         g_grid_pending_level = 0;
         g_grid_pending_price = 0.0;
         g_favorable_grid_filled_levels = 0;
         g_favorable_grid_filled_mask = 0;
         g_favorable_grid_pending_level = 0;
         g_favorable_grid_pending_price = 0.0;
         g_grid_lots = VolumeNormalize(g_previous_grid_lots * InpGridLotMultiplier);
         g_transition_phase = TRANSITION_COMPLETE;
         g_transition_id = (long)TimeCurrent() * 1000 + g_reversal_count;
        }
       volume = TotalPositionLots(position_type);
       if(g_group_first_lots <= 0.0)
          g_group_first_lots = volume;
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

      if(pending_filled && (!SetGroupStops(position_type)
                            || !StopsVerified(position_type)))
        {
         Print("Reverse fill protection is not verified; follow-up orders are paused.");
         SaveState();
         return;
        }

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
         if(!SetGroupStops(position_type) || !StopsVerified(position_type))
           {
            Print("Position protection is not verified; follow-up orders are paused.");
            SaveState();
            return;
           }
         EnsureNextPending(GroupStopPrice(position_type), GroupTakeProfitPrice(position_type),
                           volume);
         EnsureGridPending(position_type);
         SaveState();
          return;
         }

      if(!StopsVerified(position_type))
        {
         if(!SetGroupStops(position_type) || !StopsVerified(position_type))
           {
            Print("Position protection is not verified; follow-up orders are paused.");
            SaveState();
            return;
           }
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
         if(latest_pending_status == REVERSE_PENDING_FILLED && pending_position_found)
            return;
         if(latest_pending_status == REVERSE_PENDING_ACTIVE
            || latest_pending_status == REVERSE_PENDING_UNKNOWN
            || (latest_pending_status == REVERSE_PENDING_FILLED
                && !pending_position_found))
            Print("Stop reached; canceling the old reverse pending order and forcing a market reversal.");
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

   if(RecoverFlatGroupAfterBrokerStop())
      return;

   const int flat_pending_status = GetReversePendingStatus();
   if(flat_pending_status == REVERSE_PENDING_FILLED)
     {
      Print("Reverse pending order is filled; waiting for the resulting market position before starting a new cycle.");
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
                                   ? (FirstOrderLotType == 2
                                      ? NextGroupLotsAfterStop(g_group_first_lots)
                                      : VolumeNormalize(g_cumulative_loss_lots))
                                   : VolumeNormalize(InpInitialLots);
      if(篮子数量==2)
        {
         StartInitialMultiOco(previous_high,previous_low,range_points,initial_lots);
         return;
        }
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
   else if(InpDistanceMode == DISTANCE_LONG_CANDLE)
     {
      if(!GetLongCandleDirection(first_direction)
         || !GetDistancePoints(initial_stop_points, initial_take_profit_points))
         return;
      g_active_first_direction = first_direction == OP_BUY ? FIRST_BUY : FIRST_SELL;
      g_active_cycle_mode = InpCycleMode;
     }
   else
     {
      if(首单方向确定方式 == FIRST_DIRECTION_BOLLINGER
         && !GetBollingerFirstDirection(first_direction))
         return;
      if(首单方向确定方式 == FIRST_DIRECTION_PRESET)
         first_direction = InpFirstDirection == FIRST_SELL ? OP_SELL : OP_BUY;
      g_active_first_direction = first_direction == OP_BUY ? FIRST_BUY : FIRST_SELL;
      g_active_cycle_mode = InpCycleMode;
      if(!GetDistancePoints(initial_stop_points, initial_take_profit_points))
         return;
     }
   g_had_position = false;
   g_cycle_index = 0;
   g_pending_index = -1;
   g_group_stop_points = initial_stop_points;
   g_group_take_profit_points = initial_take_profit_points;
    const double initial_lots = g_cumulative_loss_lots > 0.0
                                ? (FirstOrderLotType == 2
                                   ? NextGroupLotsAfterStop(g_group_first_lots)
                                   : VolumeNormalize(g_cumulative_loss_lots))
                                : VolumeNormalize(InpInitialLots);
   if(篮子数量 == 2)
     {
      StartResolvedMultiPair(first_direction, initial_stop_points,
                             initial_take_profit_points, initial_lots);
      return;
     }
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
          g_group_first_lots = volume;
          g_group_total_lots = TotalPositionLots(position_type);
         g_grid_filled_levels = 0;
         g_grid_filled_mask = 0;
         ClearGridOrderTicketCache();
         g_grid_pending_level = 0;
         g_grid_pending_price = 0.0;
         g_favorable_grid_filled_levels = 0;
         g_favorable_grid_filled_mask = 0;
         g_favorable_grid_pending_level = 0;
         g_favorable_grid_pending_price = 0.0;
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
   bool     dirty;
   int      first_direction;
   int      cycle_mode;
   int      cycle_index;
   int      pending_index;
   int      reversal_count;
   int      pending_ticket;
   int      pair_parent_id;
   int      pair_peer_id;
   bool     launch_confirmed;
   bool     launch_attempted;
   bool     launch_failed;
   int      launch_error;
   datetime launch_retry_after;
   datetime launch_log_time;
   int      launch_event_id;
   int      launch_attempt_count;
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
   double   first_lots;
   double   previous_grid_lots;
   double   grid_lots;
   double   total_lots;
   double   transition_target_lots;
   double   anchor_price;
   double   last_entry;
   double   linear_extreme;
   int      grid_filled_levels;
   long     grid_filled_mask;
   int      grid_pending_level;
   double   grid_pending_price;
   int      favorable_grid_pending_ticket;
   int      favorable_grid_filled_levels;
   long     favorable_grid_filled_mask;
   int      favorable_grid_pending_level;
    double   favorable_grid_pending_price;
    bool     cost_mode;
    bool     cost_frozen;
    datetime cost_start;
    double   cost_target;
    double   cost_tp;
    double   cost_high;
    double   cost_low;
    datetime cost_bar;
    int      cost_good_quotes;
    int      cost_last_ticket;
    int      cost_last_type;
    double   cost_last_stop;
    int      cost_handled_ticket;
  };

MultiGroupState g_multi_groups[];
datetime g_multi_last_trigger_bar = 0;
int g_multi_next_id = 1;
int g_multi_last_send_error = 0;
int g_multi_grid_order_tickets[];
int g_multi_favorable_grid_order_tickets[];

int MultiGridTicketCacheIndex(const int group_id, const int level)
  {
   if(group_id <= 0 || level <= 0 || level >= MAX_GRID_COUNT)
      return -1;
   return group_id * MAX_GRID_COUNT + level;
  }

void MultiEnsureGridTicketCache(const int group_id)
  {
   const int required = (group_id + 1) * MAX_GRID_COUNT;
   if(ArraySize(g_multi_grid_order_tickets) < required)
     {
      const int old_size = ArraySize(g_multi_grid_order_tickets);
      ArrayResize(g_multi_grid_order_tickets, required);
      for(int index = old_size; index < required; index++)
         g_multi_grid_order_tickets[index] = -1;
     }
   if(ArraySize(g_multi_favorable_grid_order_tickets) < required)
     {
      const int old_size = ArraySize(g_multi_favorable_grid_order_tickets);
      ArrayResize(g_multi_favorable_grid_order_tickets, required);
      for(int index = old_size; index < required; index++)
         g_multi_favorable_grid_order_tickets[index] = -1;
     }
  }

void MultiRememberGridOrderTicket(const int group_id, const int level,
                                  const bool favorable, const int ticket)
  {
   const int cache_index = MultiGridTicketCacheIndex(group_id, level);
   if(cache_index < 0)
      return;
   MultiEnsureGridTicketCache(group_id);
   if(favorable)
      g_multi_favorable_grid_order_tickets[cache_index] = ticket;
   else
      g_multi_grid_order_tickets[cache_index] = ticket;
  }

int MultiGridOrderTicket(const int group_id, const int level,
                         const bool favorable)
  {
   const int cache_index = MultiGridTicketCacheIndex(group_id, level);
   if(cache_index < 0)
      return -1;
   MultiEnsureGridTicketCache(group_id);
   return favorable ? g_multi_favorable_grid_order_tickets[cache_index]
                    : g_multi_grid_order_tickets[cache_index];
  }

string MultiGroupTag(const int group_id)
  {
   return ".G" + IntegerToString(group_id);
  }

string MultiGroupComment(const int group_id, const bool grid)
  {
   return MultiGroupTag(group_id) + InpOrderComment + (grid ? ".Grid" : "");
  }

string MultiInitialPendingComment(const int group_id, const bool high)
  {
   return MultiGroupTag(group_id) + InpOrderComment
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
   GlobalVariableDel(prefix + ".pairparent");
   GlobalVariableDel(prefix + ".pairpeer");
   GlobalVariableDel(prefix + ".launchconfirmed");
   GlobalVariableDel(prefix + ".launchattempted");
   GlobalVariableDel(prefix + ".launchfailed");
   GlobalVariableDel(prefix + ".launcherror");
   GlobalVariableDel(prefix + ".launchretry");
   GlobalVariableDel(prefix + ".launchlogtime");
   GlobalVariableDel(prefix + ".launchevent");
   GlobalVariableDel(prefix + ".launchcount");
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
   GlobalVariableDel(prefix + ".firstlots");
   GlobalVariableDel(prefix + ".prevgridlots");
   GlobalVariableDel(prefix + ".gridlots");
   GlobalVariableDel(prefix + ".totallots");
   GlobalVariableDel(prefix + ".transitiontarget");
   GlobalVariableDel(prefix + ".anchor");
   GlobalVariableDel(prefix + ".lastentry");
   GlobalVariableDel(prefix + ".linearextreme");
   GlobalVariableDel(prefix + ".gridlevel");
   DeleteGridMask(prefix);
   GlobalVariableDel(prefix + ".gridpendinglevel");
   GlobalVariableDel(prefix + ".gridpendingprice");
   GlobalVariableDel(prefix + ".favorablegridticket");
   GlobalVariableDel(prefix + ".favorablegridlevel");
   DeleteGridMask(prefix + ".favorable");
   GlobalVariableDel(prefix + ".favorablegridpendinglevel");
    GlobalVariableDel(prefix + ".favorablegridpendingprice");
    GlobalVariableDel(prefix + ".cost.mode");
    GlobalVariableDel(prefix + ".cost.frozen");
    GlobalVariableDel(prefix + ".cost.start");
    GlobalVariableDel(prefix + ".cost.target");
    GlobalVariableDel(prefix + ".cost.tp");
    GlobalVariableDel(prefix + ".cost.high");
    GlobalVariableDel(prefix + ".cost.low");
    GlobalVariableDel(prefix + ".cost.bar");
    GlobalVariableDel(prefix + ".cost.lastticket");
    GlobalVariableDel(prefix + ".cost.lasttype");
    GlobalVariableDel(prefix + ".cost.laststop");
    GlobalVariableDel(prefix + ".cost.handled");
  }

bool MultiCommentMatches(const string comment, const int group_id)
  {
    const string tag=MultiGroupTag(group_id);
    const int at=StringFind(comment,tag);
    if(at<0) return false;
    const int after=at+StringLen(tag);
    return after>=StringLen(comment) || StringSubstr(comment,after,1)==".";
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
   ArrayResize(g_multi_grid_order_tickets, 0);
   ArrayResize(g_multi_favorable_grid_order_tickets, 0);
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
   group.dirty = true;
   group.first_direction = FIRST_BUY;
   group.cycle_mode = CYCLE_MODE_1;
   group.cycle_index = 0;
   group.pending_index = -1;
   group.reversal_count = 0;
   group.pending_ticket = -1;
   group.pair_parent_id = 0;
   group.pair_peer_id = 0;
   group.launch_confirmed = false;
   group.launch_attempted = false;
    group.launch_failed = false;
    group.launch_error = 0;
    group.launch_retry_after = 0;
    group.launch_log_time = 0;
    group.launch_event_id = group_id;
    group.launch_attempt_count = 0;
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
   group.first_lots = 0.0;
   group.previous_grid_lots = 0.0;
   group.grid_lots = 0.0;
   group.total_lots = 0.0;
   group.transition_target_lots = 0.0;
   group.anchor_price = 0.0;
   group.last_entry = 0.0;
   group.linear_extreme = 0.0;
   group.grid_filled_levels = 0;
   group.grid_filled_mask = 0;
   group.grid_pending_level = 0;
   group.grid_pending_price = 0.0;
   group.favorable_grid_pending_ticket = -1;
   group.favorable_grid_filled_levels = 0;
   group.favorable_grid_filled_mask = 0;
   group.favorable_grid_pending_level = 0;
    group.favorable_grid_pending_price = 0.0;
    group.cost_mode = false;
    group.cost_frozen = false;
    group.cost_start = 0;
    group.cost_target = 0.0;
    group.cost_tp = 0.0;
    group.cost_high = 0.0;
    group.cost_low = 0.0;
    group.cost_bar = 0;
    group.cost_good_quotes = 0;
    group.cost_last_ticket = -1;
    group.cost_last_type = OP_BUY;
    group.cost_last_stop = 0.0;
    group.cost_handled_ticket = -1;
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
   bool keep_favorable = false;
   for(int index = OrdersTotal() - 1; index >= 0; index--)
     {
      if(!OrderSelect(index, SELECT_BY_POS, MODE_TRADES)
         || !MultiIsGridPendingAtLevel(group, expected_direction, expected_level,
                                       expected_price, expected_volume))
         continue;
      const int candidate = OrderTicket();
      if(keep_ticket <= 0 || candidate < keep_ticket)
        {
         keep_ticket = candidate;
         keep_favorable = StringFind(OrderComment(), ".Grid.F.", 0) >= 0;
        }
     }
   MultiRememberGridOrderTicket(group.id, expected_level, keep_favorable, keep_ticket);
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

bool MultiFindFilledGridPosition(const MultiGroupState &group, const int position_type,
                                 const int level, const bool favorable,
                                 double &fill_price)
  {
   for(int index = OrdersTotal() - 1; index >= 0; index--)
     {
      if(!OrderSelect(index, SELECT_BY_POS, MODE_TRADES) || !IsOurMarketOrder()
         || OrderType() != position_type
         || !MultiCommentMatches(OrderComment(), group.id)
         || !MultiIsGridSelectedOrder()
         || GridPendingLevelFromComment(OrderComment()) != level
         || (StringFind(OrderComment(), ".Grid.F.", 0) >= 0) != favorable)
         continue;
      fill_price = OrderOpenPrice();
      return true;
     }
   return false;
  }

bool MultiFindFilledGridOrder(const MultiGroupState &group, const int position_type,
                              const int level, const double expected_price,
                              const bool favorable,
                              double &fill_price)
  {
   if(MultiFindFilledGridPosition(group, position_type, level, favorable, fill_price))
      return true;
   const int ticket = MultiGridOrderTicket(group.id, level, favorable);
   if(ticket <= 0 || !OrderSelect(ticket, SELECT_BY_TICKET, MODE_HISTORY))
      return false;
   if(OrderSymbol() == Symbol() && OrderMagicNumber() == InpMagicNumber
      && (OrderType() == OP_BUY || OrderType() == OP_SELL)
      && MultiCommentMatches(OrderComment(), group.id)
      && MultiIsGridSelectedOrder()
      && GridPendingLevelFromComment(OrderComment()) == level
      && PendingDirection(OrderType()) == position_type
      && MathAbs(OrderOpenPrice() - expected_price) <= Point * 10.0)
     {
      fill_price = OrderOpenPrice();
      return true;
     }
   return false;
  }

int MultiGridFilledLevelCount(const MultiGroupState &group)
  {
   return MultiGridFilledLevelCountForMask(group.grid_filled_mask);
  }

int MultiGridFilledLevelCountForMask(const long mask)
  {
   int count = 0;
   for(int level = 1; level < 网格数量; level++)
      if((mask & GridLevelBit(level)) != 0)
         count++;
   return count;
  }

bool MultiStateChanged(const MultiGroupState &before,
                       const MultiGroupState &after)
  {
   return before.active != after.active
          || before.first_direction != after.first_direction
          || before.cycle_mode != after.cycle_mode
          || before.cycle_index != after.cycle_index
          || before.pending_index != after.pending_index
          || before.reversal_count != after.reversal_count
          || before.pending_ticket != after.pending_ticket
          || before.pair_parent_id != after.pair_parent_id
          || before.pair_peer_id != after.pair_peer_id
          || before.launch_confirmed != after.launch_confirmed
          || before.launch_attempted != after.launch_attempted
          || before.launch_failed != after.launch_failed
          || before.launch_error != after.launch_error
          || before.launch_retry_after != after.launch_retry_after
          || before.launch_log_time != after.launch_log_time
          || before.launch_event_id != after.launch_event_id
          || before.launch_attempt_count != after.launch_attempt_count
          || before.initial_high_ticket != after.initial_high_ticket
          || before.initial_low_ticket != after.initial_low_ticket
          || before.initial_high_price != after.initial_high_price
          || before.initial_low_price != after.initial_low_price
          || before.initial_high_direction != after.initial_high_direction
          || before.initial_low_direction != after.initial_low_direction
          || before.grid_pending_ticket != after.grid_pending_ticket
          || before.stop_points != after.stop_points
          || before.take_profit_points != after.take_profit_points
          || before.cumulative_loss_lots != after.cumulative_loss_lots
          || before.first_lots != after.first_lots
          || before.previous_grid_lots != after.previous_grid_lots
          || before.grid_lots != after.grid_lots
          || before.total_lots != after.total_lots
          || before.transition_target_lots != after.transition_target_lots
          || before.anchor_price != after.anchor_price
          || before.last_entry != after.last_entry
          || before.linear_extreme != after.linear_extreme
          || before.grid_filled_levels != after.grid_filled_levels
          || before.grid_filled_mask != after.grid_filled_mask
          || before.grid_pending_level != after.grid_pending_level
          || before.grid_pending_price != after.grid_pending_price
          || before.favorable_grid_pending_ticket != after.favorable_grid_pending_ticket
          || before.favorable_grid_filled_levels != after.favorable_grid_filled_levels
          || before.favorable_grid_filled_mask != after.favorable_grid_filled_mask
          || before.favorable_grid_pending_level != after.favorable_grid_pending_level
           || before.favorable_grid_pending_price != after.favorable_grid_pending_price
           || before.cost_mode != after.cost_mode
           || before.cost_frozen != after.cost_frozen
           || before.cost_start != after.cost_start
           || before.cost_target != after.cost_target
           || before.cost_tp != after.cost_tp
           || before.cost_high != after.cost_high
           || before.cost_low != after.cost_low
           || before.cost_bar != after.cost_bar
           || before.cost_last_ticket != after.cost_last_ticket
           || before.cost_last_stop != after.cost_last_stop
           || before.cost_handled_ticket != after.cost_handled_ticket;
  }

void MultiSaveGroup(MultiGroupState &group)
  {
   if(!group.dirty)
      return;
   const string prefix = MultiStatePrefix(group.id);
   GlobalVariableSet(prefix + ".active", group.active ? 1.0 : 0.0);
   GlobalVariableSet(prefix + ".first", group.first_direction);
   GlobalVariableSet(prefix + ".mode", group.cycle_mode);
   GlobalVariableSet(prefix + ".index", group.cycle_index);
   GlobalVariableSet(prefix + ".pendingindex", group.pending_index);
   GlobalVariableSet(prefix + ".reversals", group.reversal_count);
   GlobalVariableSet(prefix + ".pendingticket", group.pending_ticket);
   GlobalVariableSet(prefix + ".pairparent", group.pair_parent_id);
   GlobalVariableSet(prefix + ".pairpeer", group.pair_peer_id);
   GlobalVariableSet(prefix + ".launchconfirmed", group.launch_confirmed ? 1.0 : 0.0);
   GlobalVariableSet(prefix + ".launchattempted", group.launch_attempted ? 1.0 : 0.0);
    GlobalVariableSet(prefix + ".launchfailed", group.launch_failed ? 1.0 : 0.0);
    GlobalVariableSet(prefix + ".launcherror", group.launch_error);
    GlobalVariableSet(prefix + ".launchretry", (double)group.launch_retry_after);
    GlobalVariableSet(prefix + ".launchlogtime", (double)group.launch_log_time);
    GlobalVariableSet(prefix + ".launchevent", group.launch_event_id);
    GlobalVariableSet(prefix + ".launchcount", group.launch_attempt_count);
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
   GlobalVariableSet(prefix + ".firstlots", group.first_lots);
   GlobalVariableSet(prefix + ".prevgridlots", group.previous_grid_lots);
   GlobalVariableSet(prefix + ".gridlots", group.grid_lots);
   GlobalVariableSet(prefix + ".totallots", group.total_lots);
   GlobalVariableSet(prefix + ".transitiontarget", group.transition_target_lots);
   GlobalVariableSet(prefix + ".anchor", group.anchor_price);
   GlobalVariableSet(prefix + ".lastentry", group.last_entry);
   GlobalVariableSet(prefix + ".linearextreme", group.linear_extreme);
   GlobalVariableSet(prefix + ".gridlevel", group.grid_filled_levels);
   SaveGridMask(prefix, group.grid_filled_mask);
   GlobalVariableSet(prefix + ".gridpendinglevel", group.grid_pending_level);
   GlobalVariableSet(prefix + ".gridpendingprice", group.grid_pending_price);
   GlobalVariableSet(prefix + ".favorablegridticket", group.favorable_grid_pending_ticket);
   GlobalVariableSet(prefix + ".favorablegridlevel", group.favorable_grid_filled_levels);
   SaveGridMask(prefix + ".favorable", group.favorable_grid_filled_mask);
   GlobalVariableSet(prefix + ".favorablegridpendinglevel", group.favorable_grid_pending_level);
    GlobalVariableSet(prefix + ".favorablegridpendingprice", group.favorable_grid_pending_price);
    GlobalVariableSet(prefix + ".cost.mode",group.cost_mode ? 1.0 : 0.0);
    GlobalVariableSet(prefix + ".cost.frozen",group.cost_frozen ? 1.0 : 0.0);
    GlobalVariableSet(prefix + ".cost.start",(double)group.cost_start);
    GlobalVariableSet(prefix + ".cost.target",group.cost_target);
    GlobalVariableSet(prefix + ".cost.tp",group.cost_tp);
    GlobalVariableSet(prefix + ".cost.high",group.cost_high);
    GlobalVariableSet(prefix + ".cost.low",group.cost_low);
    GlobalVariableSet(prefix + ".cost.bar",(double)group.cost_bar);
    GlobalVariableSet(prefix + ".cost.lastticket",group.cost_last_ticket);
    GlobalVariableSet(prefix + ".cost.lasttype",group.cost_last_type);
    GlobalVariableSet(prefix + ".cost.laststop",group.cost_last_stop);
    GlobalVariableSet(prefix + ".cost.handled",group.cost_handled_ticket);
   GlobalVariableSet(StatePrefix() + ".multi.nextid", g_multi_next_id);
   group.dirty = false;
  }

void MultiEnsureRecoveredOpposite(const int source_id)
  {
   int source_index=-1;
   for(int i=0;i<ArraySize(g_multi_groups);i++)
      if(g_multi_groups[i].id==source_id) { source_index=i; break; }
   if(source_index<0) return;
   const int opposite_id=g_multi_groups[source_index].initial_low_direction;
   if(opposite_id<=source_id) return;
   for(int i=0;i<ArraySize(g_multi_groups);i++)
      if(g_multi_groups[i].id==opposite_id)
        {
         g_multi_groups[source_index].initial_low_direction=-1;
         g_multi_groups[source_index].dirty=true;
         MultiSaveGroup(g_multi_groups[source_index]);
         return;
        }
   MultiGroupState opposite;
   MultiResetState(opposite,opposite_id);
   opposite.first_direction=g_multi_groups[source_index].first_direction==FIRST_BUY
                             ? FIRST_SELL : FIRST_BUY;
   opposite.pair_parent_id=source_id;
   opposite.cycle_mode=g_multi_groups[source_index].cycle_mode;
   opposite.stop_points=g_multi_groups[source_index].stop_points;
   opposite.take_profit_points=g_multi_groups[source_index].take_profit_points;
   opposite.transition_target_lots=VolumeNormalize(g_multi_groups[source_index].first_lots);
   if(opposite.transition_target_lots<=0.0)
      opposite.transition_target_lots=VolumeNormalize(首单手数);
   const int new_index=ArraySize(g_multi_groups);
   if(ArrayResize(g_multi_groups,new_index+1)!=new_index+1) return;
   g_multi_groups[new_index]=opposite;
   MultiSaveGroup(g_multi_groups[new_index]);
   for(int i=0;i<ArraySize(g_multi_groups);i++)
      if(g_multi_groups[i].id==source_id)
        {
         g_multi_groups[i].initial_low_direction=-1;
         g_multi_groups[i].dirty=true;
         MultiSaveGroup(g_multi_groups[i]);
         break;
        }
  }

bool MultiLaunchErrorIsAmbiguous(const int error)
  {
   return error==ERR_NO_RESULT || error==ERR_NO_CONNECTION
          || error==ERR_TRADE_TIMEOUT;
  }

bool MultiLaunchErrorIsRetryable(const int error)
  {
   return error==ERR_SERVER_BUSY || error==ERR_TOO_FREQUENT_REQUESTS
          || error==ERR_TRADE_CONTEXT_BUSY || error==ERR_BROKER_BUSY
          || error==ERR_OFF_QUOTES || error==ERR_REQUOTE
          || error==ERR_PRICE_CHANGED || error==ERR_INVALID_PRICE
          || error==ERR_MARKET_CLOSED || error==ERR_TRADE_MODIFY_DENIED;
  }

void MultiRecordLaunchFailure(MultiGroupState &group,const int error)
  {
   group.launch_error=error;
   group.launch_attempt_count++;
   if(MultiLaunchErrorIsAmbiguous(error))
     {
      group.launch_attempted=true;
      group.launch_retry_after=0;
     }
   else
     {
      group.launch_attempted=false;
      if(MultiLaunchErrorIsRetryable(error))
        {
         int delay=5*(int)MathMin(12,MathMax(1,group.launch_attempt_count));
         group.launch_retry_after=TimeCurrent()+delay;
        }
      else
        {
         group.launch_failed=true;
         group.launch_retry_after=0;
        }
     }
   const datetime now=TimeCurrent();
   if(group.launch_log_time==0 || now-group.launch_log_time>=60)
     {
      const int event_id=group.launch_event_id>0 ? group.launch_event_id : group.id;
      Print("Multi pair launch ",group.launch_failed ? "permanent failure" :
            (MultiLaunchErrorIsAmbiguous(error) ? "ambiguous" : "retryable"),
            ", group=",group.id,", event=",event_id,", error=",error,
            ", attempts=",group.launch_attempt_count);
      group.launch_log_time=now;
     }
   group.dirty=true;
   MultiSaveGroup(group);
  }

void MultiCreateOppositeAfterInitialFill(const int source_id)
  {
   int source_index=-1;
   for(int i=0;i<ArraySize(g_multi_groups);i++)
      if(g_multi_groups[i].id==source_id) { source_index=i; break; }
   if(source_index<0) return;
   if(g_multi_groups[source_index].initial_low_direction<=source_id)
     {
      const int opposite_id=g_multi_next_id++;
      g_multi_groups[source_index].initial_low_direction=opposite_id;
      g_multi_groups[source_index].dirty=true;
      GlobalVariableSet(StatePrefix()+".multi.nextid",g_multi_next_id);
      MultiSaveGroup(g_multi_groups[source_index]);
     }
   MultiEnsureRecoveredOpposite(source_id);
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
      if(GlobalVariableCheck(prefix + ".pairparent"))
         state.pair_parent_id=(int)MathRound(GlobalVariableGet(prefix + ".pairparent"));
      if(GlobalVariableCheck(prefix + ".pairpeer"))
         state.pair_peer_id=(int)MathRound(GlobalVariableGet(prefix + ".pairpeer"));
      if(GlobalVariableCheck(prefix + ".launchconfirmed"))
         state.launch_confirmed=GlobalVariableGet(prefix + ".launchconfirmed")>0.5;
      if(GlobalVariableCheck(prefix + ".launchattempted"))
         state.launch_attempted=GlobalVariableGet(prefix + ".launchattempted")>0.5;
      if(GlobalVariableCheck(prefix + ".launchfailed"))
         state.launch_failed=GlobalVariableGet(prefix + ".launchfailed")>0.5;
      if(GlobalVariableCheck(prefix + ".launcherror"))
         state.launch_error=(int)MathRound(GlobalVariableGet(prefix + ".launcherror"));
      if(GlobalVariableCheck(prefix + ".launchretry"))
         state.launch_retry_after=(datetime)MathRound(GlobalVariableGet(prefix + ".launchretry"));
      if(GlobalVariableCheck(prefix + ".launchlogtime"))
         state.launch_log_time=(datetime)MathRound(GlobalVariableGet(prefix + ".launchlogtime"));
      if(GlobalVariableCheck(prefix + ".launchevent"))
         state.launch_event_id=(int)MathRound(GlobalVariableGet(prefix + ".launchevent"));
      if(GlobalVariableCheck(prefix + ".launchcount"))
         state.launch_attempt_count=(int)MathRound(GlobalVariableGet(prefix + ".launchcount"));
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
      if(GlobalVariableCheck(prefix + ".firstlots"))
         state.first_lots = GlobalVariableGet(prefix + ".firstlots");
      state.previous_grid_lots = GlobalVariableGet(prefix + ".prevgridlots");
      state.grid_lots = GlobalVariableGet(prefix + ".gridlots");
      state.total_lots = GlobalVariableGet(prefix + ".totallots");
      if(GlobalVariableCheck(prefix + ".transitiontarget"))
         state.transition_target_lots = GlobalVariableGet(prefix + ".transitiontarget");
      if(state.first_lots <= 0.0 && state.total_lots > 0.0)
         state.first_lots = state.total_lots;
      state.anchor_price = GlobalVariableGet(prefix + ".anchor");
      state.last_entry = GlobalVariableGet(prefix + ".lastentry");
      state.linear_extreme = GlobalVariableGet(prefix + ".linearextreme");
      state.grid_filled_levels = (int)MathRound(GlobalVariableGet(prefix + ".gridlevel"));
      if(!LoadGridMask(prefix, state.grid_filled_mask)
         && GlobalVariableCheck(prefix + ".gridmask"))
         state.grid_filled_mask = (long)MathRound(GlobalVariableGet(prefix + ".gridmask"));
      else if(state.grid_filled_levels > 0)
         state.grid_filled_mask = ((long)1 << state.grid_filled_levels) - 1;
      state.grid_pending_level = (int)MathRound(GlobalVariableGet(prefix + ".gridpendinglevel"));
      state.grid_pending_price = GlobalVariableGet(prefix + ".gridpendingprice");
      if(GlobalVariableCheck(prefix + ".favorablegridticket"))
         state.favorable_grid_pending_ticket = (int)MathRound(GlobalVariableGet(prefix + ".favorablegridticket"));
      if(GlobalVariableCheck(prefix + ".favorablegridlevel"))
         state.favorable_grid_filled_levels = (int)MathRound(GlobalVariableGet(prefix + ".favorablegridlevel"));
      if(!LoadGridMask(prefix + ".favorable", state.favorable_grid_filled_mask)
         && GlobalVariableCheck(prefix + ".favorable.gridmask"))
         state.favorable_grid_filled_mask = (long)MathRound(GlobalVariableGet(prefix + ".favorable.gridmask"));
      else if(state.favorable_grid_filled_levels > 0)
         state.favorable_grid_filled_mask = ((long)1 << state.favorable_grid_filled_levels) - 1;
      if(GlobalVariableCheck(prefix + ".favorablegridpendinglevel"))
         state.favorable_grid_pending_level = (int)MathRound(GlobalVariableGet(prefix + ".favorablegridpendinglevel"));
       if(GlobalVariableCheck(prefix + ".favorablegridpendingprice"))
          state.favorable_grid_pending_price = GlobalVariableGet(prefix + ".favorablegridpendingprice");
       if(GlobalVariableCheck(prefix + ".cost.mode"))
          state.cost_mode=GlobalVariableGet(prefix + ".cost.mode")>0.5;
       if(GlobalVariableCheck(prefix + ".cost.frozen"))
          state.cost_frozen=GlobalVariableGet(prefix + ".cost.frozen")>0.5;
       if(GlobalVariableCheck(prefix + ".cost.start"))
          state.cost_start=(datetime)GlobalVariableGet(prefix + ".cost.start");
       if(GlobalVariableCheck(prefix + ".cost.target"))
          state.cost_target=GlobalVariableGet(prefix + ".cost.target");
       if(GlobalVariableCheck(prefix + ".cost.tp"))
          state.cost_tp=GlobalVariableGet(prefix + ".cost.tp");
       if(GlobalVariableCheck(prefix + ".cost.high"))
          state.cost_high=GlobalVariableGet(prefix + ".cost.high");
       if(GlobalVariableCheck(prefix + ".cost.low"))
          state.cost_low=GlobalVariableGet(prefix + ".cost.low");
       if(GlobalVariableCheck(prefix + ".cost.bar"))
          state.cost_bar=(datetime)GlobalVariableGet(prefix + ".cost.bar");
       if(GlobalVariableCheck(prefix + ".cost.lastticket"))
          state.cost_last_ticket=(int)GlobalVariableGet(prefix + ".cost.lastticket");
       if(GlobalVariableCheck(prefix + ".cost.lasttype"))
          state.cost_last_type=(int)GlobalVariableGet(prefix + ".cost.lasttype");
       if(GlobalVariableCheck(prefix + ".cost.laststop"))
          state.cost_last_stop=GlobalVariableGet(prefix + ".cost.laststop");
       if(GlobalVariableCheck(prefix + ".cost.handled"))
          state.cost_handled_ticket=(int)GlobalVariableGet(prefix + ".cost.handled");
       if(启用XAU净盈亏比 && (!state.cost_mode || state.cost_target<=0.0))
         {state.cost_frozen=true;Print("COST_LEDGER_INCOMPLETE: multi group=",id);}
      state.dirty = false;
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

bool MultiClosePositionsExcept(const int group_id, const int keep_ticket)
  {
   if(keep_ticket <= 0 || !OrderSelect(keep_ticket, SELECT_BY_TICKET, MODE_TRADES)
      || !MultiCommentMatches(OrderComment(), group_id)
      || !IsOurMarketOrder())
      return false;
   bool closed = true;
   RefreshRates();
   for(int index = OrdersTotal() - 1; index >= 0; index--)
     {
      if(!OrderSelect(index, SELECT_BY_POS, MODE_TRADES)
         || OrderTicket() == keep_ticket
         || !IsOurMarketOrder()
         || !MultiCommentMatches(OrderComment(), group_id))
         continue;
      const int ticket = OrderTicket();
      const int type = OrderType();
      const double close_price = type == OP_BUY ? Bid : Ask;
      if(!OrderClose(ticket, OrderLots(), close_price, 0, clrRed))
        {
         Print("Previous multi-group close failed after reverse fill, group=", group_id,
               ", ticket=", ticket, ", error=", GetLastError());
         closed = false;
        }
     }
   for(int index = OrdersTotal() - 1; index >= 0; index--)
     {
      if(OrderSelect(index, SELECT_BY_POS, MODE_TRADES)
         && OrderTicket() != keep_ticket && IsOurMarketOrder()
         && MultiCommentMatches(OrderComment(), group_id))
         closed = false;
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
   const int cycle_length = CycleLength(group.cycle_mode);
   const int normalized = ((index % cycle_length) + cycle_length) % cycle_length;
   bool buy = false;
   if(group.cycle_mode == CYCLE_MODE_1)
      buy = normalized == 0 || normalized == 3;
   else if(group.cycle_mode == CYCLE_MODE_2)
      buy = normalized == 0 || normalized == 2 || normalized == 4 || normalized == 5;
   else if(group.cycle_mode == CYCLE_MODE_3)
      buy = normalized == 0 || normalized == 2 || normalized == 3 || normalized == 5;
   else
      buy = normalized == 0 || normalized == 3 || normalized == 4;
   if(group.first_direction == FIRST_SELL)
      buy = !buy;
   return buy ? OP_BUY : OP_SELL;
  }

double MultiStopPrice(const MultiGroupState &group, const int type)
  {
   double stop_loss = type == OP_BUY
                      ? group.anchor_price - group.stop_points * Point
                      : group.anchor_price + group.stop_points * Point;
   if(DynamicStopLossEnable == 1 && InpGridCount >= 2)
     {
      const int level = HighestFavorableGridLevel(group.favorable_grid_filled_mask);
      const double grid_spacing = group.stop_points * Point / InpGridCount;
      if(type == OP_BUY)
         stop_loss += level * grid_spacing;
      else
         stop_loss -= level * grid_spacing;
     }
   return PriceNormalize(stop_loss);
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

bool MultiSetStops(const MultiGroupState &group, const int type)
  {
   const double stop_loss = MultiStopPrice(group, type);
   const double take_profit = MultiTakeProfitPrice(group, type);
   bool modified = true;
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
        {
         Print("Multi stops modify failed, group=", group.id,
               ", ticket=", OrderTicket(), ", error=", GetLastError());
         modified = false;
        }
     }
   return modified && MultiStopsVerified(group, type);
  }

bool MultiStopsVerified(const MultiGroupState &group, const int type)
  {
   bool found = false;
   const double stop_loss = MultiStopPrice(group, type);
   const double take_profit = MultiTakeProfitPrice(group, type);
   for(int index = OrdersTotal() - 1; index >= 0; index--)
     {
      if(!OrderSelect(index, SELECT_BY_POS, MODE_TRADES)
         || OrderSymbol() != Symbol() || OrderMagicNumber() != InpMagicNumber
         || (OrderType() != OP_BUY && OrderType() != OP_SELL)
         || OrderType() != type || !MultiCommentMatches(OrderComment(), group.id))
         continue;
      found = true;
      if(OrderStopLoss() <= 0.0 || OrderTakeProfit() <= 0.0
         || MathAbs(OrderStopLoss() - stop_loss) > Point * 0.5
         || MathAbs(OrderTakeProfit() - take_profit) > Point * 0.5)
         return false;
     }
   return found;
  }

bool MultiSendMarketLeg(MultiGroupState &group, const int type, const double requested_volume)
  {
   if(启用XAU净盈亏比 && !g_cost_wait_flat) return false;
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

bool MultiOpenMarket(MultiGroupState &group, const int type, const double requested_volume)
  {
   ReversalLotPlan plan;
   if(!BuildReversalLotPlan(requested_volume, plan)
      || plan.status == REVERSAL_LOT_RESTART_GROUP)
      return false;
   const double step = MarketInfo(Symbol(), MODE_LOTSTEP);
   const double tolerance = step > 0.0 ? step * 0.5 : 0.0000001;
   const double target = plan.first_lots
                         + (plan.count == 2 ? plan.second_lots : 0.0);
   double current = MultiTotalLots(group.id, type);
   for(int leg = 0; leg < plan.count && current + tolerance < target; leg++)
     {
      const double leg_target = leg == 0 ? plan.first_lots : plan.second_lots;
      const double leg_volume = MathMin(leg_target, target - current);
      if(leg_volume <= tolerance)
         continue;
      if(!MultiSendMarketLeg(group, type, leg_volume))
         return false;
      current = MultiTotalLots(group.id, type);
     }
   return current + tolerance >= target;
  }

double MultiNextGroupLotsRaw(const MultiGroupState &group, const double fallback)
   {
    if(FirstOrderLotType == 2)
      {
       const double base = group.first_lots > 0.0 ? group.first_lots : fallback;
       return base * FirstOrderMult;
      }
    double requested = group.cumulative_loss_lots + group.total_lots;
   if(requested <= 0.0)
      requested = fallback;
   else
      requested *= 首单手数倍数;
    return requested;
   }

double MultiNextGroupLots(const MultiGroupState &group, const double fallback)
   {
    return VolumeNormalize(MultiNextGroupLotsRaw(group, fallback));
   }

double MultiNextGroupLotsAfterStopRaw(const MultiGroupState &group, const double fallback)
   {
    if(FirstOrderLotType == 2)
      {
       const double base = group.first_lots > 0.0 ? group.first_lots : fallback;
       return base * FirstOrderMult;
      }
    const double requested = group.cumulative_loss_lots > 0.0
                             ? group.cumulative_loss_lots : fallback;
    return requested * 首单手数倍数;
   }

double MultiNextGroupLotsAfterStop(const MultiGroupState &group, const double fallback)
   {
    return VolumeNormalize(MultiNextGroupLotsAfterStopRaw(group, fallback));
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
        {
         if(!OrderDelete(high_ticket, clrRed))
            Print("Multi initial pending rollback failed, group=", group.id,
                  ", ticket=", high_ticket, ", error=", GetLastError());
        }
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

bool MultiHandlePairedInitialPendingFill(MultiGroupState &group)
  {
   int ticket=group.initial_high_ticket>0 ? group.initial_high_ticket
                                           : group.initial_low_ticket;
   if(ticket<=0)
     {
      for(int i=OrdersTotal()-1;i>=0;i--)
         if(OrderSelect(i,SELECT_BY_POS,MODE_TRADES) && IsOurPendingOrder()
            && MultiCommentMatches(OrderComment(),group.id)
            && MultiIsInitialPendingComment()) {ticket=OrderTicket();break;}
      if(ticket<=0)
         for(int i=OrdersHistoryTotal()-1;i>=0;i--)
            if(OrderSelect(i,SELECT_BY_POS,MODE_HISTORY) && IsOurMarketOrder()
               && MultiCommentMatches(OrderComment(),group.id)
               && MultiIsInitialPendingComment()) {ticket=OrderTicket();break;}
      if(ticket>0)
        {
         if(StringFind(OrderComment(),".InitialHigh",0)>=0)
            group.initial_high_ticket=ticket;
         else group.initial_low_ticket=ticket;
         group.dirty=true;MultiSaveGroup(group);
        }
     }
   if(ticket<=0 && group.first_lots>0.0
      && (group.initial_high_price>0.0 || group.initial_low_price>0.0))
     {
      if(group.launch_attempted) return true;
      const bool high_leg=group.initial_high_price>0.0;
      int reopened=-1;
      const double price=high_leg ? group.initial_high_price : group.initial_low_price;
      group.launch_attempted=true;group.dirty=true;MultiSaveGroup(group);
      g_multi_last_send_error=0;
      if(!PlaceInitialPendingOrder(group.first_direction==FIRST_BUY ? OP_BUY : OP_SELL,
                                   price,group.stop_points,group.first_lots,
                                   MultiInitialPendingComment(group.id,high_leg),reopened))
        {if(g_multi_last_send_error!=128) group.launch_attempted=false;
         group.dirty=true;MultiSaveGroup(group);return true;}
      if(high_leg) group.initial_high_ticket=reopened;
      else group.initial_low_ticket=reopened;
      group.launch_attempted=false;group.dirty=true;MultiSaveGroup(group);return true;
     }
   if(ticket<=0) return false;
   const int status=MultiInitialPendingStatus(ticket,group.id);
   if(status==REVERSE_PENDING_ACTIVE || status==REVERSE_PENDING_UNKNOWN) return true;
   if(status!=REVERSE_PENDING_FILLED)
     {group.active=false;group.dirty=true;return false;}
   int pos_ticket=-1,type=OP_BUY;double lots=0.0,entry=0.0,sl=0.0,tp=0.0;
   if(!FindPositionByTicket(ticket,pos_ticket,type,lots,entry,sl,tp)) return true;
   int peer_index=-1;
   for(int i=0;i<ArraySize(g_multi_groups);i++)
      if(group.pair_peer_id>0 && g_multi_groups[i].id==group.pair_peer_id)
        {peer_index=i;break;}
   if(peer_index>=0 && g_multi_groups[peer_index].launch_attempted
      && g_multi_groups[peer_index].initial_high_ticket<0
      && g_multi_groups[peer_index].initial_low_ticket<0)
     {
      int recovered=-1;bool recovered_high=false;
      for(int i=OrdersTotal()-1;i>=0;i--)
         if(OrderSelect(i,SELECT_BY_POS,MODE_TRADES) && IsOurPendingOrder()
            && MultiCommentMatches(OrderComment(),group.pair_peer_id)
            && MultiIsInitialPendingComment())
           {recovered=OrderTicket();recovered_high=StringFind(OrderComment(),".InitialHigh",0)>=0;break;}
      if(recovered<=0)
         for(int i=OrdersHistoryTotal()-1;i>=0;i--)
            if(OrderSelect(i,SELECT_BY_POS,MODE_HISTORY) && IsOurMarketOrder()
               && MultiCommentMatches(OrderComment(),group.pair_peer_id)
               && MultiIsInitialPendingComment())
              {recovered=OrderTicket();recovered_high=StringFind(OrderComment(),".InitialHigh",0)>=0;break;}
      if(recovered<=0) return true;
      if(recovered_high) g_multi_groups[peer_index].initial_high_ticket=recovered;
      else g_multi_groups[peer_index].initial_low_ticket=recovered;
      g_multi_groups[peer_index].launch_attempted=false;
      g_multi_groups[peer_index].dirty=true;MultiSaveGroup(g_multi_groups[peer_index]);
     }
   const int peer_ticket=peer_index<0 ? -1
                         : (g_multi_groups[peer_index].initial_high_ticket>0
                            ? g_multi_groups[peer_index].initial_high_ticket
                            : g_multi_groups[peer_index].initial_low_ticket);
   int pt=-1,ptype=OP_BUY;double pl=0.0,pe=0.0,ps=0.0,ptp=0.0;
   bool peer_filled=peer_index>=0
      && MultiFindPosition(group.pair_peer_id,pt,ptype,pl,pe,ps,ptp);
   if(!peer_filled && peer_ticket>0)
     {
      const int peer_status=MultiInitialPendingStatus(peer_ticket,group.pair_peer_id);
      if(peer_status==REVERSE_PENDING_ACTIVE)
        {
         if(!OrderDelete(peer_ticket,clrRed)) return true;
         const int after_delete=MultiInitialPendingStatus(peer_ticket,group.pair_peer_id);
         if(after_delete==REVERSE_PENDING_UNKNOWN || after_delete==REVERSE_PENDING_ACTIVE)
            return true;
         if(after_delete==REVERSE_PENDING_FILLED)
           {
            if(!MultiFindPosition(group.pair_peer_id,pt,ptype,pl,pe,ps,ptp))
               return true;
            peer_filled=true;
           }
        }
      else if(peer_status==REVERSE_PENDING_UNKNOWN) return true;
      else if(peer_status==REVERSE_PENDING_FILLED)
        {
         if(!MultiFindPosition(group.pair_peer_id,pt,ptype,pl,pe,ps,ptp))
            return true;
         peer_filled=true;
        }
     }
   group.first_direction=type==OP_BUY ? FIRST_BUY : FIRST_SELL;
   group.pair_peer_id=0;
   group.launch_confirmed=true;
   group.anchor_price=entry;group.last_entry=entry;group.linear_extreme=entry;
   group.first_lots=lots;group.total_lots=MultiTotalLots(group.id,type);
   group.grid_lots=group.total_lots;group.initial_high_ticket=-1;
   group.initial_low_ticket=-1;group.initial_high_price=0.0;group.initial_low_price=0.0;
   if(!MultiSetStops(group,type) || !MultiStopsVerified(group,type))
     {Print("Multi OCO fill protection is not verified; follow-up orders are paused.");
      if(!peer_filled) MultiCreateOppositeAfterInitialFill(group.id);
      return true;}
   MultiPlaceReversePending(group,type);MultiPlaceGridPending(group,type);
   if(!peer_filled) MultiCreateOppositeAfterInitialFill(group.id);
   return true;
  }

bool MultiHandleInitialPendingFill(MultiGroupState &group)
  {
   if(group.pair_peer_id!=0)
      return MultiHandlePairedInitialPendingFill(group);
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
      group.first_lots = volume;
      group.total_lots = volume;
      group.grid_filled_levels = 0;
      group.grid_filled_mask = 0;
      group.grid_pending_level = 0;
      group.grid_pending_price = 0.0;
      group.favorable_grid_pending_ticket = -1;
      group.favorable_grid_filled_levels = 0;
      group.favorable_grid_filled_mask = 0;
      group.favorable_grid_pending_level = 0;
      group.favorable_grid_pending_price = 0.0;
      group.grid_lots = group.previous_grid_lots > 0.0
                        ? VolumeNormalize(group.previous_grid_lots * InpGridLotMultiplier)
                        : volume;
      group.initial_high_ticket = -1;
      group.initial_low_ticket = -1;
      group.initial_high_price = 0.0;
      group.initial_low_price = 0.0;
      if(!MultiSetStops(group, position_type) || !MultiStopsVerified(group, position_type))
        {
         Print("Multi initial fill protection is not verified; follow-up orders are paused.");
         return true;
        }
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

bool MultiNormalizeReversePending(const MultiGroupState &group,
                                  const int expected_direction,
                                  const double expected_price,
                                  const double expected_volume,
                                  int &keep_ticket)
  {
   keep_ticket = -1;
   const double price_tolerance = Point * 0.5;
   const double volume_tolerance = MarketInfo(Symbol(), MODE_LOTSTEP) * 0.5;
   for(int index = OrdersTotal() - 1; index >= 0; index--)
     {
      if(!OrderSelect(index, SELECT_BY_POS, MODE_TRADES)
         || !IsOurPendingOrder() || !MultiCommentMatches(OrderComment(), group.id)
         || MultiIsGridSelectedOrder() || MultiIsInitialPendingComment())
         continue;
      if(PendingDirection(OrderType()) == expected_direction
         && MathAbs(OrderOpenPrice() - expected_price) <= price_tolerance
         && MathAbs(OrderLots() - expected_volume) <= volume_tolerance
         && (keep_ticket <= 0 || OrderTicket() < keep_ticket))
         keep_ticket = OrderTicket();
     }
   bool normalized = true;
   for(int index = OrdersTotal() - 1; index >= 0; index--)
     {
      if(!OrderSelect(index, SELECT_BY_POS, MODE_TRADES)
         || !IsOurPendingOrder() || !MultiCommentMatches(OrderComment(), group.id)
         || MultiIsGridSelectedOrder() || MultiIsInitialPendingComment()
         || OrderTicket() == keep_ticket)
         continue;
      const int candidate = OrderTicket();
      if(!OrderDelete(candidate, clrRed))
        {
         Print("Multi reverse pending reconciliation failed, group=", group.id,
               ", ticket=", candidate, ", error=", GetLastError());
         normalized = false;
        }
     }
   return normalized;
  }

bool MultiPlaceReversePending(MultiGroupState &group, const int current_type)
  {
   if(启用XAU净盈亏比 && !g_cost_wait_flat) return false;
   if(group.reversal_count >= 最大反手次数 || group.stop_points <= 0
      || group.take_profit_points <= 0 || group.total_lots <= 0.0)
      return false;
   const int next_index = (group.cycle_index + 1) % CycleLength(group.cycle_mode);
   const int next_direction = MultiSequenceDirection(group, next_index);
   const double entry = MultiStopPrice(group, current_type);
   ReversalLotPlan plan;
   if(!BuildReversalLotPlan(MultiNextGroupLotsRaw(group, group.total_lots), plan)
      || plan.status != REVERSAL_LOT_SINGLE)
      return false;
   const double volume = VolumeNormalize(plan.first_lots);
   int existing_ticket = -1;
   if(!MultiNormalizeReversePending(group, next_direction, entry, volume,
                                    existing_ticket))
      return false;
   if(existing_ticket > 0)
     {
      group.pending_ticket = existing_ticket;
      group.pending_index = next_index;
      return true;
     }
    const int pending_type = PendingTypeForDirection(next_direction, entry);
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

double MultiFavorableGridLevelPrice(const MultiGroupState &group, const int type, const int level)
  {
   if(网格数量 <= 0 || group.stop_points <= 0 || group.anchor_price <= 0.0)
      return 0.0;
   const double distance = group.stop_points * Point * level / 网格数量;
   return type == OP_BUY
          ? PriceNormalize(group.anchor_price + distance)
          : PriceNormalize(group.anchor_price - distance);
  }

string MultiGridComment(const int group_id, const int level, const bool favorable)
  {
   return InpOrderComment + MultiGroupTag(group_id)
          + (favorable ? ".Grid.F." : ".Grid.")
            + IntegerToString(level);
  }

bool PrepareMultiGridPendingForCurrentStop(const MultiGroupState &group,
                                           const int position_type,
                                           const double entry, const bool favorable,
                                           int &ticket)
  {
   if(ticket <= 0)
      return true;
   const double stop_loss = MultiStopPrice(group, position_type);
   const double tolerance = Point * 0.5;
   const bool adverse_level_invalid = !favorable
                                      && ((position_type == OP_BUY
                                           && entry <= stop_loss + tolerance)
                                          || (position_type == OP_SELL
                                              && entry >= stop_loss - tolerance));
   if(!OrderSelect(ticket, SELECT_BY_TICKET, MODE_TRADES))
     {
      ticket = -1;
      return true;
     }
   const double expected_take_profit = MultiTakeProfitPrice(group, position_type);
   const bool wrong_take_profit = favorable
                                  && MathAbs(OrderTakeProfit() - expected_take_profit) > tolerance;
   if(!adverse_level_invalid
      && (DynamicStopLossEnable != 1
          || MathAbs(OrderStopLoss() - stop_loss) <= tolerance)
      && !wrong_take_profit)
      return true;
   if(!OrderDelete(ticket, clrRed))
     {
      Print("Dynamic multi grid pending cleanup failed, group=", group.id,
            ", ticket=", ticket, ", error=", GetLastError());
      return false;
     }
   ticket = -1;
   return true;
  }

double MultiGridLotsForNewGroup(const MultiGroupState &group)
  {
   return GridLotsForNewGroup(group.first_lots, group.grid_lots);
  }

bool MultiPlaceGridPending(MultiGroupState &group, const int type)
  {
   if(启用XAU净盈亏比 && !g_cost_wait_flat) return false;
   group.grid_lots = MultiGridLotsForNewGroup(group);
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
       if(!PrepareMultiGridPendingForCurrentStop(group, type, entry, false,
                                                 existing_ticket))
          return false;
       if(existing_ticket <= 0
          && ((type == OP_BUY && entry <= MultiStopPrice(group, type) + Point * 0.5)
              || (type == OP_SELL && entry >= MultiStopPrice(group, type) - Point * 0.5)))
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
                                      MultiGridComment(group.id, level, false), InpMagicNumber,
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
      MultiRememberGridOrderTicket(group.id, level, false, existing_ticket);
      placed = true;
      }
    if(FavorableGridEnable == 1)
      for(int level = 1; level < 网格数量; level++)
        {
         if((group.favorable_grid_filled_mask & GridLevelBit(level)) != 0)
            continue;
         const double entry = MultiFavorableGridLevelPrice(group, type, level);
         int existing_ticket = -1;
       if(!MultiNormalizeGridPendingLevel(group, type, level, entry, volume,
                                          existing_ticket))
          continue;
       if(!PrepareMultiGridPendingForCurrentStop(group, type, entry, true,
                                                 existing_ticket))
          return false;
       if(existing_ticket <= 0)
           {
            const int pending_type = PendingTypeForDirection(type, entry);
            const double stop_loss = MultiStopPrice(group, type);
            const double take_profit = MultiTakeProfitPrice(group, type);
            RefreshRates();
            existing_ticket = OrderSend(Symbol(), pending_type, volume, entry, 0,
                                        stop_loss, take_profit,
                                        MultiGridComment(group.id, level, true), InpMagicNumber,
                                        0, clrOrange);
            if(existing_ticket < 0)
              {
               Print("Multi favorable grid pending failed, group=", group.id,
                     ", level=", level, ", error=", GetLastError());
               continue;
              }
           }
         group.favorable_grid_pending_ticket = existing_ticket;
         group.favorable_grid_pending_level = level;
         group.favorable_grid_pending_price = entry;
         MultiRememberGridOrderTicket(group.id, level, true, existing_ticket);
         placed = true;
        }
    group.grid_filled_levels = MultiGridFilledLevelCount(group);
    group.favorable_grid_filled_levels = MultiGridFilledLevelCountForMask(
       group.favorable_grid_filled_mask);
   return placed;
  }

void MultiHandleGridFill(MultiGroupState &group, const int type, const double current_total)
  {
   if(网格数量 < 2 || group.anchor_price <= 0.0)
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
                                  MultiGridLevelPrice(group, type, level), false,
                                  fill_price))
        {
         group.grid_filled_mask |= level_bit;
         latest_entry = fill_price;
         changed = true;
         }
      }
    if(FavorableGridEnable == 1)
      for(int level = 1; level < 网格数量; level++)
        {
         const long level_bit = GridLevelBit(level);
         if(level_bit == 0 || (group.favorable_grid_filled_mask & level_bit) != 0)
            continue;
         double fill_price = 0.0;
         if(MultiFindFilledGridOrder(group, type, level,
                                     MultiFavorableGridLevelPrice(group, type, level),
                                     true, fill_price))
           {
            group.favorable_grid_filled_mask |= level_bit;
            changed = true;
           }
        }
   if(!changed)
      return;
   group.grid_filled_levels = MultiGridFilledLevelCount(group);
   group.grid_pending_level = 0;
   group.grid_pending_ticket = -1;
   group.grid_pending_price = 0.0;
   group.favorable_grid_filled_levels = MultiGridFilledLevelCountForMask(
      group.favorable_grid_filled_mask);
   group.favorable_grid_pending_ticket = -1;
   group.favorable_grid_pending_level = 0;
   group.favorable_grid_pending_price = 0.0;
   group.total_lots = current_total;
   if(latest_entry > 0.0)
      group.last_entry = latest_entry;
   MultiSetStops(group, type);
  }

bool MultiHandleReverseFill(MultiGroupState &group, int &type, double &entry,
                            double &current_total)
  {
    if(group.pending_ticket < 0 || group.pending_index < 0
       || group.pending_index == group.cycle_index
       || MultiPendingStatus(group.pending_ticket, group.id, false) != REVERSE_PENDING_FILLED)
       return false;
    int filled_ticket = -1;
    int filled_type = type;
    double filled_volume = 0.0;
    double filled_entry = entry;
    double filled_stop_loss = 0.0;
    double filled_take_profit = 0.0;
    if(!FindPositionByTicket(group.pending_ticket, filled_ticket, filled_type,
                             filled_volume, filled_entry, filled_stop_loss,
                             filled_take_profit))
       return true;
    if(!MultiDeletePending(group.id))
       return true;
    if(!MultiClosePositionsExcept(group.id, filled_ticket))
      {
       Print("Reverse fill detected for multi group ", group.id,
             ", but the previous order group is not fully closed; retrying.");
       return true;
      }
    const int promoted_type = filled_type;
    const double promoted_entry = filled_entry;
    const double promoted_total = MultiTotalLots(group.id, promoted_type);
    if(promoted_total <= 0.0)
       return true;
    type = promoted_type;
    entry = promoted_entry;
    current_total = promoted_total;
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
    group.anchor_price = promoted_entry;
    group.last_entry = promoted_entry;
    group.linear_extreme = promoted_entry;
    group.first_lots = promoted_total;
    group.total_lots = promoted_total;
   group.grid_filled_levels = 0;
     group.grid_filled_mask = 0;
     group.grid_pending_level = 0;
     group.grid_pending_ticket = -1;
     group.grid_pending_price = 0.0;
      group.favorable_grid_filled_levels = 0;
      group.favorable_grid_filled_mask = 0;
      group.favorable_grid_pending_level = 0;
      group.favorable_grid_pending_ticket = -1;
      group.favorable_grid_pending_price = 0.0;
   group.grid_lots = group.previous_grid_lots > 0.0
                     ? VolumeNormalize(group.previous_grid_lots * 网格手数倍数)
                      : promoted_total;
    MultiSetStops(group, promoted_type);
   return true;
  }

bool ResetOrderGroupAfterOversizedReversal(MultiGroupState &group)
  {
   Print("Oversized reversal stopped group ", group.id,
         "; start a fresh base-lot group on the next tick.");
   if(!MultiDeletePending(group.id) || !MultiClosePositions(group.id))
      return false;
   group.active = false;
   return true;
  }

bool MultiRecoverFlatGroupAfterBrokerStop(MultiGroupState &group)
  {
   if(!group.active || group.transition_target_lots > 0.0
      || group.first_lots <= 0.0 || group.stop_points <= 0
      || group.take_profit_points <= 0)
      return false;

   const int current_type = MultiSequenceDirection(group, group.cycle_index);
   const double stop_loss = MultiStopPrice(group, current_type);
   const double take_profit = MultiTakeProfitPrice(group, current_type);
   RefreshRates();
   if((current_type == OP_BUY && Bid >= take_profit)
      || (current_type == OP_SELL && Ask <= take_profit))
      return false;
   if(!((current_type == OP_BUY && Bid <= stop_loss)
        || (current_type == OP_SELL && Ask >= stop_loss)))
      return false;

   const double stopped_group_volume = group.total_lots > 0.0
                                      ? group.total_lots : group.first_lots;
   const double next_group_lots = MultiNextGroupLotsAfterStopRaw(
      group, stopped_group_volume);
   ReversalLotPlan reversal_plan;
   if(!BuildReversalLotPlan(next_group_lots, reversal_plan))
      return true;
   Print("Broker stop closed multi group ", group.id,
         " before EA processing; recovering the reverse market order. first_lots=",
         DoubleToString(group.first_lots, 2), ", group_lots=",
         DoubleToString(stopped_group_volume, 2), ", next_lots=",
         DoubleToString(next_group_lots, 2));
   if(reversal_plan.status == REVERSAL_LOT_RESTART_GROUP)
     {
      ResetOrderGroupAfterOversizedReversal(group);
      return true;
     }
   if(!MultiDeletePending(group.id))
      return true;
   group.cumulative_loss_lots += stopped_group_volume;
   group.previous_grid_lots = group.grid_lots;
   const int next_index = (group.cycle_index + 1) % CycleLength(group.cycle_mode);
   const int next_type = MultiSequenceDirection(group, next_index);
   group.reversal_count++;
   group.cycle_index = next_index;
   group.pending_index = -1;
   group.pending_ticket = -1;
   group.transition_target_lots = next_group_lots;
   if(!MultiOpenMarket(group, next_type, next_group_lots))
      return true;

   int ticket = -1;
   int type = OP_BUY;
   double total = 0.0;
   double entry = 0.0;
   double actual_stop_loss = 0.0;
   double actual_take_profit = 0.0;
   if(!MultiFindPosition(group.id, ticket, type, total, entry,
                         actual_stop_loss, actual_take_profit))
      return true;
   group.transition_target_lots = 0.0;
   group.anchor_price = entry;
   group.last_entry = entry;
   group.linear_extreme = entry;
   group.first_lots = total;
   group.total_lots = total;
   group.grid_filled_levels = 0;
   group.grid_filled_mask = 0;
   group.grid_pending_level = 0;
   group.grid_pending_ticket = -1;
   group.grid_pending_price = 0.0;
   group.favorable_grid_pending_ticket = -1;
   group.favorable_grid_filled_levels = 0;
   group.favorable_grid_filled_mask = 0;
   group.favorable_grid_pending_level = 0;
   group.favorable_grid_pending_price = 0.0;
   group.grid_lots = group.previous_grid_lots > 0.0
                     ? VolumeNormalize(group.previous_grid_lots * 网格手数倍数)
                     : total;
   if(!MultiSetStops(group, type) || !MultiStopsVerified(group, type))
      return true;
   MultiPlaceReversePending(group, type);
   MultiPlaceGridPending(group, type);
   return true;
  }

int MultiInitialMarketStatus(const int group_id)
  {
   for(int i=OrdersTotal()-1;i>=0;i--)
      if(OrderSelect(i,SELECT_BY_POS,MODE_TRADES)
         && OrderSymbol()==Symbol() && OrderMagicNumber()==InpMagicNumber
         && IsOurMarketOrder() && MultiCommentMatches(OrderComment(),group_id))
         return 1;
   for(int i=OrdersHistoryTotal()-1;i>=0;i--)
      if(OrderSelect(i,SELECT_BY_POS,MODE_HISTORY)
         && OrderSymbol()==Symbol() && OrderMagicNumber()==InpMagicNumber
         && IsOurMarketOrder() && MultiCommentMatches(OrderComment(),group_id))
         return 2;
   return 0;
  }

bool MultiManageGroup(MultiGroupState &group)
  {
   if(group.initial_low_direction>group.id && group.initial_high_ticket<0
      && group.initial_low_ticket<0)
      MultiEnsureRecoveredOpposite(group.id);
   if(group.pair_parent_id>0)
     {
      int parent_index=-1;
      for(int i=0;i<ArraySize(g_multi_groups);i++)
         if(g_multi_groups[i].id==group.pair_parent_id) { parent_index=i; break; }
      if(parent_index<0 || !g_multi_groups[parent_index].active)
        {group.active=false;group.dirty=true;return false;}
      int pt=-1,ptype=OP_BUY;double pl=0.0,pe=0.0,ps=0.0,ptp=0.0;
      if(!MultiFindPosition(group.pair_parent_id,pt,ptype,pl,pe,ps,ptp))
        {
         const int parent_status=MultiInitialMarketStatus(group.pair_parent_id);
          if(parent_status==2)
           {group.active=false;group.dirty=true;return false;}
         if(parent_status==1)
           {g_multi_groups[parent_index].launch_confirmed=true;
            g_multi_groups[parent_index].dirty=true;}
         return true;
        }
     }
   if(MultiHandleInitialPendingFill(group))
      return true;
   int ticket = -1;
   int type = OP_BUY;
   double total = 0.0;
   double entry = 0.0;
   double stop_loss = 0.0;
   double take_profit = 0.0;
   bool has_position = MultiFindPosition(group.id, ticket, type, total, entry,
                                         stop_loss, take_profit);
   if(has_position && group.launch_attempted)
     {group.launch_attempted=false;group.launch_confirmed=true;
      group.dirty=true;MultiSaveGroup(group);}
   // A failed market reversal must remain recoverable. The old reverse
   // pending order is not a substitute for the required market order.
   if(!has_position && group.transition_target_lots > 0.0)
     {
      int initial_status=0;
      if(!group.launch_confirmed)
         initial_status=MultiInitialMarketStatus(group.id);
      if(!group.launch_confirmed && initial_status==1)
        {
         group.launch_confirmed=true;
         group.dirty=true;
         return true;
        }
      if(!group.launch_confirmed && initial_status==2)
        {
         group.launch_confirmed=true;
         group.active=false;
         group.dirty=true;
         return false;
        }
      if(group.launch_failed) return true;
      if(group.launch_retry_after>TimeCurrent()) return true;
      if(group.launch_attempted) return true;
      if(!MultiDeletePending(group.id))
         return true;
      const int expected_type = MultiSequenceDirection(group, group.cycle_index);
      g_multi_last_send_error=0;
      group.launch_attempted=true;group.dirty=true;MultiSaveGroup(group);
      if(!MultiOpenMarket(group, expected_type, group.transition_target_lots))
        {MultiRecordLaunchFailure(group,g_multi_last_send_error);return true;}
      group.launch_confirmed=true;
      group.launch_attempted=false;group.launch_failed=false;group.launch_error=0;
      group.launch_retry_after=0;group.launch_attempt_count=0;
      group.dirty=true;
      has_position = MultiFindPosition(group.id, ticket, type, total, entry,
                                       stop_loss, take_profit);
      if(!has_position)
         return true;
     }
   if(!has_position)
     {
      if(MultiRecoverFlatGroupAfterBrokerStop(group))
         return true;
      const int status = MultiPendingStatus(group.pending_ticket, group.id, false);
      if(status == REVERSE_PENDING_ACTIVE || status == REVERSE_PENDING_FILLED)
         return true;
      if(!MultiDeletePending(group.id))
         return true;
      group.active = false;
      MarkMultiCandleTriggerBar();
      return false;
     }
   if(group.transition_target_lots > 0.0)
     {
      group.launch_confirmed=true;
      if(group.launch_failed)
         group.transition_target_lots=total;
      const double tolerance = MarketInfo(Symbol(), MODE_LOTSTEP) * 0.5;
      if(type != MultiSequenceDirection(group, group.cycle_index))
         return true;
      if(total + tolerance < group.transition_target_lots)
        {
         if(group.launch_attempted) return true;
         if(group.launch_retry_after>TimeCurrent()) return true;
         g_multi_last_send_error=0;
         group.launch_attempted=true;group.dirty=true;MultiSaveGroup(group);
         if(!MultiOpenMarket(group, type, group.transition_target_lots))
           {MultiRecordLaunchFailure(group,g_multi_last_send_error);return true;}
         group.launch_attempted=false;group.launch_failed=false;
         group.launch_error=0;group.launch_retry_after=0;
         group.launch_attempt_count=0;
         if(!MultiFindPosition(group.id, ticket, type, total, entry,
                               stop_loss, take_profit))
            return true;
        }
      if(total > group.transition_target_lots + tolerance)
         return true;
      group.transition_target_lots = 0.0;
      group.anchor_price = entry;
      group.last_entry = entry;
      group.linear_extreme = entry;
      group.first_lots = total;
      group.total_lots = total;
      group.grid_filled_levels = 0;
      group.grid_filled_mask = 0;
      group.grid_pending_level = 0;
      group.grid_pending_ticket = -1;
      group.grid_pending_price = 0.0;
      group.favorable_grid_pending_ticket = -1;
      group.favorable_grid_filled_levels = 0;
      group.favorable_grid_filled_mask = 0;
      group.favorable_grid_pending_level = 0;
      group.favorable_grid_pending_price = 0.0;
      group.grid_lots = group.previous_grid_lots > 0.0
                        ? VolumeNormalize(group.previous_grid_lots * InpGridLotMultiplier)
                        : total;
     }
   if(MultiHandleReverseFill(group, type, entry, total))
     {
      if(g_reset_pending)
         return false;
      if(!MultiStopsVerified(group, type)
         && (!MultiSetStops(group, type) || !MultiStopsVerified(group, type)))
        {
         Print("Multi reverse fill protection is not verified; follow-up orders are paused.");
         return true;
        }
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
   if(group.first_lots <= 0.0) group.first_lots = total;
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
         if(!MultiSetStops(group, type) || !MultiStopsVerified(group, type))
            return true;
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
      Print("Stop reached for group ", group.id,
            "; canceling the old reverse pending order and forcing a market reversal.");
      if(group.reversal_count >= 最大反手次数)
        {
         BeginResetAfterMaxReversals();
         return false;
        }
      const double next_group_lots = MultiNextGroupLotsAfterStopRaw(group, group.total_lots);
      ReversalLotPlan reversal_plan;
      if(!BuildReversalLotPlan(next_group_lots, reversal_plan))
         return true;
      if(reversal_plan.status == REVERSAL_LOT_RESTART_GROUP)
        {
         ResetOrderGroupAfterOversizedReversal(group);
         return false;
        }
      if(!MultiDeletePending(group.id))
         return true;
      group.cumulative_loss_lots += group.total_lots;
      group.previous_grid_lots = group.grid_lots;
      if(!MultiClosePositions(group.id)) return false;
      const int next_index = (group.cycle_index + 1) % CycleLength(group.cycle_mode);
      const int next_type = MultiSequenceDirection(group, next_index);
      group.reversal_count++;
      group.cycle_index = next_index;
      group.pending_index = -1;
      group.pending_ticket = -1;
      group.transition_target_lots = next_group_lots;
      if(!MultiOpenMarket(group, next_type, next_group_lots))
         return false;
      if(!MultiFindPosition(group.id, ticket, type, total, entry, stop_loss, take_profit))
         return false;
       group.transition_target_lots = 0.0;
       group.anchor_price = entry;
       group.last_entry = entry;
       group.linear_extreme = entry;
       group.first_lots = total;
       group.total_lots = total;
      group.grid_filled_levels = 0;
      group.grid_filled_mask = 0;
      group.grid_pending_level = 0;
      group.grid_pending_ticket = -1;
      group.grid_pending_price = 0.0;
      group.grid_lots = group.previous_grid_lots > 0.0
                        ? VolumeNormalize(group.previous_grid_lots * 网格手数倍数)
                        : total;
      if(!MultiSetStops(group, type) || !MultiStopsVerified(group, type))
        {
         Print("Multi transition protection is not verified; follow-up orders are paused.");
         return true;
        }
      MultiPlaceReversePending(group, type);
      MultiPlaceGridPending(group, type);
      return true;
     }
   if(!MultiStopsVerified(group, type)
      && (!MultiSetStops(group, type) || !MultiStopsVerified(group, type)))
     {
      Print("Multi position protection is not verified; follow-up orders are paused.");
     return true;
     }
   MultiHandleGridFill(group, type, total);
   if(!MultiStopsVerified(group, type)
      && (!MultiSetStops(group, type) || !MultiStopsVerified(group, type)))
     {
      Print("Multi grid-fill protection is not verified; follow-up orders are paused.");
      return true;
     }
   MultiPlaceReversePending(group, type);
   MultiPlaceGridPending(group, type);
   return true;
  }

void ProcessInitialPendingFillEvent()
  {
   if(g_reset_pending)
      return;
   if(InpDistanceMode == DISTANCE_CANDLE_RANGE
      && (kline_enable_multiple == 1 || 篮子数量 == 2))
     {
      for(int index = ArraySize(g_multi_groups) - 1; index >= 0; index--)
        {
         if(!g_multi_groups[index].active)
            continue;
         MultiGroupState before = g_multi_groups[index];
         if(MultiHandleInitialPendingFill(g_multi_groups[index])
            && MultiStateChanged(before, g_multi_groups[index]))
            g_multi_groups[index].dirty = true;
         if(g_multi_groups[index].dirty)
            MultiSaveGroup(g_multi_groups[index]);
        }
      return;
     }
   HandleInitialPendingFill();
  }

bool MultiTryOpenCandleGroup()
  {
   if(篮子数量 == 2 && MultiHasActiveGroups()) return false;
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
      if(篮子数量==2)
        {
         MultiRemoveGroup(new_index);
         return StartInitialMultiOco(previous_high,previous_low,range_points,首单手数);
        }
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
   if(篮子数量 == 2)
     {
      MultiRemoveGroup(new_index);
      StartResolvedMultiPair(first_direction, range_points, range_points, 首单手数);
      if(Korder_type == KORDER_ONCE_PER_BAR && current_bar > 0)
         MarkMultiCandleTriggerBar();
      return true;
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
   state.first_lots = total;
   state.total_lots = total;
   state.grid_lots = total;
   if(!MultiSetStops(state, type) || !MultiStopsVerified(state, type))
     {
      Print("Multi initial market protection is not verified; follow-up orders are paused.");
      g_multi_groups[new_index] = state;
      MultiSaveGroup(g_multi_groups[new_index]);
      return true;
     }
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
      MultiGroupState before = g_multi_groups[index];
      MultiManageGroup(g_multi_groups[index]);
      if(MultiStateChanged(before, g_multi_groups[index]))
         g_multi_groups[index].dirty = true;
      if(was_active && !g_multi_groups[index].active)
        {
         MultiRemoveGroup(index);
         closed_group = true;
        }
      else if(g_multi_groups[index].active && g_multi_groups[index].dirty)
         MultiSaveGroup(g_multi_groups[index]);
      if(g_reset_pending) return;
     }
   if(closed_group) return;
   MultiTryOpenCandleGroup();
   }

string MultiCostTicketPrefix(const int id)
  {return MultiStatePrefix(id)+".cost.t.";}

bool MultiCostOwnsSelected(const int id)
  {
   return OrderSymbol()==Symbol() && OrderMagicNumber()==InpMagicNumber
          && (OrderType()==OP_BUY || OrderType()==OP_SELL)
          && GlobalVariableCheck(MultiCostTicketPrefix(id)
                                 +IntegerToString(OrderTicket()));
  }

bool MultiCostFindPosition(const int id,int &ticket,int &type,double &volume,
                           double &entry,double &sl,double &tp)
  {
   bool found=false;volume=0.0;
   for(int i=OrdersTotal()-1;i>=0;i--)
     {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES)
         || !MultiCostOwnsSelected(id)) continue;
      if(!found)
        {ticket=OrderTicket();type=OrderType();entry=OrderOpenPrice();
         sl=OrderStopLoss();tp=OrderTakeProfit();found=true;}
      volume+=OrderLots();
     }
   return found;
  }

double MultiCostTotalLots(const int id,const int type)
  {
   double total=0.0;
   for(int i=OrdersTotal()-1;i>=0;i--)
      if(OrderSelect(i,SELECT_BY_POS,MODE_TRADES)
         && MultiCostOwnsSelected(id) && OrderType()==type)
         total+=OrderLots();
   return total;
  }

bool MultiCostClosePositions(const int id)
  {
   bool ok=true;
   for(int i=OrdersTotal()-1;i>=0;i--)
     {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES)
         || !MultiCostOwnsSelected(id)) continue;
      const int ticket=OrderTicket();const int type=OrderType();
      const double lots=OrderLots();
      RefreshRates();
      if(!OrderClose(ticket,lots,type==OP_BUY ? Bid : Ask,
                     最大开仓滑点点数,clrRed))
        {ok=false;Print("MULTI_COST_CLOSE_FAILED group=",id,
                        " ticket=",ticket," error=",GetLastError());}
     }
   return ok;
  }

bool MultiCostLedger(const MultiGroupState &group,double &cash)
  {
   cash=0.0;
   const string prefix=MultiCostTicketPrefix(group.id);
   int mapped=0;
   for(int i=0;i<GlobalVariablesTotal();i++)
     {
      const string key=GlobalVariableName(i);
      if(StringFind(key,prefix)!=0) continue;
      mapped++;
      const int ticket=(int)StringToInteger(StringSubstr(key,StringLen(prefix)));
      if(ticket<=0 || !OrderSelect(ticket,SELECT_BY_TICKET)
         || OrderSymbol()!=Symbol() || OrderMagicNumber()!=InpMagicNumber
         || (OrderType()!=OP_BUY && OrderType()!=OP_SELL)) return false;
      if(OrderCloseTime()==0) continue;
      const double remaining=MathMax(0.0,每手往返佣金费用预算*OrderLots()
                                     -MathMax(0.0,-OrderCommission()));
      cash+=OrderProfit()+OrderCommission()+OrderSwap()-remaining;
     }
   for(int j=0;j<OrdersTotal();j++)
     {
      if(!OrderSelect(j,SELECT_BY_POS,MODE_TRADES)
         || OrderSymbol()!=Symbol() || OrderMagicNumber()!=InpMagicNumber
         || (OrderType()!=OP_BUY && OrderType()!=OP_SELL)
         || !MultiCostOwnsSelected(group.id)) continue;
      if(!GlobalVariableCheck(prefix+IntegerToString(OrderTicket()))) return false;
     }
   return mapped>0 || group.cost_last_ticket<=0;
  }

bool MultiCostOutcomes(const MultiGroupState &group,const int type,
                       const double extra_lots,const double extra_entry,
                       const double sl,const double tp,double &profit,double &loss)
  {
   if(CostMoneyPerPriceUnit()<=0.0 || !MultiCostLedger(group,profit)) return false;
   loss=profit;
   double total=0.0;
   for(int i=0;i<OrdersTotal();i++)
     {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES)
         || OrderSymbol()!=Symbol() || OrderMagicNumber()!=InpMagicNumber
         || !MultiCostOwnsSelected(group.id)) continue;
      if(OrderType()!=type) return false;
      const double lots=OrderLots();
      const double paid=OrderCommission()+OrderSwap();
      const double remaining=MathMax(0.0,每手往返佣金费用预算*lots
                                     -MathMax(0.0,-OrderCommission()));
      profit+=CostPriceProfit(type,lots,OrderOpenPrice(),tp)+paid-remaining;
      loss+=CostPriceProfit(type,lots,OrderOpenPrice(),sl)+paid-remaining;
      total+=lots;
     }
   if(extra_lots>0.0)
     {
      profit+=CostPriceProfit(type,extra_lots,extra_entry,tp)
              -每手往返佣金费用预算*extra_lots;
      loss+=CostPriceProfit(type,extra_lots,extra_entry,sl)
            -每手往返佣金费用预算*extra_lots;
      total+=extra_lots;
     }
   const double slip=预计平仓滑点点数*Point*total*CostMoneyPerPriceUnit();
   profit-=slip;loss-=slip;
   return total>0.0;
  }

bool MultiCostSolve(const MultiGroupState &group,const int type,
                    const double lots,const double entry,const double sl,
                    const double strategy,double &tp,double &loss,string &reason)
  {
   const double tick=CostTickSize();
   if(tick<=0.0 || group.cost_target<=0.0)
     {reason="CONTRACT_UNAVAILABLE";return false;}
   const int sign=type==OP_BUY ? 1 : -1;
   const double cap=MathMin(最大止盈补偿点数*Point,
                            group.take_profit_points*Point*最大止盈补偿比例);
   tp=NormalizeDouble((type==OP_BUY ? MathCeil(strategy/tick)
                                   : MathFloor(strategy/tick))*tick,Digits);
   const int steps=(int)MathCeil(cap/tick)+2;
   for(int step=0;step<=steps;step++)
     {
      if(sign*(tp-strategy)>cap+tick*0.01) break;
      double profit=0.0;
      if(!MultiCostOutcomes(group,type,lots,entry,sl,tp,profit,loss))
        {reason="COST_LEDGER_INCOMPLETE";return false;}
      if(profit>0.0 && (loss>=0.0 || profit+0.000001>=group.cost_target*(-loss)))
         return true;
      tp=NormalizeDouble(tp+sign*tick,Digits);
     }
   reason="TARGET_INFEASIBLE";return false;
  }

double MultiCostScenarioLoss(const MultiGroupState &group,const int type,
                             const double base_loss,const double sl,
                             const double candidate_trigger,const double fallback_lots)
  {
   double result=base_loss;
   if(InpGridCount<2) return result;
   const int sign=type==OP_BUY ? 1 : -1;
   const double anchor=group.anchor_price>0.0 ? group.anchor_price
                       : (candidate_trigger>0.0 ? candidate_trigger
                                                 : (type==OP_BUY ? Ask : Bid));
   const double lots=group.grid_lots>0.0 ? group.grid_lots : fallback_lots;
   for(int level=1;level<InpGridCount;level++)
     for(int side=0;side<2;side++)
       {
        if(side==1 && FavorableGridEnable!=1) continue;
        const long bit=GridLevelBit(level);
        if((side==0 && (group.grid_filled_mask&bit)!=0)
           || (side==1 && (group.favorable_grid_filled_mask&bit)!=0)) continue;
        const double trigger=PriceNormalize(anchor+(side==0 ? -sign : sign)
                             *group.stop_points*Point*level/InpGridCount);
        if(candidate_trigger>0.0 && MathAbs(trigger-candidate_trigger)<=Point*0.5)
           continue;
        if((type==OP_BUY && trigger<=sl)||(type==OP_SELL && trigger>=sl)) continue;
        const double worst=trigger+sign*最大开仓滑点点数*Point;
        result+=CostPriceProfit(type,lots,worst,sl)
                -每手往返佣金费用预算*lots
                -预计平仓滑点点数*Point*lots*CostMoneyPerPriceUnit();
       }
   return MathMin(base_loss,result);
  }

bool MultiCostRisk(const MultiGroupState &group,const int type,const double loss,
                   const double sl,const double candidate_trigger,
                   const double fallback_lots,string &reason)
  {
   if(AccountEquity()<=0.0) {reason="EQUITY_UNAVAILABLE";return false;}
   const double own=-MultiCostScenarioLoss(group,type,loss,sl,candidate_trigger,fallback_lots);
   if(own>单轮最大预计亏损权益比例*AccountEquity())
     {reason="CYCLE_RISK_LIMIT";return false;}
   double aggregate=MathMax(0.0,own);
   for(int j=0;j<ArraySize(g_multi_groups);j++)
     {
      MultiGroupState other=g_multi_groups[j];
      if(!other.active || other.id==group.id) continue;
      if(!other.cost_mode || other.cost_frozen)
        {reason="PARALLEL_LEDGER_UNAVAILABLE";return false;}
      if(other.cost_last_ticket<=0)
        {
         double max_virtual_risk=0.0;
         for(int side=0;side<2;side++)
           {
            const int virtual_type=side==0
               ? (ordertype==ORDERTYPE_FORWARD ? OP_BUY : OP_SELL)
               : (ordertype==ORDERTYPE_FORWARD ? OP_SELL : OP_BUY);
            const double trigger=side==0 ? other.cost_high : other.cost_low;
            if(trigger<=0.0) {reason="PARALLEL_TRIGGER_UNAVAILABLE";return false;}
            const int sign=virtual_type==OP_BUY ? 1 : -1;
            const double worst=trigger+sign*最大开仓滑点点数*Point;
            const double virtual_sl=PriceNormalize(trigger-sign*other.stop_points*Point);
            const double virtual_tp=PriceNormalize(trigger+sign*other.take_profit_points*Point);
            double profit=0.0,virtual_loss=0.0;
            if(!MultiCostOutcomes(other,virtual_type,InpInitialLots,worst,
                                  virtual_sl,virtual_tp,profit,virtual_loss))
              {reason="PARALLEL_LEDGER_UNAVAILABLE";return false;}
            MultiGroupState scenario=other;
            scenario.anchor_price=trigger;
            const double projected=MultiCostScenarioLoss(scenario,virtual_type,virtual_loss,
                                      virtual_sl,0.0,InpInitialLots);
            max_virtual_risk=MathMax(max_virtual_risk,MathMax(0.0,-projected));
           }
         aggregate+=max_virtual_risk;
         continue;
        }
      const int other_type=MultiSequenceDirection(other,other.cycle_index);
      const double other_sl=MultiStopPrice(other,other_type);
      double other_profit=0.0,other_loss=0.0;
      const double other_tp=other.cost_tp>0.0 ? other.cost_tp
                                                : MultiTakeProfitPrice(other,other_type);
      if(!MultiCostOutcomes(other,other_type,0.0,0.0,other_sl,other_tp,
                            other_profit,other_loss))
        {reason="PARALLEL_LEDGER_UNAVAILABLE";return false;}
      aggregate+=MathMax(0.0,-MultiCostScenarioLoss(other,other_type,other_loss,
                         other_sl,0.0,other.grid_lots));
     }
   if(aggregate>全部轮次最大预计亏损权益比例*AccountEquity())
     {reason="ACCOUNT_RISK_LIMIT";return false;}
   return true;
  }

bool MultiCostPrepareCandidate(MultiGroupState &group,const int type,
                               const double lots,const double trigger,
                               const double sl,const double strategy,
                               double &tp,double &loss,string &reason)
  {
   if(!MultiCostQuote(group,type,trigger,reason)) return false;
   const double worst=trigger+(type==OP_BUY ? 1 : -1)
                      *最大开仓滑点点数*Point;
   if(!MultiCostSolve(group,type,VolumeNormalize(lots),worst,sl,strategy,
                      tp,loss,reason)) return false;
   if(!MultiCostRisk(group,type,loss,sl,trigger,lots,reason)) return false;
   return true;
  }

bool MultiCostPairMarginAllowed(const int first_type,const double first_lots,
                                const int second_type,const double second_lots)
  {
   if(AccountFreeMarginCheck(Symbol(),first_type,first_lots)<=0.0
      || AccountFreeMarginCheck(Symbol(),second_type,second_lots)<=0.0)
      return false;
   const double required=MarketInfo(Symbol(),MODE_MARGINREQUIRED)
                         *(first_lots+second_lots);
   return required<=0.0 || AccountFreeMargin()>required;
  }

bool MultiCostQuote(MultiGroupState &group,const int type,
                    const double trigger,string &reason)
  {
   RefreshRates();
   const datetime quote_time=(datetime)MarketInfo(Symbol(),MODE_TIME);
   if(Bid<=0.0 || Ask<=Bid || quote_time<=0
      || (TimeCurrent()-quote_time)*1000>最长报价延迟毫秒)
     {group.cost_good_quotes=0;reason="STALE_QUOTE";return false;}
   const double spread=(Ask-Bid)/Point;
   if(spread>最大开仓点差点数)
     {group.cost_good_quotes=0;reason="SPREAD_ABSOLUTE";return false;}
   if(group.stop_points<=0 || spread>group.stop_points*最大点差占止损比例)
     {group.cost_good_quotes=0;reason="SPREAD_RELATIVE";return false;}
   const double quote=type==OP_BUY ? Ask : Bid;
   if((type==OP_BUY && quote>trigger+最大开仓滑点点数*Point)
      || (type==OP_SELL && quote<trigger-最大开仓滑点点数*Point))
     {group.cost_good_quotes=0;reason="ENTRY_PRICE_LIMIT";return false;}
   group.cost_good_quotes=MathMin(2,group.cost_good_quotes+1);
   if(group.cost_good_quotes<2)
     {reason="QUOTE_RECOVERY";return false;}
   return true;
  }

bool MultiCostSend(MultiGroupState &group,const int type,const double requested,
                   const double trigger,const double sl,const double strategy)
  {
   g_multi_last_send_error=0;
   string reason="";
   if(group.cost_frozen || requested<=0.0
      || requested>MarketInfo(Symbol(),MODE_MAXLOT))
     {Print("MULTI_COST_GATE: FROZEN_OR_VOLUME group=",group.id);return false;}
   if(!MultiCostQuote(group,type,trigger,reason))
     {Print("MULTI_COST_GATE: ",reason," group=",group.id);return false;}
   const double lots=VolumeNormalize(requested);
   const double quote=type==OP_BUY ? Ask : Bid;
   const double worst=trigger+(type==OP_BUY ? 1 : -1)*最大开仓滑点点数*Point;
   double tp=0.0,loss=0.0;
   if(!MultiCostSolve(group,type,lots,worst,sl,strategy,tp,loss,reason)
      || !MultiCostRisk(group,type,loss,sl,trigger,lots,reason))
     {Print("MULTI_COST_GATE: ",reason," group=",group.id);return false;}
   if(AccountFreeMarginCheck(Symbol(),type,lots)<=0.0)
     {Print("MULTI_COST_GATE: MARGIN group=",group.id);return false;}
   group.dirty=true;MultiSaveGroup(group);
   const int ticket=OrderSend(Symbol(),type,lots,quote,最大开仓滑点点数,
                              sl,tp,MultiGroupComment(group.id,false),
                              InpMagicNumber,0,clrBlue);
   if(ticket<=0)
     {g_multi_last_send_error=GetLastError();
      Print("MULTI_COST_SEND_FAILED group=",group.id," error=",g_multi_last_send_error);return false;}
   GlobalVariableSet(MultiCostTicketPrefix(group.id)+IntegerToString(ticket),1.0);
   group.cost_last_ticket=ticket;group.cost_last_type=type;
   group.cost_last_stop=sl;group.dirty=true;MultiSaveGroup(group);
   if(!OrderSelect(ticket,SELECT_BY_TICKET))
     {group.cost_frozen=true;group.dirty=true;MultiSaveGroup(group);return false;}
   const double actual=OrderOpenPrice();
   if((type==OP_BUY && actual>worst+Point*0.01)
      || (type==OP_SELL && actual<worst-Point*0.01))
     {group.cost_frozen=true;Print("MULTI_ENTRY_SLIPPAGE_EXCEEDED group=",group.id);}
   if(MathAbs(OrderStopLoss()-sl)>Point*0.5
      || MathAbs(OrderTakeProfit()-tp)>Point*0.5)
     {
      group.cost_frozen=true;
      if(!OrderModify(ticket,actual,sl,tp,0,clrNONE))
        {
         RefreshRates();
         if(!OrderClose(ticket,lots,type==OP_BUY ? Bid : Ask,最大开仓滑点点数,clrRed))
            Print("MULTI_EMERGENCY_CLOSE_FAILED group=",group.id,
                  " ticket=",ticket," error=",GetLastError());
        }
     }
   group.dirty=true;MultiSaveGroup(group);
   return true;
  }

bool MultiCostProtect(MultiGroupState &group,const int type)
  {
   string reason="";
   const double sl=MultiStopPrice(group,type);
   const double strategy=MultiTakeProfitPrice(group,type);
   double tp=0.0,loss=0.0;
   if(!MultiCostSolve(group,type,0.0,0.0,sl,strategy,tp,loss,reason))
     {group.cost_frozen=true;group.dirty=true;MultiSaveGroup(group);
      Print("MULTI_COST_FROZEN: ",reason," group=",group.id);return false;}
   if(!MultiCostRisk(group,type,loss,sl,0.0,group.grid_lots,reason))
     {group.cost_frozen=true;
      Print("MULTI_COST_FROZEN: ",reason," group=",group.id);}
   bool ok=true;
   for(int i=OrdersTotal()-1;i>=0;i--)
     {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES)
         || OrderSymbol()!=Symbol() || OrderMagicNumber()!=InpMagicNumber
         || OrderType()!=type || !MultiCostOwnsSelected(group.id)) continue;
      if(MathAbs(OrderStopLoss()-sl)<=Point*0.5
         && MathAbs(OrderTakeProfit()-tp)<=Point*0.5) continue;
      if(!OrderModify(OrderTicket(),OrderOpenPrice(),sl,tp,0,clrNONE))
        {ok=false;Print("MULTI_COST_PROTECTION_FAILED group=",group.id,
                        " ticket=",OrderTicket()," error=",GetLastError());}
     }
   for(int j=OrdersTotal()-1;j>=0;j--)
     {
      if(!OrderSelect(j,SELECT_BY_POS,MODE_TRADES)
         || OrderSymbol()!=Symbol() || OrderMagicNumber()!=InpMagicNumber
         || OrderType()!=type || !MultiCostOwnsSelected(group.id)) continue;
      if(MathAbs(OrderStopLoss()-sl)>Point*0.5
         || MathAbs(OrderTakeProfit()-tp)>Point*0.5) ok=false;
     }
   if(!ok) group.cost_frozen=true;
   group.cost_tp=tp;group.cost_last_stop=sl;
   group.dirty=true;MultiSaveGroup(group);
   return ok;
  }

void MultiCostReverse(MultiGroupState &group,const int old_type,
                      const double old_lots)
  {
   group.cumulative_loss_lots+=old_lots;
   group.previous_grid_lots=group.grid_lots;
   group.reversal_count++;
   if(group.reversal_count>最大反手次数)
     {group.active=false;group.dirty=true;MultiSaveGroup(group);return;}
   const double requested=MultiNextGroupLotsAfterStopRaw(group,old_lots);
   if(requested>MarketInfo(Symbol(),MODE_MAXLOT))
     {Print("MULTI_COST_REVERSAL_VOLUME_UNSUPPORTED group=",group.id);
      group.active=false;group.dirty=true;MultiSaveGroup(group);return;}
   group.cycle_index=(group.cycle_index+1)%CycleLength(group.cycle_mode);
   const int next_type=MultiSequenceDirection(group,group.cycle_index);
   const double quote=next_type==OP_BUY ? Ask : Bid;
   const double sl=PriceNormalize(quote+(next_type==OP_BUY ? -1 : 1)
                                  *group.stop_points*Point);
   const double strategy=PriceNormalize(quote+(next_type==OP_BUY ? 1 : -1)
                                        *group.take_profit_points*Point);
   const int prior_ticket=group.cost_last_ticket;
   group.dirty=true;MultiSaveGroup(group);
   if(!MultiCostSend(group,next_type,requested,quote,sl,strategy))
     {
      int ticket=-1,type=OP_BUY;double lots=0,entry=0,stop=0,tp=0;
      if(group.cost_last_ticket!=prior_ticket
         || MultiCostFindPosition(group.id,ticket,type,lots,entry,stop,tp))
         group.cost_frozen=true;
      else group.active=false;
      group.dirty=true;MultiSaveGroup(group);return;
     }
   int ticket=-1,type=OP_BUY;double lots=0,entry=0,stop=0,tp=0;
   if(!MultiCostFindPosition(group.id,ticket,type,lots,entry,stop,tp))
     {group.cost_frozen=true;group.dirty=true;MultiSaveGroup(group);return;}
   group.anchor_price=entry;group.last_entry=entry;group.linear_extreme=entry;
   group.first_lots=lots;group.total_lots=MultiCostTotalLots(group.id,type);
   group.grid_lots=group.previous_grid_lots>0.0
                   ? VolumeNormalize(group.previous_grid_lots*InpGridLotMultiplier)
                   : group.total_lots;
   group.grid_filled_mask=0;group.favorable_grid_filled_mask=0;
   group.cost_last_ticket=ticket;group.cost_last_type=type;
   group.dirty=true;MultiSaveGroup(group);
   MultiCostProtect(group,type);
  }

int MultiCostPassiveStopTicket(const MultiGroupState &group)
  {
   const string prefix=MultiCostTicketPrefix(group.id);
   int latest=-1;
   for(int i=0;i<GlobalVariablesTotal();i++)
     {
      const string key=GlobalVariableName(i);
      if(StringFind(key,prefix)!=0) continue;
      const int ticket=(int)StringToInteger(StringSubstr(key,StringLen(prefix)));
      if(ticket<=0 || ticket==group.cost_handled_ticket
         || !OrderSelect(ticket,SELECT_BY_TICKET)
         || OrderCloseTime()!=TimeCurrent()) continue;
      const double sl=OrderStopLoss()>0.0 ? OrderStopLoss() : group.cost_last_stop;
      if((OrderType()==OP_BUY && OrderClosePrice()<=sl+Point*0.5)
         || (OrderType()==OP_SELL && OrderClosePrice()>=sl-Point*0.5))
         latest=MathMax(latest,ticket);
     }
   return latest;
  }

void MultiCostManageGroup(MultiGroupState &group)
  {
   if(!group.active) return;
   if(group.pair_parent_id>0)
     {
      int parent_index=-1;
      for(int i=0;i<ArraySize(g_multi_groups);i++)
         if(g_multi_groups[i].id==group.pair_parent_id) {parent_index=i;break;}
      if(parent_index<0 || !g_multi_groups[parent_index].active)
        {group.active=false;group.dirty=true;MultiSaveGroup(group);return;}
      if(g_multi_groups[parent_index].launch_failed)
        {group.launch_failed=true;group.launch_error=g_multi_groups[parent_index].launch_error;
         group.active=false;group.dirty=true;MultiSaveGroup(group);return;}
      int parent_ticket=-1,parent_type=OP_BUY;
      double parent_lots=0.0,parent_entry=0.0,parent_sl=0.0,parent_tp=0.0;
      if(!MultiCostFindPosition(group.pair_parent_id,parent_ticket,parent_type,
                                parent_lots,parent_entry,parent_sl,parent_tp))
        {
         if(g_multi_groups[parent_index].launch_confirmed
            && g_multi_groups[parent_index].cost_last_ticket>0
            && OrderSelect(g_multi_groups[parent_index].cost_last_ticket,
                           SELECT_BY_TICKET,MODE_HISTORY)
            && OrderCloseTime()>0)
           {group.active=false;group.dirty=true;MultiSaveGroup(group);return;}
         return;
        }
      g_multi_groups[parent_index].launch_confirmed=true;
      g_multi_groups[parent_index].dirty=true;
      MultiSaveGroup(g_multi_groups[parent_index]);
      int child_ticket=-1,child_type=OP_BUY;
      double child_lots=0.0,child_entry=0.0,child_sl=0.0,child_tp=0.0;
      if(MultiCostFindPosition(group.id,child_ticket,child_type,child_lots,
                               child_entry,child_sl,child_tp))
        {group.launch_confirmed=true;group.pair_parent_id=0;
         group.dirty=true;MultiSaveGroup(group);}
      else if(group.cost_last_ticket>0 || group.launch_failed || group.launch_attempted)
         return;
      else
        {
         const int intended_type=group.cost_last_type;
         const double trigger=group.cost_high;
         const double initial_sl=group.cost_last_stop;
         const double strategy=group.initial_high_price;
         const double requested=group.first_lots;
         double candidate_tp=0.0,candidate_loss=0.0;string candidate_reason="";
         if(!MultiCostPrepareCandidate(group,intended_type,requested,trigger,
                                       initial_sl,strategy,candidate_tp,
                                       candidate_loss,candidate_reason))
            return;
         group.launch_attempted=true;group.dirty=true;MultiSaveGroup(group);
         const int previous_ticket=group.cost_last_ticket;
         if(!MultiCostSend(group,intended_type,requested,trigger,initial_sl,strategy))
           {
            if(MultiCostFindPosition(group.id,child_ticket,child_type,child_lots,
                                     child_entry,child_sl,child_tp))
               group.launch_confirmed=true;
            else if(g_multi_last_send_error!=0)
               MultiRecordLaunchFailure(group,g_multi_last_send_error);
            else
              {group.launch_attempted=false;group.dirty=true;MultiSaveGroup(group);}
            return;
           }
         if(group.cost_last_ticket==previous_ticket
            || !MultiCostFindPosition(group.id,child_ticket,child_type,child_lots,
                                      child_entry,child_sl,child_tp))
            return;
         group.launch_attempted=false;group.launch_confirmed=true;
         group.launch_failed=false;group.launch_error=0;
         group.launch_retry_after=0;group.launch_attempt_count=0;
         group.pair_parent_id=0;
         group.anchor_price=child_entry;group.last_entry=child_entry;
         group.linear_extreme=child_entry;group.total_lots=child_lots;
         group.grid_lots=child_lots;group.cost_last_type=child_type;
         group.dirty=true;MultiSaveGroup(group);
         MultiCostProtect(group,child_type);
         return;
        }
     }
   if(!group.cost_mode || group.cost_target<=0.0
      || group.stop_points<=0 || group.take_profit_points<=0)
     {
      group.cost_frozen=true;group.dirty=true;MultiSaveGroup(group);
      Print("MULTI_COST_LEDGER_INCOMPLETE group=",group.id);return;
     }
   int ticket=-1,type=OP_BUY;double lots=0,entry=0,sl=0,tp=0;
   const bool found=MultiCostFindPosition(group.id,ticket,type,lots,entry,sl,tp);
   if(group.cost_frozen && !found && group.cost_last_ticket<=0)
     {group.active=false;group.dirty=true;MultiSaveGroup(group);return;}
   if(found)
     {
      if(group.anchor_price<=0.0) group.anchor_price=entry;
      if(group.last_entry<=0.0) group.last_entry=entry;
      if(group.linear_extreme<=0.0) group.linear_extreme=entry;
      group.total_lots=MultiCostTotalLots(group.id,type);
      group.cost_last_type=type;
      group.cost_last_stop=MultiStopPrice(group,type);
      if(InpTakeProfitMode==TAKE_PROFIT_LINEAR)
        {
         const double quote=type==OP_BUY ? Ask : Bid;
         if((type==OP_BUY && quote<group.linear_extreme)
            || (type==OP_SELL && quote>group.linear_extreme))
            group.linear_extreme=quote;
        }
      if(!MultiCostProtect(group,type)) return;
      if((type==OP_BUY && Bid>=group.cost_tp)
         || (type==OP_SELL && Ask<=group.cost_tp))
        {
         if(MultiCostClosePositions(group.id)) group.active=false;
         group.dirty=true;MultiSaveGroup(group);return;
        }
      if((type==OP_BUY && Bid<=MultiStopPrice(group,type))
         || (type==OP_SELL && Ask>=MultiStopPrice(group,type)))
        {
         const double old_lots=group.total_lots;
         if(!MultiCostClosePositions(group.id)) return;
         MultiCostReverse(group,type,old_lots);return;
        }
      if(group.cost_frozen || InpGridCount<2) return;
      for(int level=1;level<InpGridCount;level++)
        for(int side=0;side<2;side++)
          {
           if(side==1 && FavorableGridEnable!=1) continue;
           const long bit=GridLevelBit(level);
           if((side==0 && (group.grid_filled_mask&bit)!=0)
              || (side==1 && (group.favorable_grid_filled_mask&bit)!=0)) continue;
           const double trigger=side==0 ? MultiGridLevelPrice(group,type,level)
                                          : MultiFavorableGridLevelPrice(group,type,level);
           const double quote=type==OP_BUY ? Ask : Bid;
           if((side==0 && ((type==OP_BUY && quote>trigger)
                           || (type==OP_SELL && quote<trigger)))
              || (side==1 && ((type==OP_BUY && quote<trigger)
                              || (type==OP_SELL && quote>trigger)))) continue;
           const double strategy=PriceNormalize(quote+(type==OP_BUY ? 1 : -1)
                                                 *group.take_profit_points*Point);
           if(!MultiCostSend(group,type,group.grid_lots,trigger,
                             MultiStopPrice(group,type),strategy)) return;
           double actual=quote;
           if(OrderSelect(group.cost_last_ticket,SELECT_BY_TICKET))
              actual=OrderOpenPrice();
           if(side==0)
             {group.grid_filled_mask|=bit;group.last_entry=actual;}
           else
             {group.favorable_grid_filled_mask|=bit;
              if(DynamicStopLossEnable==1) group.last_entry=actual;}
           group.total_lots=MultiCostTotalLots(group.id,type);
           group.dirty=true;MultiSaveGroup(group);
           MultiCostProtect(group,type);return;
          }
      group.dirty=true;MultiSaveGroup(group);return;
     }
   if(group.cost_last_ticket>0)
     {
      const int stop_ticket=MultiCostPassiveStopTicket(group);
      if(stop_ticket>0)
        {
         group.cost_handled_ticket=stop_ticket;
         group.dirty=true;MultiSaveGroup(group);
         MultiCostReverse(group,group.cost_last_type,group.total_lots);
         return;
        }
      group.active=false;group.dirty=true;MultiSaveGroup(group);return;
     }
   if(group.cost_bar<=0 || group.cost_high<=0.0 || group.cost_low<=0.0)
     {group.cost_frozen=true;group.dirty=true;MultiSaveGroup(group);return;}
   const bool signal_resolved=group.initial_high_ticket==-2;
   if(!signal_resolved && iTime(Symbol(),Period(),0)!=group.cost_bar)
     {group.active=false;group.dirty=true;MultiSaveGroup(group);return;}
   if(group.launch_failed || group.launch_attempted
      || group.launch_retry_after>TimeCurrent()) return;
   bool high_hit=false,low_hit=false;
   int initial_type=OP_BUY;
   double trigger=0.0,initial_sl=0.0,strategy=0.0;
   if(signal_resolved)
     {
      initial_type=group.initial_high_direction;
      trigger=group.cost_high;initial_sl=group.cost_last_stop;
      strategy=group.initial_high_price;
     }
   else
     {
      high_hit=Ask>=group.cost_high;low_hit=Bid<=group.cost_low;
      if(high_hit && low_hit)
        {Print("MULTI_COST_DUAL_TRIGGER group=",group.id);
         group.active=false;group.dirty=true;MultiSaveGroup(group);return;}
      if(!high_hit && !low_hit) return;
      initial_type=high_hit
         ? (ordertype==ORDERTYPE_FORWARD ? OP_BUY : OP_SELL)
         : (ordertype==ORDERTYPE_FORWARD ? OP_SELL : OP_BUY);
      trigger=high_hit ? group.cost_high : group.cost_low;
      const double resolve_quote=initial_type==OP_BUY ? Ask : Bid;
      initial_sl=PriceNormalize(resolve_quote+(initial_type==OP_BUY ? -1 : 1)
                                  *group.stop_points*Point);
      strategy=PriceNormalize(resolve_quote+(initial_type==OP_BUY ? 1 : -1)
                                *group.take_profit_points*Point);
      group.initial_high_ticket=-2;
      group.initial_high_direction=initial_type;
      group.cost_high=trigger;group.cost_low=trigger;
      group.cost_last_type=initial_type;group.cost_last_stop=initial_sl;
      group.initial_high_price=strategy;
      group.first_lots=VolumeNormalize(InpInitialLots);
      group.dirty=true;MultiSaveGroup(group);
     }
   group.first_direction=initial_type==OP_BUY ? FIRST_BUY : FIRST_SELL;
   const double quote=initial_type==OP_BUY ? Ask : Bid;
   const double requested=group.first_lots>0.0 ? group.first_lots
                                                : VolumeNormalize(InpInitialLots);
   if(group.pair_peer_id>0)
     {
      int peer_index=-1;
      for(int i=0;i<ArraySize(g_multi_groups);i++)
         if(g_multi_groups[i].id==group.pair_peer_id) {peer_index=i;break;}
      if(peer_index<0) {group.cost_frozen=true;group.dirty=true;MultiSaveGroup(group);return;}
      const int opposite_type=initial_type==OP_BUY ? OP_SELL : OP_BUY;
      const double opposite_quote=opposite_type==OP_BUY ? Ask : Bid;
      const double opposite_trigger=trigger;
      const double opposite_sl=PriceNormalize(opposite_quote
         +(opposite_type==OP_BUY ? -1 : 1)*group.stop_points*Point);
      const double opposite_strategy=PriceNormalize(opposite_quote
         +(opposite_type==OP_BUY ? 1 : -1)*group.take_profit_points*Point);
      g_multi_groups[peer_index].cost_high=opposite_trigger;
      g_multi_groups[peer_index].cost_low=opposite_trigger;
      g_multi_groups[peer_index].cost_last_type=opposite_type;
      g_multi_groups[peer_index].cost_last_stop=opposite_sl;
      g_multi_groups[peer_index].initial_high_price=opposite_strategy;
      g_multi_groups[peer_index].first_lots=requested;
      g_multi_groups[peer_index].stop_points=group.stop_points;
      g_multi_groups[peer_index].take_profit_points=group.take_profit_points;
      g_multi_groups[peer_index].cost_target=group.cost_target;
      g_multi_groups[peer_index].initial_high_ticket=-2;
      g_multi_groups[peer_index].initial_high_direction=opposite_type;
      g_multi_groups[peer_index].launch_event_id=group.id;
      g_multi_groups[peer_index].cost_bar=group.cost_bar;
      g_multi_groups[peer_index].dirty=true;MultiSaveGroup(g_multi_groups[peer_index]);
      double first_tp=0.0,first_loss=0.0,peer_tp=0.0,peer_loss=0.0;
      string pair_reason="";
      if(!MultiCostPrepareCandidate(group,initial_type,requested,trigger,
                                    initial_sl,strategy,first_tp,first_loss,pair_reason)
         || !MultiCostPrepareCandidate(g_multi_groups[peer_index],opposite_type,requested,opposite_trigger,
                                       opposite_sl,opposite_strategy,peer_tp,peer_loss,
                                       pair_reason)
         || !MultiCostPairMarginAllowed(initial_type,requested,
                                         opposite_type,requested))
        {Print("MULTI_COST_PAIR_PREFLIGHT_FAILED group=",group.id,
               " event=",group.launch_event_id," reason=",
               pair_reason=="" ? "PAIR_MARGIN" : pair_reason);
         return;}
      g_multi_groups[peer_index].cost_good_quotes=2;
      g_multi_groups[peer_index].dirty=true;MultiSaveGroup(g_multi_groups[peer_index]);
     }
   const int prior_ticket=group.cost_last_ticket;
   group.launch_attempted=true;group.dirty=true;MultiSaveGroup(group);
   if(!MultiCostSend(group,initial_type,requested,trigger,initial_sl,strategy))
     {
      if(MultiCostFindPosition(group.id,ticket,type,lots,entry,sl,tp))
        {group.launch_attempted=false;group.launch_confirmed=true;}
      else if(g_multi_last_send_error!=0)
         MultiRecordLaunchFailure(group,g_multi_last_send_error);
      else {group.launch_attempted=false;group.dirty=true;MultiSaveGroup(group);}
      if(group.cost_last_ticket!=prior_ticket) group.cost_frozen=true;
      group.dirty=true;MultiSaveGroup(group);return;
     }
   if(!MultiCostFindPosition(group.id,ticket,type,lots,entry,sl,tp))
     {group.cost_frozen=true;group.dirty=true;MultiSaveGroup(group);return;}
   group.anchor_price=entry;group.last_entry=entry;group.linear_extreme=entry;
   group.first_lots=lots;group.total_lots=MultiCostTotalLots(group.id,type);
   group.grid_lots=group.total_lots;
   group.cost_last_ticket=ticket;group.cost_last_type=type;
   group.launch_attempted=false;group.launch_confirmed=true;
   group.launch_failed=false;group.launch_error=0;
   group.launch_retry_after=0;group.launch_attempt_count=0;
   group.dirty=true;MultiSaveGroup(group);
   MultiCostProtect(group,type);
  }

void MultiCostCleanupTickets(const int group_id)
  {
   const string prefix=MultiCostTicketPrefix(group_id);
   for(int i=GlobalVariablesTotal()-1;i>=0;i--)
     {
      const string key=GlobalVariableName(i);
      if(StringFind(key,prefix)==0) GlobalVariableDel(key);
     }
  }

void MultiCostManageGroups()
  {
   RefreshRates();
   for(int order_index=OrdersTotal()-1;order_index>=0;order_index--)
     {
      if(!OrderSelect(order_index,SELECT_BY_POS,MODE_TRADES)
         || OrderSymbol()!=Symbol() || OrderMagicNumber()!=InpMagicNumber
         || (OrderType()!=OP_BUY && OrderType()!=OP_SELL)) continue;
      bool mapped=false;
      for(int group_index=0;group_index<ArraySize(g_multi_groups);group_index++)
         if(g_multi_groups[group_index].active
            && MultiCostOwnsSelected(g_multi_groups[group_index].id))
            mapped=true;
      if(mapped) continue;
      for(int freeze_index=0;freeze_index<ArraySize(g_multi_groups);freeze_index++)
        {g_multi_groups[freeze_index].cost_frozen=true;
         g_multi_groups[freeze_index].dirty=true;
         MultiSaveGroup(g_multi_groups[freeze_index]);}
      Print("MULTI_COST_LEDGER_INCOMPLETE: unmapped live ticket=",OrderTicket());
      return;
     }
   if(HasOurPending())
     {
      DeleteAllPending();
      for(int k=0;k<ArraySize(g_multi_groups);k++)
        {g_multi_groups[k].cost_frozen=true;g_multi_groups[k].dirty=true;
         MultiSaveGroup(g_multi_groups[k]);}
      Print("MULTI_COST_LEGACY_PENDING: all new entries frozen.");
      return;
     }
   for(int i=ArraySize(g_multi_groups)-1;i>=0;i--)
     {
      MultiCostManageGroup(g_multi_groups[i]);
      if(!g_multi_groups[i].active)
        {
         int ticket=-1,type=OP_BUY;double lots=0,entry=0,sl=0,tp=0;
         if(MultiCostFindPosition(g_multi_groups[i].id,ticket,type,lots,entry,sl,tp))
           {g_multi_groups[i].cost_frozen=true;g_multi_groups[i].active=true;
            g_multi_groups[i].dirty=true;MultiSaveGroup(g_multi_groups[i]);continue;}
         MultiCostCleanupTickets(g_multi_groups[i].id);
         MultiRemoveGroup(i);
        }
     }
    if(篮子数量==2 && MultiHasActiveGroups()) return;
    if(!IsInitialEntryAllowed()) return;
   const datetime bar=iTime(Symbol(),Period(),0);
   if(bar<=0 || (Korder_type==KORDER_ONCE_PER_BAR
      && InpDistanceMode==DISTANCE_CANDLE_RANGE
      && bar==g_multi_last_trigger_bar)) return;
   const bool direct_signal=InpDistanceMode!=DISTANCE_CANDLE_RANGE;
   if(direct_signal && MultiHasActiveGroups()) return;
   double high=0.0,low=0.0;int range=0,tp_range=0;int resolved_type=OP_BUY;
   if(direct_signal)
     {
      if(InpDistanceMode==DISTANCE_LONG_CANDLE)
        {if(!GetLongCandleDirection(resolved_type)) return;}
      else if(首单方向确定方式==FIRST_DIRECTION_BOLLINGER)
        {if(!GetBollingerFirstDirection(resolved_type)) return;}
      else resolved_type=InpFirstDirection==FIRST_SELL ? OP_SELL : OP_BUY;
      if(!GetDistancePoints(range,tp_range) || range<=0 || tp_range<=0) return;
      const double quote=resolved_type==OP_BUY ? Ask : Bid;
      high=quote;low=quote;
     }
   else
     {
      if(!GetPreviousCandleRange(high,low,range)) return;
      if(Korder_type==KORDER_REPEAT_PER_BAR && Ask<high && Bid>low) return;
     }
   const int index=ArraySize(g_multi_groups);
   const bool paired_cost=篮子数量==2;
   if(ArrayResize(g_multi_groups,index+(paired_cost ? 2 : 1))
      !=index+(paired_cost ? 2 : 1)) return;
   MultiGroupState state;
   const int id=g_multi_next_id++;
   MultiResetState(state,id);
   state.cost_mode=true;state.cost_start=TimeCurrent();
   state.cost_target=目标净盈亏比>0.0 ? 目标净盈亏比 : 1.0;
   state.cost_high=PriceNormalize(high);state.cost_low=PriceNormalize(low);
   state.cost_bar=bar;state.stop_points=range;
   state.take_profit_points=direct_signal ? tp_range : range;
   if(direct_signal)
     {
      const double quote=resolved_type==OP_BUY ? Ask : Bid;
      state.cost_target=目标净盈亏比>0.0 ? 目标净盈亏比
                                          : (double)tp_range/range;
      state.initial_high_ticket=-2;state.initial_high_direction=resolved_type;
      state.first_direction=resolved_type==OP_BUY ? FIRST_BUY : FIRST_SELL;
      state.cost_last_type=resolved_type;
      state.cost_last_stop=PriceNormalize(quote+(resolved_type==OP_BUY ? -1 : 1)
                                          *range*Point);
      state.initial_high_price=PriceNormalize(quote+(resolved_type==OP_BUY ? 1 : -1)
                                              *tp_range*Point);
      state.first_lots=VolumeNormalize(InpInitialLots);
     }
   int peer_id=-1;
   if(paired_cost)
     {
      peer_id=g_multi_next_id++;
      state.pair_peer_id=peer_id;state.launch_event_id=id;
      MultiGroupState peer;
      MultiResetState(peer,peer_id);
      peer.cost_mode=true;peer.cost_start=state.cost_start;
      peer.cost_target=state.cost_target;peer.cost_high=state.cost_high;
      peer.cost_low=state.cost_low;peer.cost_bar=bar;
      peer.stop_points=range;peer.take_profit_points=range;
      peer.pair_parent_id=id;peer.launch_event_id=id;
      g_multi_groups[index+1]=peer;
     }
   g_multi_groups[index]=state;
   bool candidate_ok=true;
   for(int side=0;side<2;side++)
     {
      const int base_type=direct_signal ? resolved_type
         : (ordertype==ORDERTYPE_FORWARD ? OP_BUY : OP_SELL);
      const int type=side==0 ? base_type
                             : (base_type==OP_BUY ? OP_SELL : OP_BUY);
      const double trigger=side==0 ? state.cost_high : state.cost_low;
      const int sign=type==OP_BUY ? 1 : -1;
      const double worst=trigger+sign*最大开仓滑点点数*Point;
      const double sl=PriceNormalize(trigger-sign*range*Point);
      const double strategy=PriceNormalize(trigger+sign*state.take_profit_points*Point);
      double tp=0.0,loss=0.0;string reason="";
      if(!MultiCostSolve(state,type,VolumeNormalize(InpInitialLots),worst,
                         sl,strategy,tp,loss,reason)
         || !MultiCostRisk(state,type,loss,sl,trigger,InpInitialLots,reason))
        {Print("MULTI_COST_TRIGGER_REJECTED group=",id," reason=",reason);
         candidate_ok=false;break;}
     }
   if(!candidate_ok)
     {if(paired_cost) MultiDeleteState(peer_id);
      MultiDeleteState(id);ArrayResize(g_multi_groups,index);return;}
   g_multi_groups[index].dirty=true;MultiSaveGroup(g_multi_groups[index]);
   if(paired_cost)
      MultiSaveGroup(g_multi_groups[index+1]);
   if(Korder_type==KORDER_ONCE_PER_BAR) MarkMultiCandleTriggerBar();
  }

bool MultiHasActiveGroups()
  {
   for(int index=0; index<ArraySize(g_multi_groups); index++)
      if(g_multi_groups[index].active)
         return true;
   return false;
  }

bool MultiHasActiveCostGroups()
  {
   for(int index=0;index<ArraySize(g_multi_groups);index++)
      if(g_multi_groups[index].active && g_multi_groups[index].cost_mode)
         return true;
   return false;
  }

void StartResolvedMultiPair(const int first_type, const int stop_points,
                            const int take_profit_points, const double lots)
  {
   if(first_type != OP_BUY && first_type != OP_SELL)
      return;
   if(stop_points <= 0 || take_profit_points <= 0 || lots <= 0.0
      || !IsInitialSpreadAllowed())
      return;
   const int original_index=ArraySize(g_multi_groups);
   if(ArrayResize(g_multi_groups,original_index+2)!=original_index+2)
      return;
   const int original_id=g_multi_next_id++;
   const int opposite_id=g_multi_next_id++;
   MultiGroupState original;
   MultiGroupState opposite;
   MultiResetState(original,original_id);
   MultiResetState(opposite,opposite_id);
   original.first_direction=first_type==OP_BUY ? FIRST_BUY : FIRST_SELL;
   opposite.first_direction=first_type==OP_BUY ? FIRST_SELL : FIRST_BUY;
   opposite.pair_parent_id=original_id;
   original.launch_event_id=original_id;
   opposite.launch_event_id=original_id;
   original.cycle_mode=InpCycleMode;
   opposite.cycle_mode=InpCycleMode;
   original.stop_points=stop_points;
   opposite.stop_points=stop_points;
   original.take_profit_points=take_profit_points;
   opposite.take_profit_points=take_profit_points;
   original.transition_target_lots=VolumeNormalize(lots);
   opposite.transition_target_lots=VolumeNormalize(lots);
   // Persist both identities and their intended first-order size before either send.
   g_multi_groups[original_index]=original;
   g_multi_groups[original_index+1]=opposite;
   MultiSaveGroup(g_multi_groups[original_index]);
   MultiSaveGroup(g_multi_groups[original_index+1]);
   MultiManageGroup(g_multi_groups[original_index]);
   if(g_multi_groups[original_index].dirty)
      MultiSaveGroup(g_multi_groups[original_index]);
   if(!g_reset_pending)
     {
      MultiManageGroup(g_multi_groups[original_index+1]);
      if(g_multi_groups[original_index+1].dirty)
         MultiSaveGroup(g_multi_groups[original_index+1]);
     }
  }

bool StartInitialMultiOco(const double previous_high, const double previous_low,
                          const int range_points, const double lots)
  {
   const int index=ArraySize(g_multi_groups);
   if(ArrayResize(g_multi_groups,index+2)!=index+2) return false;
   const int high_id=g_multi_next_id++;
   const int low_id=g_multi_next_id++;
   MultiGroupState high_group,low_group;
   MultiResetState(high_group,high_id);MultiResetState(low_group,low_id);
   high_group.first_direction=ordertype==ORDERTYPE_FORWARD ? FIRST_BUY : FIRST_SELL;
   low_group.first_direction=ordertype==ORDERTYPE_FORWARD ? FIRST_SELL : FIRST_BUY;
   high_group.cycle_mode=InpCycleMode;low_group.cycle_mode=InpCycleMode;
   high_group.stop_points=range_points;low_group.stop_points=range_points;
   high_group.take_profit_points=range_points;low_group.take_profit_points=range_points;
   high_group.first_lots=VolumeNormalize(lots);low_group.first_lots=VolumeNormalize(lots);
   high_group.pair_peer_id=low_id;low_group.pair_peer_id=high_id;
   high_group.launch_event_id=high_id;low_group.launch_event_id=high_id;
   high_group.initial_high_price=PriceNormalize(previous_high);
   low_group.initial_low_price=PriceNormalize(previous_low);
   g_multi_groups[index]=high_group;g_multi_groups[index+1]=low_group;
   MultiSaveGroup(g_multi_groups[index]);MultiSaveGroup(g_multi_groups[index+1]);
   int high_ticket=-1,low_ticket=-1;
   const int high_type=ordertype==ORDERTYPE_FORWARD ? OP_BUY : OP_SELL;
   const int low_type=ordertype==ORDERTYPE_FORWARD ? OP_SELL : OP_BUY;
   g_multi_groups[index].launch_attempted=true;
   g_multi_groups[index].dirty=true;MultiSaveGroup(g_multi_groups[index]);
   g_multi_last_send_error=0;
   if(!PlaceInitialPendingOrder(high_type,previous_high,range_points,lots,
                                MultiInitialPendingComment(high_id,true),high_ticket))
     {if(g_multi_last_send_error==128){MarkMultiCandleTriggerBar();return true;}
      MultiRemoveGroup(index+1);MultiRemoveGroup(index);return false;}
   g_multi_groups[index+1].launch_attempted=true;
   g_multi_groups[index+1].dirty=true;MultiSaveGroup(g_multi_groups[index+1]);
   g_multi_last_send_error=0;
   if(!PlaceInitialPendingOrder(low_type,previous_low,range_points,lots,
                                MultiInitialPendingComment(low_id,false),low_ticket))
     {
      if(g_multi_last_send_error==128)
        {g_multi_groups[index].initial_high_ticket=high_ticket;
         g_multi_groups[index].launch_attempted=false;
         g_multi_groups[index].dirty=true;MultiSaveGroup(g_multi_groups[index]);
         g_multi_groups[index+1].launch_attempted=true;
         g_multi_groups[index+1].dirty=true;MultiSaveGroup(g_multi_groups[index+1]);
         MarkMultiCandleTriggerBar();return true;}
      ResetLastError();
      if(high_ticket>0 && !OrderDelete(high_ticket,clrRed))
        {const int rollback_error=GetLastError();
         const int rejected_leg_error=g_multi_last_send_error;
         g_multi_groups[index].initial_high_ticket=high_ticket;
         g_multi_groups[index].pair_peer_id=-1;
         g_multi_groups[index].launch_attempted=false;
         g_multi_groups[index].launch_failed=true;
         g_multi_groups[index].launch_error=rejected_leg_error;
         g_multi_groups[index].launch_event_id=high_id;
         g_multi_groups[index].launch_log_time=TimeCurrent();
         g_multi_groups[index].dirty=true;MultiSaveGroup(g_multi_groups[index]);
         Print("Multi OCO partial pair failure, group=",high_id,
               ", event=",high_id,", missing_group=",low_id,
               ", send_error=",rejected_leg_error,
               ", rollback_error=",rollback_error,
               ", surviving_ticket=",high_ticket);
         MultiRemoveGroup(index+1);MarkMultiCandleTriggerBar();return true;}
      MultiRemoveGroup(index+1);MultiRemoveGroup(index);return false;
     }
   g_multi_groups[index].initial_high_ticket=high_ticket;
   g_multi_groups[index].launch_attempted=false;
   g_multi_groups[index].dirty=true;MultiSaveGroup(g_multi_groups[index]);
   g_multi_groups[index+1].initial_low_ticket=low_ticket;
   g_multi_groups[index+1].launch_attempted=false;
   g_multi_groups[index+1].dirty=true;MultiSaveGroup(g_multi_groups[index+1]);
   MarkMultiCandleTriggerBar();
   return true;
  }

void ManageAllMultiGroups()
  {
   for(int index=ArraySize(g_multi_groups)-1; index>=0; index--)
     {
      if(!g_multi_groups[index].active)
        {
         MultiRemoveGroup(index);
         continue;
        }
      MultiGroupState before=g_multi_groups[index];
      if(g_multi_groups[index].cost_mode)
         MultiCostManageGroup(g_multi_groups[index]);
      else
         MultiManageGroup(g_multi_groups[index]);
      if(MultiStateChanged(before,g_multi_groups[index]))
         g_multi_groups[index].dirty=true;
      if(!g_multi_groups[index].active)
         MultiRemoveGroup(index);
      else if(g_multi_groups[index].dirty)
         MultiSaveGroup(g_multi_groups[index]);
      if(g_reset_pending)
         return;
     }
  }

// The cost path is intentionally independent of the legacy server pending-order
// path.  A terminal outage can miss a virtual entry; protective exits remain
// on the server.  All cash values below are in the account deposit currency.
bool CostMode() { return 启用XAU净盈亏比 && !g_cost_wait_flat; }

string CostKey(const string name) { return StatePrefix() + ".netrr." + name; }

void CostSave()
  {
   GlobalVariableSet(CostKey("active"), g_cost_active ? 1.0 : 0.0);
   GlobalVariableSet(CostKey("frozen"), g_cost_frozen ? 1.0 : 0.0);
   GlobalVariableSet(CostKey("start"), (double)g_cost_cycle_start);
   GlobalVariableSet(CostKey("id"), (double)g_cost_cycle_id);
   GlobalVariableSet(CostKey("target"), g_cost_target);
   GlobalVariableSet(CostKey("tp"), g_cost_tp);
   GlobalVariableSet(CostKey("high"), g_cost_high);
   GlobalVariableSet(CostKey("low"), g_cost_low);
   GlobalVariableSet(CostKey("bar"), (double)g_cost_trigger_bar);
   GlobalVariableSet(CostKey("ticket"), g_cost_last_ticket);
   GlobalVariableSet(CostKey("type"), g_cost_last_type);
   GlobalVariableSet(CostKey("stop"), g_cost_last_stop);
   GlobalVariableSet(CostKey("handled"),g_cost_last_closed_handled);
   SaveState();
  }

void CostLoad()
  {
   if(!GlobalVariableCheck(CostKey("active"))) return;
   g_cost_active = GlobalVariableGet(CostKey("active")) > 0.5;
   g_cost_frozen = GlobalVariableGet(CostKey("frozen")) > 0.5;
   g_cost_cycle_start = (datetime)GlobalVariableGet(CostKey("start"));
   if(GlobalVariableCheck(CostKey("id")))
      g_cost_cycle_id=(long)GlobalVariableGet(CostKey("id"));
   g_cost_target = GlobalVariableGet(CostKey("target"));
   g_cost_tp = GlobalVariableGet(CostKey("tp"));
   g_cost_high = GlobalVariableGet(CostKey("high"));
   g_cost_low = GlobalVariableGet(CostKey("low"));
   g_cost_trigger_bar = (datetime)GlobalVariableGet(CostKey("bar"));
   if(GlobalVariableCheck(CostKey("ticket")))
      g_cost_last_ticket=(int)GlobalVariableGet(CostKey("ticket"));
   if(GlobalVariableCheck(CostKey("type")))
      g_cost_last_type=(int)GlobalVariableGet(CostKey("type"));
   if(GlobalVariableCheck(CostKey("stop")))
      g_cost_last_stop=GlobalVariableGet(CostKey("stop"));
   if(GlobalVariableCheck(CostKey("handled")))
      g_cost_last_closed_handled=(int)GlobalVariableGet(CostKey("handled"));
   if(g_cost_active && (g_cost_cycle_id<=0 || g_cost_cycle_start <= 0 || g_cost_target <= 0.0
      || g_group_stop_points <= 0 || g_group_take_profit_points <= 0))
     {
      g_cost_frozen = true;
      Print("COST_LEDGER_INCOMPLETE: restored cycle metadata is missing; entries frozen.");
     }
  }

void CostClear()
  {
   // Only a flat, completed cycle calls this.  Keep all ticket mapping while
   // an uncertain send or live position is being reconciled.
   if(HasOurPosition())
     {g_cost_frozen=true;CostSave();return;}
   const string ticket_prefix=CostKey("ticket.");
   for(int i=GlobalVariablesTotal()-1;i>=0;i--)
     {
      const string key=GlobalVariableName(i);
      if(StringFind(key,ticket_prefix)==0
         && (long)GlobalVariableGet(key)==g_cost_cycle_id)
         GlobalVariableDel(key);
     }
   GlobalVariableDel(CostKey("active")); GlobalVariableDel(CostKey("frozen"));
   GlobalVariableDel(CostKey("id"));
   GlobalVariableDel(CostKey("start")); GlobalVariableDel(CostKey("target"));
   GlobalVariableDel(CostKey("tp")); GlobalVariableDel(CostKey("high"));
   GlobalVariableDel(CostKey("low")); GlobalVariableDel(CostKey("bar"));
   GlobalVariableDel(CostKey("ticket"));GlobalVariableDel(CostKey("type"));
   GlobalVariableDel(CostKey("stop"));
   GlobalVariableDel(CostKey("handled"));
   g_cost_active = false; g_cost_frozen = false; g_cost_cycle_start = 0;
   g_cost_cycle_id=0;
   g_cost_target = 0.0; g_cost_tp = 0.0; g_cost_high = 0.0;
   g_cost_low = 0.0; g_cost_trigger_bar = 0;
   g_cost_last_ticket=-1;g_cost_last_stop=0.0;
   g_cost_last_closed_handled=-1;
   ClearState();
  }

double CostTickSize()
  {
   const double tick_points = MarketInfo(Symbol(), MODE_TICKSIZE);
   return tick_points > 0.0 ? tick_points * Point : 0.0;
  }

double CostMoneyPerPriceUnit()
  {
   const double tick = CostTickSize();
   const double value = MarketInfo(Symbol(), MODE_TICKVALUE);
   if(tick <= 0.0 || value <= 0.0 || !MathIsValidNumber(value)) return 0.0;
   return value / tick;
  }

double CostPriceProfit(const int type, const double lots,
                       const double entry, const double exit_price)
  {
   const double direction = type == OP_BUY ? 1.0 : -1.0;
   return direction * (exit_price - entry) * lots * CostMoneyPerPriceUnit();
  }

string CostTicketKey(const int ticket)
  { return CostKey("ticket."+IntegerToString(ticket)); }

bool CostHistoryCash(double &cash)
  {
   cash=0.0;
   const string prefix=CostKey("ticket.");
   int mapped=0,closed=0;
   for(int i=0;i<GlobalVariablesTotal();i++)
     {
      const string key=GlobalVariableName(i);
      if(StringFind(key,prefix)!=0 || (long)GlobalVariableGet(key)!=g_cost_cycle_id)
         continue;
      mapped++;
      const int ticket=(int)StringToInteger(StringSubstr(key,StringLen(prefix)));
      if(ticket<=0 || !OrderSelect(ticket,SELECT_BY_TICKET)
         || OrderSymbol()!=Symbol() || OrderMagicNumber()!=InpMagicNumber
         || (OrderType()!=OP_BUY && OrderType()!=OP_SELL))
         return false;
      if(OrderCloseTime()==0) continue;
      closed++;
      const double paid=OrderCommission();
      const double remaining=MathMax(0.0,每手往返佣金费用预算*OrderLots()
                                      -MathMax(0.0,-paid));
      cash+=OrderProfit()+paid+OrderSwap()-remaining;
     }
   if(g_reversal_count>0 && closed==0) return false;
   for(int j=0;j<OrdersTotal();j++)
     {
      if(!OrderSelect(j,SELECT_BY_POS,MODE_TRADES)||!IsOurMarketOrder()) continue;
      if(g_cost_cycle_id<=0 || !GlobalVariableCheck(CostTicketKey(OrderTicket()))
         || (long)GlobalVariableGet(CostTicketKey(OrderTicket()))!=g_cost_cycle_id)
         return false;
     }
   return mapped>0 || g_cost_last_ticket<=0;
  }

bool CostQuote(const int type, const double trigger_price, string &reason)
  {
   RefreshRates();
   const datetime quote_time = (datetime)MarketInfo(Symbol(), MODE_TIME);
   if(Bid<=0.0 || Ask<=Bid || quote_time<=0
      || (TimeCurrent()-quote_time)*1000 > 最长报价延迟毫秒)
     { g_cost_good_quotes=0; reason="STALE_QUOTE"; return false; }
   const double spread=(Ask-Bid)/Point;
   if(spread>最大开仓点差点数)
     { g_cost_good_quotes=0; reason="SPREAD_ABSOLUTE"; return false; }
   if(g_group_stop_points<=0 || spread>最大点差占止损比例*g_group_stop_points)
     { g_cost_good_quotes=0; reason="SPREAD_RELATIVE"; return false; }
   const double price=type==OP_BUY ? Ask : Bid;
   if(trigger_price>0.0 && ((type==OP_BUY && price>trigger_price+最大开仓滑点点数*Point)
      || (type==OP_SELL && price<trigger_price-最大开仓滑点点数*Point)))
     { g_cost_good_quotes=0;reason="ENTRY_PRICE_LIMIT"; return false; }
   g_cost_good_quotes=MathMin(2,g_cost_good_quotes+1);
   if(g_cost_good_quotes<2) { reason="QUOTE_RECOVERY"; return false; }
   return true;
  }

// Includes actually paid fees once; the remaining round-trip budget is kept
// until the broker has booked it.  MT4 exposes no separate DEAL_FEE field.
bool CostOutcomes(const int type, const double extra_lots, const double extra_entry,
                  const double sl, const double tp, double &profit, double &loss)
  {
   if(CostMoneyPerPriceUnit()<=0.0 || sl<=0.0 || tp<=0.0) return false;
   if(!CostHistoryCash(profit)) return false;
   loss=profit;
   double lots_total=0.0;
   for(int i=0; i<OrdersTotal(); i++)
     {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES) || !IsOurMarketOrder()) continue;
      if(OrderType()!=type) return false;
      const double lots=OrderLots();
      const double paid=OrderCommission()+OrderSwap();
      const double remaining=MathMax(0.0, 每手往返佣金费用预算*lots
                                      - MathMax(0.0, -OrderCommission()));
      profit += CostPriceProfit(type,lots,OrderOpenPrice(),tp)+paid-remaining;
      loss += CostPriceProfit(type,lots,OrderOpenPrice(),sl)+paid-remaining;
      lots_total+=lots;
     }
   if(extra_lots>0.0)
     {
      profit+=CostPriceProfit(type,extra_lots,extra_entry,tp)
              -每手往返佣金费用预算*extra_lots;
      loss+=CostPriceProfit(type,extra_lots,extra_entry,sl)
            -每手往返佣金费用预算*extra_lots;
      lots_total+=extra_lots;
     }
   const double exit_slip=预计平仓滑点点数*Point*lots_total*CostMoneyPerPriceUnit();
   profit-=exit_slip; loss-=exit_slip;
   return lots_total>0.0;
  }

bool CostSolve(const int type, const double lots, const double entry,
               const double sl, const double strategy_tp, double &out_tp,
               double &out_loss, string &reason)
  {
   const double tick=CostTickSize();
   if(tick<=0.0 || g_cost_target<=0.0) { reason="CONTRACT_UNAVAILABLE"; return false; }
   const double max_move=MathMin(最大止盈补偿点数*Point,
                      g_group_take_profit_points*Point*最大止盈补偿比例);
   const int sign=type==OP_BUY ? 1 : -1;
   double cash=0.0;
   out_tp=type==OP_BUY ? MathCeil((strategy_tp-1e-10)/tick)*tick
                       : MathFloor((strategy_tp+1e-10)/tick)*tick;
   out_tp=NormalizeDouble(out_tp,Digits);
   const int max_steps=(int)MathCeil(max_move/tick)+2;
   for(int step=0; step<=max_steps; step++)
     {
      if(sign*(out_tp-strategy_tp)>max_move+tick*0.01) break;
      if(!CostOutcomes(type,lots,entry,sl,out_tp,cash,out_loss))
        { reason="COST_LEDGER_INCOMPLETE"; return false; }
      if(cash>0.0 && (out_loss>=0.0 || cash+0.000001>=g_cost_target*(-out_loss)))
         return true;
      out_tp=NormalizeDouble(out_tp+sign*tick,Digits);
     }
   reason="TARGET_INFEASIBLE";
   return false;
  }

bool CostRiskAllowed(const int type, const double loss, const double sl,
                     const double fallback_grid_lots,
                     const double candidate_trigger, string &reason)
  {
   if(AccountEquity()<=0.0) { reason="EQUITY_UNAVAILABLE"; return false; }
   double scenario_loss=loss;
   if(InpGridCount>=2)
     {
      const int sign=type==OP_BUY ? 1 : -1;
      const double anchor=g_group_anchor_price>0.0 ? g_group_anchor_price
                           : (type==OP_BUY ? Ask : Bid);
      const double grid_lots=g_grid_lots>0.0 ? g_grid_lots : fallback_grid_lots;
      if(anchor<=0.0 || grid_lots<=0.0)
        {reason="RISK_SCENARIO_UNAVAILABLE";return false;}
      for(int level=1;level<InpGridCount;level++)
        for(int side=0;side<2;side++)
          {
           if(side==1 && FavorableGridEnable!=1) continue;
           const long bit=GridLevelBit(level);
           if((side==0 && (g_grid_filled_mask&bit)!=0)
              || (side==1 && (g_favorable_grid_filled_mask&bit)!=0)) continue;
           const double distance=g_group_stop_points*Point*level/InpGridCount;
           const double trigger=PriceNormalize(anchor+(side==0 ? -sign : sign)*distance);
           if(candidate_trigger>0.0
              && MathAbs(trigger-candidate_trigger)<=Point*0.5) continue;
           if((type==OP_BUY && trigger<=sl) || (type==OP_SELL && trigger>=sl))
              continue;
           const double worst=trigger+sign*最大开仓滑点点数*Point;
           scenario_loss+=CostPriceProfit(type,grid_lots,worst,sl)
                          -每手往返佣金费用预算*grid_lots
                          -预计平仓滑点点数*Point*grid_lots*CostMoneyPerPriceUnit();
          }
     }
   const double cap=MathMin(单轮最大预计亏损权益比例,
                             全部轮次最大预计亏损权益比例)*AccountEquity();
   if(-MathMin(loss,scenario_loss)>cap+0.000001)
     { reason="RISK_LOOKAHEAD_LIMIT"; return false; }
   return true;
  }

bool CostSend(const int type, const double requested_lots,
              const double trigger, const double sl, const double strategy_tp)
  {
   string reason="";
   if(g_cost_frozen) { Print("COST_FROZEN: new exposure denied"); return false; }
   if(!CostQuote(type,trigger,reason))
     { Print("COST_GATE: ",reason); return false; }
   if(requested_lots>MarketInfo(Symbol(),MODE_MAXLOT))
     {Print("COST_GATE: VOLUME_LIMIT");return false;}
   const double lots=VolumeNormalize(requested_lots);
   const double quote=type==OP_BUY ? Ask : Bid;
   const double worst=(trigger>0.0 ? trigger : quote)
                      +(type==OP_BUY ? 1 : -1)*最大开仓滑点点数*Point;
   double tp=0.0, loss=0.0;
   if(!CostSolve(type,lots,worst,sl,strategy_tp,tp,loss,reason)
      || !CostRiskAllowed(type,loss,sl,lots,trigger,reason))
     { Print("COST_GATE: ",reason); return false; }
   if(AccountFreeMarginCheck(Symbol(),type,lots)<=0.0)
     { Print("COST_GATE: MARGIN"); return false; }
   const int ticket=OrderSend(Symbol(),type,lots,quote,最大开仓滑点点数,
                              sl,tp,InpOrderComment,InpMagicNumber,0,clrBlue);
   if(ticket<=0) { Print("COST_SEND_FAILED: ",GetLastError()); return false; }
   GlobalVariableSet(CostTicketKey(ticket),(double)g_cost_cycle_id);
   g_cost_last_ticket=ticket;g_cost_last_type=type;g_cost_last_stop=sl;
   if(!OrderSelect(ticket,SELECT_BY_TICKET))
     { g_cost_frozen=true; CostSave(); return false; }
   const double actual=OrderOpenPrice();
   g_cost_last_ticket=ticket;g_cost_last_type=type;g_cost_last_stop=sl;
   if((type==OP_BUY && actual>worst+Point*0.01)
      || (type==OP_SELL && actual<worst-Point*0.01))
     { g_cost_frozen=true; Print("ENTRY_SLIPPAGE_EXCEEDED: ticket=",ticket); }
   if(MathAbs(OrderStopLoss()-sl)>Point*0.5
      || MathAbs(OrderTakeProfit()-tp)>Point*0.5)
     {
      g_cost_frozen=true;
      Print("PROTECTION_UNVERIFIED: ticket=",ticket,"; attempting immediate protection.");
      if(!OrderModify(ticket,actual,sl,tp,0,clrNONE))
        {
         Print("PROTECTION_MODIFY_FAILED: ",GetLastError(),"; attempting emergency close.");
         RefreshRates();
         if(!OrderClose(ticket,lots,type==OP_BUY ? Bid : Ask,最大开仓滑点点数,clrRed))
            Print("EMERGENCY_CLOSE_FAILED: ticket=",ticket,", error=",GetLastError());
        }
     }
   CostSave();
   return true;
  }

bool CostProtect(const int type)
  {
   string reason="";
   const double sl=GroupStopPrice(type);
   const double strategy_tp=type==OP_BUY
      ? PriceNormalize((InpTakeProfitMode==TAKE_PROFIT_LINEAR ? g_group_linear_extreme : g_group_last_entry)
                       +g_group_take_profit_points*Point)
      : PriceNormalize((InpTakeProfitMode==TAKE_PROFIT_LINEAR ? g_group_linear_extreme : g_group_last_entry)
                       -g_group_take_profit_points*Point);
   double tp=0.0, loss=0.0;
   if(!CostSolve(type,0.0,0.0,sl,strategy_tp,tp,loss,reason)
      || !CostRiskAllowed(type,loss,sl,g_group_first_lots,0.0,reason))
     { g_cost_frozen=true; CostSave(); Print("COST_FROZEN: ",reason); return false; }
   bool ok=true;
   for(int i=OrdersTotal()-1;i>=0;i--)
     {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES)||!IsOurMarketOrder()) continue;
      if(MathAbs(OrderStopLoss()-sl)<Point*0.5 && MathAbs(OrderTakeProfit()-tp)<Point*0.5)
         continue;
      if(!OrderModify(OrderTicket(),OrderOpenPrice(),sl,tp,0,clrNONE))
        { ok=false; Print("COST_PROTECTION_FAILED: ",GetLastError()); }
     }
   for(int j=OrdersTotal()-1;j>=0;j--)
     {
      if(!OrderSelect(j,SELECT_BY_POS,MODE_TRADES)||!IsOurMarketOrder()) continue;
      if(MathAbs(OrderStopLoss()-sl)>Point*0.5 || MathAbs(OrderTakeProfit()-tp)>Point*0.5)
         ok=false;
     }
   if(!ok) g_cost_frozen=true;
   g_cost_tp=tp;g_cost_last_stop=sl;CostSave();
   return ok;
  }

bool CostReverse(const int old_type, const double old_lots)
  {
   g_cumulative_loss_lots+=old_lots;
   g_previous_grid_lots=g_grid_lots;
   g_reversal_count++;
   if(g_reversal_count>最大反手次数) {CostClear();return false;}
   const int next_index=NextCycleIndex();
   const int next_type=SequenceDirection(next_index);
   const double requested=NextGroupLotsAfterStopRaw(old_lots);
   if(requested>MarketInfo(Symbol(),MODE_MAXLOT))
     {Print("COST_REVERSAL_VOLUME_UNSUPPORTED");CostClear();return false;}
   g_cycle_index=next_index;
   const double q=next_type==OP_BUY ? Ask : Bid;
   const double stop=PriceNormalize(q+(next_type==OP_BUY ? -1 : 1)*g_group_stop_points*Point);
   const double strategy=PriceNormalize(q+(next_type==OP_BUY ? 1 : -1)*g_group_take_profit_points*Point);
   const int prior_ticket=g_cost_last_ticket;
   if(!CostSend(next_type,requested,q,stop,strategy))
     {
      if(g_cost_last_ticket!=prior_ticket || HasOurPosition())
        {g_cost_frozen=true;CostSave();}
      else CostClear();
      return false;
     }
   int ticket=-1,type=OP_BUY;double lots=0,entry=0,sl=0,tp=0;
   if(!FindPosition(ticket,type,lots,entry,sl,tp))
     {g_cost_frozen=true;CostSave();return false;}
   g_group_anchor_price=entry;g_group_last_entry=entry;g_group_linear_extreme=entry;
   g_group_first_lots=lots;g_group_total_lots=TotalPositionLots(type);
   g_grid_lots=VolumeNormalize(g_previous_grid_lots*InpGridLotMultiplier);
   g_grid_filled_mask=0;g_favorable_grid_filled_mask=0;
   g_cost_last_ticket=ticket;g_cost_last_type=type;g_cost_last_stop=stop;
   CostProtect(type);CostSave();return true;
  }

int CostPassiveStopTicket()
  {
   const string prefix=CostKey("ticket.");
   int latest=-1;
   for(int i=0;i<GlobalVariablesTotal();i++)
     {
      const string key=GlobalVariableName(i);
      if(StringFind(key,prefix)!=0 || (long)GlobalVariableGet(key)!=g_cost_cycle_id)
         continue;
      const int ticket=(int)StringToInteger(StringSubstr(key,StringLen(prefix)));
      if(ticket==g_cost_last_closed_handled || ticket<=0
         || !OrderSelect(ticket,SELECT_BY_TICKET) || OrderCloseTime()!=TimeCurrent())
         continue;
      const double order_stop=OrderStopLoss()>0.0 ? OrderStopLoss() : g_cost_last_stop;
      if(order_stop<=0.0) continue;
      if((OrderType()==OP_BUY && OrderClosePrice()<=order_stop+Point*0.5)
         || (OrderType()==OP_SELL && OrderClosePrice()>=order_stop-Point*0.5))
         latest=MathMax(latest,ticket);
     }
   return latest;
  }

void CostManage()
  {
   string quote_reason="";
   RefreshRates();
   if(Bid<=0.0 || Ask<=Bid || (TimeCurrent()-(datetime)MarketInfo(Symbol(),MODE_TIME))*1000>最长报价延迟毫秒)
      g_cost_good_quotes=0;
   if(HasOurPending())
     { g_cost_frozen=true; DeleteAllPending(); Print("LEGACY_PENDING_IN_COST_MODE"); return; }
   int ticket=-1,type=OP_BUY; double lots=0.0,entry=0.0,sl=0.0,tp=0.0;
   const bool found=FindPosition(ticket,type,lots,entry,sl,tp);
   if(found)
     {
      if(!g_cost_active) { g_cost_frozen=true; Print("COST_LEDGER_INCOMPLETE: position without cycle"); return; }
      if(g_group_anchor_price<=0.0) g_group_anchor_price=entry;
      if(g_group_last_entry<=0.0) g_group_last_entry=entry;
      if(g_group_linear_extreme<=0.0) g_group_linear_extreme=entry;
      g_group_total_lots=TotalPositionLots(type);
      g_cost_last_ticket=ticket;g_cost_last_type=type;
      g_cost_last_stop=GroupStopPrice(type);
      if(InpTakeProfitMode==TAKE_PROFIT_LINEAR)
        {
         const double q=type==OP_BUY ? Ask : Bid;
         if((type==OP_BUY && q<g_group_linear_extreme)
            || (type==OP_SELL && q>g_group_linear_extreme)) g_group_linear_extreme=q;
        }
      // Existing server protection takes priority over every new grid entry.
      if(!CostProtect(type)) return;
      if((type==OP_BUY && Bid>=g_cost_tp)||(type==OP_SELL && Ask<=g_cost_tp))
        { if(CloseAllPositions(type)) CostClear(); return; }
      if((type==OP_BUY && Bid<=GroupStopPrice(type))
         || (type==OP_SELL && Ask>=GroupStopPrice(type)))
        {
         const double old_lots=g_group_total_lots;
         if(!CloseAllPositions(type)) return;
         CostReverse(type,old_lots); return;
        }
      if(g_cost_frozen || g_group_stop_points<=0 || InpGridCount<2) return;
      for(int level=1;level<InpGridCount;level++)
        for(int side=0;side<2;side++)
          {
           if(side==1 && FavorableGridEnable!=1) continue;
           const long bit=GridLevelBit(level);
           if((side==0 && (g_grid_filled_mask&bit)!=0)
              || (side==1 && (g_favorable_grid_filled_mask&bit)!=0)) continue;
           const double trigger=side==0 ? GridLevelPrice(type,level)
                                          : FavorableGridLevelPrice(type,level);
           const double q=type==OP_BUY ? Ask : Bid;
           if((side==0 && ((type==OP_BUY && q>trigger)||(type==OP_SELL && q<trigger)))
              || (side==1 && ((type==OP_BUY && q<trigger)||(type==OP_SELL && q>trigger)))) continue;
           const double strategy=type==OP_BUY ? q+g_group_take_profit_points*Point
                                               : q-g_group_take_profit_points*Point;
           if(!CostSend(type,g_grid_lots,trigger,GroupStopPrice(type),strategy)) return;
           double actual_entry=q;
           if(OrderSelect(g_cost_last_ticket,SELECT_BY_TICKET))
              actual_entry=OrderOpenPrice();
           if(side==0) {g_grid_filled_mask|=bit;g_group_last_entry=actual_entry;}
           else
             {
              g_favorable_grid_filled_mask|=bit;
              if(DynamicStopLossEnable==1) g_group_last_entry=actual_entry;
             }
           g_group_total_lots=TotalPositionLots(type);
           CostProtect(type); CostSave(); return;
          }
      return;
     }
   if(g_cost_active)
     {
      // Reversal is one-shot on the close event.  Never keep a delayed trigger.
      const int stop_ticket=CostPassiveStopTicket();
      if(stop_ticket>0)
        {
         g_cost_last_closed_handled=stop_ticket;
         CostSave();
         CostReverse(g_cost_last_type,g_group_total_lots);
         return;
        }
      double realized=0.0;
      if(!CostHistoryCash(realized)) Print("COST_LEDGER_INCOMPLETE: closed ticket unavailable.");
      Print("COST_CYCLE_CLOSED_EXTERNALLY: conservative realized=",realized);
      CostClear(); return;
     }
   if(!IsInitialEntryAllowed()) return;
   int stop_points=0,tp_points=0,first_type=OP_BUY;
   double initial_trigger=0.0;
   if(InpDistanceMode==DISTANCE_CANDLE_RANGE)
     {
      double high=0.0,low=0.0;int range=0;
      if(!GetPreviousCandleRange(high,low,range)) return;
      const datetime bar=iTime(Symbol(),Period(),0);
      if(g_cost_trigger_bar!=bar)
        { g_cost_high=high;g_cost_low=low;g_cost_trigger_bar=bar;CostSave(); }
      if(Korder_type==KORDER_ONCE_PER_BAR && bar==g_last_candle_entry_bar_time)
         return;
      const bool high_hit=Ask>=g_cost_high;
      const bool low_hit=Bid<=g_cost_low;
      if(high_hit && low_hit)
        {
         Print("COST_DUAL_TRIGGER: both skipped");
         if(Korder_type==KORDER_ONCE_PER_BAR) MarkCandleEntryBarProcessed(bar);
         return;
        }
      if(!high_hit && !low_hit) return;
      first_type=high_hit ? (ordertype==ORDERTYPE_FORWARD ? OP_BUY : OP_SELL)
                          : (ordertype==ORDERTYPE_FORWARD ? OP_SELL : OP_BUY);
      initial_trigger=high_hit ? g_cost_high : g_cost_low;
      stop_points=range;tp_points=range;
     }
   else
     {
      if(InpDistanceMode==DISTANCE_LONG_CANDLE)
        {if(!GetLongCandleDirection(first_type)) return;}
      else if(首单方向确定方式==FIRST_DIRECTION_BOLLINGER)
        {if(!GetBollingerFirstDirection(first_type)) return;}
      else first_type=InpFirstDirection==FIRST_SELL ? OP_SELL : OP_BUY;
      if(!GetDistancePoints(stop_points,tp_points)) return;
     }
   g_group_stop_points=stop_points;g_group_take_profit_points=tp_points;
   g_cost_target=目标净盈亏比>0.0 ? 目标净盈亏比 : (double)tp_points/stop_points;
   g_cost_cycle_start=TimeCurrent();
   const double prior_id=GlobalVariableCheck(CostKey("next"))
                         ? GlobalVariableGet(CostKey("next")) : 0.0;
   g_cost_cycle_id=(long)prior_id+1;
   GlobalVariableSet(CostKey("next"),(double)g_cost_cycle_id);
   g_cost_active=true; g_cost_frozen=false; g_cycle_index=0;g_reversal_count=0;
   g_active_first_direction=first_type==OP_BUY ? FIRST_BUY : FIRST_SELL;
   g_active_cycle_mode=InpCycleMode;
   const double q=first_type==OP_BUY ? Ask : Bid;
   const double stop=PriceNormalize(q+(first_type==OP_BUY ? -1 : 1)*stop_points*Point);
   const double strategy=PriceNormalize(q+(first_type==OP_BUY ? 1 : -1)*tp_points*Point);
   const double trigger=InpDistanceMode==DISTANCE_CANDLE_RANGE ? initial_trigger : q;
   const int prior_ticket=g_cost_last_ticket;
   if(!CostSend(first_type,InpInitialLots,trigger,stop,strategy))
     {
      if(g_cost_last_ticket!=prior_ticket || HasOurPosition())
        {g_cost_frozen=true;CostSave();}
      else g_cost_active=false;
      return;
     }
   if(InpDistanceMode==DISTANCE_CANDLE_RANGE && Korder_type==KORDER_ONCE_PER_BAR)
      MarkCandleEntryBarProcessed(iTime(Symbol(),Period(),0));
   if(!FindPosition(ticket,type,lots,entry,sl,tp))
     {g_cost_frozen=true;CostSave();return;}
   g_group_anchor_price=entry;g_group_last_entry=entry;g_group_linear_extreme=entry;
   g_group_first_lots=lots;g_group_total_lots=TotalPositionLots(type);
   g_cost_last_ticket=ticket;g_cost_last_type=type;g_cost_last_stop=stop;
   g_grid_lots=g_group_total_lots;
   g_grid_filled_mask=0;g_favorable_grid_filled_mask=0;
   CostProtect(type);CostSave();
  }

int OnInit()
  {
   const bool single_cost_active=GlobalVariableCheck(CostKey("active"))
      && GlobalVariableGet(CostKey("active"))>0.5;
   if(single_cost_active && !启用XAU净盈亏比)
     {
      Print("COST_MODE_SWITCH_BLOCKED: active single cost cycle requires single cost mode.");
      return INIT_PARAMETERS_INCORRECT;
     }
   const string multi_prefix=StatePrefix()+".multi.";
   bool multi_cost_active=false;
   for(int key_index=0;key_index<GlobalVariablesTotal();key_index++)
     {
      const string key=GlobalVariableName(key_index);
      const string suffix=".cost.mode";
      if(StringFind(key,multi_prefix)!=0 || StringLen(key)<=StringLen(suffix)
         || StringSubstr(key,StringLen(key)-StringLen(suffix))!=suffix
         || GlobalVariableGet(key)<0.5) continue;
      const string group_prefix=StringSubstr(key,0,StringLen(key)-StringLen(suffix));
      if(GlobalVariableCheck(group_prefix+".active")
         && GlobalVariableGet(group_prefix+".active")>0.5)
         multi_cost_active=true;
     }
   if(multi_cost_active && !启用XAU净盈亏比)
     {Print("COST_MODE_SWITCH_BLOCKED: active multi cost groups require NetRR mode.");
      return INIT_PARAMETERS_INCORRECT;}
   if(启用XAU净盈亏比)
     {
      if(StringFind(Symbol(),"XAUUSD")!=0
         || 最大开仓点差点数<=0.0 || 最大点差占止损比例<=0.0
         || 最大开仓滑点点数<=0 || 预计平仓滑点点数<=0
         || 每手往返佣金费用预算<=0.0 || 最大止盈补偿点数<0
         || 最大止盈补偿比例<0.0 || 单轮最大预计亏损权益比例<=0.0
         || 全部轮次最大预计亏损权益比例<=0.0
         || 最长报价延迟毫秒<1000 || 目标净盈亏比<0.0)
        { Print("COST_CONFIG_INVALID: XAUUSD and configured budgets required.");
          return INIT_PARAMETERS_INCORRECT; }
      if(CostMoneyPerPriceUnit()<=0.0)
        {Print("COST_CONTRACT_UNAVAILABLE");return INIT_FAILED;}
     }
   g_start_operation_minutes[0] = ParseTimeMinutes(开始时间);
   g_end_operation_minutes[0] = ParseTimeMinutes(结束时间);
   g_start_operation_minutes[1] = ParseTimeMinutes(时段2开始时间);
   g_end_operation_minutes[1] = ParseTimeMinutes(时段2结束时间);
   g_start_operation_minutes[2] = ParseTimeMinutes(时段3开始时间);
   g_end_operation_minutes[2] = ParseTimeMinutes(时段3结束时间);
   if(DynamicStopLossEnable != 0 && DynamicStopLossEnable != 1)
     {
      Print("动态止损必须为0或1。");
      return INIT_PARAMETERS_INCORRECT;
     }
   if(InpInitialLots <= 0.0 || 首单手数倍数 <= 0.0
       || (FirstOrderLotType != 1 && FirstOrderLotType != 2)
       || (FavorableGridEnable != 0 && FavorableGridEnable != 1)
       || (DynamicStopLossEnable != 0 && DynamicStopLossEnable != 1)
        || !MathIsValidNumber(FirstOrderMult) || FirstOrderMult <= 0.0
       || InpGridCount < 0 || InpGridCount > MAX_GRID_COUNT
      || InpGridLotMultiplier <= 0.0
      || InpStopLossDistancePoints <= 0 || InpTakeProfitDistancePoints <= 0
      || InpCandleMinRangePoints <= 0 || InpCandleMaxRangePoints < InpCandleMinRangePoints
       || InpAverageCandleCount <= 0 || InpAverageStopMultiplier <= 0.0
       || InpAverageTakeProfitMultiplier <= 0.0
       || 最大反手次数 < 0
       || (kline_enable_multiple != 0 && kline_enable_multiple != 1)
       || (篮子数量 != 1 && 篮子数量 != 2)
       || (Korder_type != KORDER_ONCE_PER_BAR && Korder_type != KORDER_REPEAT_PER_BAR)
      || g_start_operation_minutes[0] < 0 || g_end_operation_minutes[0] < 0
      || g_start_operation_minutes[1] < 0 || g_end_operation_minutes[1] < 0
      || g_start_operation_minutes[2] < 0 || g_end_operation_minutes[2] < 0)
      return INIT_PARAMETERS_INCORRECT;
   if(!AcquireExecutionOwnership())
      return INIT_FAILED;
   g_active_first_direction = InpFirstDirection;
   g_active_cycle_mode = InpCycleMode;
    LoadState();
    if(启用XAU净盈亏比)
      {
       CostLoad();
      }
    MultiLoadGroups();
    if(启用XAU净盈亏比 && InpDistanceMode==DISTANCE_CANDLE_RANGE
       && kline_enable_multiple==1 && !HasOurPosition() && !HasOurPending())
      for(int i=ArraySize(g_multi_groups)-1;i>=0;i--)
         if(!g_multi_groups[i].cost_mode) MultiRemoveGroup(i);
    if(启用XAU净盈亏比 && !g_cost_active
       && (HasOurPosition() || HasOurPending()))
      {
       bool restored_cost_multi=false;
       for(int i=0;i<ArraySize(g_multi_groups);i++)
          if(g_multi_groups[i].cost_mode) restored_cost_multi=true;
       if(!restored_cost_multi)
         {g_cost_wait_flat=true;
          Print("COST_WAIT_FLAT: existing legacy exposure remains in legacy mode.");}
      }
    if(!启用XAU净盈亏比 && InpDistanceMode==DISTANCE_CANDLE_RANGE
       && kline_enable_multiple==1)
      for(int i=0;i<ArraySize(g_multi_groups);i++)
        if(g_multi_groups[i].cost_mode)
          {Print("COST_MODE_SWITCH_BLOCKED: multi cost cycle active.");
           return INIT_PARAMETERS_INCORRECT;}
   if(!EventSetTimer(1))
      Print("Unable to start the initial pending OCO timer.");
   return INIT_SUCCEEDED;
  }

void OnTimer()
  {
   if(!CostMode()) ProcessInitialPendingFillEvent();
  }

void OnTick()
  {
   if(!AcquireExecutionOwnership())
      return;
    if(g_cost_wait_flat && !HasOurPosition() && !HasOurPending())
      {
       if(InpDistanceMode==DISTANCE_CANDLE_RANGE && kline_enable_multiple==1)
          MultiClearAll();
       g_cost_wait_flat=false;
      }
    if(CostMode() && g_cost_active)
       CostManage();
    else if(CostMode() && (MultiHasActiveCostGroups() || 篮子数量==2
       || (InpDistanceMode==DISTANCE_CANDLE_RANGE && kline_enable_multiple==1)))
       MultiCostManageGroups();
    else if((篮子数量==2 || MultiHasActiveGroups()) && MultiHasActiveGroups())
       ManageAllMultiGroups();
    else if(CostMode())
       CostManage();
    else if(InpDistanceMode == DISTANCE_CANDLE_RANGE && kline_enable_multiple == 1)
      ManageMultipleCandleGroups();
   else
      Manage();
  }

void OnDeinit(const int reason)
  {
   EventKillTimer();
   ReleaseExecutionOwnership();
  }
