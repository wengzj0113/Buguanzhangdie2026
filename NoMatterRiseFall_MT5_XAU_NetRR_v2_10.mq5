#property strict
#property version   "2.10"
#property description "不管涨跌 XAUUSD 净盈亏比成本控制实验版"

#include <Trade/Trade.mqh>

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

enum StrategyState
  {
   STATE_IDLE = 0,
   STATE_SIGNAL_READY = 1,
   STATE_ORDER_SENDING = 2,
   STATE_POSITION_ACTIVE = 3,
   STATE_PROTECTION_PENDING = 4,
   STATE_RECOVERY = 5,
   STATE_PAUSED_TEMP = 6,
   STATE_FATAL = 7
  };

input group ">>>> 策略与首单";
// 首单方向：做多或做空
input FirstDirection 首单方向 = FIRST_BUY; // [方向]首单做多或做空
// 首单方向确定方式：预设方向或按当前价格相对布林带中轨判断
input FirstDirectionMode 首单方向确定方式 = FIRST_DIRECTION_PRESET; // [方向]预设方向或按布林中轨判断
// 固定距离、平均K线高度和长K线模式均使用用户选择的循环模式
input CycleMode      循环模式 = CYCLE_MODE_1; // [策略]订单组循环方向序列

input group ">>>> 入场信号";
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

input group ">>>> 手数与风险";
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

input group ">>>> 网格与止盈";
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

input group ">>>> 止盈止损距离";
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

input group ">>>> 订单识别";
// 用于识别本EA订单的唯一编号
input ulong          订单识别编号 = 20260830; // [订单]识别本EA订单的编号
// 订单注释；网格单会自动追加网格标记
input string         订单注释 = "不管涨跌"; // [订单]发送到平台的订单备注

input group ">>>> 交易时段";
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

input group ">>>> 净盈亏比与交易成本";
input bool           启用XAU净盈亏比成本模式 = false; // [成本]0=关闭，1=启用成本校正
input double         目标净盈亏比 = 0.0;  // [成本]目标净盈亏比；0=保留初始止盈/止损距离比
input double         最大开仓点差点数 = 0.0; // [成本]开仓最大点差（点）；0=不限
input double         最大点差占止损比例 = 0.0; // [成本]点差/止损最大比例（%）；0=不限
input double         最大开仓滑点点数 = 0.0; // [成本]开仓最大滑点（点）；0=不限制
input double         预计平仓滑点点数 = 0.0; // [成本]预计平仓滑点（点）；0=不计入
input double         每手往返佣金费用预算 = 0.0; // [成本]每手开平仓佣金预算；0=不计入
input double         最大止盈补偿点数 = 0.0; // [成本]止盈成本补偿上限（点）；0=不限
input double         最大止盈补偿比例 = 0.0; // [成本]止盈成本补偿比例上限（%）；0=不限
input double         单轮最大预计亏损权益比例 = 0.0; // [成本]单轮预计亏损占权益上限（%）；0=不限
input double         全部轮次最大预计亏损权益比例 = 0.0; // [成本]全轮预计亏损占权益上限（%）；0=不限
input int            最长报价延迟毫秒 = 0; // [成本]允许报价延迟上限（毫秒）；0=不限

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
#define InpMagicNumber 订单识别编号
#define InpOrderComment 订单注释
#define MAX_OPERATION_WINDOWS 3

enum GuiPage
  {
   GUI_PAGE_OVERVIEW = 0,
   GUI_PAGE_OPENING = 1,
   GUI_PAGE_DISTANCE = 2,
   GUI_PAGE_GRID = 3,
   GUI_PAGE_RISK = 4
  };

enum GuiDisplayMode
  {
   GUI_MODE_EXPERT = 0,
   GUI_MODE_SIMPLE = 1
  };

enum GuiRunState
  {
   GUI_RUN_RUNNING = 0,
   GUI_RUN_PAUSED_INITIAL = 1,
   GUI_RUN_CLEANING = 2,
   GUI_RUN_ERROR = 3
  };

enum GuiCommand
  {
   GUI_CMD_NONE = 0,
   GUI_CMD_APPLY = 1,
   GUI_CMD_PAUSE_INITIAL = 2,
   GUI_CMD_RESUME_INITIAL = 3,
   GUI_CMD_REQUEST_CLOSE_ALL = 4,
   GUI_CMD_CONFIRM_CLOSE_ALL = 5,
   GUI_CMD_CANCEL_CLOSE_ALL = 6
  };

const int GUI_WINDOW_WIDTH = 760;
const int GUI_WINDOW_HEIGHT = 640;
const int GUI_TITLE_HEIGHT = 42;
const int GUI_NAV_WIDTH = 178;
const int GUI_CONTENT_WIDTH = 560;
const int GUI_CONTENT_X = GUI_NAV_WIDTH + 18;
const int GUI_CONTENT_PADDING = 20;
const int GUI_FORM_GAP = 12;
const int GUI_FIELD_WIDTH = 254;
const int GUI_FIELD_HEIGHT = 32;
const int GUI_DROPDOWN_ARROW_WIDTH = 34;
const int GUI_DROPDOWN_ARROW_FONT_SIZE = 30;
const int GUI_EDITABLE_OPTION_MAX = 24;

struct GuiConfig
  {
   bool cost_mode;
   double cost_target_rr;
   double cost_max_spread_points;
   double cost_max_spread_ratio;
   double cost_entry_slippage_points;
   double cost_exit_slippage_points;
   double cost_roundtrip_fee_per_lot;
   double cost_max_tp_extension_points;
   double cost_max_tp_extension_ratio;
   double cost_max_cycle_loss_equity_ratio;
   double cost_max_total_loss_equity_ratio;
   int cost_max_quote_age_ms;
   FirstDirection first_direction;
   FirstDirectionMode first_direction_mode;
   int bollinger_period;
   double bollinger_deviation;
   CycleMode cycle_mode;
   DistanceMode distance_mode;
   OrderTypeMode order_type;
   CandleOrderMode candle_order_mode;
   int candle_enable_multiple;
   TakeProfitMode take_profit_mode;
   double initial_lots;
   double initial_lots_multiplier;
   int    first_order_lot_type;
   double first_order_mult;
   int    favorable_grid_enable;
   int    dynamic_stop_loss_enable;
   int max_reversals;
   int grid_count;
   double grid_lot_multiplier;
   int stop_loss_distance_points;
   int take_profit_distance_points;
   int candle_min_range_points;
   int candle_max_range_points;
   int average_candle_count;
   double average_stop_multiplier;
   double average_take_profit_multiplier;
   ulong magic_number;
   string order_comment;
   string start_time;
   string end_time;
   string start_time_2;
   string end_time_2;
   string start_time_3;
   string end_time_3;
  };

GuiConfig       g_gui_applied_config;
GuiConfig       g_gui_draft_config;
GuiPage         g_gui_page = GUI_PAGE_OVERVIEW;
GuiDisplayMode  g_gui_display_mode = GUI_MODE_EXPERT;
GuiRunState     g_gui_run_state = GUI_RUN_RUNNING;
bool            g_gui_full_window = true;
bool            g_gui_has_unapplied_changes = false;
bool            g_gui_close_confirm_open = false;
string          g_gui_notice = "";
bool            g_gui_config_initialized = false;
string          g_gui_object_prefix = "";
string          g_gui_last_snapshot = "";
bool            g_gui_dirty = true;
bool            g_gui_objects_created = false;
string          g_gui_dropdown_key = "";
string          g_gui_edit_key = "";
string          g_gui_edit_original_value = "";
bool            g_gui_object_click_pending = false;
long            g_gui_object_click_x = 0;
long            g_gui_object_click_y = 0;
bool            g_gui_chart_overlay_state_saved = false;
bool            g_gui_saved_trade_levels = true;
bool            g_gui_saved_trade_history = true;
string          g_gui_render_error = "";
int             g_gui_render_error_code = 0;

CTrade g_trade;
bool   g_had_position = false;
long   g_last_position_type = POSITION_TYPE_BUY;
double g_last_take_profit = 0.0;
int    g_cycle_index = 0;
int    g_pending_index = -1;
int    g_reversal_count = 0;
ulong  g_pending_ticket = 0;
ulong  g_initial_high_ticket = 0;
ulong  g_initial_low_ticket = 0;
double g_initial_high_price = 0.0;
double g_initial_low_price = 0.0;
long   g_initial_high_direction = ORDER_TYPE_BUY;
long   g_initial_low_direction = ORDER_TYPE_SELL;
int    g_execution_lock_handle = INVALID_HANDLE;
bool   g_duplicate_exposure_logged = false;
int    g_transition_phase = TRANSITION_NONE;
long   g_transition_id = 0;
StrategyState g_strategy_state = STATE_IDLE;
bool   g_trade_request_in_flight = false;
ulong  g_trade_request_order_ticket = 0;
ulong  g_trade_request_position_ticket = 0;
long   g_trade_request_signal_id = 0;
datetime g_trade_request_bar_time = 0;
long   g_trade_request_direction = ORDER_TYPE_BUY;
double g_trade_request_volume = 0.0;
datetime g_trade_request_started = 0;
int    g_trade_request_retry_count = 0;
datetime g_last_single_request_wait_log = 0;
datetime g_last_multi_request_wait_log = 0;
datetime g_last_trade_time = 0;
datetime g_last_watchdog_time = 0;
bool   g_signal_consumed = false;
long   g_signal_id = 0;
datetime g_signal_bar_time = 0;
long   g_signal_direction = ORDER_TYPE_BUY;
int    g_signal_retry_count = 0;
datetime g_signal_retry_after = 0;
ulong  g_position_ticket = 0;
int    g_protection_retry_count = 0;
datetime g_protection_retry_after = 0;
string g_protection_pause_reason = "";
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
bool g_cost_active = false;
bool g_cost_frozen = false;
datetime g_cost_cycle_start = 0;
ulong g_cost_first_deal = 0;
datetime g_cost_trigger_bar = 0;
double g_cost_trigger_high = 0.0;
double g_cost_trigger_low = 0.0;
double g_cost_locked_target = 0.0;
double g_cost_entry_trigger_price = 0.0;
bool g_cost_entry_favorable = false;
long g_cost_passive_stop_msc = 0;
long g_cost_consumed_stop_msc = 0;
double g_cost_passive_stop_price = 0.0;
long g_cost_passive_stop_type = POSITION_TYPE_BUY;
long g_cost_last_end_tick_msc = 0;
long g_cost_flat_wait_tick_msc = 0;
ulong g_cost_position_ids[];
ulong g_cost_closed_position_ids[];
datetime g_cost_closed_cycle_starts[];

datetime CostClosedCycleForPosition(const long position_id)
   {
    for(int index = ArraySize(g_cost_closed_position_ids) - 1; index >= 0; index--)
       if((long)g_cost_closed_position_ids[index] == position_id)
          return g_cost_closed_cycle_starts[index];
    return 0;
   }

void CostArchiveClosedPositions()
   {
    if(!g_cost_active || g_cost_cycle_start <= 0) return;
    const string prefix = StatePrefix() + ".cost.archive";
    for(int index = 0; index < ArraySize(g_cost_position_ids); index++)
      {
       const ulong id = g_cost_position_ids[index];
       if(CostClosedCycleForPosition((long)id) > 0) continue;
       const int count = ArraySize(g_cost_closed_position_ids);
       if(count >= 4096 || ArrayResize(g_cost_closed_position_ids, count + 1) != count + 1
          || ArrayResize(g_cost_closed_cycle_starts, count + 1) != count + 1)
         { Print("[COST_ARCHIVE_FULL][LATE_FEES_UNATTRIBUTED=1]"); return; }
       g_cost_closed_position_ids[count] = id;
       g_cost_closed_cycle_starts[count] = g_cost_cycle_start;
       GlobalVariableSet(prefix + ".id." + IntegerToString(count), (double)id);
       GlobalVariableSet(prefix + ".start." + IntegerToString(count),
                         (double)g_cost_cycle_start);
      }
    GlobalVariableSet(prefix + ".count", (double)ArraySize(g_cost_closed_position_ids));
   }

void CostLoadClosedPositions()
   {
    const string prefix = StatePrefix() + ".cost.archive";
    if(!GlobalVariableCheck(prefix + ".count")) return;
    const int count = (int)MathRound(GlobalVariableGet(prefix + ".count"));
    if(count < 0 || count > 4096
       || ArrayResize(g_cost_closed_position_ids, count) != count
       || ArrayResize(g_cost_closed_cycle_starts, count) != count)
      { Print("[COST_ARCHIVE_INCOMPLETE]"); return; }
    for(int index = 0; index < count; index++)
      {
       const string id_key = prefix + ".id." + IntegerToString(index);
       const string start_key = prefix + ".start." + IntegerToString(index);
       if(!GlobalVariableCheck(id_key) || !GlobalVariableCheck(start_key))
         { Print("[COST_ARCHIVE_INCOMPLETE]"); return; }
       g_cost_closed_position_ids[index] = (ulong)MathRound(GlobalVariableGet(id_key));
       g_cost_closed_cycle_starts[index] = (datetime)MathRound(GlobalVariableGet(start_key));
      }
   }

bool CostOwnsPositionId(const long position_id)
  {
   for(int index = 0; index < ArraySize(g_cost_position_ids); index++)
      if((long)g_cost_position_ids[index] == position_id) return true;
   return false;
  }

void CostRememberPositionId(const long position_id)
  {
   if(position_id <= 0 || CostOwnsPositionId(position_id)) return;
   const int count = ArraySize(g_cost_position_ids);
   if(count >= 512 || ArrayResize(g_cost_position_ids, count + 1) != count + 1)
     { g_cost_frozen = true; Print("[COST_FREEZE=POSITION_MAP_FULL]"); return; }
   g_cost_position_ids[count] = (ulong)position_id;
  }
int    g_grid_filled_levels = 0;
long   g_grid_filled_mask = 0;
int    g_grid_pending_level = 0;
double g_grid_pending_price = 0.0;
int    g_favorable_grid_filled_levels = 0;
long   g_favorable_grid_filled_mask = 0;
int    g_favorable_grid_pending_level = 0;
double g_favorable_grid_pending_price = 0.0;
ulong  g_grid_order_tickets[MAX_GRID_COUNT];
ulong  g_favorable_grid_order_tickets[MAX_GRID_COUNT];
bool   g_reset_pending = false;
int    g_start_operation_minutes[MAX_OPERATION_WINDOWS];
int    g_end_operation_minutes[MAX_OPERATION_WINDOWS];

void ClearGridOrderTicketCache()
  {
   ArrayInitialize(g_grid_order_tickets, 0);
   ArrayInitialize(g_favorable_grid_order_tickets, 0);
  }

void MultiClearAll();
bool CostSolveSingle(const long order_type, const double volume,
                     const double entry, const double stop_loss,
                     const double strategy_tp, const int stop_points,
                     const int tp_points, double &approved_tp, string &reason);
string SanitizeExecutionLockPart(string value);
bool HasManagedExposureForMagic(const ulong magic_number);
bool ResetInMemoryStrategyState();
bool GuiCreate();
void GuiDestroy();
bool GuiRender();
string GuiObjectPrefix();
string GuiLegacyObjectPrefix();
bool GuiRenderTitleBar();
bool GuiRenderNavigation();
bool GuiRenderContent();
bool GuiRenderActions();
bool GuiRenderCompactSummaryField(const string key, const string label, const string value,
                                  const int x, const int y, bool &ok);
bool GuiRefreshOverviewData();
bool GuiRenderMinimizedBar();
void GuiRenderIfNeeded();
void GuiMarkDirty();
bool GuiHandleDropdownClick(const string object_name);
bool GuiHandleFieldClick(const string object_name);
bool GuiHandleChartClick(const int x, const int y);
bool GuiIsEditableDropdownKey(const string key);
int GuiEditableDropdownOptionCount(const string key);
string GuiEditableDropdownOptionText(const string key, const int index);
bool GuiParseEditableDropdownValue(const string key, const string value,
                                   string &normalized, string &error);
bool GuiCreateDropdownArrow(const string name, const int x, const int y,
                            const int width, const int height);
bool GuiRenderEditableDropdownField(const string key, const string label,
                                    const string value, const int x, const int y,
                                    bool &ok);
int GuiAnyDropdownOptionCount(const string key);
string GuiAnyDropdownOptionText(const string key, const int index);
int GuiAnyDropdownValueIndex(const string key);
bool GuiSetAnyDropdownValue(const string key, const int index);
int GuiDropdownOptionColumns(const string key);
void GuiDropdownOptionGeometry(const string key, const int field_x, const int field_y,
                               const int index, int &option_x, int &option_y,
                               int &option_width);
bool GuiHandleEditKeyDown(const long key_code);
void GuiRememberObjectClick(const long x, const long y);
bool GuiShouldSkipChartClick(const long x, const long y);
void GuiReleaseButtonState(const string object_name);
bool GuiSyncEditValue(const string key);
bool GuiPrepareChartForWindow();
void GuiRestoreChartAfterWindow();
bool GuiProcessPendingReset();
bool GuiAllowsInitialEntry();

string StatePrefix()
  {
   return "NMR." + SanitizeExecutionLockPart(AccountInfoString(ACCOUNT_SERVER))
          + "." + IntegerToString((long)AccountInfoInteger(ACCOUNT_LOGIN))
          + "." + SanitizeExecutionLockPart(_Symbol) + "."
          + IntegerToString((long)g_gui_applied_config.magic_number);
  }

bool DisableLegacyStateFallback(string &error)
  {
   error = "";
   const string key = StatePrefix() + ".legacy_disabled";
   if(!GlobalVariableSet(key, 1.0))
     {
      error = "Failed to persist MT5 legacy-state migration marker: " + key;
      Print(error);
      return false;
     }
   return true;
  }

bool HasStrategyStateDataAtPrefix(const string prefix)
  {
   return GlobalVariableCheck(prefix + ".candleentrybar")
          || GlobalVariableCheck(prefix + ".index")
          || GlobalVariableCheck(prefix + ".meta")
          || GlobalVariableCheck(prefix + ".transitionphase")
          || GlobalVariableCheck(prefix + ".multi.nextid")
          || GlobalVariableCheck(prefix + ".configfingerprint")
          || GlobalVariableCheck(prefix + ".configfingerprint2");
  }

string StatePrefixForMagic(const ulong magic_number)
  {
   return "NMR." + SanitizeExecutionLockPart(AccountInfoString(ACCOUNT_SERVER))
          + "." + IntegerToString((long)AccountInfoInteger(ACCOUNT_LOGIN))
          + "." + SanitizeExecutionLockPart(_Symbol) + "."
          + IntegerToString((long)magic_number);
  }

string StateReadPrefixForMagic(const ulong magic_number)
  {
   return StatePrefixForMagic(magic_number);
  }

string StateReadPrefix()
  {
   return StateReadPrefixForMagic(g_gui_applied_config.magic_number);
  }

string SanitizeExecutionLockPart(string value)
  {
   string encoded = "x";
   for(int index = 0; index < StringLen(value); index++)
     {
      const int character = StringGetCharacter(value, index);
      if((character >= 48 && character <= 57)
         || (character >= 65 && character <= 90)
         || (character >= 97 && character <= 122)
         || character == 45)
         encoded += StringSubstr(value, index, 1);
      else
         encoded += "_" + IntegerToString(character) + "_";
     }
   return encoded;
  }

string ExecutionLockFileName()
  {
   string name = "NMR_lock_" + SanitizeExecutionLockPart(AccountInfoString(ACCOUNT_SERVER))
                 + "_" + IntegerToString((long)AccountInfoInteger(ACCOUNT_LOGIN))
                 + "_" + SanitizeExecutionLockPart(_Symbol)
                 + "_" + IntegerToString((long)g_gui_applied_config.magic_number);
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
                  AccountInfoInteger(ACCOUNT_LOGIN), _Symbol,
                  g_gui_applied_config.magic_number, GetLastError());
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

string GuiConfigFingerprintText(const GuiConfig &config)
  {
   // Legacy mode retains its original fingerprint for existing installations.
   const string cost_suffix = config.cost_mode
      ? "|XAU_NET_RR_2_10|" + DoubleToString(config.cost_target_rr, 8)
        + "|" + DoubleToString(config.cost_max_spread_points, 8)
        + "|" + DoubleToString(config.cost_max_spread_ratio, 8)
        + "|" + DoubleToString(config.cost_entry_slippage_points, 8)
        + "|" + DoubleToString(config.cost_exit_slippage_points, 8)
        + "|" + DoubleToString(config.cost_roundtrip_fee_per_lot, 8)
        + "|" + DoubleToString(config.cost_max_tp_extension_points, 8)
        + "|" + DoubleToString(config.cost_max_tp_extension_ratio, 8)
        + "|" + DoubleToString(config.cost_max_cycle_loss_equity_ratio, 8)
        + "|" + DoubleToString(config.cost_max_total_loss_equity_ratio, 8)
        + "|" + IntegerToString(config.cost_max_quote_age_ms) : "";
   return IntegerToString((int)config.first_direction) + "|"
          + IntegerToString((int)config.cycle_mode) + "|"
          + IntegerToString((int)config.distance_mode) + "|"
          + IntegerToString((int)config.order_type) + "|"
          + IntegerToString((int)config.candle_order_mode) + "|"
          + IntegerToString(config.candle_enable_multiple) + "|"
          + IntegerToString((int)config.take_profit_mode) + "|"
           + DoubleToString(config.initial_lots, 16) + "|"
           + DoubleToString(config.initial_lots_multiplier, 16) + "|"
           + IntegerToString(config.first_order_lot_type) + "|"
           + DoubleToString(config.first_order_mult, 16) + "|"
           + IntegerToString(config.favorable_grid_enable) + "|"
           + IntegerToString(config.dynamic_stop_loss_enable) + "|"
           + IntegerToString(config.max_reversals) + "|"
          + IntegerToString(config.grid_count) + "|"
          + DoubleToString(config.grid_lot_multiplier, 16) + "|"
          + IntegerToString(config.stop_loss_distance_points) + "|"
          + IntegerToString(config.take_profit_distance_points) + "|"
          + IntegerToString(config.candle_min_range_points) + "|"
          + IntegerToString(config.candle_max_range_points) + "|"
          + IntegerToString(config.average_candle_count) + "|"
          + DoubleToString(config.average_stop_multiplier, 16) + "|"
          + DoubleToString(config.average_take_profit_multiplier, 16) + "|"
          + IntegerToString((long)config.magic_number) + "|"
          + config.order_comment + "|" + config.start_time + "|" + config.end_time
          + "|" + config.start_time_2 + "|" + config.end_time_2
          + "|" + config.start_time_3 + "|" + config.end_time_3
          + "|" + IntegerToString((int)config.first_direction_mode)
          + "|" + IntegerToString(config.bollinger_period)
          + "|" + DoubleToString(config.bollinger_deviation, 16) + cost_suffix;
  }

double GuiConfigFingerprint(const GuiConfig &config)
  {
   const string text = GuiConfigFingerprintText(config);
   double hash = 1000003.0;
   for(int index = 0; index < StringLen(text); index++)
      hash = MathMod(hash * 257.0 + StringGetCharacter(text, index),
                     1000000007.0);
   return hash;
  }

double GuiConfigFingerprint2(const GuiConfig &config)
  {
   const string text = GuiConfigFingerprintText(config);
   double hash = 1000033.0;
   for(int index = 0; index < StringLen(text); index++)
      hash = MathMod(hash * 263.0 + StringGetCharacter(text, index),
                     1000000009.0);
   return hash;
  }

string GuiConfigBeforeBollingerFingerprintText(const GuiConfig &config)
  {
   string text = GuiConfigFingerprintText(config);
   const string suffix = "|" + IntegerToString((int)config.first_direction_mode)
                         + "|" + IntegerToString(config.bollinger_period)
                         + "|" + DoubleToString(config.bollinger_deviation, 16);
   if(StringLen(text) >= StringLen(suffix))
      text = StringSubstr(text, 0, StringLen(text) - StringLen(suffix));
   return text;
  }

string GuiConfigPreOperationWindowsFingerprintText(const GuiConfig &config)
  {
   string text = GuiConfigBeforeBollingerFingerprintText(config);
   const string suffix = "|" + config.start_time_2 + "|" + config.end_time_2
                         + "|" + config.start_time_3 + "|" + config.end_time_3;
   if(StringLen(text) >= StringLen(suffix))
      text = StringSubstr(text, 0, StringLen(text) - StringLen(suffix));
   return text;
  }

double GuiConfigBeforeBollingerFingerprint(const GuiConfig &config)
  {
   const string text = GuiConfigBeforeBollingerFingerprintText(config);
   double hash = 1000003.0;
   for(int index = 0; index < StringLen(text); index++)
      hash = MathMod(hash * 257.0 + StringGetCharacter(text, index),
                     1000000007.0);
   return hash;
  }

double GuiConfigBeforeBollingerFingerprint2(const GuiConfig &config)
  {
   const string text = GuiConfigBeforeBollingerFingerprintText(config);
   double hash = 1000033.0;
   for(int index = 0; index < StringLen(text); index++)
      hash = MathMod(hash * 263.0 + StringGetCharacter(text, index),
                     1000000009.0);
   return hash;
  }

double GuiConfigPreOperationWindowsFingerprint(const GuiConfig &config)
  {
   const string text = GuiConfigPreOperationWindowsFingerprintText(config);
   double hash = 1000003.0;
   for(int index = 0; index < StringLen(text); index++)
      hash = MathMod(hash * 257.0 + StringGetCharacter(text, index),
                     1000000007.0);
   return hash;
  }

double GuiConfigPreOperationWindowsFingerprint2(const GuiConfig &config)
  {
   const string text = GuiConfigPreOperationWindowsFingerprintText(config);
   double hash = 1000033.0;
   for(int index = 0; index < StringLen(text); index++)
      hash = MathMod(hash * 263.0 + StringGetCharacter(text, index),
                     1000000009.0);
   return hash;
  }

string GuiConfigLegacyFingerprintText(const GuiConfig &config)
  {
   string text = GuiConfigPreOperationWindowsFingerprintText(config);
   const string marker = "|" + IntegerToString(config.dynamic_stop_loss_enable)
                         + "|" + IntegerToString(config.max_reversals) + "|";
   StringReplace(text, marker, "|" + IntegerToString(config.max_reversals) + "|");
   return text;
  }

double GuiConfigLegacyFingerprint(const GuiConfig &config)
  {
   const string text = GuiConfigLegacyFingerprintText(config);
   double hash = 1000003.0;
   for(int index = 0; index < StringLen(text); index++)
      hash = MathMod(hash * 257.0 + StringGetCharacter(text, index),
                     1000000007.0);
   return hash;
  }

double GuiConfigLegacyFingerprint2(const GuiConfig &config)
  {
   const string text = GuiConfigLegacyFingerprintText(config);
   double hash = 1000033.0;
   for(int index = 0; index < StringLen(text); index++)
      hash = MathMod(hash * 263.0 + StringGetCharacter(text, index),
                     1000000009.0);
   return hash;
  }

bool MigrateLegacyGuiConfig(const GuiConfig &config, string &error)
  {
   error = "";
   const string prefix = StateReadPrefixForMagic(config.magic_number);
   const string fingerprint_key = prefix + ".configfingerprint";
   const string fingerprint2_key = prefix + ".configfingerprint2";
   if(!GlobalVariableSet(fingerprint_key, GuiConfigFingerprint(config))
      || !GlobalVariableSet(fingerprint2_key, GuiConfigFingerprint2(config)))
     {
      error = "Failed to migrate legacy state configuration fingerprint for magic/order id "
              + IntegerToString((long)config.magic_number) + ".";
      return false;
     }
   PrintFormat("Migrated legacy MT5 state to GUI configuration for magic/order id %I64u.",
               config.magic_number);
   return true;
  }

bool ValidatePersistedConfigForMagic(const GuiConfig &config, string &error)
  {
   error = "";
   const string prefix = StateReadPrefixForMagic(config.magic_number);
   const bool has_state = HasStrategyStateDataAtPrefix(prefix);
   if(!has_state && !HasManagedExposureForMagic(config.magic_number))
      return true;
   const string fingerprint_key = prefix + ".configfingerprint";
   const string fingerprint2_key = prefix + ".configfingerprint2";
   if(!GlobalVariableCheck(fingerprint_key)
      || !GlobalVariableCheck(fingerprint2_key))
     {
      return MigrateLegacyGuiConfig(config, error);
     }
    const double persisted_fingerprint = GlobalVariableGet(fingerprint_key);
    const double persisted_fingerprint2 = GlobalVariableGet(fingerprint2_key);
    const bool current_match = MathAbs(persisted_fingerprint
                                       - GuiConfigFingerprint(config)) <= 0.5
                               && MathAbs(persisted_fingerprint2
                                          - GuiConfigFingerprint2(config)) <= 0.5;
    const bool pre_operation_windows_match = MathAbs(persisted_fingerprint
                                                     - GuiConfigPreOperationWindowsFingerprint(config)) <= 0.5
                                             && MathAbs(persisted_fingerprint2
                                                        - GuiConfigPreOperationWindowsFingerprint2(config)) <= 0.5;
    if(!current_match && pre_operation_windows_match)
      {
       if(!GlobalVariableSet(fingerprint_key, GuiConfigFingerprint(config))
          || !GlobalVariableSet(fingerprint2_key, GuiConfigFingerprint2(config)))
         {
          error = "Failed to migrate the persisted configuration after adding operation windows.";
          return false;
         }
       Print("Migrated legacy fingerprint after adding operation windows");
       return true;
      }
    if(!current_match
       && MathAbs(persisted_fingerprint - GuiConfigBeforeBollingerFingerprint(config)) <= 0.5
       && MathAbs(persisted_fingerprint2 - GuiConfigBeforeBollingerFingerprint2(config)) <= 0.5)
      {
       if(!GlobalVariableSet(fingerprint_key, GuiConfigFingerprint(config))
          || !GlobalVariableSet(fingerprint2_key, GuiConfigFingerprint2(config)))
         {
          error = "Failed to migrate the persisted configuration after adding Bollinger direction settings.";
          return false;
         }
       Print("Migrated legacy fingerprint after adding Bollinger direction settings");
       return true;
      }
    if(!current_match && config.dynamic_stop_loss_enable == 0
       && MathAbs(persisted_fingerprint - GuiConfigLegacyFingerprint(config)) <= 0.5
       && MathAbs(persisted_fingerprint2 - GuiConfigLegacyFingerprint2(config)) <= 0.5)
      {
       if(!GlobalVariableSet(fingerprint_key, GuiConfigFingerprint(config))
          || !GlobalVariableSet(fingerprint2_key, GuiConfigFingerprint2(config)))
         {
          error = "Failed to migrate the persisted configuration fingerprint after adding dynamic stop-loss.";
          return false;
         }
       Print("Migrated legacy fingerprint after adding dynamic stop-loss");
       return true;
      }
    if(!current_match)
      {
       error = "Cannot safely recover magic/order id "
              + IntegerToString((long)config.magic_number)
              + "; input GUI configuration does not match the persisted active configuration.";
      return false;
     }
   return true;
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
   if(g_gui_applied_config.cost_mode)
     {
      GlobalVariableSet(prefix + ".cost.active", g_cost_active ? 1.0 : 0.0);
      GlobalVariableSet(prefix + ".cost.frozen", g_cost_frozen ? 1.0 : 0.0);
      GlobalVariableSet(prefix + ".cost.start", (double)g_cost_cycle_start);
      GlobalVariableSet(prefix + ".cost.firstdeal", (double)g_cost_first_deal);
      GlobalVariableSet(prefix + ".cost.bar", (double)g_cost_trigger_bar);
      GlobalVariableSet(prefix + ".cost.high", g_cost_trigger_high);
      GlobalVariableSet(prefix + ".cost.low", g_cost_trigger_low);
      GlobalVariableSet(prefix + ".cost.target", g_cost_locked_target);
       GlobalVariableSet(prefix + ".cost.stopms", (double)g_cost_passive_stop_msc);
       GlobalVariableSet(prefix + ".cost.consumedstopms", (double)g_cost_consumed_stop_msc);
      GlobalVariableSet(prefix + ".cost.stopprice", g_cost_passive_stop_price);
      GlobalVariableSet(prefix + ".cost.stoptype", (double)g_cost_passive_stop_type);
      GlobalVariableSet(prefix + ".cost.idcount", (double)ArraySize(g_cost_position_ids));
      for(int index = 0; index < ArraySize(g_cost_position_ids); index++)
         GlobalVariableSet(prefix + ".cost.id." + IntegerToString(index),
                           (double)g_cost_position_ids[index]);
     }
   GlobalVariableSet(prefix + ".index", (double)g_cycle_index);
   GlobalVariableSet(prefix + ".pending", (double)g_pending_index);
   GlobalVariableSet(prefix + ".reversals", (double)g_reversal_count);
   GlobalVariableSet(prefix + ".pendingticket", (double)g_pending_ticket);
   GlobalVariableSet(prefix + ".initial_high_ticket", (double)g_initial_high_ticket);
   GlobalVariableSet(prefix + ".initial_low_ticket", (double)g_initial_low_ticket);
   GlobalVariableSet(prefix + ".initial_high_price", g_initial_high_price);
   GlobalVariableSet(prefix + ".initial_low_price", g_initial_low_price);
   GlobalVariableSet(prefix + ".initial_high_direction", (double)g_initial_high_direction);
   GlobalVariableSet(prefix + ".initial_low_direction", (double)g_initial_low_direction);
   GlobalVariableSet(prefix + ".candleentrybar", (double)g_last_candle_entry_bar_time);
   GlobalVariableSet(prefix + ".meta", (double)(g_active_first_direction + g_active_cycle_mode * 2));
   GlobalVariableSet(prefix + ".slpoints", (double)g_group_stop_points);
   GlobalVariableSet(prefix + ".tppoints", (double)g_group_take_profit_points);
    GlobalVariableSet(prefix + ".cumlots", g_cumulative_loss_lots);
    GlobalVariableSet(prefix + ".groupfirstlots", g_group_first_lots);
   GlobalVariableSet(prefix + ".prevgridlots", g_previous_grid_lots);
   GlobalVariableSet(prefix + ".gridlots", g_grid_lots);
   GlobalVariableSet(prefix + ".grouptotal", g_group_total_lots);
   GlobalVariableSet(prefix + ".anchor", g_group_anchor_price);
   GlobalVariableSet(prefix + ".lastentry", g_group_last_entry);
   GlobalVariableSet(prefix + ".linearextreme", g_group_linear_extreme);
   GlobalVariableSet(prefix + ".gridlevel", (double)g_grid_filled_levels);
   SaveGridMask(prefix, g_grid_filled_mask);
    GlobalVariableSet(prefix + ".gridpendinglevel", (double)g_grid_pending_level);
    GlobalVariableSet(prefix + ".gridpendingprice", g_grid_pending_price);
    GlobalVariableSet(prefix + ".favorablegridlevel", (double)g_favorable_grid_filled_levels);
    SaveGridMask(prefix + ".favorable", g_favorable_grid_filled_mask);
    GlobalVariableSet(prefix + ".favorablegridpendinglevel", (double)g_favorable_grid_pending_level);
    GlobalVariableSet(prefix + ".favorablegridpendingprice", g_favorable_grid_pending_price);
   GlobalVariableSet(prefix + ".reset", g_reset_pending ? 1.0 : 0.0);
   GlobalVariableSet(prefix + ".transitionphase", (double)g_transition_phase);
   GlobalVariableSet(prefix + ".transitionid", (double)g_transition_id);
   GlobalVariableSet(prefix + ".signalconsumed", g_signal_consumed ? 1.0 : 0.0);
   GlobalVariableSet(prefix + ".signalid", (double)g_signal_id);
   GlobalVariableSet(prefix + ".signalbar", (double)g_signal_bar_time);
   GlobalVariableSet(prefix + ".signaldirection", (double)g_signal_direction);
   if(!GlobalVariableSet(prefix + ".configfingerprint",
                         GuiConfigFingerprint(g_gui_applied_config))
      || !GlobalVariableSet(prefix + ".configfingerprint2",
                            GuiConfigFingerprint2(g_gui_applied_config)))
      PrintFormat("Failed to persist MT5 GUI configuration fingerprint: %s", prefix);
  }

 void ClearState()
   {
    CostArchiveClosedPositions();
    const string prefix = StatePrefix();
   GlobalVariableDel(prefix + ".cost.active");
   GlobalVariableDel(prefix + ".cost.frozen");
   GlobalVariableDel(prefix + ".cost.start");
   GlobalVariableDel(prefix + ".cost.firstdeal");
   GlobalVariableDel(prefix + ".cost.bar");
   GlobalVariableDel(prefix + ".cost.high");
   GlobalVariableDel(prefix + ".cost.low");
   GlobalVariableDel(prefix + ".cost.target");
    GlobalVariableDel(prefix + ".cost.stopms");
    GlobalVariableDel(prefix + ".cost.consumedstopms");
   GlobalVariableDel(prefix + ".cost.stopprice");
   GlobalVariableDel(prefix + ".cost.stoptype");
   const int cost_id_count = GlobalVariableCheck(prefix + ".cost.idcount")
                             ? (int)MathRound(GlobalVariableGet(prefix + ".cost.idcount")) : 0;
   for(int index = 0; index < cost_id_count; index++)
      GlobalVariableDel(prefix + ".cost.id." + IntegerToString(index));
   GlobalVariableDel(prefix + ".cost.idcount");
   ArrayResize(g_cost_position_ids, 0);
   g_cost_active = false;
   g_cost_frozen = false;
   g_cost_cycle_start = 0;
   g_cost_first_deal = 0;
   g_cost_trigger_bar = 0;
   g_cost_trigger_high = 0.0;
   g_cost_trigger_low = 0.0;
   g_cost_locked_target = 0.0;
    g_cost_passive_stop_msc = 0;
    g_cost_consumed_stop_msc = 0;
   g_cost_passive_stop_price = 0.0;
    g_cost_passive_stop_type = POSITION_TYPE_BUY;
    g_cost_flat_wait_tick_msc = 0;
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
   GlobalVariableDel(prefix + ".signalconsumed");
   GlobalVariableDel(prefix + ".signalid");
   GlobalVariableDel(prefix + ".signalbar");
   GlobalVariableDel(prefix + ".signaldirection");
   GlobalVariableDel(prefix + ".configfingerprint");
   GlobalVariableDel(prefix + ".configfingerprint2");
   g_had_position = false;
   g_last_position_type = POSITION_TYPE_BUY;
   g_last_take_profit = 0.0;
   g_cycle_index = 0;
   g_pending_index = -1;
   g_reversal_count = 0;
   g_pending_ticket = 0;
   g_initial_high_ticket = 0;
   g_initial_low_ticket = 0;
   g_initial_high_price = 0.0;
   g_initial_low_price = 0.0;
   g_initial_high_direction = ORDER_TYPE_BUY;
   g_initial_low_direction = ORDER_TYPE_SELL;
   g_transition_phase = TRANSITION_NONE;
   g_transition_id = 0;
   g_reset_pending = false;
   g_strategy_state = STATE_IDLE;
   g_trade_request_in_flight = false;
   g_trade_request_order_ticket = 0;
   g_trade_request_position_ticket = 0;
   g_trade_request_signal_id = 0;
   g_trade_request_bar_time = 0;
   g_trade_request_direction = ORDER_TYPE_BUY;
   g_trade_request_volume = 0.0;
   g_trade_request_started = 0;
   g_trade_request_retry_count = 0;
   g_last_single_request_wait_log = 0;
   g_last_multi_request_wait_log = 0;
   // Keep the consumed signal key across a flat-group cleanup so a second
   // entry cannot be generated for the same bar/direction after TP or reset.
   g_signal_retry_count = 0;
   g_signal_retry_after = 0;
   g_position_ticket = 0;
   g_protection_retry_count = 0;
   g_protection_retry_after = 0;
   g_protection_pause_reason = "";
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
   string migration_error = "";
   if(!DisableLegacyStateFallback(migration_error))
      PrintFormat("Failed to disable legacy MT5 state fallback: %s", migration_error);
  }

bool LoadStateFromPrefix(const string prefix)
  {
   if(GlobalVariableCheck(prefix + ".candleentrybar"))
      g_last_candle_entry_bar_time = (datetime)MathRound(GlobalVariableGet(prefix + ".candleentrybar"));
   if(!GlobalVariableCheck(prefix + ".index") || !GlobalVariableCheck(prefix + ".meta"))
      return false;

   if(GlobalVariableCheck(prefix + ".reset"))
      g_reset_pending = GlobalVariableGet(prefix + ".reset") > 0.5;
   if(GlobalVariableCheck(prefix + ".transitionphase"))
      g_transition_phase = (int)MathRound(GlobalVariableGet(prefix + ".transitionphase"));
   if(GlobalVariableCheck(prefix + ".transitionid"))
      g_transition_id = (long)MathRound(GlobalVariableGet(prefix + ".transitionid"));
   if(GlobalVariableCheck(prefix + ".signalconsumed"))
      g_signal_consumed = GlobalVariableGet(prefix + ".signalconsumed") > 0.5;
   if(GlobalVariableCheck(prefix + ".signalid"))
      g_signal_id = (long)MathRound(GlobalVariableGet(prefix + ".signalid"));
   if(GlobalVariableCheck(prefix + ".signalbar"))
      g_signal_bar_time = (datetime)MathRound(GlobalVariableGet(prefix + ".signalbar"));
   if(GlobalVariableCheck(prefix + ".signaldirection"))
      g_signal_direction = (long)MathRound(GlobalVariableGet(prefix + ".signaldirection"));

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
      g_pending_ticket = (ulong)MathRound(GlobalVariableGet(prefix + ".pendingticket"));
   if(GlobalVariableCheck(prefix + ".initial_high_ticket"))
      g_initial_high_ticket = (ulong)MathRound(GlobalVariableGet(prefix + ".initial_high_ticket"));
   if(GlobalVariableCheck(prefix + ".initial_low_ticket"))
      g_initial_low_ticket = (ulong)MathRound(GlobalVariableGet(prefix + ".initial_low_ticket"));
   if(GlobalVariableCheck(prefix + ".initial_high_price"))
      g_initial_high_price = GlobalVariableGet(prefix + ".initial_high_price");
   if(GlobalVariableCheck(prefix + ".initial_low_price"))
      g_initial_low_price = GlobalVariableGet(prefix + ".initial_low_price");
   if(GlobalVariableCheck(prefix + ".initial_high_direction"))
      g_initial_high_direction = (long)MathRound(GlobalVariableGet(prefix + ".initial_high_direction"));
   if(GlobalVariableCheck(prefix + ".initial_low_direction"))
      g_initial_low_direction = (long)MathRound(GlobalVariableGet(prefix + ".initial_low_direction"));
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
   if(GlobalVariableCheck(prefix + ".cost.active"))
     {
      g_cost_active = GlobalVariableGet(prefix + ".cost.active") > 0.5;
      g_cost_frozen = GlobalVariableGet(prefix + ".cost.frozen") > 0.5;
      g_cost_cycle_start = (datetime)MathRound(GlobalVariableGet(prefix + ".cost.start"));
      g_cost_first_deal = (ulong)MathRound(GlobalVariableGet(prefix + ".cost.firstdeal"));
      g_cost_trigger_bar = (datetime)MathRound(GlobalVariableGet(prefix + ".cost.bar"));
      g_cost_trigger_high = GlobalVariableGet(prefix + ".cost.high");
      g_cost_trigger_low = GlobalVariableGet(prefix + ".cost.low");
      g_cost_locked_target = GlobalVariableGet(prefix + ".cost.target");
      g_cost_passive_stop_msc = (long)MathRound(GlobalVariableGet(prefix + ".cost.stopms"));
      if(GlobalVariableCheck(prefix + ".cost.consumedstopms"))
         g_cost_consumed_stop_msc = (long)MathRound(GlobalVariableGet(prefix + ".cost.consumedstopms"));
      g_cost_passive_stop_price = GlobalVariableGet(prefix + ".cost.stopprice");
      g_cost_passive_stop_type = (long)MathRound(GlobalVariableGet(prefix + ".cost.stoptype"));
      const int count = (int)MathRound(GlobalVariableGet(prefix + ".cost.idcount"));
      if(count < 0 || count > 512 || ArrayResize(g_cost_position_ids, count) != count)
         g_cost_frozen = true;
      else
         for(int index = 0; index < count; index++)
           {
            const string key = prefix + ".cost.id." + IntegerToString(index);
            if(!GlobalVariableCheck(key)) { g_cost_frozen = true; break; }
            g_cost_position_ids[index] = (ulong)MathRound(GlobalVariableGet(key));
           }
     }
   return true;
  }

void LoadState()
  {
   LoadStateFromPrefix(StateReadPrefix());
  }

bool LoadStateForMagic(const ulong magic_number)
  {
   return LoadStateFromPrefix(StateReadPrefixForMagic(magic_number));
  }

int PriceDigits()
  {
   return (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
  }

double PriceNormalize(const double price)
  {
   return NormalizeDouble(price, PriceDigits());
  }

double NormalizePriceToTick(const double price)
  {
   const double tick_size = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(!MathIsValidNumber(price) || price <= 0.0)
      return 0.0;
   const double step = tick_size > 0.0 ? tick_size : _Point;
   return NormalizeDouble(MathRound(price / step) * step, PriceDigits());
  }

double PriceFloorToTick(const double price)
  {
   const double tick_size = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   const double step = tick_size > 0.0 ? tick_size : _Point;
   return NormalizeDouble(MathFloor(price / step + 0.0000000001) * step,
                          PriceDigits());
  }

double PriceCeilToTick(const double price)
  {
   const double tick_size = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   const double step = tick_size > 0.0 ? tick_size : _Point;
   return NormalizeDouble(MathCeil(price / step - 0.0000000001) * step,
                          PriceDigits());
  }

bool ValidateStops(const ENUM_POSITION_TYPE type, const double entryPrice,
                   double &sl, double &tp, string &reason)
  {
   reason = "";
   const double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   const double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   const long stop_level = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   const long freeze_level = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL);
   const double tick_size = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   const double step = tick_size > 0.0 ? tick_size : _Point;
   const double minimum_distance = MathMax((double)stop_level,
                                           (double)freeze_level) * _Point + step;
   if(entryPrice <= 0.0 || bid <= 0.0 || ask <= 0.0 || minimum_distance <= 0.0)
     {
      reason = StringFormat("invalid market context entry=%.5f bid=%.5f ask=%.5f "
                            "stop_level=%I64d freeze_level=%I64d tick_size=%.10f",
                            entryPrice, bid, ask, stop_level, freeze_level, step);
      return false;
     }

   const double requested_sl = sl;
   const double requested_tp = tp;
   const double reference = type == POSITION_TYPE_BUY ? bid : ask;
   if(type == POSITION_TYPE_BUY)
     {
      sl = MathMin(sl, entryPrice - minimum_distance);
      sl = MathMin(sl, reference - minimum_distance);
      tp = MathMax(tp, entryPrice + minimum_distance);
      tp = MathMax(tp, reference + minimum_distance);
      sl = PriceFloorToTick(sl);
      tp = PriceCeilToTick(tp);
      if(sl <= 0.0 || sl >= entryPrice || sl >= reference
         || tp <= entryPrice || tp <= reference)
         {
          reason = StringFormat("buy stop geometry invalid entry=%.5f bid=%.5f ask=%.5f "
                                "sl=%.5f tp=%.5f min_distance=%.5f",
                                entryPrice, bid, ask, sl, tp, minimum_distance);
          return false;
         }
     }
   else if(type == POSITION_TYPE_SELL)
     {
      sl = MathMax(sl, entryPrice + minimum_distance);
      sl = MathMax(sl, reference + minimum_distance);
      tp = MathMin(tp, entryPrice - minimum_distance);
      tp = MathMin(tp, reference - minimum_distance);
      sl = PriceCeilToTick(sl);
      tp = PriceFloorToTick(tp);
      if(sl <= entryPrice || sl <= reference || tp <= 0.0
         || tp >= entryPrice || tp >= reference)
         {
          reason = StringFormat("sell stop geometry invalid entry=%.5f bid=%.5f ask=%.5f "
                                "sl=%.5f tp=%.5f min_distance=%.5f",
                                entryPrice, bid, ask, sl, tp, minimum_distance);
          return false;
         }
     }
   else
     {
      reason = "unsupported position type";
      return false;
     }

   reason = StringFormat("requested_sl=%.5f requested_tp=%.5f adjusted_sl=%.5f "
                         "adjusted_tp=%.5f bid=%.5f ask=%.5f stop_level=%I64d "
                         "freeze_level=%I64d tick_size=%.10f",
                         requested_sl, requested_tp, sl, tp, bid, ask,
                         stop_level, freeze_level, step);
   return true;
  }

bool BuildStopsForEntry(const long direction, const double entry,
                        const int stop_loss_points, const int take_profit_points,
                        double &stop_loss, double &take_profit, string &reason)
  {
   if(stop_loss_points <= 0 || take_profit_points <= 0)
     {
      reason = "stop/take-profit distance must be positive";
      return false;
     }
   const double distance_sl = stop_loss_points * _Point;
   const double distance_tp = take_profit_points * _Point;
   if(direction == ORDER_TYPE_BUY)
     {
      stop_loss = entry - distance_sl;
      take_profit = entry + distance_tp;
     }
   else
     {
      stop_loss = entry + distance_sl;
      take_profit = entry - distance_tp;
     }
   const ENUM_POSITION_TYPE position_type = direction == ORDER_TYPE_BUY
                                            ? POSITION_TYPE_BUY : POSITION_TYPE_SELL;
   return ValidateStops(position_type, entry, stop_loss, take_profit, reason);
  }

int ParseTimeMinutes(const string value)
  {
   if(StringLen(value) != 5 || StringGetCharacter(value, 2) != 58)
      return -1;
   for(int index = 0; index < 5; index++)
     {
      if(index == 2)
         continue;
      const int character = StringGetCharacter(value, index);
      if(character < 48 || character > 57)
         return -1;
     }
   const int hour = (int)StringToInteger(StringSubstr(value, 0, 2));
   const int minute = (int)StringToInteger(StringSubstr(value, 3, 2));
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

bool IsFinitePositive(const double value)
  {
   return MathIsValidNumber(value) && value > 0.0;
  }

bool IsVolumeAligned(const double volume, const double minimum,
                     const double maximum, const double step)
  {
   if(!IsFinitePositive(volume) || !IsFinitePositive(minimum)
      || !IsFinitePositive(maximum) || !IsFinitePositive(step)
      || minimum > maximum || volume < minimum || volume > maximum)
      return false;
   const double steps = (volume - minimum) / step;
   return MathIsValidNumber(steps)
          && MathAbs(steps - MathRound(steps)) <= 1e-6;
  }

bool HasManagedExposureForMagic(const ulong magic_number)
  {
   for(int index = 0; index < PositionsTotal(); index++)
     {
      const ulong ticket = PositionGetTicket(index);
      if(ticket > 0 && PositionGetString(POSITION_SYMBOL) == _Symbol
         && (ulong)PositionGetInteger(POSITION_MAGIC)
            == magic_number)
         return true;
     }
   for(int index = 0; index < OrdersTotal(); index++)
     {
      const ulong ticket = OrderGetTicket(index);
      if(ticket > 0 && OrderGetString(ORDER_SYMBOL) == _Symbol
         && (ulong)OrderGetInteger(ORDER_MAGIC)
            == magic_number)
         return true;
     }
   return false;
  }

string ScopeRegistryPrefix()
  {
   return "NMR.scope." + SanitizeExecutionLockPart(AccountInfoString(ACCOUNT_SERVER))
          + "." + IntegerToString((long)AccountInfoInteger(ACCOUNT_LOGIN))
          + "." + SanitizeExecutionLockPart(_Symbol) + ".";
  }

string ScopeRegistryKey(const ulong magic_number)
  {
   return ScopeRegistryPrefix() + IntegerToString((long)magic_number);
  }

string StateScopePrefix()
  {
   return "NMR." + SanitizeExecutionLockPart(AccountInfoString(ACCOUNT_SERVER))
          + "." + IntegerToString((long)AccountInfoInteger(ACCOUNT_LOGIN))
          + "." + SanitizeExecutionLockPart(_Symbol) + ".";
  }

bool LoadPersistedTransitionPhaseForPrefix(const string prefix,
                                           const ulong magic_number, int &phase)
  {
   const string key = prefix + IntegerToString((long)magic_number)
                      + ".transitionphase";
   if(!GlobalVariableCheck(key))
      return false;
   const int persisted_phase = (int)MathRound(GlobalVariableGet(key));
   if(persisted_phase != TRANSITION_PREPARED
      && persisted_phase != TRANSITION_COMPLETE)
      return false;
   phase = persisted_phase;
   return true;
  }

bool HasCurrentServerPersistedTransition(const ulong magic_number)
  {
   int phase = TRANSITION_NONE;
   return LoadPersistedTransitionPhaseForPrefix(StateScopePrefix(), magic_number, phase);
  }

bool HasBlockingCandidateTransition(const ulong magic_number)
  {
   return HasCurrentServerPersistedTransition(magic_number);
  }

bool ParsePositiveMagicText(const string value, ulong &magic_number)
  {
   if(StringLen(value) == 0)
      return false;
   for(int index = 0; index < StringLen(value); index++)
     {
      const int character = StringGetCharacter(value, index);
      if(character < 48 || character > 57)
         return false;
     }
   const long parsed = StringToInteger(value);
   if(parsed <= 0)
      return false;
   magic_number = (ulong)parsed;
   return true;
  }

bool HasPersistedStateForMagicPrefix(const string prefix, const ulong magic_number)
  {
   const string state_prefix = prefix + IntegerToString((long)magic_number);
   return GlobalVariableCheck(state_prefix + ".candleentrybar")
          || GlobalVariableCheck(state_prefix + ".index")
          || GlobalVariableCheck(state_prefix + ".meta")
          || GlobalVariableCheck(state_prefix + ".transitionphase")
          || GlobalVariableCheck(state_prefix + ".multi.nextid")
          || GlobalVariableCheck(state_prefix + ".configfingerprint")
          || GlobalVariableCheck(state_prefix + ".configfingerprint2");
  }

bool IsKnownScopeForMagic(const ulong magic_number)
  {
   return GlobalVariableCheck(ScopeRegistryKey(magic_number))
          || HasPersistedStateForMagicPrefix(StateScopePrefix(), magic_number);
  }

bool HasCandidatePersistedState(const ulong magic_number)
  {
   return HasStrategyStateDataAtPrefix(StatePrefixForMagic(magic_number));
  }

bool CheckKnownScopeExposurePrefix(const string prefix, const bool registry_keys,
                                   const bool cleanup_registry,
                                   const ulong requested_magic, string &error)
  {
   for(int index = GlobalVariablesTotal() - 1; index >= 0; index--)
     {
      const string name = GlobalVariableName(index);
      if(StringFind(name, prefix) != 0)
         continue;
      ulong known_magic = 0;
      bool is_known_scope = false;
      if(registry_keys)
        {
         is_known_scope = ParsePositiveMagicText(
            StringSubstr(name, StringLen(prefix)), known_magic);
        }
      else
        {
         const string state_suffix = StringSubstr(name, StringLen(prefix));
         const int separator = StringFind(state_suffix, ".");
         if(separator > 0)
            is_known_scope = ParsePositiveMagicText(
               StringSubstr(state_suffix, 0, separator), known_magic);
        }
      if(!is_known_scope || known_magic == requested_magic)
         continue;
      if(HasManagedExposureForMagic(known_magic))
        {
         error = "Cannot initialize magic/order id "
                 + IntegerToString((long)requested_magic)
                 + "; known scope " + IntegerToString((long)known_magic)
                 + " still has positions or pending orders.";
         return false;
        }
      if(cleanup_registry)
        {
         int persisted_phase = TRANSITION_NONE;
         if(LoadPersistedTransitionPhaseForPrefix(StateScopePrefix(), known_magic,
                                                  persisted_phase))
            continue;
        }
      if(cleanup_registry && !GlobalVariableDel(name))
        {
         error = "Failed to remove stale MT5 scope registry key: " + name;
         Print(error);
         return false;
        }
     }
   return true;
  }

bool CheckKnownScopeExposure(const ulong requested_magic, string &error)
  {
   if(!CheckKnownScopeExposurePrefix(ScopeRegistryPrefix(), true, true,
                                     requested_magic, error)
      || !CheckKnownScopeExposurePrefix(StateScopePrefix(), false, false,
                                        requested_magic, error))
      return false;
   return true;
  }

bool CheckKnownScopeTransitionsPrefix(const string registry_prefix,
                                      const ulong requested_magic, string &error)
  {
   int persisted_phase = TRANSITION_NONE;
   for(int index = GlobalVariablesTotal() - 1; index >= 0; index--)
     {
      const string name = GlobalVariableName(index);
      if(StringFind(name, registry_prefix) != 0)
         continue;
      ulong known_magic = 0;
      if(!ParsePositiveMagicText(
            StringSubstr(name, StringLen(registry_prefix)), known_magic)
         || known_magic == requested_magic)
         continue;
      const bool has_transition = HasCurrentServerPersistedTransition(known_magic);
      if(has_transition)
        {
         error = "Cannot initialize magic/order id "
                 + IntegerToString((long)requested_magic)
                 + "; known scope " + IntegerToString((long)known_magic)
                 + " has a persisted transition in flight.";
         return false;
        }
     }
   return true;
  }

bool CheckKnownStateTransitions(const ulong requested_magic, string &error)
  {
   const string prefix = StateScopePrefix();
   const string marker = ".transitionphase";
   int persisted_phase = TRANSITION_NONE;
   for(int index = GlobalVariablesTotal() - 1; index >= 0; index--)
     {
      const string name = GlobalVariableName(index);
      if(StringFind(name, prefix) != 0)
         continue;
      const string suffix = StringSubstr(name, StringLen(prefix));
      const int marker_index = StringFind(suffix, marker);
      if(marker_index <= 0 || StringSubstr(suffix, marker_index) != marker)
         continue;
      ulong known_magic = 0;
      if(!ParsePositiveMagicText(StringSubstr(suffix, 0, marker_index), known_magic)
         || known_magic == requested_magic
         || !LoadPersistedTransitionPhaseForPrefix(prefix, known_magic,
                                                   persisted_phase))
         continue;
      error = "Cannot initialize magic/order id "
              + IntegerToString((long)requested_magic)
              + "; known scope " + IntegerToString((long)known_magic)
              + " has a persisted transition in flight.";
      return false;
     }
   return true;
  }

bool CheckKnownScopeTransitions(const ulong requested_magic, string &error)
  {
   return CheckKnownScopeTransitionsPrefix(ScopeRegistryPrefix(), requested_magic,
                                            error)
          && CheckKnownStateTransitions(requested_magic, error);
  }

bool RememberManagedScope(const ulong magic_number, string &error)
  {
   error = "";
   if(magic_number == 0)
     {
      error = "Cannot persist an invalid zero magic/order id in the MT5 scope registry.";
      Print(error);
      return false;
     }
   const string key = ScopeRegistryKey(magic_number);
   if(!GlobalVariableSet(key, 1.0))
     {
      error = "Failed to persist MT5 scope registry key: " + key;
      Print(error);
      return false;
     }
   return true;
  }

bool ForgetManagedScopeIfFlat(const ulong magic_number, string &error)
  {
   error = "";
   if(magic_number == 0 || HasManagedExposureForMagic(magic_number))
      return true;
   const string key = ScopeRegistryKey(magic_number);
   if(HasCurrentServerPersistedTransition(magic_number))
      return true;
   if(!GlobalVariableCheck(key))
      return true;
   if(!GlobalVariableDel(key))
     {
      error = "Failed to remove MT5 scope registry key: " + key;
      Print(error);
      return false;
     }
   return true;
  }

bool ValidateGuiConfig(const GuiConfig &config, string &error)
  {
   error = "";
   if(config.cost_mode)
     {
      if(_Symbol != "XAUUSD"
         || AccountInfoInteger(ACCOUNT_MARGIN_MODE) != ACCOUNT_MARGIN_MODE_RETAIL_HEDGING)
        { error = "COST_REQUIRES_XAUUSD_HEDGING"; return false; }
      if(!MathIsValidNumber(config.cost_target_rr) || config.cost_target_rr < 0.0
         || !IsFinitePositive(config.cost_max_spread_points)
         || !IsFinitePositive(config.cost_max_spread_ratio)
         || !IsFinitePositive(config.cost_entry_slippage_points)
         || !IsFinitePositive(config.cost_exit_slippage_points)
         || !IsFinitePositive(config.cost_roundtrip_fee_per_lot)
         || !MathIsValidNumber(config.cost_max_tp_extension_points)
         || config.cost_max_tp_extension_points < 0.0
         || !MathIsValidNumber(config.cost_max_tp_extension_ratio)
         || config.cost_max_tp_extension_ratio < 0.0
         || !IsFinitePositive(config.cost_max_cycle_loss_equity_ratio)
         || !IsFinitePositive(config.cost_max_total_loss_equity_ratio)
         || config.cost_max_quote_age_ms <= 0)
        { error = "COST_BUDGET_REQUIRED"; return false; }
     }
   if(config.first_direction != FIRST_BUY && config.first_direction != FIRST_SELL)
     {
       error = "首单方向设置无效。";
      return false;
     }
   if(config.first_direction_mode != FIRST_DIRECTION_PRESET
      && config.first_direction_mode != FIRST_DIRECTION_BOLLINGER)
     {
       error = "首单方向确定方式设置无效。";
      return false;
     }
   if(config.bollinger_period <= 0 || !IsFinitePositive(config.bollinger_deviation))
     {
       error = "布林带周期必须大于0，标准差倍数必须为有限正数。";
      return false;
     }
   if(config.cycle_mode != CYCLE_MODE_1 && config.cycle_mode != CYCLE_MODE_2
      && config.cycle_mode != CYCLE_MODE_3 && config.cycle_mode != CYCLE_MODE_4)
     {
       error = "循环模式设置无效。";
      return false;
     }
   if(config.distance_mode != DISTANCE_FIXED
      && config.distance_mode != DISTANCE_CANDLE_RANGE
      && config.distance_mode != DISTANCE_AVERAGE_CANDLE_RANGE
      && config.distance_mode != DISTANCE_LONG_CANDLE
      && config.distance_mode != DISTANCE_BOLLINGER_RANGE)
     {
       error = "距离模式设置无效。";
      return false;
     }
   if(config.order_type != ORDERTYPE_FORWARD && config.order_type != ORDERTYPE_REVERSE)
     {
       error = "开单方式设置无效。";
      return false;
     }
   if(config.candle_order_mode != KORDER_ONCE_PER_BAR
      && config.candle_order_mode != KORDER_REPEAT_PER_BAR)
     {
       error = "K线开单模式设置无效。";
      return false;
     }
   if(config.candle_enable_multiple != 0 && config.candle_enable_multiple != 1)
     {
       error = "K线多组必须为0或1。";
      return false;
     }
   if(篮子数量 != 1 && 篮子数量 != 2)
     {
      error = "篮子数量必须为1或2。";
      return false;
     }
   if(篮子数量 == 2
      && AccountInfoInteger(ACCOUNT_MARGIN_MODE) != ACCOUNT_MARGIN_MODE_RETAIL_HEDGING)
     {
      error = "篮子数量为2需要MT5对冲账户。";
      return false;
     }
    if(config.take_profit_mode != TAKE_PROFIT_GRID
       && config.take_profit_mode != TAKE_PROFIT_LINEAR)
     {
       error = "止盈移动模式设置无效。";
       return false;
      }
    if(config.first_order_lot_type != 1 && config.first_order_lot_type != 2)
      {
       error = "止损首单类型必须为1或2。";
       return false;
      }
     if(config.favorable_grid_enable != 0 && config.favorable_grid_enable != 1)
       {
        error = "有利方向加单必须为0或1。";
        return false;
       }
    if(config.dynamic_stop_loss_enable != 0 && config.dynamic_stop_loss_enable != 1)
      {
       error = "动态止损必须为0或1。";
       return false;
      }
    if(!IsFinitePositive(config.initial_lots)
       || !IsFinitePositive(config.initial_lots_multiplier)
       || !IsFinitePositive(config.first_order_mult)
       || !IsFinitePositive(config.grid_lot_multiplier))
     {
       error = "手数和倍数必须为有限正数。";
      return false;
     }
   if(config.max_reversals < 0 || config.grid_count < 0
      || config.grid_count > MAX_GRID_COUNT
      || config.magic_number == 0
      || config.magic_number > (ulong)0x7FFFFFFFFFFFFFFF)
     {
       error = "风控、网格或订单编号设置无效。";
      return false;
     }
   const double volume_min = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   const double volume_max = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   const double volume_step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
    if(!IsVolumeAligned(config.initial_lots, volume_min, volume_max, volume_step)
       || !IsVolumeAligned(config.initial_lots * config.initial_lots_multiplier,
                           volume_min, volume_max, volume_step)
       || !IsVolumeAligned(config.initial_lots * config.first_order_mult,
                           volume_min, volume_max, volume_step)
       || !IsVolumeAligned(config.initial_lots * config.grid_lot_multiplier,
                          volume_min, volume_max, volume_step))
     {
       error = "手数和倍数不符合当前品种要求。";
      return false;
     }
   if(config.stop_loss_distance_points <= 0 || config.take_profit_distance_points <= 0
      || config.candle_min_range_points <= 0
      || config.candle_max_range_points < config.candle_min_range_points
      || config.average_candle_count <= 0
      || !IsFinitePositive(config.average_stop_multiplier)
      || !IsFinitePositive(config.average_take_profit_multiplier))
     {
       error = "距离和K线范围设置无效。";
      return false;
     }
   string comment = config.order_comment;
   StringTrimLeft(comment);
   StringTrimRight(comment);
   if(StringLen(comment) == 0)
     {
       error = "订单注释不能为空。";
      return false;
     }
   if(StringFind(comment, ".Grid") >= 0 || StringFind(comment, ".G") >= 0)
     {
       error = "订单注释不能包含保留标记 .Grid 或 .G。";
      return false;
     }
   if(ParseTimeMinutes(config.start_time) < 0 || ParseTimeMinutes(config.end_time) < 0
      || ParseTimeMinutes(config.start_time_2) < 0
      || ParseTimeMinutes(config.end_time_2) < 0
      || ParseTimeMinutes(config.start_time_3) < 0
      || ParseTimeMinutes(config.end_time_3) < 0)
     {
      error = "All operation windows must use HH:MM within the server day.";
      return false;
     }
   return true;
  }

bool ApplyGuiConfig(const GuiConfig &config, string &error)
   {
    if(g_gui_config_initialized && g_gui_applied_config.cost_mode)
      {
       bool active_cost_cycle = g_cost_active;
       for(int index = 0; index < ArraySize(g_multi_groups); index++)
          if(g_multi_groups[index].active && g_multi_groups[index].cost_active)
             active_cost_cycle = true;
       if(active_cost_cycle)
         {
          error = "Cannot apply GUI config while a cost cycle or virtual trigger is active.";
          g_gui_notice = error;
          return false;
         }
      }
    const bool allow_initial_scope_recovery = !g_gui_config_initialized
                                             && (IsKnownScopeForMagic(config.magic_number)
                                                 || HasManagedExposureForMagic(config.magic_number));
   if((g_transition_phase == TRANSITION_PREPARED
      || g_transition_phase == TRANSITION_COMPLETE)
      && !allow_initial_scope_recovery)
     {
      error = "Cannot apply GUI config while a persisted transition is in flight.";
      g_gui_notice = error;
      return false;
     }
    if(g_gui_config_initialized
       && HasManagedExposureForMagic(g_gui_applied_config.magic_number))
     {
      error = "Cannot apply GUI config while positions or pending orders are active.";
      g_gui_notice = error;
      return false;
     }
   if(!allow_initial_scope_recovery
      && HasManagedExposureForMagic(config.magic_number))
     {
      error = "Cannot apply GUI config for the candidate magic/order id while positions or pending orders are active.";
      g_gui_notice = error;
      return false;
     }
   if(!ValidateGuiConfig(config, error))
     {
      g_gui_notice = error;
      return false;
     }
   if(!ValidatePersistedConfigForMagic(config, error))
     {
      g_gui_notice = error;
      return false;
     }

   GuiConfig previous_config = g_gui_applied_config;
   GuiConfig previous_draft = g_gui_draft_config;
   int previous_start_minutes[MAX_OPERATION_WINDOWS];
   int previous_end_minutes[MAX_OPERATION_WINDOWS];
   ArrayCopy(previous_start_minutes, g_start_operation_minutes);
   ArrayCopy(previous_end_minutes, g_end_operation_minutes);
   const bool previous_has_unapplied_changes = g_gui_has_unapplied_changes;
   const bool previous_config_initialized = g_gui_config_initialized;
   const string previous_object_prefix = g_gui_object_prefix;
   const bool magic_changed = g_gui_config_initialized
                              && config.magic_number != previous_config.magic_number;
   if(magic_changed && HasBlockingCandidateTransition(config.magic_number))
     {
      error = "Cannot apply GUI config for a magic/order id with a persisted transition in flight.";
      g_gui_notice = error;
      return false;
     }
   if(magic_changed && HasCandidatePersistedState(config.magic_number))
     {
      error = "Cannot apply GUI config for a magic/order id with persisted state; clear that scope before switching.";
      g_gui_notice = error;
      return false;
     }
   if(magic_changed)
      ReleaseExecutionOwnership();

   g_gui_applied_config = config;
   g_gui_draft_config = config;
   g_start_operation_minutes[0] = ParseTimeMinutes(config.start_time);
   g_end_operation_minutes[0] = ParseTimeMinutes(config.end_time);
   g_start_operation_minutes[1] = ParseTimeMinutes(config.start_time_2);
   g_end_operation_minutes[1] = ParseTimeMinutes(config.end_time_2);
   g_start_operation_minutes[2] = ParseTimeMinutes(config.start_time_3);
   g_end_operation_minutes[2] = ParseTimeMinutes(config.end_time_3);
   g_trade.SetExpertMagicNumber(config.magic_number);
   if(magic_changed && !AcquireExecutionOwnership())
     {
      ReleaseExecutionOwnership();
      g_gui_applied_config = previous_config;
      g_gui_draft_config = previous_draft;
      ArrayCopy(g_start_operation_minutes, previous_start_minutes);
      ArrayCopy(g_end_operation_minutes, previous_end_minutes);
      g_trade.SetExpertMagicNumber(previous_config.magic_number);
      g_gui_has_unapplied_changes = previous_has_unapplied_changes;
      g_gui_config_initialized = previous_config_initialized;
      if(!AcquireExecutionOwnership())
         error = "New magic/order-id lock failed and the previous execution lock could not be restored.";
      else
         error = "Cannot acquire execution lock for the new magic/order id; previous config restored.";
      g_gui_notice = error;
      return false;
   }
   bool scope_registry_ok = true;
   string scope_registry_error = "";
   if(g_gui_config_initialized)
     {
      if(magic_changed)
        {
         if(!ForgetManagedScopeIfFlat(previous_config.magic_number, scope_registry_error))
            scope_registry_ok = false;
        }
      if(scope_registry_ok
         && !RememberManagedScope(config.magic_number, scope_registry_error))
         scope_registry_ok = false;
     }
   if(!scope_registry_ok)
     {
      string cleanup_error = "";
      if(magic_changed
         && !ForgetManagedScopeIfFlat(config.magic_number, cleanup_error))
         scope_registry_error += " " + cleanup_error;
      if(magic_changed)
         ReleaseExecutionOwnership();
      g_gui_applied_config = previous_config;
      g_gui_draft_config = previous_draft;
      ArrayCopy(g_start_operation_minutes, previous_start_minutes);
      ArrayCopy(g_end_operation_minutes, previous_end_minutes);
      g_trade.SetExpertMagicNumber(previous_config.magic_number);
      g_gui_has_unapplied_changes = previous_has_unapplied_changes;
      g_gui_config_initialized = previous_config_initialized;
      string restore_error = "";
      if(magic_changed
         && !RememberManagedScope(previous_config.magic_number, restore_error))
         scope_registry_error += " " + restore_error;
      if(magic_changed && !AcquireExecutionOwnership())
         scope_registry_error += " Previous execution lock could not be restored.";
      error = "Cannot apply GUI config because MT5 scope registry update failed: "
              + scope_registry_error;
      g_gui_notice = error;
      return false;
     }
   if(magic_changed)
     {
      if(!ResetInMemoryStrategyState())
        {
         string cleanup_error = "";
         if(!ForgetManagedScopeIfFlat(config.magic_number, cleanup_error))
            scope_registry_error += " " + cleanup_error;
         ReleaseExecutionOwnership();
         g_gui_applied_config = previous_config;
         g_gui_draft_config = previous_draft;
      ArrayCopy(g_start_operation_minutes, previous_start_minutes);
      ArrayCopy(g_end_operation_minutes, previous_end_minutes);
         g_trade.SetExpertMagicNumber(previous_config.magic_number);
         g_gui_has_unapplied_changes = previous_has_unapplied_changes;
         g_gui_config_initialized = previous_config_initialized;
         string restore_error = "";
         if(!RememberManagedScope(previous_config.magic_number, restore_error))
            scope_registry_error += " " + restore_error;
         if(!AcquireExecutionOwnership())
            scope_registry_error += " Previous execution lock could not be restored.";
         error = "Cannot switch magic/order id because in-memory strategy state could not be reset: "
                 + scope_registry_error;
         g_gui_notice = error;
         return false;
        }
      g_active_first_direction = config.first_direction;
      g_active_cycle_mode = config.cycle_mode;
    LoadState();
    if(g_gui_applied_config.cost_mode)
       CostLoadClosedPositions();
      if(config.distance_mode == DISTANCE_CANDLE_RANGE
         && config.candle_enable_multiple == 1)
         MultiLoadGroups();
     }
   g_gui_has_unapplied_changes = false;
   g_gui_notice = "";
   g_gui_config_initialized = true;
   if(magic_changed && StringLen(previous_object_prefix) > 0)
     {
      ObjectsDeleteAll(0, previous_object_prefix);
      g_gui_object_prefix = GuiObjectPrefix();
     }
   return true;
  }

GuiConfig LoadConfigFromInputs()
  {
   GuiConfig config;
   config.cost_mode = 启用XAU净盈亏比成本模式;
   config.cost_target_rr = 目标净盈亏比;
   config.cost_max_spread_points = 最大开仓点差点数;
   config.cost_max_spread_ratio = 最大点差占止损比例;
   config.cost_entry_slippage_points = 最大开仓滑点点数;
   config.cost_exit_slippage_points = 预计平仓滑点点数;
   config.cost_roundtrip_fee_per_lot = 每手往返佣金费用预算;
   config.cost_max_tp_extension_points = 最大止盈补偿点数;
   config.cost_max_tp_extension_ratio = 最大止盈补偿比例;
   config.cost_max_cycle_loss_equity_ratio = 单轮最大预计亏损权益比例;
   config.cost_max_total_loss_equity_ratio = 全部轮次最大预计亏损权益比例;
   config.cost_max_quote_age_ms = 最长报价延迟毫秒;
   config.first_direction = 首单方向;
   config.first_direction_mode = 首单方向确定方式;
   config.bollinger_period = 布林带周期;
   config.bollinger_deviation = 布林带标准差;
   config.cycle_mode = 循环模式;
   config.distance_mode = 距离模式;
   config.order_type = 开单方式;
   config.candle_order_mode = K线开单模式;
   config.candle_enable_multiple = kline_enable_multiple;
   config.take_profit_mode = 止盈移动模式;
    config.initial_lots = 首单手数;
    config.initial_lots_multiplier = 首单手数倍数;
    config.first_order_lot_type = FirstOrderLotType;
     config.first_order_mult = FirstOrderMult;
     config.favorable_grid_enable = FavorableGridEnable;
     config.dynamic_stop_loss_enable = DynamicStopLossEnable;
    config.max_reversals = 最大反手次数;
   config.grid_count = 网格数量;
   config.grid_lot_multiplier = 网格手数倍数;
   config.stop_loss_distance_points = 固定止损距离;
   config.take_profit_distance_points = 固定止盈距离;
   config.candle_min_range_points = K线最小高度;
   config.candle_max_range_points = K线最大高度;
   config.average_candle_count = 平均K线根数;
   config.average_stop_multiplier = 平均止损倍数;
   config.average_take_profit_multiplier = 平均止盈倍数;
   config.magic_number = 订单识别编号;
   config.order_comment = 订单注释;
   config.start_time = 开始时间;
   config.end_time = 结束时间;
   config.start_time_2 = 时段2开始时间;
   config.end_time_2 = 时段2结束时间;
   config.start_time_3 = 时段3开始时间;
   config.end_time_3 = 时段3结束时间;

   return config;
  }

bool IsInitialEntryAllowed()
  {
   MqlDateTime current_time;
   TimeToStruct(TimeCurrent(), current_time);
   const int current_minutes = current_time.hour * 60 + current_time.min;
   for(int window = 0; window < MAX_OPERATION_WINDOWS; window++)
     {
      if(IsOperationWindowActive(current_minutes, g_start_operation_minutes[window],
                                 g_end_operation_minutes[window]))
         return true;
     }
   return false;
  }

int CycleLength(const int cycle_mode)
  {
   return cycle_mode == CYCLE_MODE_4 ? 7 : 6;
  }

long SequenceDirection(const int index)
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
   return buy_direction ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
  }

int NextCycleIndex()
  {
   return (g_cycle_index + 1) % CycleLength(g_active_cycle_mode);
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
   if(range_points < g_gui_applied_config.candle_min_range_points
      || range_points > g_gui_applied_config.candle_max_range_points)
      return false;

   return true;
  }

bool PreviousCandleDataReady()
  {
   if(Bars(_Symbol, _Period) < 2)
      return false;
   return iHigh(_Symbol, _Period, 1) > 0.0
          && iLow(_Symbol, _Period, 1) > 0.0;
  }

bool GetAverageCandleRangePoints(int &average_range_points)
  {
   if(g_gui_applied_config.average_candle_count <= 0
      || Bars(_Symbol, _Period) < g_gui_applied_config.average_candle_count + 1)
      return false;
   double total_range_points = 0.0;
   for(int shift = 1; shift <= g_gui_applied_config.average_candle_count; shift++)
     {
      const double high = iHigh(_Symbol, _Period, shift);
      const double low = iLow(_Symbol, _Period, shift);
      if(high <= 0.0 || low <= 0.0 || high <= low)
         return false;
      total_range_points += (high - low) / _Point;
     }
   average_range_points = (int)MathRound(
      total_range_points / g_gui_applied_config.average_candle_count);
   return average_range_points > 0;
  }

bool GetLongCandleDirection(long &first_direction)
  {
   // K1 使用上一根已完成K线；K2～K21为用于比较的前20根K线。
   if(Bars(_Symbol, _Period) < 22)
      return false;

   const double k1_open = iOpen(_Symbol, _Period, 1);
   const double k1_close = iClose(_Symbol, _Period, 1);
   const double k1_high = iHigh(_Symbol, _Period, 1);
   const double k1_low = iLow(_Symbol, _Period, 1);
   if(k1_open <= 0.0 || k1_close <= 0.0 || k1_high <= k1_low)
      return false;

   const double k1_range = k1_high - k1_low;
   double max_prior_range = 0.0;
   for(int shift = 2; shift <= 21; shift++)
     {
      const double high = iHigh(_Symbol, _Period, shift);
      const double low = iLow(_Symbol, _Period, shift);
      if(high <= 0.0 || low <= 0.0 || high <= low)
         return false;
      max_prior_range = MathMax(max_prior_range, high - low);
     }
   if(k1_range < max_prior_range)
      return false;

   if(k1_close > k1_open)
      first_direction = ORDER_TYPE_BUY;
   else if(k1_close < k1_open)
      first_direction = ORDER_TYPE_SELL;
   else
      return false;
   return true;
  }

bool GetBollingerFirstDirection(long &first_direction)
  {
   if(g_gui_applied_config.bollinger_period <= 0
      || g_gui_applied_config.bollinger_deviation <= 0.0)
      return false;
   const int handle = iBands(_Symbol, _Period,
                             g_gui_applied_config.bollinger_period, 0,
                             g_gui_applied_config.bollinger_deviation, PRICE_CLOSE);
   if(handle == INVALID_HANDLE)
      return false;
   double middle[1];
   const int copied = CopyBuffer(handle, 0, 0, 1, middle);
   IndicatorRelease(handle);
   if(copied != 1 || middle[0] == EMPTY_VALUE || middle[0] <= 0.0)
      return false;
   MqlTick tick;
   if(!SymbolInfoTick(_Symbol, tick) || tick.bid <= 0.0 || tick.ask <= 0.0)
      return false;
   const double price = (tick.bid + tick.ask) * 0.5;
   const double epsilon = _Point * 0.5;
   if(MathAbs(price - middle[0]) <= epsilon)
      return false;
   if(price > middle[0])
      first_direction = ORDER_TYPE_BUY;
   else
      first_direction = ORDER_TYPE_SELL;
   return true;
  }

bool GetBollingerDistancePoints(int &stop_loss_points, int &take_profit_points)
  {
   if(g_gui_applied_config.bollinger_period <= 0
      || g_gui_applied_config.bollinger_deviation <= 0.0)
      return false;
   const int handle = iBands(_Symbol, _Period,
                             g_gui_applied_config.bollinger_period, 0,
                             g_gui_applied_config.bollinger_deviation, PRICE_CLOSE);
   if(handle == INVALID_HANDLE)
      return false;
   double upper[1];
   double lower[1];
   const int upper_copied = CopyBuffer(handle, 1, 0, 1, upper);
   const int lower_copied = CopyBuffer(handle, 2, 0, 1, lower);
   IndicatorRelease(handle);
   if(upper_copied != 1 || lower_copied != 1
      || upper[0] == EMPTY_VALUE || lower[0] == EMPTY_VALUE
      || upper[0] <= lower[0])
      return false;
   const double width_points = (upper[0] - lower[0]) / _Point;
   stop_loss_points = (int)MathRound(width_points / 4.0);
   take_profit_points = stop_loss_points;
   return stop_loss_points > 0 && take_profit_points > 0;
  }

bool GetDistancePoints(int &stop_loss_points, int &take_profit_points)
  {
   if(g_gui_applied_config.distance_mode == DISTANCE_FIXED)
     {
      stop_loss_points = g_gui_applied_config.stop_loss_distance_points;
      take_profit_points = g_gui_applied_config.take_profit_distance_points;
      return stop_loss_points > 0 && take_profit_points > 0;
     }

   if(g_gui_applied_config.distance_mode == DISTANCE_AVERAGE_CANDLE_RANGE)
     {
      int average_range_points = 0;
      if(!GetAverageCandleRangePoints(average_range_points)
         || !IsFinitePositive(g_gui_applied_config.average_stop_multiplier)
         || !IsFinitePositive(g_gui_applied_config.average_take_profit_multiplier))
         return false;
      stop_loss_points = (int)MathRound(
         average_range_points * g_gui_applied_config.average_stop_multiplier);
      take_profit_points = (int)MathRound(
         stop_loss_points * g_gui_applied_config.average_take_profit_multiplier);
      return stop_loss_points > 0 && take_profit_points > 0;
     }

   if(g_gui_applied_config.distance_mode == DISTANCE_LONG_CANDLE)
     {
      stop_loss_points = g_gui_applied_config.stop_loss_distance_points;
      take_profit_points = g_gui_applied_config.take_profit_distance_points;
      return stop_loss_points > 0 && take_profit_points > 0;
     }

   if(g_gui_applied_config.distance_mode == DISTANCE_BOLLINGER_RANGE)
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
                          long &first_direction)
  {
   const double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   const double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   if(bid > previous_high)
     {
      first_direction = g_gui_applied_config.order_type == ORDERTYPE_FORWARD
                        ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
      return true;
     }
   if(ask < previous_low)
     {
      first_direction = g_gui_applied_config.order_type == ORDERTYPE_FORWARD
                        ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
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
   if(g_gui_applied_config.distance_mode == DISTANCE_CANDLE_RANGE
      && stop_loss > 0.0 && take_profit > 0.0)
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

bool IsOurPosition(const ulong ticket)
  {
   if(ticket == 0 || !PositionSelectByTicket(ticket))
      return false;
   return PositionGetString(POSITION_SYMBOL) == _Symbol
          && (ulong)PositionGetInteger(POSITION_MAGIC) == g_gui_applied_config.magic_number;
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
         || (ulong)HistoryDealGetInteger(deal_ticket, DEAL_MAGIC)
            != g_gui_applied_config.magic_number)
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

bool ClosePreviousGroupAfterReverseFill(const ulong keep_ticket)
  {
   if(keep_ticket == 0 || !IsOurPosition(keep_ticket))
      return false;
   bool closed = true;
   for(int index = PositionsTotal() - 1; index >= 0; index--)
     {
      const ulong candidate = PositionGetTicket(index);
      if(candidate == 0 || candidate == keep_ticket || !IsOurPosition(candidate))
         continue;
      if(!g_trade.PositionClose(candidate))
        {
         PrintFormat("Previous group close failed after reverse fill, ticket=%I64u, retcode=%u, %s",
                     candidate, g_trade.ResultRetcode(), g_trade.ResultRetcodeDescription());
         closed = false;
        }
     }
   for(int index = PositionsTotal() - 1; index >= 0; index--)
     {
      const ulong candidate = PositionGetTicket(index);
      if(candidate != 0 && candidate != keep_ticket && IsOurPosition(candidate))
         closed = false;
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

bool IsInitialPendingComment(const string comment)
  {
   return StringFind(comment, ".InitialHigh") >= 0
          || StringFind(comment, ".InitialLow") >= 0;
  }

bool FindPending(ulong &ticket, long &type, double &volume, double &price)
  {
   for(int index = 0; index < OrdersTotal(); index++)
     {
      const ulong candidate = OrderGetTicket(index);
      if(candidate == 0)
         continue;
      if(OrderGetString(ORDER_SYMBOL) != _Symbol
          || (ulong)OrderGetInteger(ORDER_MAGIC) != g_gui_applied_config.magic_number
          || !IsReversePendingType(OrderGetInteger(ORDER_TYPE))
          || IsGridPendingComment(OrderGetString(ORDER_COMMENT))
          || IsInitialPendingComment(OrderGetString(ORDER_COMMENT)))
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
          || (ulong)OrderGetInteger(ORDER_MAGIC) != g_gui_applied_config.magic_number
          || !IsReversePendingType(OrderGetInteger(ORDER_TYPE))
          || !IsGridPendingComment(OrderGetString(ORDER_COMMENT))
          || IsInitialPendingComment(OrderGetString(ORDER_COMMENT)))
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

bool HasActiveInitialPending()
  {
   for(int index = 0; index < OrdersTotal(); index++)
     {
      const ulong candidate = OrderGetTicket(index);
      if(candidate == 0)
         continue;
      if(OrderGetString(ORDER_SYMBOL) != _Symbol
         || (ulong)OrderGetInteger(ORDER_MAGIC) != g_gui_applied_config.magic_number
         || !IsReversePendingType(OrderGetInteger(ORDER_TYPE))
         || !IsInitialPendingComment(OrderGetString(ORDER_COMMENT)))
         continue;
      return true;
     }
   return false;
  }

void ResetInitialPendingTracking()
  {
   g_initial_high_ticket = 0;
   g_initial_low_ticket = 0;
   g_initial_high_price = 0.0;
   g_initial_low_price = 0.0;
   g_initial_high_direction = ORDER_TYPE_BUY;
   g_initial_low_direction = ORDER_TYPE_SELL;
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
          || (ulong)OrderGetInteger(ORDER_MAGIC) != g_gui_applied_config.magic_number
          || !IsReversePendingType(OrderGetInteger(ORDER_TYPE))
          || IsGridPendingComment(OrderGetString(ORDER_COMMENT)) != grid
          || IsInitialPendingComment(OrderGetString(ORDER_COMMENT)))
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
         || (ulong)OrderGetInteger(ORDER_MAGIC) != g_gui_applied_config.magic_number
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
          && (ulong)OrderGetInteger(ORDER_MAGIC) == g_gui_applied_config.magic_number
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
   if(g_pending_ticket == 0)
      return REVERSE_PENDING_UNKNOWN;

   if(OrderSelect(g_pending_ticket))
     {
      if(OrderGetString(ORDER_SYMBOL) == _Symbol
         && (ulong)OrderGetInteger(ORDER_MAGIC) == g_gui_applied_config.magic_number
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
   if(HasActiveInitialPending())
      return true;
   return false;
  }

void BeginFullReset(const string reason)
  {
   Print(reason);
   g_gui_run_state = GUI_RUN_CLEANING;
   g_gui_notice = "清理中";
   GuiMarkDirty();
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

void SetStops(const ulong position_ticket, const long type, const double entry,
              const int stop_loss_points, const int take_profit_points)
  {
   double stop_loss = 0.0;
   double take_profit = 0.0;
   string reason = "";
   const long direction = type == POSITION_TYPE_BUY ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   if(!BuildStopsForEntry(direction, entry, stop_loss_points, take_profit_points,
                          stop_loss, take_profit, reason))
     {
      PrintFormat("[GROUP=single][STATE=%s][EVENT=PROTECTION_VALIDATION_FAILED] "
                  "[POSITION=%I64u][ENTRY=%.5f][SL=%.5f][TP=%.5f][ERROR=%s]",
                  StrategyStateText(g_strategy_state), position_ticket, entry,
                  stop_loss, take_profit, reason);
      return;
     }

   if(!g_trade.PositionModify(position_ticket, stop_loss, take_profit))
      PrintFormat("[GROUP=single][STATE=%s][EVENT=POSITION_MODIFY_FAILED] "
                  "[POSITION=%I64u][ENTRY=%.5f][SL=%.5f][TP=%.5f][RETCODE=%u] "
                  "[ERROR=%s]",
                  StrategyStateText(g_strategy_state), position_ticket, entry,
                  stop_loss, take_profit, g_trade.ResultRetcode(), reason);
  }

bool ProtectionRetryAllowed()
  {
   if(g_strategy_state != STATE_PAUSED_TEMP)
      return true;
   if(TimeCurrent() < g_protection_retry_after)
      return false;
   g_strategy_state = STATE_RECOVERY;
   g_protection_retry_after = 0;
   LogSingleTradeEvent("PROTECTION_RETRY_RESUMED", 0, g_position_ticket,
                       0.0, 0.0, 0.0, g_protection_pause_reason);
   return true;
  }

void RegisterProtectionFailure(const uint retcode, const string reason)
  {
   g_strategy_state = STATE_PROTECTION_PENDING;
   g_protection_retry_count++;
   g_protection_pause_reason = reason;
   if(g_protection_retry_count >= 3)
     {
      g_strategy_state = STATE_PAUSED_TEMP;
      g_protection_retry_after = TimeCurrent() + 10;
     }
   LogSingleTradeEvent("PROTECTION_RETRY_SCHEDULED", retcode, g_position_ticket,
                       0.0, 0.0, 0.0, reason);
  }

double GroupStopPrice(const long type)
  {
   double stop_loss = type == POSITION_TYPE_BUY
                      ? g_group_anchor_price - g_group_stop_points * _Point
                      : g_group_anchor_price + g_group_stop_points * _Point;
   if(g_gui_applied_config.dynamic_stop_loss_enable == 1
      && g_gui_applied_config.grid_count >= 2)
     {
      const int level = HighestFavorableGridLevel(g_favorable_grid_filled_mask);
      const double grid_spacing = g_group_stop_points * _Point
                                  / g_gui_applied_config.grid_count;
      if(type == POSITION_TYPE_BUY)
         stop_loss += level * grid_spacing;
      else
         stop_loss -= level * grid_spacing;
     }
   return PriceNormalize(stop_loss);
  }

double GroupTakeProfitPrice(const long type)
  {
   double reference_price = g_group_last_entry;
   if(g_gui_applied_config.take_profit_mode == TAKE_PROFIT_LINEAR
      && g_group_linear_extreme > 0.0)
      reference_price = g_group_linear_extreme;
   const double strategy_tp = type == POSITION_TYPE_BUY
      ? PriceNormalize(reference_price + g_group_take_profit_points * _Point)
      : PriceNormalize(reference_price - g_group_take_profit_points * _Point);
   if(!g_gui_applied_config.cost_mode)
      return strategy_tp;
   if(g_cost_frozen)
     {
      for(int index = PositionsTotal() - 1; index >= 0; index--)
        {
         const ulong ticket = PositionGetTicket(index);
         if(IsOurPosition(ticket) && PositionGetInteger(POSITION_TYPE) == type
            && PositionGetDouble(POSITION_TP) > 0.0)
            return PositionGetDouble(POSITION_TP);
        }
      return strategy_tp;
     }
   double approved_tp = 0.0;
   string reason = "";
   const double group_sl = GroupStopPrice(type);
   bool found = false;
   for(int index = PositionsTotal() - 1; index >= 0; index--)
     {
      const ulong ticket = PositionGetTicket(index);
      if(!IsOurPosition(ticket) || PositionGetInteger(POSITION_TYPE) != type)
         continue;
      found = true;
      const long direction = type == POSITION_TYPE_BUY ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
      if(!CostSolveSingle(direction, 0.0, 0.0, group_sl,
                          strategy_tp, g_group_stop_points, g_group_take_profit_points,
                          approved_tp, reason))
        {
         if(!g_cost_frozen)
            PrintFormat("[COST_FREEZE=%s][POSITION=%I64u]", reason, ticket);
         g_cost_frozen = true;
         return PositionGetDouble(POSITION_TP) > 0.0
                ? PositionGetDouble(POSITION_TP) : strategy_tp;
        }
     }
   return found ? approved_tp : strategy_tp;
  }

bool SetGroupStops(const long type)
  {
   if(!ProtectionRetryAllowed())
      return false;
   double stop_loss = GroupStopPrice(type);
   double take_profit = GroupTakeProfitPrice(type);
   string reason = "";
   if(!ValidateStops((ENUM_POSITION_TYPE)type, g_group_anchor_price,
                     stop_loss, take_profit, reason))
     {
      RegisterProtectionFailure(0, reason);
      return false;
     }
   g_strategy_state = STATE_PROTECTION_PENDING;
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
         const uint retcode = g_trade.ResultRetcode();
         RegisterProtectionFailure(retcode, reason + " "
                                   + g_trade.ResultRetcodeDescription());
         PrintFormat("[GROUP=single][STATE=%s][EVENT=POSITION_MODIFY_FAILED] "
                     "[POSITION=%I64u][ENTRY=%.5f][SL=%.5f][TP=%.5f][RETCODE=%u] "
                     "[ERROR=%s]",
                     StrategyStateText(g_strategy_state), candidate,
                     g_group_anchor_price, stop_loss, take_profit, retcode, reason);
         modified = false;
        }
     }
   g_last_take_profit = take_profit;
   const bool verified = modified && StopsVerified(type);
   if(verified)
     {
      g_protection_retry_count = 0;
      g_protection_retry_after = 0;
      g_protection_pause_reason = "";
      g_strategy_state = STATE_POSITION_ACTIVE;
     }
   else if(modified)
      RegisterProtectionFailure(0, "position stops are not visible after modify");
   return verified;
   }

bool StopsVerified(const long type)
  {
   bool found = false;
   double stop_loss = GroupStopPrice(type);
   double take_profit = GroupTakeProfitPrice(type);
   string reason = "";
   if(!ValidateStops((ENUM_POSITION_TYPE)type, g_group_anchor_price,
                     stop_loss, take_profit, reason))
      return false;
   for(int index = PositionsTotal() - 1; index >= 0; index--)
     {
      const ulong candidate = PositionGetTicket(index);
      if(!IsOurPosition(candidate) || PositionGetInteger(POSITION_TYPE) != type)
         continue;
      found = true;
      if(PositionGetDouble(POSITION_SL) <= 0.0
         || PositionGetDouble(POSITION_TP) <= 0.0
         || MathAbs(PositionGetDouble(POSITION_SL) - stop_loss) > _Point * 0.5
         || MathAbs(PositionGetDouble(POSITION_TP) - take_profit) > _Point * 0.5)
         return false;
     }
   return found;
  }

bool UpdateLinearTakeProfit(const long type)
  {
   if(g_gui_applied_config.take_profit_mode != TAKE_PROFIT_LINEAR
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

bool CostQuoteAllowed(const int stop_points, MqlTick &tick, string &reason)
  {
   reason = "";
   if(!SymbolInfoTick(_Symbol, tick) || tick.bid <= 0.0 || tick.ask <= tick.bid
      || tick.time_msc <= 0)
     { reason = "STALE_QUOTE"; return false; }
   const long age_ms = (long)TimeCurrent() * 1000 - tick.time_msc;
   if(age_ms > g_gui_applied_config.cost_max_quote_age_ms || age_ms < -1000)
     { reason = "STALE_QUOTE"; return false; }
   const double spread_points = (tick.ask - tick.bid) / _Point;
   if(spread_points > g_gui_applied_config.cost_max_spread_points)
     { reason = "SPREAD_ABSOLUTE"; return false; }
   if(stop_points <= 0
      || spread_points > stop_points * g_gui_applied_config.cost_max_spread_ratio)
     { reason = "SPREAD_RELATIVE"; return false; }
   return true;
  }

bool CostSolveSingle(const long order_type, const double volume,
                     const double entry, const double stop_loss,
                     const double strategy_tp, const int stop_points,
                     const int tp_points, double &approved_tp, string &reason)
  {
   reason = "";
   const ENUM_ORDER_TYPE calc_type = order_type == ORDER_TYPE_BUY
                                     ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   const double exit_sl = order_type == ORDER_TYPE_BUY
                          ? stop_loss - g_gui_applied_config.cost_exit_slippage_points * _Point
                          : stop_loss + g_gui_applied_config.cost_exit_slippage_points * _Point;
   double sl_price_cash = 0.0;
   double total_volume = volume;
   double first_position_entry = 0.0;
   if(volume > 0.0 && !OrderCalcProfit(calc_type, _Symbol, volume, entry,
                                       exit_sl, sl_price_cash))
     { reason = "PROFIT_CALC_FAILED"; return false; }
   for(int index = PositionsTotal() - 1; index >= 0; index--)
     {
      const ulong ticket = PositionGetTicket(index);
      if(!IsOurPosition(ticket)) continue;
      if(PositionGetInteger(POSITION_TYPE) != (order_type == ORDER_TYPE_BUY
          ? POSITION_TYPE_BUY : POSITION_TYPE_SELL))
        { reason = "MIXED_DIRECTION"; return false; }
      const double lots = PositionGetDouble(POSITION_VOLUME);
      if(first_position_entry <= 0.0)
         first_position_entry = PositionGetDouble(POSITION_PRICE_OPEN);
      double cash = 0.0;
      if(!OrderCalcProfit(calc_type, _Symbol, lots,
                          PositionGetDouble(POSITION_PRICE_OPEN), exit_sl, cash))
        { reason = "PROFIT_CALC_FAILED"; return false; }
      sl_price_cash += cash;
      total_volume += lots;
     }
   double realized_cash = 0.0;
   double paid_fees = 0.0;
   double opened_lots = 0.0;
   if(g_cost_active && g_cost_cycle_start > 0)
     {
      if(!HistorySelect(g_cost_cycle_start, TimeCurrent()))
        { reason = "COST_LEDGER_INCOMPLETE"; return false; }
      for(int index = 0; index < HistoryDealsTotal(); index++)
        {
         const ulong deal = HistoryDealGetTicket(index);
         if(HistoryDealGetString(deal, DEAL_SYMBOL) != _Symbol
            || !CostOwnsPositionId(HistoryDealGetInteger(deal, DEAL_POSITION_ID))) continue;
         const double fees = HistoryDealGetDouble(deal, DEAL_COMMISSION)
                             + HistoryDealGetDouble(deal, DEAL_FEE);
         paid_fees += MathMax(0.0, -fees);
         if(HistoryDealGetInteger(deal, DEAL_ENTRY) == DEAL_ENTRY_IN)
            opened_lots += HistoryDealGetDouble(deal, DEAL_VOLUME);
         realized_cash += HistoryDealGetDouble(deal, DEAL_PROFIT)
                          + fees + HistoryDealGetDouble(deal, DEAL_SWAP);
        }
     }
   if(g_cost_active && total_volume - volume > 0.0
      && (ArraySize(g_cost_position_ids) == 0
          || opened_lots + SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP) * 0.5
             < total_volume - volume))
     { reason = "COST_LEDGER_INCOMPLETE"; return false; }
   const double fee_cash = MathMax(0.0, (opened_lots + volume)
                             * g_gui_applied_config.cost_roundtrip_fee_per_lot - paid_fees);
   const double net_sl = realized_cash + sl_price_cash - fee_cash;
   double projected_loss = MathMax(0.0, -net_sl);
   if(g_gui_applied_config.grid_count >= 2 && stop_points > 0)
     {
      const double anchor = g_group_anchor_price > 0.0 ? g_group_anchor_price
                            : entry > 0.0 ? entry : first_position_entry;
      const double group_grid_lots = g_grid_lots > 0.0 ? g_grid_lots
                                     : g_group_first_lots > 0.0
                                       ? g_group_first_lots : total_volume;
      const double future_lots = MathMax(volume, MathMax(group_grid_lots,
            g_previous_grid_lots * g_gui_applied_config.grid_lot_multiplier));
      if(anchor <= 0.0 || future_lots <= 0.0)
        { reason = "GRID_RISK_UNKNOWN"; return false; }
      for(int level = 1; level < g_gui_applied_config.grid_count; level++)
         for(int side = 0; side < 2; side++)
           {
            if(side == 1 && g_gui_applied_config.favorable_grid_enable != 1) continue;
            const long bit = GridLevelBit(level);
            if((side == 0 && (g_grid_filled_mask & bit) != 0)
               || (side == 1 && (g_favorable_grid_filled_mask & bit) != 0)) continue;
            const double spacing = stop_points * _Point * level
                                   / g_gui_applied_config.grid_count;
            const double trigger = anchor + (order_type == ORDER_TYPE_BUY
                  ? (side == 0 ? -spacing : spacing)
                  : (side == 0 ? spacing : -spacing));
            if(volume > 0.0 && g_cost_entry_trigger_price > 0.0
               && MathAbs(trigger - g_cost_entry_trigger_price)
                  <= SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE) * 0.5)
               continue;
            const double future_entry = trigger + (order_type == ORDER_TYPE_BUY
                  ? g_gui_applied_config.cost_entry_slippage_points * _Point
                  : -g_gui_applied_config.cost_entry_slippage_points * _Point);
            double future_cash = 0.0;
            if(!OrderCalcProfit(calc_type, _Symbol, future_lots,
                                future_entry, exit_sl, future_cash))
              { reason = "GRID_RISK_CALC_FAILED"; return false; }
            projected_loss += MathMax(0.0, -future_cash
                          + future_lots * g_gui_applied_config.cost_roundtrip_fee_per_lot);
           }
     }
   const double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   if(equity <= 0.0
      || projected_loss > equity * g_gui_applied_config.cost_max_cycle_loss_equity_ratio
      || projected_loss > equity * g_gui_applied_config.cost_max_total_loss_equity_ratio)
     { reason = "CYCLE_OR_TOTAL_RISK"; return false; }
   const double target_rr = g_cost_locked_target > 0.0 ? g_cost_locked_target
                            : g_gui_applied_config.cost_target_rr > 0.0
                            ? g_gui_applied_config.cost_target_rr
                            : (double)tp_points / stop_points;
   const double tick_size = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tick_size <= 0.0 || target_rr <= 0.0)
     { reason = "INVALID_TICK_OR_TARGET"; return false; }
   const double extension = MathMin(g_gui_applied_config.cost_max_tp_extension_points,
                                    tp_points * g_gui_applied_config.cost_max_tp_extension_ratio) * _Point;
   double candidate = order_type == ORDER_TYPE_BUY
                      ? PriceCeilToTick(strategy_tp) : PriceFloorToTick(strategy_tp);
   const double boundary = order_type == ORDER_TYPE_BUY
                           ? candidate + extension : candidate - extension;
   const int max_steps = (int)MathMin(100000.0, MathCeil(extension / tick_size) + 2.0);
   for(int step = 0; step <= max_steps; step++)
     {
      if((order_type == ORDER_TYPE_BUY && candidate > boundary + tick_size * 0.1)
         || (order_type == ORDER_TYPE_SELL && candidate < boundary - tick_size * 0.1))
         break;
      const double exit_tp = order_type == ORDER_TYPE_BUY
                             ? candidate - g_gui_applied_config.cost_exit_slippage_points * _Point
                             : candidate + g_gui_applied_config.cost_exit_slippage_points * _Point;
      double tp_price_cash = 0.0;
      if(volume > 0.0 && !OrderCalcProfit(calc_type, _Symbol, volume, entry,
                                          exit_tp, tp_price_cash))
        { reason = "PROFIT_CALC_FAILED"; return false; }
      for(int index = PositionsTotal() - 1; index >= 0; index--)
        {
         const ulong ticket = PositionGetTicket(index);
         if(!IsOurPosition(ticket)) continue;
         double cash = 0.0;
         if(!OrderCalcProfit(calc_type, _Symbol, PositionGetDouble(POSITION_VOLUME),
                             PositionGetDouble(POSITION_PRICE_OPEN), exit_tp, cash))
           { reason = "PROFIT_CALC_FAILED"; return false; }
         tp_price_cash += cash;
        }
      const double net_tp = realized_cash + tp_price_cash - fee_cash;
      if(net_tp > 0.0 && (net_sl >= 0.0 || net_tp >= target_rr * -net_sl))
        { approved_tp = PriceNormalize(candidate); return true; }
      candidate += order_type == ORDER_TYPE_BUY ? tick_size : -tick_size;
      candidate = PriceNormalize(candidate);
     }
   reason = "TARGET_INFEASIBLE";
   return false;
  }

bool SendMarketLeg(const long order_type, const double requested_volume)
  {
   if(g_trade_request_in_flight)
     {
      LogSingleTradeEvent("REQUEST_BLOCKED_IN_FLIGHT");
      return false;
     }
   const double volume = VolumeNormalize(requested_volume);
   if(volume <= 0.0)
      return false;
   double cost_sl = 0.0;
   double cost_tp = 0.0;
   double cost_quote_entry = 0.0;
   if(g_gui_applied_config.cost_mode)
     {
      MqlTick tick;
      string reason = "";
      if(!CostQuoteAllowed(g_group_stop_points, tick, reason))
        { PrintFormat("[COST_REJECT=%s]", reason); return false; }
      cost_quote_entry = order_type == ORDER_TYPE_BUY ? tick.ask : tick.bid;
      const double reference_entry = g_cost_entry_trigger_price > 0.0
                                     ? g_cost_entry_trigger_price : cost_quote_entry;
      if(g_cost_entry_trigger_price > 0.0
         && ((order_type == ORDER_TYPE_BUY
              && cost_quote_entry > g_cost_entry_trigger_price
                 + g_gui_applied_config.cost_entry_slippage_points * _Point)
             || (order_type == ORDER_TYPE_SELL
                 && cost_quote_entry < g_cost_entry_trigger_price
                    - g_gui_applied_config.cost_entry_slippage_points * _Point)))
        { Print("[COST_REJECT=ENTRY_PRICE_LIMIT]"); return false; }
      const double worst_entry = order_type == ORDER_TYPE_BUY
         ? reference_entry + g_gui_applied_config.cost_entry_slippage_points * _Point
         : reference_entry - g_gui_applied_config.cost_entry_slippage_points * _Point;
      const double planned_sl = g_cost_active && HasOurPosition()
         ? GroupStopPrice(order_type == ORDER_TYPE_BUY ? POSITION_TYPE_BUY : POSITION_TYPE_SELL)
         : order_type == ORDER_TYPE_BUY
           ? worst_entry - g_group_stop_points * _Point
           : worst_entry + g_group_stop_points * _Point;
      double tp_reference = worst_entry;
      if(g_cost_entry_favorable && HasOurPosition())
         tp_reference = g_gui_applied_config.take_profit_mode == TAKE_PROFIT_LINEAR
                        ? g_group_linear_extreme : g_group_last_entry;
      const double planned_tp = order_type == ORDER_TYPE_BUY
         ? tp_reference + g_group_take_profit_points * _Point
         : tp_reference - g_group_take_profit_points * _Point;
      cost_sl = PriceNormalize(planned_sl);
      if(!CostSolveSingle(order_type, volume, worst_entry, cost_sl,
                          planned_tp, g_group_stop_points,
                          g_group_take_profit_points, cost_tp, reason))
        { PrintFormat("[COST_REJECT=%s]", reason); return false; }
       if(!ValidateStops((ENUM_POSITION_TYPE)(order_type == ORDER_TYPE_BUY
                           ? POSITION_TYPE_BUY : POSITION_TYPE_SELL),
                         cost_quote_entry, cost_sl, cost_tp, reason))
         { PrintFormat("[COST_REJECT=STOP_VALIDATION][DETAIL=%s]", reason); return false; }
       if(!CostMarginAllowed(order_type, volume, worst_entry, reason))
         { PrintFormat("[COST_REJECT=%s][CYCLE=%I64d]", reason,
                       (long)g_cost_cycle_start); return false; }
      g_trade.SetDeviationInPoints((ulong)MathCeil(g_gui_applied_config.cost_entry_slippage_points));
     }

   g_trade_request_in_flight = true;
   g_trade_request_direction = order_type;
   g_trade_request_volume = volume;
   g_trade_request_bar_time = g_signal_bar_time > 0
                              ? g_signal_bar_time : iTime(_Symbol, _Period, 0);
   g_trade_request_signal_id = g_signal_id != 0
                               ? g_signal_id
                               : BuildSignalId(g_trade_request_bar_time, order_type);
   g_trade_request_started = TimeCurrent();
   g_strategy_state = STATE_ORDER_SENDING;
   LogSingleTradeEvent("REQUEST_SUBMITTED", 0, 0, 0.0, 0.0, 0.0);

   bool sent = false;
   if(order_type == ORDER_TYPE_BUY)
      sent = g_trade.Buy(volume, _Symbol, 0.0, cost_sl, cost_tp,
                         g_gui_applied_config.order_comment);
   else if(order_type == ORDER_TYPE_SELL)
      sent = g_trade.Sell(volume, _Symbol, 0.0, cost_sl, cost_tp,
                          g_gui_applied_config.order_comment);

   const uint retcode = g_trade.ResultRetcode();
   g_trade_request_order_ticket = g_trade.ResultOrder();
   const bool completed = retcode == TRADE_RETCODE_DONE
                          || retcode == TRADE_RETCODE_DONE_PARTIAL;
   if(!sent || !completed)
     {
      HandleTradeRequestFailure(retcode, g_trade.ResultRetcodeDescription());
      if(retcode == TRADE_RETCODE_NO_MONEY)
         BeginResetAfterNoMoney();
      return false;
     }
   if(!ConfirmTradeRequestFromVisiblePosition())
     {
      g_strategy_state = STATE_ORDER_SENDING;
      LogSingleTradeEvent("WAITING_DEAL_CONFIRMATION", retcode,
                          g_trade_request_order_ticket);
      return false;
     }
   if(g_gui_applied_config.cost_mode)
     {
      const ulong ticket = g_trade_request_position_ticket;
      if(ticket > 0 && PositionSelectByTicket(ticket))
        {
         const double actual_entry = PositionGetDouble(POSITION_PRICE_OPEN);
         const double signed_slippage = order_type == ORDER_TYPE_BUY
                                        ? actual_entry - (g_cost_entry_trigger_price > 0.0
                                                          ? g_cost_entry_trigger_price : cost_quote_entry)
                                        : (g_cost_entry_trigger_price > 0.0
                                           ? g_cost_entry_trigger_price : cost_quote_entry) - actual_entry;
         if(signed_slippage > g_gui_applied_config.cost_entry_slippage_points * _Point + _Point * 0.1)
           {
            g_cost_frozen = true;
            PrintFormat("[COST_FREEZE=ACTUAL_ENTRY_SLIPPAGE][POSITION=%I64u][PLAN=%.5f][FILL=%.5f]",
                        ticket, cost_quote_entry, actual_entry);
            SaveState();
           }
        }
      else
        { g_cost_frozen = true; Print("[COST_FREEZE=FILL_NOT_VISIBLE]"); SaveState(); }
      if(retcode == TRADE_RETCODE_DONE_PARTIAL)
        { g_cost_frozen = true; Print("[COST_FREEZE=PARTIAL_FILL]"); SaveState(); }
     }
   return true;
  }

bool OpenMarket(const long order_type, const double requested_volume)
  {
   ReversalLotPlan plan;
   if(!BuildReversalLotPlan(requested_volume, plan))
      return false;
   if(g_gui_applied_config.cost_mode && plan.count != 1)
     { Print("[COST_REJECT=MULTI_LEG_VOLUME]"); return false; }
   if(plan.status == REVERSAL_LOT_RESTART_GROUP)
     {
      PrintFormat("Reversal volume %.2f reaches %.2f lots; stop this group and restart from base lot on the next tick.",
                  requested_volume, MAX_GROUP_REVERSAL_LOTS);
      return false;
     }
   const long position_type = order_type == ORDER_TYPE_BUY
                               ? POSITION_TYPE_BUY : POSITION_TYPE_SELL;
   const double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   const double tolerance = step > 0.0 ? step * 0.5 : 0.0000001;
   const double target = plan.first_lots
                         + (plan.count == 2 ? plan.second_lots : 0.0);
   double current = TotalPositionVolume(position_type);
   for(int leg = 0; leg < plan.count && current + tolerance < target; leg++)
     {
      const double leg_target = leg == 0 ? plan.first_lots : plan.second_lots;
      const double remaining = target - current;
      const double leg_volume = MathMin(leg_target, remaining);
      if(leg_volume <= tolerance)
         continue;
      if(!SendMarketLeg(order_type, leg_volume))
         return false;
      current = TotalPositionVolume(position_type);
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
    if(g_gui_applied_config.first_order_lot_type == 2)
      {
       const double base = g_group_first_lots > 0.0
                           ? g_group_first_lots : fallback_volume;
       return base * g_gui_applied_config.first_order_mult;
      }
    double requested = g_cumulative_loss_lots + g_group_total_lots;
   if(requested <= 0.0)
      requested = fallback_volume;
   else
      requested *= g_gui_applied_config.initial_lots_multiplier;
    return requested;
   }

double NextGroupLots(const double fallback_volume)
   {
    return VolumeNormalize(NextGroupLotsRaw(fallback_volume));
   }

double NextGroupLotsAfterStopRaw(const double fallback_volume)
   {
    if(g_gui_applied_config.first_order_lot_type == 2)
      {
       const double base = g_group_first_lots > 0.0
                           ? g_group_first_lots : fallback_volume;
       return base * g_gui_applied_config.first_order_mult;
      }
    const double requested = g_cumulative_loss_lots > 0.0
                             ? g_cumulative_loss_lots : fallback_volume;
    return requested * g_gui_applied_config.initial_lots_multiplier;
   }

double NextGroupLotsAfterStop(const double fallback_volume)
   {
    return VolumeNormalize(NextGroupLotsAfterStopRaw(fallback_volume));
   }

bool PlaceInitialPendingOrder(const long direction, const double entry,
                              const int distance_points, const double volume,
                              const string comment, ulong &ticket)
  {
   if(g_gui_applied_config.cost_mode)
     { Print("[COST_REJECT=SERVER_ENTRY_PENDING]"); return false; }
   ticket = 0;
   const long pending_type = PendingTypeForDirection(direction, entry);
   const double normalized_entry = PriceNormalize(entry);
   double stop_loss = 0.0;
   double take_profit = 0.0;
   string reason = "";
   if(!BuildStopsForEntry(direction, normalized_entry, distance_points, distance_points,
                          stop_loss, take_profit, reason))
     {
      PrintFormat("Initial pending stops rejected: entry=%.5f sl=%.5f tp=%.5f %s",
                  normalized_entry, stop_loss, take_profit, reason);
      return false;
     }
   bool sent = false;
   if(direction == ORDER_TYPE_BUY)
     {
      sent = pending_type == ORDER_TYPE_BUY_STOP
             ? g_trade.BuyStop(volume, normalized_entry, _Symbol, stop_loss, take_profit,
                               ORDER_TIME_GTC, 0, comment)
             : g_trade.BuyLimit(volume, normalized_entry, _Symbol, stop_loss, take_profit,
                                ORDER_TIME_GTC, 0, comment);
     }
   else
     {
      sent = pending_type == ORDER_TYPE_SELL_STOP
             ? g_trade.SellStop(volume, normalized_entry, _Symbol, stop_loss, take_profit,
                                ORDER_TIME_GTC, 0, comment)
             : g_trade.SellLimit(volume, normalized_entry, _Symbol, stop_loss, take_profit,
                                 ORDER_TIME_GTC, 0, comment);
     }
   const uint retcode = g_trade.ResultRetcode();
   if(!sent || (retcode != TRADE_RETCODE_DONE && retcode != TRADE_RETCODE_PLACED)
      || g_trade.ResultOrder() == 0)
     {
      PrintFormat("Initial pending failed, retcode=%u, %s",
                  retcode, g_trade.ResultRetcodeDescription());
      return false;
     }
   ticket = g_trade.ResultOrder();
   return true;
  }

bool PlaceInitialPendingPair(const double previous_high, const double previous_low,
                             const int range_points, const double volume)
  {
   if(g_initial_high_ticket > 0 || g_initial_low_ticket > 0
      || range_points <= 0 || volume <= 0.0)
      return false;
   const long high_direction = g_gui_applied_config.order_type == ORDERTYPE_FORWARD
                               ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   const long low_direction = g_gui_applied_config.order_type == ORDERTYPE_FORWARD
                              ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
   ulong high_ticket = 0;
   ulong low_ticket = 0;
   if(!PlaceInitialPendingOrder(high_direction, previous_high, range_points, volume,
                                g_gui_applied_config.order_comment + ".InitialHigh",
                                high_ticket))
      return false;
   if(!PlaceInitialPendingOrder(low_direction, previous_low, range_points, volume,
                                g_gui_applied_config.order_comment + ".InitialLow",
                                low_ticket))
     {
      DeletePendingTicket(high_ticket, "Initial pending rollback");
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

int InitialPendingStatus(const ulong ticket)
  {
   if(ticket == 0)
      return REVERSE_PENDING_UNKNOWN;
   if(OrderSelect(ticket))
     {
      if(OrderGetString(ORDER_SYMBOL) == _Symbol
         && (ulong)OrderGetInteger(ORDER_MAGIC) == g_gui_applied_config.magic_number
         && IsInitialPendingComment(OrderGetString(ORDER_COMMENT)))
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

bool HandleInitialPendingFill()
  {
   // The two initial orders form one OCO pair: once either side fills,
   // cancel the still-active opposite order before managing the position.
   if(g_initial_high_ticket == 0 && g_initial_low_ticket == 0)
      return false;
   const int high_status = InitialPendingStatus(g_initial_high_ticket);
   const int low_status = InitialPendingStatus(g_initial_low_ticket);
   const bool high_filled = high_status == REVERSE_PENDING_FILLED;
   const bool low_filled = low_status == REVERSE_PENDING_FILLED;
   if(high_status == REVERSE_PENDING_ACTIVE && low_status == REVERSE_PENDING_ACTIVE)
      return true;
   if(high_filled || low_filled)
     {
      const ulong filled_ticket = high_filled ? g_initial_high_ticket : g_initial_low_ticket;
      const ulong other_ticket = filled_ticket == g_initial_high_ticket
                                 ? g_initial_low_ticket : g_initial_high_ticket;
      const int other_status = high_filled ? low_status : high_status;
      if(other_status == REVERSE_PENDING_UNKNOWN)
         return true;
      if(other_ticket > 0 && other_status == REVERSE_PENDING_ACTIVE
         && !DeletePendingTicket(other_ticket, "Initial OCO delete"))
         return true;
      ulong position_ticket = 0;
      long position_type = POSITION_TYPE_BUY;
      double volume = 0.0;
      double entry = 0.0;
      double stop_loss = 0.0;
      double take_profit = 0.0;
      if(!FindPositionByPendingOrder(filled_ticket, position_ticket, position_type,
                                     volume, entry, stop_loss, take_profit))
         return true;
      g_active_first_direction = position_type == POSITION_TYPE_BUY ? FIRST_BUY : FIRST_SELL;
      g_active_cycle_mode = g_gui_applied_config.cycle_mode;
      g_cycle_index = 0;
      g_pending_index = -1;
      g_pending_ticket = 0;
       g_group_anchor_price = entry;
       g_group_last_entry = entry;
       g_group_linear_extreme = entry;
       g_group_first_lots = volume;
       g_group_total_lots = TotalPositionVolume(position_type);
      g_grid_filled_levels = 0;
      g_grid_filled_mask = 0;
      g_grid_pending_level = 0;
       g_grid_pending_price = 0.0;
       g_favorable_grid_filled_levels = 0;
       g_favorable_grid_filled_mask = 0;
       g_favorable_grid_pending_level = 0;
       g_favorable_grid_pending_price = 0.0;
       ClearGridOrderTicketCache();
       g_grid_lots = g_previous_grid_lots > 0.0
                    ? VolumeNormalize(g_previous_grid_lots
                                      * g_gui_applied_config.grid_lot_multiplier)
                    : g_group_total_lots;
      g_had_position = true;
      g_last_position_type = position_type;
      g_initial_high_ticket = 0;
      g_initial_low_ticket = 0;
      g_initial_high_price = 0.0;
      g_initial_low_price = 0.0;
      if(!SetGroupStops(position_type) || !StopsVerified(position_type))
        {
         Print("Initial fill protection is not verified; follow-up orders are paused.");
         SaveState();
         return true;
        }
      EnsureNextPending(position_type, GroupStopPrice(position_type),
                        GroupTakeProfitPrice(position_type), g_group_total_lots);
      EnsureGridPending(position_type);
      SaveState();
      return true;
     }
   if(high_status == REVERSE_PENDING_UNKNOWN || low_status == REVERSE_PENDING_UNKNOWN)
      return true;
   if(high_status == REVERSE_PENDING_ACTIVE || low_status == REVERSE_PENDING_ACTIVE)
     {
      const ulong active_ticket = high_status == REVERSE_PENDING_ACTIVE
                                  ? g_initial_high_ticket : g_initial_low_ticket;
      if(active_ticket > 0 && !DeletePendingTicket(active_ticket, "Initial OCO cleanup"))
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

bool PlaceNextPending(const long next_direction, const double stop_loss,
                      const double take_profit, const double current_volume)
  {
   if(g_gui_applied_config.cost_mode)
     { Print("[COST_REJECT=SERVER_REVERSE_PENDING]"); return false; }
   if(g_reversal_count >= g_gui_applied_config.max_reversals
      || stop_loss <= 0.0 || current_volume <= 0.0)
      return false;

   int stop_loss_points = 0;
   int take_profit_points = 0;
   if(!GetActiveDistancePoints(stop_loss, take_profit, stop_loss_points, take_profit_points))
      return false;

   ReversalLotPlan plan;
   if(!BuildReversalLotPlan(NextGroupLotsRaw(current_volume), plan)
      || plan.status != REVERSAL_LOT_SINGLE)
      return false;
   const double volume = VolumeNormalize(plan.first_lots);
   const double entry = PriceNormalize(stop_loss);
   double pending_sl = 0.0;
   double pending_tp = 0.0;
   string reason = "";
   if(!BuildStopsForEntry(next_direction, entry, stop_loss_points,
                          take_profit_points, pending_sl, pending_tp, reason))
     {
      PrintFormat("Reverse pending stops rejected: entry=%.5f sl=%.5f tp=%.5f %s",
                  entry, pending_sl, pending_tp, reason);
      return false;
     }
   const long pending_type = PendingTypeForDirection(next_direction, entry);
   bool sent = false;

   if(pending_type == ORDER_TYPE_BUY_STOP || pending_type == ORDER_TYPE_BUY_LIMIT)
     {
      if(pending_type == ORDER_TYPE_BUY_STOP)
         sent = g_trade.BuyStop(volume, entry, _Symbol, pending_sl, pending_tp,
                                ORDER_TIME_GTC, 0, g_gui_applied_config.order_comment);
      else
         sent = g_trade.BuyLimit(volume, entry, _Symbol, pending_sl, pending_tp,
                                 ORDER_TIME_GTC, 0, g_gui_applied_config.order_comment);
     }
   else
     {
      if(pending_type == ORDER_TYPE_SELL_STOP)
         sent = g_trade.SellStop(volume, entry, _Symbol, pending_sl, pending_tp,
                                 ORDER_TIME_GTC, 0, g_gui_applied_config.order_comment);
      else
         sent = g_trade.SellLimit(volume, entry, _Symbol, pending_sl, pending_tp,
                                  ORDER_TIME_GTC, 0, g_gui_applied_config.order_comment);
     }

   const uint retcode = g_trade.ResultRetcode();
   if(!sent || (retcode != TRADE_RETCODE_DONE && retcode != TRADE_RETCODE_PLACED)
      || g_trade.ResultOrder() == 0)
     {
      PrintFormat("Reverse pending failed, retcode=%u, %s",
                  retcode, g_trade.ResultRetcodeDescription());
      return false;
     }
   g_pending_ticket = g_trade.ResultOrder();
   g_pending_index = (g_cycle_index + 1) % CycleLength(g_active_cycle_mode);
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
   if(g_gui_applied_config.grid_count <= 0 || g_group_stop_points <= 0
      || g_group_anchor_price <= 0.0)
      return 0.0;
   const double distance = g_group_stop_points * _Point * level
                           / g_gui_applied_config.grid_count;
   if(position_type == POSITION_TYPE_BUY)
      return PriceNormalize(g_group_anchor_price - distance);
   return PriceNormalize(g_group_anchor_price + distance);
  }

double FavorableGridLevelPrice(const long position_type, const int level)
  {
   if(g_gui_applied_config.grid_count <= 0 || g_group_stop_points <= 0
      || g_group_anchor_price <= 0.0)
      return 0.0;
   const double distance = g_group_stop_points * _Point * level
                           / g_gui_applied_config.grid_count;
   if(position_type == POSITION_TYPE_BUY)
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
   for(int level = 1; level < g_gui_applied_config.grid_count; level++)
      if((mask & GridLevelBit(level)) != 0)
         count++;
   return count;
  }

int HighestFavorableGridLevel(const long mask)
  {
   for(int level = g_gui_applied_config.grid_count - 1; level >= 1; level--)
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
   const int favorable_marker = StringFind(comment, ".Grid.F.");
   if(favorable_marker >= 0)
      return (int)StringToInteger(StringSubstr(comment, favorable_marker + 8));
   const int marker = StringFind(comment, ".Grid.");
   if(marker < 0)
      return 0;
   return (int)StringToInteger(StringSubstr(comment, marker + 6));
  }

bool IsGridPendingAtLevel(const long order_type, const string comment,
                          const double order_price, const double order_volume,
                          const long expected_direction, const int expected_level,
                          const double expected_price, const double expected_volume)
  {
   const int comment_level = GridPendingLevelFromComment(comment);
   if(comment_level > 0 && comment_level != expected_level)
      return false;
   return IsReversePendingType(order_type) && IsGridPendingComment(comment)
          && !IsInitialPendingComment(comment)
          && PendingDirection(order_type) == expected_direction
          && MathAbs(order_price - expected_price) <= _Point * 0.5
          && MathAbs(order_volume - expected_volume)
             <= SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP) * 0.5;
  }

bool NormalizeGridPendingLevel(const long expected_direction, const int expected_level,
                               const double expected_price, const double expected_volume,
                               ulong &keep_ticket)
  {
   keep_ticket = 0;
   bool keep_favorable = false;
   for(int index = 0; index < OrdersTotal(); index++)
     {
      const ulong candidate = OrderGetTicket(index);
      if(candidate == 0
         || OrderGetString(ORDER_SYMBOL) != _Symbol
         || (ulong)OrderGetInteger(ORDER_MAGIC) != g_gui_applied_config.magic_number
         || !IsGridPendingAtLevel(OrderGetInteger(ORDER_TYPE),
                                  OrderGetString(ORDER_COMMENT),
                                  OrderGetDouble(ORDER_PRICE_OPEN),
                                  OrderGetDouble(ORDER_VOLUME_CURRENT),
                                  expected_direction, expected_level,
                                  expected_price, expected_volume))
         continue;
      if(keep_ticket == 0 || candidate < keep_ticket)
        {
         keep_ticket = candidate;
         keep_favorable = StringFind(OrderGetString(ORDER_COMMENT), ".Grid.F.") >= 0;
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
      const ulong candidate = OrderGetTicket(index);
      if(candidate == 0 || candidate == keep_ticket
         || OrderGetString(ORDER_SYMBOL) != _Symbol
         || (ulong)OrderGetInteger(ORDER_MAGIC) != g_gui_applied_config.magic_number
         || !IsGridPendingAtLevel(OrderGetInteger(ORDER_TYPE),
                                  OrderGetString(ORDER_COMMENT),
                                  OrderGetDouble(ORDER_PRICE_OPEN),
                                  OrderGetDouble(ORDER_VOLUME_CURRENT),
                                  expected_direction, expected_level,
                                  expected_price, expected_volume))
         continue;
      if(!DeletePendingTicket(candidate, "Grid level duplicate delete"))
         normalized = false;
     }
   return normalized;
  }

bool FindFilledGridPosition(const long position_type, const int level,
                            const bool favorable, double &fill_price)
  {
   for(int index = PositionsTotal() - 1; index >= 0; index--)
     {
      const ulong ticket = PositionGetTicket(index);
      if(!IsOurPosition(ticket) || PositionGetInteger(POSITION_TYPE) != position_type)
         continue;
      const string comment = PositionGetString(POSITION_COMMENT);
      if(!IsGridPendingComment(comment)
         || GridPendingLevelFromComment(comment) != level
         || (StringFind(comment, ".Grid.F.") >= 0) != favorable)
         continue;
      fill_price = PositionGetDouble(POSITION_PRICE_OPEN);
      return true;
     }
   return false;
  }

bool FindFilledGridOrder(const long position_type, const int level,
                         const double expected_price, const bool favorable,
                         double &fill_price)
  {
   if(level <= 0 || level >= MAX_GRID_COUNT)
      return false;
   if(FindFilledGridPosition(position_type, level, favorable, fill_price))
      return true;
   ulong ticket = favorable ? g_favorable_grid_order_tickets[level]
                            : g_grid_order_tickets[level];
   if(ticket == 0 || !HistoryOrderSelect(ticket))
      return false;
   const string comment = HistoryOrderGetString(ticket, ORDER_COMMENT);
   if(HistoryOrderGetString(ticket, ORDER_SYMBOL) == _Symbol
      && (ulong)HistoryOrderGetInteger(ticket, ORDER_MAGIC)
         == g_gui_applied_config.magic_number
      && HistoryOrderGetInteger(ticket, ORDER_STATE) == ORDER_STATE_FILLED
      && IsGridPendingComment(comment)
      && GridPendingLevelFromComment(comment) == level
      && PendingDirection(HistoryOrderGetInteger(ticket, ORDER_TYPE)) == position_type
      && MathAbs(HistoryOrderGetDouble(ticket, ORDER_PRICE_OPEN) - expected_price)
         <= _Point * 0.5)
     {
      fill_price = HistoryOrderGetDouble(ticket, ORDER_PRICE_OPEN);
      return true;
     }
   return false;
  }

bool PlaceGridPending(const long position_type, const int level, const bool favorable)
  {
   if(g_gui_applied_config.cost_mode)
     { Print("[COST_REJECT=SERVER_GRID_PENDING]"); return false; }
   if(g_gui_applied_config.grid_count < 2 || level <= 0
      || level >= g_gui_applied_config.grid_count
      || g_grid_lots <= 0.0 || g_group_anchor_price <= 0.0)
      return false;

   const double entry = favorable ? FavorableGridLevelPrice(position_type, level)
                                  : GridLevelPrice(position_type, level);
   double stop_loss = GroupStopPrice(position_type);
   double take_profit = favorable ? GroupTakeProfitPrice(position_type)
                        : position_type == POSITION_TYPE_BUY
                          ? PriceNormalize(entry + g_group_take_profit_points * _Point)
                          : PriceNormalize(entry - g_group_take_profit_points * _Point);
   string reason = "";
   if(!ValidateStops((ENUM_POSITION_TYPE)position_type, entry,
                     stop_loss, take_profit, reason))
     {
      PrintFormat("Grid pending stops rejected: entry=%.5f sl=%.5f tp=%.5f %s",
                  entry, stop_loss, take_profit, reason);
      return false;
     }
   if(favorable
      && MathAbs(take_profit - GroupTakeProfitPrice(position_type)) > _Point * 0.5)
      return false;
   const double volume = VolumeNormalize(g_grid_lots);
   const long pending_type = PendingTypeForDirection(position_type == POSITION_TYPE_BUY
                                                     ? ORDER_TYPE_BUY : ORDER_TYPE_SELL,
                                                     entry);
    const string grid_comment = g_gui_applied_config.order_comment
                                + (favorable ? ".Grid.F." : ".Grid.")
                                + IntegerToString(level);
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
   const uint retcode = g_trade.ResultRetcode();
   if(!sent || (retcode != TRADE_RETCODE_DONE && retcode != TRADE_RETCODE_PLACED)
      || g_trade.ResultOrder() == 0)
     {
      PrintFormat("Grid pending failed, retcode=%u, %s",
                  retcode, g_trade.ResultRetcodeDescription());
      return false;
     }
    if(favorable)
      {
       g_favorable_grid_pending_level = level;
       g_favorable_grid_pending_price = entry;
       g_favorable_grid_order_tickets[level] = g_trade.ResultOrder();
      }
    else
      {
       g_grid_pending_level = level;
       g_grid_pending_price = entry;
       g_grid_order_tickets[level] = g_trade.ResultOrder();
      }
   SaveState();
   return true;
  }

string StrategyStateText(const StrategyState state)
  {
   switch(state)
     {
      case STATE_IDLE: return "IDLE";
      case STATE_SIGNAL_READY: return "SIGNAL_READY";
      case STATE_ORDER_SENDING: return "ORDER_SENDING";
      case STATE_POSITION_ACTIVE: return "POSITION_ACTIVE";
      case STATE_PROTECTION_PENDING: return "PROTECTION_PENDING";
      case STATE_RECOVERY: return "RECOVERY";
      case STATE_PAUSED_TEMP: return "PAUSED_TEMP";
      case STATE_FATAL: return "FATAL";
     }
   return "UNKNOWN";
  }

long BuildSignalId(const datetime bar_time, const long direction)
  {
   const long safe_bar = bar_time > 0 ? (long)bar_time : (long)TimeCurrent();
   return safe_bar * 10 + direction;
  }

void LogSingleTradeEvent(const string event, const uint retcode = 0,
                         const ulong ticket = 0, const double entry = 0.0,
                         const double stop_loss = 0.0, const double take_profit = 0.0,
                         const string error = "")
  {
   const double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   const double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   const long stop_level = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   const long freeze_level = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL);
   const double tick_size = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   PrintFormat("[GROUP=single][STATE=%s][EVENT=%s][POSITION=%I64u][ORDER=%I64u] "
               "[DEAL=0][SIGNAL_ID=%I64d][BAR_TIME=%s][BID=%.5f][ASK=%.5f] "
               "[ENTRY=%.5f][SL=%.5f][TP=%.5f][STOP_LEVEL=%I64d][FREEZE_LEVEL=%I64d] "
               "[TICK_SIZE=%.10f][RETCODE=%u][ERROR=%s]",
               StrategyStateText(g_strategy_state), event, g_position_ticket,
               g_trade_request_order_ticket, g_trade_request_signal_id,
               TimeToString(g_trade_request_bar_time, TIME_DATE|TIME_MINUTES),
               bid, ask, entry, stop_loss, take_profit, stop_level, freeze_level,
               tick_size, retcode, error);
  }

bool FindPositionForOrderType(const long order_type, ulong &ticket)
  {
   const long position_type = order_type == ORDER_TYPE_BUY
                              ? POSITION_TYPE_BUY : POSITION_TYPE_SELL;
   for(int index = 0; index < PositionsTotal(); index++)
     {
      const ulong candidate = PositionGetTicket(index);
      if(!IsOurPosition(candidate)
         || PositionGetInteger(POSITION_TYPE) != position_type)
         continue;
      ticket = candidate;
      return true;
     }
   return false;
  }

bool RecoverDuplicateSingleGroupExposure()
  {
   if(!DeleteAllPending())
     {
      g_strategy_state = STATE_RECOVERY;
      Print("[GROUP=single][STATE=RECOVERY][EVENT=DUPLICATE_PENDING_CLEANUP_RETRY] "
            "pending orders remain; new orders stay blocked until cleanup succeeds.");
      return false;
     }

   ulong primary_base_ticket = 0;
   long primary_time_msc = LONG_MAX;
   for(int index = 0; index < PositionsTotal(); index++)
     {
      const ulong candidate = PositionGetTicket(index);
      if(!IsOurPosition(candidate)
         || IsGridPendingComment(PositionGetString(POSITION_COMMENT)))
         continue;
      const long open_time_msc = PositionGetInteger(POSITION_TIME_MSC);
      if(primary_base_ticket == 0 || open_time_msc < primary_time_msc
         || (open_time_msc == primary_time_msc && candidate < primary_base_ticket))
        {
         primary_base_ticket = candidate;
         primary_time_msc = open_time_msc;
        }
     }

   bool recovered = true;
   for(int index = PositionsTotal() - 1; index >= 0; index--)
     {
      const ulong candidate = PositionGetTicket(index);
      if(!IsOurPosition(candidate)
         || IsGridPendingComment(PositionGetString(POSITION_COMMENT))
         || candidate == primary_base_ticket)
         continue;
      if(!g_trade.PositionClose(candidate))
        {
         recovered = false;
         PrintFormat("[GROUP=single][STATE=RECOVERY][EVENT=DUPLICATE_CLOSE_FAILED] "
                     "[POSITION=%I64u][RETCODE=%u][ERROR=%s]",
                     candidate, g_trade.ResultRetcode(),
                     g_trade.ResultRetcodeDescription());
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
      const long left_time_msc = PositionGetInteger(POSITION_TIME_MSC);
      for(int right = left + 1; right < PositionsTotal(); right++)
        {
         const ulong right_ticket = PositionGetTicket(right);
         if(!IsOurPosition(right_ticket)
            || !IsGridPendingComment(PositionGetString(POSITION_COMMENT))
            || PositionGetInteger(POSITION_TYPE) != left_type
            || MathAbs(PositionGetDouble(POSITION_PRICE_OPEN) - left_price)
               > price_tolerance
            || MathAbs(PositionGetDouble(POSITION_VOLUME) - left_volume)
               > volume_tolerance)
            continue;
         const long right_time_msc = PositionGetInteger(POSITION_TIME_MSC);
         const ulong close_ticket = right_time_msc > left_time_msc
                                    || (right_time_msc == left_time_msc
                                        && right_ticket > left_ticket)
                                    ? right_ticket : left_ticket;
         if(!g_trade.PositionClose(close_ticket))
           {
            recovered = false;
            PrintFormat("[GROUP=single][STATE=RECOVERY][EVENT=DUPLICATE_GRID_CLOSE_FAILED] "
                        "[POSITION=%I64u][RETCODE=%u][ERROR=%s]",
                        close_ticket, g_trade.ResultRetcode(),
                        g_trade.ResultRetcodeDescription());
           }
        }
     }

   if(recovered && !HasDuplicateSingleGroupExposure())
     {
      g_duplicate_exposure_logged = false;
      g_strategy_state = g_position_ticket > 0
                         ? STATE_POSITION_ACTIVE : STATE_RECOVERY;
      PrintFormat("[GROUP=single][STATE=%s][EVENT=DUPLICATE_RECOVERED] "
                  "primary_position=%I64u; pending orders canceled; group resumed.",
                  StrategyStateText(g_strategy_state), primary_base_ticket);
      return true;
     }
   g_strategy_state = STATE_RECOVERY;
   Print("[GROUP=single][STATE=RECOVERY][EVENT=DUPLICATE_RECOVERY_RETRY] "
         "duplicate exposure remains; retrying on the next tick.");
   return false;
  }

bool PrepareInitialSignal(const datetime bar_time, const long direction)
  {
   const long signal_id = BuildSignalId(bar_time, direction);
   if(g_signal_consumed && g_signal_id == signal_id
      && g_signal_bar_time == bar_time && g_signal_direction == direction)
     {
      if(g_signal_retry_count >= 3 || TimeCurrent() < g_signal_retry_after)
         return false;
     }
   if(g_signal_id != signal_id || g_signal_bar_time != bar_time
      || g_signal_direction != direction)
      g_signal_retry_count = 0;
   g_signal_consumed = true;
   g_signal_id = signal_id;
   g_signal_bar_time = bar_time;
   g_signal_direction = direction;
   g_signal_retry_after = 0;
   g_strategy_state = STATE_SIGNAL_READY;
   LogSingleTradeEvent("SIGNAL_READY");
   return true;
  }

void ClearTradeRequest(const string event)
  {
   g_trade_request_in_flight = false;
   g_trade_request_order_ticket = 0;
   g_trade_request_position_ticket = 0;
   g_trade_request_signal_id = 0;
   g_trade_request_bar_time = 0;
   g_trade_request_direction = ORDER_TYPE_BUY;
   g_trade_request_volume = 0.0;
   g_trade_request_started = 0;
   g_trade_request_retry_count = 0;
   if(g_position_ticket > 0)
      g_strategy_state = STATE_POSITION_ACTIVE;
   else if(g_strategy_state != STATE_PAUSED_TEMP)
      g_strategy_state = STATE_RECOVERY;
   LogSingleTradeEvent(event);
  }

bool ConfirmTradeRequestFromVisiblePosition()
  {
   if(!g_trade_request_in_flight)
      return true;
   ulong ticket = 0;
   if(g_gui_applied_config.cost_mode)
     {
      if(g_trade_request_order_ticket == 0
         || !HistorySelect(g_trade_request_started, TimeCurrent())) return false;
      long position_id = 0;
      for(int index = 0; index < HistoryDealsTotal(); index++)
        {
         const ulong deal = HistoryDealGetTicket(index);
         if((ulong)HistoryDealGetInteger(deal, DEAL_ORDER) == g_trade_request_order_ticket
            && (ulong)HistoryDealGetInteger(deal, DEAL_MAGIC) == g_gui_applied_config.magic_number
            && HistoryDealGetInteger(deal, DEAL_ENTRY) == DEAL_ENTRY_IN)
           { position_id = HistoryDealGetInteger(deal, DEAL_POSITION_ID); break; }
        }
      if(position_id == 0) return false;
      for(int index = PositionsTotal() - 1; index >= 0; index--)
        {
         const ulong candidate = PositionGetTicket(index);
         if(IsOurPosition(candidate)
            && PositionGetInteger(POSITION_IDENTIFIER) == position_id)
           { ticket = candidate; break; }
        }
      if(ticket == 0) return false;
      CostRememberPositionId(position_id);
     }
   else if(!FindPositionForOrderType(g_trade_request_direction, ticket))
      return false;
   g_position_ticket = ticket;
   g_last_trade_time = TimeCurrent();
   g_trade_request_position_ticket = ticket;
   g_trade_request_in_flight = false;
   g_signal_retry_count = 0;
   g_signal_retry_after = 0;
   g_strategy_state = STATE_POSITION_ACTIVE;
   LogSingleTradeEvent("POSITION_CONFIRMED", 0, ticket);
   return true;
  }

bool ConfirmTradeRequestFromTransaction(const MqlTradeTransaction &trans)
  {
   if(!g_trade_request_in_flight || trans.type != TRADE_TRANSACTION_DEAL_ADD
      || trans.deal == 0 || trans.symbol != _Symbol)
      return false;
   if(g_gui_applied_config.cost_mode && g_trade_request_order_ticket != 0
      && trans.order != g_trade_request_order_ticket)
      return false;
   if(!HistoryDealSelect(trans.deal))
      return false;
   if((ulong)HistoryDealGetInteger(trans.deal, DEAL_MAGIC)
         != g_gui_applied_config.magic_number
      || HistoryDealGetInteger(trans.deal, DEAL_ENTRY) != DEAL_ENTRY_IN)
      return false;
   const long deal_type = HistoryDealGetInteger(trans.deal, DEAL_TYPE);
   const long expected_deal_type = g_trade_request_direction == ORDER_TYPE_BUY
                                   ? DEAL_TYPE_BUY : DEAL_TYPE_SELL;
   if(deal_type != expected_deal_type)
      return false;
   if(g_gui_applied_config.cost_mode)
      CostRememberPositionId(HistoryDealGetInteger(trans.deal, DEAL_POSITION_ID));
   g_position_ticket = trans.position;
   g_last_trade_time = TimeCurrent();
   g_trade_request_position_ticket = trans.position;
   g_trade_request_order_ticket = trans.order;
   g_trade_request_in_flight = false;
   g_signal_retry_count = 0;
   g_signal_retry_after = 0;
   g_strategy_state = STATE_POSITION_ACTIVE;
   LogSingleTradeEvent("DEAL_CONFIRMED", 0, trans.position,
                       trans.price, 0.0, 0.0,
                       HistoryDealGetString(trans.deal, DEAL_COMMENT));
   return true;
  }

bool IsAmbiguousTradeRetcode(const uint retcode)
  {
   return retcode == TRADE_RETCODE_TIMEOUT
          || retcode == TRADE_RETCODE_PRICE_CHANGED
          || retcode == TRADE_RETCODE_PRICE_OFF
          || retcode == TRADE_RETCODE_REQUOTE
          || retcode == TRADE_RETCODE_LOCKED
          || retcode == TRADE_RETCODE_TOO_MANY_REQUESTS;
  }

void HandleTradeRequestFailure(const uint retcode, const string description)
  {
   g_strategy_state = STATE_RECOVERY;
   g_trade_request_retry_count++;
   if(g_signal_consumed && g_trade_request_signal_id == g_signal_id)
     {
      g_signal_retry_count++;
      g_signal_retry_after = TimeCurrent() + 1;
     }
   LogSingleTradeEvent("REQUEST_FAILED", retcode, 0, 0.0, 0.0, 0.0, description);
   if(IsAmbiguousTradeRetcode(retcode))
      return;
   ClearTradeRequest("REQUEST_RELEASED");
  }

bool PrepareGridPendingForCurrentStop(const long position_type, const double entry,
                                      const bool favorable, ulong &ticket)
  {
   if(ticket == 0)
      return true;
   const double stop_loss = GroupStopPrice(position_type);
   const double tolerance = _Point * 0.5;
   const bool adverse_level_invalid = !favorable
                                      && ((position_type == POSITION_TYPE_BUY
                                           && entry <= stop_loss + tolerance)
                                          || (position_type == POSITION_TYPE_SELL
                                              && entry >= stop_loss - tolerance));
   if(!OrderSelect(ticket))
     {
      ticket = 0;
      return true;
     }
   const double expected_take_profit = GroupTakeProfitPrice(position_type);
   const bool wrong_take_profit = favorable
                                  && MathAbs(OrderGetDouble(ORDER_TP) - expected_take_profit)
                                     > tolerance;
   if(!adverse_level_invalid
      && (g_gui_applied_config.dynamic_stop_loss_enable != 1
          || MathAbs(OrderGetDouble(ORDER_SL) - stop_loss) <= tolerance)
      && !wrong_take_profit)
      return true;
   if(!DeletePendingTicket(ticket, "Dynamic grid pending cleanup"))
      return false;
   ticket = 0;
   return true;
  }

bool HandleGridFill(const long position_type)
  {
   if(g_gui_applied_config.grid_count < 2 || g_group_anchor_price <= 0.0)
      return false;
   const double current_total_lots = TotalPositionVolume(position_type);

   bool changed = false;
   double latest_entry = 0.0;
   for(int level = 1; level < g_gui_applied_config.grid_count; level++)
     {
      const long level_bit = GridLevelBit(level);
      if(level_bit == 0 || (g_grid_filled_mask & level_bit) != 0)
         continue;
      double fill_price = 0.0;
      if(FindFilledGridOrder(position_type, level,
                             GridLevelPrice(position_type, level), false,
                             fill_price))
        {
         g_grid_filled_mask |= level_bit;
         latest_entry = fill_price;
         changed = true;
         }
      }
    if(g_gui_applied_config.favorable_grid_enable == 1)
      for(int level = 1; level < g_gui_applied_config.grid_count; level++)
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
   if(g_gui_applied_config.first_order_lot_type == 2 && first_lots > 0.0
      && MathAbs(g_gui_applied_config.first_order_mult
                 - g_gui_applied_config.grid_lot_multiplier) < 0.00000001)
      return VolumeNormalize(first_lots);
   return calculated_grid_lots;
  }

void EnsureGridPending(const long position_type)
  {
   g_grid_lots = GridLotsForNewGroup(g_group_first_lots, g_grid_lots);
   if(g_gui_applied_config.grid_count < 2)
     {
      g_grid_pending_level = 0;
      g_grid_pending_price = 0.0;
      g_favorable_grid_pending_level = 0;
      g_favorable_grid_pending_price = 0.0;
      return;
     }
   const long expected_direction = position_type == POSITION_TYPE_BUY
                                   ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   const double expected_volume = VolumeNormalize(g_grid_lots);
   g_grid_pending_level = 0;
   g_grid_pending_price = 0.0;
   for(int level = 1; level < g_gui_applied_config.grid_count; level++)
     {
      if((g_grid_filled_mask & GridLevelBit(level)) != 0)
         continue;
      const double expected_price = GridLevelPrice(position_type, level);
      ulong grid_ticket = 0;
       if(!NormalizeGridPendingLevel(expected_direction, level, expected_price,
                                     expected_volume, grid_ticket))
          continue;
       if(!PrepareGridPendingForCurrentStop(position_type, expected_price, false,
                                            grid_ticket))
          return;
       if(grid_ticket == 0
          && ((position_type == POSITION_TYPE_BUY
               && expected_price <= GroupStopPrice(position_type) + _Point * 0.5)
              || (position_type == POSITION_TYPE_SELL
                  && expected_price >= GroupStopPrice(position_type) - _Point * 0.5)))
          continue;
       if(grid_ticket == 0)
          PlaceGridPending(position_type, level, false);
      if(grid_ticket > 0 || g_grid_pending_level == level)
        {
         g_grid_pending_level = level;
         g_grid_pending_price = expected_price;
        }
      }
    g_favorable_grid_pending_level = 0;
    g_favorable_grid_pending_price = 0.0;
    if(g_gui_applied_config.favorable_grid_enable == 1)
      for(int level = 1; level < g_gui_applied_config.grid_count; level++)
        {
         if((g_favorable_grid_filled_mask & GridLevelBit(level)) != 0)
            continue;
         const double expected_price = FavorableGridLevelPrice(position_type, level);
         ulong grid_ticket = 0;
          if(!NormalizeGridPendingLevel(expected_direction, level, expected_price,
                                        expected_volume, grid_ticket))
             continue;
          if(!PrepareGridPendingForCurrentStop(position_type, expected_price, true,
                                               grid_ticket))
             return;
          if(grid_ticket == 0)
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

void EnsureNextPending(const long position_type, const double stop_loss,
                       const double take_profit, const double fallback_volume)
  {
   if(g_reversal_count >= g_gui_applied_config.max_reversals)
      return;

   const long expected_direction = SequenceDirection(NextCycleIndex());
   ReversalLotPlan plan;
   if(!BuildReversalLotPlan(NextGroupLotsRaw(fallback_volume), plan)
      || plan.status != REVERSAL_LOT_SINGLE)
      return;
   const double expected_volume = VolumeNormalize(plan.first_lots);
   const double expected_price = PriceNormalize(stop_loss);
   ulong active_pending = 0;
   if(!NormalizeSingleGroupPending(false, expected_direction, expected_price,
                                   expected_volume, active_pending))
      return;
   if(active_pending == 0)
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

   const long current_direction = SequenceDirection(g_cycle_index);
   const long reverse_direction = g_pending_index >= 0
                                  ? SequenceDirection(g_pending_index)
                                  : SequenceDirection(NextCycleIndex());
   const double reverse_price = GroupStopPrice(current_direction);
   const double reverse_volume = NextGroupLots(g_group_total_lots > 0.0
                                                ? g_group_total_lots
                                                : g_gui_applied_config.initial_lots);
   ulong reverse_ticket = 0;
   if(!NormalizeSingleGroupPending(false, reverse_direction, reverse_price,
                                   reverse_volume, reverse_ticket))
      return false;

   EnsureGridPending(current_direction);
   return true;
  }

bool Transition(const long position_type, const double volume,
                const double stop_loss, const double take_profit)
  {
   if(g_reversal_count >= g_gui_applied_config.max_reversals)
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
   // A stop transition is a market-order transition.  Any reverse pending
   // order from the stopped group is stale now, including a stale ticket
   // whose history status can no longer be trusted.
   g_pending_ticket = 0;
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
     g_group_first_lots = g_group_total_lots;
    g_grid_filled_levels = 0;
    g_grid_filled_mask = 0;
    g_grid_pending_level = 0;
    g_grid_pending_price = 0.0;
    g_favorable_grid_filled_levels = 0;
    g_favorable_grid_filled_mask = 0;
    g_favorable_grid_pending_level = 0;
    g_favorable_grid_pending_price = 0.0;
   ClearGridOrderTicketCache();
    g_grid_lots = VolumeNormalize(
      g_previous_grid_lots * g_gui_applied_config.grid_lot_multiplier);
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

   const long expected_direction = SequenceDirection(g_cycle_index);
   const double expected_volume = NextGroupLotsAfterStopRaw(g_group_first_lots);
   ReversalLotPlan recovery_plan;
   if(!BuildReversalLotPlan(expected_volume, recovery_plan))
      return false;
   if(recovery_plan.status == REVERSAL_LOT_RESTART_GROUP)
     {
      ResetOrderGroupAfterOversizedReversal();
      return false;
     }
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
      if(position_type != expected_direction || total > expected_volume + tolerance)
        {
         PrintFormat("Transition recovery conflict, id=%I64d, expected_type=%d, expected_volume=%.2f, "
                     "actual_type=%d, actual_volume=%.2f",
                     g_transition_id, expected_direction, expected_volume, position_type, total);
         return false;
        }
      if(total + tolerance < expected_volume)
        {
         if(!OpenMarket(expected_direction, expected_volume))
            return false;
         if(!FindPosition(ticket, position_type, volume, entry, stop_loss, take_profit)
            || position_type != expected_direction
            || TotalPositionVolume(position_type) + tolerance < expected_volume)
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
     g_group_first_lots = g_group_total_lots;
    g_grid_filled_levels = 0;
    g_grid_filled_mask = 0;
    g_grid_pending_level = 0;
    g_grid_pending_price = 0.0;
    g_favorable_grid_filled_levels = 0;
    g_favorable_grid_filled_mask = 0;
    g_favorable_grid_pending_level = 0;
    g_favorable_grid_pending_price = 0.0;
   ClearGridOrderTicketCache();
    g_grid_lots = VolumeNormalize(
      g_previous_grid_lots * g_gui_applied_config.grid_lot_multiplier);
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

   const long position_type = g_last_position_type;
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

void CostManage()
  {
   if(GuiProcessPendingReset()) return;
   if(g_trade_request_in_flight)
     {
      if(!ConfirmTradeRequestFromVisiblePosition()) return;
      // A fill made visible after an ambiguous result needs reconciliation.
      g_cost_frozen = true;
      SaveState();
     }
   if(HasOurPending())
     {
      g_cost_frozen = true;
      Print("[COST_FREEZE=LEGACY_SERVER_PENDING]");
      if(!DeleteAllPending()) return;
      SaveState();
     }
   ulong ticket = 0;
   long type = POSITION_TYPE_BUY;
   double volume = 0.0, entry = 0.0, stop_loss = 0.0, take_profit = 0.0;
    if(FindPosition(ticket, type, volume, entry, stop_loss, take_profit))
      {
       g_cost_flat_wait_tick_msc = 0;
      if(!g_cost_active || g_cost_cycle_start <= 0 || g_cost_locked_target <= 0.0)
        {
         g_cost_frozen = true;
         Print("[COST_FREEZE=COST_LEDGER_INCOMPLETE]");
         SaveState();
         return;
        }
      if(g_group_anchor_price <= 0.0) g_group_anchor_price = entry;
      if(g_group_last_entry <= 0.0) g_group_last_entry = entry;
      if(g_group_linear_extreme <= 0.0) g_group_linear_extreme = entry;
      g_group_total_lots = TotalPositionVolume(type);
      if(g_gui_applied_config.take_profit_mode == TAKE_PROFIT_LINEAR)
        {
         const double extreme_quote = type == POSITION_TYPE_BUY
                                      ? SymbolInfoDouble(_Symbol, SYMBOL_ASK)
                                      : SymbolInfoDouble(_Symbol, SYMBOL_BID);
         if((type == POSITION_TYPE_BUY && extreme_quote < g_group_linear_extreme)
            || (type == POSITION_TYPE_SELL && extreme_quote > g_group_linear_extreme))
            g_group_linear_extreme = extreme_quote;
        }
      if(!SetGroupStops(type) || !StopsVerified(type))
        { g_cost_frozen = true; SaveState(); return; }
      const double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      const double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      const double protected_tp = GroupTakeProfitPrice(type);
      if((type == POSITION_TYPE_BUY && bid >= protected_tp)
         || (type == POSITION_TYPE_SELL && ask <= protected_tp))
        {
         if(CloseAllPositions(type)) ClearState();
         return;
        }
      const double protected_sl = GroupStopPrice(type);
      if((type == POSITION_TYPE_BUY && bid <= protected_sl)
         || (type == POSITION_TYPE_SELL && ask >= protected_sl))
        {
         int next_sl_points = 0, next_tp_points = 0;
         const bool have_next_distance = GetActiveDistancePoints(protected_sl,
                                           protected_tp, next_sl_points, next_tp_points);
         const double prior_lots = g_group_total_lots;
         const double prior_grid_lots = g_grid_lots;
         if(!CloseAllPositions(type)) return;
         if(g_reversal_count >= g_gui_applied_config.max_reversals
            || !have_next_distance || g_cost_frozen)
           { Print("[COST_CYCLE_END=STOP]"); ClearState(); return; }
         g_cumulative_loss_lots += prior_lots;
         g_previous_grid_lots = prior_grid_lots;
         g_reversal_count++;
         g_cycle_index = NextCycleIndex();
         const long next_direction = SequenceDirection(g_cycle_index);
         const double next_lots = NextGroupLotsAfterStopRaw(prior_lots);
         g_group_stop_points = next_sl_points;
         g_group_take_profit_points = next_tp_points;
         g_group_anchor_price = 0.0;
         g_group_last_entry = 0.0;
         g_group_linear_extreme = 0.0;
         g_cost_entry_trigger_price = protected_sl;
         g_cost_entry_favorable = false;
         SaveState();
          if(!OpenMarket(next_direction, next_lots))
            {
             if(g_trade_request_in_flight)
               { g_cost_frozen = true; SaveState(); return; }
             Print("[COST_CYCLE_END=REVERSE_GATE]");
             MqlTick end_tick;
             if(SymbolInfoTick(_Symbol, end_tick))
                g_cost_last_end_tick_msc = end_tick.time_msc;
             ClearState();
             return;
           }
         if(!FindPosition(ticket, type, volume, entry, stop_loss, take_profit))
           { g_cost_frozen = true; SaveState(); return; }
         g_group_anchor_price = entry;
         g_group_last_entry = entry;
         g_group_linear_extreme = entry;
         g_group_first_lots = volume;
         g_group_total_lots = TotalPositionVolume(type);
         g_grid_lots = VolumeNormalize(g_previous_grid_lots
                          * g_gui_applied_config.grid_lot_multiplier);
         g_grid_filled_mask = 0;
         g_favorable_grid_filled_mask = 0;
         if(!SetGroupStops(type) || !StopsVerified(type)) g_cost_frozen = true;
         SaveState();
         return;
        }
      if(g_cost_frozen || g_gui_applied_config.grid_count < 2)
        { SaveState(); return; }
      g_grid_lots = GridLotsForNewGroup(g_group_first_lots, g_grid_lots);
      MqlTick tick;
      string quote_reason = "";
      if(!CostQuoteAllowed(g_group_stop_points, tick, quote_reason))
        { PrintFormat("[COST_SKIP=%s]", quote_reason); return; }
      for(int level = 1; level < g_gui_applied_config.grid_count; level++)
        for(int side = 0; side < 2; side++)
          {
           if(side == 1 && g_gui_applied_config.favorable_grid_enable != 1) continue;
           const long bit = GridLevelBit(level);
           if((side == 0 && (g_grid_filled_mask & bit) != 0)
              || (side == 1 && (g_favorable_grid_filled_mask & bit) != 0)) continue;
           const double trigger = side == 0 ? GridLevelPrice(type, level)
                                               : FavorableGridLevelPrice(type, level);
           if(side == 0)
             { g_grid_pending_level = level; g_grid_pending_price = trigger; }
           else
             { g_favorable_grid_pending_level = level; g_favorable_grid_pending_price = trigger; }
           const double quote = type == POSITION_TYPE_BUY ? tick.ask : tick.bid;
           const bool hit = side == 0
              ? (type == POSITION_TYPE_BUY ? quote <= trigger : quote >= trigger)
              : (type == POSITION_TYPE_BUY ? quote >= trigger : quote <= trigger);
           if(!hit) continue;
           if((type == POSITION_TYPE_BUY && trigger <= GroupStopPrice(type) + _Point * 0.5)
              || (type == POSITION_TYPE_SELL && trigger >= GroupStopPrice(type) - _Point * 0.5))
              continue;
           g_cost_entry_trigger_price = trigger;
           g_cost_entry_favorable = side == 1;
           if(!SendMarketLeg(type == POSITION_TYPE_BUY ? ORDER_TYPE_BUY : ORDER_TYPE_SELL,
                             g_grid_lots))
             {
              if(g_trade_request_in_flight) { g_cost_frozen = true; SaveState(); }
              return;
             }
           ulong newest_ticket = 0;
           double newest_entry = 0.0;
           for(int position_index = PositionsTotal() - 1; position_index >= 0; position_index--)
             {
              const ulong candidate = PositionGetTicket(position_index);
              if(IsOurPosition(candidate) && PositionGetInteger(POSITION_TYPE) == type
                 && candidate > newest_ticket)
                { newest_ticket = candidate; newest_entry = PositionGetDouble(POSITION_PRICE_OPEN); }
             }
           if(newest_ticket == 0) { g_cost_frozen = true; SaveState(); return; }
           if(side == 0)
             { g_grid_filled_mask |= bit; g_group_last_entry = newest_entry; }
           else g_favorable_grid_filled_mask |= bit;
           g_group_total_lots = TotalPositionVolume(type);
           if(!SetGroupStops(type) || !StopsVerified(type)) g_cost_frozen = true;
           SaveState();
           return;
          }
      SaveState();
      return;
     }
    if(g_cost_active)
      {
       if(g_cost_cycle_start > 0 && HistorySelect(g_cost_cycle_start, TimeCurrent()))
         {
          // Rebuild ownership before inspecting exits: a broker SL may have
          // removed the position before the terminal dispatches DEAL_ADD.
          for(int index = 0; index < HistoryDealsTotal(); index++)
            {
             const ulong deal = HistoryDealGetTicket(index);
             if(deal <= g_cost_first_deal
                || HistoryDealGetString(deal, DEAL_SYMBOL) != _Symbol
                || HistoryDealGetInteger(deal, DEAL_ENTRY) != DEAL_ENTRY_IN
                || (ulong)HistoryDealGetInteger(deal, DEAL_MAGIC)
                   != g_gui_applied_config.magic_number) continue;
             CostRememberPositionId(HistoryDealGetInteger(deal, DEAL_POSITION_ID));
            }
          for(int index = 0; index < HistoryDealsTotal(); index++)
            {
            const ulong deal = HistoryDealGetTicket(index);
            if(HistoryDealGetString(deal, DEAL_SYMBOL) != _Symbol
               || !CostOwnsPositionId(HistoryDealGetInteger(deal, DEAL_POSITION_ID))
               || HistoryDealGetInteger(deal, DEAL_ENTRY) != DEAL_ENTRY_OUT
               || HistoryDealGetInteger(deal, DEAL_REASON) != DEAL_REASON_SL) continue;
            const long deal_msc = HistoryDealGetInteger(deal, DEAL_TIME_MSC);
             if(deal_msc <= MathMax(g_cost_passive_stop_msc,
                                    g_cost_consumed_stop_msc)) continue;
            g_cost_passive_stop_msc = deal_msc;
            g_cost_passive_stop_price = HistoryDealGetDouble(deal, DEAL_PRICE);
             g_cost_passive_stop_type = HistoryDealGetInteger(deal, DEAL_TYPE) == DEAL_TYPE_SELL
                                        ? POSITION_TYPE_BUY : POSITION_TYPE_SELL;
            }
         }
       if(g_cost_passive_stop_msc == 0)
         {
          MqlTick flat_tick;
          if(SymbolInfoTick(_Symbol, flat_tick))
            {
             if(g_cost_flat_wait_tick_msc == 0)
               { g_cost_flat_wait_tick_msc = flat_tick.time_msc; SaveState(); return; }
             if(flat_tick.time_msc <= g_cost_flat_wait_tick_msc) return;
            }
         }
      if(g_cost_passive_stop_msc > 0 && !g_cost_frozen
         && g_reversal_count < g_gui_applied_config.max_reversals)
        {
         MqlTick tick;
         string reason = "";
         const bool fresh = CostQuoteAllowed(g_group_stop_points, tick, reason)
            && tick.time_msc >= g_cost_passive_stop_msc
            && tick.time_msc - g_cost_passive_stop_msc
               <= g_gui_applied_config.cost_max_quote_age_ms;
         if(fresh)
           {
            const long old_type = g_cost_passive_stop_type;
            const double old_lots = g_group_total_lots;
            int next_sl_points = 0, next_tp_points = 0;
            const bool have_distance = GetActiveDistancePoints(GroupStopPrice(old_type),
                GroupTakeProfitPrice(old_type), next_sl_points, next_tp_points);
            if(have_distance && old_lots > 0.0)
              {
               g_cumulative_loss_lots += old_lots;
               g_previous_grid_lots = g_grid_lots;
               g_reversal_count++;
               g_cycle_index = NextCycleIndex();
               const long next_direction = SequenceDirection(g_cycle_index);
               const double next_lots = NextGroupLotsAfterStopRaw(old_lots);
               g_group_stop_points = next_sl_points;
               g_group_take_profit_points = next_tp_points;
               g_group_anchor_price = 0.0;
               g_group_last_entry = 0.0;
               g_group_linear_extreme = 0.0;
               g_cost_entry_trigger_price = g_cost_passive_stop_price;
               g_cost_entry_favorable = false;
                g_cost_consumed_stop_msc = g_cost_passive_stop_msc;
                g_cost_passive_stop_msc = 0;
               SaveState();
               if(OpenMarket(next_direction, next_lots)
                  && FindPosition(ticket, type, volume, entry, stop_loss, take_profit))
                 {
                  g_group_anchor_price = entry;
                  g_group_last_entry = entry;
                  g_group_linear_extreme = entry;
                  g_group_first_lots = volume;
                  g_group_total_lots = TotalPositionVolume(type);
                  g_grid_lots = VolumeNormalize(g_previous_grid_lots
                                  * g_gui_applied_config.grid_lot_multiplier);
                  g_grid_filled_mask = 0;
                  g_favorable_grid_filled_mask = 0;
                  if(!SetGroupStops(type) || !StopsVerified(type)) g_cost_frozen = true;
                  SaveState();
                  return;
                 }
                if(g_trade_request_in_flight)
                  { g_cost_frozen = true; SaveState(); return; }
                MqlTick rejected_tick;
                if(SymbolInfoTick(_Symbol, rejected_tick))
                   g_cost_last_end_tick_msc = rejected_tick.time_msc;
                const datetime rejected_bar = iTime(_Symbol, _Period, 0);
                PrintFormat("[COST_CYCLE_END=PASSIVE_SL_REVERSE_REJECTED][CYCLE=%I64d][TICK_MSC=%I64d][BAR=%I64d]",
                            (long)g_cost_cycle_start, g_cost_last_end_tick_msc,
                            (long)rejected_bar);
                ClearState();
                MarkCandleEntryBarProcessed(rejected_bar);
                return;
              }
           }
         else PrintFormat("[COST_CYCLE_END=PASSIVE_SL_GATE][REASON=%s]", reason);
        }
       Print(g_cost_passive_stop_msc > 0
             ? "[COST_CYCLE_END=PASSIVE_SL]"
             : "[COST_CYCLE_END=EXTERNAL_CLOSE]");
       MqlTick end_tick;
       if(SymbolInfoTick(_Symbol, end_tick))
          g_cost_last_end_tick_msc = end_tick.time_msc;
       const datetime completed_bar = iTime(_Symbol, _Period, 0);
       ClearState();
       MarkCandleEntryBarProcessed(completed_bar);
       return;
      }
    MqlTick current_cost_tick;
    if(SymbolInfoTick(_Symbol, current_cost_tick)
       && current_cost_tick.time_msc <= g_cost_last_end_tick_msc)
       return;
   if(!GuiAllowsInitialEntry() || !IsInitialEntryAllowed()) return;
   int stop_points = 0, tp_points = 0;
   long first_direction = ORDER_TYPE_BUY;
   double trigger = 0.0;
   if(g_gui_applied_config.distance_mode == DISTANCE_CANDLE_RANGE)
     {
      double high = 0.0, low = 0.0;
      int range_points = 0;
      if(!GetPreviousCandleRange(high, low, range_points)) return;
      const datetime bar = iTime(_Symbol, _Period, 0);
      if(g_gui_applied_config.candle_order_mode == KORDER_ONCE_PER_BAR
         && bar == g_last_candle_entry_bar_time) return;
      if(bar != g_cost_trigger_bar)
        {
         g_cost_trigger_bar = bar;
         g_cost_trigger_high = high;
         g_cost_trigger_low = low;
         SaveState();
        }
      const double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      const double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      const bool high_hit = ask >= high;
      const bool low_hit = bid <= low;
      if(high_hit && low_hit)
        {
         if(g_gui_applied_config.candle_order_mode == KORDER_ONCE_PER_BAR)
            g_last_candle_entry_bar_time = bar;
         SaveState();
         Print("[COST_SKIP=DUAL_CANDLE_TRIGGER]");
         return;
        }
      if(!high_hit && !low_hit) return;
      first_direction = high_hit
         ? (g_gui_applied_config.order_type == ORDERTYPE_FORWARD ? ORDER_TYPE_BUY : ORDER_TYPE_SELL)
         : (g_gui_applied_config.order_type == ORDERTYPE_FORWARD ? ORDER_TYPE_SELL : ORDER_TYPE_BUY);
      trigger = high_hit ? high : low;
      stop_points = range_points;
      tp_points = range_points;
     }
   else
     {
      if(g_gui_applied_config.distance_mode == DISTANCE_LONG_CANDLE)
        { if(!GetLongCandleDirection(first_direction)) return; }
      else if(g_gui_applied_config.first_direction_mode == FIRST_DIRECTION_BOLLINGER)
        { if(!GetBollingerFirstDirection(first_direction)) return; }
      else first_direction = g_gui_applied_config.first_direction == FIRST_SELL
                             ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
      if(!GetDistancePoints(stop_points, tp_points)) return;
      trigger = first_direction == ORDER_TYPE_BUY
                ? SymbolInfoDouble(_Symbol, SYMBOL_ASK)
                : SymbolInfoDouble(_Symbol, SYMBOL_BID);
     }
   if(stop_points <= 0 || tp_points <= 0) return;
   if(!PrepareInitialSignal(iTime(_Symbol, _Period, 0), first_direction)) return;
   g_cost_first_deal = 0;
   if(HistorySelect(0, TimeCurrent()))
      for(int index = 0; index < HistoryDealsTotal(); index++)
         g_cost_first_deal = MathMax(g_cost_first_deal, HistoryDealGetTicket(index));
   else { Print("[COST_REJECT=COST_LEDGER_INCOMPLETE]"); return; }
   g_cost_cycle_start = TimeCurrent();
   g_cost_locked_target = g_gui_applied_config.cost_target_rr > 0.0
                          ? g_gui_applied_config.cost_target_rr
                          : (double)tp_points / stop_points;
   g_cost_active = true;
   g_cost_frozen = false;
   g_cycle_index = 0;
   g_reversal_count = 0;
   g_group_stop_points = stop_points;
   g_group_take_profit_points = tp_points;
   g_active_first_direction = first_direction == ORDER_TYPE_BUY ? FIRST_BUY : FIRST_SELL;
   g_active_cycle_mode = g_gui_applied_config.cycle_mode;
    g_cost_entry_trigger_price = trigger;
    g_cost_entry_favorable = false;
    MqlTick starting_tick;
    if(SymbolInfoTick(_Symbol, starting_tick))
       PrintFormat("[COST_CYCLE_START][CYCLE=%I64d][TICK_MSC=%I64d][PREVIOUS_END_TICK_MSC=%I64d][TRIGGER=%.5f][TARGET=%.3f]",
                   (long)g_cost_cycle_start, starting_tick.time_msc,
                   g_cost_last_end_tick_msc, trigger, g_cost_locked_target);
    SaveState();
   if(!OpenMarket(first_direction, g_gui_applied_config.initial_lots))
     {
      if(g_trade_request_in_flight)
        { g_cost_frozen = true; SaveState(); return; }
      ClearState();
      return;
     }
   if(!FindPosition(ticket, type, volume, entry, stop_loss, take_profit))
     { g_cost_frozen = true; SaveState(); return; }
   g_group_anchor_price = entry;
   g_group_last_entry = entry;
   g_group_linear_extreme = entry;
   g_group_first_lots = volume;
   g_group_total_lots = TotalPositionVolume(type);
   g_grid_lots = volume;
   g_grid_filled_mask = 0;
   g_favorable_grid_filled_mask = 0;
   if(g_gui_applied_config.distance_mode == DISTANCE_CANDLE_RANGE
      && g_gui_applied_config.candle_order_mode == KORDER_ONCE_PER_BAR)
      g_last_candle_entry_bar_time = iTime(_Symbol, _Period, 0);
   if(!SetGroupStops(type) || !StopsVerified(type)) g_cost_frozen = true;
   SaveState();
  }

void Manage()
  {
   if(g_gui_applied_config.cost_mode)
     { CostManage(); return; }
   if(GuiProcessPendingReset())
      return;

   if(g_trade_request_in_flight)
     {
      if(!ConfirmTradeRequestFromVisiblePosition())
        {
         g_strategy_state = STATE_ORDER_SENDING;
         const datetime now = TimeCurrent();
         if(g_last_single_request_wait_log == 0
            || now - g_last_single_request_wait_log >= 10)
           {
            LogSingleTradeEvent("REQUEST_STILL_IN_FLIGHT");
            g_last_single_request_wait_log = now;
           }
         return;
        }
      // Let the following tick initialize the position and its group state.
      // This closes the visibility gap between a DONE result and the
      // terminal's position snapshot.
      return;
     }
   if(!ProtectionRetryAllowed())
      return;

   if(HasDuplicateSingleGroupExposure())
     {
      if(!g_duplicate_exposure_logged)
        {
         Print("[GROUP=single][STATE=RECOVERY][EVENT=DUPLICATE_DETECTED] "
               "pending orders will be canceled and duplicate positions will be normalized automatically.");
         g_duplicate_exposure_logged = true;
        }
      if(!RecoverDuplicateSingleGroupExposure())
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

   const bool candle_once_mode = g_gui_applied_config.distance_mode == DISTANCE_CANDLE_RANGE
                                 && g_gui_applied_config.candle_order_mode == KORDER_ONCE_PER_BAR;
   const datetime current_bar_time = candle_once_mode ? iTime(_Symbol, _Period, 0) : 0;
   if(candle_once_mode && current_bar_time > 0
      && current_bar_time != g_last_candle_entry_bar_time
      && !PrepareCandleOnceEntry(current_bar_time))
      return;

   if(HandleInitialPendingFill())
      return;

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
          if(g_reversal_count >= g_gui_applied_config.max_reversals)
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
          g_group_first_lots = volume;
          g_grid_filled_levels = 0;
          g_grid_filled_mask = 0;
          g_grid_pending_level = 0;
          g_grid_pending_price = 0.0;
          g_favorable_grid_filled_levels = 0;
          g_favorable_grid_filled_mask = 0;
          g_favorable_grid_pending_level = 0;
          g_favorable_grid_pending_price = 0.0;
          ClearGridOrderTicketCache();
          g_grid_lots = VolumeNormalize(
            g_previous_grid_lots * g_gui_applied_config.grid_lot_multiplier);
         g_transition_phase = TRANSITION_COMPLETE;
         g_transition_id = (long)TimeCurrent() * 1000 + g_reversal_count;
        }
       volume = TotalPositionVolume(position_type);
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
                       ? VolumeNormalize(g_previous_grid_lots
                                         * g_gui_applied_config.grid_lot_multiplier)
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
         if(!SetGroupStops(position_type) || !StopsVerified(position_type))
           {
            Print("Position protection is not verified; follow-up orders are paused.");
            SaveState();
            return;
           }
         EnsureNextPending(position_type, GroupStopPrice(position_type),
                           GroupTakeProfitPrice(position_type), volume);
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
       if(g_gui_applied_config.take_profit_mode == TAKE_PROFIT_LINEAR)
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
            const datetime completed_bar_time = iTime(_Symbol, _Period, 0);
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

      EnsureNextPending(position_type, GroupStopPrice(position_type),
                        GroupTakeProfitPrice(position_type), volume);
      EnsureGridPending(position_type);
      return;
     }

   if(PastLastTakeProfit())
     {
      if(!DeleteAllPending())
         return;
      const datetime completed_bar_time = iTime(_Symbol, _Period, 0);
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
   if(!GuiAllowsInitialEntry())
      return;
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
                                   ? (g_gui_applied_config.first_order_lot_type == 2
                                      ? NextGroupLotsAfterStop(g_group_first_lots)
                                      : VolumeNormalize(g_cumulative_loss_lots))
                                   : VolumeNormalize(g_gui_applied_config.initial_lots);
      if(PlaceInitialPendingPair(previous_high, previous_low, range_points, initial_lots))
         MarkCandleEntryBarProcessed(current_bar_time);
      return;
     }

   int initial_stop_points = 0;
   int initial_take_profit_points = 0;
   long first_direction = ORDER_TYPE_BUY;
   if(g_gui_applied_config.distance_mode == DISTANCE_CANDLE_RANGE)
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
      g_active_cycle_mode = g_gui_applied_config.cycle_mode;
     }
   else if(g_gui_applied_config.distance_mode == DISTANCE_LONG_CANDLE)
     {
      if(!GetLongCandleDirection(first_direction)
         || !GetDistancePoints(initial_stop_points, initial_take_profit_points))
         return;
      g_active_first_direction = first_direction == ORDER_TYPE_BUY
                                 ? FIRST_BUY : FIRST_SELL;
      g_active_cycle_mode = g_gui_applied_config.cycle_mode;
     }
   else
     {
      if(g_gui_applied_config.first_direction_mode == FIRST_DIRECTION_BOLLINGER
         && !GetBollingerFirstDirection(first_direction))
         return;
      if(g_gui_applied_config.first_direction_mode == FIRST_DIRECTION_PRESET)
         first_direction = g_gui_applied_config.first_direction == FIRST_SELL
                           ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
      g_active_first_direction = first_direction == ORDER_TYPE_BUY
                                 ? FIRST_BUY : FIRST_SELL;
      g_active_cycle_mode = g_gui_applied_config.cycle_mode;
      if(!GetDistancePoints(initial_stop_points, initial_take_profit_points))
         return;
     }
   g_had_position = false;
   g_cycle_index = 0;
   g_pending_index = -1;
   g_group_stop_points = initial_stop_points;
   g_group_take_profit_points = initial_take_profit_points;
    const double initial_lots = g_cumulative_loss_lots > 0.0
                                ? (g_gui_applied_config.first_order_lot_type == 2
                                   ? NextGroupLotsAfterStop(g_group_first_lots)
                                   : VolumeNormalize(g_cumulative_loss_lots))
                                : VolumeNormalize(g_gui_applied_config.initial_lots);
   if(!PrepareInitialSignal(iTime(_Symbol, _Period, 0), first_direction))
      return;
   if(OpenMarket(first_direction, initial_lots))
     {
      if(g_gui_applied_config.distance_mode == DISTANCE_CANDLE_RANGE
         && g_gui_applied_config.candle_order_mode == KORDER_ONCE_PER_BAR)
        {
         const datetime market_entry_bar_time = iTime(_Symbol, _Period, 0);
         if(market_entry_bar_time > 0)
            g_last_candle_entry_bar_time = market_entry_bar_time;
        }
       if(FindPosition(position_ticket, position_type, volume, entry,
                       stop_loss, take_profit))
         {
          g_position_ticket = position_ticket;
          g_strategy_state = STATE_POSITION_ACTIVE;
          g_group_anchor_price = entry;
          g_group_last_entry = entry;
          g_group_linear_extreme = entry;
          g_group_first_lots = volume;
          g_group_total_lots = TotalPositionVolume(position_type);
         g_grid_filled_levels = 0;
         g_grid_filled_mask = 0;
         g_grid_pending_level = 0;
          g_grid_pending_price = 0.0;
         ClearGridOrderTicketCache();
         g_grid_lots = g_previous_grid_lots > 0.0
                       ? VolumeNormalize(g_previous_grid_lots
                                         * g_gui_applied_config.grid_lot_multiplier)
                       : g_group_total_lots;
        }
      SaveState();
      Manage();
      }
  }

struct MultiGroupState
  {
   bool     cost_active;
   bool     cost_frozen;
   datetime cost_start;
   double   cost_target;
   double   cost_tp;
   double   cost_risk;
   datetime cost_bar;
   double   cost_high;
   double   cost_low;
    long     cost_stop_msc;
    ulong    cost_stop_deal;
    ulong    cost_consumed_stop_deal;
   double   cost_stop_price;
   long     cost_stop_type;
   int      id;
   bool     active;
   bool     dirty;
   int      pair_role;
   int      pair_peer_id;
   int      pair_failure_retcode;
   bool     initial_pair_incomplete;
   int      first_direction;
   int      cycle_mode;
   int      cycle_index;
   int      pending_index;
   int      reversal_count;
   ulong    pending_ticket;
   ulong    initial_high_ticket;
   ulong    initial_low_ticket;
   double   initial_high_price;
   double   initial_low_price;
   double   initial_pending_lots;
   long     initial_high_direction;
   long     initial_low_direction;
   ulong    grid_pending_ticket;
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
   ulong    favorable_grid_pending_ticket;
   int      favorable_grid_filled_levels;
   long     favorable_grid_filled_mask;
   int      favorable_grid_pending_level;
   double   favorable_grid_pending_price;
   bool     request_in_flight;
   ulong    request_order_ticket;
   ulong    request_position_ticket;
   long     request_signal_id;
   datetime request_bar_time;
   long     request_direction;
   double   request_volume;
   int      request_retry_count;
   bool     signal_consumed;
   long     signal_id;
   datetime signal_bar_time;
   StrategyState state;
  };

MultiGroupState g_multi_groups[];
datetime g_multi_pair_failure_log_time = 0;
long g_multi_cost_position_ids[];
int g_multi_cost_position_groups[];
long g_multi_closed_position_ids[];
int g_multi_closed_position_groups[];
datetime g_multi_closed_cycle_starts[];

int MultiCostClosedGroupForPosition(const long position_id, datetime &cycle_start)
   {
    cycle_start = 0;
    for(int index = ArraySize(g_multi_closed_position_ids) - 1; index >= 0; index--)
       if(g_multi_closed_position_ids[index] == position_id)
         {
          cycle_start = g_multi_closed_cycle_starts[index];
          return g_multi_closed_position_groups[index];
         }
    return 0;
   }

void MultiCostArchiveGroup(const int group_id, const datetime cycle_start)
   {
    const string prefix = StatePrefix() + ".multi.cost.archive";
    for(int index = 0; index < ArraySize(g_multi_cost_position_ids); index++)
      {
       if(g_multi_cost_position_groups[index] != group_id) continue;
       datetime previous_start = 0;
       if(MultiCostClosedGroupForPosition(g_multi_cost_position_ids[index],
                                          previous_start) > 0) continue;
       const int count = ArraySize(g_multi_closed_position_ids);
       if(count >= 4096 || ArrayResize(g_multi_closed_position_ids, count + 1) != count + 1
          || ArrayResize(g_multi_closed_position_groups, count + 1) != count + 1
          || ArrayResize(g_multi_closed_cycle_starts, count + 1) != count + 1)
         { PrintFormat("[MULTI_COST_ARCHIVE_FULL][GROUP=%d][LATE_FEES_UNATTRIBUTED=1]", group_id); return; }
       g_multi_closed_position_ids[count] = g_multi_cost_position_ids[index];
       g_multi_closed_position_groups[count] = group_id;
       g_multi_closed_cycle_starts[count] = cycle_start;
       GlobalVariableSet(prefix + ".id." + IntegerToString(count),
                         (double)g_multi_closed_position_ids[count]);
       GlobalVariableSet(prefix + ".group." + IntegerToString(count), (double)group_id);
       GlobalVariableSet(prefix + ".start." + IntegerToString(count), (double)cycle_start);
      }
    GlobalVariableSet(prefix + ".count", (double)ArraySize(g_multi_closed_position_ids));
   }

void MultiCostLoadArchive()
   {
    const string prefix = StatePrefix() + ".multi.cost.archive";
    if(!GlobalVariableCheck(prefix + ".count")) return;
    const int count = (int)MathRound(GlobalVariableGet(prefix + ".count"));
    if(count < 0 || count > 4096
       || ArrayResize(g_multi_closed_position_ids, count) != count
       || ArrayResize(g_multi_closed_position_groups, count) != count
       || ArrayResize(g_multi_closed_cycle_starts, count) != count)
      { Print("[MULTI_COST_ARCHIVE_INCOMPLETE]"); return; }
    for(int index = 0; index < count; index++)
      {
       const string id_key = prefix + ".id." + IntegerToString(index);
       const string group_key = prefix + ".group." + IntegerToString(index);
       const string start_key = prefix + ".start." + IntegerToString(index);
       if(!GlobalVariableCheck(id_key) || !GlobalVariableCheck(group_key)
          || !GlobalVariableCheck(start_key))
         { Print("[MULTI_COST_ARCHIVE_INCOMPLETE]"); return; }
       g_multi_closed_position_ids[index] = (long)MathRound(GlobalVariableGet(id_key));
       g_multi_closed_position_groups[index] = (int)MathRound(GlobalVariableGet(group_key));
       g_multi_closed_cycle_starts[index] = (datetime)MathRound(GlobalVariableGet(start_key));
      }
   }

int MultiCostGroupForPosition(const long position_id)
  {
   for(int index = 0; index < ArraySize(g_multi_cost_position_ids); index++)
      if(g_multi_cost_position_ids[index] == position_id)
         return g_multi_cost_position_groups[index];
   return 0;
  }

bool MultiCostRememberPosition(const long position_id, const int group_id)
  {
   if(position_id <= 0 || group_id <= 0) return false;
   const int existing = MultiCostGroupForPosition(position_id);
   if(existing > 0) return existing == group_id;
   const int count = ArraySize(g_multi_cost_position_ids);
   if(count >= 1024 || ArrayResize(g_multi_cost_position_ids, count + 1) != count + 1
      || ArrayResize(g_multi_cost_position_groups, count + 1) != count + 1)
      return false;
   g_multi_cost_position_ids[count] = position_id;
   g_multi_cost_position_groups[count] = group_id;
   return true;
  }

void MultiCostSaveMap()
  {
   const string prefix = StatePrefix() + ".multi.cost";
   GlobalVariableSet(prefix + ".count", (double)ArraySize(g_multi_cost_position_ids));
   for(int index = 0; index < ArraySize(g_multi_cost_position_ids); index++)
     {
      GlobalVariableSet(prefix + ".id." + IntegerToString(index),
                        (double)g_multi_cost_position_ids[index]);
      GlobalVariableSet(prefix + ".group." + IntegerToString(index),
                        (double)g_multi_cost_position_groups[index]);
     }
  }

bool MultiCostLoadMap()
  {
   const string prefix = StatePrefix() + ".multi.cost";
   ArrayResize(g_multi_cost_position_ids, 0);
   ArrayResize(g_multi_cost_position_groups, 0);
   if(!GlobalVariableCheck(prefix + ".count"))
      return ArraySize(g_multi_groups) == 0;
   const int count = (int)MathRound(GlobalVariableGet(prefix + ".count"));
   if(count < 0 || count > 1024
      || ArrayResize(g_multi_cost_position_ids, count) != count
      || ArrayResize(g_multi_cost_position_groups, count) != count) return false;
   for(int index = 0; index < count; index++)
     {
      const string id_key = prefix + ".id." + IntegerToString(index);
      const string group_key = prefix + ".group." + IntegerToString(index);
      if(!GlobalVariableCheck(id_key) || !GlobalVariableCheck(group_key)) return false;
      g_multi_cost_position_ids[index] = (long)MathRound(GlobalVariableGet(id_key));
      g_multi_cost_position_groups[index] = (int)MathRound(GlobalVariableGet(group_key));
     }
   return true;
  }

void MultiCostForgetGroup(const int group_id)
  {
   for(int index = ArraySize(g_multi_cost_position_ids) - 1; index >= 0; index--)
      if(g_multi_cost_position_groups[index] == group_id)
        {
         const int last = ArraySize(g_multi_cost_position_ids) - 1;
         g_multi_cost_position_ids[index] = g_multi_cost_position_ids[last];
         g_multi_cost_position_groups[index] = g_multi_cost_position_groups[last];
         ArrayResize(g_multi_cost_position_ids, last);
         ArrayResize(g_multi_cost_position_groups, last);
        }
   MultiCostSaveMap();
  }
datetime g_multi_last_trigger_bar = 0;
int g_multi_next_id = 1;
ulong g_multi_grid_order_tickets[];
ulong g_multi_favorable_grid_order_tickets[];

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
      ArrayResize(g_multi_grid_order_tickets, required);
   if(ArraySize(g_multi_favorable_grid_order_tickets) < required)
      ArrayResize(g_multi_favorable_grid_order_tickets, required);
  }

void MultiRememberGridOrderTicket(const int group_id, const int level,
                                  const bool favorable, const ulong ticket)
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

ulong MultiGridOrderTicket(const int group_id, const int level,
                           const bool favorable)
  {
   const int cache_index = MultiGridTicketCacheIndex(group_id, level);
   if(cache_index < 0)
      return 0;
   MultiEnsureGridTicketCache(group_id);
   return favorable ? g_multi_favorable_grid_order_tickets[cache_index]
                    : g_multi_grid_order_tickets[cache_index];
  }

bool ResetInMemoryStrategyState()
  {
   if(ArrayResize(g_multi_groups, 0) < 0)
      return false;
   g_multi_last_trigger_bar = 0;
   g_multi_next_id = 1;
   ArrayResize(g_multi_grid_order_tickets, 0);
   ArrayResize(g_multi_favorable_grid_order_tickets, 0);
   g_had_position = false;
   g_last_position_type = POSITION_TYPE_BUY;
   g_last_take_profit = 0.0;
   g_cycle_index = 0;
   g_pending_index = -1;
   g_reversal_count = 0;
   g_pending_ticket = 0;
   g_initial_high_ticket = 0;
   g_initial_low_ticket = 0;
   g_initial_high_price = 0.0;
   g_initial_low_price = 0.0;
   g_initial_high_direction = ORDER_TYPE_BUY;
   g_initial_low_direction = ORDER_TYPE_SELL;
   g_last_candle_entry_bar_time = 0;
   g_transition_phase = TRANSITION_NONE;
   g_transition_id = 0;
   g_reset_pending = false;
   g_active_first_direction = FIRST_BUY;
   g_active_cycle_mode = CYCLE_MODE_1;
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
         ClearGridOrderTicketCache();
         g_grid_pending_level = 0;
    g_grid_pending_price = 0.0;
    g_favorable_grid_filled_levels = 0;
    g_favorable_grid_filled_mask = 0;
    g_favorable_grid_pending_level = 0;
    g_favorable_grid_pending_price = 0.0;
    ClearGridOrderTicketCache();
    return true;
  }

string MultiGroupTag(const int group_id)
  {
   return ".G" + IntegerToString(group_id);
  }

string MultiGroupComment(const int group_id, const bool grid)
  {
   return g_gui_applied_config.order_comment + MultiGroupTag(group_id)
          + (grid ? ".Grid" : "");
  }

string MultiInitialPendingComment(const int group_id, const bool high)
  {
   return g_gui_applied_config.order_comment + MultiGroupTag(group_id)
          + (high ? ".InitialHigh" : ".InitialLow");
  }

string MultiStatePrefix(const int group_id)
  {
   return StatePrefix() + ".multi." + IntegerToString(group_id);
  }

void MultiDeleteState(const int group_id)
  {
   const string prefix = MultiStatePrefix(group_id);
   GlobalVariableDel(prefix + ".cost.active");
   GlobalVariableDel(prefix + ".cost.frozen");
   GlobalVariableDel(prefix + ".cost.start");
   GlobalVariableDel(prefix + ".cost.target");
   GlobalVariableDel(prefix + ".cost.tp");
   GlobalVariableDel(prefix + ".cost.risk");
   GlobalVariableDel(prefix + ".cost.bar");
   GlobalVariableDel(prefix + ".cost.high");
   GlobalVariableDel(prefix + ".cost.low");
    GlobalVariableDel(prefix + ".cost.stopms");
    GlobalVariableDel(prefix + ".cost.stopdeal");
    GlobalVariableDel(prefix + ".cost.consumedstopdeal");
   GlobalVariableDel(prefix + ".cost.stopprice");
   GlobalVariableDel(prefix + ".cost.stoptype");
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
  }

bool MultiCommentMatches(const string comment, const int group_id)
  {
   return StringFind(comment, MultiGroupTag(group_id)) >= 0;
  }

bool MultiIsInitialPendingComment(const string comment)
  {
   return StringFind(comment, ".InitialHigh") >= 0
          || StringFind(comment, ".InitialLow") >= 0;
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
   group.cost_active = false;
   group.cost_frozen = false;
   group.cost_start = 0;
   group.cost_target = 0.0;
   group.cost_tp = 0.0;
   group.cost_risk = -1.0;
   group.cost_bar = 0;
   group.cost_high = 0.0;
   group.cost_low = 0.0;
    group.cost_stop_msc = 0;
    group.cost_stop_deal = 0;
    group.cost_consumed_stop_deal = 0;
   group.cost_stop_price = 0.0;
   group.cost_stop_type = POSITION_TYPE_BUY;
   group.id = group_id;
   group.active = true;
   group.dirty = true;
    group.pair_role = 0;
    group.pair_peer_id = 0;
    group.pair_failure_retcode = 0;
    group.initial_pair_incomplete = false;
   group.first_direction = FIRST_BUY;
   group.cycle_mode = CYCLE_MODE_1;
   group.cycle_index = 0;
   group.pending_index = -1;
   group.reversal_count = 0;
   group.pending_ticket = 0;
   group.initial_high_ticket = 0;
   group.initial_low_ticket = 0;
   group.initial_high_price = 0.0;
   group.initial_low_price = 0.0;
    group.initial_pending_lots = 0.0;
   group.initial_high_direction = ORDER_TYPE_BUY;
   group.initial_low_direction = ORDER_TYPE_SELL;
   group.grid_pending_ticket = 0;
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
   group.favorable_grid_pending_ticket = 0;
   group.favorable_grid_filled_levels = 0;
   group.favorable_grid_filled_mask = 0;
   group.favorable_grid_pending_level = 0;
   group.favorable_grid_pending_price = 0.0;
   group.request_in_flight = false;
   group.request_order_ticket = 0;
   group.request_position_ticket = 0;
   group.request_signal_id = 0;
   group.request_bar_time = 0;
   group.request_direction = ORDER_TYPE_BUY;
   group.request_volume = 0.0;
   group.request_retry_count = 0;
   group.signal_consumed = false;
   group.signal_id = 0;
   group.signal_bar_time = 0;
   group.state = STATE_IDLE;
  }

 void MultiClearAll()
   {
    if(g_gui_applied_config.cost_mode)
       for(int index = 0; index < ArraySize(g_multi_groups); index++)
          if(g_multi_groups[index].cost_active)
             MultiCostArchiveGroup(g_multi_groups[index].id,
                                   g_multi_groups[index].cost_start);
    const string map_prefix = StatePrefix() + ".multi.cost";
   const int map_count = GlobalVariableCheck(map_prefix + ".count")
                         ? (int)MathRound(GlobalVariableGet(map_prefix + ".count")) : 0;
   for(int index = 0; index < map_count; index++)
     {
      GlobalVariableDel(map_prefix + ".id." + IntegerToString(index));
      GlobalVariableDel(map_prefix + ".group." + IntegerToString(index));
     }
   GlobalVariableDel(map_prefix + ".count");
   ArrayResize(g_multi_cost_position_ids, 0);
   ArrayResize(g_multi_cost_position_groups, 0);
   for(int id = 1; id < g_multi_next_id; id++)
      MultiDeleteState(id);
   ArrayResize(g_multi_groups, 0);
   g_multi_last_trigger_bar = 0;
   g_multi_next_id = 1;
   GlobalVariableDel(StatePrefix() + ".multi.nextid");
   GlobalVariableDel(StatePrefix() + ".multi.lasttriggerbar");
   GlobalVariableDel(StatePrefix() + ".configfingerprint");
   GlobalVariableDel(StatePrefix() + ".configfingerprint2");
   string migration_error = "";
   if(!DisableLegacyStateFallback(migration_error))
      PrintFormat("Failed to disable legacy MT5 state fallback: %s", migration_error);
  }

void MultiRemoveGroup(const int index)
  {
   if(index < 0 || index >= ArraySize(g_multi_groups))
      return;
    if(g_gui_applied_config.cost_mode)
      {
       MultiCostArchiveGroup(g_multi_groups[index].id,
                             g_multi_groups[index].cost_start);
       MultiCostForgetGroup(g_multi_groups[index].id);
      }
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
   if(g_gui_applied_config.cost_mode)
      return PositionGetString(POSITION_SYMBOL) == _Symbol
             && (ulong)PositionGetInteger(POSITION_MAGIC) == g_gui_applied_config.magic_number
             && MultiCostGroupForPosition(PositionGetInteger(POSITION_IDENTIFIER)) == group_id;
   return PositionGetString(POSITION_SYMBOL) == _Symbol
          && (ulong)PositionGetInteger(POSITION_MAGIC) == g_gui_applied_config.magic_number
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
         || (ulong)OrderGetInteger(ORDER_MAGIC) != g_gui_applied_config.magic_number
         || !IsReversePendingType(OrderGetInteger(ORDER_TYPE)))
         continue;
      const string comment = OrderGetString(ORDER_COMMENT);
      if(!MultiCommentMatches(comment, group_id)
         || IsGridPendingComment(comment) != grid
         || MultiIsInitialPendingComment(comment))
         continue;
      ticket = candidate;
      type = OrderGetInteger(ORDER_TYPE);
      volume = OrderGetDouble(ORDER_VOLUME_CURRENT);
      price = OrderGetDouble(ORDER_PRICE_OPEN);
      return true;
     }
   return false;
  }

bool MultiIsGridPendingAtLevel(const MultiGroupState &group, const long order_type,
                               const string comment, const double order_price,
                               const double order_volume, const long expected_direction,
                               const int expected_level, const double expected_price,
                               const double expected_volume)
  {
   const int comment_level = GridPendingLevelFromComment(comment);
   if(comment_level > 0 && comment_level != expected_level)
      return false;
   return MultiCommentMatches(comment, group.id)
          && IsGridPendingComment(comment)
          && !MultiIsInitialPendingComment(comment)
          && IsReversePendingType(order_type)
          && PendingDirection(order_type) == expected_direction
          && MathAbs(order_price - expected_price) <= _Point * 0.5
          && MathAbs(order_volume - expected_volume)
             <= SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP) * 0.5;
  }

bool MultiNormalizeGridPendingLevel(const MultiGroupState &group,
                                    const long expected_direction, const int expected_level,
                                    const double expected_price, const double expected_volume,
                                    ulong &keep_ticket)
   {
    keep_ticket = 0;
   bool keep_favorable = false;
   for(int index = 0; index < OrdersTotal(); index++)
     {
      const ulong candidate = OrderGetTicket(index);
      if(candidate == 0
         || OrderGetString(ORDER_SYMBOL) != _Symbol
         || (ulong)OrderGetInteger(ORDER_MAGIC) != g_gui_applied_config.magic_number
         || !MultiIsGridPendingAtLevel(group, OrderGetInteger(ORDER_TYPE),
                                       OrderGetString(ORDER_COMMENT),
                                       OrderGetDouble(ORDER_PRICE_OPEN),
                                       OrderGetDouble(ORDER_VOLUME_CURRENT),
                                       expected_direction, expected_level,
                                       expected_price, expected_volume))
         continue;
      if(keep_ticket == 0 || candidate < keep_ticket)
        {
         keep_ticket = candidate;
         keep_favorable = StringFind(OrderGetString(ORDER_COMMENT), ".Grid.F.") >= 0;
        }
     }
   MultiRememberGridOrderTicket(group.id, expected_level, keep_favorable, keep_ticket);
   bool normalized = true;
   for(int index = OrdersTotal() - 1; index >= 0; index--)
     {
      const ulong candidate = OrderGetTicket(index);
      if(candidate == 0 || candidate == keep_ticket
         || OrderGetString(ORDER_SYMBOL) != _Symbol
         || (ulong)OrderGetInteger(ORDER_MAGIC) != g_gui_applied_config.magic_number
         || !MultiIsGridPendingAtLevel(group, OrderGetInteger(ORDER_TYPE),
                                       OrderGetString(ORDER_COMMENT),
                                       OrderGetDouble(ORDER_PRICE_OPEN),
                                       OrderGetDouble(ORDER_VOLUME_CURRENT),
                                       expected_direction, expected_level,
                                       expected_price, expected_volume))
         continue;
      if(!DeletePendingTicket(candidate, "Multi grid level duplicate delete"))
         normalized = false;
     }
   return normalized;
  }

bool MultiFindFilledGridPosition(const MultiGroupState &group, const long position_type,
                                 const int level, const bool favorable,
                                 double &fill_price)
  {
   for(int index = PositionsTotal() - 1; index >= 0; index--)
     {
      const ulong ticket = PositionGetTicket(index);
      if(!MultiIsOurPosition(ticket, group.id)
         || PositionGetInteger(POSITION_TYPE) != position_type)
         continue;
      const string comment = PositionGetString(POSITION_COMMENT);
      if(!IsGridPendingComment(comment)
         || GridPendingLevelFromComment(comment) != level
         || (StringFind(comment, ".Grid.F.") >= 0) != favorable)
         continue;
      fill_price = PositionGetDouble(POSITION_PRICE_OPEN);
      return true;
     }
   return false;
  }

bool MultiFindFilledGridOrder(const MultiGroupState &group, const long position_type,
                              const int level, const double expected_price,
                              const bool favorable,
                              double &fill_price)
  {
   if(MultiFindFilledGridPosition(group, position_type, level, favorable, fill_price))
      return true;
   ulong ticket = MultiGridOrderTicket(group.id, level, favorable);
   if(ticket == 0
      && (favorable ? group.favorable_grid_pending_level
                    : group.grid_pending_level) == level)
      ticket = favorable ? group.favorable_grid_pending_ticket
                         : group.grid_pending_ticket;
   if(ticket == 0 || !HistoryOrderSelect(ticket))
      return false;
   const string comment = HistoryOrderGetString(ticket, ORDER_COMMENT);
   if(HistoryOrderGetString(ticket, ORDER_SYMBOL) == _Symbol
      && (ulong)HistoryOrderGetInteger(ticket, ORDER_MAGIC)
         == g_gui_applied_config.magic_number
      && HistoryOrderGetInteger(ticket, ORDER_STATE) == ORDER_STATE_FILLED
      && MultiIsGridPendingAtLevel(group,
                                   HistoryOrderGetInteger(ticket, ORDER_TYPE),
                                   comment,
                                   HistoryOrderGetDouble(ticket, ORDER_PRICE_OPEN),
                                   HistoryOrderGetDouble(ticket, ORDER_VOLUME_INITIAL),
                                   position_type, level, expected_price,
                                   HistoryOrderGetDouble(ticket, ORDER_VOLUME_INITIAL)))
     {
      fill_price = HistoryOrderGetDouble(ticket, ORDER_PRICE_OPEN);
      return true;
     }
   return false;
  }

int MultiGridFilledLevelCount(const MultiGroupState &group)
  {
   int count = 0;
   for(int level = 1; level < g_gui_applied_config.grid_count; level++)
      if((group.grid_filled_mask & GridLevelBit(level)) != 0)
         count++;
   return count;
  }

bool MultiStateChanged(const MultiGroupState &before,
                       const MultiGroupState &after)
  {
   return before.active != after.active
          || before.pair_role != after.pair_role
          || before.pair_peer_id != after.pair_peer_id
          || before.pair_failure_retcode != after.pair_failure_retcode
          || before.initial_pair_incomplete != after.initial_pair_incomplete
          || before.initial_pending_lots != after.initial_pending_lots
          || before.first_direction != after.first_direction
          || before.cycle_mode != after.cycle_mode
          || before.cycle_index != after.cycle_index
          || before.pending_index != after.pending_index
          || before.reversal_count != after.reversal_count
          || before.pending_ticket != after.pending_ticket
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
          || before.request_in_flight != after.request_in_flight
          || before.request_order_ticket != after.request_order_ticket
          || before.request_position_ticket != after.request_position_ticket
          || before.request_signal_id != after.request_signal_id
          || before.request_bar_time != after.request_bar_time
          || before.request_direction != after.request_direction
          || before.request_volume != after.request_volume
          || before.request_retry_count != after.request_retry_count
          || before.signal_consumed != after.signal_consumed
          || before.signal_id != after.signal_id
          || before.signal_bar_time != after.signal_bar_time
          || before.state != after.state;
  }

void MultiSaveGroup(MultiGroupState &group)
  {
   if(!group.dirty)
      return;
   const string prefix = MultiStatePrefix(group.id);
   if(g_gui_applied_config.cost_mode)
     {
      GlobalVariableSet(prefix + ".cost.active", group.cost_active ? 1.0 : 0.0);
      GlobalVariableSet(prefix + ".cost.frozen", group.cost_frozen ? 1.0 : 0.0);
      GlobalVariableSet(prefix + ".cost.start", (double)group.cost_start);
      GlobalVariableSet(prefix + ".cost.target", group.cost_target);
      GlobalVariableSet(prefix + ".cost.tp", group.cost_tp);
      GlobalVariableSet(prefix + ".cost.risk", group.cost_risk);
      GlobalVariableSet(prefix + ".cost.bar", (double)group.cost_bar);
      GlobalVariableSet(prefix + ".cost.high", group.cost_high);
      GlobalVariableSet(prefix + ".cost.low", group.cost_low);
    GlobalVariableSet(prefix + ".cost.stopms", (double)group.cost_stop_msc);
    GlobalVariableSet(prefix + ".cost.stopdeal", (double)group.cost_stop_deal);
    GlobalVariableSet(prefix + ".cost.consumedstopdeal",
                      (double)group.cost_consumed_stop_deal);
      GlobalVariableSet(prefix + ".cost.stopprice", group.cost_stop_price);
      GlobalVariableSet(prefix + ".cost.stoptype", (double)group.cost_stop_type);
      MultiCostSaveMap();
     }
   GlobalVariableSet(prefix + ".active", group.active ? 1.0 : 0.0);
    GlobalVariableSet(prefix + ".pairrole", (double)group.pair_role);
    GlobalVariableSet(prefix + ".pairpeer", (double)group.pair_peer_id);
    GlobalVariableSet(prefix + ".pairretcode", (double)group.pair_failure_retcode);
    GlobalVariableSet(prefix + ".pairincomplete", group.initial_pair_incomplete ? 1.0 : 0.0);
   GlobalVariableSet(prefix + ".first", (double)group.first_direction);
   GlobalVariableSet(prefix + ".mode", (double)group.cycle_mode);
   GlobalVariableSet(prefix + ".index", (double)group.cycle_index);
   GlobalVariableSet(prefix + ".pendingindex", (double)group.pending_index);
   GlobalVariableSet(prefix + ".reversals", (double)group.reversal_count);
   GlobalVariableSet(prefix + ".pendingticket", (double)group.pending_ticket);
   GlobalVariableSet(prefix + ".initial_high_ticket", (double)group.initial_high_ticket);
   GlobalVariableSet(prefix + ".initial_low_ticket", (double)group.initial_low_ticket);
   GlobalVariableSet(prefix + ".initial_high_price", group.initial_high_price);
   GlobalVariableSet(prefix + ".initial_low_price", group.initial_low_price);
    GlobalVariableSet(prefix + ".initial_lots", group.initial_pending_lots);
   GlobalVariableSet(prefix + ".initial_high_direction", (double)group.initial_high_direction);
   GlobalVariableSet(prefix + ".initial_low_direction", (double)group.initial_low_direction);
   GlobalVariableSet(prefix + ".gridticket", (double)group.grid_pending_ticket);
   GlobalVariableSet(prefix + ".slpoints", (double)group.stop_points);
   GlobalVariableSet(prefix + ".tppoints", (double)group.take_profit_points);
    GlobalVariableSet(prefix + ".cumlots", group.cumulative_loss_lots);
    GlobalVariableSet(prefix + ".firstlots", group.first_lots);
   GlobalVariableSet(prefix + ".prevgridlots", group.previous_grid_lots);
   GlobalVariableSet(prefix + ".gridlots", group.grid_lots);
   GlobalVariableSet(prefix + ".totallots", group.total_lots);
   GlobalVariableSet(prefix + ".transitiontarget", group.transition_target_lots);
   GlobalVariableSet(prefix + ".anchor", group.anchor_price);
   GlobalVariableSet(prefix + ".lastentry", group.last_entry);
   GlobalVariableSet(prefix + ".linearextreme", group.linear_extreme);
   GlobalVariableSet(prefix + ".gridlevel", (double)group.grid_filled_levels);
   SaveGridMask(prefix, group.grid_filled_mask);
    GlobalVariableSet(prefix + ".gridpendinglevel", (double)group.grid_pending_level);
    GlobalVariableSet(prefix + ".gridpendingprice", group.grid_pending_price);
    GlobalVariableSet(prefix + ".favorablegridticket", (double)group.favorable_grid_pending_ticket);
    GlobalVariableSet(prefix + ".favorablegridlevel", (double)group.favorable_grid_filled_levels);
    SaveGridMask(prefix + ".favorable", group.favorable_grid_filled_mask);
    GlobalVariableSet(prefix + ".favorablegridpendinglevel", (double)group.favorable_grid_pending_level);
    GlobalVariableSet(prefix + ".favorablegridpendingprice", group.favorable_grid_pending_price);
    GlobalVariableSet(prefix + ".reqflight", group.request_in_flight ? 1.0 : 0.0);
    GlobalVariableSet(prefix + ".reqorder", (double)group.request_order_ticket);
    GlobalVariableSet(prefix + ".reqposition", (double)group.request_position_ticket);
    GlobalVariableSet(prefix + ".reqsignal", (double)group.request_signal_id);
    GlobalVariableSet(prefix + ".reqbar", (double)group.request_bar_time);
    GlobalVariableSet(prefix + ".reqdir", (double)group.request_direction);
    GlobalVariableSet(prefix + ".reqvolume", group.request_volume);
    GlobalVariableSet(prefix + ".reqretry", (double)group.request_retry_count);
   GlobalVariableSet(StatePrefix() + ".multi.nextid", (double)g_multi_next_id);
   if(!GlobalVariableSet(StatePrefix() + ".configfingerprint",
                         GuiConfigFingerprint(g_gui_applied_config))
      || !GlobalVariableSet(StatePrefix() + ".configfingerprint2",
                            GuiConfigFingerprint2(g_gui_applied_config)))
      PrintFormat("Failed to persist MT5 GUI configuration fingerprint: %s",
                  StatePrefix());
   group.dirty = false;
  }

void MultiLoadGroups()
  {
   const string state_prefix = StatePrefix();
   const string next_key = state_prefix + ".multi.nextid";
   const string last_trigger_key = state_prefix + ".multi.lasttriggerbar";
   if(GlobalVariableCheck(last_trigger_key))
      g_multi_last_trigger_bar = (datetime)MathRound(GlobalVariableGet(last_trigger_key));
   if(!GlobalVariableCheck(next_key))
      return;
   g_multi_next_id = (int)MathMax(1.0, MathRound(GlobalVariableGet(next_key)));
   for(int id = 1; id < g_multi_next_id; id++)
     {
      const string prefix = state_prefix + ".multi." + IntegerToString(id);
      if(!GlobalVariableCheck(prefix + ".active")
         || GlobalVariableGet(prefix + ".active") < 0.5)
         continue;
      const int index = ArraySize(g_multi_groups);
      if(ArrayResize(g_multi_groups, index + 1) != index + 1)
         break;
      MultiGroupState state;
      MultiResetState(state, id);
       if(GlobalVariableCheck(prefix + ".pairrole"))
          state.pair_role = (int)MathRound(GlobalVariableGet(prefix + ".pairrole"));
       if(GlobalVariableCheck(prefix + ".pairpeer"))
          state.pair_peer_id = (int)MathRound(GlobalVariableGet(prefix + ".pairpeer"));
       if(GlobalVariableCheck(prefix + ".pairretcode"))
          state.pair_failure_retcode = (int)MathRound(GlobalVariableGet(prefix + ".pairretcode"));
       if(GlobalVariableCheck(prefix + ".pairincomplete"))
          state.initial_pair_incomplete = GlobalVariableGet(prefix + ".pairincomplete") > 0.5;
      if(g_gui_applied_config.cost_mode)
        {
         if(!GlobalVariableCheck(prefix + ".cost.active"))
            state.cost_frozen = true;
         else
           {
            state.cost_active = GlobalVariableGet(prefix + ".cost.active") > 0.5;
            state.cost_frozen = GlobalVariableGet(prefix + ".cost.frozen") > 0.5;
            state.cost_start = (datetime)MathRound(GlobalVariableGet(prefix + ".cost.start"));
            state.cost_target = GlobalVariableGet(prefix + ".cost.target");
            state.cost_tp = GlobalVariableGet(prefix + ".cost.tp");
            state.cost_risk = GlobalVariableGet(prefix + ".cost.risk");
            state.cost_bar = (datetime)MathRound(GlobalVariableGet(prefix + ".cost.bar"));
            state.cost_high = GlobalVariableGet(prefix + ".cost.high");
            state.cost_low = GlobalVariableGet(prefix + ".cost.low");
             state.cost_stop_msc = (long)MathRound(GlobalVariableGet(prefix + ".cost.stopms"));
             if(GlobalVariableCheck(prefix + ".cost.stopdeal"))
                state.cost_stop_deal = (ulong)MathRound(GlobalVariableGet(prefix + ".cost.stopdeal"));
             if(GlobalVariableCheck(prefix + ".cost.consumedstopdeal"))
                state.cost_consumed_stop_deal = (ulong)MathRound(
                   GlobalVariableGet(prefix + ".cost.consumedstopdeal"));
            state.cost_stop_price = GlobalVariableGet(prefix + ".cost.stopprice");
            state.cost_stop_type = (long)MathRound(GlobalVariableGet(prefix + ".cost.stoptype"));
            if(state.cost_start <= 0 || state.cost_target <= 0.0 || state.cost_risk < 0.0)
               state.cost_frozen = true;
           }
        }
      state.first_direction = (int)MathRound(GlobalVariableGet(prefix + ".first"));
      state.cycle_mode = (int)MathRound(GlobalVariableGet(prefix + ".mode"));
      state.cycle_index = (int)MathRound(GlobalVariableGet(prefix + ".index"));
      state.pending_index = (int)MathRound(GlobalVariableGet(prefix + ".pendingindex"));
      state.reversal_count = (int)MathRound(GlobalVariableGet(prefix + ".reversals"));
      state.pending_ticket = (ulong)MathRound(GlobalVariableGet(prefix + ".pendingticket"));
      if(GlobalVariableCheck(prefix + ".initial_high_ticket"))
         state.initial_high_ticket = (ulong)MathRound(GlobalVariableGet(prefix + ".initial_high_ticket"));
      if(GlobalVariableCheck(prefix + ".initial_low_ticket"))
         state.initial_low_ticket = (ulong)MathRound(GlobalVariableGet(prefix + ".initial_low_ticket"));
      if(GlobalVariableCheck(prefix + ".initial_high_price"))
         state.initial_high_price = GlobalVariableGet(prefix + ".initial_high_price");
      if(GlobalVariableCheck(prefix + ".initial_low_price"))
         state.initial_low_price = GlobalVariableGet(prefix + ".initial_low_price");
       if(GlobalVariableCheck(prefix + ".initial_lots"))
          state.initial_pending_lots = GlobalVariableGet(prefix + ".initial_lots");
      if(GlobalVariableCheck(prefix + ".initial_high_direction"))
         state.initial_high_direction = (long)MathRound(GlobalVariableGet(prefix + ".initial_high_direction"));
      if(GlobalVariableCheck(prefix + ".initial_low_direction"))
         state.initial_low_direction = (long)MathRound(GlobalVariableGet(prefix + ".initial_low_direction"));
      state.grid_pending_ticket = (ulong)MathRound(GlobalVariableGet(prefix + ".gridticket"));
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
         state.favorable_grid_pending_ticket = (ulong)MathRound(GlobalVariableGet(prefix + ".favorablegridticket"));
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
       if(GlobalVariableCheck(prefix + ".reqflight"))
          state.request_in_flight = GlobalVariableGet(prefix + ".reqflight") > 0.5;
       if(GlobalVariableCheck(prefix + ".reqorder"))
          state.request_order_ticket = (ulong)MathRound(GlobalVariableGet(prefix + ".reqorder"));
       if(GlobalVariableCheck(prefix + ".reqposition"))
          state.request_position_ticket = (ulong)MathRound(GlobalVariableGet(prefix + ".reqposition"));
       if(GlobalVariableCheck(prefix + ".reqsignal"))
          state.request_signal_id = (long)MathRound(GlobalVariableGet(prefix + ".reqsignal"));
       if(GlobalVariableCheck(prefix + ".reqbar"))
          state.request_bar_time = (datetime)MathRound(GlobalVariableGet(prefix + ".reqbar"));
       if(GlobalVariableCheck(prefix + ".reqdir"))
          state.request_direction = (long)MathRound(GlobalVariableGet(prefix + ".reqdir"));
       if(GlobalVariableCheck(prefix + ".reqvolume"))
          state.request_volume = GlobalVariableGet(prefix + ".reqvolume");
       if(GlobalVariableCheck(prefix + ".reqretry"))
          state.request_retry_count = (int)MathRound(GlobalVariableGet(prefix + ".reqretry"));
      state.dirty = false;
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
         && (ulong)OrderGetInteger(ORDER_MAGIC) == g_gui_applied_config.magic_number
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

bool MultiClosePositionsExcept(const int group_id, const ulong keep_ticket)
  {
   if(keep_ticket == 0 || !MultiIsOurPosition(keep_ticket, group_id))
      return false;
   bool closed = true;
   for(int index = PositionsTotal() - 1; index >= 0; index--)
     {
      const ulong candidate = PositionGetTicket(index);
      if(candidate == 0 || candidate == keep_ticket
         || !MultiIsOurPosition(candidate, group_id))
         continue;
      if(!g_trade.PositionClose(candidate))
        {
         PrintFormat("Previous multi-group close failed after reverse fill, group=%d, ticket=%I64u, retcode=%u, %s",
                     group_id, candidate, g_trade.ResultRetcode(),
                     g_trade.ResultRetcodeDescription());
         closed = false;
        }
     }
   for(int index = PositionsTotal() - 1; index >= 0; index--)
     {
      const ulong candidate = PositionGetTicket(index);
      if(candidate != 0 && candidate != keep_ticket
         && MultiIsOurPosition(candidate, group_id))
         closed = false;
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
         || (ulong)OrderGetInteger(ORDER_MAGIC) != g_gui_applied_config.magic_number
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
   return buy ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
  }

double MultiStopPrice(const MultiGroupState &group, const long type)
  {
   double stop_loss = type == POSITION_TYPE_BUY
                      ? group.anchor_price - group.stop_points * _Point
                      : group.anchor_price + group.stop_points * _Point;
   if(g_gui_applied_config.dynamic_stop_loss_enable == 1
      && g_gui_applied_config.grid_count >= 2)
     {
      const int level = HighestFavorableGridLevel(group.favorable_grid_filled_mask);
      const double grid_spacing = group.stop_points * _Point
                                  / g_gui_applied_config.grid_count;
      if(type == POSITION_TYPE_BUY)
         stop_loss += level * grid_spacing;
      else
         stop_loss -= level * grid_spacing;
     }
   return PriceNormalize(stop_loss);
  }

double MultiTakeProfitPrice(const MultiGroupState &group, const long type)
  {
   double reference = group.last_entry;
   if(g_gui_applied_config.take_profit_mode == TAKE_PROFIT_LINEAR
      && group.linear_extreme > 0.0)
      reference = group.linear_extreme;
   if(type == POSITION_TYPE_BUY)
      return PriceNormalize(reference + group.take_profit_points * _Point);
   return PriceNormalize(reference - group.take_profit_points * _Point);
  }

bool MultiSetStops(const MultiGroupState &group, const long type)
  {
   bool modified = true;
   for(int index = PositionsTotal() - 1; index >= 0; index--)
     {
      const ulong ticket = PositionGetTicket(index);
      if(!MultiIsOurPosition(ticket, group.id)
         || PositionGetInteger(POSITION_TYPE) != type)
         continue;
      double stop_loss = MultiStopPrice(group, type);
      double take_profit = MultiTakeProfitPrice(group, type);
      string reason = "";
      if(!ValidateStops((ENUM_POSITION_TYPE)type,
                        PositionGetDouble(POSITION_PRICE_OPEN),
                        stop_loss, take_profit, reason))
        {
         modified = false;
         PrintFormat("[GROUP=%d][STATE=PROTECTION_PENDING][EVENT=STOP_VALIDATION_FAILED] "
                     "[POSITION=%I64u][SL=%.5f][TP=%.5f][ERROR=%s]",
                     group.id, ticket, stop_loss, take_profit, reason);
         continue;
        }
      const double old_sl = PositionGetDouble(POSITION_SL);
      const double old_tp = PositionGetDouble(POSITION_TP);
      if(MathAbs(old_sl - stop_loss) <= _Point * 0.5
         && MathAbs(old_tp - take_profit) <= _Point * 0.5)
         continue;
      if(!g_trade.PositionModify(ticket, stop_loss, take_profit))
        {
         PrintFormat("[GROUP=%d][STATE=PROTECTION_PENDING][EVENT=POSITION_MODIFY_FAILED] "
                     "[POSITION=%I64u][SL=%.5f][TP=%.5f][RETCODE=%u][ERROR=%s]",
                     group.id, ticket, stop_loss, take_profit,
                     g_trade.ResultRetcode(), g_trade.ResultRetcodeDescription());
         modified = false;
        }
     }
   return modified && MultiStopsVerified(group, type);
  }

bool MultiStopsVerified(const MultiGroupState &group, const long type)
  {
   bool found = false;
   for(int index = PositionsTotal() - 1; index >= 0; index--)
     {
      const ulong ticket = PositionGetTicket(index);
      if(!MultiIsOurPosition(ticket, group.id)
         || PositionGetInteger(POSITION_TYPE) != type)
         continue;
      found = true;
      double stop_loss = MultiStopPrice(group, type);
      double take_profit = MultiTakeProfitPrice(group, type);
      string reason = "";
      if(!ValidateStops((ENUM_POSITION_TYPE)type,
                        PositionGetDouble(POSITION_PRICE_OPEN),
                        stop_loss, take_profit, reason))
         return false;
      if(PositionGetDouble(POSITION_SL) <= 0.0
         || PositionGetDouble(POSITION_TP) <= 0.0
         || MathAbs(PositionGetDouble(POSITION_SL) - stop_loss) > _Point * 0.5
         || MathAbs(PositionGetDouble(POSITION_TP) - take_profit) > _Point * 0.5)
         return false;
     }
   return found;
  }

void MultiLogTradeEvent(const MultiGroupState &group, const string event,
                        const uint retcode = 0, const string error = "")
  {
   const double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   const double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   PrintFormat("[GROUP=%d][STATE=%s][EVENT=%s][POSITION=%I64u][ORDER=%I64u] "
               "[SIGNAL_ID=%I64d][BAR_TIME=%s][BID=%.5f][ASK=%.5f] "
               "[STOP_LEVEL=%I64d][FREEZE_LEVEL=%I64d][TICK_SIZE=%.10f] "
               "[RETCODE=%u][ERROR=%s]",
               group.id, StrategyStateText(group.state), event,
               group.request_position_ticket, group.request_order_ticket,
               group.request_signal_id,
               TimeToString(group.request_bar_time, TIME_DATE|TIME_MINUTES),
               bid, ask, SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL),
               SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL),
               SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE), retcode, error);
  }

bool MultiConfirmTradeRequestFromVisible(MultiGroupState &group)
  {
   if(!group.request_in_flight)
      return true;
   ulong ticket = 0;
   long type = POSITION_TYPE_BUY;
   double volume = 0.0;
   double entry = 0.0;
   double stop_loss = 0.0;
   double take_profit = 0.0;
   if(!MultiFindPosition(group.id, ticket, type, volume, entry, stop_loss,
                          take_profit)
      || (group.request_direction == ORDER_TYPE_BUY && type != POSITION_TYPE_BUY)
      || (group.request_direction == ORDER_TYPE_SELL && type != POSITION_TYPE_SELL))
      return false;
   group.request_in_flight = false;
   group.request_position_ticket = ticket;
   group.state = STATE_POSITION_ACTIVE;
   group.dirty = true;
   MultiLogTradeEvent(group, "POSITION_CONFIRMED");
   return true;
  }

bool MultiConfirmTradeRequestFromTransaction(const MqlTradeTransaction &trans)
  {
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD || trans.deal == 0
      || trans.symbol != _Symbol || !HistoryDealSelect(trans.deal)
      || (ulong)HistoryDealGetInteger(trans.deal, DEAL_MAGIC)
         != g_gui_applied_config.magic_number
      || HistoryDealGetInteger(trans.deal, DEAL_ENTRY) != DEAL_ENTRY_IN)
      return false;
   const string comment = HistoryDealGetString(trans.deal, DEAL_COMMENT);
   for(int index = 0; index < ArraySize(g_multi_groups); index++)
     {
      MultiGroupState group = g_multi_groups[index];
      if(!group.active || !group.request_in_flight
         || !MultiCommentMatches(comment, group.id))
         continue;
      const long deal_type = HistoryDealGetInteger(trans.deal, DEAL_TYPE);
      const long expected_type = group.request_direction == ORDER_TYPE_BUY
                                 ? DEAL_TYPE_BUY : DEAL_TYPE_SELL;
      if(deal_type != expected_type)
         continue;
      group.request_in_flight = false;
      group.request_order_ticket = trans.order;
      group.request_position_ticket = trans.position;
      group.state = STATE_POSITION_ACTIVE;
      group.dirty = true;
      g_multi_groups[index] = group;
      MultiLogTradeEvent(group, "DEAL_CONFIRMED");
      return true;
     }
   return false;
  }

bool MultiSendMarketLeg(MultiGroupState &group, const long type, const double volume)
  {
   if(g_gui_applied_config.cost_mode)
     { Print("[COST_REJECT=UNSUPPORTED_MULTI_MARKET]"); return false; }
   if(group.request_in_flight)
     {
      MultiLogTradeEvent(group, "REQUEST_BLOCKED_IN_FLIGHT");
      return false;
     }
   const double normalized_volume = VolumeNormalize(volume);
   if(normalized_volume <= 0.0)
      return false;
   group.request_in_flight = true;
   group.request_direction = type;
   group.request_volume = normalized_volume;
   group.request_bar_time = group.signal_bar_time > 0
                            ? group.signal_bar_time : iTime(_Symbol, _Period, 0);
   group.request_signal_id = group.signal_id != 0
                             ? group.signal_id
                             : BuildSignalId(group.request_bar_time, type);
   group.state = STATE_ORDER_SENDING;
   group.dirty = true;
   MultiSaveGroup(group);
   MultiLogTradeEvent(group, "REQUEST_SUBMITTED");
   const string comment = MultiGroupComment(group.id, false);
   bool sent = type == ORDER_TYPE_BUY
               ? g_trade.Buy(normalized_volume, _Symbol, 0.0, 0.0, 0.0, comment)
               : g_trade.Sell(normalized_volume, _Symbol, 0.0, 0.0, 0.0, comment);
   if(!sent || g_trade.ResultRetcode() == TRADE_RETCODE_NO_MONEY)
     {
      const uint retcode = g_trade.ResultRetcode();
      group.request_retry_count++;
      group.state = STATE_RECOVERY;
      group.request_order_ticket = g_trade.ResultOrder();
      MultiLogTradeEvent(group, "REQUEST_FAILED", retcode,
                         g_trade.ResultRetcodeDescription());
      if(IsAmbiguousTradeRetcode(retcode))
         return false;
      group.request_in_flight = false;
      if(g_trade.ResultRetcode() == TRADE_RETCODE_NO_MONEY)
         BeginResetAfterNoMoney();
      return false;
     }
   group.request_order_ticket = g_trade.ResultOrder();
   if(!MultiConfirmTradeRequestFromVisible(group))
     {
      group.state = STATE_ORDER_SENDING;
      MultiLogTradeEvent(group, "WAITING_DEAL_CONFIRMATION",
                         g_trade.ResultRetcode());
      return false;
     }
   return true;
  }

bool MultiOpenMarket(MultiGroupState &group, const long type, const double volume)
  {
   ReversalLotPlan plan;
   if(!BuildReversalLotPlan(volume, plan)
      || plan.status == REVERSAL_LOT_RESTART_GROUP)
      return false;
   const double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   const double tolerance = step > 0.0 ? step * 0.5 : 0.0000001;
   const double target = plan.first_lots
                         + (plan.count == 2 ? plan.second_lots : 0.0);
   const long position_type = type == ORDER_TYPE_BUY
                               ? POSITION_TYPE_BUY : POSITION_TYPE_SELL;
   double current = MultiTotalPositionVolume(group.id, position_type);
   for(int leg = 0; leg < plan.count && current + tolerance < target; leg++)
     {
      const double leg_target = leg == 0 ? plan.first_lots : plan.second_lots;
      const double leg_volume = MathMin(leg_target, target - current);
      if(leg_volume <= tolerance)
         continue;
      if(!MultiSendMarketLeg(group, type, leg_volume))
         return false;
      current = MultiTotalPositionVolume(group.id, position_type);
     }
   return current + tolerance >= target;
  }

double MultiNextGroupLotsRaw(const MultiGroupState &group, const double fallback)
   {
    if(g_gui_applied_config.first_order_lot_type == 2)
      {
       const double base = group.first_lots > 0.0 ? group.first_lots : fallback;
       return base * g_gui_applied_config.first_order_mult;
      }
    double requested = group.cumulative_loss_lots + group.total_lots;
   if(requested <= 0.0)
      requested = fallback;
   else
      requested *= g_gui_applied_config.initial_lots_multiplier;
    return requested;
   }

double MultiNextGroupLots(const MultiGroupState &group, const double fallback)
   {
    return VolumeNormalize(MultiNextGroupLotsRaw(group, fallback));
   }

double MultiNextGroupLotsAfterStopRaw(const MultiGroupState &group, const double fallback)
   {
    if(g_gui_applied_config.first_order_lot_type == 2)
      {
       const double base = group.first_lots > 0.0 ? group.first_lots : fallback;
       return base * g_gui_applied_config.first_order_mult;
      }
    const double requested = group.cumulative_loss_lots > 0.0
                             ? group.cumulative_loss_lots : fallback;
    return requested * g_gui_applied_config.initial_lots_multiplier;
   }

double MultiNextGroupLotsAfterStop(const MultiGroupState &group, const double fallback)
   {
    return VolumeNormalize(MultiNextGroupLotsAfterStopRaw(group, fallback));
   }

int MultiInitialPendingStatus(const ulong ticket, const int group_id)
  {
   if(ticket == 0)
      return REVERSE_PENDING_UNKNOWN;
   if(OrderSelect(ticket))
     {
      const string comment = OrderGetString(ORDER_COMMENT);
      if(OrderGetString(ORDER_SYMBOL) == _Symbol
         && (ulong)OrderGetInteger(ORDER_MAGIC) == g_gui_applied_config.magic_number
         && MultiCommentMatches(comment, group_id)
         && MultiIsInitialPendingComment(comment))
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

bool MultiPlaceInitialPendingPair(MultiGroupState &group, const double previous_high,
                                  const double previous_low, const int range_points,
                                  const double volume)
  {
   if(g_gui_applied_config.cost_mode)
     { Print("[COST_REJECT=UNSUPPORTED_MULTI_INITIAL]"); return false; }
   if(group.initial_high_ticket > 0 || group.initial_low_ticket > 0)
      return true;
   const long high_direction = g_gui_applied_config.order_type == ORDERTYPE_FORWARD
                               ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   const long low_direction = g_gui_applied_config.order_type == ORDERTYPE_FORWARD
                              ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
   ulong high_ticket = 0;
   ulong low_ticket = 0;
   if(!PlaceInitialPendingOrder(high_direction, previous_high, range_points, volume,
                                MultiInitialPendingComment(group.id, true), high_ticket))
      return false;
   if(!PlaceInitialPendingOrder(low_direction, previous_low, range_points, volume,
                                MultiInitialPendingComment(group.id, false), low_ticket))
     {
      DeletePendingTicket(high_ticket, "Multi initial pending rollback");
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

bool MultiStartCandleOcoPair(const double previous_high, const double previous_low,
                             const int range_points, const double volume)
  {
   if(range_points <= 0 || volume <= 0.0)
      return false;
   const int first_index = ArraySize(g_multi_groups);
   if(ArrayResize(g_multi_groups, first_index + 2) != first_index + 2)
      return false;
   const int high_id = g_multi_next_id++;
   const int low_id = g_multi_next_id++;
   MultiResetState(g_multi_groups[first_index], high_id);
   MultiResetState(g_multi_groups[first_index + 1], low_id);
   const long high_direction = g_gui_applied_config.order_type == ORDERTYPE_FORWARD
                               ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   const long low_direction = high_direction == ORDER_TYPE_BUY
                              ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
   const datetime signal_bar = iTime(_Symbol, _Period, 0);
   for(int leg = 0; leg < 2; leg++)
     {
      const int index = first_index + leg;
      const long direction = leg == 0 ? high_direction : low_direction;
      g_multi_groups[index].pair_role = leg == 0 ? 4 : 5;
      g_multi_groups[index].pair_peer_id = leg == 0 ? low_id : high_id;
      g_multi_groups[index].first_direction = direction == ORDER_TYPE_BUY ? FIRST_BUY : FIRST_SELL;
      g_multi_groups[index].cycle_mode = g_gui_applied_config.cycle_mode;
      g_multi_groups[index].stop_points = range_points;
      g_multi_groups[index].take_profit_points = range_points;
      g_multi_groups[index].initial_high_price = PriceNormalize(previous_high);
      g_multi_groups[index].initial_low_price = PriceNormalize(previous_low);
      g_multi_groups[index].initial_high_direction = high_direction;
      g_multi_groups[index].initial_low_direction = low_direction;
      g_multi_groups[index].initial_pending_lots = VolumeNormalize(volume);
      g_multi_groups[index].transition_target_lots = VolumeNormalize(volume);
      g_multi_groups[index].signal_bar_time = signal_bar;
      g_multi_groups[index].signal_id = BuildSignalId(signal_bar, direction) * 1000
                                        + g_multi_groups[index].id;
      g_multi_groups[index].state = STATE_SIGNAL_READY;
      MultiSaveGroup(g_multi_groups[index]);
     }
   ulong high_ticket = 0;
   if(!PlaceInitialPendingOrder(high_direction, previous_high, range_points, volume,
        MultiInitialPendingComment(high_id, true), high_ticket))
     {
      g_multi_groups[first_index].active = false;
      g_multi_groups[first_index + 1].active = false;
      g_multi_groups[first_index].dirty = true;
      g_multi_groups[first_index + 1].dirty = true;
      MultiSaveGroup(g_multi_groups[first_index]);
      MultiSaveGroup(g_multi_groups[first_index + 1]);
      return false;
     }
   g_multi_groups[first_index].initial_high_ticket = high_ticket;
   g_multi_groups[first_index].dirty = true;
   MultiSaveGroup(g_multi_groups[first_index]);
   ulong low_ticket = 0;
   if(!PlaceInitialPendingOrder(low_direction, previous_low, range_points, volume,
        MultiInitialPendingComment(low_id, false), low_ticket))
     {
      if(!DeletePendingTicket(high_ticket, "Initial dual-basket OCO rollback"))
        {
         g_multi_groups[first_index].initial_pair_incomplete = true;
         g_multi_groups[first_index].dirty = true;
         MultiSaveGroup(g_multi_groups[first_index]);
         PrintFormat("[PAIR_STATUS=INCOMPLETE_OCO][HIGH_GROUP=%d][LOW_GROUP=%d][FIRST_PENDING=%I64u][REASON=ROLLBACK_CANCEL_FAILED]",
                     high_id, low_id, high_ticket);
         return true;
        }
      g_multi_groups[first_index].active = false;
      g_multi_groups[first_index + 1].active = false;
      g_multi_groups[first_index].dirty = true;
      g_multi_groups[first_index + 1].dirty = true;
      MultiSaveGroup(g_multi_groups[first_index]);
      MultiSaveGroup(g_multi_groups[first_index + 1]);
      return false;
     }
   g_multi_groups[first_index + 1].initial_low_ticket = low_ticket;
   g_multi_groups[first_index].dirty = true;
   g_multi_groups[first_index + 1].dirty = true;
   MultiSaveGroup(g_multi_groups[first_index]);
   MultiSaveGroup(g_multi_groups[first_index + 1]);
   MarkMultiCandleTriggerBar();
   return true;
  }

bool MultiHandleOcoBasketGroup(MultiGroupState &group)
  {
   if(group.pair_role != 4 && group.pair_role != 5)
      return false;
   const ulong own_ticket = group.pair_role == 4
                            ? group.initial_high_ticket : group.initial_low_ticket;
   const int peer_index = MultiFindGroupIndex(group.pair_peer_id);
   if(peer_index < 0)
      return true;
   if(group.request_order_ticket > 0 || group.request_position_ticket > 0)
     {
      ulong market_ticket = 0;
      long market_type = POSITION_TYPE_BUY;
      double market_volume = 0.0, market_entry = 0.0, market_sl = 0.0, market_tp = 0.0;
      if(MultiFindPosition(group.id, market_ticket, market_type, market_volume,
                           market_entry, market_sl, market_tp))
        {
         group.anchor_price = market_entry;
         group.last_entry = market_entry;
         group.linear_extreme = market_entry;
         group.first_lots = market_volume;
         group.total_lots = market_volume;
         group.grid_lots = market_volume;
         group.pair_role = 0;
         group.pair_peer_id = 0;
         group.signal_consumed = true;
         group.initial_high_ticket = 0;
         group.initial_low_ticket = 0;
         group.transition_target_lots = 0.0;
         group.dirty = true;
         MultiSetStops(group, market_type);
         MultiSaveGroup(group);
         return true;
        }
     }
   const ulong peer_ticket = g_multi_groups[peer_index].pair_role == 4
      ? g_multi_groups[peer_index].initial_high_ticket
      : g_multi_groups[peer_index].initial_low_ticket;
   int own_status = MultiInitialPendingStatus(own_ticket, group.id);
   int peer_status = MultiInitialPendingStatus(peer_ticket, g_multi_groups[peer_index].id);
   if(group.initial_pair_incomplete && own_status == REVERSE_PENDING_FILLED)
      peer_status = REVERSE_PENDING_CANCELED;
   if(group.initial_pair_incomplete)
     {
      if(own_status == REVERSE_PENDING_ACTIVE)
        {
         if(!DeletePendingTicket(own_ticket, "Incomplete dual-basket OCO rollback"))
            return true;
         own_status = MultiInitialPendingStatus(own_ticket, group.id);
        }
      if(own_status == REVERSE_PENDING_UNKNOWN)
         return true;
      if(own_status != REVERSE_PENDING_FILLED)
        {
         group.active = false;
         group.dirty = true;
         g_multi_groups[peer_index].active = false;
         g_multi_groups[peer_index].dirty = true;
         MultiSaveGroup(group);
         MultiSaveGroup(g_multi_groups[peer_index]);
         return true;
        }
     }
   if(own_status == REVERSE_PENDING_ACTIVE)
     {
      if(peer_status == REVERSE_PENDING_FILLED)
        {
         if(!DeletePendingTicket(own_ticket, "Dual-basket OCO sibling delete"))
            return true;
         own_status = MultiInitialPendingStatus(own_ticket, group.id);
        }
      else
         return true;
     }
   if(own_status == REVERSE_PENDING_UNKNOWN)
      return true;
   if(own_status == REVERSE_PENDING_CANCELED)
     {
      if(peer_status == REVERSE_PENDING_ACTIVE || peer_status == REVERSE_PENDING_UNKNOWN)
         return true;
      if(peer_status != REVERSE_PENDING_FILLED)
        {
         group.active = false;
         group.dirty = true;
         MultiSaveGroup(group);
         return true;
        }
      ulong peer_pos = 0;
      long peer_type = POSITION_TYPE_BUY;
      double peer_vol = 0.0, peer_entry = 0.0, peer_sl = 0.0, peer_tp = 0.0;
      if(!FindPositionByPendingOrder(peer_ticket, peer_pos, peer_type,
                                     peer_vol, peer_entry, peer_sl, peer_tp))
         return true;
      const long direction = group.first_direction == FIRST_BUY ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
      if(!MultiOpenMarket(group, direction, group.initial_pending_lots))
        {
         if(group.request_in_flight) return true;
         group.pair_role = 3;
         group.pair_failure_retcode = (int)g_trade.ResultRetcode();
         group.state = STATE_RECOVERY;
         group.dirty = true;
         MultiSaveGroup(group);
         PrintFormat("[PAIR_STATUS=PARTIAL][PRIMARY_GROUP=%d][OPPOSITE_GROUP=%d][RETCODE=%d][REASON=OCO_OPPOSITE_SEND_PERMANENT]",
                     group.pair_peer_id, group.id, group.pair_failure_retcode);
         return true;
        }
      group.pair_role = 0;
      group.pair_peer_id = 0;
      group.signal_consumed = true;
      group.initial_high_ticket = 0;
      group.initial_low_ticket = 0;
      group.transition_target_lots = 0.0;
      group.dirty = true;
      return true;
     }
   if(own_status == REVERSE_PENDING_FILLED)
     {
      ulong own_pos = 0;
      long own_type = POSITION_TYPE_BUY;
      double own_vol = 0.0, own_entry = 0.0, own_sl = 0.0, own_tp = 0.0;
      if(!FindPositionByPendingOrder(own_ticket, own_pos, own_type,
                                     own_vol, own_entry, own_sl, own_tp))
         return true;
      if(peer_status == REVERSE_PENDING_ACTIVE)
        {
         if(!DeletePendingTicket(peer_ticket, "Dual-basket OCO sibling cancel"))
            return true;
         peer_status = MultiInitialPendingStatus(peer_ticket, g_multi_groups[peer_index].id);
        }
      if(peer_status == REVERSE_PENDING_UNKNOWN)
         return true;
      if(peer_status == REVERSE_PENDING_FILLED)
        {
         ulong peer_pos = 0;
         long peer_type = POSITION_TYPE_BUY;
         double peer_vol = 0.0, peer_entry = 0.0, peer_sl = 0.0, peer_tp = 0.0;
         if(!FindPositionByPendingOrder(peer_ticket, peer_pos, peer_type,
                                        peer_vol, peer_entry, peer_sl, peer_tp))
            return true;
         group.anchor_price = own_entry;
         group.last_entry = own_entry;
         group.linear_extreme = own_entry;
         group.first_lots = own_vol;
         group.total_lots = own_vol;
         group.grid_lots = own_vol;
         group.pair_role = 0;
         group.pair_peer_id = 0;
         group.signal_consumed = true;
         group.initial_high_ticket = 0;
         group.initial_low_ticket = 0;
         group.dirty = true;
         g_multi_groups[peer_index].anchor_price = peer_entry;
         g_multi_groups[peer_index].last_entry = peer_entry;
         g_multi_groups[peer_index].linear_extreme = peer_entry;
         g_multi_groups[peer_index].first_lots = peer_vol;
         g_multi_groups[peer_index].total_lots = peer_vol;
         g_multi_groups[peer_index].grid_lots = peer_vol;
         g_multi_groups[peer_index].pair_role = 0;
         g_multi_groups[peer_index].pair_peer_id = 0;
         g_multi_groups[peer_index].signal_consumed = true;
         g_multi_groups[peer_index].initial_high_ticket = 0;
         g_multi_groups[peer_index].initial_low_ticket = 0;
         g_multi_groups[peer_index].dirty = true;
         MultiSetStops(group, own_type);
         MultiSetStops(g_multi_groups[peer_index], peer_type);
         MultiSaveGroup(group);
         MultiSaveGroup(g_multi_groups[peer_index]);
         return true;
        }
      group.anchor_price = own_entry;
      group.last_entry = own_entry;
      group.linear_extreme = own_entry;
      group.first_lots = own_vol;
      group.total_lots = own_vol;
      group.grid_lots = own_vol;
      group.initial_high_ticket = 0;
      group.initial_low_ticket = 0;
      group.pair_role = 1;
      group.transition_target_lots = 0.0;
      group.signal_consumed = true;
      group.dirty = true;
      g_multi_groups[peer_index].pair_role = 2;
      g_multi_groups[peer_index].first_direction = group.first_direction == FIRST_BUY ? FIRST_SELL : FIRST_BUY;
      g_multi_groups[peer_index].initial_high_ticket = 0;
      g_multi_groups[peer_index].initial_low_ticket = 0;
      g_multi_groups[peer_index].transition_target_lots = group.initial_pending_lots;
      g_multi_groups[peer_index].signal_consumed = true;
      g_multi_groups[peer_index].dirty = true;
      MultiSetStops(group, own_type);
      MultiSaveGroup(group);
      MultiSaveGroup(g_multi_groups[peer_index]);
      return true;
     }
   return true;
  }

bool MultiHandleInitialPendingFill(MultiGroupState &group)
  {
   if(group.pair_role == 4 || group.pair_role == 5)
      return MultiHandleOcoBasketGroup(group);
   if(group.initial_high_ticket == 0 && group.initial_low_ticket == 0)
      return false;
   int high_status = MultiInitialPendingStatus(group.initial_high_ticket, group.id);
   int low_status = MultiInitialPendingStatus(group.initial_low_ticket, group.id);
   if(group.initial_pair_incomplete && group.initial_high_ticket > 0
      && group.initial_low_ticket == 0)
     {
      if(high_status == REVERSE_PENDING_ACTIVE)
        {
         if(!DeletePendingTicket(group.initial_high_ticket,
                                 "Incomplete multi initial OCO rollback"))
            return true;
         high_status = MultiInitialPendingStatus(group.initial_high_ticket, group.id);
        }
      if(high_status == REVERSE_PENDING_UNKNOWN)
         return true;
      if(high_status == REVERSE_PENDING_FILLED)
        {
         group.initial_pair_incomplete = false;
         low_status = REVERSE_PENDING_CANCELED;
        }
      else
        {
         const double retry_high = group.initial_high_price;
         const double retry_low = group.initial_low_price;
         const int retry_range = group.stop_points;
         group.initial_high_ticket = 0;
         group.initial_low_ticket = 0;
         group.initial_pair_incomplete = false;
         if(group.signal_bar_time > 0
            && group.signal_bar_time == iTime(_Symbol, _Period, 0)
            && GuiAllowsInitialEntry() && IsInitialEntryAllowed())
            MultiPlaceInitialPendingPair(group, retry_high, retry_low,
                                         retry_range,
                                         group.initial_pending_lots);
         group.dirty = true;
         MultiSaveGroup(group);
         return true;
        }
     }
   const bool high_filled = high_status == REVERSE_PENDING_FILLED;
   const bool low_filled = low_status == REVERSE_PENDING_FILLED;
   if(high_status == REVERSE_PENDING_ACTIVE && low_status == REVERSE_PENDING_ACTIVE)
      return true;
   if(high_filled || low_filled)
     {
      const ulong filled_ticket = high_filled
                                  ? group.initial_high_ticket : group.initial_low_ticket;
      const ulong other_ticket = filled_ticket == group.initial_high_ticket
                                 ? group.initial_low_ticket : group.initial_high_ticket;
      const int other_status = high_filled ? low_status : high_status;
      if(other_status == REVERSE_PENDING_UNKNOWN)
         return true;
      if(other_ticket > 0
         && other_status == REVERSE_PENDING_ACTIVE
         && !DeletePendingTicket(other_ticket, "Multi initial OCO delete"))
         return true;
      ulong position_ticket = 0;
      long position_type = POSITION_TYPE_BUY;
      double volume = 0.0;
      double entry = 0.0;
      double stop_loss = 0.0;
      double take_profit = 0.0;
       if(!FindPositionByPendingOrder(filled_ticket, position_ticket, position_type,
                                      volume, entry, stop_loss, take_profit))
          return true;
       if(high_filled && low_filled)
         {
          ulong other_position_ticket = 0;
          long other_position_type = POSITION_TYPE_BUY;
          double other_volume = 0.0;
          double other_entry = 0.0;
          double other_stop_loss = 0.0;
          double other_take_profit = 0.0;
          if(!FindPositionByPendingOrder(other_ticket, other_position_ticket,
                                         other_position_type, other_volume, other_entry,
                                         other_stop_loss, other_take_profit))
             return true;
          if(!ClosePreviousGroupAfterReverseFill(position_ticket))
             return true;
         }
       group.first_direction = position_type == POSITION_TYPE_BUY ? FIRST_BUY : FIRST_SELL;
      group.cycle_index = 0;
      group.pending_index = -1;
      group.pending_ticket = 0;
       group.anchor_price = entry;
       group.last_entry = entry;
       group.linear_extreme = entry;
       group.first_lots = volume;
       group.total_lots = volume;
      group.grid_filled_levels = 0;
      group.grid_filled_mask = 0;
      group.grid_pending_level = 0;
      group.grid_pending_price = 0.0;
      group.favorable_grid_pending_ticket = 0;
      group.favorable_grid_filled_levels = 0;
      group.favorable_grid_filled_mask = 0;
      group.favorable_grid_pending_level = 0;
      group.favorable_grid_pending_price = 0.0;
      group.grid_lots = group.previous_grid_lots > 0.0
                        ? VolumeNormalize(group.previous_grid_lots
                                          * g_gui_applied_config.grid_lot_multiplier)
                        : group.total_lots;
      group.initial_high_ticket = 0;
      group.initial_low_ticket = 0;
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
   if(group.pair_role == 3)
     {
      if(g_multi_pair_failure_log_time == 0
         || TimeCurrent() - g_multi_pair_failure_log_time >= 10)
        {
         PrintFormat("[PAIR_STATUS=PARTIAL][PRIMARY_GROUP=%d][OPPOSITE_GROUP=%d][RETCODE=%d][REASON=OPPOSITE_SEND_PERMANENT]",
                     group.pair_peer_id, group.id, group.pair_failure_retcode);
         g_multi_pair_failure_log_time = TimeCurrent();
        }
      return true;
     }
   if(high_status == REVERSE_PENDING_UNKNOWN || low_status == REVERSE_PENDING_UNKNOWN)
      return true;
   if(high_status == REVERSE_PENDING_ACTIVE || low_status == REVERSE_PENDING_ACTIVE)
     {
      const ulong active_ticket = high_status == REVERSE_PENDING_ACTIVE
                                  ? group.initial_high_ticket : group.initial_low_ticket;
      if(active_ticket > 0 && !DeletePendingTicket(active_ticket, "Multi initial OCO cleanup"))
         return true;
     }
   if(MultiInitialPendingStatus(group.initial_high_ticket, group.id) != REVERSE_PENDING_ACTIVE
      && MultiInitialPendingStatus(group.initial_low_ticket, group.id) != REVERSE_PENDING_ACTIVE)
     {
      group.initial_high_ticket = 0;
      group.initial_low_ticket = 0;
      group.initial_high_price = 0.0;
      group.initial_low_price = 0.0;
      return false;
     }
   return true;
  }

bool MultiNormalizeReversePending(const MultiGroupState &group,
                                  const long expected_direction,
                                  const double expected_price,
                                  const double expected_volume,
                                  ulong &keep_ticket)
  {
   keep_ticket = 0;
   const double price_tolerance = _Point * 0.5;
   const double volume_tolerance = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP) * 0.5;
   for(int index = 0; index < OrdersTotal(); index++)
     {
      const ulong candidate = OrderGetTicket(index);
      if(candidate == 0
         || OrderGetString(ORDER_SYMBOL) != _Symbol
         || (ulong)OrderGetInteger(ORDER_MAGIC) != g_gui_applied_config.magic_number
         || !IsReversePendingType(OrderGetInteger(ORDER_TYPE)))
         continue;
      const string comment = OrderGetString(ORDER_COMMENT);
      if(!MultiCommentMatches(comment, group.id)
         || IsGridPendingComment(comment)
         || MultiIsInitialPendingComment(comment))
         continue;
      if(PendingDirection(OrderGetInteger(ORDER_TYPE)) == expected_direction
         && MathAbs(OrderGetDouble(ORDER_PRICE_OPEN) - expected_price) <= price_tolerance
         && MathAbs(OrderGetDouble(ORDER_VOLUME_CURRENT) - expected_volume)
            <= volume_tolerance
         && (keep_ticket == 0 || candidate < keep_ticket))
         keep_ticket = candidate;
     }
   bool normalized = true;
   for(int index = OrdersTotal() - 1; index >= 0; index--)
     {
      const ulong candidate = OrderGetTicket(index);
      if(candidate == 0 || candidate == keep_ticket
         || OrderGetString(ORDER_SYMBOL) != _Symbol
         || (ulong)OrderGetInteger(ORDER_MAGIC) != g_gui_applied_config.magic_number
         || !IsReversePendingType(OrderGetInteger(ORDER_TYPE)))
         continue;
      const string comment = OrderGetString(ORDER_COMMENT);
      if(!MultiCommentMatches(comment, group.id)
         || IsGridPendingComment(comment)
         || MultiIsInitialPendingComment(comment))
         continue;
      if(!DeletePendingTicket(candidate, "Multi reverse pending reconciliation"))
         normalized = false;
     }
   return normalized;
  }

bool MultiPlaceReversePending(MultiGroupState &group, const long current_type)
  {
   if(g_gui_applied_config.cost_mode)
     { Print("[COST_REJECT=UNSUPPORTED_MULTI_REVERSE]"); return false; }
   if(group.reversal_count >= g_gui_applied_config.max_reversals
      || group.stop_points <= 0
      || group.take_profit_points <= 0 || group.total_lots <= 0.0)
      return false;
   const int next_index = (group.cycle_index + 1) % CycleLength(group.cycle_mode);
   const long next_direction = MultiSequenceDirection(group, next_index);
   const double entry = MultiStopPrice(group, current_type);
   ReversalLotPlan plan;
   if(!BuildReversalLotPlan(MultiNextGroupLotsRaw(group, group.total_lots), plan)
      || plan.status != REVERSAL_LOT_SINGLE)
      return false;
   const double volume = VolumeNormalize(plan.first_lots);
   ulong existing_ticket = 0;
   if(!MultiNormalizeReversePending(group, next_direction, entry, volume,
                                    existing_ticket))
      return false;
   if(existing_ticket > 0)
     {
      group.pending_ticket = existing_ticket;
      group.pending_index = next_index;
      return true;
   }
   const long pending_type = PendingTypeForDirection(next_direction, entry);
   double pending_sl = 0.0;
   double pending_tp = 0.0;
   string reason = "";
   if(!BuildStopsForEntry(next_direction, entry, group.stop_points,
                          group.take_profit_points, pending_sl, pending_tp,
                          reason))
     {
      PrintFormat("[GROUP=%d][STATE=%s][EVENT=REVERSE_PENDING_STOP_REJECTED] "
                  "[ENTRY=%.5f][SL=%.5f][TP=%.5f][ERROR=%s]",
                  group.id, StrategyStateText(group.state), entry, pending_sl,
                  pending_tp, reason);
      return false;
     }
   bool sent = false;
   const string comment = MultiGroupComment(group.id, false);
   if(pending_type == ORDER_TYPE_BUY_STOP || pending_type == ORDER_TYPE_BUY_LIMIT)
     {
      sent = pending_type == ORDER_TYPE_BUY_STOP
             ? g_trade.BuyStop(volume, entry, _Symbol, pending_sl, pending_tp,
                               ORDER_TIME_GTC, 0, comment)
             : g_trade.BuyLimit(volume, entry, _Symbol, pending_sl, pending_tp,
                                ORDER_TIME_GTC, 0, comment);
     }
   else
     {
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
   if(g_gui_applied_config.grid_count <= 0 || group.stop_points <= 0
      || group.anchor_price <= 0.0)
      return 0.0;
   const double distance = group.stop_points * _Point * level
                           / g_gui_applied_config.grid_count;
   return type == POSITION_TYPE_BUY
          ? PriceNormalize(group.anchor_price - distance)
          : PriceNormalize(group.anchor_price + distance);
  }

double MultiFavorableGridLevelPrice(const MultiGroupState &group, const long type, const int level)
  {
   if(g_gui_applied_config.grid_count <= 0 || group.stop_points <= 0
      || group.anchor_price <= 0.0)
      return 0.0;
   const double distance = group.stop_points * _Point * level
                           / g_gui_applied_config.grid_count;
   return type == POSITION_TYPE_BUY
          ? PriceNormalize(group.anchor_price + distance)
          : PriceNormalize(group.anchor_price - distance);
  }

bool PrepareMultiGridPendingForCurrentStop(const MultiGroupState &group,
                                           const long position_type,
                                           const double entry, const bool favorable,
                                           ulong &ticket);

double MultiGridLotsForNewGroup(const MultiGroupState &group)
  {
   return GridLotsForNewGroup(group.first_lots, group.grid_lots);
  }

bool MultiPlaceGridPending(MultiGroupState &group, const long type)
  {
   if(g_gui_applied_config.cost_mode)
     { Print("[COST_REJECT=UNSUPPORTED_MULTI_GRID]"); return false; }
   group.grid_lots = MultiGridLotsForNewGroup(group);
   if(g_gui_applied_config.grid_count < 2
      || group.grid_lots <= 0.0 || group.anchor_price <= 0.0)
      return false;
   const double volume = VolumeNormalize(group.grid_lots);
   bool placed = false;
   for(int level = 1; level < g_gui_applied_config.grid_count; level++)
     {
      if((group.grid_filled_mask & GridLevelBit(level)) != 0)
         continue;
      const double entry = MultiGridLevelPrice(group, type, level);
      ulong existing_ticket = 0;
       if(!MultiNormalizeGridPendingLevel(group,
                                          type == POSITION_TYPE_BUY
                                          ? ORDER_TYPE_BUY : ORDER_TYPE_SELL,
                                          level, entry, volume, existing_ticket))
          continue;
       if(!PrepareMultiGridPendingForCurrentStop(group, type, entry, false,
                                                 existing_ticket))
          return false;
       if(existing_ticket == 0
          && ((type == POSITION_TYPE_BUY && entry <= MultiStopPrice(group, type) + _Point * 0.5)
              || (type == POSITION_TYPE_SELL && entry >= MultiStopPrice(group, type) - _Point * 0.5)))
          continue;
       if(existing_ticket == 0)
        {
         const long pending_type = PendingTypeForDirection(type, entry);
         double stop_loss = MultiStopPrice(group, type);
         double take_profit = type == POSITION_TYPE_BUY
                              ? PriceNormalize(entry + group.take_profit_points * _Point)
                              : PriceNormalize(entry - group.take_profit_points * _Point);
         string stop_reason = "";
         if(!ValidateStops((ENUM_POSITION_TYPE)type, entry, stop_loss,
                           take_profit, stop_reason))
            continue;
         const string comment = g_gui_applied_config.order_comment
                                + MultiGroupTag(group.id) + ".Grid."
                                + IntegerToString(level);
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
            PrintFormat("Multi group grid pending failed, group=%d, level=%d, retcode=%u, %s",
                        group.id, level, g_trade.ResultRetcode(),
                        g_trade.ResultRetcodeDescription());
            continue;
           }
         existing_ticket = g_trade.ResultOrder();
        }
      group.grid_pending_ticket = existing_ticket;
      group.grid_pending_level = level;
      group.grid_pending_price = entry;
      MultiRememberGridOrderTicket(group.id, level, false, existing_ticket);
      placed = true;
      }
    if(g_gui_applied_config.favorable_grid_enable == 1)
      for(int level = 1; level < g_gui_applied_config.grid_count; level++)
        {
         if((group.favorable_grid_filled_mask & GridLevelBit(level)) != 0)
            continue;
         const double entry = MultiFavorableGridLevelPrice(group, type, level);
         ulong existing_ticket = 0;
          if(!MultiNormalizeGridPendingLevel(group,
                                             type == POSITION_TYPE_BUY
                                             ? ORDER_TYPE_BUY : ORDER_TYPE_SELL,
                                             level, entry, volume, existing_ticket))
             continue;
          if(!PrepareMultiGridPendingForCurrentStop(group, type, entry, true,
                                                    existing_ticket))
             return false;
          if(existing_ticket == 0)
           {
            const long pending_type = PendingTypeForDirection(type, entry);
            double stop_loss = MultiStopPrice(group, type);
            double take_profit = MultiTakeProfitPrice(group, type);
            string stop_reason = "";
            if(!ValidateStops((ENUM_POSITION_TYPE)type, entry, stop_loss,
                              take_profit, stop_reason))
               continue;
            if(MathAbs(take_profit - MultiTakeProfitPrice(group, type)) > _Point * 0.5)
               continue;
            const string comment = g_gui_applied_config.order_comment
                                   + MultiGroupTag(group.id) + ".Grid.F."
                                   + IntegerToString(level);
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
               PrintFormat("Multi favorable grid pending failed, group=%d, level=%d, retcode=%u, %s",
                           group.id, level, g_trade.ResultRetcode(),
                           g_trade.ResultRetcodeDescription());
               continue;
              }
            existing_ticket = g_trade.ResultOrder();
           }
         group.favorable_grid_pending_ticket = existing_ticket;
         group.favorable_grid_pending_level = level;
         group.favorable_grid_pending_price = entry;
         MultiRememberGridOrderTicket(group.id, level, true, existing_ticket);
         placed = true;
        }
    group.grid_filled_levels = MultiGridFilledLevelCount(group);
    group.favorable_grid_filled_levels = 0;
    for(int level = 1; level < g_gui_applied_config.grid_count; level++)
       if((group.favorable_grid_filled_mask & GridLevelBit(level)) != 0)
          group.favorable_grid_filled_levels++;
   return placed;
  }

bool PrepareMultiGridPendingForCurrentStop(const MultiGroupState &group,
                                           const long position_type,
                                           const double entry, const bool favorable,
                                           ulong &ticket)
  {
   if(ticket == 0)
      return true;
   const double stop_loss = MultiStopPrice(group, position_type);
   const double tolerance = _Point * 0.5;
   const bool adverse_level_invalid = !favorable
                                      && ((position_type == POSITION_TYPE_BUY
                                           && entry <= stop_loss + tolerance)
                                          || (position_type == POSITION_TYPE_SELL
                                              && entry >= stop_loss - tolerance));
   if(!OrderSelect(ticket))
     {
      ticket = 0;
      return true;
     }
   const double expected_take_profit = MultiTakeProfitPrice(group, position_type);
   const bool wrong_take_profit = favorable
                                  && MathAbs(OrderGetDouble(ORDER_TP) - expected_take_profit)
                                     > tolerance;
   if(!adverse_level_invalid
      && (g_gui_applied_config.dynamic_stop_loss_enable != 1
          || MathAbs(OrderGetDouble(ORDER_SL) - stop_loss) <= tolerance)
      && !wrong_take_profit)
      return true;
   if(!DeletePendingTicket(ticket, "Dynamic multi grid pending cleanup"))
      return false;
   ticket = 0;
   return true;
  }

bool MultiHandleGridFill(MultiGroupState &group, const long type, const double current_total)
  {
   if(g_gui_applied_config.grid_count < 2 || group.anchor_price <= 0.0)
      return false;
   bool changed = false;
   double latest_entry = 0.0;
   for(int level = 1; level < g_gui_applied_config.grid_count; level++)
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
    if(g_gui_applied_config.favorable_grid_enable == 1)
      for(int level = 1; level < g_gui_applied_config.grid_count; level++)
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
      return false;
   group.grid_filled_levels = MultiGridFilledLevelCount(group);
   group.grid_pending_level = 0;
   group.grid_pending_ticket = 0;
   group.grid_pending_price = 0.0;
   group.favorable_grid_filled_levels = 0;
   for(int level = 1; level < g_gui_applied_config.grid_count; level++)
      if((group.favorable_grid_filled_mask & GridLevelBit(level)) != 0)
         group.favorable_grid_filled_levels++;
   group.favorable_grid_pending_ticket = 0;
   group.favorable_grid_pending_level = 0;
   group.favorable_grid_pending_price = 0.0;
   group.total_lots = current_total;
   if(latest_entry > 0.0)
      group.last_entry = latest_entry;
   MultiSetStops(group, type);
   return true;
  }

bool MultiHandleReverseFill(MultiGroupState &group, long &type, double &entry,
                             double &current_total)
  {
   if(group.pending_ticket == 0 || group.pending_index < 0
      || group.pending_index == group.cycle_index)
      return false;
   const int status = MultiPendingStatus(group.pending_ticket, group.id, false);
    if(status != REVERSE_PENDING_FILLED)
       return false;
    ulong filled_ticket = 0;
    long filled_type = type;
    double filled_volume = 0.0;
    double filled_entry = entry;
    double filled_stop_loss = 0.0;
    double filled_take_profit = 0.0;
    if(!FindPositionByPendingOrder(group.pending_ticket, filled_ticket, filled_type,
                                   filled_volume, filled_entry, filled_stop_loss,
                                   filled_take_profit)
       && !FindPositionByTicket(group.pending_ticket, filled_ticket, filled_type,
                                filled_volume, filled_entry, filled_stop_loss,
                                filled_take_profit))
       return true;
    if(!MultiDeletePending(group.id))
       return true;
    if(!MultiClosePositionsExcept(group.id, filled_ticket))
      {
       PrintFormat("Reverse fill detected for multi group %d, but the previous order group is not fully closed; retrying.",
                   group.id);
       return true;
      }
    const long promoted_type = filled_type;
    const double promoted_entry = filled_entry;
    const double promoted_total = MultiTotalPositionVolume(group.id, promoted_type);
    if(promoted_total <= 0.0)
       return true;
    type = promoted_type;
    entry = promoted_entry;
    current_total = promoted_total;
    if(group.reversal_count >= g_gui_applied_config.max_reversals)
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
    group.anchor_price = promoted_entry;
    group.last_entry = promoted_entry;
    group.linear_extreme = promoted_entry;
    group.first_lots = promoted_total;
    group.total_lots = promoted_total;
   group.grid_filled_levels = 0;
   group.grid_filled_mask = 0;
   group.grid_pending_level = 0;
   group.grid_pending_ticket = 0;
   group.grid_pending_price = 0.0;
   group.favorable_grid_pending_ticket = 0;
   group.favorable_grid_filled_levels = 0;
   group.favorable_grid_filled_mask = 0;
   group.favorable_grid_pending_level = 0;
   group.favorable_grid_pending_price = 0.0;
   group.grid_lots = group.previous_grid_lots > 0.0
                     ? VolumeNormalize(group.previous_grid_lots
                                       * g_gui_applied_config.grid_lot_multiplier)
                      : promoted_total;
    MultiSetStops(group, promoted_type);
   return true;
  }

bool ResetOrderGroupAfterOversizedReversal(MultiGroupState &group)
  {
   PrintFormat("Oversized reversal stopped group %d; start a fresh base-lot group on the next tick.",
               group.id);
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

   const long current_type = MultiSequenceDirection(group, group.cycle_index);
   const double stop_loss = MultiStopPrice(group, current_type);
   const double take_profit = MultiTakeProfitPrice(group, current_type);
   const double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   const double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   if((current_type == POSITION_TYPE_BUY && bid >= take_profit)
      || (current_type == POSITION_TYPE_SELL && ask <= take_profit))
      return false;
   if(!((current_type == POSITION_TYPE_BUY && bid <= stop_loss)
        || (current_type == POSITION_TYPE_SELL && ask >= stop_loss)))
      return false;

   const double stopped_group_volume = group.total_lots > 0.0
                                      ? group.total_lots : group.first_lots;
   const double next_group_lots = MultiNextGroupLotsAfterStopRaw(
      group, stopped_group_volume);
   ReversalLotPlan reversal_plan;
   if(!BuildReversalLotPlan(next_group_lots, reversal_plan))
      return true;
   PrintFormat("Broker stop closed multi group %d before EA processing; recovering the reverse market order. "
               "first_lots=%.2f, group_lots=%.2f, next_lots=%.2f",
               group.id, group.first_lots, stopped_group_volume, next_group_lots);
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
   const long next_type = MultiSequenceDirection(group, next_index);
   group.reversal_count++;
   group.cycle_index = next_index;
   group.pending_index = -1;
   group.pending_ticket = 0;
   group.transition_target_lots = next_group_lots;
   if(!MultiOpenMarket(group, next_type, next_group_lots))
      return true;

   ulong ticket = 0;
   long type = POSITION_TYPE_BUY;
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
   group.grid_pending_ticket = 0;
   group.grid_pending_price = 0.0;
   group.favorable_grid_pending_ticket = 0;
   group.favorable_grid_filled_levels = 0;
   group.favorable_grid_filled_mask = 0;
   group.favorable_grid_pending_level = 0;
   group.favorable_grid_pending_price = 0.0;
   group.grid_lots = group.previous_grid_lots > 0.0
                     ? VolumeNormalize(group.previous_grid_lots
                                       * g_gui_applied_config.grid_lot_multiplier)
                     : total;
   if(!MultiSetStops(group, type) || !MultiStopsVerified(group, type))
      return true;
   MultiPlaceReversePending(group, type);
   MultiPlaceGridPending(group, type);
   return true;
  }

bool MultiManageGroup(MultiGroupState &group)
  {
   if(group.request_in_flight)
     {
      if(!MultiConfirmTradeRequestFromVisible(group))
        {
         group.state = STATE_ORDER_SENDING;
         const datetime now = TimeCurrent();
         if(g_last_multi_request_wait_log == 0
            || now - g_last_multi_request_wait_log >= 10)
           {
            MultiLogTradeEvent(group, "REQUEST_STILL_IN_FLIGHT");
            g_last_multi_request_wait_log = now;
           }
        }
      return true;
     }
   if(group.pair_role == 3)
     {
      if(g_multi_pair_failure_log_time == 0
         || TimeCurrent() - g_multi_pair_failure_log_time >= 10)
        {
         PrintFormat("[PAIR_STATUS=PARTIAL][PRIMARY_GROUP=%d][OPPOSITE_GROUP=%d][RETCODE=%d][REASON=OPPOSITE_SEND_PERMANENT]",
                     group.pair_peer_id, group.id, group.pair_failure_retcode);
         g_multi_pair_failure_log_time = TimeCurrent();
        }
      return true;
     }
   if(group.pair_role == 2)
     {
      const int peer_index = MultiFindGroupIndex(group.pair_peer_id);
      if(peer_index < 0 || !g_multi_groups[peer_index].active)
        { group.active = false; group.dirty = true; return false; }
      if(g_multi_groups[peer_index].request_in_flight)
         return true;
      ulong peer_ticket = 0;
      long peer_type = POSITION_TYPE_BUY;
      double peer_total = 0.0, peer_entry = 0.0, peer_sl = 0.0, peer_tp = 0.0;
      if(!MultiFindPosition(group.pair_peer_id, peer_ticket, peer_type,
                            peer_total, peer_entry, peer_sl, peer_tp))
         return true;
      if(!MultiStopsVerified(g_multi_groups[peer_index], peer_type)
         && (!MultiSetStops(g_multi_groups[peer_index], peer_type)
             || !MultiStopsVerified(g_multi_groups[peer_index], peer_type)))
         return true;
     }
   if(MultiHandleInitialPendingFill(group))
      return true;
   ulong ticket = 0;
   long type = POSITION_TYPE_BUY;
   double total = 0.0;
   double entry = 0.0;
   double stop_loss = 0.0;
   double take_profit = 0.0;
   bool has_position = MultiFindPosition(group.id, ticket, type, total, entry,
                                         stop_loss, take_profit);
   if(has_position && group.pair_role != 0)
     {
      group.pair_role = 0;
      group.pair_peer_id = 0;
      group.dirty = true;
     }
   // A failed market reversal must remain recoverable. The old reverse
   // pending order is not a substitute for the required market order.
   if(!has_position && group.transition_target_lots > 0.0)
     {
      if(!MultiDeletePending(group.id))
         return true;
      const long expected_type = MultiSequenceDirection(group, group.cycle_index);
      if(!MultiOpenMarket(group, expected_type, group.transition_target_lots))
        {
         if(group.pair_role == 2 && !group.request_in_flight)
           {
            group.pair_role = 3;
            group.pair_failure_retcode = (int)g_trade.ResultRetcode();
            group.state = STATE_RECOVERY;
            group.dirty = true;
            if(g_multi_pair_failure_log_time == 0
               || TimeCurrent() - g_multi_pair_failure_log_time >= 10)
              {
               PrintFormat("[PAIR_STATUS=PARTIAL][PRIMARY_GROUP=%d][OPPOSITE_GROUP=%d][RETCODE=%u][REASON=%s]",
                           group.pair_peer_id, group.id, g_trade.ResultRetcode(),
                           g_trade.ResultRetcodeDescription());
               g_multi_pair_failure_log_time = TimeCurrent();
              }
            MultiSaveGroup(group);
           }
         return true;
        }
      has_position = MultiFindPosition(group.id, ticket, type, total, entry,
                                       stop_loss, take_profit);
      if(!has_position)
         return true;
     }
   if(!has_position)
     {
      if(MultiRecoverFlatGroupAfterBrokerStop(group))
         return true;
      const int pending_status = MultiPendingStatus(group.pending_ticket, group.id, false);
      if(pending_status == REVERSE_PENDING_ACTIVE
         || pending_status == REVERSE_PENDING_FILLED)
         return true;
      if(!MultiDeletePending(group.id))
         return true;
      group.active = false;
      MarkMultiCandleTriggerBar();
      return false;
     }

   if(group.transition_target_lots > 0.0)
     {
      const double tolerance = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP) * 0.5;
      if(type != MultiSequenceDirection(group, group.cycle_index))
         return true;
      if(total + tolerance < group.transition_target_lots)
        {
         if(!MultiOpenMarket(group, type, group.transition_target_lots))
            return true;
         if(!MultiFindPosition(group.id, ticket, type, total, entry,
                               stop_loss, take_profit))
            return true;
        }
      if(total > group.transition_target_lots + tolerance)
         return true;
      group.transition_target_lots = 0.0;
      group.pair_role = 0;
      group.pair_peer_id = 0;
      group.anchor_price = entry;
      group.last_entry = entry;
      group.linear_extreme = entry;
      group.first_lots = total;
      group.total_lots = total;
      group.grid_filled_levels = 0;
      group.grid_filled_mask = 0;
      group.grid_pending_level = 0;
      group.grid_pending_ticket = 0;
      group.grid_pending_price = 0.0;
      group.favorable_grid_pending_ticket = 0;
      group.favorable_grid_filled_levels = 0;
      group.favorable_grid_filled_mask = 0;
      group.favorable_grid_pending_level = 0;
      group.favorable_grid_pending_price = 0.0;
      group.grid_lots = group.previous_grid_lots > 0.0
                        ? VolumeNormalize(group.previous_grid_lots
                                          * g_gui_applied_config.grid_lot_multiplier)
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
    if(group.first_lots <= 0.0)
       group.first_lots = total;
    group.total_lots = total;
   if(group.grid_lots <= 0.0)
      group.grid_lots = total;

   if(g_gui_applied_config.take_profit_mode == TAKE_PROFIT_LINEAR)
     {
      const double reference = type == POSITION_TYPE_BUY
                               ? SymbolInfoDouble(_Symbol, SYMBOL_ASK)
                               : SymbolInfoDouble(_Symbol, SYMBOL_BID);
      if((type == POSITION_TYPE_BUY && reference < group.linear_extreme)
         || (type == POSITION_TYPE_SELL && reference > group.linear_extreme))
        {
         group.linear_extreme = reference;
         if(!MultiSetStops(group, type) || !MultiStopsVerified(group, type))
            return true;
        }
     }

   const double desired_stop_loss = MultiStopPrice(group, type);
   const double desired_take_profit = MultiTakeProfitPrice(group, type);
   if((type == POSITION_TYPE_BUY && SymbolInfoDouble(_Symbol, SYMBOL_BID) >= desired_take_profit)
      || (type == POSITION_TYPE_SELL && SymbolInfoDouble(_Symbol, SYMBOL_ASK) <= desired_take_profit))
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

   if((type == POSITION_TYPE_BUY && SymbolInfoDouble(_Symbol, SYMBOL_BID) <= desired_stop_loss)
      || (type == POSITION_TYPE_SELL && SymbolInfoDouble(_Symbol, SYMBOL_ASK) >= desired_stop_loss))
     {
      PrintFormat("Stop reached for group %d; canceling the old reverse pending order and forcing a market reversal.",
                  group.id);
      if(group.reversal_count >= g_gui_applied_config.max_reversals)
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
      if(!MultiClosePositions(group.id))
         return false;
      const int next_index = (group.cycle_index + 1) % CycleLength(group.cycle_mode);
      const long next_type = MultiSequenceDirection(group, next_index);
      group.reversal_count++;
      group.cycle_index = next_index;
      group.pending_index = -1;
      group.pending_ticket = 0;
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
      group.grid_pending_ticket = 0;
      group.grid_pending_price = 0.0;
      group.favorable_grid_pending_ticket = 0;
      group.favorable_grid_filled_levels = 0;
      group.favorable_grid_filled_mask = 0;
      group.favorable_grid_pending_level = 0;
      group.favorable_grid_pending_price = 0.0;
      group.grid_lots = group.previous_grid_lots > 0.0
                        ? VolumeNormalize(group.previous_grid_lots
                                          * g_gui_applied_config.grid_lot_multiplier)
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
   if(!g_gui_config_initialized || g_reset_pending)
      return;
   if((g_gui_applied_config.distance_mode == DISTANCE_CANDLE_RANGE
       && g_gui_applied_config.candle_enable_multiple == 1)
      || MultiHasActiveGroups())
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

bool MultiStartResolvedStandardPair(const long direction, const int stop_points,
                                    const int take_profit_points,
                                    const double requested_lots)
  {
   if((direction != ORDER_TYPE_BUY && direction != ORDER_TYPE_SELL)
      || stop_points <= 0 || take_profit_points <= 0
      )
      return false;
   const double lots = VolumeNormalize(requested_lots);
   if(lots <= 0.0)
      return false;
   const int first_index = ArraySize(g_multi_groups);
   if(ArrayResize(g_multi_groups, first_index + 2) != first_index + 2)
      return false;
   const int primary_id = g_multi_next_id++;
   const int opposite_id = g_multi_next_id++;
   const long opposite = direction == ORDER_TYPE_BUY ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
   for(int leg = 0; leg < 2; leg++)
     {
      const int index = first_index + leg;
      const long leg_direction = leg == 0 ? direction : opposite;
      MultiResetState(g_multi_groups[index], leg == 0 ? primary_id : opposite_id);
      g_multi_groups[index].pair_role = leg == 0 ? 1 : 2;
      g_multi_groups[index].pair_peer_id = leg == 0 ? opposite_id : primary_id;
      g_multi_groups[index].first_direction = leg_direction == ORDER_TYPE_BUY ? FIRST_BUY : FIRST_SELL;
      g_multi_groups[index].cycle_mode = g_gui_applied_config.cycle_mode;
      g_multi_groups[index].stop_points = stop_points;
      g_multi_groups[index].take_profit_points = take_profit_points;
      g_multi_groups[index].transition_target_lots = lots;
      g_multi_groups[index].signal_bar_time = iTime(_Symbol, _Period, 0);
      g_multi_groups[index].signal_id = BuildSignalId(g_multi_groups[index].signal_bar_time,
                                                       leg_direction) * 1000
                                        + g_multi_groups[index].id;
      g_multi_groups[index].state = STATE_SIGNAL_READY;
      g_multi_groups[index].dirty = true;
      MultiSaveGroup(g_multi_groups[index]);
     }
   if(!MultiOpenMarket(g_multi_groups[first_index], direction, lots))
     {
      if(g_multi_groups[first_index].request_in_flight)
         return true;
      g_multi_groups[first_index].pair_role = 0;
      g_multi_groups[first_index].pair_peer_id = 0;
      g_multi_groups[first_index].active = false;
      g_multi_groups[first_index + 1].active = false;
      g_multi_groups[first_index].dirty = true;
      g_multi_groups[first_index + 1].dirty = true;
      MultiSaveGroup(g_multi_groups[first_index]);
      MultiSaveGroup(g_multi_groups[first_index + 1]);
      return false;
     }
   ulong ticket = 0;
   long type = POSITION_TYPE_BUY;
   double total = 0.0, entry = 0.0, sl = 0.0, tp = 0.0;
   if(!MultiFindPosition(primary_id, ticket, type, total, entry, sl, tp))
      return true;
   g_multi_groups[first_index].anchor_price = entry;
   g_multi_groups[first_index].last_entry = entry;
   g_multi_groups[first_index].linear_extreme = entry;
   g_multi_groups[first_index].first_lots = total;
   g_multi_groups[first_index].total_lots = total;
   g_multi_groups[first_index].grid_lots = total;
   if(!MultiSetStops(g_multi_groups[first_index], type)
      || !MultiStopsVerified(g_multi_groups[first_index], type))
      {
       MultiSaveGroup(g_multi_groups[first_index]);
       return true;
      }
   MultiSaveGroup(g_multi_groups[first_index]);
   return true;
  }

bool MultiTryOpenCandleGroup()
  {
    if(篮子数量 == 2 && MultiHasActiveGroups())
       return false;
   if(!GuiAllowsInitialEntry())
      return false;
   if(!IsInitialEntryAllowed())
      return false;
   double previous_high = 0.0;
   double previous_low = 0.0;
   int range_points = 0;
   long first_direction = ORDER_TYPE_BUY;
    if(!GetPreviousCandleRange(previous_high, previous_low, range_points))
      return false;
   const datetime current_bar = iTime(_Symbol, _Period, 0);
   if(g_gui_applied_config.candle_order_mode == KORDER_ONCE_PER_BAR
      && current_bar > 0
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
    state.cycle_mode = g_gui_applied_config.cycle_mode;
    state.stop_points = range_points;
    state.take_profit_points = range_points;
    state.signal_bar_time = current_bar;
    state.signal_id = BuildSignalId(current_bar, first_direction) * 1000 + new_group_id;
    state.signal_consumed = true;
    state.state = STATE_SIGNAL_READY;
    if(g_gui_applied_config.candle_order_mode == KORDER_ONCE_PER_BAR
       && 篮子数量 == 2)
      {
       ArrayResize(g_multi_groups, new_index);
       return MultiStartCandleOcoPair(previous_high, previous_low,
                                      range_points, g_gui_applied_config.initial_lots);
      }
    if(g_gui_applied_config.candle_order_mode == KORDER_ONCE_PER_BAR)
      {
       if(!MultiPlaceInitialPendingPair(state, previous_high, previous_low,
                                        range_points, g_gui_applied_config.initial_lots))
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
       ArrayResize(g_multi_groups, new_index);
       return MultiStartResolvedStandardPair(first_direction, range_points,
                                              range_points,
                                              g_gui_applied_config.initial_lots);
      }
   state.first_direction = first_direction == ORDER_TYPE_BUY ? FIRST_BUY : FIRST_SELL;
   state.signal_id = BuildSignalId(current_bar, first_direction) * 1000 + new_group_id;
   if(!MultiOpenMarket(state, first_direction, g_gui_applied_config.initial_lots))
     {
      if(state.request_in_flight)
        {
         g_multi_groups[new_index] = state;
         MultiSaveGroup(g_multi_groups[new_index]);
         return true;
        }
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
      if(state.request_in_flight)
        {
         g_multi_groups[new_index] = state;
         MultiSaveGroup(g_multi_groups[new_index]);
         return true;
        }
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
   if(g_gui_applied_config.candle_order_mode == KORDER_ONCE_PER_BAR
      && current_bar > 0)
      g_multi_last_trigger_bar = current_bar;
   return true;
  }

void MarkMultiCandleTriggerBar()
  {
   if(g_gui_applied_config.candle_order_mode != KORDER_ONCE_PER_BAR)
      return;
   const datetime current_bar = iTime(_Symbol, _Period, 0);
   if(current_bar > 0)
      g_multi_last_trigger_bar = current_bar;
   GlobalVariableSet(StatePrefix() + ".multi.lasttriggerbar", (double)g_multi_last_trigger_bar);
  }

bool MultiCostEvaluate(MultiGroupState &group, const long direction,
                       const double extra_lots, const double extra_entry,
                       const double stop_loss, const double strategy_tp,
                       const double candidate_trigger, double &approved_tp,
                       double &projected_risk, string &reason)
  {
   reason = "";
   if(!group.cost_active || group.cost_start <= 0 || group.cost_target <= 0.0
      || group.stop_points <= 0)
     { reason = "COST_LEDGER_INCOMPLETE"; return false; }
   const ENUM_ORDER_TYPE calc_type = direction == ORDER_TYPE_BUY
                                     ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   const long expected_position_type = direction == ORDER_TYPE_BUY
                                       ? POSITION_TYPE_BUY : POSITION_TYPE_SELL;
   const double exit_sl = stop_loss + (direction == ORDER_TYPE_BUY ? -1.0 : 1.0)
      * g_gui_applied_config.cost_exit_slippage_points * _Point;
   double sl_cash = 0.0;
   double current_lots = 0.0;
   if(extra_lots > 0.0 && !OrderCalcProfit(calc_type, _Symbol, extra_lots,
                                          extra_entry, exit_sl, sl_cash))
     { reason = "PROFIT_CALC_FAILED"; return false; }
   for(int index = PositionsTotal() - 1; index >= 0; index--)
     {
      const ulong ticket = PositionGetTicket(index);
      if(!MultiIsOurPosition(ticket, group.id)) continue;
      if(PositionGetInteger(POSITION_TYPE) != expected_position_type)
        { reason = "MIXED_DIRECTION"; return false; }
      const double lots = PositionGetDouble(POSITION_VOLUME);
      double cash = 0.0;
      if(!OrderCalcProfit(calc_type, _Symbol, lots,
                          PositionGetDouble(POSITION_PRICE_OPEN), exit_sl, cash))
        { reason = "PROFIT_CALC_FAILED"; return false; }
      sl_cash += cash;
      current_lots += lots;
     }
   if(!HistorySelect(group.cost_start, TimeCurrent()))
     { reason = "COST_LEDGER_INCOMPLETE"; return false; }
   double realized = 0.0, paid_fees = 0.0, opened_lots = 0.0;
   for(int index = 0; index < HistoryDealsTotal(); index++)
     {
      const ulong deal = HistoryDealGetTicket(index);
      if(HistoryDealGetString(deal, DEAL_SYMBOL) != _Symbol
         || MultiCostGroupForPosition(HistoryDealGetInteger(deal, DEAL_POSITION_ID))
            != group.id) continue;
      const double fees = HistoryDealGetDouble(deal, DEAL_COMMISSION)
                          + HistoryDealGetDouble(deal, DEAL_FEE);
      realized += HistoryDealGetDouble(deal, DEAL_PROFIT)
                  + fees + HistoryDealGetDouble(deal, DEAL_SWAP);
      paid_fees += MathMax(0.0, -fees);
      if(HistoryDealGetInteger(deal, DEAL_ENTRY) == DEAL_ENTRY_IN)
         opened_lots += HistoryDealGetDouble(deal, DEAL_VOLUME);
     }
   if(current_lots > 0.0
      && opened_lots + SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP) * 0.5 < current_lots)
     { reason = "COST_LEDGER_INCOMPLETE"; return false; }
   const double unpaid_fees = MathMax(0.0,
      (opened_lots + extra_lots) * g_gui_applied_config.cost_roundtrip_fee_per_lot
      - paid_fees);
   const double net_sl = realized + sl_cash - unpaid_fees;
   projected_risk = MathMax(0.0, -net_sl);
   if(g_gui_applied_config.grid_count >= 2)
     {
      double anchor = group.anchor_price > 0.0 ? group.anchor_price : extra_entry;
      if(anchor <= 0.0)
        {
         for(int index = PositionsTotal() - 1; index >= 0; index--)
           {
            const ulong ticket = PositionGetTicket(index);
            if(MultiIsOurPosition(ticket, group.id))
              { anchor = PositionGetDouble(POSITION_PRICE_OPEN); break; }
           }
        }
      const double grid_lots = group.grid_lots > 0.0 ? group.grid_lots
                              : group.first_lots > 0.0 ? group.first_lots
                                : MathMax(extra_lots, current_lots);
      if(anchor <= 0.0 || grid_lots <= 0.0)
        { reason = "GRID_RISK_UNKNOWN"; return false; }
      for(int level = 1; level < g_gui_applied_config.grid_count; level++)
         for(int side = 0; side < 2; side++)
           {
            if(side == 1 && g_gui_applied_config.favorable_grid_enable != 1) continue;
            const long bit = GridLevelBit(level);
            if((side == 0 && (group.grid_filled_mask & bit) != 0)
               || (side == 1 && (group.favorable_grid_filled_mask & bit) != 0)) continue;
            const double spacing = group.stop_points * _Point * level
                                   / g_gui_applied_config.grid_count;
            const double trigger = anchor + (direction == ORDER_TYPE_BUY
               ? (side == 0 ? -spacing : spacing)
               : (side == 0 ? spacing : -spacing));
            if(extra_lots > 0.0 && candidate_trigger > 0.0
               && MathAbs(trigger - candidate_trigger)
                  <= SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE) * 0.5) continue;
            const double worst = trigger + (direction == ORDER_TYPE_BUY ? 1.0 : -1.0)
               * g_gui_applied_config.cost_entry_slippage_points * _Point;
            double cash = 0.0;
            if(!OrderCalcProfit(calc_type, _Symbol, grid_lots, worst, exit_sl, cash))
              { reason = "GRID_RISK_CALC_FAILED"; return false; }
            projected_risk += MathMax(0.0, -cash
               + grid_lots * g_gui_applied_config.cost_roundtrip_fee_per_lot);
           }
     }
   const double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   if(equity <= 0.0 || projected_risk
      > equity * g_gui_applied_config.cost_max_cycle_loss_equity_ratio)
     { reason = "CYCLE_RISK_LIMIT"; return false; }
   double aggregate = projected_risk;
   for(int index = 0; index < ArraySize(g_multi_groups); index++)
     {
      const MultiGroupState other = g_multi_groups[index];
      if(!other.active || other.id == group.id) continue;
       if(!other.cost_active || other.cost_risk < 0.0 || other.cost_frozen)
        { reason = "PARALLEL_LEDGER_UNAVAILABLE"; return false; }
      aggregate += other.cost_risk;
     }
   if(aggregate > equity * g_gui_applied_config.cost_max_total_loss_equity_ratio)
     { reason = "ACCOUNT_RISK_LIMIT"; return false; }
   const double tick_size = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tick_size <= 0.0)
     { reason = "INVALID_TICK"; return false; }
   const double extension = MathMin(g_gui_applied_config.cost_max_tp_extension_points,
      group.take_profit_points * g_gui_applied_config.cost_max_tp_extension_ratio) * _Point;
   double candidate = direction == ORDER_TYPE_BUY
                      ? PriceCeilToTick(strategy_tp) : PriceFloorToTick(strategy_tp);
   const double boundary = direction == ORDER_TYPE_BUY
                           ? candidate + extension : candidate - extension;
   const int steps = (int)MathMin(100000.0, MathCeil(extension / tick_size) + 2.0);
   for(int step = 0; step <= steps; step++)
     {
      if((direction == ORDER_TYPE_BUY && candidate > boundary + tick_size * 0.1)
         || (direction == ORDER_TYPE_SELL && candidate < boundary - tick_size * 0.1)) break;
      const double exit_tp = candidate + (direction == ORDER_TYPE_BUY ? -1.0 : 1.0)
         * g_gui_applied_config.cost_exit_slippage_points * _Point;
      double tp_cash = 0.0;
      if(extra_lots > 0.0 && !OrderCalcProfit(calc_type, _Symbol,
           extra_lots, extra_entry, exit_tp, tp_cash))
        { reason = "PROFIT_CALC_FAILED"; return false; }
      for(int index = PositionsTotal() - 1; index >= 0; index--)
        {
         const ulong ticket = PositionGetTicket(index);
         if(!MultiIsOurPosition(ticket, group.id)) continue;
         double cash = 0.0;
         if(!OrderCalcProfit(calc_type, _Symbol,
              PositionGetDouble(POSITION_VOLUME),
              PositionGetDouble(POSITION_PRICE_OPEN), exit_tp, cash))
           { reason = "PROFIT_CALC_FAILED"; return false; }
         tp_cash += cash;
        }
      const double net_tp = realized + tp_cash - unpaid_fees;
      if(net_tp > 0.0 && (net_sl >= 0.0 || net_tp >= group.cost_target * -net_sl))
        { approved_tp = PriceNormalize(candidate); return true; }
      candidate += direction == ORDER_TYPE_BUY ? tick_size : -tick_size;
      candidate = PriceNormalize(candidate);
     }
   reason = "TARGET_INFEASIBLE";
   return false;
  }

bool MultiCostSend(MultiGroupState &group, const long direction,
                   const double requested_lots, const double trigger,
                   const bool favorable)
  {
   if(group.cost_frozen || group.request_in_flight)
     { PrintFormat("[MULTI_COST_REJECT=FROZEN_OR_IN_FLIGHT][GROUP=%d]", group.id); return false; }
   const double lots = VolumeNormalize(requested_lots);
   if(lots <= 0.0 || trigger <= 0.0) return false;
   MqlTick tick;
   string reason = "";
   if(!CostQuoteAllowed(group.stop_points, tick, reason))
     { PrintFormat("[MULTI_COST_REJECT=%s][GROUP=%d]", reason, group.id); return false; }
   const double quote = direction == ORDER_TYPE_BUY ? tick.ask : tick.bid;
   const double worst = trigger + (direction == ORDER_TYPE_BUY ? 1.0 : -1.0)
      * g_gui_applied_config.cost_entry_slippage_points * _Point;
   if((direction == ORDER_TYPE_BUY && quote > worst)
      || (direction == ORDER_TYPE_SELL && quote < worst))
     { PrintFormat("[MULTI_COST_REJECT=ENTRY_PRICE_LIMIT][GROUP=%d]", group.id); return false; }
   ulong current_ticket = 0;
   long current_type = POSITION_TYPE_BUY;
   double current_volume = 0.0, current_entry = 0.0, current_sl = 0.0, current_tp = 0.0;
   const bool has_position = MultiFindPosition(group.id, current_ticket, current_type,
      current_volume, current_entry, current_sl, current_tp);
    double stop_loss = has_position
      ? MultiStopPrice(group, current_type)
      : PriceNormalize(worst + (direction == ORDER_TYPE_BUY ? -1.0 : 1.0)
         * group.stop_points * _Point);
   const double reference = favorable && has_position
      ? (g_gui_applied_config.take_profit_mode == TAKE_PROFIT_LINEAR
         ? group.linear_extreme : group.last_entry) : worst;
   const double strategy_tp = PriceNormalize(reference
      + (direction == ORDER_TYPE_BUY ? 1.0 : -1.0)
        * group.take_profit_points * _Point);
   double approved_tp = 0.0, projected_risk = 0.0;
   if(!MultiCostEvaluate(group, direction, lots, worst, stop_loss,
                         strategy_tp, trigger, approved_tp, projected_risk, reason))
     { PrintFormat("[MULTI_COST_REJECT=%s][GROUP=%d]", reason, group.id); return false; }
    if(!ValidateStops((ENUM_POSITION_TYPE)(direction == ORDER_TYPE_BUY
                      ? POSITION_TYPE_BUY : POSITION_TYPE_SELL),
                      quote, stop_loss, approved_tp, reason))
      { PrintFormat("[MULTI_COST_REJECT=STOP_VALIDATION][GROUP=%d][DETAIL=%s]",
                    group.id, reason); return false; }
    if(!CostMarginAllowed(direction, lots, worst, reason))
      { PrintFormat("[MULTI_COST_REJECT=%s][GROUP=%d][CYCLE=%I64d]",
                    reason, group.id, (long)group.cost_start); return false; }
   g_trade.SetDeviationInPoints((ulong)MathCeil(g_gui_applied_config.cost_entry_slippage_points));
   group.request_in_flight = true;
   group.request_order_ticket = 0;
   group.request_direction = direction;
   group.request_volume = lots;
    group.dirty = true;
    MultiSaveGroup(group);
    const string comment = MultiGroupComment(group.id, has_position);
    PrintFormat("[MULTI_COST_REQUEST][GROUP=%d][CYCLE=%I64d][TRIGGER=%.5f][BID=%.5f][ASK=%.5f][WORST=%.5f][LOTS=%.2f][SL=%.5f][TP=%.5f][RISK=%.2f]",
                group.id, (long)group.cost_start, trigger, tick.bid, tick.ask,
                worst, lots, stop_loss, approved_tp, projected_risk);
   const bool sent = direction == ORDER_TYPE_BUY
      ? g_trade.Buy(lots, _Symbol, 0.0, stop_loss, approved_tp, comment)
      : g_trade.Sell(lots, _Symbol, 0.0, stop_loss, approved_tp, comment);
   const uint retcode = g_trade.ResultRetcode();
   group.request_order_ticket = g_trade.ResultOrder();
   group.dirty = true;
   MultiSaveGroup(group);
   if(!sent || (retcode != TRADE_RETCODE_DONE
                && retcode != TRADE_RETCODE_DONE_PARTIAL))
     {
      if(IsAmbiguousTradeRetcode(retcode))
        { group.cost_frozen = true; group.dirty = true; MultiSaveGroup(group); return false; }
      group.request_in_flight = false;
      group.dirty = true;
      MultiSaveGroup(group);
      PrintFormat("[MULTI_COST_REJECT=ORDER_SEND][GROUP=%d][RETCODE=%u]", group.id, retcode);
      return false;
     }
    const ulong deal = g_trade.ResultDeal();
   if(deal == 0 || !HistoryDealSelect(deal)
      || !MultiCostRememberPosition(HistoryDealGetInteger(deal, DEAL_POSITION_ID), group.id))
     { group.cost_frozen = true; group.dirty = true; MultiSaveGroup(group); return false; }
    MultiCostSaveMap();
    PrintFormat("[MULTI_COST_FILL][GROUP=%d][CYCLE=%I64d][DEAL=%I64u][PRICE=%.5f][LOTS=%.2f][PROFIT=%.2f][COMMISSION=%.2f][FEE=%.2f][SWAP=%.2f]",
                group.id, (long)group.cost_start, deal,
                HistoryDealGetDouble(deal, DEAL_PRICE), HistoryDealGetDouble(deal, DEAL_VOLUME),
                HistoryDealGetDouble(deal, DEAL_PROFIT),
                HistoryDealGetDouble(deal, DEAL_COMMISSION),
                HistoryDealGetDouble(deal, DEAL_FEE), HistoryDealGetDouble(deal, DEAL_SWAP));
   const long position_id = HistoryDealGetInteger(deal, DEAL_POSITION_ID);
   bool visible = false;
   for(int index = PositionsTotal() - 1; index >= 0; index--)
     {
      const ulong ticket = PositionGetTicket(index);
      if(MultiIsOurPosition(ticket, group.id)
         && PositionGetInteger(POSITION_IDENTIFIER) == position_id)
        {
         visible = true;
         const double fill = PositionGetDouble(POSITION_PRICE_OPEN);
         if((direction == ORDER_TYPE_BUY && fill > worst + _Point * 0.1)
            || (direction == ORDER_TYPE_SELL && fill < worst - _Point * 0.1))
            group.cost_frozen = true;
         break;
        }
     }
   group.request_in_flight = !visible;
   if(!visible || retcode == TRADE_RETCODE_DONE_PARTIAL)
      group.cost_frozen = true;
   group.cost_risk = projected_risk;
   group.dirty = true;
   MultiSaveGroup(group);
   return visible;
  }

bool MultiStartResolvedPair(const long direction, const int stop_points,
                            const int take_profit_points, const double requested_lots)
  {
   if((direction != ORDER_TYPE_BUY && direction != ORDER_TYPE_SELL)
      || stop_points <= 0 || take_profit_points <= 0)
      return false;
   const double lots = VolumeNormalize(requested_lots);
   if(lots <= 0.0)
      return false;
   MqlTick tick;
   string reason = "";
   if(!CostQuoteAllowed(stop_points, tick, reason))
      return false;
   const int first_index = ArraySize(g_multi_groups);
   if(ArrayResize(g_multi_groups, first_index + 2) != first_index + 2)
      return false;
   const int first_id = g_multi_next_id++;
   const int second_id = g_multi_next_id++;
   MultiResetState(g_multi_groups[first_index], first_id);
   MultiResetState(g_multi_groups[first_index + 1], second_id);
   g_multi_groups[first_index].pair_role = 1;
   g_multi_groups[first_index].pair_peer_id = second_id;
   g_multi_groups[first_index + 1].pair_role = 2;
   g_multi_groups[first_index + 1].pair_peer_id = first_id;
   const long opposite = direction == ORDER_TYPE_BUY ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
   const int dirs[2] = { (int)direction, (int)opposite };
   for(int leg = 0; leg < 2; leg++)
     {
      const int index = first_index + leg;
      const long leg_direction = (long)dirs[leg];
      g_multi_groups[index].first_direction = leg_direction == ORDER_TYPE_BUY ? FIRST_BUY : FIRST_SELL;
      g_multi_groups[index].cycle_mode = g_gui_applied_config.cycle_mode;
      g_multi_groups[index].stop_points = stop_points;
      g_multi_groups[index].take_profit_points = take_profit_points;
      g_multi_groups[index].transition_target_lots = lots;
      g_multi_groups[index].signal_bar_time = iTime(_Symbol, _Period, 0);
      g_multi_groups[index].signal_id = BuildSignalId(g_multi_groups[index].signal_bar_time, leg_direction) * 1000 + g_multi_groups[index].id;
      g_multi_groups[index].cost_active = true;
      g_multi_groups[index].cost_start = TimeCurrent() - 1;
      g_multi_groups[index].cost_target = g_gui_applied_config.cost_target_rr > 0.0
                          ? g_gui_applied_config.cost_target_rr : 1.0;
      g_multi_groups[index].cost_risk = 0.0;
      g_multi_groups[index].cost_bar = g_multi_groups[index].signal_bar_time;
      g_multi_groups[index].dirty = true;
     }
   const double prices[2] = { tick.ask, tick.bid };
   for(int leg = 0; leg < 2; leg++)
     {
      const int index = first_index + leg;
      const long leg_direction = (long)dirs[leg];
      const double worst = prices[leg] + (leg_direction == ORDER_TYPE_BUY ? 1.0 : -1.0)
                           * g_gui_applied_config.cost_entry_slippage_points * _Point;
      const double stop = PriceNormalize(worst + (leg_direction == ORDER_TYPE_BUY ? -1.0 : 1.0)
                                         * stop_points * _Point);
      const double target = PriceNormalize(worst + (leg_direction == ORDER_TYPE_BUY ? 1.0 : -1.0)
                                           * take_profit_points * _Point);
      double approved = 0.0, risk = 0.0;
      if(!MultiCostEvaluate(g_multi_groups[index], leg_direction, lots, worst, stop, target,
                            worst, approved, risk, reason))
        {
         g_multi_groups[first_index].active = false;
         g_multi_groups[first_index + 1].active = false;
         g_multi_groups[first_index].dirty = true;
         g_multi_groups[first_index + 1].dirty = true;
         MultiSaveGroup(g_multi_groups[first_index]);
         MultiSaveGroup(g_multi_groups[first_index + 1]);
         PrintFormat("[MULTI_COST_PAIR_REJECT=%s]", reason);
         return false;
        }
      g_multi_groups[index].cost_risk = risk;
      g_multi_groups[index].dirty = true;
      MultiSaveGroup(g_multi_groups[index]);
     }
   double first_margin = 0.0, second_margin = 0.0;
   const double first_worst = tick.ask + (direction == ORDER_TYPE_BUY ? 1.0 : -1.0)
      * g_gui_applied_config.cost_entry_slippage_points * _Point;
   const double second_worst = tick.bid + (opposite == ORDER_TYPE_BUY ? 1.0 : -1.0)
      * g_gui_applied_config.cost_entry_slippage_points * _Point;
   if(!OrderCalcMargin((ENUM_ORDER_TYPE)direction, _Symbol, lots, first_worst, first_margin)
      || !OrderCalcMargin((ENUM_ORDER_TYPE)opposite, _Symbol, lots, second_worst, second_margin)
      || first_margin + second_margin > AccountInfoDouble(ACCOUNT_MARGIN_FREE))
     {
      g_multi_groups[first_index].active = false;
      g_multi_groups[first_index + 1].active = false;
      g_multi_groups[first_index].dirty = true;
      g_multi_groups[first_index + 1].dirty = true;
      MultiSaveGroup(g_multi_groups[first_index]);
      MultiSaveGroup(g_multi_groups[first_index + 1]);
      Print("[MULTI_COST_PAIR_REJECT=COMBINED_MARGIN]");
      return false;
     }
   for(int index = first_index; index < first_index + 2; index++)
      MultiSaveGroup(g_multi_groups[index]);
   const double trigger = direction == ORDER_TYPE_BUY ? tick.ask : tick.bid;
   if(!MultiCostSend(g_multi_groups[first_index], direction, lots, trigger, false))
     {
      if(g_multi_groups[first_index].request_in_flight)
         return true;
      g_multi_groups[first_index].active = false;
      g_multi_groups[first_index + 1].active = false;
      g_multi_groups[first_index].dirty = true;
      g_multi_groups[first_index + 1].dirty = true;
      MultiSaveGroup(g_multi_groups[first_index]);
      MultiSaveGroup(g_multi_groups[first_index + 1]);
      return false;
     }
   ulong ticket = 0;
   long type = POSITION_TYPE_BUY;
   double total = 0.0, entry = 0.0, sl = 0.0, tp = 0.0;
   if(MultiFindPosition(first_id, ticket, type, total, entry, sl, tp))
     {
      g_multi_groups[first_index].anchor_price = entry;
      g_multi_groups[first_index].last_entry = entry;
      g_multi_groups[first_index].linear_extreme = entry;
      g_multi_groups[first_index].first_lots = total;
      g_multi_groups[first_index].total_lots = total;
      g_multi_groups[first_index].grid_lots = total;
      MultiCostProtect(g_multi_groups[first_index], type);
     }
   MultiSaveGroup(g_multi_groups[first_index]);
   return true;
  }

bool MultiCostProtect(MultiGroupState &group, const long type)
  {
   const double stop_loss = MultiStopPrice(group, type);
   double desired_tp = group.cost_tp;
   if(!group.cost_frozen)
     {
      string reason = "";
      double risk = 0.0;
      const long direction = type == POSITION_TYPE_BUY ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
      if(!MultiCostEvaluate(group, direction, 0.0, 0.0, stop_loss,
                            MultiTakeProfitPrice(group, type), 0.0,
                            desired_tp, risk, reason))
        { group.cost_frozen = true; PrintFormat("[MULTI_COST_FREEZE=%s][GROUP=%d]", reason, group.id); }
      else
        { group.cost_tp = desired_tp; group.cost_risk = risk; }
     }
   bool found = false;
   bool protected_all = true;
   for(int index = PositionsTotal() - 1; index >= 0; index--)
     {
      const ulong ticket = PositionGetTicket(index);
      if(!MultiIsOurPosition(ticket, group.id)
         || PositionGetInteger(POSITION_TYPE) != type) continue;
      found = true;
      const double current_sl = PositionGetDouble(POSITION_SL);
      const double current_tp = PositionGetDouble(POSITION_TP);
      const double target_tp = desired_tp > 0.0 ? desired_tp : current_tp;
      if(group.cost_frozen && current_sl > 0.0 && current_tp > 0.0) continue;
      if(target_tp <= 0.0) { protected_all = false; continue; }
      if(MathAbs(current_sl - stop_loss) > _Point * 0.5
         || MathAbs(current_tp - target_tp) > _Point * 0.5)
        {
         if(!g_trade.PositionModify(ticket, stop_loss, target_tp)
            || !PositionSelectByTicket(ticket)
            || MathAbs(PositionGetDouble(POSITION_SL) - stop_loss) > _Point * 0.5
            || MathAbs(PositionGetDouble(POSITION_TP) - target_tp) > _Point * 0.5)
           { protected_all = false; group.cost_frozen = true; }
        }
     }
   group.dirty = true;
   MultiSaveGroup(group);
    return found && protected_all;
   }

// The position identifier survives broker changes to the position comment and
// is also present on a server-side SL deal after the position has disappeared.
bool MultiCostLastStop(MultiGroupState &group)
   {
    if(group.cost_start <= 0 || !HistorySelect(group.cost_start, TimeCurrent()))
       return false;
    for(int index = 0; index < HistoryDealsTotal(); index++)
      {
       const ulong deal = HistoryDealGetTicket(index);
       if(HistoryDealGetString(deal, DEAL_SYMBOL) != _Symbol
          || MultiCostGroupForPosition(HistoryDealGetInteger(deal, DEAL_POSITION_ID)) != group.id
          || HistoryDealGetInteger(deal, DEAL_ENTRY) != DEAL_ENTRY_OUT
          || HistoryDealGetInteger(deal, DEAL_REASON) != DEAL_REASON_SL
          || deal <= group.cost_consumed_stop_deal) continue;
       const long msc = HistoryDealGetInteger(deal, DEAL_TIME_MSC);
       if(msc <= group.cost_stop_msc) continue;
       group.cost_stop_msc = msc;
       group.cost_stop_deal = deal;
       group.cost_stop_price = HistoryDealGetDouble(deal, DEAL_PRICE);
       group.cost_stop_type = HistoryDealGetInteger(deal, DEAL_TYPE) == DEAL_TYPE_SELL
                              ? POSITION_TYPE_BUY : POSITION_TYPE_SELL;
      }
    return group.cost_stop_deal > group.cost_consumed_stop_deal;
   }

void MultiCostEnd(MultiGroupState &group, const string reason)
   {
    double cash = 0.0, fees = 0.0;
    if(group.cost_start > 0 && HistorySelect(group.cost_start, TimeCurrent()))
       for(int index = 0; index < HistoryDealsTotal(); index++)
         {
          const ulong deal = HistoryDealGetTicket(index);
          if(MultiCostGroupForPosition(HistoryDealGetInteger(deal, DEAL_POSITION_ID)) != group.id)
             continue;
          const double paid = HistoryDealGetDouble(deal, DEAL_COMMISSION)
                              + HistoryDealGetDouble(deal, DEAL_FEE);
          fees += paid;
          cash += HistoryDealGetDouble(deal, DEAL_PROFIT) + paid
                  + HistoryDealGetDouble(deal, DEAL_SWAP);
         }
    PrintFormat("[MULTI_COST_CYCLE_END=%s][GROUP=%d][START=%I64d][NET=%.2f][FEES=%.2f][TARGET=%.3f]",
                reason, group.id, (long)group.cost_start, cash, fees, group.cost_target);
    group.active = false;
    group.dirty = true;
    MarkMultiCandleTriggerBar();
   }

bool MultiCostManageGroup(MultiGroupState &group)
   {
    if(group.pair_role == 3)
      {
       if(g_multi_pair_failure_log_time == 0
          || TimeCurrent() - g_multi_pair_failure_log_time >= 10)
         {
          PrintFormat("[PAIR_STATUS=PARTIAL][PRIMARY_GROUP=%d][OPPOSITE_GROUP=%d][RETCODE=%d][REASON=OPPOSITE_SEND_PERMANENT]",
                      group.pair_peer_id, group.id, group.pair_failure_retcode);
          g_multi_pair_failure_log_time = TimeCurrent();
         }
       return true;
      }
    if(group.request_in_flight)
      {
       if(!MultiConfirmTradeRequestFromVisible(group)) return true;
       group.cost_frozen = true; // Reconcile an ambiguous fill before any more risk.
      }
    if(!MultiDeletePending(group.id))
      { group.cost_frozen = true; return true; }
    ulong ticket = 0;
    long type = POSITION_TYPE_BUY;
    double total = 0.0, entry = 0.0, sl = 0.0, tp = 0.0;
    if(MultiFindPosition(group.id, ticket, type, total, entry, sl, tp))
      {
       if(group.pair_role != 0)
         { group.pair_role = 0; group.pair_peer_id = 0; group.dirty = true; }
       if(group.anchor_price <= 0.0) group.anchor_price = entry;
       if(group.last_entry <= 0.0) group.last_entry = entry;
       if(group.linear_extreme <= 0.0) group.linear_extreme = entry;
       if(group.first_lots <= 0.0) group.first_lots = total;
       group.total_lots = total;
       if(group.grid_lots <= 0.0) group.grid_lots = total;
       if(g_gui_applied_config.take_profit_mode == TAKE_PROFIT_LINEAR)
         {
          const double quote = type == POSITION_TYPE_BUY
             ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
          if((type == POSITION_TYPE_BUY && quote < group.linear_extreme)
             || (type == POSITION_TYPE_SELL && quote > group.linear_extreme))
             group.linear_extreme = quote;
         }
       if(!MultiCostProtect(group, type)) return true;
       const double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
       const double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
       if((type == POSITION_TYPE_BUY && bid >= group.cost_tp)
          || (type == POSITION_TYPE_SELL && ask <= group.cost_tp))
         {
          if(MultiClosePositions(group.id)) MultiCostEnd(group, "TP");
          return true;
         }
       const double stop = MultiStopPrice(group, type);
       if((type == POSITION_TYPE_BUY && bid <= stop)
          || (type == POSITION_TYPE_SELL && ask >= stop))
         {
          const double old_lots = group.total_lots;
          const double old_grid_lots = group.grid_lots;
          if(!MultiClosePositions(group.id)) return true;
          if(group.cost_frozen || group.reversal_count >= g_gui_applied_config.max_reversals)
            { MultiCostEnd(group, "STOP"); return true; }
          group.cumulative_loss_lots += old_lots;
          group.previous_grid_lots = old_grid_lots;
          group.reversal_count++;
          group.cycle_index = (group.cycle_index + 1) % CycleLength(group.cycle_mode);
          const long direction = MultiSequenceDirection(group, group.cycle_index);
          const double lots = MultiNextGroupLotsAfterStopRaw(group, old_lots);
          group.anchor_price = 0.0;
          group.last_entry = 0.0;
          group.linear_extreme = 0.0;
          group.grid_filled_mask = 0;
          group.favorable_grid_filled_mask = 0;
          group.grid_lots = VolumeNormalize(old_grid_lots * g_gui_applied_config.grid_lot_multiplier);
          group.dirty = true;
          MultiSaveGroup(group);
          if(!MultiCostSend(group, direction, lots, stop, false))
            { if(!group.request_in_flight) MultiCostEnd(group, "REVERSE_GATE"); return true; }
          if(!MultiFindPosition(group.id, ticket, type, total, entry, sl, tp))
            { group.cost_frozen = true; return true; }
          group.anchor_price = entry;
          group.last_entry = entry;
          group.linear_extreme = entry;
          group.first_lots = total;
          group.total_lots = total;
          MultiCostProtect(group, type);
          return true;
         }
       if(group.cost_frozen || g_gui_applied_config.grid_count < 2) return true;
       MqlTick tick;
       string quote_reason = "";
       if(!CostQuoteAllowed(group.stop_points, tick, quote_reason)) return true;
       group.grid_lots = MultiGridLotsForNewGroup(group);
       for(int level = 1; level < g_gui_applied_config.grid_count; level++)
          for(int side = 0; side < 2; side++)
            {
             if(side == 1 && g_gui_applied_config.favorable_grid_enable != 1) continue;
             const long bit = GridLevelBit(level);
             if((side == 0 && (group.grid_filled_mask & bit) != 0)
                || (side == 1 && (group.favorable_grid_filled_mask & bit) != 0)) continue;
             const double trigger = side == 0
                ? MultiGridLevelPrice(group, type, level)
                : MultiFavorableGridLevelPrice(group, type, level);
             if(side == 0)
               { group.grid_pending_level = level; group.grid_pending_price = trigger; }
             else
               { group.favorable_grid_pending_level = level;
                 group.favorable_grid_pending_price = trigger; }
             const double quote = type == POSITION_TYPE_BUY ? tick.ask : tick.bid;
             const bool hit = side == 0
                ? (type == POSITION_TYPE_BUY ? quote <= trigger : quote >= trigger)
                : (type == POSITION_TYPE_BUY ? quote >= trigger : quote <= trigger);
             if(!hit) continue;
             if((type == POSITION_TYPE_BUY && trigger <= stop + _Point * 0.5)
                || (type == POSITION_TYPE_SELL && trigger >= stop - _Point * 0.5)) continue;
             if(!MultiCostSend(group, type == POSITION_TYPE_BUY ? ORDER_TYPE_BUY : ORDER_TYPE_SELL,
                               group.grid_lots, trigger, side == 1)) return true;
             if(!MultiFindPosition(group.id, ticket, type, total, entry, sl, tp))
               { group.cost_frozen = true; return true; }
             if(side == 0)
               { group.grid_filled_mask |= bit; group.last_entry = entry; }
             else group.favorable_grid_filled_mask |= bit;
             group.total_lots = total;
             MultiCostProtect(group, type);
             return true;
            }
       return true;
      }
    if(group.pair_role != 0)
      {
       if(group.pair_role == 2)
         {
          const int peer_index = MultiFindGroupIndex(group.pair_peer_id);
          if(peer_index < 0 || !g_multi_groups[peer_index].active)
            { MultiCostEnd(group, "PAIR_PRIMARY_UNAVAILABLE"); return true; }
          if(g_multi_groups[peer_index].request_in_flight) return true;
          ulong peer_ticket = 0;
          long peer_type = POSITION_TYPE_BUY;
          double peer_total = 0.0, peer_entry = 0.0, peer_sl = 0.0, peer_tp = 0.0;
          if(!MultiFindPosition(group.pair_peer_id, peer_ticket, peer_type,
                                peer_total, peer_entry, peer_sl, peer_tp)) return true;
          if(!MultiCostProtect(g_multi_groups[peer_index], peer_type)) return true;
         }
       const long direction = group.first_direction == FIRST_BUY
                              ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
       MqlTick pair_tick;
       string pair_reason = "";
       if(!CostQuoteAllowed(group.stop_points, pair_tick, pair_reason)) return true;
       const double trigger = direction == ORDER_TYPE_BUY ? pair_tick.ask : pair_tick.bid;
       const double pair_lots = group.transition_target_lots > 0.0
                                ? group.transition_target_lots
                                : VolumeNormalize(g_gui_applied_config.initial_lots);
       if(!MultiCostSend(group, direction, pair_lots,
                         trigger, false))
         {
          if(group.request_in_flight) return true;
          if(group.pair_role == 2)
            {
             group.pair_role = 3;
             group.pair_failure_retcode = (int)g_trade.ResultRetcode();
             group.state = STATE_RECOVERY;
             group.dirty = true;
             if(g_multi_pair_failure_log_time == 0
                || TimeCurrent() - g_multi_pair_failure_log_time >= 10)
               {
                PrintFormat("[PAIR_STATUS=PARTIAL][PRIMARY_GROUP=%d][OPPOSITE_GROUP=%d][RETCODE=%u][REASON=%s]",
                            group.pair_peer_id, group.id, g_trade.ResultRetcode(),
                            g_trade.ResultRetcodeDescription());
                g_multi_pair_failure_log_time = TimeCurrent();
               }
             MultiSaveGroup(group);
             return true;
            }
          MultiCostEnd(group, "PAIR_ENTRY_GATE");
          return true;
         }
       if(!MultiFindPosition(group.id, ticket, type, total, entry, sl, tp))
         { group.cost_frozen = true; return true; }
       group.anchor_price = entry;
       group.last_entry = entry;
       group.linear_extreme = entry;
       group.first_lots = total;
       group.total_lots = total;
       group.grid_lots = total;
       group.transition_target_lots = 0.0;
       group.pair_role = 0;
       group.pair_peer_id = 0;
       MultiCostProtect(group, type);
       return true;
      }
    if(!group.cost_active) return true;
    if(group.cost_high > 0.0 && group.cost_low > 0.0)
      {
       if(group.cost_bar != iTime(_Symbol, _Period, 0))
         { MultiCostEnd(group, "ENTRY_EXPIRED"); return true; }
       MqlTick tick;
       string reason = "";
       if(!CostQuoteAllowed(group.stop_points, tick, reason)) return true;
       const bool high = tick.ask >= group.cost_high;
       const bool low = tick.bid <= group.cost_low;
       if(high && low)
         { PrintFormat("[MULTI_COST_SKIP=DUAL_CANDLE_TRIGGER][GROUP=%d]", group.id); return true; }
       if(!high && !low) return true;
       const long direction = high ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
       const double trigger = high ? group.cost_high : group.cost_low;
        if(篮子数量 == 2)
          {
           const int stop_points = group.stop_points;
           const int take_profit_points = group.take_profit_points;
           group.cost_high = 0.0;
           group.cost_low = 0.0;
           group.active = false;
           group.dirty = true;
           MultiSaveGroup(group);
           return MultiStartResolvedPair(direction, stop_points, take_profit_points,
                                         g_gui_applied_config.initial_lots);
          }
       group.cost_high = 0.0;
       group.cost_low = 0.0;
       group.dirty = true;
       MultiSaveGroup(group);
       if(!MultiCostSend(group, direction, g_gui_applied_config.initial_lots, trigger, false))
         { if(!group.request_in_flight) MultiCostEnd(group, "ENTRY_GATE"); return true; }
       if(!MultiFindPosition(group.id, ticket, type, total, entry, sl, tp))
         { group.cost_frozen = true; return true; }
       group.first_direction = direction == ORDER_TYPE_BUY ? FIRST_BUY : FIRST_SELL;
       group.anchor_price = entry;
       group.last_entry = entry;
       group.linear_extreme = entry;
       group.first_lots = total;
       group.total_lots = total;
       group.grid_lots = total;
       MultiCostProtect(group, type);
       return true;
      }
    if(MultiCostLastStop(group) && !group.cost_frozen
       && group.reversal_count < g_gui_applied_config.max_reversals)
      {
       MqlTick tick;
       string reason = "";
       const bool fresh = CostQuoteAllowed(group.stop_points, tick, reason)
          && tick.time_msc >= group.cost_stop_msc
          && tick.time_msc - group.cost_stop_msc <= g_gui_applied_config.cost_max_quote_age_ms;
       if(fresh && group.total_lots > 0.0)
         {
          const double old_lots = group.total_lots;
          group.cumulative_loss_lots += old_lots;
          group.previous_grid_lots = group.grid_lots;
          group.reversal_count++;
          group.cycle_index = (group.cycle_index + 1) % CycleLength(group.cycle_mode);
          const long direction = MultiSequenceDirection(group, group.cycle_index);
          const double lots = MultiNextGroupLotsAfterStopRaw(group, old_lots);
          group.anchor_price = 0.0;
          group.last_entry = 0.0;
          group.linear_extreme = 0.0;
          group.grid_filled_mask = 0;
          group.favorable_grid_filled_mask = 0;
          group.grid_lots = VolumeNormalize(group.grid_lots * g_gui_applied_config.grid_lot_multiplier);
          const double trigger = group.cost_stop_price;
          group.cost_consumed_stop_deal = group.cost_stop_deal;
          group.cost_stop_msc = 0;
          group.dirty = true;
          MultiSaveGroup(group);
          if(MultiCostSend(group, direction, lots, trigger, false)) return true;
          if(group.request_in_flight) return true;
          MultiCostEnd(group, "PASSIVE_SL_GATE");
          return true;
         }
       PrintFormat("[MULTI_COST_PASSIVE_SL_GATE][GROUP=%d][REASON=%s]", group.id,
                   fresh ? "DISTANCE_OR_VOLUME" : reason);
       MultiCostEnd(group, "PASSIVE_SL_GATE");
       return true;
      }
    MultiCostEnd(group, group.cost_stop_msc > 0 ? "PASSIVE_SL" : "EXTERNAL_CLOSE");
    return true;
   }

bool CostMarginAllowed(const long direction, const double volume,
                       const double worst_price, string &reason)
   {
    double required = 0.0;
    if(!OrderCalcMargin((ENUM_ORDER_TYPE)direction, _Symbol, volume,
                        worst_price, required)
       || !MathIsValidNumber(required) || required < 0.0)
      { reason = "MARGIN_CALC_FAILED"; return false; }
    if(required > AccountInfoDouble(ACCOUNT_MARGIN_FREE))
      { reason = "MARGIN_LIMIT"; return false; }
    return true;
   }

bool MultiCostTryOpenCandleGroup()
   {
    if(篮子数量 == 2 && MultiHasActiveGroups()) return false;
    if(!GuiAllowsInitialEntry() || !IsInitialEntryAllowed()) return false;
    double high = 0.0, low = 0.0;
    int range = 0;
    if(!GetPreviousCandleRange(high, low, range)) return false;
    const datetime bar = iTime(_Symbol, _Period, 0);
    if(bar <= 0 || (g_gui_applied_config.candle_order_mode == KORDER_ONCE_PER_BAR
       && bar == g_multi_last_trigger_bar)) return false;
    if(g_gui_applied_config.candle_order_mode != KORDER_ONCE_PER_BAR)
      {
       long direction = ORDER_TYPE_BUY;
       if(!GetBreakoutDirection(high, low, direction)) return false;
      }
    const int index = ArraySize(g_multi_groups);
    if(ArrayResize(g_multi_groups, index + 1) != index + 1) return false;
    MultiGroupState group;
    MultiResetState(group, g_multi_next_id++);
    group.cost_active = true;
    group.cost_start = TimeCurrent() - 1;
    group.cost_target = g_gui_applied_config.cost_target_rr > 0.0
       ? g_gui_applied_config.cost_target_rr : 1.0;
    group.cost_risk = 0.0;
    group.cost_bar = bar;
    group.stop_points = range;
    group.take_profit_points = range;
    group.cycle_mode = g_gui_applied_config.cycle_mode;
    group.signal_bar_time = bar;
    g_multi_groups[index] = group;
    MultiSaveGroup(g_multi_groups[index]);
    if(g_gui_applied_config.candle_order_mode == KORDER_ONCE_PER_BAR)
      {
       g_multi_groups[index].cost_high = high;
       g_multi_groups[index].cost_low = low;
       MultiSaveGroup(g_multi_groups[index]);
       MarkMultiCandleTriggerBar();
       return true;
      }
    long direction = ORDER_TYPE_BUY;
    if(!GetBreakoutDirection(high, low, direction)) return true;
    if(篮子数量 == 2)
      {
       ArrayResize(g_multi_groups, index);
       return MultiStartResolvedPair(direction, range, range,
                                     g_gui_applied_config.initial_lots);
      }
    const double trigger = direction == ORDER_TYPE_BUY ? high : low;
    if(!MultiCostSend(g_multi_groups[index], direction,
                      g_gui_applied_config.initial_lots, trigger, false))
      {
       if(!g_multi_groups[index].request_in_flight) MultiRemoveGroup(index);
       return false;
      }
    ulong ticket = 0;
    long type = POSITION_TYPE_BUY;
    double total = 0.0, entry = 0.0, sl = 0.0, tp = 0.0;
    if(MultiFindPosition(group.id, ticket, type, total, entry, sl, tp))
      {
       g_multi_groups[index].first_direction = direction == ORDER_TYPE_BUY ? FIRST_BUY : FIRST_SELL;
       g_multi_groups[index].anchor_price = entry;
       g_multi_groups[index].last_entry = entry;
       g_multi_groups[index].linear_extreme = entry;
       g_multi_groups[index].first_lots = total;
       g_multi_groups[index].total_lots = total;
       g_multi_groups[index].grid_lots = total;
       MultiCostProtect(g_multi_groups[index], type);
      }
    MultiSaveGroup(g_multi_groups[index]);
    return true;
   }

void ManageMultipleCandleGroups()
  {
   if(GuiProcessPendingReset())
      return;
   bool closed_group = false;
   for(int index = ArraySize(g_multi_groups) - 1; index >= 0; index--)
     {
      const bool was_active = g_multi_groups[index].active;
      MultiGroupState before = g_multi_groups[index];
       if(g_multi_groups[index].cost_active)
          MultiCostManageGroup(g_multi_groups[index]);
       else
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
      if(g_reset_pending)
         return;
     }
   if(closed_group)
      return;
    if(g_gui_applied_config.distance_mode != DISTANCE_CANDLE_RANGE
       || g_gui_applied_config.candle_enable_multiple != 1)
       return;
    if(g_gui_applied_config.cost_mode)
       MultiCostTryOpenCandleGroup();
    else
       MultiTryOpenCandleGroup();
  }

bool MultiHasActiveGroups()
  {
   for(int index = 0; index < ArraySize(g_multi_groups); index++)
      if(g_multi_groups[index].active)
         return true;
   return false;
  }

int CountManagedPositions()
  {
   int count = 0;
   for(int index = 0; index < PositionsTotal(); index++)
      if(IsOurPosition(PositionGetTicket(index)))
         count++;
   return count;
  }

int CountManagedPendingOrders()
  {
   int count = 0;
   for(int index = 0; index < OrdersTotal(); index++)
     {
      const ulong ticket = OrderGetTicket(index);
      if(ticket != 0 && OrderGetString(ORDER_SYMBOL) == _Symbol
         && (ulong)OrderGetInteger(ORDER_MAGIC) == g_gui_applied_config.magic_number
         && IsReversePendingType(OrderGetInteger(ORDER_TYPE)))
         count++;
     }
   return count;
  }

int CountPausedGroups()
  {
   int count = g_strategy_state == STATE_PAUSED_TEMP ? 1 : 0;
   for(int index = 0; index < ArraySize(g_multi_groups); index++)
      if(g_multi_groups[index].active
         && g_multi_groups[index].state == STATE_PAUSED_TEMP)
         count++;
   return count;
  }

void EmitStrategyWatchdog()
  {
   const datetime now = TimeCurrent();
   if(now <= 0 || (g_last_watchdog_time > 0 && now - g_last_watchdog_time < 300))
      return;
   g_last_watchdog_time = now;
   PrintFormat("[WATCHDOG][EVENT=EA_ALIVE][STATE=%s][OpenPositions=%d] "
               "[PendingOrders=%d][PausedGroups=%d][LastTradeTime=%s] "
               "[LastSignalTime=%s][RequestInFlight=%s][LastError=%d]",
               StrategyStateText(g_strategy_state), CountManagedPositions(),
               CountManagedPendingOrders(), CountPausedGroups(),
               TimeToString(g_last_trade_time, TIME_DATE|TIME_MINUTES),
               TimeToString(g_signal_bar_time, TIME_DATE|TIME_MINUTES),
               g_trade_request_in_flight ? "true" : "false", GetLastError());
  }

string GuiObjectPrefix()
  {
   const long account_tail = AccountInfoInteger(ACCOUNT_LOGIN) % 10000;
   const string symbol_part = StringSubstr(SanitizeExecutionLockPart(_Symbol), 0, 4);
   const long magic_tail = (long)(g_gui_applied_config.magic_number % 1000000);
   return "NMR.g." + IntegerToString(account_tail) + "." + symbol_part + "."
          + IntegerToString(magic_tail) + ".";
  }

string GuiLegacyObjectPrefix()
  {
   return "NMR.gui." + SanitizeExecutionLockPart(AccountInfoString(ACCOUNT_SERVER))
          + "." + IntegerToString((long)AccountInfoInteger(ACCOUNT_LOGIN))
          + "." + SanitizeExecutionLockPart(_Symbol) + "."
          + IntegerToString((long)g_gui_applied_config.magic_number) + ".";
  }

color GuiColorBackground() { return C'7,11,18'; }
color GuiColorPanel()      { return C'16,26,42'; }
color GuiColorSurface()    { return C'22,36,58'; }
color GuiColorInput()      { return C'11,21,37'; }
color GuiColorBorder()     { return C'59,90,126'; }
color GuiColorText()       { return C'237,245,255'; }
color GuiColorMuted()      { return C'142,168,196'; }
color GuiColorPrimary()    { return C'40,118,240'; }
color GuiColorSuccess()    { return C'54,217,138'; }
color GuiColorWarning()    { return C'231,189,103'; }
color GuiColorDanger()     { return C'119,31,39'; }

void GuiSetObjectBase(const string name, const int x, const int y,
                      const int width, const int height)
  {
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE, width);
   ObjectSetInteger(0, name, OBJPROP_YSIZE, height);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_SELECTED, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   ObjectSetInteger(0, name, OBJPROP_BACK, false);
  }

bool GuiCreatePanel(const string name, const int x, const int y,
                    const int width, const int height, const color background,
                    const color border)
  {
   if(!ObjectCreate(0, name, OBJ_RECTANGLE_LABEL, 0, 0, 0))
      return false;
   GuiSetObjectBase(name, x, y, width, height);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, background);
   ObjectSetInteger(0, name, OBJPROP_BORDER_COLOR, border);
   ObjectSetInteger(0, name, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, name, OBJPROP_ZORDER, 10);
   return true;
  }

bool GuiCreateText(const string name, const string text, const int x, const int y,
                   const int width, const int height, const color text_color,
                   const int font_size, const string font = "Arial")
  {
   if(!ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0))
      return false;
   GuiSetObjectBase(name, x, y, width, height);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetString(0, name, OBJPROP_FONT, font);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, font_size);
   ObjectSetInteger(0, name, OBJPROP_COLOR, text_color);
   ObjectSetInteger(0, name, OBJPROP_ANCHOR, ANCHOR_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_ZORDER, 500);
   return true;
  }

bool GuiCreateButton(const string name, const string text, const int x, const int y,
                     const int width, const int height, const color background,
                     const color text_color)
  {
   if(!ObjectCreate(0, name, OBJ_BUTTON, 0, 0, 0))
      return false;
   GuiSetObjectBase(name, x, y, width, height);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetString(0, name, OBJPROP_FONT, "Arial");
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 10);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, background);
   ObjectSetInteger(0, name, OBJPROP_COLOR, text_color);
   ObjectSetInteger(0, name, OBJPROP_BORDER_COLOR, GuiColorBorder());
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, true);
   ObjectSetInteger(0, name, OBJPROP_SELECTED, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, false);
   ObjectSetInteger(0, name, OBJPROP_ZORDER, 1000);
   return true;
  }

bool GuiCreateEdit(const string name, const string text, const int x, const int y,
                   const int width, const int height)
  {
   if(!ObjectCreate(0, name, OBJ_EDIT, 0, 0, 0))
      return false;
   GuiSetObjectBase(name, x, y, width, height);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, true);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, false);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetString(0, name, OBJPROP_FONT, "Arial");
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 10);
   ObjectSetInteger(0, name, OBJPROP_ALIGN, ALIGN_LEFT);
   ObjectSetInteger(0, name, OBJPROP_READONLY, false);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, GuiColorInput());
   ObjectSetInteger(0, name, OBJPROP_COLOR, GuiColorText());
   ObjectSetInteger(0, name, OBJPROP_BORDER_COLOR, GuiColorBorder());
   ObjectSetInteger(0, name, OBJPROP_ZORDER, 1000);
   return true;
  }

bool GuiCreateDropdownArrow(const string name, const int x, const int y,
                            const int width, const int height)
  {
   if(!GuiCreateButton(name, "▼", x, y, width, height,
                       GuiColorInput(), GuiColorText()))
      return false;
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, GUI_DROPDOWN_ARROW_FONT_SIZE);
   ObjectSetInteger(0, name, OBJPROP_ZORDER, 1100);
   return true;
  }

bool GuiTrackCreateResult(const bool created, const string object_name)
  {
   if(created)
      return true;
   if(StringLen(g_gui_render_error) == 0)
     {
      g_gui_render_error = object_name;
      g_gui_render_error_code = GetLastError();
     }
   return false;
  }

string GuiPageText(const GuiPage page)
  {
   switch(page)
     {
      case GUI_PAGE_OPENING:  return "开仓";
      case GUI_PAGE_DISTANCE: return "距离";
      case GUI_PAGE_GRID:     return "网格";
      case GUI_PAGE_RISK:     return "风控";
     default:                return "总览";
    }
  }

string GuiSymbolPeriodText()
  {
   string period = EnumToString(_Period);
   StringReplace(period, "PERIOD_", "");
   return _Symbol + " · " + period;
  }

string GuiRunStateText()
  {
   switch(g_gui_run_state)
     {
      case GUI_RUN_PAUSED_INITIAL: return "暂停开首单";
      case GUI_RUN_CLEANING:       return "清理中";
      case GUI_RUN_ERROR:          return "错误";
      default:                     return "运行中";
     }
  }

string GuiFirstDirectionText(const FirstDirection value)
  {
   return value == FIRST_SELL ? "做空" : "做多";
  }

string GuiFirstDirectionModeText(const FirstDirectionMode value)
  {
   return value == FIRST_DIRECTION_BOLLINGER ? "布林带判断" : "预设方向";
  }

string GuiCycleModeText(const CycleMode value)
  {
   if(value == CYCLE_MODE_2)
      return "模式2";
   if(value == CYCLE_MODE_3)
      return "模式3";
   if(value == CYCLE_MODE_4)
      return "模式4";
   return "模式1";
  }

string GuiDistanceModeText(const DistanceMode value)
  {
   if(value == DISTANCE_CANDLE_RANGE)
      return "K线高度";
   if(value == DISTANCE_AVERAGE_CANDLE_RANGE)
      return "平均K线高度";
   if(value == DISTANCE_LONG_CANDLE)
      return "长K线市价";
   if(value == DISTANCE_BOLLINGER_RANGE)
      return "布林带区间";
   return "固定距离";
  }

string GuiDistanceSummaryText(const GuiConfig &config)
  {
   if(config.distance_mode == DISTANCE_BOLLINGER_RANGE)
      return "止损/止盈：布林带宽度/4";
   if(config.distance_mode == DISTANCE_AVERAGE_CANDLE_RANGE)
      return "均高N=" + IntegerToString(config.average_candle_count)
             + " ×止损" + DoubleToString(config.average_stop_multiplier, 2)
             + " / 止盈" + DoubleToString(config.average_take_profit_multiplier, 2);
   return IntegerToString(config.stop_loss_distance_points) + "/"
          + IntegerToString(config.take_profit_distance_points);
  }

string GuiOperationWindowText(const string start_time, const string end_time)
  {
   if(ParseTimeMinutes(start_time) == 0 && ParseTimeMinutes(end_time) == 0)
      return "关闭";
   return start_time + " - " + end_time;
  }

string GuiScheduleSummaryText(const GuiConfig &config)
  {
   return GuiOperationWindowText(config.start_time, config.end_time) + " / "
          + GuiOperationWindowText(config.start_time_2, config.end_time_2) + " / "
          + GuiOperationWindowText(config.start_time_3, config.end_time_3);
  }

string GuiOrderTypeText(const OrderTypeMode value)
  {
   return value == ORDERTYPE_REVERSE ? "逆向" : "正向";
  }

string GuiCandleOrderModeText(const CandleOrderMode value)
  {
   return value == KORDER_REPEAT_PER_BAR ? "每根重复" : "每根一次";
  }

string GuiMultipleText(const int value)
  {
   return value == 1 ? "多组" : "单组";
  }

string GuiTakeProfitModeText(const TakeProfitMode value)
  {
   return value == TAKE_PROFIT_LINEAR ? "线性移动" : "网格移动";
  }

bool GuiIsEditableDropdownKey(const string key)
   {
   return key == "initial_lots" || key == "initial_lots_multiplier"
          || key == "first_order_mult"
          || key == "stop_loss_distance_points"
          || key == "take_profit_distance_points"
          || key == "candle_min_range_points"
          || key == "candle_max_range_points"
          || key == "average_candle_count"
          || key == "average_stop_multiplier"
          || key == "average_take_profit_multiplier"
          || key == "bollinger_period"
          || key == "bollinger_deviation"
          || key == "grid_count" || key == "grid_lot_multiplier"
          || key == "max_reversals" || key == "start_time"
          || key == "end_time" || key == "start_time_2"
          || key == "end_time_2" || key == "start_time_3"
          || key == "end_time_3";
  }

int GuiEditableDropdownOptionCount(const string key)
  {
   if(key == "initial_lots")
      return 10;
   if(key == "initial_lots_multiplier")
      return 5;
   if(key == "first_order_mult")
      return 5;
   if(key == "stop_loss_distance_points"
      || key == "take_profit_distance_points"
      || key == "candle_min_range_points"
      || key == "candle_max_range_points")
      return 11;
   if(key == "average_candle_count")
      return 6;
   if(key == "average_stop_multiplier" || key == "average_take_profit_multiplier")
      return 6;
   if(key == "bollinger_period" || key == "bollinger_deviation")
      return 6;
   if(key == "grid_count")
      return 10;
   if(key == "grid_lot_multiplier")
      return 9;
   if(key == "max_reversals")
      return 19;
   if(key == "start_time" || key == "end_time"
      || key == "start_time_2" || key == "end_time_2"
      || key == "start_time_3" || key == "end_time_3")
      return 24;
   return 0;
  }

string GuiEditableDropdownOptionText(const string key, const int index)
  {
   if(key == "initial_lots")
     {
      if(index == 0) return "0.01";
      if(index == 1) return "0.02";
      if(index == 2) return "0.03";
      if(index == 3) return "0.04";
      if(index == 4) return "0.05";
      if(index == 5) return "0.1";
      if(index == 6) return "0.2";
      if(index == 7) return "0.3";
      if(index == 8) return "0.4";
      if(index == 9) return "0.5";
     }
   if(key == "initial_lots_multiplier")
     {
      if(index == 0) return "1.0";
      if(index == 1) return "1.2";
      if(index == 2) return "1.3";
      if(index == 3) return "1.5";
      if(index == 4) return "2.0";
      }
   if(key == "first_order_mult")
      {
       if(index == 0) return "1.0";
       if(index == 1) return "1.5";
       if(index == 2) return "2.0";
       if(index == 3) return "3.0";
       if(index == 4) return "4.0";
      }
   if(key == "average_candle_count")
     {
      if(index == 0) return "5";
      if(index == 1) return "10";
      if(index == 2) return "20";
      if(index == 3) return "30";
      if(index == 4) return "50";
      if(index == 5) return "100";
     }
   if(key == "average_stop_multiplier" || key == "average_take_profit_multiplier")
     {
      if(index == 0) return "0.5";
      if(index == 1) return "1.0";
      if(index == 2) return "1.5";
      if(index == 3) return "2.0";
      if(index == 4) return "3.0";
      if(index == 5) return "4.0";
     }
   if(key == "bollinger_period")
     {
      if(index == 0) return "5";
      if(index == 1) return "10";
      if(index == 2) return "20";
      if(index == 3) return "30";
      if(index == 4) return "50";
      if(index == 5) return "100";
     }
   if(key == "bollinger_deviation")
     {
      if(index == 0) return "1.0";
      if(index == 1) return "1.5";
      if(index == 2) return "2.0";
      if(index == 3) return "2.5";
      if(index == 4) return "3.0";
      if(index == 5) return "4.0";
     }
   if(key == "stop_loss_distance_points"
      || key == "take_profit_distance_points"
      || key == "candle_min_range_points"
      || key == "candle_max_range_points")
     {
      if(index >= 0 && index < 10)
         return IntegerToString((index + 1) * 100);
      if(index == 10)
         return "1500";
     }
   if(key == "grid_count" && index >= 0 && index < 10)
      return IntegerToString(index + 1);
   if(key == "grid_lot_multiplier" && index >= 0 && index < 9)
     {
      if(index == 8)
         return "5.0";
      return DoubleToString(1.0 + index * 0.5, 1);
     }
   if(key == "max_reversals" && index >= 0 && index < 19)
      return IntegerToString(index + 2);
   if(key == "start_time" || key == "end_time"
      || key == "start_time_2" || key == "end_time_2"
      || key == "start_time_3" || key == "end_time_3")
     {
      for(int hour = 0; hour < 24; hour++)
        {
         if(index == hour)
            return StringFormat("%02d:00", hour);
        }
     }
   return "";
  }

int GuiDropdownOptionCount(const string key)
  {
   if(key == "first_direction" || key == "first_direction_mode"
       || key == "distance_mode" || key == "order_type"
       || key == "candle_order_mode" || key == "candle_enable_multiple"
       || key == "take_profit_mode" || key == "first_order_lot_type"
        || key == "favorable_grid_enable" || key == "dynamic_stop_loss_enable")
      return key == "distance_mode" ? 5 : 2;
   if(key == "cycle_mode")
      return 4;
   return 0;
  }

string GuiDropdownOptionText(const string key, const int index)
  {
   if(key == "first_direction")
      return index == 1 ? "做空" : "做多";
   if(key == "first_direction_mode")
      return index == 1 ? "布林带判断" : "预设方向";
   if(key == "cycle_mode")
     {
      if(index == 1)
         return "模式2";
      if(index == 2)
         return "模式3";
      if(index == 3)
         return "模式4";
      return "模式1";
     }
   if(key == "distance_mode")
     {
      if(index == 1) return "K线高度";
      if(index == 2) return "平均K线高度";
      if(index == 3) return "长K线市价";
      if(index == 4) return "布林带区间";
      return "固定距离";
     }
   if(key == "order_type")
      return index == 1 ? "逆向" : "正向";
   if(key == "candle_order_mode")
      return index == 1 ? "每根重复" : "每根一次";
   if(key == "candle_enable_multiple")
      return index == 1 ? "多组" : "单组";
   if(key == "take_profit_mode")
       return index == 1 ? "线性移动" : "网格移动";
   if(key == "first_order_lot_type")
       return index == 1 ? "上一组首单" : "累计组总手数";
    if(key == "favorable_grid_enable")
       return index == 1 ? "开启" : "关闭";
    if(key == "dynamic_stop_loss_enable")
       return index == 1 ? "开启" : "关闭";
   return "";
  }

int GuiDropdownValueIndex(const string key)
  {
   if(key == "first_direction")
      return g_gui_draft_config.first_direction == FIRST_SELL ? 1 : 0;
   if(key == "first_direction_mode")
      return g_gui_draft_config.first_direction_mode == FIRST_DIRECTION_BOLLINGER ? 1 : 0;
   if(key == "cycle_mode")
      return (int)g_gui_draft_config.cycle_mode;
   if(key == "distance_mode")
      return (int)g_gui_draft_config.distance_mode;
   if(key == "order_type")
      return g_gui_draft_config.order_type == ORDERTYPE_REVERSE ? 1 : 0;
   if(key == "candle_order_mode")
      return g_gui_draft_config.candle_order_mode == KORDER_REPEAT_PER_BAR ? 1 : 0;
   if(key == "candle_enable_multiple")
      return g_gui_draft_config.candle_enable_multiple == 1 ? 1 : 0;
   if(key == "take_profit_mode")
       return g_gui_draft_config.take_profit_mode == TAKE_PROFIT_LINEAR ? 1 : 0;
   if(key == "first_order_lot_type")
       return g_gui_draft_config.first_order_lot_type == 2 ? 1 : 0;
    if(key == "favorable_grid_enable")
       return g_gui_draft_config.favorable_grid_enable == 1 ? 1 : 0;
    if(key == "dynamic_stop_loss_enable")
       return g_gui_draft_config.dynamic_stop_loss_enable == 1 ? 1 : 0;
   return -1;
  }

bool GuiSetDropdownValue(const string key, const int index)
  {
   if(index < 0 || index >= GuiDropdownOptionCount(key))
      return false;
   if(key == "first_direction")
      g_gui_draft_config.first_direction = index == 1 ? FIRST_SELL : FIRST_BUY;
   else if(key == "first_direction_mode")
      g_gui_draft_config.first_direction_mode = index == 1
                                                ? FIRST_DIRECTION_BOLLINGER
                                                : FIRST_DIRECTION_PRESET;
   else if(key == "cycle_mode")
      g_gui_draft_config.cycle_mode = (CycleMode)index;
   else if(key == "distance_mode")
      g_gui_draft_config.distance_mode = (DistanceMode)index;
   else if(key == "order_type")
      g_gui_draft_config.order_type = index == 1 ? ORDERTYPE_REVERSE : ORDERTYPE_FORWARD;
   else if(key == "candle_order_mode")
      g_gui_draft_config.candle_order_mode = index == 1 ? KORDER_REPEAT_PER_BAR : KORDER_ONCE_PER_BAR;
   else if(key == "candle_enable_multiple")
      g_gui_draft_config.candle_enable_multiple = index == 1 ? 1 : 0;
   else if(key == "take_profit_mode")
       g_gui_draft_config.take_profit_mode = index == 1 ? TAKE_PROFIT_LINEAR : TAKE_PROFIT_GRID;
   else if(key == "first_order_lot_type")
       g_gui_draft_config.first_order_lot_type = index == 1 ? 2 : 1;
    else if(key == "favorable_grid_enable")
       g_gui_draft_config.favorable_grid_enable = index == 1 ? 1 : 0;
   else if(key == "dynamic_stop_loss_enable")
       g_gui_draft_config.dynamic_stop_loss_enable = index == 1 ? 1 : 0;
   else
      return false;
   return true;
  }

int GuiAnyDropdownOptionCount(const string key)
  {
   const int editable_count = GuiEditableDropdownOptionCount(key);
   if(editable_count > 0)
      return editable_count;
   return GuiDropdownOptionCount(key);
  }

string GuiAnyDropdownOptionText(const string key, const int index)
  {
   if(GuiIsEditableDropdownKey(key))
      return GuiEditableDropdownOptionText(key, index);
   return GuiDropdownOptionText(key, index);
  }

int GuiAnyDropdownValueIndex(const string key)
  {
   if(!GuiIsEditableDropdownKey(key))
      return GuiDropdownValueIndex(key);
   const int option_count = GuiEditableDropdownOptionCount(key);
   const bool time_value = key == "start_time" || key == "end_time"
                           || key == "start_time_2" || key == "end_time_2"
                           || key == "start_time_3" || key == "end_time_3";
   string current = "";
   if(key == "initial_lots")
      current = DoubleToString(g_gui_draft_config.initial_lots, 8);
   else if(key == "initial_lots_multiplier")
       current = DoubleToString(g_gui_draft_config.initial_lots_multiplier, 8);
   else if(key == "first_order_mult")
       current = DoubleToString(g_gui_draft_config.first_order_mult, 8);
   else if(key == "grid_count")
      current = IntegerToString(g_gui_draft_config.grid_count);
   else if(key == "grid_lot_multiplier")
      current = DoubleToString(g_gui_draft_config.grid_lot_multiplier, 8);
   else if(key == "stop_loss_distance_points")
      current = IntegerToString(g_gui_draft_config.stop_loss_distance_points);
   else if(key == "take_profit_distance_points")
      current = IntegerToString(g_gui_draft_config.take_profit_distance_points);
   else if(key == "candle_min_range_points")
      current = IntegerToString(g_gui_draft_config.candle_min_range_points);
   else if(key == "candle_max_range_points")
      current = IntegerToString(g_gui_draft_config.candle_max_range_points);
   else if(key == "average_candle_count")
      current = IntegerToString(g_gui_draft_config.average_candle_count);
   else if(key == "average_stop_multiplier")
      current = DoubleToString(g_gui_draft_config.average_stop_multiplier, 8);
   else if(key == "average_take_profit_multiplier")
      current = DoubleToString(g_gui_draft_config.average_take_profit_multiplier, 8);
   else if(key == "bollinger_period")
      current = IntegerToString(g_gui_draft_config.bollinger_period);
   else if(key == "bollinger_deviation")
      current = DoubleToString(g_gui_draft_config.bollinger_deviation, 8);
   else if(key == "max_reversals")
      current = IntegerToString(g_gui_draft_config.max_reversals);
   else if(key == "start_time")
      current = g_gui_draft_config.start_time;
   else if(key == "end_time")
      current = g_gui_draft_config.end_time;
   else if(key == "start_time_2")
      current = g_gui_draft_config.start_time_2;
   else if(key == "end_time_2")
      current = g_gui_draft_config.end_time_2;
   else if(key == "start_time_3")
      current = g_gui_draft_config.start_time_3;
   else if(key == "end_time_3")
      current = g_gui_draft_config.end_time_3;
   for(int index = 0; index < option_count; index++)
     {
      const string option = GuiEditableDropdownOptionText(key, index);
      if(time_value && option == current)
         return index;
      if(!time_value && MathAbs(StringToDouble(option) - StringToDouble(current)) <= 1e-8)
         return index;
     }
   return -1;
  }

bool GuiSetAnyDropdownValue(const string key, const int index)
  {
   if(index < 0 || index >= GuiAnyDropdownOptionCount(key))
      return false;
   if(!GuiIsEditableDropdownKey(key))
      return GuiSetDropdownValue(key, index);
   const string value = GuiEditableDropdownOptionText(key, index);
   if(key == "initial_lots")
      g_gui_draft_config.initial_lots = StringToDouble(value);
   else if(key == "initial_lots_multiplier")
       g_gui_draft_config.initial_lots_multiplier = StringToDouble(value);
   else if(key == "first_order_mult")
       g_gui_draft_config.first_order_mult = StringToDouble(value);
   else if(key == "stop_loss_distance_points")
      g_gui_draft_config.stop_loss_distance_points = (int)StringToInteger(value);
   else if(key == "take_profit_distance_points")
      g_gui_draft_config.take_profit_distance_points = (int)StringToInteger(value);
   else if(key == "candle_min_range_points")
      g_gui_draft_config.candle_min_range_points = (int)StringToInteger(value);
   else if(key == "candle_max_range_points")
      g_gui_draft_config.candle_max_range_points = (int)StringToInteger(value);
   else if(key == "average_candle_count")
      g_gui_draft_config.average_candle_count = (int)StringToInteger(value);
   else if(key == "average_stop_multiplier")
      g_gui_draft_config.average_stop_multiplier = StringToDouble(value);
   else if(key == "average_take_profit_multiplier")
      g_gui_draft_config.average_take_profit_multiplier = StringToDouble(value);
   else if(key == "bollinger_period")
      g_gui_draft_config.bollinger_period = (int)StringToInteger(value);
   else if(key == "bollinger_deviation")
      g_gui_draft_config.bollinger_deviation = StringToDouble(value);
   else if(key == "grid_count")
      g_gui_draft_config.grid_count = (int)StringToInteger(value);
   else if(key == "grid_lot_multiplier")
      g_gui_draft_config.grid_lot_multiplier = StringToDouble(value);
   else if(key == "max_reversals")
      g_gui_draft_config.max_reversals = (int)StringToInteger(value);
   else if(key == "start_time")
      g_gui_draft_config.start_time = value;
   else if(key == "end_time")
      g_gui_draft_config.end_time = value;
   else if(key == "start_time_2")
      g_gui_draft_config.start_time_2 = value;
   else if(key == "end_time_2")
      g_gui_draft_config.end_time_2 = value;
   else if(key == "start_time_3")
      g_gui_draft_config.start_time_3 = value;
   else if(key == "end_time_3")
      g_gui_draft_config.end_time_3 = value;
   else
      return false;
   return true;
  }

int GuiDropdownOptionColumns(const string key)
  {
   if(key == "start_time" || key == "end_time"
      || key == "start_time_2" || key == "end_time_2"
      || key == "start_time_3" || key == "end_time_3"
      || key == "max_reversals")
      return 2;
   return 1;
  }

void GuiDropdownOptionGeometry(const string key, const int field_x, const int field_y,
                               const int index, int &option_x, int &option_y,
                               int &option_width)
  {
   const int columns = GuiDropdownOptionColumns(key);
   option_width = GUI_FIELD_WIDTH / columns;
   option_x = field_x + (index % columns) * option_width;
   option_y = field_y + GUI_FIELD_HEIGHT + (index / columns) * GUI_FIELD_HEIGHT;
  }

bool GuiCreateDropdownOption(const string name, const string text, const int x, const int y,
                             const int width, const int height, const bool selected)
  {
   const bool created = GuiCreateButton(name, text, x, y, width, height,
                                        selected ? GuiColorPrimary() : GuiColorInput(),
                                        GuiColorText());
   if(created)
      ObjectSetInteger(0, name, OBJPROP_ZORDER, 2000);
   return created;
  }

bool GuiRenderDropdownField(const string key, const string label, const string value,
                            const int x, const int y, bool &ok)
  {
   const int value_x = x;
   const int value_y = y + 18;
   const int value_width = GUI_FIELD_WIDTH - GUI_DROPDOWN_ARROW_WIDTH;
   if(!GuiTrackCreateResult(GuiCreateText(g_gui_object_prefix + "field.label." + key,
                                          label, x, y, value_width, 16,
                                          GuiColorMuted(), 9),
                            "field.label." + key))
      ok = false;
   if(!GuiTrackCreateResult(GuiCreateButton(g_gui_object_prefix + "field." + key,
                                            value, value_x, value_y, value_width,
                                            GUI_FIELD_HEIGHT,
                                            GuiColorInput(), GuiColorText()),
                            "field." + key))
      ok = false;
   if(!GuiTrackCreateResult(GuiCreateDropdownArrow(g_gui_object_prefix + "field.arrow." + key,
                                                   value_x + value_width, value_y,
                                                   GUI_DROPDOWN_ARROW_WIDTH,
                                                   GUI_FIELD_HEIGHT),
                            "field.arrow." + key))
      ok = false;
   return true;
  }

bool GuiRenderEditableDropdownField(const string key, const string label,
                                    const string value, const int x, const int y,
                                    bool &ok)
  {
   const int value_x = x;
   const int value_y = y + 18;
   const int edit_width = GUI_FIELD_WIDTH - GUI_DROPDOWN_ARROW_WIDTH;
   if(!GuiTrackCreateResult(GuiCreateText(g_gui_object_prefix + "field.label." + key,
                                          label, x, y, GUI_FIELD_WIDTH, 16,
                                          GuiColorMuted(), 9),
                            "field.label." + key))
      ok = false;
   if(!GuiTrackCreateResult(GuiCreateEdit(g_gui_object_prefix + "field." + key,
                                          value, value_x, value_y, edit_width,
                                          GUI_FIELD_HEIGHT),
                            "field." + key))
      ok = false;
   if(!GuiTrackCreateResult(GuiCreateDropdownArrow(g_gui_object_prefix + "field.arrow." + key,
                                                   value_x + edit_width, value_y,
                                                   GUI_DROPDOWN_ARROW_WIDTH,
                                                   GUI_FIELD_HEIGHT),
                            "field.arrow." + key))
      ok = false;
   return true;
  }

bool GuiDropdownFieldPosition(const string key, int &field_x, int &field_y)
  {
   const int left_x = GUI_CONTENT_X + GUI_CONTENT_PADDING;
   const int right_x = left_x + GUI_FIELD_WIDTH + GUI_FORM_GAP;
   const int first_y = 60 + 94 + 18;
   const int row_gap = 64;
   string keys[14];
   int field_count = 0;
   if(g_gui_page == GUI_PAGE_OPENING)
     {
      keys[0] = "first_direction";
      keys[1] = "first_direction_mode";
      keys[2] = "cycle_mode";
      keys[3] = "order_type";
      keys[4] = "candle_order_mode";
      keys[5] = "candle_enable_multiple";
      keys[6] = "initial_lots";
      keys[7] = "initial_lots_multiplier";
      keys[8] = "first_order_lot_type";
      keys[9] = "first_order_mult";
      keys[10] = "bollinger_period";
      keys[11] = "bollinger_deviation";
      field_count = 12;
     }
   else if(g_gui_page == GUI_PAGE_DISTANCE)
     {
      keys[0] = "distance_mode";
      keys[1] = "stop_loss_distance_points";
      keys[2] = "take_profit_distance_points";
      keys[3] = "candle_min_range_points";
      keys[4] = "candle_max_range_points";
      keys[5] = "take_profit_mode";
      field_count = 6;
     }
    else if(g_gui_page == GUI_PAGE_GRID)
      {
       keys[0] = "grid_count";
       keys[1] = "grid_lot_multiplier";
       keys[2] = "favorable_grid_enable";
       keys[3] = "dynamic_stop_loss_enable";
       field_count = 4;
      }
   else if(g_gui_page == GUI_PAGE_RISK)
     {
      keys[0] = "max_reversals";
      keys[1] = "start_time";
      keys[2] = "end_time";
      keys[3] = "start_time_2";
      keys[4] = "end_time_2";
      keys[5] = "start_time_3";
      keys[6] = "end_time_3";
      keys[7] = "magic_number";
      keys[8] = "order_comment";
      field_count = 9;
     }
   for(int index = 0; index < field_count; index++)
     {
      if(keys[index] != key)
         continue;
      field_x = (index % 2 == 0) ? left_x : right_x;
      field_y = first_y + (index / 2) * row_gap;
      return true;
     }
   return false;
  }

bool GuiRenderDropdownOverlay(bool &ok)
  {
   if(StringLen(g_gui_dropdown_key) == 0)
      return true;
   int field_x = 0;
   int field_y = 0;
   if(!GuiDropdownFieldPosition(g_gui_dropdown_key, field_x, field_y))
      return true;
   const int option_count = GuiAnyDropdownOptionCount(g_gui_dropdown_key);
   const int option_columns = GuiDropdownOptionColumns(g_gui_dropdown_key);
   const int option_rows = (option_count + option_columns - 1) / option_columns;
   if(!GuiTrackCreateResult(GuiCreatePanel(g_gui_object_prefix + "dropdown.panel."
                                            + g_gui_dropdown_key,
                                            field_x, field_y + GUI_FIELD_HEIGHT,
                                            GUI_FIELD_WIDTH, option_rows * GUI_FIELD_HEIGHT,
                                            GuiColorInput(), GuiColorBorder()),
                            "dropdown.panel." + g_gui_dropdown_key))
      ok = false;
   const int selected_index = GuiAnyDropdownValueIndex(g_gui_dropdown_key);
   for(int index = 0; index < option_count; index++)
     {
      const string option_name = g_gui_object_prefix + "dropdown." + g_gui_dropdown_key + "."
                                 + IntegerToString(index);
      int option_x = field_x;
      int option_y = field_y;
      int option_width = GUI_FIELD_WIDTH;
      GuiDropdownOptionGeometry(g_gui_dropdown_key, field_x, field_y, index,
                                option_x, option_y, option_width);
      if(!GuiTrackCreateResult(GuiCreateDropdownOption(option_name,
                                                       GuiAnyDropdownOptionText(g_gui_dropdown_key,
                                                                                 index),
                                                       option_x, option_y, option_width,
                                                       GUI_FIELD_HEIGHT,
                                                       index == selected_index),
                                "dropdown." + g_gui_dropdown_key + "."
                                + IntegerToString(index)))
         ok = false;
     }
   return ok;
  }

bool GuiRenderLabelValue(const string key, const string label, const string value,
                         const int x, const int y, const bool editable,
                         const bool button_value, bool &ok)
  {
   if(!GuiTrackCreateResult(GuiCreateText(g_gui_object_prefix + "field.label." + key,
                                          label, x, y, GUI_FIELD_WIDTH, 16,
                                          GuiColorMuted(), 9),
                            "field.label." + key))
      ok = false;
   const int value_x = x;
   const int value_y = y + 18;
   const int value_width = GUI_FIELD_WIDTH;
   bool created = false;
   if(editable)
      created = GuiCreateEdit(g_gui_object_prefix + "field." + key,
                              value, value_x, value_y, value_width, GUI_FIELD_HEIGHT);
   else if(button_value)
      created = GuiCreateButton(g_gui_object_prefix + "field." + key,
                                value, value_x, value_y, value_width, GUI_FIELD_HEIGHT,
                                GuiColorInput(), GuiColorText());
   else
      created = GuiCreateText(g_gui_object_prefix + "field." + key, value,
                              value_x + 8, value_y + 7, value_width - 8, 18,
                              GuiColorMuted(), 10);
   if(!GuiTrackCreateResult(created, "field." + key))
      ok = false;
   return created;
  }

bool GuiRenderEditField(const string key, const string label, const string value,
                        const int x, const int y, bool &ok)
  {
   return GuiRenderLabelValue(key, label, value, x, y, true, false, ok);
  }

bool GuiRenderEnumField(const string key, const string label, const string value,
                        const int x, const int y, bool &ok)
  {
   return GuiRenderDropdownField(key, label, value, x, y, ok);
  }

bool GuiRenderReadOnlyField(const string key, const string label, const string value,
                            const int x, const int y, bool &ok)
  {
   if(StringFind(key, "overview.") == 0)
      return GuiRenderCompactSummaryField(key, label, value, x, y, ok);
   return GuiRenderLabelValue(key, label, value, x, y, false, false, ok);
  }

bool GuiRenderCompactSummaryField(const string key, const string label, const string value,
                                  const int x, const int y, bool &ok)
  {
   if(!GuiTrackCreateResult(GuiCreateText(g_gui_object_prefix + "field.label." + key,
                                          label, x, y, 104, 18,
                                          GuiColorMuted(), 9),
                            "field.label." + key))
      ok = false;
   if(!GuiTrackCreateResult(GuiCreateText(g_gui_object_prefix + "field." + key, value,
                                          x + 108, y, GUI_FIELD_WIDTH - 108, 18,
                                          GuiColorText(), 9),
                            "field." + key))
      ok = false;
   return ok;
  }

void GuiRenderNotice(const int x, const int y, bool &ok)
  {
   if(!GuiTrackCreateResult(GuiCreateText(g_gui_object_prefix + "notice", g_gui_notice,
                                          x, y, 252, 30,
                                          g_gui_run_state == GUI_RUN_ERROR
                                          ? C'248,113,113' : GuiColorSuccess(), 9),
                            "notice"))
      ok = false;
  }

void GuiRefreshNoticeObject()
  {
   const string notice_name = g_gui_object_prefix + "notice";
   if(ObjectFind(0, notice_name) < 0)
      return;
   ObjectSetString(0, notice_name, OBJPROP_TEXT, g_gui_notice);
   ObjectSetInteger(0, notice_name, OBJPROP_COLOR,
                    g_gui_run_state == GUI_RUN_ERROR ? C'248,113,113' : GuiColorWarning());
   ChartRedraw(0);
  }

void GuiRenderMetricCard(const string key, const string label, const string value,
                         const int x, const int y, const int width, bool &ok)
  {
   if(!GuiTrackCreateResult(GuiCreatePanel(g_gui_object_prefix + "metric." + key,
                                            x, y, width, 56,
                                            GuiColorPanel(), GuiColorBorder()),
                            "metric." + key))
      ok = false;
   if(!GuiTrackCreateResult(GuiCreateText(g_gui_object_prefix + "metric.label." + key,
                                          label, x + 10, y + 8, width - 20, 14,
                                          GuiColorMuted(), 9),
                            "metric.label." + key))
      ok = false;
   if(!GuiTrackCreateResult(GuiCreateText(g_gui_object_prefix + "metric.value." + key,
                                          value, x + 10, y + 27, width - 20, 20,
                                          GuiColorText(), 12),
                            "metric.value." + key))
      ok = false;
  }

struct GuiSnapshot
  {
   int position_count;
   int pending_order_count;
   double floating_profit;
  };

void GuiCollectSnapshot(GuiSnapshot &snapshot)
  {
   snapshot.position_count = 0;
   snapshot.pending_order_count = 0;
   snapshot.floating_profit = 0.0;
   for(int index = 0; index < PositionsTotal(); index++)
     {
      const ulong ticket = PositionGetTicket(index);
      if(ticket == 0 || PositionGetString(POSITION_SYMBOL) != _Symbol
         || (ulong)PositionGetInteger(POSITION_MAGIC)
            != g_gui_applied_config.magic_number)
         continue;
      snapshot.position_count++;
      snapshot.floating_profit += PositionGetDouble(POSITION_PROFIT);
     }
   for(int index = 0; index < OrdersTotal(); index++)
     {
      const ulong ticket = OrderGetTicket(index);
      if(ticket == 0 || OrderGetString(ORDER_SYMBOL) != _Symbol
         || (ulong)OrderGetInteger(ORDER_MAGIC)
            != g_gui_applied_config.magic_number)
         continue;
      snapshot.pending_order_count++;
     }
  }

string GuiBuildSnapshot()
  {
   GuiSnapshot snapshot;
   GuiCollectSnapshot(snapshot);
   return IntegerToString((int)g_gui_page) + "|"
          + IntegerToString((int)g_gui_run_state) + "|"
          + (g_gui_full_window ? "1" : "0") + "|"
          + (g_gui_has_unapplied_changes ? "1" : "0") + "|"
          + (g_gui_close_confirm_open ? "1" : "0") + "|"
          + (HasManagedExposureForMagic(g_gui_applied_config.magic_number) ? "1" : "0") + "|"
          + IntegerToString(snapshot.position_count) + "|"
          + IntegerToString(snapshot.pending_order_count) + "|"
          + DoubleToString(snapshot.floating_profit, 2) + "|"
          + (g_had_position ? "1" : "0") + "|"
          + IntegerToString(g_cycle_index) + "|"
          + IntegerToString(g_reversal_count) + "|"
          + IntegerToString(g_grid_filled_levels) + "|"
          + IntegerToString(g_pending_index) + "|"
          + g_gui_notice;
  }

bool GuiRefreshOverviewText(const string suffix, const string value)
  {
   const string object_name = g_gui_object_prefix + suffix;
   if(ObjectFind(0, object_name) < 0)
      return false;
   return ObjectSetString(0, object_name, OBJPROP_TEXT, value);
  }

bool GuiRefreshOverviewData()
  {
   if(!g_gui_objects_created || !g_gui_full_window || g_gui_page != GUI_PAGE_OVERVIEW)
      return false;

   GuiSnapshot snapshot;
   GuiCollectSnapshot(snapshot);
   const string direction = g_had_position
                            ? (g_last_position_type == POSITION_TYPE_BUY ? "做多" : "做空")
                            : "无持仓";
   const string reversal = IntegerToString(g_reversal_count) + "/"
                           + IntegerToString(g_gui_applied_config.max_reversals);
   const string exposure = IntegerToString(snapshot.position_count) + " / "
                           + IntegerToString(snapshot.pending_order_count);
   const string order_group = (g_had_position || snapshot.pending_order_count > 0)
                              ? "第" + IntegerToString(g_cycle_index + 1) + "组"
                              : "无活跃订单组";
   const string cycle = "阶段" + IntegerToString(g_cycle_index + 1) + "/"
                        + IntegerToString(CycleLength(g_active_cycle_mode))
                        + (g_pending_index >= 0
                           ? " · 待转" + IntegerToString(g_pending_index + 1)
                           : "");
   const string first_direction = GuiFirstDirectionText(g_active_first_direction == FIRST_SELL
                                                        ? FIRST_SELL : FIRST_BUY);
   const string stops = GuiDistanceSummaryText(g_gui_applied_config);
   const string schedule = GuiScheduleSummaryText(g_gui_applied_config);

   bool ok = true;
   ok = GuiRefreshOverviewText("title.status", "● " + GuiRunStateText()) && ok;
   ok = GuiRefreshOverviewText("title.dirty",
                               g_gui_has_unapplied_changes ? "· 未应用" : " ") && ok;
   ok = GuiRefreshOverviewText("mode.hint",
                               g_gui_has_unapplied_changes
                               ? "有未应用修改：点击应用参数后生效"
                               : (g_gui_display_mode == GUI_MODE_EXPERT
                                  ? "专家模式：显示完整运行状态与参数"
                                  : "简易模式：核心参数优先，全部参数仍可编辑")) && ok;
   ok = GuiRefreshOverviewText("metric.value.direction", direction) && ok;
   ok = GuiRefreshOverviewText("metric.value.reversal", reversal) && ok;
   ok = GuiRefreshOverviewText("metric.value.exposure", exposure) && ok;
   ok = GuiRefreshOverviewText("field.overview.state", GuiRunStateText()) && ok;
   ok = GuiRefreshOverviewText("field.overview.direction", first_direction) && ok;
   ok = GuiRefreshOverviewText("field.overview.order_group", order_group) && ok;
   ok = GuiRefreshOverviewText("field.overview.cycle", cycle) && ok;
   ok = GuiRefreshOverviewText("field.overview.positions",
                               IntegerToString(snapshot.position_count)) && ok;
   ok = GuiRefreshOverviewText("field.overview.orders",
                               IntegerToString(snapshot.pending_order_count)) && ok;
   ok = GuiRefreshOverviewText("field.overview.profit",
                               DoubleToString(snapshot.floating_profit, 2)) && ok;
   ok = GuiRefreshOverviewText("field.overview.reversal", reversal) && ok;
   ok = GuiRefreshOverviewText("field.overview.cycle_mode",
                               GuiCycleModeText(g_gui_applied_config.cycle_mode)) && ok;
   ok = GuiRefreshOverviewText("field.overview.distance_mode",
                               GuiDistanceModeText(g_gui_applied_config.distance_mode)) && ok;
   ok = GuiRefreshOverviewText("field.overview.order_type",
                               GuiOrderTypeText(g_gui_applied_config.order_type)) && ok;
   ok = GuiRefreshOverviewText("field.overview.initial_lots",
                               DoubleToString(g_gui_applied_config.initial_lots, 8)) && ok;
   ok = GuiRefreshOverviewText("field.overview.initial_lots_multiplier",
                               DoubleToString(g_gui_applied_config.initial_lots_multiplier, 8)) && ok;
   ok = GuiRefreshOverviewText("field.overview.grid_count",
                               IntegerToString(g_gui_applied_config.grid_count)) && ok;
   ok = GuiRefreshOverviewText("field.overview.grid_lot_multiplier",
                               DoubleToString(g_gui_applied_config.grid_lot_multiplier, 8)) && ok;
   ok = GuiRefreshOverviewText("field.overview.stops", stops) && ok;
   ok = GuiRefreshOverviewText("field.overview.take_profit_mode",
                               GuiTakeProfitModeText(g_gui_applied_config.take_profit_mode)) && ok;
   ok = GuiRefreshOverviewText("field.overview.schedule", schedule) && ok;
   ok = GuiRefreshOverviewText("field.overview.magic_number",
                               IntegerToString((long)g_gui_applied_config.magic_number)) && ok;
   ok = GuiRefreshOverviewText("field.overview.order_comment",
                               g_gui_applied_config.order_comment) && ok;
   ok = GuiRefreshOverviewText("notice", g_gui_notice) && ok;
   if(!ok)
      return false;
   ObjectSetInteger(0, g_gui_object_prefix + "title.status", OBJPROP_COLOR,
                    g_gui_run_state == GUI_RUN_ERROR ? C'248,113,113' : GuiColorSuccess());
   ObjectSetInteger(0, g_gui_object_prefix + "title.dirty", OBJPROP_COLOR, GuiColorWarning());
   ObjectSetInteger(0, g_gui_object_prefix + "mode.hint", OBJPROP_COLOR,
                    g_gui_has_unapplied_changes ? GuiColorWarning() : GuiColorMuted());
   ObjectSetInteger(0, g_gui_object_prefix + "notice", OBJPROP_COLOR,
                    g_gui_run_state == GUI_RUN_ERROR ? C'248,113,113' : GuiColorWarning());
   ChartRedraw(0);
   return true;
  }

void GuiMarkDirty()
  {
   g_gui_dirty = true;
  }

bool GuiAllowsInitialEntry()
  {
   return g_gui_run_state != GUI_RUN_PAUSED_INITIAL
          && g_gui_run_state != GUI_RUN_CLEANING;
  }

bool GuiProcessPendingReset()
  {
   if(g_reset_pending)
     {
      const bool complete = ProcessReset();
      g_gui_run_state = complete ? GUI_RUN_RUNNING : GUI_RUN_ERROR;
      g_gui_notice = complete ? "清理完成" : "清理失败：服务器操作未完成，将继续重试";
      GuiMarkDirty();
      return true;
     }
   if(g_gui_run_state == GUI_RUN_CLEANING)
     {
      if(!HasManagedExposureForMagic(g_gui_applied_config.magic_number))
        {
         g_gui_run_state = GUI_RUN_RUNNING;
         g_gui_notice = "清理完成";
        }
      else
         g_gui_notice = "清理中";
      GuiMarkDirty();
      return true;
     }
   return false;
  }

bool GuiRenderTitleBar()
  {
   bool ok = true;
   const int x = 18;
   const int y = 18;
   if(!GuiTrackCreateResult(GuiCreatePanel(g_gui_object_prefix + "title", x, y,
                                            GUI_WINDOW_WIDTH, GUI_TITLE_HEIGHT,
                                            GuiColorPanel(), GuiColorBorder()), "title"))
      ok = false;
   if(!GuiTrackCreateResult(GuiCreateText(g_gui_object_prefix + "title.text", "不管涨跌 EA",
                                          x + 14, y + 11, 160, 20, GuiColorText(), 11), "title.text"))
      ok = false;
   if(!GuiTrackCreateResult(GuiCreateText(g_gui_object_prefix + "title.context",
                                          GuiSymbolPeriodText(), x + 174, y + 12, 112, 18,
                                          GuiColorMuted(), 9), "title.context"))
      ok = false;
   if(!GuiTrackCreateResult(GuiCreateText(g_gui_object_prefix + "title.status",
                                          "● " + GuiRunStateText(), x + 292, y + 12, 110, 18,
                                          g_gui_run_state == GUI_RUN_ERROR ? C'248,113,113' : GuiColorSuccess(), 9),
                            "title.status"))
      ok = false;
   if(!GuiTrackCreateResult(GuiCreateText(g_gui_object_prefix + "title.dirty",
                                          g_gui_has_unapplied_changes ? "· 未应用" : " ",
                                          x + 570, y + 12, 90, 18,
                                          GuiColorWarning(), 9), "title.dirty"))
      ok = false;
   if(!GuiTrackCreateResult(GuiCreateButton(g_gui_object_prefix + "minimize", "—",
                                            x + GUI_WINDOW_WIDTH - 38, y + 7, 28, 28,
                                            GuiColorSurface(), GuiColorMuted()), "minimize"))
      ok = false;
   return ok;
  }

bool GuiRenderNavigation()
  {
   bool ok = true;
   const int x = 18;
   const int y = 60;
   if(!GuiTrackCreateResult(GuiCreatePanel(g_gui_object_prefix + "navigation", x, y,
                                            GUI_NAV_WIDTH, GUI_WINDOW_HEIGHT - GUI_TITLE_HEIGHT,
                                            GuiColorInput(), GuiColorBorder()), "navigation"))
      ok = false;
    const string pages[5] = {"总览  01", "开仓  12", "距离与止盈  06", "网格  03", "风控与时段  05"};
   for(int index = 0; index < 5; index++)
     {
      const GuiPage page = (GuiPage)index;
      const int item_y = y + 48 + index * 48;
      const bool selected = g_gui_page == page;
      if(selected)
        {
         if(!GuiTrackCreateResult(GuiCreatePanel(g_gui_object_prefix + "nav.bg." + IntegerToString(index),
                                                  x + 12, item_y - 4, GUI_NAV_WIDTH - 24, 36,
                                                  GuiColorPrimary(), GuiColorPrimary()),
                                  "nav.bg." + IntegerToString(index)))
            ok = false;
        }
      if(!GuiTrackCreateResult(GuiCreateButton(g_gui_object_prefix + "nav." + IntegerToString(index),
                                               pages[index], x + 12, item_y, GUI_NAV_WIDTH - 24, 28,
                                               selected ? GuiColorPrimary() : GuiColorInput(),
                                               GuiColorText()),
                               "nav." + IntegerToString(index)))
         ok = false;
     }
   return ok;
  }

bool GuiRenderCloseConfirmation(bool &ok)
  {
   const int x = 112;
   const int y = 152;
   if(!GuiTrackCreateResult(GuiCreatePanel(g_gui_object_prefix + "confirm.panel",
                                            x, y, 258, 154,
                                            GuiColorPanel(), GuiColorBorder()),
                            "confirm.panel"))
      ok = false;
   if(!GuiTrackCreateResult(GuiCreateText(g_gui_object_prefix + "confirm.title",
                                          "确认清理", x + 14, y + 14, 220, 20,
                                          GuiColorText(), 10), "confirm.title"))
      ok = false;
   if(!GuiTrackCreateResult(GuiCreateText(g_gui_object_prefix + "confirm.text",
                                          "将平仓并删除当前 EA 的全部挂单。\n此操作不可撤销。",
                                          x + 14, y + 44, 226, 40,
                                          GuiColorText(), 10), "confirm.text"))
      ok = false;
   if(!GuiTrackCreateResult(GuiCreateButton(g_gui_object_prefix + "confirm.cleanup",
                                            "确认清理", x + 14, y + 104, 104, 28,
                                            GuiColorDanger(), GuiColorText()), "confirm.cleanup"))
      ok = false;
   if(!GuiTrackCreateResult(GuiCreateButton(g_gui_object_prefix + "confirm.cancel",
                                            "取消", x + 130, y + 104, 104, 28,
                                            GuiColorSurface(), GuiColorText()), "confirm.cancel"))
      ok = false;
   return ok;
  }

bool GuiRenderContent()
  {
   bool ok = true;
   const int x = GUI_CONTENT_X;
   const int y = 60;
   if(!GuiTrackCreateResult(GuiCreatePanel(g_gui_object_prefix + "content", x, y,
                                            GUI_CONTENT_WIDTH,
                                            GUI_WINDOW_HEIGHT - GUI_TITLE_HEIGHT,
                                            GuiColorSurface(), GuiColorBorder()), "content"))
      ok = false;
   if(!GuiTrackCreateResult(GuiCreateText(g_gui_object_prefix + "content.page", "EA控制面板",
                                          x + GUI_CONTENT_PADDING, y + 14, 240, 22,
                                          GuiColorText(), 11), "content.page"))
      ok = false;
   if(!GuiTrackCreateResult(GuiCreateButton(g_gui_object_prefix + "mode.toggle",
                                            g_gui_display_mode == GUI_MODE_EXPERT ? "专家模式" : "简易模式",
                                            x + GUI_CONTENT_WIDTH - 112, y + 12, 92, 24,
                                            GuiColorInput(), GuiColorText()), "mode.toggle"))
      ok = false;
   const string mode_hint = g_gui_has_unapplied_changes
                            ? "有未应用修改：点击应用参数后生效"
                            : (g_gui_display_mode == GUI_MODE_EXPERT
                               ? "专家模式：显示完整运行状态与参数"
                               : "简易模式：核心参数优先，全部参数仍可编辑");
   const color mode_hint_color = g_gui_has_unapplied_changes
                                 ? GuiColorWarning() : GuiColorMuted();
   if(!GuiTrackCreateResult(GuiCreateText(g_gui_object_prefix + "mode.hint",
                                          mode_hint,
                                          x + GUI_CONTENT_PADDING, y + 36,
                                          GUI_CONTENT_WIDTH - GUI_CONTENT_PADDING * 2, 16,
                                          mode_hint_color, 9), "mode.hint"))
      ok = false;
   string section_title = "运行总览";
   string section_note = "已应用配置";
   if(g_gui_page == GUI_PAGE_OPENING)
     {
      section_title = "开仓参数";
       section_note = "12项";
     }
   else if(g_gui_page == GUI_PAGE_DISTANCE)
     {
      section_title = "距离与止盈";
      section_note = "9项";
     }
   else if(g_gui_page == GUI_PAGE_GRID)
     {
      section_title = "网格参数";
      section_note = "3项";
     }
   else if(g_gui_page == GUI_PAGE_RISK)
     {
      section_title = "风控与时段";
      section_note = "5项";
     }
   if(!GuiTrackCreateResult(GuiCreateText(g_gui_object_prefix + "content.section",
                                          section_title, x + GUI_CONTENT_PADDING, y + 62,
                                          240, 18, GuiColorText(), 10), "content.section"))
      ok = false;
   if(!GuiTrackCreateResult(GuiCreateText(g_gui_object_prefix + "content.section.note",
                                          section_note, x + GUI_CONTENT_WIDTH - 78, y + 62,
                                          58, 18, GuiColorMuted(), 9), "content.section.note"))
      ok = false;

   if(g_gui_page == GUI_PAGE_OVERVIEW)
     {
      GuiSnapshot snapshot;
      GuiCollectSnapshot(snapshot);
      const int metric_width = 166;
      GuiRenderMetricCard("direction", "当前方向",
                          g_had_position ? (g_last_position_type == POSITION_TYPE_BUY
                                            ? "做多" : "做空") : "无持仓",
                          x + GUI_CONTENT_PADDING, y + 86, metric_width, ok);
      GuiRenderMetricCard("reversal", "反手次数",
                          IntegerToString(g_reversal_count) + "/"
                          + IntegerToString(g_gui_applied_config.max_reversals),
                          x + GUI_CONTENT_PADDING + metric_width + GUI_FORM_GAP,
                          y + 86, metric_width, ok);
      GuiRenderMetricCard("exposure", "持仓 / 挂单",
                          IntegerToString(snapshot.position_count) + " / "
                          + IntegerToString(snapshot.pending_order_count),
                          x + GUI_CONTENT_PADDING + (metric_width + GUI_FORM_GAP) * 2,
                          y + 86, metric_width, ok);

      const int left_x = x + GUI_CONTENT_PADDING;
      const int right_x = left_x + GUI_FIELD_WIDTH + GUI_FORM_GAP;
      const int summary_y = y + 154;
      const int row_gap = 32;
      if(!GuiRenderReadOnlyField("overview.state", "运行状态", GuiRunStateText(),
                                 left_x, summary_y, ok)) ok = false;
      if(!GuiRenderReadOnlyField("overview.direction", "首单方向",
                                 GuiFirstDirectionText(g_active_first_direction == FIRST_SELL
                                                       ? FIRST_SELL : FIRST_BUY),
                                 right_x, summary_y, ok)) ok = false;
      if(!GuiRenderReadOnlyField("overview.order_group", "订单组",
                                 (g_had_position || snapshot.pending_order_count > 0)
                                 ? "第" + IntegerToString(g_cycle_index + 1) + "组"
                                 : "无活跃订单组",
                                 left_x, summary_y + row_gap, ok)) ok = false;
      if(!GuiRenderReadOnlyField("overview.cycle", "循环阶段",
                                 "阶段" + IntegerToString(g_cycle_index + 1) + "/"
                                 + IntegerToString(CycleLength(g_active_cycle_mode))
                                 + (g_pending_index >= 0
                                    ? " · 待转" + IntegerToString(g_pending_index + 1)
                                    : ""),
                                 right_x, summary_y + row_gap, ok)) ok = false;
      if(!GuiRenderReadOnlyField("overview.positions", "持仓",
                                 IntegerToString(snapshot.position_count),
                                 left_x, summary_y + row_gap * 2, ok)) ok = false;
      if(!GuiRenderReadOnlyField("overview.orders", "挂单",
                                 IntegerToString(snapshot.pending_order_count),
                                 right_x, summary_y + row_gap * 2, ok)) ok = false;
      if(!GuiRenderReadOnlyField("overview.profit", "浮盈",
                                 DoubleToString(snapshot.floating_profit, 2),
                                 left_x, summary_y + row_gap * 3, ok)) ok = false;
      if(!GuiRenderReadOnlyField("overview.reversal", "反手次数",
                                 IntegerToString(g_reversal_count) + "/"
                                 + IntegerToString(g_gui_applied_config.max_reversals),
                                 right_x, summary_y + row_gap * 3, ok)) ok = false;
      if(!GuiRenderReadOnlyField("overview.cycle_mode", "循环模式",
                                 GuiCycleModeText(g_gui_applied_config.cycle_mode),
                                 left_x, summary_y + row_gap * 4, ok)) ok = false;
      if(!GuiRenderReadOnlyField("overview.distance_mode", "距离模式",
                                 GuiDistanceModeText(g_gui_applied_config.distance_mode),
                                 right_x, summary_y + row_gap * 4, ok)) ok = false;
      if(!GuiRenderReadOnlyField("overview.order_type", "开单方式",
                                 GuiOrderTypeText(g_gui_applied_config.order_type),
                                 left_x, summary_y + row_gap * 5, ok)) ok = false;
      if(!GuiRenderReadOnlyField("overview.initial_lots", "首单手数",
                                 DoubleToString(g_gui_applied_config.initial_lots, 8),
                                 right_x, summary_y + row_gap * 5, ok)) ok = false;
       if(!GuiRenderReadOnlyField("overview.initial_lots_multiplier", "首单手数倍数",
                                  DoubleToString(g_gui_applied_config.initial_lots_multiplier, 8),
                                  left_x, summary_y + row_gap * 6, ok)) ok = false;
       if(!GuiRenderReadOnlyField("overview.grid_count", "网格数量",
                                  IntegerToString(g_gui_applied_config.grid_count),
                                  right_x, summary_y + row_gap * 6, ok)) ok = false;
       if(!GuiRenderReadOnlyField("overview.first_order_lot_type", "止损首单类型",
                                  g_gui_applied_config.first_order_lot_type == 2
                                  ? "上一组首单" : "累计组总手数",
                                  left_x, summary_y + row_gap * 7, ok)) ok = false;
        if(!GuiRenderReadOnlyField("overview.first_order_mult", "首单类型2倍数",
                                  DoubleToString(g_gui_applied_config.first_order_mult, 8),
                                  right_x, summary_y + row_gap * 7, ok)) ok = false;
       if(!GuiRenderReadOnlyField("overview.grid_lot_multiplier", "网格手数倍数",
                                  DoubleToString(g_gui_applied_config.grid_lot_multiplier, 8),
                                  left_x, summary_y + row_gap * 8, ok)) ok = false;
       if(!GuiRenderReadOnlyField("overview.stops", "止损 / 止盈(点)",
                                  GuiDistanceSummaryText(g_gui_applied_config),
                                  right_x, summary_y + row_gap * 8, ok)) ok = false;
       if(!GuiRenderReadOnlyField("overview.take_profit_mode", "止盈移动模式",
                                  GuiTakeProfitModeText(g_gui_applied_config.take_profit_mode),
                                  left_x, summary_y + row_gap * 9, ok)) ok = false;
       if(!GuiRenderReadOnlyField("overview.schedule", "运行时间",
                                  GuiScheduleSummaryText(g_gui_applied_config),
                                  right_x, summary_y + row_gap * 9, ok)) ok = false;
       if(!GuiRenderReadOnlyField("overview.magic_number", "订单识别编号",
                                  IntegerToString((long)g_gui_applied_config.magic_number),
                                  left_x, summary_y + row_gap * 10, ok)) ok = false;
       if(!GuiRenderReadOnlyField("overview.order_comment", "订单注释",
                                  g_gui_applied_config.order_comment,
                                  right_x, summary_y + row_gap * 10, ok)) ok = false;
      GuiRenderNotice(left_x, y + 500, ok);
     }
   else if(g_gui_page == GUI_PAGE_OPENING)
     {
      const int left_x = x + GUI_CONTENT_PADDING;
      const int right_x = left_x + GUI_FIELD_WIDTH + GUI_FORM_GAP;
      const int row = y + 94;
      const int row_gap = 64;
      if(!GuiRenderEnumField("first_direction", "首单方向",
                             GuiFirstDirectionText(g_gui_draft_config.first_direction), left_x, row, ok))
         ok = false;
      if(!GuiRenderEnumField("first_direction_mode", "首单方向确定方式",
                             GuiFirstDirectionModeText(g_gui_draft_config.first_direction_mode), right_x, row, ok))
         ok = false;
      if(!GuiRenderEnumField("cycle_mode", "循环模式",
                             GuiCycleModeText(g_gui_draft_config.cycle_mode), left_x, row + row_gap, ok))
         ok = false;
      if(!GuiRenderEnumField("order_type", "开单方式",
                             GuiOrderTypeText(g_gui_draft_config.order_type), right_x, row + row_gap, ok))
         ok = false;
      if(!GuiRenderEnumField("candle_order_mode", "K线开单模式",
                             GuiCandleOrderModeText(g_gui_draft_config.candle_order_mode), left_x,
                             row + row_gap * 2, ok))
         ok = false;
      if(!GuiRenderEnumField("candle_enable_multiple", "K线多组",
                             GuiMultipleText(g_gui_draft_config.candle_enable_multiple), right_x,
                             row + row_gap * 2, ok))
         ok = false;
      if(!GuiRenderEditableDropdownField("initial_lots", "首单手数",
                                         DoubleToString(g_gui_draft_config.initial_lots, 8), left_x,
                                         row + row_gap * 3, ok))
         ok = false;
      if(!GuiRenderEditableDropdownField("initial_lots_multiplier", "首单手数倍数",
                                          DoubleToString(g_gui_draft_config.initial_lots_multiplier, 8),
                                          right_x, row + row_gap * 3, ok))
          ok = false;
       if(!GuiRenderEnumField("first_order_lot_type", "止损首单类型",
                              g_gui_draft_config.first_order_lot_type == 2
                              ? "上一组首单" : "累计组总手数",
                              left_x, row + row_gap * 4, ok))
          ok = false;
       if(!GuiRenderEditableDropdownField("first_order_mult", "首单类型2倍数",
                                          DoubleToString(g_gui_draft_config.first_order_mult, 8),
                                          right_x, row + row_gap * 4, ok))
          ok = false;
       if(!GuiRenderEditableDropdownField("bollinger_period", "布林带周期",
                                          IntegerToString(g_gui_draft_config.bollinger_period),
                                          left_x, row + row_gap * 5, ok))
          ok = false;
       if(!GuiRenderEditableDropdownField("bollinger_deviation", "布林带标准差",
                                          DoubleToString(g_gui_draft_config.bollinger_deviation, 8),
                                          right_x, row + row_gap * 5, ok))
          ok = false;
      GuiRenderNotice(x + GUI_CONTENT_PADDING, y + 500, ok);
     }
   else if(g_gui_page == GUI_PAGE_DISTANCE)
     {
      const int left_x = x + GUI_CONTENT_PADDING;
      const int right_x = left_x + GUI_FIELD_WIDTH + GUI_FORM_GAP;
      const int row = y + 94;
      const int row_gap = 64;
      if(!GuiRenderEnumField("distance_mode", "距离模式",
                             GuiDistanceModeText(g_gui_draft_config.distance_mode), left_x, row, ok))
         ok = false;
      if(!GuiRenderEditableDropdownField("stop_loss_distance_points", "固定止损距离(点)",
                                         IntegerToString(g_gui_draft_config.stop_loss_distance_points),
                                         right_x, row, ok))
         ok = false;
      if(!GuiRenderEditableDropdownField("take_profit_distance_points", "固定止盈距离(点)",
                                         IntegerToString(g_gui_draft_config.take_profit_distance_points),
                                         left_x, row + row_gap, ok))
         ok = false;
      if(!GuiRenderEditableDropdownField("candle_min_range_points", "K线最小高度(点)",
                                         IntegerToString(g_gui_draft_config.candle_min_range_points),
                                         right_x, row + row_gap, ok))
         ok = false;
      if(!GuiRenderEditableDropdownField("candle_max_range_points", "K线最大高度(点)",
                                         IntegerToString(g_gui_draft_config.candle_max_range_points),
                                         left_x, row + row_gap * 2, ok))
         ok = false;
      if(!GuiRenderEditableDropdownField("average_candle_count", "平均K线根数",
                                         IntegerToString(g_gui_draft_config.average_candle_count),
                                         right_x, row + row_gap * 3, ok))
         ok = false;
      if(!GuiRenderEditableDropdownField("average_stop_multiplier", "平均止损倍数",
                                         DoubleToString(g_gui_draft_config.average_stop_multiplier, 8),
                                         left_x, row + row_gap * 3, ok))
         ok = false;
      if(!GuiRenderEditableDropdownField("average_take_profit_multiplier", "平均止盈倍数",
                                         DoubleToString(g_gui_draft_config.average_take_profit_multiplier, 8),
                                         right_x, row + row_gap * 4, ok))
         ok = false;
      if(!GuiRenderEnumField("take_profit_mode", "止盈移动模式",
                             GuiTakeProfitModeText(g_gui_draft_config.take_profit_mode), right_x,
                             row + row_gap * 2, ok))
         ok = false;
      GuiRenderNotice(x + GUI_CONTENT_PADDING, y + 500, ok);
     }
   else if(g_gui_page == GUI_PAGE_GRID)
     {
      const int left_x = x + GUI_CONTENT_PADDING;
      const int right_x = left_x + GUI_FIELD_WIDTH + GUI_FORM_GAP;
      const int row = y + 94;
      if(!GuiRenderEditableDropdownField("grid_count", "网格数量",
                                         IntegerToString(g_gui_draft_config.grid_count), left_x, row, ok))
         ok = false;
       if(!GuiRenderEditableDropdownField("grid_lot_multiplier", "网格手数倍数",
                                          DoubleToString(g_gui_draft_config.grid_lot_multiplier, 8),
                                          right_x, row, ok))
          ok = false;
       if(!GuiRenderEnumField("favorable_grid_enable", "有利方向加单",
                              g_gui_draft_config.favorable_grid_enable == 1 ? "开启" : "关闭",
                              left_x, row + 64, ok))
           ok = false;
        if(!GuiRenderEnumField("dynamic_stop_loss_enable", "动态止损",
                               g_gui_draft_config.dynamic_stop_loss_enable == 1 ? "开启" : "关闭",
                               right_x, row + 64, ok))
           ok = false;
        if(!GuiRenderReadOnlyField("grid.filled", "已成交网格",
                                  IntegerToString(g_grid_filled_levels), left_x, row + 128, ok))
           ok = false;
        if(!GuiRenderReadOnlyField("grid.pending", "挂单价",
                                  g_grid_pending_price > 0.0
                                  ? DoubleToString(g_grid_pending_price, _Digits) : "--", right_x,
                                  row + 128, ok))
           ok = false;
        if(!GuiRenderReadOnlyField("grid.lots", "当前组手数",
                                  DoubleToString(g_group_total_lots, 2), left_x, row + 192, ok))
          ok = false;
      GuiRenderNotice(x + GUI_CONTENT_PADDING, y + 500, ok);
     }
   else
     {
      const int left_x = x + GUI_CONTENT_PADDING;
      const int right_x = left_x + GUI_FIELD_WIDTH + GUI_FORM_GAP;
      const int row = y + 94;
      const int row_gap = 64;
      if(!GuiRenderEditableDropdownField("max_reversals", "最大反手次数",
                                         IntegerToString(g_gui_draft_config.max_reversals), left_x, row, ok))
         ok = false;
      if(!GuiRenderEditableDropdownField("start_time", "时段1开始时间",
                                         g_gui_draft_config.start_time, right_x, row, ok))
         ok = false;
      if(!GuiRenderEditableDropdownField("end_time", "时段1结束时间",
                                         g_gui_draft_config.end_time, left_x, row + row_gap, ok))
         ok = false;
      if(!GuiRenderEditableDropdownField("start_time_2", "时段2开始时间",
                                         g_gui_draft_config.start_time_2, right_x,
                                         row + row_gap, ok))
         ok = false;
      if(!GuiRenderEditableDropdownField("end_time_2", "时段2结束时间",
                                         g_gui_draft_config.end_time_2, left_x,
                                         row + row_gap * 2, ok))
         ok = false;
      if(!GuiRenderEditableDropdownField("start_time_3", "时段3开始时间",
                                         g_gui_draft_config.start_time_3, right_x,
                                         row + row_gap * 2, ok))
         ok = false;
      if(!GuiRenderEditableDropdownField("end_time_3", "时段3结束时间",
                                         g_gui_draft_config.end_time_3, left_x,
                                         row + row_gap * 3, ok))
         ok = false;
      if(!GuiRenderEditField("magic_number", "订单识别编号",
                             IntegerToString((long)g_gui_draft_config.magic_number),
                             right_x, row + row_gap * 3, ok))
         ok = false;
       if(!GuiRenderEditField("order_comment", "订单注释",
                              g_gui_draft_config.order_comment, left_x, row + row_gap * 4, ok))
          ok = false;
       const string cost_status = g_gui_applied_config.cost_mode
          ? "成本模式 开 | RR " + DoubleToString(g_gui_applied_config.cost_target_rr, 2)
            + " | 点差 " + DoubleToString(g_gui_applied_config.cost_max_spread_points, 1)
            + " | 单轮/总风险 "
            + DoubleToString(g_gui_applied_config.cost_max_cycle_loss_equity_ratio * 100.0, 1)
            + "%/" + DoubleToString(g_gui_applied_config.cost_max_total_loss_equity_ratio * 100.0, 1) + "%"
          : "成本模式 关；在 EA 参数窗口配置 XAUUSD 成本预算";
       if(!GuiTrackCreateResult(GuiCreateText(g_gui_object_prefix + "risk.cost.status",
                                              cost_status, left_x, row + row_gap * 5,
                                              GUI_CONTENT_WIDTH - GUI_CONTENT_PADDING * 2, 22,
                                              GuiColorMuted(), 9), "risk.cost.status"))
          ok = false;
       GuiRenderNotice(x + GUI_CONTENT_PADDING, y + 500, ok);
     }
   if(g_gui_close_confirm_open)
      GuiRenderCloseConfirmation(ok);
   if(!GuiRenderDropdownOverlay(ok))
      ok = false;
   return ok;
  }

bool GuiRenderActions()
  {
   bool ok = true;
   const int x = GUI_CONTENT_X + GUI_CONTENT_PADDING;
   const int y = GUI_WINDOW_HEIGHT - 44;
   if(!GuiTrackCreateResult(GuiCreateButton(g_gui_object_prefix + "apply", "应用参数", x, y, 88, 28,
                                             GuiColorPrimary(), GuiColorText()), "apply"))
      ok = false;
   if(!GuiTrackCreateResult(GuiCreateButton(g_gui_object_prefix + "pause",
                                             g_gui_run_state == GUI_RUN_PAUSED_INITIAL ? "继续" : "暂停",
                                             x + 94, y, 72, 28, GuiColorSurface(), GuiColorText()), "pause"))
      ok = false;
   if(!GuiTrackCreateResult(GuiCreateButton(g_gui_object_prefix + "close", "平仓删挂单",
                                             x + 172, y, 102, 28, GuiColorDanger(), GuiColorText()), "close"))
      ok = false;
   return ok;
  }

bool GuiRenderMinimizedBar()
  {
   bool ok = true;
   const int x = 18;
   const int y = 18;
   if(!GuiTrackCreateResult(GuiCreatePanel(g_gui_object_prefix + "minimized", x, y,
                                            GUI_WINDOW_WIDTH, 34,
                                            GuiColorPanel(), GuiColorBorder()), "minimized"))
      ok = false;
   if(!GuiTrackCreateResult(GuiCreateText(g_gui_object_prefix + "minimized.text",
                                          "不管涨跌 EA  ·  " + GuiRunStateText(),
                                          x + 12, y + 8, 250, 18, GuiColorText(), 10),
                            "minimized.text"))
      ok = false;
   if(!GuiTrackCreateResult(GuiCreateButton(g_gui_object_prefix + "restore", "恢复",
                                            x + GUI_WINDOW_WIDTH - 58, y + 4, 46, 26,
                                            GuiColorPrimary(), GuiColorText()), "restore"))
      ok = false;
   return ok;
  }

bool GuiRenderActiveEdit()
  {
   if(StringLen(g_gui_edit_key) == 0)
      return false;
   const string edit_name = g_gui_object_prefix + "field." + g_gui_edit_key;
   return ObjectFind(0, edit_name) >= 0;
  }

bool GuiRender()
  {
   if(!g_gui_objects_created || StringLen(g_gui_object_prefix) == 0)
      return false;
   if(GuiRenderActiveEdit())
      return true;
   ObjectsDeleteAll(0, g_gui_object_prefix);
   g_gui_render_error = "";
   g_gui_render_error_code = 0;
   bool render_ok = true;
   if(g_gui_full_window)
     {
      if(!GuiTrackCreateResult(GuiCreatePanel(g_gui_object_prefix + "window", 18, 18,
                                              GUI_WINDOW_WIDTH, GUI_WINDOW_HEIGHT,
                                              GuiColorBackground(), GuiColorBorder()), "window"))
         render_ok = false;
      if(!GuiRenderTitleBar())
         render_ok = false;
      if(!GuiRenderNavigation())
         render_ok = false;
      if(!GuiRenderContent())
         render_ok = false;
      if(!GuiRenderActions())
         render_ok = false;
     }
   else
     {
      if(!GuiRenderMinimizedBar())
         render_ok = false;
     }
   if(!render_ok)
     {
      g_gui_notice = "GUI对象创建失败: " + g_gui_render_error;
      g_gui_run_state = GUI_RUN_ERROR;
      g_gui_dirty = true;
      PrintFormat("%s (GetLastError=%d)", g_gui_notice, g_gui_render_error_code);
      ChartRedraw(0);
      return false;
     }
   g_gui_last_snapshot = GuiBuildSnapshot();
   g_gui_dirty = false;
   ChartRedraw(0);
   return true;
  }

void GuiRenderIfNeeded()
  {
   if(v_enable != 1)
      return;
   if(!g_gui_objects_created)
      return;
   if(g_gui_full_window && g_gui_page != GUI_PAGE_OVERVIEW && !g_gui_dirty)
      return;
   const string snapshot = GuiBuildSnapshot();
   if(!g_gui_dirty && g_gui_full_window && g_gui_page == GUI_PAGE_OVERVIEW
      && snapshot != g_gui_last_snapshot)
     {
      if(GuiRefreshOverviewData())
        {
         g_gui_last_snapshot = snapshot;
         return;
        }
     }
   if(g_gui_dirty || snapshot != g_gui_last_snapshot)
      GuiRender();
  }

void GuiMarkDraftChanged()
  {
   g_gui_has_unapplied_changes = true;
   g_gui_notice = "有未应用修改";
   GuiMarkDirty();
  }

bool GuiIsEditableFieldKey(const string key)
  {
   return key == "initial_lots" || key == "initial_lots_multiplier"
          || key == "first_order_mult"
          || key == "grid_count" || key == "grid_lot_multiplier"
          || key == "stop_loss_distance_points"
          || key == "take_profit_distance_points"
          || key == "candle_min_range_points"
          || key == "candle_max_range_points"
          || key == "bollinger_period"
          || key == "bollinger_deviation"
          || key == "max_reversals" || key == "magic_number"
          || key == "start_time" || key == "end_time"
          || key == "start_time_2" || key == "end_time_2"
          || key == "start_time_3" || key == "end_time_3"
          || key == "order_comment";
  }

bool GuiIsDecimalText(const string value, const bool allow_decimal)
  {
   string trimmed = value;
   StringTrimLeft(trimmed);
   StringTrimRight(trimmed);
   if(StringLen(trimmed) == 0)
      return false;
   int digits = 0;
   int decimals = 0;
   for(int index = 0; index < StringLen(trimmed); index++)
     {
      const int ch = StringGetCharacter(trimmed, index);
      if(ch >= '0' && ch <= '9')
        {
         digits++;
         continue;
        }
      if(ch == '-' && index == 0)
         continue;
      if(allow_decimal && ch == '.' && decimals == 0)
        {
         decimals++;
         continue;
        }
      return false;
     }
   return digits > 0;
  }

bool GuiTryParseDouble(const string value, double &result)
  {
   if(!GuiIsDecimalText(value, true))
      return false;
   result = StringToDouble(value);
   return true;
  }

bool GuiTryParseLong(const string value, long &result)
  {
   if(!GuiIsDecimalText(value, false))
      return false;
   result = StringToInteger(value);
   return true;
  }

bool GuiTryParseInteger(const string value, int &result)
  {
   long parsed = 0;
   if(!GuiTryParseLong(value, parsed)
      || parsed < -2147483648
      || parsed > 2147483647)
      return false;
   result = (int)parsed;
   return true;
  }

bool GuiParseEditableDropdownValue(const string key, const string value,
                                   string &normalized, string &error)
  {
   normalized = value;
   error = "";
   string trimmed = value;
   StringTrimLeft(trimmed);
   StringTrimRight(trimmed);
    if(key == "initial_lots" || key == "initial_lots_multiplier"
       || key == "first_order_mult"
       || key == "grid_lot_multiplier")
     {
      double parsed = 0.0;
      if(!GuiTryParseDouble(trimmed, parsed))
        {
         error = "请输入有效的正数";
         return false;
        }
      normalized = DoubleToString(parsed, 8);
      return true;
     }
   if(key == "stop_loss_distance_points"
      || key == "take_profit_distance_points"
      || key == "candle_min_range_points"
      || key == "candle_max_range_points"
      || key == "bollinger_period"
      || key == "grid_count" || key == "max_reversals")
     {
      int parsed = 0;
      if(!GuiTryParseInteger(trimmed, parsed))
        {
         error = "请输入有效的整数";
         return false;
        }
      if((key == "stop_loss_distance_points"
          || key == "take_profit_distance_points"
          || key == "candle_min_range_points"
          || key == "candle_max_range_points"
          || key == "bollinger_period") && parsed <= 0)
        {
         error = "距离和K线高度必须大于 0";
         return false;
        }
      if(key == "grid_count" && parsed < 0)
        {
         error = "网格数量必须在 0 到 63 之间";
         return false;
        }
      if(key == "grid_count" && parsed > MAX_GRID_COUNT)
        {
         error = "网格数量必须在 0 到 63 之间";
         return false;
        }
      if(key == "max_reversals" && parsed < 0)
        {
         error = "最大反手次数不能小于 0";
         return false;
        }
      if(key == "candle_max_range_points"
         && parsed < g_gui_draft_config.candle_min_range_points)
        {
         error = "K线最大高度不能小于最小高度";
         return false;
        }
      normalized = IntegerToString(parsed);
      return true;
     }
   if(key == "magic_number")
     {
      long parsed = 0;
      if(!GuiTryParseLong(trimmed, parsed) || parsed <= 0)
        {
         error = "订单识别编号必须是正整数";
         return false;
        }
      normalized = IntegerToString(parsed);
      return true;
     }
   if(key == "start_time" || key == "end_time"
      || key == "start_time_2" || key == "end_time_2"
      || key == "start_time_3" || key == "end_time_3")
     {
      string time_value = trimmed;
      if(StringLen(time_value) == 4 && StringGetCharacter(time_value, 1) == 58)
         time_value = "0" + time_value;
      if(ParseTimeMinutes(time_value) < 0)
        {
         error = "时间格式必须为 HH:MM，范围为 00:00-23:59";
         return false;
        }
      normalized = time_value;
      return true;
     }
   if(key == "order_comment")
     {
      if(StringLen(trimmed) == 0)
        {
         error = "订单注释不能为空";
         return false;
        }
      normalized = trimmed;
      return true;
     }
   return false;
  }

bool GuiSyncEditValue(const string key)
  {
   if(!GuiIsEditableFieldKey(key))
      return false;
   const string object_name = g_gui_object_prefix + "field." + key;
   if(ObjectFind(0, object_name) < 0)
      return false;
   string value = ObjectGetString(0, object_name, OBJPROP_TEXT);
   string normalized = value;
   string input_error = "";
   if(!GuiParseEditableDropdownValue(key, value, normalized, input_error))
     {
      g_gui_notice = input_error;
      GuiRefreshNoticeObject();
      return false;
     }
   if(normalized != value)
     {
      ObjectSetString(0, object_name, OBJPROP_TEXT, normalized);
      value = normalized;
     }
   double parsed_double = 0.0;
   int parsed_integer = 0;
   long parsed_long = 0;
   if(key == "initial_lots")
     {
      if(!GuiTryParseDouble(value, parsed_double))
        {
         g_gui_notice = "首单手数格式无效";
         GuiRefreshNoticeObject();
         return false;
        }
      g_gui_draft_config.initial_lots = parsed_double;
     }
    else if(key == "initial_lots_multiplier")
      {
      if(!GuiTryParseDouble(value, parsed_double))
        {
         g_gui_notice = "首单手数倍数格式无效";
         GuiRefreshNoticeObject();
         return false;
        }
       g_gui_draft_config.initial_lots_multiplier = parsed_double;
      }
    else if(key == "first_order_mult")
      {
       if(!GuiTryParseDouble(value, parsed_double))
         {
          g_gui_notice = "首单类型2倍数格式无效";
          GuiRefreshNoticeObject();
          return false;
         }
       g_gui_draft_config.first_order_mult = parsed_double;
      }
   else if(key == "grid_count")
     {
      if(!GuiTryParseInteger(value, parsed_integer))
        {
         g_gui_notice = "网格数量格式无效";
         GuiRefreshNoticeObject();
         return false;
        }
      g_gui_draft_config.grid_count = parsed_integer;
     }
   else if(key == "grid_lot_multiplier")
     {
      if(!GuiTryParseDouble(value, parsed_double))
        {
         g_gui_notice = "网格手数倍数格式无效";
         GuiRefreshNoticeObject();
         return false;
        }
      g_gui_draft_config.grid_lot_multiplier = parsed_double;
     }
   else if(key == "stop_loss_distance_points")
     {
      if(!GuiTryParseInteger(value, parsed_integer))
        {
         g_gui_notice = "止损距离格式无效";
         GuiRefreshNoticeObject();
         return false;
        }
      g_gui_draft_config.stop_loss_distance_points = parsed_integer;
     }
   else if(key == "take_profit_distance_points")
     {
      if(!GuiTryParseInteger(value, parsed_integer))
        {
         g_gui_notice = "止盈距离格式无效";
         GuiRefreshNoticeObject();
         return false;
        }
      g_gui_draft_config.take_profit_distance_points = parsed_integer;
     }
   else if(key == "candle_min_range_points")
     {
      if(!GuiTryParseInteger(value, parsed_integer))
        {
         g_gui_notice = "K线最小高度格式无效";
         GuiRefreshNoticeObject();
         return false;
        }
      g_gui_draft_config.candle_min_range_points = parsed_integer;
     }
   else if(key == "candle_max_range_points")
     {
      if(!GuiTryParseInteger(value, parsed_integer))
        {
         g_gui_notice = "K线最大高度格式无效";
         GuiRefreshNoticeObject();
         return false;
        }
      g_gui_draft_config.candle_max_range_points = parsed_integer;
     }
   else if(key == "bollinger_period")
     {
      if(!GuiTryParseInteger(value, parsed_integer))
        {
         g_gui_notice = "布林带周期格式无效";
         GuiRefreshNoticeObject();
         return false;
        }
      g_gui_draft_config.bollinger_period = parsed_integer;
     }
   else if(key == "bollinger_deviation")
     {
      if(!GuiTryParseDouble(value, parsed_double))
        {
         g_gui_notice = "布林带标准差格式无效";
         GuiRefreshNoticeObject();
         return false;
        }
      g_gui_draft_config.bollinger_deviation = parsed_double;
     }
   else if(key == "max_reversals")
     {
      if(!GuiTryParseInteger(value, parsed_integer))
        {
         g_gui_notice = "最大反手次数格式无效";
         GuiRefreshNoticeObject();
         return false;
        }
      g_gui_draft_config.max_reversals = parsed_integer;
     }
   else if(key == "magic_number")
     {
      if(!GuiTryParseLong(value, parsed_long))
        {
         g_gui_notice = "订单识别编号格式无效";
         GuiRefreshNoticeObject();
         return false;
        }
      g_gui_draft_config.magic_number = parsed_long > 0 ? (ulong)parsed_long : 0;
     }
   else if(key == "start_time")
      g_gui_draft_config.start_time = value;
   else if(key == "end_time")
      g_gui_draft_config.end_time = value;
   else if(key == "start_time_2")
      g_gui_draft_config.start_time_2 = value;
   else if(key == "end_time_2")
      g_gui_draft_config.end_time_2 = value;
   else if(key == "start_time_3")
      g_gui_draft_config.start_time_3 = value;
   else if(key == "end_time_3")
      g_gui_draft_config.end_time_3 = value;
   else if(key == "order_comment")
      g_gui_draft_config.order_comment = value;
   else
      return false;
   return true;
  }

bool GuiLeaveEditSession()
  {
   if(StringLen(g_gui_edit_key) == 0)
      return true;
   if(!GuiSyncEditValue(g_gui_edit_key))
     {
      g_gui_notice = "请先修正当前输入";
      GuiRefreshNoticeObject();
      return false;
     }
   g_gui_edit_key = "";
   g_gui_has_unapplied_changes = true;
   g_gui_edit_original_value = "";
   return true;
  }

void GuiReleaseButtonState(const string object_name)
  {
   if(ObjectFind(0, object_name) < 0)
      return;
   if((ENUM_OBJECT)ObjectGetInteger(0, object_name, OBJPROP_TYPE) == OBJ_BUTTON)
      ObjectSetInteger(0, object_name, OBJPROP_STATE, false);
  }

bool GuiHandleEditEnd(const string object_name)
  {
   const string field_prefix = g_gui_object_prefix + "field.";
   if(StringFind(object_name, field_prefix) != 0)
      return false;
   const string key = StringSubstr(object_name, StringLen(field_prefix));
   if(!GuiSyncEditValue(key))
      return false;
   g_gui_edit_key = "";
   g_gui_edit_original_value = "";
   GuiMarkDraftChanged();
   return true;
  }

bool GuiHandleEditKeyDown(const long key_code)
  {
   if(StringLen(g_gui_edit_key) == 0)
      return false;
   if(key_code == 27)
     {
      const string edit_name = g_gui_object_prefix + "field." + g_gui_edit_key;
      if(ObjectFind(0, edit_name) >= 0)
         ObjectSetString(0, edit_name, OBJPROP_TEXT, g_gui_edit_original_value);
      g_gui_edit_key = "";
      g_gui_edit_original_value = "";
      g_gui_notice = "已取消本次编辑";
      GuiMarkDirty();
      return true;
     }
   if(key_code == 13)
     {
      if(!GuiLeaveEditSession())
         return true;
      g_gui_edit_original_value = "";
      GuiMarkDirty();
      return true;
     }
   return false;
  }

bool GuiHandleEnumClick(const string object_name)
  {
   const string field_prefix = g_gui_object_prefix + "field.";
   if(StringFind(object_name, field_prefix) != 0)
      return false;
   const string key = StringSubstr(object_name, StringLen(field_prefix));
   if(GuiDropdownOptionCount(key) == 0)
      return false;
   g_gui_dropdown_key = g_gui_dropdown_key == key ? "" : key;
   GuiMarkDirty();
   return true;
  }

bool GuiHandleFieldClick(const string object_name)
  {
   const string field_prefix = g_gui_object_prefix + "field.";
   const string arrow_prefix = field_prefix + "arrow.";
   if(StringFind(object_name, arrow_prefix) == 0)
     {
      const string arrow_key = StringSubstr(object_name, StringLen(arrow_prefix));
      if(GuiAnyDropdownOptionCount(arrow_key) <= 0)
         return false;
      if(StringLen(g_gui_edit_key) > 0 && !GuiLeaveEditSession())
         return true;
      g_gui_edit_key = "";
      g_gui_edit_original_value = "";
      g_gui_dropdown_key = g_gui_dropdown_key == arrow_key ? "" : arrow_key;
      GuiMarkDirty();
      return true;
     }
   if(StringFind(object_name, field_prefix) != 0)
      return false;
   const string key = StringSubstr(object_name, StringLen(field_prefix));
   if(GuiIsEditableFieldKey(key))
     {
      if(g_gui_edit_key != key)
        {
         if(StringLen(g_gui_edit_key) > 0 && !GuiLeaveEditSession())
            return true;
         g_gui_dropdown_key = "";
         g_gui_edit_key = key;
         const string edit_name = field_prefix + key;
         g_gui_edit_original_value = ObjectFind(0, edit_name) >= 0
                                      ? ObjectGetString(0, edit_name, OBJPROP_TEXT) : "";
        }
      const string edit_name = field_prefix + key;
      if(ObjectFind(0, edit_name) >= 0)
        {
         ObjectSetInteger(0, edit_name, OBJPROP_SELECTABLE, true);
         ObjectSetInteger(0, edit_name, OBJPROP_READONLY, false);
         ObjectSetInteger(0, edit_name, OBJPROP_SELECTED, false);
        }
      return true;
     }
   if(GuiAnyDropdownOptionCount(key) <= 0)
      return false;
   if(StringLen(g_gui_edit_key) > 0 && !GuiLeaveEditSession())
      return true;
   g_gui_edit_key = "";
   g_gui_edit_original_value = "";
   g_gui_dropdown_key = g_gui_dropdown_key == key ? "" : key;
   GuiMarkDirty();
   return true;
  }

bool GuiHandleDropdownClick(const string object_name)
  {
   const string dropdown_prefix = g_gui_object_prefix + "dropdown.";
   if(StringFind(object_name, dropdown_prefix) != 0)
      return false;
   const string payload = StringSubstr(object_name, StringLen(dropdown_prefix));
   const int separator = StringFind(payload, ".");
   if(separator <= 0)
      return false;
   const string key = StringSubstr(payload, 0, separator);
   const int index = (int)StringToInteger(StringSubstr(payload, separator + 1));
   if(!GuiSetAnyDropdownValue(key, index))
      return false;
   g_gui_dropdown_key = "";
   GuiMarkDraftChanged();
   return true;
  }

bool GuiHandleChartClick(const int x, const int y)
  {
   if(g_gui_close_confirm_open)
      return false;

   if(!g_gui_full_window)
     {
      const int restore_x = 18 + GUI_WINDOW_WIDTH - 58;
      if(x >= restore_x && x <= restore_x + 46 && y >= 22 && y <= 52)
        {
         g_gui_dropdown_key = "";
         g_gui_edit_key = "";
         if(!GuiPrepareChartForWindow())
           {
            g_gui_run_state = GUI_RUN_ERROR;
            g_gui_notice = "GUI无法隐藏图表交易叠加层";
            GuiMarkDirty();
            return true;
           }
         g_gui_full_window = true;
         GuiMarkDirty();
         return true;
        }
      return false;
     }

   const int navigation_x = 18 + 12;
   const int navigation_width = GUI_NAV_WIDTH - 24;
   for(int index = 0; index < 5; index++)
     {
      const int navigation_y = 60 + 48 + index * 48;
      if(x < navigation_x || x > navigation_x + navigation_width
         || y < navigation_y - 4 || y > navigation_y + 32)
         continue;
      if(StringLen(g_gui_edit_key) > 0 && !GuiLeaveEditSession())
         return true;
      g_gui_dropdown_key = "";
      g_gui_edit_key = "";
      g_gui_page = (GuiPage)index;
      GuiMarkDirty();
      return true;
     }

   const int content_x = GUI_CONTENT_X + GUI_CONTENT_WIDTH - 112;
   if(x >= content_x && x <= content_x + 92 && y >= 72 && y <= 96)
     {
      if(StringLen(g_gui_edit_key) > 0 && !GuiLeaveEditSession())
         return true;
      g_gui_dropdown_key = "";
      g_gui_edit_key = "";
      g_gui_display_mode = g_gui_display_mode == GUI_MODE_EXPERT
                           ? GUI_MODE_SIMPLE : GUI_MODE_EXPERT;
      GuiMarkDirty();
      return true;
     }

   const int actions_x = GUI_CONTENT_X + GUI_CONTENT_PADDING;
   const int actions_y = GUI_WINDOW_HEIGHT - 44;
   if(y >= actions_y && y <= actions_y + 28)
     {
      if(StringLen(g_gui_edit_key) > 0 && !GuiLeaveEditSession())
         return true;
      g_gui_dropdown_key = "";
      g_gui_edit_key = "";
      if(x >= actions_x && x <= actions_x + 88)
        {
         GuiApplyDraft();
         return true;
        }
      if(x >= actions_x + 94 && x <= actions_x + 166)
        {
         if(g_gui_run_state == GUI_RUN_PAUSED_INITIAL)
           {
            g_gui_run_state = GUI_RUN_RUNNING;
            g_gui_notice = "已恢复；不会强制开首单";
           }
         else if(g_gui_run_state != GUI_RUN_CLEANING)
           {
            g_gui_run_state = GUI_RUN_PAUSED_INITIAL;
            g_gui_notice = "已暂停新首单；现有持仓及挂单继续管理";
           }
         GuiMarkDirty();
         return true;
        }
      if(x >= actions_x + 172 && x <= actions_x + 274)
        {
         g_gui_close_confirm_open = true;
         GuiMarkDirty();
         return true;
        }
     }

   const int minimize_x = 18 + GUI_WINDOW_WIDTH - 38;
   if(x >= minimize_x && x <= minimize_x + 28 && y >= 25 && y <= 53)
     {
      if(StringLen(g_gui_edit_key) > 0 && !GuiLeaveEditSession())
         return true;
      g_gui_dropdown_key = "";
      g_gui_edit_key = "";
      GuiRestoreChartAfterWindow();
      g_gui_full_window = false;
      GuiMarkDirty();
      return true;
     }

   const int left_x = GUI_CONTENT_X + GUI_CONTENT_PADDING;
   const int right_x = left_x + GUI_FIELD_WIDTH + GUI_FORM_GAP;
   const int value_width = GUI_FIELD_WIDTH;
   const int first_y = 60 + 94;
   const int row_gap = 64;
   string keys[12];
   int field_count = 0;
   if(g_gui_page == GUI_PAGE_OPENING)
     {
      keys[0] = "first_direction";
      keys[1] = "cycle_mode";
      keys[2] = "order_type";
      keys[3] = "candle_order_mode";
      keys[4] = "candle_enable_multiple";
      keys[5] = "initial_lots";
      keys[6] = "initial_lots_multiplier";
      field_count = 7;
     }
   else if(g_gui_page == GUI_PAGE_DISTANCE)
     {
      keys[0] = "distance_mode";
      keys[1] = "stop_loss_distance_points";
      keys[2] = "take_profit_distance_points";
      keys[3] = "candle_min_range_points";
      keys[4] = "candle_max_range_points";
      keys[5] = "take_profit_mode";
      field_count = 6;
     }
    else if(g_gui_page == GUI_PAGE_GRID)
      {
       keys[0] = "grid_count";
       keys[1] = "grid_lot_multiplier";
       keys[2] = "favorable_grid_enable";
       keys[3] = "dynamic_stop_loss_enable";
       field_count = 4;
      }
   else if(g_gui_page == GUI_PAGE_RISK)
     {
      keys[0] = "max_reversals";
      keys[1] = "start_time";
      keys[2] = "end_time";
      keys[3] = "start_time_2";
      keys[4] = "end_time_2";
      keys[5] = "start_time_3";
      keys[6] = "end_time_3";
      keys[7] = "magic_number";
      keys[8] = "order_comment";
      field_count = 9;
     }

   if(StringLen(g_gui_dropdown_key) > 0)
     {
      for(int index = 0; index < field_count; index++)
        {
         if(keys[index] != g_gui_dropdown_key)
            continue;
         const int option_count = GuiAnyDropdownOptionCount(keys[index]);
         for(int option = 0; option < option_count; option++)
           {
            const int field_x = (index % 2 == 0) ? left_x : right_x;
            const int field_y = first_y + (index / 2) * row_gap + 18;
            int option_x = field_x;
            int option_y = field_y;
            int option_width = value_width;
            GuiDropdownOptionGeometry(keys[index], field_x, field_y, option,
                                      option_x, option_y, option_width);
            if(x >= option_x && x <= option_x + option_width
               && y >= option_y && y <= option_y + GUI_FIELD_HEIGHT)
              {
               if(GuiSetAnyDropdownValue(keys[index], option))
                 {
                  g_gui_dropdown_key = "";
                  GuiMarkDraftChanged();
                  return true;
                 }
               return false;
              }
           }
         break;
        }
     }

   for(int index = 0; index < field_count; index++)
     {
      const int field_x = (index % 2 == 0) ? left_x : right_x;
      const int field_y = first_y + (index / 2) * row_gap + 18;
      if(x < field_x || x > field_x + value_width
         || y < field_y || y > field_y + GUI_FIELD_HEIGHT)
         continue;
      const bool editable_dropdown = GuiIsEditableDropdownKey(keys[index]);
      if(!editable_dropdown && GuiAnyDropdownOptionCount(keys[index]) > 0)
        {
         g_gui_edit_key = "";
         g_gui_edit_original_value = "";
         g_gui_dropdown_key = g_gui_dropdown_key == keys[index] ? "" : keys[index];
         GuiMarkDirty();
         return true;
        }
      if(editable_dropdown
         && x >= field_x + value_width - GUI_DROPDOWN_ARROW_WIDTH)
        {
         g_gui_edit_key = "";
         g_gui_edit_original_value = "";
         g_gui_dropdown_key = g_gui_dropdown_key == keys[index] ? "" : keys[index];
         GuiMarkDirty();
         return true;
        }
      const string edit_name = g_gui_object_prefix + "field." + keys[index];
      if(ObjectFind(0, edit_name) >= 0)
        {
         g_gui_dropdown_key = "";
         g_gui_edit_key = keys[index];
         g_gui_edit_original_value = ObjectGetString(0, edit_name, OBJPROP_TEXT);
         ObjectSetInteger(0, edit_name, OBJPROP_SELECTABLE, true);
         ObjectSetInteger(0, edit_name, OBJPROP_READONLY, false);
         ObjectSetInteger(0, edit_name, OBJPROP_SELECTED, false);
        }
      return true;
     }
   if(StringLen(g_gui_dropdown_key) > 0)
     {
      g_gui_dropdown_key = "";
      GuiMarkDirty();
      return true;
     }
   return false;
  }

bool GuiApplyDraft()
  {
   string error = "";
   if(!ValidateGuiConfig(g_gui_draft_config, error))
     {
      g_gui_notice = error;
      GuiMarkDirty();
      return false;
     }
   if(!ApplyGuiConfig(g_gui_draft_config, error))
     {
      if(StringLen(error) == 0)
         error = g_gui_notice;
      g_gui_notice = error;
      GuiMarkDirty();
      return false;
     }
   g_gui_notice = "已应用；当前订单组锁定参数保持不变，新设置从下一轮生效";
   GuiMarkDirty();
   return true;
  }

bool GuiSetChartOverlayProperty(const ENUM_CHART_PROPERTY_INTEGER property, const bool value)
  {
   ResetLastError();
   if(!ChartSetInteger(0, property, value))
      return false;
   return GetLastError() == 0;
  }

bool GuiPrepareChartForWindow()
  {
   if(g_gui_chart_overlay_state_saved)
      return true;
   ResetLastError();
   g_gui_saved_trade_levels = (bool)ChartGetInteger(0, CHART_SHOW_TRADE_LEVELS);
   if(GetLastError() != 0)
      return false;
   ResetLastError();
   g_gui_saved_trade_history = (bool)ChartGetInteger(0, CHART_SHOW_TRADE_HISTORY);
   if(GetLastError() != 0)
      return false;
   g_gui_chart_overlay_state_saved = true;
   if(!GuiSetChartOverlayProperty(CHART_SHOW_TRADE_LEVELS, false))
     {
      g_gui_chart_overlay_state_saved = false;
      return false;
     }
   if(!GuiSetChartOverlayProperty(CHART_SHOW_TRADE_HISTORY, false))
     {
      GuiSetChartOverlayProperty(CHART_SHOW_TRADE_LEVELS, g_gui_saved_trade_levels);
      g_gui_chart_overlay_state_saved = false;
      return false;
     }
   ChartRedraw(0);
   return true;
  }

void GuiRestoreChartAfterWindow()
  {
   if(!g_gui_chart_overlay_state_saved)
      return;
   const bool levels_restored = GuiSetChartOverlayProperty(CHART_SHOW_TRADE_LEVELS,
                                                            g_gui_saved_trade_levels);
   const bool history_restored = GuiSetChartOverlayProperty(CHART_SHOW_TRADE_HISTORY,
                                                             g_gui_saved_trade_history);
   if(levels_restored && history_restored)
      g_gui_chart_overlay_state_saved = false;
   else
     {
      g_gui_run_state = GUI_RUN_ERROR;
      g_gui_notice = "GUI无法恢复图表交易叠加层";
     }
   ChartRedraw(0);
  }

bool GuiCreate()
  {
   g_gui_object_prefix = GuiObjectPrefix();
   const string legacy_prefix = GuiLegacyObjectPrefix();
   ObjectsDeleteAll(0, legacy_prefix);
   g_gui_objects_created = true;
   g_gui_dirty = true;
   if(!GuiPrepareChartForWindow())
     {
      g_gui_run_state = GUI_RUN_ERROR;
      g_gui_notice = "GUI无法隐藏图表交易叠加层";
     }
   return GuiRender();
  }

void GuiDestroy()
  {
   if(!g_gui_objects_created)
     {
      g_gui_object_prefix = "";
      g_gui_dropdown_key = "";
      g_gui_edit_key = "";
      return;
     }
   if(StringLen(g_gui_object_prefix) > 0)
      ObjectsDeleteAll(0, g_gui_object_prefix);
   const string legacy_prefix = GuiLegacyObjectPrefix();
   ObjectsDeleteAll(0, legacy_prefix);
   g_gui_objects_created = false;
   g_gui_dropdown_key = "";
   g_gui_edit_key = "";
   GuiRestoreChartAfterWindow();
   g_gui_last_snapshot = "";
   g_gui_dirty = true;
   g_gui_object_prefix = "";
  }

void GuiRememberObjectClick(const long x, const long y)
  {
   g_gui_object_click_pending = true;
   g_gui_object_click_x = x;
   g_gui_object_click_y = y;
  }

bool GuiShouldSkipChartClick(const long x, const long y)
  {
   if(!g_gui_object_click_pending)
      return false;
   const bool same_click = x == g_gui_object_click_x && y == g_gui_object_click_y;
   g_gui_object_click_pending = false;
   return same_click;
  }

void OnChartEvent(const int id, const long &lparam, const double &dparam,
                  const string &sparam)
  {
   if(v_enable != 1)
      return;
   if(id == CHARTEVENT_OBJECT_CLICK)
      GuiRememberObjectClick(lparam, (long)dparam);
   if(id == CHARTEVENT_CLICK && GuiShouldSkipChartClick(lparam, (long)dparam))
      return;
   if(id == CHARTEVENT_CLICK)
     {
      if(GuiHandleChartClick((int)lparam, (int)dparam))
        {
         GuiRender();
         return;
        }
     }
   if(id == CHARTEVENT_KEYDOWN && StringLen(g_gui_edit_key) > 0)
     {
      if(GuiHandleEditKeyDown(lparam))
        {
         GuiRender();
         return;
        }
      if(GuiSyncEditValue(g_gui_edit_key))
        {
         g_gui_has_unapplied_changes = true;
         g_gui_notice = "有未应用修改";
        }
      return;
     }
   if(!g_gui_objects_created || StringFind(sparam, g_gui_object_prefix) != 0)
      return;

   if(id == CHARTEVENT_OBJECT_CLICK && GuiHandleFieldClick(sparam))
     {
      const string field_prefix = g_gui_object_prefix + "field.";
      const string field_key = StringSubstr(sparam, StringLen(field_prefix));
      if(!GuiIsEditableFieldKey(field_key))
         GuiRender();
      return;
     }

   if(id == CHARTEVENT_OBJECT_CLICK && StringLen(g_gui_edit_key) > 0
      && StringFind(sparam, g_gui_object_prefix + "field.") != 0)
     {
      if(!GuiLeaveEditSession())
         return;
     }

   if(id == CHARTEVENT_OBJECT_CLICK)
      GuiReleaseButtonState(sparam);

   if(id == CHARTEVENT_OBJECT_ENDEDIT)
     {
      if(GuiHandleEditEnd(sparam))
         GuiRender();
      return;
     }
   if(id != CHARTEVENT_OBJECT_CLICK)
      return;

      if(sparam == g_gui_object_prefix + "minimize")
     {
      g_gui_dropdown_key = "";
      g_gui_edit_key = "";
      GuiRestoreChartAfterWindow();
      g_gui_full_window = false;
      GuiMarkDirty();
      GuiRender();
      return;
     }
   if(sparam == g_gui_object_prefix + "restore")
     {
      g_gui_dropdown_key = "";
      g_gui_edit_key = "";
      if(!GuiPrepareChartForWindow())
        {
         g_gui_run_state = GUI_RUN_ERROR;
         g_gui_notice = "GUI无法隐藏图表交易叠加层";
         GuiMarkDirty();
         GuiRender();
         return;
        }
      g_gui_full_window = true;
      GuiMarkDirty();
      GuiRender();
      return;
     }
   if(sparam == g_gui_object_prefix + "pause")
     {
      g_gui_dropdown_key = "";
      g_gui_edit_key = "";
      if(g_gui_run_state == GUI_RUN_PAUSED_INITIAL)
        {
         g_gui_run_state = GUI_RUN_RUNNING;
         g_gui_notice = "已恢复；不会强制开首单";
        }
      else if(g_gui_run_state != GUI_RUN_CLEANING)
        {
         g_gui_run_state = GUI_RUN_PAUSED_INITIAL;
         g_gui_notice = "已暂停新首单；现有持仓及挂单继续管理";
        }
      GuiMarkDirty();
      GuiRender();
      return;
     }
   if(sparam == g_gui_object_prefix + "close")
     {
      g_gui_dropdown_key = "";
      g_gui_edit_key = "";
      g_gui_close_confirm_open = true;
      GuiMarkDirty();
      GuiRender();
      return;
     }
   if(sparam == g_gui_object_prefix + "confirm.cancel")
     {
      g_gui_dropdown_key = "";
      g_gui_edit_key = "";
      g_gui_close_confirm_open = false;
      GuiMarkDirty();
      GuiRender();
      return;
     }
   if(sparam == g_gui_object_prefix + "confirm.cleanup")
     {
      if(!g_gui_close_confirm_open)
         return;
      g_gui_close_confirm_open = false;
      g_gui_run_state = GUI_RUN_CLEANING;
      g_gui_notice = "清理中";
      GuiMarkDirty();
      BeginFullReset("GUI requested clearing all EA positions and pending orders.");
      GuiRender();
      return;
     }
   if(sparam == g_gui_object_prefix + "mode.toggle")
     {
      g_gui_dropdown_key = "";
      g_gui_edit_key = "";
      g_gui_display_mode = g_gui_display_mode == GUI_MODE_EXPERT
                           ? GUI_MODE_SIMPLE : GUI_MODE_EXPERT;
      GuiMarkDirty();
      GuiRender();
      return;
     }
   if(sparam == g_gui_object_prefix + "apply")
     {
      g_gui_dropdown_key = "";
      g_gui_edit_key = "";
      GuiApplyDraft();
      GuiRender();
      return;
     }
   if(GuiHandleDropdownClick(sparam))
     {
      g_gui_edit_key = "";
      GuiRender();
      return;
     }
   if(GuiHandleEnumClick(sparam))
     {
      g_gui_edit_key = "";
      GuiRender();
      return;
     }
   for(int index = 0; index < 5; index++)
     {
      if(sparam == g_gui_object_prefix + "nav." + IntegerToString(index))
        {
         g_gui_dropdown_key = "";
         g_gui_edit_key = "";
         g_gui_page = (GuiPage)index;
         GuiMarkDirty();
         GuiRender();
         return;
        }
     }
  }

int OnInit()
  {
   GuiConfig input_config = LoadConfigFromInputs();
   string config_error = "";
   if(!ValidateGuiConfig(input_config, config_error))
     {
      PrintFormat("Invalid GUI configuration: %s", config_error);
      return INIT_PARAMETERS_INCORRECT;
     }
   if(!CheckKnownScopeExposure(input_config.magic_number, config_error))
     {
      PrintFormat("Cannot initialize GUI configuration: %s", config_error);
      return INIT_FAILED;
     }
   if(!CheckKnownScopeTransitions(input_config.magic_number, config_error))
     {
      PrintFormat("Cannot initialize GUI configuration: %s", config_error);
      return INIT_FAILED;
     }
   if(!ValidatePersistedConfigForMagic(input_config, config_error))
     {
      PrintFormat("Cannot initialize GUI configuration: %s", config_error);
      return INIT_FAILED;
     }
   const bool persisted_state_loaded = LoadStateForMagic(input_config.magic_number);
   if(!ApplyGuiConfig(input_config, config_error))
     {
      PrintFormat("Invalid GUI configuration: %s", config_error);
      return INIT_PARAMETERS_INCORRECT;
     }

   if(!AcquireExecutionOwnership())
      return INIT_FAILED;
   string scope_error = "";
   if(!RememberManagedScope(g_gui_applied_config.magic_number, scope_error))
     {
      PrintFormat("Cannot initialize MT5 scope registry: %s", scope_error);
      ReleaseExecutionOwnership();
      return INIT_FAILED;
     }

   if(!persisted_state_loaded)
     {
      g_active_first_direction = g_gui_applied_config.first_direction;
      g_active_cycle_mode = g_gui_applied_config.cycle_mode;
     }
   LoadState();
   MultiLoadGroups();
   bool has_multi_cost_state = false;
   for(int loaded_group = 0; loaded_group < ArraySize(g_multi_groups); loaded_group++)
      if(g_multi_groups[loaded_group].active && g_multi_groups[loaded_group].cost_active)
         has_multi_cost_state = true;
    if(g_gui_applied_config.cost_mode && !g_cost_active
       && !(g_gui_applied_config.distance_mode == DISTANCE_CANDLE_RANGE
            && g_gui_applied_config.candle_enable_multiple == 1)
       && !MultiHasActiveGroups()
       && HasManagedExposureForMagic(g_gui_applied_config.magic_number))
     {
      Print("[COST_INIT_REJECT=LEGACY_EXPOSURE_REQUIRES_FLAT_SCOPE]");
      ReleaseExecutionOwnership();
      return INIT_FAILED;
     }
   if(g_gui_applied_config.cost_mode || has_multi_cost_state)
     {
       if(!MultiCostLoadMap())
         {
         Print("[COST_INIT_REJECT=MULTI_POSITION_MAP_INCOMPLETE]");
         ReleaseExecutionOwnership();
          return INIT_FAILED;
         }
       MultiCostLoadArchive();
       if(has_multi_cost_state || g_gui_applied_config.cost_mode)
          for(int index = PositionsTotal() - 1; index >= 0; index--)
            {
             const ulong ticket = PositionGetTicket(index);
             if(PositionGetString(POSITION_SYMBOL) != _Symbol
                || (ulong)PositionGetInteger(POSITION_MAGIC) != g_gui_applied_config.magic_number)
                continue;
             const int group_id = MultiCostGroupForPosition(
                PositionGetInteger(POSITION_IDENTIFIER));
             if(group_id <= 0 || MultiFindGroupIndex(group_id) < 0)
               {
                PrintFormat("[COST_INIT_REJECT=MULTI_POSITION_UNMAPPED][POSITION=%I64u]", ticket);
                ReleaseExecutionOwnership();
                return INIT_FAILED;
               }
            }
      }
   g_trade.SetTypeFillingBySymbol(_Symbol);
   if(v_enable == 1)
     {
      if(!GuiCreate())
         Print("GUI initialization failed; EA continues without stopping trade management.");
     }
   if(!EventSetTimer(1))
      Print("Unable to start the initial pending OCO timer.");
   return INIT_SUCCEEDED;
  }

 void OnTradeTransaction(const MqlTradeTransaction &trans,
                         const MqlTradeRequest &request,
                         const MqlTradeResult &result)
   {
    if(g_gui_applied_config.cost_mode
       && trans.type == TRADE_TRANSACTION_DEAL_ADD && trans.deal > 0
       && HistoryDealSelect(trans.deal)
       && HistoryDealGetString(trans.deal, DEAL_SYMBOL) == _Symbol)
      {
       const int group_id = MultiCostGroupForPosition(
          HistoryDealGetInteger(trans.deal, DEAL_POSITION_ID));
       datetime closed_cycle = 0;
       const int closed_group = MultiCostClosedGroupForPosition(
          HistoryDealGetInteger(trans.deal, DEAL_POSITION_ID), closed_cycle);
       if(group_id > 0)
         {
          PrintFormat("[MULTI_COST_DEAL][GROUP=%d][DEAL=%I64u][ENTRY=%d][REASON=%d][PRICE=%.5f][LOTS=%.2f][PROFIT=%.2f][COMMISSION=%.2f][FEE=%.2f][SWAP=%.2f]",
                      group_id, trans.deal,
                      (int)HistoryDealGetInteger(trans.deal, DEAL_ENTRY),
                      (int)HistoryDealGetInteger(trans.deal, DEAL_REASON),
                      HistoryDealGetDouble(trans.deal, DEAL_PRICE),
                      HistoryDealGetDouble(trans.deal, DEAL_VOLUME),
                      HistoryDealGetDouble(trans.deal, DEAL_PROFIT),
                      HistoryDealGetDouble(trans.deal, DEAL_COMMISSION),
                      HistoryDealGetDouble(trans.deal, DEAL_FEE),
                      HistoryDealGetDouble(trans.deal, DEAL_SWAP));
         }
       else if(closed_group > 0)
         {
          PrintFormat("[MULTI_COST_LATE_DEAL][GROUP=%d][CYCLE=%I64d][DEAL=%I64u][POSITION_ID=%I64d][ENTRY=%d][REASON=%d][PRICE=%.5f][LOTS=%.2f][PROFIT=%.2f][COMMISSION=%.2f][FEE=%.2f][SWAP=%.2f][FEE_RESERVE_PER_LOT=%.2f]",
                      closed_group, (long)closed_cycle, trans.deal,
                      HistoryDealGetInteger(trans.deal, DEAL_POSITION_ID),
                      (int)HistoryDealGetInteger(trans.deal, DEAL_ENTRY),
                      (int)HistoryDealGetInteger(trans.deal, DEAL_REASON),
                      HistoryDealGetDouble(trans.deal, DEAL_PRICE),
                      HistoryDealGetDouble(trans.deal, DEAL_VOLUME),
                      HistoryDealGetDouble(trans.deal, DEAL_PROFIT),
                      HistoryDealGetDouble(trans.deal, DEAL_COMMISSION),
                      HistoryDealGetDouble(trans.deal, DEAL_FEE),
                      HistoryDealGetDouble(trans.deal, DEAL_SWAP),
                      g_gui_applied_config.cost_roundtrip_fee_per_lot);
         }
      }
    if(g_gui_applied_config.cost_mode
       && trans.type == TRADE_TRANSACTION_DEAL_ADD && trans.deal > 0
      && HistoryDealSelect(trans.deal)
      && HistoryDealGetString(trans.deal, DEAL_SYMBOL) == _Symbol)
     {
      const long position_id = HistoryDealGetInteger(trans.deal, DEAL_POSITION_ID);
      const long entry_kind = HistoryDealGetInteger(trans.deal, DEAL_ENTRY);
       const bool owned_entry = g_cost_active && entry_kind == DEAL_ENTRY_IN
           && (ulong)HistoryDealGetInteger(trans.deal, DEAL_MAGIC)
               == g_gui_applied_config.magic_number;
       const bool owned_exit = entry_kind == DEAL_ENTRY_OUT
           && CostOwnsPositionId(position_id);
       const datetime closed_cycle = CostClosedCycleForPosition(position_id);
       if(entry_kind == DEAL_ENTRY_OUT
          && ((ulong)HistoryDealGetInteger(trans.deal, DEAL_MAGIC)
                == g_gui_applied_config.magic_number || owned_exit || closed_cycle > 0))
          PrintFormat("[COST_EXIT_DEAL][DEAL=%I64u][POSITION_ID=%I64d][OWNED=%d][ACTIVE=%d][CLOSED_CYCLE=%I64d][REASON=%d][MAGIC=%I64d]",
                      trans.deal, position_id, owned_exit ? 1 : 0,
                      g_cost_active ? 1 : 0, (long)closed_cycle,
                      (int)HistoryDealGetInteger(trans.deal, DEAL_REASON),
                      HistoryDealGetInteger(trans.deal, DEAL_MAGIC));
       if(closed_cycle > 0)
          PrintFormat("[COST_LATE_EXIT][CYCLE=%I64d][DEAL=%I64u][POSITION_ID=%I64d][PROFIT=%.2f][COMMISSION=%.2f][FEE=%.2f][SWAP=%.2f][FEE_RESERVE_PER_LOT=%.2f]",
                      (long)closed_cycle, trans.deal, position_id,
                      HistoryDealGetDouble(trans.deal, DEAL_PROFIT),
                      HistoryDealGetDouble(trans.deal, DEAL_COMMISSION),
                      HistoryDealGetDouble(trans.deal, DEAL_FEE),
                      HistoryDealGetDouble(trans.deal, DEAL_SWAP),
                      g_gui_applied_config.cost_roundtrip_fee_per_lot);
      if(owned_entry)
         CostRememberPositionId(position_id);
       if(g_cost_active && owned_exit
          && HistoryDealGetInteger(trans.deal, DEAL_REASON) == DEAL_REASON_SL
          && HistoryDealGetInteger(trans.deal, DEAL_TIME_MSC)
             > g_cost_consumed_stop_msc)
        {
         g_cost_passive_stop_msc = HistoryDealGetInteger(trans.deal, DEAL_TIME_MSC);
         g_cost_passive_stop_price = HistoryDealGetDouble(trans.deal, DEAL_PRICE);
         g_cost_passive_stop_type = HistoryDealGetInteger(trans.deal, DEAL_TYPE) == DEAL_TYPE_SELL
                                    ? POSITION_TYPE_BUY : POSITION_TYPE_SELL;
         PrintFormat("[COST_EVENT=PASSIVE_SL][DEAL=%I64u][PRICE=%.5f]",
                     trans.deal, g_cost_passive_stop_price);
        }
       if(g_cost_active && (owned_entry || owned_exit)) SaveState();
     }
   if(ConfirmTradeRequestFromTransaction(trans))
      SaveState();
   else if(MultiConfirmTradeRequestFromTransaction(trans))
      for(int index = 0; index < ArraySize(g_multi_groups); index++)
         if(g_multi_groups[index].active)
            MultiSaveGroup(g_multi_groups[index]);
   if(trans.type == TRADE_TRANSACTION_DEAL_ADD && !g_gui_applied_config.cost_mode)
      ProcessInitialPendingFillEvent();
  }

void OnTimer()
  {
   if(g_trade_request_in_flight)
      ConfirmTradeRequestFromVisiblePosition();
   for(int index = 0; index < ArraySize(g_multi_groups); index++)
      if(g_multi_groups[index].active && g_multi_groups[index].request_in_flight)
         MultiConfirmTradeRequestFromVisible(g_multi_groups[index]);
   EmitStrategyWatchdog();
   if(!g_gui_applied_config.cost_mode)
      ProcessInitialPendingFillEvent();
  }

void OnTick()
  {
   if(!AcquireExecutionOwnership())
      return;
   EmitStrategyWatchdog();
   if((g_gui_applied_config.distance_mode == DISTANCE_CANDLE_RANGE
       && g_gui_applied_config.candle_enable_multiple == 1)
      || MultiHasActiveGroups())
      ManageMultipleCandleGroups();
   else
      Manage();
   GuiRenderIfNeeded();
  }

void OnDeinit(const int reason)
  {
   EventKillTimer();
   GuiDestroy();
   if(g_gui_config_initialized)
     {
      string scope_error = "";
      if(HasManagedExposureForMagic(g_gui_applied_config.magic_number))
        {
         if(!RememberManagedScope(g_gui_applied_config.magic_number, scope_error))
            PrintFormat("Failed to retain MT5 scope registry: %s", scope_error);
        }
      else if(!ForgetManagedScopeIfFlat(g_gui_applied_config.magic_number, scope_error))
         PrintFormat("Failed to clear MT5 scope registry: %s", scope_error);
     }
   ReleaseExecutionOwnership();
  }
