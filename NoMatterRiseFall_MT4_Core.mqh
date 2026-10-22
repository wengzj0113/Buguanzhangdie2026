
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
   DISTANCE_BOLLINGER_RANGE = 4, // 当前布林带上下轨宽度按百分比计算止损和止盈
   DISTANCE_ZIGZAG_RANGE = 5, // 已确认 ZigZag 波段高度
   DISTANCE_BOX_RANGE = 6, // M1时间箱体高度
   DISTANCE_BOX_BREAKOUT = 7, // 已确认箱体突破
   DISTANCE_AVERAGE_DOUBLE_CANDLE = 8, // 已收盘K线达到此前N根均长两倍
   DISTANCE_BOLLINGER_EXPANSION = 9 // 已收盘布林带宽度达到此前N根均宽两倍

  };

#ifdef NMR_PROFILE_BOLLINGER_EXPANSION
enum BollingerExpansionDistanceMode
  {
   BOLL_EXP_PERCENT = 0, // 布林带宽度百分比
   BOLL_EXP_FIXED = 1    // 固定止盈止损点数
  };
#endif

enum BoxRangeTimeMode { BOX_RANGE_ROLLING = 0, BOX_RANGE_DAILY_SESSION = 1 };

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
#ifdef NMR_PROFILE_BOLLINGER_EXPANSION
input FirstDirection 首单方向 = FIRST_BUY; // [方向]首单做多或做空
#else
#ifdef NMR_PROFILE_FIXED_DISTANCE
input FirstDirection 首单方向 = FIRST_BUY; // [方向]首单做多或做空
#else
#ifdef NMR_PROFILE_AVERAGE_CANDLE_HEIGHT
input FirstDirection 首单方向 = FIRST_BUY; // [方向]首单做多或做空
#else
#ifdef NMR_PROFILE_BOX_HEIGHT
input FirstDirection 首单方向 = FIRST_BUY; // [方向]首单做多或做空
#else
FirstDirection 首单方向 = FIRST_BUY; // [方向]首单做多或做空
#endif
#endif
#endif
#endif
// 首单方向确定方式：预设方向或按当前价格相对布林带中轨判断
#ifdef NMR_PROFILE_BOLLINGER_EXPANSION
input FirstDirectionMode 首单方向确定方式 = FIRST_DIRECTION_PRESET; // [方向]固定方向或按布林中轨判断
#else
#ifdef NMR_PROFILE_FIXED_DISTANCE
input FirstDirectionMode 首单方向确定方式 = FIRST_DIRECTION_PRESET; // [方向]预设方向或按布林中轨判断
#else
#ifdef NMR_PROFILE_AVERAGE_CANDLE_HEIGHT
input FirstDirectionMode 首单方向确定方式 = FIRST_DIRECTION_PRESET; // [方向]预设方向或按布林中轨判断
#else
#ifdef NMR_PROFILE_BOX_HEIGHT
input FirstDirectionMode 首单方向确定方式 = FIRST_DIRECTION_PRESET; // [方向]预设方向或按布林中轨判断
#else
FirstDirectionMode 首单方向确定方式 = FIRST_DIRECTION_PRESET; // [方向]预设方向或按布林中轨判断
#endif
#endif
#endif
#endif
// 固定距离、平均K线高度和长K线模式均使用用户选择的循环模式
input CycleMode      循环模式 = CYCLE_MODE_1; // [策略]订单组循环方向序列

// ===== 入场信号 =====
// 入场/止盈止损距离模式：固定距离、K线高度、平均K线高度、长K线市价或布林带区间
// 开单方向映射：K线高度模式和布林带触轨模式共用
#ifdef NMR_PROFILE_CANDLE_HEIGHT
input OrderTypeMode  开单方式 = ORDERTYPE_FORWARD; // [开单]信号方向正向或反向
#else
#ifdef NMR_PROFILE_AVERAGE_DOUBLE_CANDLE
input OrderTypeMode  开单方式 = ORDERTYPE_FORWARD; // [开单]正向=阳线多/阴线空，逆向相反
#else
#ifdef NMR_PROFILE_BOLLINGER_RANGE
input OrderTypeMode  开单方式 = ORDERTYPE_FORWARD; // [开单]信号方向正向或反向
#else
#ifdef NMR_PROFILE_ZIGZAG_SWING
input OrderTypeMode  开单方式 = ORDERTYPE_FORWARD; // [开单]信号方向正向或反向
#else
#ifdef NMR_PROFILE_BOX_BREAKOUT
input OrderTypeMode  开单方式 = ORDERTYPE_FORWARD; // [开单]信号方向正向或反向
#else
OrderTypeMode  开单方式 = ORDERTYPE_FORWARD; // [开单]信号方向正向或反向
#endif
#endif
#endif
#endif
#endif
// K线高度模式下同一根当前K线的首单触发次数
#ifdef NMR_PROFILE_CANDLE_HEIGHT
input CandleOrderMode K线开单模式 = KORDER_ONCE_PER_BAR; // [开单]每根K线触发一次或重复触发
#else
CandleOrderMode K线开单模式 = KORDER_ONCE_PER_BAR; // [开单]每根K线触发一次或重复触发
#endif
// K线高度模式是否允许多个订单组并行：0=单组，1=多组
#ifdef NMR_PROFILE_CANDLE_HEIGHT
input int            K线多组 = 0; // [开单]0=单组，1=允许多组
#else
int            K线多组 = 0; // [开单]0=单组，1=允许多组
#endif
input int            篮子数量 = 1; // [开单]1=单篮子，2=反向双篮子，3=止损续配双篮子
// 首单方向判断使用的布林带周期（标准值为20）
#ifdef NMR_PROFILE_BOLLINGER_EXPANSION
input int            布林带周期 = 20; // [布林带]计算周期（K线根数）
#else
#ifdef NMR_PROFILE_FIXED_DISTANCE
input int            布林带周期 = 20; // [布林带]计算周期（K线根数）
#else
#ifdef NMR_PROFILE_AVERAGE_CANDLE_HEIGHT
input int            布林带周期 = 20; // [布林带]计算周期（K线根数）
#else
#ifdef NMR_PROFILE_BOLLINGER_RANGE
input int            布林带周期 = 20; // [布林带]计算周期（K线根数）
#else
#ifdef NMR_PROFILE_BOX_HEIGHT
input int            布林带周期 = 20; // [布林带]计算周期（K线根数）
#else
int            布林带周期 = 20; // [布林带]计算周期（K线根数）
#endif
#endif
#endif
#endif
#endif
// 首单方向判断使用的布林带标准差倍数（标准值为2.0）
#ifdef NMR_PROFILE_BOLLINGER_EXPANSION
input double         布林带标准差 = 2.0; // [布林带]上下轨标准差倍数
#else
#ifdef NMR_PROFILE_FIXED_DISTANCE
input double         布林带标准差 = 2.0; // [布林带]上下轨标准差倍数
#else
#ifdef NMR_PROFILE_AVERAGE_CANDLE_HEIGHT
input double         布林带标准差 = 2.0; // [布林带]上下轨标准差倍数
#else
#ifdef NMR_PROFILE_BOLLINGER_RANGE
input double         布林带标准差 = 2.0; // [布林带]上下轨标准差倍数
#else
#ifdef NMR_PROFILE_BOX_HEIGHT
input double         布林带标准差 = 2.0; // [布林带]上下轨标准差倍数
#else
double         布林带标准差 = 2.0; // [布林带]上下轨标准差倍数
#endif
#endif
#endif
#endif
#endif

// ===== 时间箱体 =====
#ifdef NMR_PROFILE_BOX_HEIGHT
input BoxRangeTimeMode 箱体时间模式 = BOX_RANGE_ROLLING;  // [箱体]滚动回看或每日固定时段
#else
BoxRangeTimeMode 箱体时间模式 = BOX_RANGE_ROLLING;  // [箱体]滚动回看或每日固定时段
#endif
#ifdef NMR_PROFILE_BOX_HEIGHT
input int            箱体回看小时数 = 12;  // [箱体]滚动模式回看小时数
#else
int            箱体回看小时数 = 12;  // [箱体]滚动模式回看小时数
#endif
#ifdef NMR_PROFILE_BOX_HEIGHT
input string         箱体开始时间 = "01:00";  // [箱体]固定时段起始时间（服务器时间）
#else
string         箱体开始时间 = "01:00";  // [箱体]固定时段起始时间（服务器时间）
#endif
#ifdef NMR_PROFILE_BOX_HEIGHT
input string         箱体结束时间 = "12:00";  // [箱体]固定时段结束时间（服务器时间）
#else
string         箱体结束时间 = "12:00";  // [箱体]固定时段结束时间（服务器时间）
#endif
#ifdef NMR_PROFILE_BOX_HEIGHT
input int            箱体最小高度 = 500;  // [箱体]允许的最小高度（点）
#else
int            箱体最小高度 = 500;  // [箱体]允许的最小高度（点）
#endif
#ifdef NMR_PROFILE_BOX_HEIGHT
input int            箱体最大高度 = 1000;  // [箱体]允许的最大高度（点）
#else
int            箱体最大高度 = 1000;  // [箱体]允许的最大高度（点）
#endif

// ===== 箱体确认突破 =====
#ifdef NMR_PROFILE_BOX_BREAKOUT
input ENUM_TIMEFRAMES 箱体识别周期 = PERIOD_CURRENT; // [箱体突破]识别周期；当前图表周期
#else
ENUM_TIMEFRAMES 箱体识别周期 = PERIOD_CURRENT; // [箱体突破]识别周期；当前图表周期
#endif
#ifdef NMR_PROFILE_BOX_BREAKOUT
input int            箱体观察窗口K线数 = 60; // [箱体突破]已收盘K线窗口
#else
int            箱体观察窗口K线数 = 60; // [箱体突破]已收盘K线窗口
#endif
#ifdef NMR_PROFILE_BOX_BREAKOUT
input int            箱体ATR周期 = 14; // [箱体突破]ATR计算周期
#else
int            箱体ATR周期 = 14; // [箱体突破]ATR计算周期
#endif
#ifdef NMR_PROFILE_BOX_BREAKOUT
input double         箱体触碰ATR倍数 = 0.2; // [箱体突破]边沿触碰容差
#else
double         箱体触碰ATR倍数 = 0.2; // [箱体突破]边沿触碰容差
#endif
#ifdef NMR_PROFILE_BOX_BREAKOUT
input int            箱体上沿最少触碰 = 2; // [箱体突破]上沿最少触碰数
#else
int            箱体上沿最少触碰 = 2; // [箱体突破]上沿最少触碰数
#endif
#ifdef NMR_PROFILE_BOX_BREAKOUT
input int            箱体下沿最少触碰 = 2; // [箱体突破]下沿最少触碰数
#else
int            箱体下沿最少触碰 = 2; // [箱体突破]下沿最少触碰数
#endif
#ifdef NMR_PROFILE_BOX_BREAKOUT
input int            箱体最少完整往返 = 2; // [箱体突破]最少完整往返数
#else
int            箱体最少完整往返 = 2; // [箱体突破]最少完整往返数
#endif
#ifdef NMR_PROFILE_BOX_BREAKOUT
input int            箱体同侧触碰间隔 = 3; // [箱体突破]同侧事件最少间隔K线
#else
int            箱体同侧触碰间隔 = 3; // [箱体突破]同侧事件最少间隔K线
#endif
#ifdef NMR_PROFILE_BOX_BREAKOUT
input int            箱体突破最小宽度 = 500; // [箱体突破]最小宽度（点）
#else
int            箱体突破最小宽度 = 500; // [箱体突破]最小宽度（点）
#endif
#ifdef NMR_PROFILE_BOX_BREAKOUT
input int            箱体突破最大宽度 = 1000; // [箱体突破]最大宽度（点）
#else
int            箱体突破最大宽度 = 1000; // [箱体突破]最大宽度（点）
#endif
#ifdef NMR_PROFILE_BOX_BREAKOUT
input double         箱体突破缓冲ATR倍数 = 0.2; // [箱体突破]突破确认缓冲
#else
double         箱体突破缓冲ATR倍数 = 0.2; // [箱体突破]突破确认缓冲
#endif


#ifdef NMR_PROFILE_AVERAGE_DOUBLE_CANDLE
input group ">>>> K线长度触发";
input int 均值比较K线根数 = 20; // [信号]用于计算平均K线长度的根数
input double 均值触发倍数 = 2.0; // [信号]当前K线长度达到前N根平均长度×此倍数时开单
input double 信号K线距离百分比 = 50.0; // [止盈止损]距离=信号K线长度×此百分比
#endif

// ===== 手数与风险 =====
#ifdef NMR_PROFILE_BOLLINGER_EXPANSION
input int 带宽比较K线根数 = 20; // [信号]用于计算平均带宽的根数
input double 带宽触发倍数 = 2.0; // [信号]当前带宽达到前N根平均带宽×此倍数时开单
input BollingerExpansionDistanceMode 带宽距离模式 = BOLL_EXP_PERCENT; // [止盈止损]按带宽百分比或固定点数计算
input double 带宽距离百分比 = 25.0; // [止盈止损]距离=信号K线带宽×此百分比
#endif

// 首单手数
input double         首单手数 = 0.01; // [手数]首轮首单交易手数
// 首单手数倍数；订单组止损后下一组首单手数乘此倍数
input double         首单手数倍数 = 1.0; // [手数]类型1止损后首单手数倍数
// 止损后首单手数计算类型：1=累计订单组总手数，2=上一组首单手数
input int            止损首单类型 = 2; // [手数]止损后算法：1累计组手数，2首单倍数，3固定手数
// 首单手数类型2的倍数
input double         首单类型2倍数 = 2.0; // [手数]类型2使用的上一组首单倍数
// 止损首单类型3使用的固定手数
input double         止损首单固定手数 = 0.01; // [手数]类型3止损后使用的固定手数
// 止损后最多切换到下一订单组的次数；达到后清理并重新开始
input int            最大反手次数 = 5; // [风险]止损后最多更换订单组次数
// 首单允许的最大点差，单位为 points；0 表示不限制
input int            最大首单点差 = 0; // [风险]首单最大点差（点）；0=不限

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

// ===== 止盈止损距离 =====
// 固定距离模式下的止损点数
#ifdef NMR_PROFILE_BOLLINGER_EXPANSION
input int            固定止损距离 = 500; // [距离]固定模式止损距离（点）
#else
#ifdef NMR_PROFILE_FIXED_DISTANCE
input int            固定止损距离 = 500; // [距离]固定模式止损距离（点）
#else
#ifdef NMR_PROFILE_LONG_CANDLE
input int            固定止损距离 = 500; // [距离]固定模式止损距离（点）
#else
int            固定止损距离 = 500; // [距离]固定模式止损距离（点）
#endif
#endif
#endif
// 固定距离模式下的止盈点数
#ifdef NMR_PROFILE_BOLLINGER_EXPANSION
input int            固定止盈距离 = 500; // [距离]固定模式止盈距离（点）
#else
#ifdef NMR_PROFILE_FIXED_DISTANCE
input int            固定止盈距离 = 500; // [距离]固定模式止盈距离（点）
#else
#ifdef NMR_PROFILE_LONG_CANDLE
input int            固定止盈距离 = 500; // [距离]固定模式止盈距离（点）
#else
int            固定止盈距离 = 500; // [距离]固定模式止盈距离（点）
#endif
#endif
#endif
// 布林带区间模式下，带宽乘以下述百分比得到止损点数
#ifdef NMR_PROFILE_BOLLINGER_RANGE
input double         布林带止损百分比 = 25.0; // [距离]布林带宽度对应的止损百分比
#else
double         布林带止损百分比 = 25.0; // [距离]布林带宽度对应的止损百分比
#endif
// 布林带模式下，止盈点数与止损点数的比值
#ifdef NMR_PROFILE_BOLLINGER_RANGE
input double         布林带盈亏比 = 1.0; // [距离]止盈距离÷止损距离
#else
double         布林带盈亏比 = 1.0; // [距离]止盈距离÷止损距离
#endif
// 布林带区间模式下，止损点数的允许范围（含边界）
#ifdef NMR_PROFILE_BOLLINGER_RANGE
input int            布林带最小止损距离 = 200; // [距离]止损最小点数
#else
int            布林带最小止损距离 = 200; // [距离]止损最小点数
#endif
#ifdef NMR_PROFILE_BOLLINGER_RANGE
input int            布林带最大止损距离 = 1000; // [距离]止损最大点数
#else
int            布林带最大止损距离 = 1000; // [距离]止损最大点数
#endif
// 上一根K线允许使用的最小高度点数
#ifdef NMR_PROFILE_CANDLE_HEIGHT
input int            K线最小高度 = 500; // [距离]上一根K线最小高度（点）
#else
int            K线最小高度 = 500; // [距离]上一根K线最小高度（点）
#endif
// 上一根K线允许使用的最大高度点数
#ifdef NMR_PROFILE_CANDLE_HEIGHT
input int            K线最大高度 = 1000; // [距离]上一根K线最大高度（点）
#else
int            K线最大高度 = 1000; // [距离]上一根K线最大高度（点）
#endif
// 平均K线模式使用的已完成K线根数
#ifdef NMR_PROFILE_AVERAGE_CANDLE_HEIGHT
input int            平均K线根数 = 20; // [距离]计算平均高度的已完成K线数
#else
int            平均K线根数 = 20; // [距离]计算平均高度的已完成K线数
#endif
// 平均K线高度计算的止损倍数
#ifdef NMR_PROFILE_AVERAGE_CANDLE_HEIGHT
input double         平均止损倍数 = 2.0; // [距离]平均K线高度止损倍数
#else
double         平均止损倍数 = 2.0; // [距离]平均K线高度止损倍数
#endif
// 平均K线模式中止盈距离相对止损距离的倍数
#ifdef NMR_PROFILE_AVERAGE_CANDLE_HEIGHT
input double         平均止盈倍数 = 2.0; // [距离]止盈距离相对止损距离倍数
#else
double         平均止盈倍数 = 2.0; // [距离]止盈距离相对止损距离倍数
#endif
#ifdef NMR_PROFILE_ZIGZAG_SWING
input int            ZigZag深度 = 12; // [距离]确认波段转折的深度
#else
int            ZigZag深度 = 12; // [距离]确认波段转折的深度
#endif
#ifdef NMR_PROFILE_ZIGZAG_SWING
input int            ZigZag偏差 = 5; // [距离]波段转折的最小偏差
#else
int            ZigZag偏差 = 5; // [距离]波段转折的最小偏差
#endif
#ifdef NMR_PROFILE_ZIGZAG_SWING
input int            ZigZag回退 = 3; // [距离]转折点间最小K线数
#else
int            ZigZag回退 = 3; // [距离]转折点间最小K线数
#endif
#ifdef NMR_PROFILE_ZIGZAG_SWING
input int            ZigZag距离最小值 = 100; // [距离]波段最小距离（点）
#else
int            ZigZag距离最小值 = 100; // [距离]波段最小距离（点）
#endif
#ifdef NMR_PROFILE_ZIGZAG_SWING
input int            ZigZag距离最大值 = 10000; // [距离]波段最大距离（点）
#else
int            ZigZag距离最大值 = 10000; // [距离]波段最大距离（点）
#endif
#ifdef NMR_PROFILE_ZIGZAG_SWING
input double         ZigZag止损百分比 = 100.0; // [距离]波段高度对应的止损百分比
#else
double         ZigZag止损百分比 = 100.0; // [距离]波段高度对应的止损百分比
#endif
#ifdef NMR_PROFILE_ZIGZAG_SWING
input double         ZigZag止盈倍数 = 1.0; // [距离]止盈距离相对止损距离倍数
#else
double         ZigZag止盈倍数 = 1.0; // [距离]止盈距离相对止损距离倍数
#endif

// ===== 订单识别 =====
// 用于识别本EA订单的唯一编号
input int            订单识别编号 = NMR_MAGIC_DEFAULT; // [订单]识别本EA订单的编号
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

// 内部兼容映射：以下名称不显示在参数设置中，仅用于保持既有逻辑代码兼容。
#define InpFirstDirection 首单方向
#define InpCycleMode 循环模式
#define InpDistanceMode NMR_FIXED_DISTANCE_MODE
#define ordertype 开单方式
#define Korder_type K线开单模式
#define InpTakeProfitMode 止盈移动模式
#define InpInitialLots 首单手数
#define kline_enable_multiple K线多组
#define FirstOrderLotType 止损首单类型
#define FirstOrderMult 首单类型2倍数
#define FirstOrderFixedLots 止损首单固定手数
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
struct BoxBreakoutState
  {
   bool valid;
   double upper;
   double lower;
   int width_points;
   double atr;
   double breakout_buffer;
   datetime confirmation_time;
   datetime last_processed_time;
   int upper_breakout_count;
   int lower_breakout_count;
   int age_bars;
   bool signal_pending;
   long signal_id;
   datetime signal_bar_time;
   int signal_direction;
  };
BoxBreakoutState g_box_state;
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
int    g_start_operation_minutes[MAX_OPERATION_WINDOWS];
int    g_end_operation_minutes[MAX_OPERATION_WINDOWS];
bool   g_initial_signal_state_loaded = false;
bool   g_signal_consumed = false;
long   g_signal_id = 0;
datetime g_signal_bar_time = 0;
int    g_signal_direction = OP_BUY;
bool   g_bollinger_touch_state_loaded = false;
bool   g_bollinger_touch_armed = true;
long   g_bollinger_touch_sequence = 0;

void ClearGridOrderTicketCache()
  {
   for(int level = 0; level < MAX_GRID_COUNT; level++)
     {
      g_grid_order_tickets[level] = -1;
      g_favorable_grid_order_tickets[level] = -1;
     }
  }

string LegacyStatePrefix()
  {
   return "NMR." + IntegerToString(AccountNumber())
          + "." + Symbol() + "." + IntegerToString(InpMagicNumber);
  }

string StatePrefix()
  {
   return LegacyStatePrefix() + ".p" + IntegerToString(NMR_FIXED_PROFILE_ID)
          + ".v1";
  }

bool HasCurrentProfileState()
  {
   const string prefix = StatePrefix() + ".";
   for(int index = GlobalVariablesTotal() - 1; index >= 0; index--)
      if(StringFind(GlobalVariableName(index), prefix) == 0)
         return true;
   return false;
  }

bool HasUnownedStateForMagic()
  {
   const string prefix = LegacyStatePrefix() + ".";
   const string owned_prefix = StatePrefix() + ".";
   for(int index = GlobalVariablesTotal() - 1; index >= 0; index--)
     {
      const string name = GlobalVariableName(index);
      if(StringFind(name, prefix) == 0 && StringFind(name, owned_prefix) != 0)
         return true;
     }
   return false;
  }

bool HasManagedExposureForMagic()
  {
   for(int index = OrdersTotal() - 1; index >= 0; index--)
     {
      if(!OrderSelect(index, SELECT_BY_POS, MODE_TRADES)
         || OrderSymbol() != Symbol() || OrderMagicNumber() != InpMagicNumber)
         continue;
      const int order_type = OrderType();
      if(order_type == OP_BUY || order_type == OP_SELL
         || order_type == OP_BUYLIMIT || order_type == OP_SELLLIMIT
         || order_type == OP_BUYSTOP || order_type == OP_SELLSTOP)
         return true;
     }
   return false;
  }

bool ValidateFixedProfileStartupState(string &error)
  {
   error = "";
   if(InpMagicNumber <= 0)
     {
      error = "订单识别编号必须为正数。";
      return false;
     }
   const bool has_state = HasCurrentProfileState();
   if(HasUnownedStateForMagic())
     {
      error = "该订单识别编号存在旧版或其他固定策略的持久状态；请先确认空仓并清理状态。";
      return false;
     }
   if(HasManagedExposureForMagic() && !has_state)
     {
      error = "发现没有本固定策略状态匹配的持仓或挂单；EA拒绝认领或修改这些订单。";
      return false;
     }
   if(has_state)
     {
      const string prefix = StatePrefix();
      if(!GlobalVariableCheck(prefix + ".owner.profile")
         || !GlobalVariableCheck(prefix + ".owner.schema")
         || (int)MathRound(GlobalVariableGet(prefix + ".owner.profile"))
            != NMR_FIXED_PROFILE_ID
         || (int)MathRound(GlobalVariableGet(prefix + ".owner.schema")) != 1)
        {
         error = "固定策略状态身份或版本不匹配；EA拒绝恢复该订单组。";
         return false;
        }
     }
   return true;
  }

bool PersistFixedProfileStateOwner()
  {
   const string prefix = StatePrefix();
   return GlobalVariableSet(prefix + ".owner.profile", NMR_FIXED_PROFILE_ID) != 0
          && GlobalVariableSet(prefix + ".owner.schema", 1.0) != 0;
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
   GlobalVariableSet(prefix + ".owner.profile", NMR_FIXED_PROFILE_ID);
   GlobalVariableSet(prefix + ".owner.schema", 1.0);
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

bool GetBoxRangePoints(int &range_points)
  {
   range_points = 0;
   if(箱体最小高度 <= 0 || 箱体最大高度 < 箱体最小高度
      || Point <= 0.0)
      return false;
   const datetime now = TimeCurrent();
   datetime start_time = 0;
   datetime end_time = now - (now % 60) + 60;
   if(箱体时间模式 == BOX_RANGE_ROLLING)
     {
      if(箱体回看小时数 <= 0 || 箱体回看小时数 > 720)
         return false;
      start_time = now - 箱体回看小时数 * 3600;
      start_time -= start_time % 60;
     }
   else if(箱体时间模式 == BOX_RANGE_DAILY_SESSION)
     {
      const int start_minutes = ParseTimeMinutes(箱体开始时间);
      const int end_minutes = ParseTimeMinutes(箱体结束时间);
      if(start_minutes < 0 || end_minutes < 0 || start_minutes == end_minutes)
         return false;
      string day_text = TimeToString(now, TIME_DATE);
      datetime day_start = StrToTime(day_text);
      datetime session_start = day_start + start_minutes * 60;
      datetime session_end = day_start + end_minutes * 60;
      if(end_minutes <= start_minutes) session_end += 86400;
      if(now < session_end)
        {
         session_start -= 86400;
         session_end -= 86400;
        }
      start_time = session_start;
      end_time = session_end;
     }
   else return false;
   const int first_shift = iBarShift(Symbol(), PERIOD_M1, start_time, false);
   const int end_shift = iBarShift(Symbol(), PERIOD_M1, end_time - 1, false);
   if(first_shift < 0 || end_shift < 0 || first_shift < end_shift)
      return false;
   if(iTime(Symbol(), PERIOD_M1, first_shift) > start_time
      || iTime(Symbol(), PERIOD_M1, end_shift) >= end_time
      || iTime(Symbol(), PERIOD_M1, end_shift) + 60 < end_time)
      return false;
   double highest = -DBL_MAX;
   double lowest = DBL_MAX;
   for(int shift = first_shift; shift >= end_shift; shift--)
     {
      const datetime bar_time = iTime(Symbol(), PERIOD_M1, shift);
      if(bar_time < start_time || bar_time >= end_time)
         continue;
      highest = MathMax(highest, iHigh(Symbol(), PERIOD_M1, shift));
      lowest = MathMin(lowest, iLow(Symbol(), PERIOD_M1, shift));
     }
   if(highest <= lowest || lowest == DBL_MAX)
      return false;
   range_points = (int)MathRound((highest - lowest) / Point);
   return range_points >= 箱体最小高度 && range_points <= 箱体最大高度;
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
   if(最大首单点差 < 0)
      return false;
   if(最大首单点差 == 0)
      return true;
   RefreshRates();
   if(Point <= 0.0 || Bid <= 0.0 || Ask < Bid)
      return false;
   const double spread_points = MathCeil((Ask - Bid) / Point);
   return MathIsValidNumber(spread_points)
          && spread_points <= (double)最大首单点差;
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

#ifdef NMR_PROFILE_AVERAGE_DOUBLE_CANDLE
bool GetAverageDoubleCandleSignal(int &first_direction,
                                  int &stop_points, int &take_profit_points)
  {
   const int count = 均值比较K线根数;
   const double trigger_multiplier = 均值触发倍数;
   const double distance_percent = 信号K线距离百分比;
   if(count < 1 || count > 10000 || _Point <= 0.0
      || !MathIsValidNumber(trigger_multiplier) || trigger_multiplier <= 0.0
      || !MathIsValidNumber(distance_percent) || distance_percent <= 0.0)
      return false;
   MqlRates rates[];
   ArraySetAsSeries(rates, false);
   // CopyRates stores oldest first: indices 0..N-1 are K(N+1)..K2;
   // index N is K1. The forming candle is never copied.
   if(CopyRates(_Symbol, _Period, 1, count + 1, rates) != count + 1)
      return false;
   if(rates[count].time != iTime(_Symbol, _Period, 1))
      return false;
   double total_range = 0.0;
   for(int index = 0; index <= count; index++)
     {
      if(rates[index].time <= 0
         || !MathIsValidNumber(rates[index].open)
         || !MathIsValidNumber(rates[index].close)
         || !MathIsValidNumber(rates[index].high)
         || !MathIsValidNumber(rates[index].low)
         || rates[index].low <= 0.0 || rates[index].high <= rates[index].low
         || rates[index].open < rates[index].low || rates[index].open > rates[index].high
         || rates[index].close < rates[index].low || rates[index].close > rates[index].high)
         return false;
      if(index < count)
         total_range += rates[index].high - rates[index].low;
     }
   const double signal_range = rates[count].high - rates[count].low;
   const double average_range = total_range / count;
   // Tolerance only removes floating point subtraction noise (< one millionth point).
   if(!MathIsValidNumber(average_range) || average_range <= 0.0
      || signal_range + _Point * 0.000001 < trigger_multiplier * average_range)
      return false;
   bool bullish_signal = false;
   if(rates[count].close > rates[count].open)
      bullish_signal = true;
   else if(rates[count].close < rates[count].open)
      bullish_signal = false;
   else
      return false;
   if(开单方式 == ORDERTYPE_FORWARD)
      first_direction = bullish_signal ? OP_BUY : OP_SELL;
   else if(开单方式 == ORDERTYPE_REVERSE)
      first_direction = bullish_signal ? OP_SELL : OP_BUY;
   else
      return false;
   const double distance_points = signal_range / _Point * distance_percent / 100.0;
   if(!MathIsValidNumber(distance_points) || distance_points > 2147483647.0
      || MathRound(distance_points) < 1.0)
      return false;
   stop_points = (int)MathRound(distance_points);
   take_profit_points = stop_points;
   static datetime logged_signal_bar = 0;
   if(logged_signal_bar != rates[count].time)
     {
      PrintFormat("[AVERAGE_DOUBLE_CANDLE_SIGNAL][BAR=%s][N=%d][MULTIPLIER=%.8f][RANGE_POINTS=%.10f][AVERAGE_POINTS=%.10f][DIRECTION=%d][PERCENT=%.8f][DISTANCE_POINTS=%d]",
                  TimeToString(rates[count].time, TIME_DATE|TIME_MINUTES), count, trigger_multiplier,
                  signal_range / _Point, average_range / _Point,
                  first_direction, distance_percent, stop_points);
      logged_signal_bar = rates[count].time;
     }
   return true;
  }
#endif

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

long BuildSignalId(const datetime bar_time, const int direction)
  {
   const long safe_bar = bar_time > 0 ? (long)bar_time : (long)TimeCurrent();
   return safe_bar * 10 + direction;
  }

void LoadBollingerTouchState()
  {
   if(g_bollinger_touch_state_loaded)
      return;
   const string prefix = StatePrefix();
   const bool has_saved_config = GlobalVariableCheck(prefix + ".bollperiod")
                                 && GlobalVariableCheck(prefix + ".bolldeviation")
                                 && GlobalVariableCheck(prefix + ".bollorder");
   if(GlobalVariableCheck(prefix + ".bollarmed"))
      g_bollinger_touch_armed = GlobalVariableGet(prefix + ".bollarmed") > 0.5;
   if(GlobalVariableCheck(prefix + ".bollsequence"))
      g_bollinger_touch_sequence = (long)MathRound(
         GlobalVariableGet(prefix + ".bollsequence"));
   if(has_saved_config
      && ((int)MathRound(GlobalVariableGet(prefix + ".bollperiod")) != 布林带周期
          || MathAbs(GlobalVariableGet(prefix + ".bolldeviation") - 布林带标准差) > 0.0000001
          || (int)MathRound(GlobalVariableGet(prefix + ".bollorder")) != 开单方式))
      g_bollinger_touch_armed = true;
   g_bollinger_touch_state_loaded = true;
  }

void SaveBollingerTouchState()
  {
   const string prefix = StatePrefix();
   GlobalVariableSet(prefix + ".bollarmed", g_bollinger_touch_armed ? 1.0 : 0.0);
   GlobalVariableSet(prefix + ".bollsequence", (double)g_bollinger_touch_sequence);
   GlobalVariableSet(prefix + ".bollperiod", 布林带周期);
   GlobalVariableSet(prefix + ".bolldeviation", 布林带标准差);
   GlobalVariableSet(prefix + ".bollorder", 开单方式);
   GlobalVariablesFlush();
  }

void CommitBollingerTouchSignal(const datetime bar_time, const int direction,
                               const long signal_id)
  {
   if(InpDistanceMode != DISTANCE_BOLLINGER_RANGE)
      return;
   LoadBollingerTouchState();
   long next_sequence = g_bollinger_touch_sequence + 1;
   if(next_sequence <= 0)
      next_sequence = 1;
   const long expected_id = BuildSignalId(bar_time, direction) * 100
                            + next_sequence % 99 + 1;
   if(g_bollinger_touch_armed && expected_id == signal_id)
     {
      g_bollinger_touch_sequence = next_sequence;
      g_bollinger_touch_armed = false;
      SaveBollingerTouchState();
     }
  }

void LoadInitialSignalState()
  {
   if(g_initial_signal_state_loaded)
      return;
   const string prefix = StatePrefix();
   if(GlobalVariableCheck(prefix + ".signalconsumed"))
      g_signal_consumed = GlobalVariableGet(prefix + ".signalconsumed") > 0.5;
   if(GlobalVariableCheck(prefix + ".signalid"))
      g_signal_id = (long)MathRound(GlobalVariableGet(prefix + ".signalid"));
   if(GlobalVariableCheck(prefix + ".signalbar"))
      g_signal_bar_time = (datetime)MathRound(GlobalVariableGet(prefix + ".signalbar"));
   if(GlobalVariableCheck(prefix + ".signaldirection"))
      g_signal_direction = (int)MathRound(GlobalVariableGet(prefix + ".signaldirection"));
   g_initial_signal_state_loaded = true;
  }

bool PrepareInitialSignal(const datetime requested_bar_time, const int direction,
                          const long explicit_signal_id = 0)
  {
   if(direction != OP_BUY && direction != OP_SELL)
      return false;
   LoadInitialSignalState();
   datetime bar_time = requested_bar_time > 0
                       ? requested_bar_time : iTime(Symbol(), Period(), 0);
   if(bar_time <= 0)
      bar_time = TimeCurrent();
#ifdef NMR_PROFILE_BOLLINGER_EXPANSION
   // A closed-bar width signal is consumed once, even when its live direction flips.
   if(g_signal_consumed && g_signal_bar_time == bar_time)
      return false;
#endif
   const long signal_id = explicit_signal_id > 0
                          ? explicit_signal_id : BuildSignalId(bar_time, direction);
   if(g_signal_consumed && g_signal_id == signal_id
      && g_signal_bar_time == bar_time && g_signal_direction == direction)
      return false;

   g_signal_consumed = true;
   g_signal_id = signal_id;
   g_signal_bar_time = bar_time;
   g_signal_direction = direction;
   CommitBollingerTouchSignal(bar_time, direction, signal_id);
   const string prefix = StatePrefix();
   GlobalVariableSet(prefix + ".signalconsumed", 1.0);
   GlobalVariableSet(prefix + ".signalid", (double)signal_id);
   GlobalVariableSet(prefix + ".signalbar", (double)bar_time);
   GlobalVariableSet(prefix + ".signaldirection", (double)direction);
   GlobalVariablesFlush();
   return true;
  }

bool IsInitialSignalConsumed(const datetime requested_bar_time, const int direction,
                             const long explicit_signal_id = 0)
  {
   if(direction != OP_BUY && direction != OP_SELL)
      return false;
   LoadInitialSignalState();
   datetime bar_time = requested_bar_time > 0
                       ? requested_bar_time : iTime(Symbol(), Period(), 0);
   if(bar_time <= 0)
      bar_time = TimeCurrent();
#ifdef NMR_PROFILE_BOLLINGER_EXPANSION
   // A closed-bar width signal is consumed once, even when its live direction flips.
   if(g_signal_consumed && g_signal_bar_time == bar_time)
      return true;
#endif
   const long signal_id = explicit_signal_id > 0
                          ? explicit_signal_id : BuildSignalId(bar_time, direction);
   return g_signal_consumed && g_signal_id == signal_id
          && g_signal_bar_time == bar_time && g_signal_direction == direction;
  }

#ifdef NMR_PROFILE_BOLLINGER_EXPANSION
bool GetBollingerExpansionSignal(int &stop_points, int &take_profit_points)
  {
   const int count = 带宽比较K线根数;
   const double trigger_multiplier = 带宽触发倍数;
   const int period = 布林带周期;
   const double deviation = 布林带标准差;
   const BollingerExpansionDistanceMode distance_mode = 带宽距离模式;
   const double distance_percent = 带宽距离百分比;
   const int fixed_stop = 固定止损距离;
   const int fixed_take_profit = 固定止盈距离;
   if(count < 1 || count > 10000 || period < 2 || period > 10000
      || !MathIsValidNumber(trigger_multiplier) || trigger_multiplier <= 0.0
      || !MathIsValidNumber(deviation) || deviation <= 0.0 || _Point <= 0.0
      || Bars(_Symbol, _Period) < period + count + 1)
      return false;
   const datetime signal_bar = iTime(_Symbol, _Period, 1);
   if(signal_bar <= 0) return false;
   double widths[];
   ArrayResize(widths, count + 1);
   // Match CopyBuffer physical order: oldest comparison first, K1 at index N.
   for(int index = 0; index <= count; index++)
     {
      const int shift = count + 1 - index;
      const double upper = iBands(_Symbol, _Period, period, deviation, 0,
                                   PRICE_CLOSE, MODE_UPPER, shift);
      const double lower = iBands(_Symbol, _Period, period, deviation, 0,
                                   PRICE_CLOSE, MODE_LOWER, shift);
      if(!MathIsValidNumber(upper) || !MathIsValidNumber(lower)
         || upper == EMPTY_VALUE || lower == EMPTY_VALUE || upper <= lower)
         return false;
      widths[index] = upper - lower;
     }
   if(signal_bar != iTime(_Symbol, _Period, 1)) return false;
   double total_width = 0.0;
   for(int index = 0; index < count; index++) total_width += widths[index];
   const double signal_width = widths[count];
   const double average_width = total_width / count;
   if(!MathIsValidNumber(average_width) || average_width <= 0.0
      || signal_width + _Point * 0.000001 < trigger_multiplier * average_width)
      return false;
   if(distance_mode == BOLL_EXP_FIXED)
     {
      if(fixed_stop < 1 || fixed_take_profit < 1) return false;
      stop_points = fixed_stop;
      take_profit_points = fixed_take_profit;
     }
   else if(distance_mode == BOLL_EXP_PERCENT)
     {
      if(!MathIsValidNumber(distance_percent) || distance_percent <= 0.0) return false;
      const double points = signal_width / _Point * distance_percent / 100.0;
      if(!MathIsValidNumber(points) || points > 2147483647.0
         || MathRound(points) < 1.0) return false;
      stop_points = (int)MathRound(points);
      take_profit_points = stop_points;
     }
   else return false;
   static datetime logged_signal_bar = 0;
   if(logged_signal_bar != signal_bar)
     {
      PrintFormat("[BOLLINGER_EXPANSION_SIGNAL][BAR=%s][N=%d][MULTIPLIER=%.8f][WIDTH_POINTS=%.10f][AVERAGE_POINTS=%.10f][MODE=%d][PERCENT=%.8f][SL_POINTS=%d][TP_POINTS=%d]",
                  TimeToString(signal_bar, TIME_DATE|TIME_MINUTES), count, trigger_multiplier,
                  signal_width / _Point, average_width / _Point,
                  (int)distance_mode, distance_percent, stop_points, take_profit_points);
      logged_signal_bar = signal_bar;
     }
   return true;
  }
#endif

bool GetBollingerTouchDirection(int &first_direction, datetime &signal_bar_time,
                                long &signal_id)
  {
   signal_bar_time = 0;
   signal_id = 0;
   if(布林带周期 <= 0 || 布林带标准差 <= 0.0
      || iBars(Symbol(), Period()) < 布林带周期)
      return false;
   RefreshRates();
   const double upper = iBands(Symbol(), Period(), 布林带周期,
                               布林带标准差, 0, PRICE_CLOSE,
                               MODE_UPPER, 0);
   const double lower = iBands(Symbol(), Period(), 布林带周期,
                               布林带标准差, 0, PRICE_CLOSE,
                               MODE_LOWER, 0);
   if(!MathIsValidNumber(upper) || !MathIsValidNumber(lower)
      || upper == EMPTY_VALUE || lower == EMPTY_VALUE || upper <= lower
      || Bid <= 0.0 || Point <= 0.0)
      return false;
   LoadBollingerTouchState();
   const double tolerance = Point * 0.5;
   if(Bid > lower + tolerance && Bid < upper - tolerance)
     {
      if(!g_bollinger_touch_armed)
        {
         g_bollinger_touch_armed = true;
         SaveBollingerTouchState();
        }
      return false;
     }
   if(!g_bollinger_touch_armed)
      return false;
   if(Bid >= upper - tolerance)
     {
      if(开单方式 == ORDERTYPE_FORWARD)
         first_direction = OP_BUY;
      else if(开单方式 == ORDERTYPE_REVERSE)
         first_direction = OP_SELL;
      else
         return false;
     }
   else if(Bid <= lower + tolerance)
     {
      if(开单方式 == ORDERTYPE_FORWARD)
         first_direction = OP_SELL;
      else if(开单方式 == ORDERTYPE_REVERSE)
         first_direction = OP_BUY;
      else
         return false;
     }
   else
      return false;
   signal_bar_time = iTime(Symbol(), Period(), 0);
   if(signal_bar_time <= 0)
      signal_bar_time = TimeCurrent();
   long next_sequence = g_bollinger_touch_sequence + 1;
   if(next_sequence <= 0)
      next_sequence = 1;
   signal_id = BuildSignalId(signal_bar_time, first_direction) * 100
               + next_sequence % 99 + 1;
   return true;
  }

bool GetBollingerDistancePoints(int &stop_loss_points, int &take_profit_points)
  {
   if(布林带周期 <= 0 || 布林带标准差 <= 0.0
      || !MathIsValidNumber(布林带止损百分比) || 布林带止损百分比 <= 0.0
      || !MathIsValidNumber(布林带盈亏比) || 布林带盈亏比 <= 0.0)
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
   const double distance = width_points * 布林带止损百分比 / 100.0;
   if(!MathIsValidNumber(distance) || distance > 2147483647.0)
      return false;
   stop_loss_points = (int)MathRound(distance);
   const double take_profit = stop_loss_points * 布林带盈亏比;
   if(!MathIsValidNumber(take_profit) || take_profit > 2147483647.0)
      return false;
   take_profit_points = (int)MathRound(take_profit);
   return stop_loss_points >= 布林带最小止损距离
          && stop_loss_points <= 布林带最大止损距离;
  }

bool GetZigZagDistancePoints(int &stop_loss_points, int &take_profit_points,
                            double &breakout_high, double &breakout_low)
  {
   // 标准 ZigZag 会回算最近三个极值，只使用第 4、5 个极值构成的波段。
   int found = 0;
   double first = 0.0;
   double second = 0.0;
   int first_kind = 0;
   int second_kind = 0;
   const int bars = MathMin(iBars(Symbol(), Period()), 2000);
   for(int shift = 1; shift < bars && found < 5; shift++)
     {
      const double price = iCustom(Symbol(), Period(), "ZigZag",
                                   ZigZag深度, ZigZag偏差, ZigZag回退, 0, shift);
      if(!MathIsValidNumber(price) || price == EMPTY_VALUE || price <= 0.0)
         continue;
      const double high = iHigh(Symbol(), Period(), shift);
      const double low = iLow(Symbol(), Period(), shift);
      const int kind = MathAbs(price - high) <= Point * 0.5 ? 1
                       : (MathAbs(price - low) <= Point * 0.5 ? -1 : 0);
      if(kind == 0)
         return false;
      found++;
      if(found == 4) { first = price; first_kind = kind; }
      if(found == 5) { second = price; second_kind = kind; }
     }
   if(found < 5 || first_kind == second_kind
      || (first_kind == 1 && first <= second)
      || (first_kind == -1 && first >= second))
      return false;
   const double raw = MathAbs(first - second) / Point;
   if(!MathIsValidNumber(raw) || raw > 2147483647.0)
      return false;
   const int raw_points = (int)MathRound(raw);
   if(raw_points < ZigZag距离最小值 || raw_points > ZigZag距离最大值)
      return false;
   breakout_high = MathMax(first, second) + raw_points * Point;
   breakout_low = MathMin(first, second) - raw_points * Point;
   const double stop = raw_points * ZigZag止损百分比 / 100.0;
   if(!MathIsValidNumber(stop) || stop > 2147483647.0)
      return false;
   stop_loss_points = (int)MathRound(stop);
   const double take_profit = stop_loss_points * ZigZag止盈倍数;
   if(!MathIsValidNumber(take_profit) || take_profit > 2147483647.0)
      return false;
   take_profit_points = (int)MathRound(take_profit);
   return stop_loss_points > 0 && take_profit_points > 0;
  }

bool GetZigZagBreakoutDirection(const double breakout_high,
                                const double breakout_low,
                                int &first_direction)
  {
   RefreshRates();
   if(Bid <= 0.0 || Ask <= Bid || Point <= 0.0
      || breakout_high <= breakout_low)
      return false;
   const double tolerance = Point * 0.5;
   if(Bid >= breakout_high - tolerance)
     {
      first_direction = ordertype == ORDERTYPE_FORWARD ? OP_BUY : OP_SELL;
      return true;
     }
   if(Ask <= breakout_low + tolerance)
     {
      first_direction = ordertype == ORDERTYPE_FORWARD ? OP_SELL : OP_BUY;
      return true;
     }
   return false;
  }

bool ZigZagBrokerDistanceValid(const int stop_points, const int take_profit_points)
  {
   RefreshRates();
   if(Bid <= 0.0 || Ask <= Bid || Point <= 0.0)
      return false;
   const int spread_points = (int)MathCeil((Ask - Bid) / Point);
   const int minimum_points = (int)MarketInfo(Symbol(), MODE_STOPLEVEL);
   const int required_points = spread_points + minimum_points + 2;
   return stop_points >= required_points && take_profit_points >= required_points;
  }

bool GetDistancePoints(int &stop_loss_points, int &take_profit_points)
  {
#ifdef NMR_PROFILE_BOLLINGER_EXPANSION
   if(InpDistanceMode == DISTANCE_BOLLINGER_EXPANSION)
      return GetBollingerExpansionSignal(stop_loss_points, take_profit_points);
#endif
#ifdef NMR_PROFILE_AVERAGE_DOUBLE_CANDLE
   if(InpDistanceMode == DISTANCE_AVERAGE_DOUBLE_CANDLE)
     {
      int direction = OP_BUY;
      return GetAverageDoubleCandleSignal(direction, stop_loss_points, take_profit_points);
     }
#endif

   if(InpDistanceMode == DISTANCE_BOX_BREAKOUT)
      return false;

   if(InpDistanceMode == DISTANCE_BOX_RANGE)
     {
      int box_points = 0;
      if(!GetBoxRangePoints(box_points)) return false;
      stop_loss_points = box_points;
      take_profit_points = box_points;
      return true;
     }
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

   if(InpDistanceMode == DISTANCE_ZIGZAG_RANGE)
     {
      double breakout_high = 0.0;
      double breakout_low = 0.0;
      return GetZigZagDistancePoints(stop_loss_points, take_profit_points,
                                     breakout_high, breakout_low);
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

int BoxRecognitionPeriod()
  {
   return 箱体识别周期 == PERIOD_CURRENT ? Period() : (int)箱体识别周期;
  }

double BoxConfigFingerprint()
  {
   const string config = IntegerToString(BoxRecognitionPeriod()) + "|"
      + IntegerToString(箱体观察窗口K线数) + "|" + IntegerToString(箱体ATR周期) + "|"
      + DoubleToString(箱体触碰ATR倍数, 12) + "|"
      + IntegerToString(箱体上沿最少触碰) + "|" + IntegerToString(箱体下沿最少触碰) + "|"
      + IntegerToString(箱体最少完整往返) + "|" + IntegerToString(箱体同侧触碰间隔) + "|"
      + IntegerToString(箱体突破最小宽度) + "|" + IntegerToString(箱体突破最大宽度) + "|"
      + DoubleToString(箱体突破缓冲ATR倍数, 12) + "|" + IntegerToString((int)开单方式);
   double hash = 1000003.0;
   for(int index = 0; index < StringLen(config); index++)
      hash = MathMod(hash * 257.0 + StringGetCharacter(config, index), 1000000007.0);
   return hash;
  }

string BoxStatePrefix()
  {
   return StatePrefix() + ".box";
  }

void ClearBoxState()
  {
   ZeroMemory(g_box_state);
   const string prefix = BoxStatePrefix();
   GlobalVariableDel(prefix + ".active");
   GlobalVariableDel(prefix + ".upper");
   GlobalVariableDel(prefix + ".lower");
   GlobalVariableDel(prefix + ".width");
   GlobalVariableDel(prefix + ".atr");
   GlobalVariableDel(prefix + ".buffer");
   GlobalVariableDel(prefix + ".confirm");
   GlobalVariableDel(prefix + ".last");
   GlobalVariableDel(prefix + ".upcount");
   GlobalVariableDel(prefix + ".downcount");
   GlobalVariableDel(prefix + ".age");
   GlobalVariableDel(prefix + ".signal");
   GlobalVariableDel(prefix + ".signalbar");
   GlobalVariableDel(prefix + ".direction");
   GlobalVariableDel(prefix + ".fingerprint");
  }

bool SaveBoxState()
  {
   if(!g_box_state.valid)
     {
      ClearBoxState();
      return true;
     }
   const string prefix = BoxStatePrefix();
   GlobalVariableSet(prefix + ".active", 0.0);
   if(!GlobalVariableSet(prefix + ".upper", g_box_state.upper)
      || !GlobalVariableSet(prefix + ".lower", g_box_state.lower)
      || !GlobalVariableSet(prefix + ".width", g_box_state.width_points)
      || !GlobalVariableSet(prefix + ".atr", g_box_state.atr)
      || !GlobalVariableSet(prefix + ".buffer", g_box_state.breakout_buffer)
      || !GlobalVariableSet(prefix + ".confirm", (double)g_box_state.confirmation_time)
      || !GlobalVariableSet(prefix + ".last", (double)g_box_state.last_processed_time)
      || !GlobalVariableSet(prefix + ".upcount", g_box_state.upper_breakout_count)
      || !GlobalVariableSet(prefix + ".downcount", g_box_state.lower_breakout_count)
      || !GlobalVariableSet(prefix + ".age", g_box_state.age_bars)
      || !GlobalVariableSet(prefix + ".signal", (double)g_box_state.signal_id)
      || !GlobalVariableSet(prefix + ".signalbar", (double)g_box_state.signal_bar_time)
      || !GlobalVariableSet(prefix + ".direction", g_box_state.signal_direction)
      || !GlobalVariableSet(prefix + ".fingerprint", BoxConfigFingerprint()))
      return false;
   return GlobalVariableSet(prefix + ".active", 1.0) != 0;
  }

bool LoadBoxState()
  {
   const string prefix = BoxStatePrefix();
   if(!GlobalVariableCheck(prefix + ".active")
      || GlobalVariableGet(prefix + ".active") < 0.5)
      return false;
   if(!GlobalVariableCheck(prefix + ".fingerprint")
      || MathAbs(GlobalVariableGet(prefix + ".fingerprint")
                 - BoxConfigFingerprint()) > 0.5)
     {
      ClearBoxState();
      return false;
     }
   string keys[13] = {"upper", "lower", "width", "atr", "buffer", "confirm",
                      "last", "upcount", "downcount", "age", "signal",
                      "signalbar", "direction"};
   for(int index = 0; index < ArraySize(keys); index++)
      if(!GlobalVariableCheck(prefix + "." + keys[index]))
        {
         ClearBoxState();
         return false;
        }
   g_box_state.upper = GlobalVariableGet(prefix + ".upper");
   g_box_state.lower = GlobalVariableGet(prefix + ".lower");
   g_box_state.width_points = (int)MathRound(GlobalVariableGet(prefix + ".width"));
   g_box_state.atr = GlobalVariableGet(prefix + ".atr");
   g_box_state.breakout_buffer = GlobalVariableGet(prefix + ".buffer");
   g_box_state.confirmation_time = (datetime)MathRound(GlobalVariableGet(prefix + ".confirm"));
   g_box_state.last_processed_time = (datetime)MathRound(GlobalVariableGet(prefix + ".last"));
   g_box_state.upper_breakout_count = (int)MathRound(GlobalVariableGet(prefix + ".upcount"));
   g_box_state.lower_breakout_count = (int)MathRound(GlobalVariableGet(prefix + ".downcount"));
   g_box_state.age_bars = (int)MathRound(GlobalVariableGet(prefix + ".age"));
   g_box_state.signal_id = (long)MathRound(GlobalVariableGet(prefix + ".signal"));
   g_box_state.signal_bar_time = (datetime)MathRound(GlobalVariableGet(prefix + ".signalbar"));
   g_box_state.signal_direction = (int)MathRound(GlobalVariableGet(prefix + ".direction"));
   g_box_state.valid = g_box_state.upper > g_box_state.lower
                       && g_box_state.width_points > 0 && g_box_state.atr > 0.0
                       && g_box_state.breakout_buffer > 0.0
                       && g_box_state.confirmation_time > 0
                       && g_box_state.last_processed_time > 0
                       && g_box_state.age_bars >= 0;
   if(!g_box_state.valid)
      ClearBoxState();
   return g_box_state.valid;
  }

bool FindConfirmedBox()
  {
   const int timeframe = BoxRecognitionPeriod();
   const int count = 箱体观察窗口K线数;
   if(count <= 0 || iBars(Symbol(), timeframe) < count + 箱体ATR周期)
      return false;
   double upper = -DBL_MAX;
   double lower = DBL_MAX;
   for(int shift = 1; shift <= count; shift++)
     {
      const double high = iHigh(Symbol(), timeframe, shift);
      const double low = iLow(Symbol(), timeframe, shift);
      if(!MathIsValidNumber(high) || !MathIsValidNumber(low) || high <= low)
         return false;
      upper = MathMax(upper, high);
      lower = MathMin(lower, low);
     }
   const int width_points = (int)MathRound((upper - lower) / Point);
   if(width_points < 箱体突破最小宽度 || width_points > 箱体突破最大宽度)
      return false;

   int events[];
   int last_upper_index = -1000000;
   int last_lower_index = -1000000;
   int upper_touches = 0;
   int lower_touches = 0;
   for(int index = 0; index < count; index++)
     {
      const int shift = count - index;
      const double atr = iATR(Symbol(), timeframe, 箱体ATR周期, shift);
      const double high = iHigh(Symbol(), timeframe, shift);
      const double low = iLow(Symbol(), timeframe, shift);
      if(!MathIsValidNumber(atr) || atr <= 0.0)
         continue;
      const double tolerance = atr * 箱体触碰ATR倍数;
      const bool upper_hit = upper - high <= tolerance;
      const bool lower_hit = low - lower <= tolerance;
      if(upper_hit && lower_hit)
         continue;
      int side = upper_hit ? 1 : lower_hit ? -1 : 0;
      if(side == 0)
         continue;
      if(side == 1)
        {
         if(index - last_upper_index < 箱体同侧触碰间隔)
            continue;
         last_upper_index = index;
         upper_touches++;
        }
      else
        {
         if(index - last_lower_index < 箱体同侧触碰间隔)
            continue;
         last_lower_index = index;
         lower_touches++;
        }
      const int size = ArraySize(events);
      if(ArrayResize(events, size + 1) != size + 1)
         return false;
      events[size] = side;
     }
   int round_trips = 0;
   for(int event = 2; event < ArraySize(events); )
     {
      if(events[event] == events[event - 2] && events[event] != events[event - 1])
        {
         round_trips++;
         event += 2;
        }
      else
         event++;
     }
   if(upper_touches < 箱体上沿最少触碰
      || lower_touches < 箱体下沿最少触碰
      || round_trips < 箱体最少完整往返)
      return false;
   const double confirmation_atr = iATR(Symbol(), timeframe, 箱体ATR周期, 1);
   const datetime confirmation_time = iTime(Symbol(), timeframe, 1);
   if(!MathIsValidNumber(confirmation_atr) || confirmation_atr <= 0.0
      || confirmation_time <= 0)
      return false;
   ZeroMemory(g_box_state);
   g_box_state.valid = true;
   g_box_state.upper = upper;
   g_box_state.lower = lower;
   g_box_state.width_points = width_points;
   g_box_state.atr = confirmation_atr;
   g_box_state.breakout_buffer = confirmation_atr * 箱体突破缓冲ATR倍数;
   g_box_state.confirmation_time = confirmation_time;
   g_box_state.last_processed_time = confirmation_time;
   return SaveBoxState();
  }

bool AdvanceBoxBreakout(int &direction, datetime &signal_time, long &signal_id)
  {
   direction = -1;
   signal_time = 0;
   signal_id = 0;
   if(!g_box_state.valid && !LoadBoxState() && !FindConfirmedBox())
      return false;
   const int timeframe = BoxRecognitionPeriod();
   const int last_shift = iBarShift(Symbol(), timeframe,
                                    g_box_state.last_processed_time, true);
   if(last_shift < 1 || iTime(Symbol(), timeframe, last_shift)
                        != g_box_state.last_processed_time)
     {
      ClearBoxState();
      return false;
     }
   if(g_box_state.age_bars + last_shift - 1 > 箱体观察窗口K线数)
     {
      ClearBoxState();
      return false;
     }
   if(g_box_state.signal_id != 0)
     {
      direction = g_box_state.signal_direction;
      signal_time = g_box_state.signal_bar_time;
      signal_id = g_box_state.signal_id;
      return true;
     }
   for(int shift = last_shift - 1; shift >= 1; shift--)
     {
      const datetime bar_time = iTime(Symbol(), timeframe, shift);
      const double close = iClose(Symbol(), timeframe, shift);
      if(bar_time <= 0 || !MathIsValidNumber(close) || close <= 0.0)
         return false;
      g_box_state.age_bars++;
      if(close > g_box_state.upper + g_box_state.breakout_buffer)
        {
         g_box_state.upper_breakout_count++;
         g_box_state.lower_breakout_count = 0;
        }
      else if(close < g_box_state.lower - g_box_state.breakout_buffer)
        {
         g_box_state.lower_breakout_count++;
         g_box_state.upper_breakout_count = 0;
        }
      else
        {
         g_box_state.upper_breakout_count = 0;
         g_box_state.lower_breakout_count = 0;
        }
      g_box_state.last_processed_time = bar_time;
      if(g_box_state.upper_breakout_count >= 2
         || g_box_state.lower_breakout_count >= 2)
        {
         const bool upper_break = g_box_state.upper_breakout_count >= 2;
         direction = upper_break
                     ? (开单方式 == ORDERTYPE_FORWARD ? OP_BUY : OP_SELL)
                     : (开单方式 == ORDERTYPE_FORWARD ? OP_SELL : OP_BUY);
         signal_time = bar_time;
         signal_id = ((long)signal_time * 1000)
                     + (long)timeframe * 10
                     + (direction == OP_BUY ? 1 : 2);
         g_box_state.signal_id = signal_id;
         g_box_state.signal_bar_time = signal_time;
         g_box_state.signal_direction = direction;
         if(!SaveBoxState())
            return false;
         return true;
        }
      if(g_box_state.age_bars >= 箱体观察窗口K线数)
        {
         ClearBoxState();
         return false;
        }
     }
   SaveBoxState();
   return false;
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
   if(InpDistanceMode == DISTANCE_BOLLINGER_EXPANSION)
      return false;
   if(InpDistanceMode == DISTANCE_AVERAGE_DOUBLE_CANDLE)
      return false;
   if(InpDistanceMode == DISTANCE_ZIGZAG_RANGE)
      return false;
   if(InpDistanceMode == DISTANCE_BOX_RANGE)
      return false;
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
   const bool renewal_cleanup=BasketRenewalResetRequiresDeferral();
   Print(reason);
   if(renewal_cleanup) BasketRenewalDeferReset(); else MultiClearAll();
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
   if(CloseAllOurPositions() && !HasOurPending() && !renewal_cleanup && BasketRenewalResetReady())
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
   if(!BasketRenewalResetReady()) return false;
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
      g_multi_last_send_error=error;
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
    if(FirstOrderLotType == 3)
       return FirstOrderFixedLots;
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
    if(FirstOrderLotType == 3)
       return FirstOrderFixedLots;
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
   ticket = -1;
   if(!IsInitialSpreadAllowed())
      return false;
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
      || range_points <= 0 || volume <= 0.0 || !IsInitialSpreadAllowed())
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

bool CancelInitialPendingPairIfSpreadTooHigh()
  {
   if(IsInitialSpreadAllowed())
      return false;
   bool deletion_failed = false;
   for(int index = OrdersTotal() - 1; index >= 0; index--)
     {
      if(!OrderSelect(index, SELECT_BY_POS, MODE_TRADES) || !IsOurPendingOrder()
         || !IsInitialPendingComment())
         continue;
      const int candidate = OrderTicket();
      if(!OrderDelete(candidate, clrRed))
        {
         Print("Wide-spread initial pending cancellation failed, ticket=", candidate,
               ", error=", GetLastError());
         deletion_failed = true;
        }
     }
   return deletion_failed;
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

bool ManageBoxBreakoutEntry()
  {
   int direction = OP_BUY;
   datetime signal_time = 0;
   long signal_id = 0;
   if(!AdvanceBoxBreakout(direction, signal_time, signal_id))
      return true;
   if(!IsInitialEntryAllowed() || !IsInitialSpreadAllowed())
      return true;
   if(HasOurPosition() || HasOurPending())
      return true;

   g_active_first_direction = direction == OP_BUY ? FIRST_BUY : FIRST_SELL;
   g_active_cycle_mode = InpCycleMode;
   g_group_stop_points = g_box_state.width_points;
   g_group_take_profit_points = g_box_state.width_points;
   g_had_position = false;
   g_cycle_index = 0;
   g_pending_index = -1;
   const double initial_lots = g_cumulative_loss_lots > 0.0
                               ? (FirstOrderLotType == 1
                                  ? VolumeNormalize(g_cumulative_loss_lots)
                                  : NextGroupLotsAfterStop(g_group_first_lots))
                               : VolumeNormalize(InpInitialLots);
   if(!SaveBoxState())
      return true;
   SaveState();
   if(IsPairedBasketMode())
     {
      StartResolvedMultiPair(direction, g_box_state.width_points,
                             g_box_state.width_points, initial_lots,
                             signal_time, signal_id);
      if(MultiHasActiveGroups() || BasketRenewalHasWork())
         ClearBoxState();
      return true;
     }
   if(!PrepareInitialSignal(signal_time, direction, signal_id))
      return true;
   if(!OpenMarket(direction, initial_lots))
      return true;
   int ticket = -1;
   int type = OP_BUY;
   double volume = 0.0;
   double entry = 0.0;
   double stop_loss = 0.0;
   double take_profit = 0.0;
   if(FindPosition(ticket, type, volume, entry, stop_loss, take_profit))
     {
      g_group_anchor_price = entry;
      g_group_last_entry = entry;
      g_group_linear_extreme = entry;
      g_group_first_lots = volume;
      g_group_total_lots = TotalPositionLots(type);
      g_grid_lots = g_previous_grid_lots > 0.0
                    ? VolumeNormalize(g_previous_grid_lots * InpGridLotMultiplier)
                    : g_group_total_lots;
      SaveState();
      ClearBoxState();
     }
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

   const bool candle_once_mode = InpDistanceMode == DISTANCE_CANDLE_RANGE
                                 && Korder_type == KORDER_ONCE_PER_BAR;
   const datetime current_bar_time = candle_once_mode ? iTime(Symbol(), Period(), 0) : 0;
   if(candle_once_mode && current_bar_time > 0
      && current_bar_time != g_last_candle_entry_bar_time
      && !PrepareCandleOnceEntry(current_bar_time))
      return;

   if(CancelInitialPendingPairIfSpreadTooHigh())
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
      if(InpDistanceMode == DISTANCE_BOX_BREAKOUT && g_group_stop_points > 0
         && g_group_take_profit_points > 0)
         ClearBoxState();
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
   if(InpDistanceMode == DISTANCE_BOX_BREAKOUT)
     {
      ManageBoxBreakoutEntry();
      return;
     }
   if(!IsInitialEntryAllowed())
      return;
   if(!IsInitialSpreadAllowed())
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
                                   ? (FirstOrderLotType == 1
                                      ? VolumeNormalize(g_cumulative_loss_lots)
                                      : NextGroupLotsAfterStop(g_group_first_lots))
                                   : VolumeNormalize(InpInitialLots);
      if(IsPairedBasketMode())
        {
         StartInitialMultiOco(previous_high,previous_low,range_points,initial_lots);
         return;
        }
       const int pending_signal_direction = ordertype == ORDERTYPE_FORWARD
                                            ? OP_BUY : OP_SELL;
       if(PrepareInitialSignal(current_bar_time, pending_signal_direction)
          && PlaceInitialPendingPair(previous_high, previous_low,
                                     range_points, initial_lots))
         MarkCandleEntryBarProcessed(current_bar_time);
      return;
     }

   int initial_stop_points = 0;
   int initial_take_profit_points = 0;
   int first_direction = OP_BUY;
   datetime signal_bar_time = iTime(Symbol(), Period(), 0);
   long signal_id = 0;
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
#ifdef NMR_PROFILE_BOLLINGER_EXPANSION
   else if(InpDistanceMode == DISTANCE_BOLLINGER_EXPANSION)
     {
      if(!GetBollingerExpansionSignal(initial_stop_points, initial_take_profit_points)) return;
      if(首单方向确定方式 == FIRST_DIRECTION_BOLLINGER && !GetBollingerFirstDirection(first_direction)) return;
      if(首单方向确定方式 == FIRST_DIRECTION_PRESET)
         first_direction = 首单方向 == FIRST_SELL ? OP_SELL : OP_BUY;
      g_active_first_direction = first_direction == OP_BUY ? FIRST_BUY : FIRST_SELL;
      g_active_cycle_mode = InpCycleMode;
     }
#endif
#ifdef NMR_PROFILE_AVERAGE_DOUBLE_CANDLE
   else if(InpDistanceMode == DISTANCE_AVERAGE_DOUBLE_CANDLE)
     {
      if(!GetAverageDoubleCandleSignal(first_direction, initial_stop_points,
                                       initial_take_profit_points))
         return;
      g_active_first_direction = first_direction == OP_BUY ? FIRST_BUY : FIRST_SELL;
      g_active_cycle_mode = InpCycleMode;
     }
#endif
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
      if(InpDistanceMode == DISTANCE_ZIGZAG_RANGE)
        {
         double breakout_high = 0.0;
         double breakout_low = 0.0;
         if(!GetZigZagDistancePoints(initial_stop_points, initial_take_profit_points,
                                     breakout_high, breakout_low)
            || !GetZigZagBreakoutDirection(breakout_high, breakout_low,
                                           first_direction))
            return;
        }
      else if(InpDistanceMode == DISTANCE_BOLLINGER_RANGE)
        {
          if(!GetBollingerTouchDirection(first_direction, signal_bar_time,
                                         signal_id))
            return;
        }
      else
        {
         if(首单方向确定方式 == FIRST_DIRECTION_BOLLINGER
            && !GetBollingerFirstDirection(first_direction))
            return;
         if(首单方向确定方式 == FIRST_DIRECTION_PRESET)
            first_direction = InpFirstDirection == FIRST_SELL ? OP_SELL : OP_BUY;
        }
      g_active_first_direction = first_direction == OP_BUY ? FIRST_BUY : FIRST_SELL;
      g_active_cycle_mode = InpCycleMode;
      if(InpDistanceMode != DISTANCE_ZIGZAG_RANGE
         && !GetDistancePoints(initial_stop_points, initial_take_profit_points))
         return;
     }
   if(InpDistanceMode == DISTANCE_ZIGZAG_RANGE
      && !ZigZagBrokerDistanceValid(initial_stop_points, initial_take_profit_points))
      return;
   g_had_position = false;
   g_cycle_index = 0;
   g_pending_index = -1;
   g_group_stop_points = initial_stop_points;
   g_group_take_profit_points = initial_take_profit_points;
    const double initial_lots = g_cumulative_loss_lots > 0.0
                                ? (FirstOrderLotType == 1
                                   ? VolumeNormalize(g_cumulative_loss_lots)
                                   : NextGroupLotsAfterStop(g_group_first_lots))
                                : VolumeNormalize(InpInitialLots);
   if(IsPairedBasketMode())
     {
      StartResolvedMultiPair(first_direction, initial_stop_points,
                              initial_take_profit_points, initial_lots,
                              signal_bar_time, signal_id);
      return;
     }
    if(!PrepareInitialSignal(signal_bar_time, first_direction, signal_id))
       return;
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
   int      basket_mode_at_start;
   int      basket_family_id;
   int      stop_event_sequence;
   int      renewal_request_state;
   ulong    renewal_deal_cursor;
   int      renewal_request_direction;
   double   renewal_request_volume_before;
   int      id;
   bool     active;
   bool     dirty;
   int      first_direction;
   int      cycle_mode;
   int      cycle_index;
   int      pending_index;
   int      reversal_count;
   int      pending_ticket;
   datetime reverse_retry_after;
   int      reverse_retry_count;
   int      reverse_pending_error;
   int      pair_parent_id;
   int      pair_peer_id;
   bool     launch_confirmed;
   bool     launch_attempted;
   bool     launch_failed;
   bool     market_request_unresolved;
   bool     market_request_exposure_hydrated;
   int      launch_error;
   int      market_request_direction;
   int      market_request_sequence;
   datetime launch_retry_after;
   datetime launch_log_time;
   int      launch_event_id;
   datetime market_request_time;
   double   market_request_volume_before;
   datetime box_signal_bar_time;
   long     box_signal_id;

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
  };

MultiGroupState g_multi_groups[];
datetime g_multi_last_trigger_bar = 0;
int g_multi_next_id = 1;
int g_multi_last_send_error = 0;
int g_multi_grid_order_tickets[];
int g_multi_favorable_grid_order_tickets[];


#define NMR_RENEWAL_CORE
#include "NoMatterRiseFall_BasketRenewal.mqh"

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

string MultiMarketRequestComment(const MultiGroupState &group)
  {
   return MultiGroupTag(group.id) + ".R"
          + IntegerToString(group.market_request_sequence) + InpOrderComment;
  }

string MultiInitialPendingComment(const int group_id, const bool high)
  {
   return MultiGroupTag(group_id) + InpOrderComment
          + (high ? ".InitialHigh" : ".InitialLow");
  }

string MultiStatePrefix(const int group_id)
  {
   const string compact=R3GroupPrefix(group_id);
   if(GlobalVariableCheck(compact+".bmode") && GlobalVariableGet(compact+".bmode")==3) return compact;
   const int renewal_index=R3GroupIndex(group_id);
   if(renewal_index>=0 && g_multi_groups[renewal_index].basket_mode_at_start==3) return compact;

   return StatePrefix() + ".multi." + IntegerToString(group_id);
  }

void MultiDeleteState(const int group_id)
  {
   const string prefix = MultiStatePrefix(group_id);
   GlobalVariableDel(prefix + ".bmode");
   GlobalVariableDel(prefix + ".bfam");
   GlobalVariableDel(prefix + ".stopseq");
   GlobalVariableDel(prefix + ".rrs");
   GlobalVariableDel(prefix + ".rhi");
   GlobalVariableDel(prefix + ".rlo");
   GlobalVariableDel(prefix + ".rrd");
   GlobalVariableDel(prefix + ".rrv");
   GlobalVariableDel(prefix + ".rrcommit");
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
   GlobalVariableDel(prefix + ".mru");
   GlobalVariableDel(prefix + ".mrt");
   GlobalVariableDel(prefix + ".mrd");
   GlobalVariableDel(prefix + ".mrvb");
   GlobalVariableDel(prefix + ".mrs");
   GlobalVariableDel(prefix + ".mrh");
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
   if(BasketRenewalDeferReset()) return;
   BasketRenewalCancelAll();
   for(int id = 1; id < g_multi_next_id; id++)
      MultiDeleteState(id);
   ArrayResize(g_multi_groups, 0);
   ArrayResize(g_multi_grid_order_tickets, 0);
   ArrayResize(g_multi_favorable_grid_order_tickets, 0);
   g_multi_last_trigger_bar = 0;
   g_multi_next_id = g_basket_next_id_floor;
   GlobalVariableDel(StatePrefix() + ".multi.nextid");
   GlobalVariableDel(StatePrefix() + ".multi.lasttriggerbar");
  }

void MultiRemoveGroup(const int index)
  {
   if(index < 0 || index >= ArraySize(g_multi_groups))
      return;
   if(!BasketRenewalRecordFinished(g_multi_groups[index]))
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
   group.basket_mode_at_start = 0;
   group.basket_family_id = 0;
   group.stop_event_sequence = 0;
   group.renewal_request_state = 0;
   group.renewal_deal_cursor = 0;
   group.renewal_request_direction = -1;
   group.renewal_request_volume_before = 0;
   group.active = true;
   group.dirty = true;
   group.first_direction = FIRST_BUY;
   group.cycle_mode = CYCLE_MODE_1;
   group.cycle_index = 0;
   group.pending_index = -1;
   group.reversal_count = 0;
   group.pending_ticket = -1;
   group.reverse_retry_after = 0;
   group.reverse_retry_count = 0;
   group.reverse_pending_error = 0;
   group.pair_parent_id = 0;
   group.pair_peer_id = 0;
   group.launch_confirmed = false;
   group.launch_attempted = false;
   group.launch_failed = false;
   group.market_request_unresolved = false;
   group.market_request_exposure_hydrated = false;
   group.launch_error = 0;
   group.market_request_direction = OP_BUY;
   group.market_request_sequence = 0;
   group.launch_retry_after = 0;
   group.launch_log_time = 0;
   group.launch_event_id = group_id;
   group.market_request_time = 0;
   group.market_request_volume_before = 0.0;
   group.box_signal_bar_time = 0;
   group.box_signal_id = 0;

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
   return before.basket_mode_at_start != after.basket_mode_at_start
          || before.basket_family_id != after.basket_family_id
          || before.stop_event_sequence != after.stop_event_sequence
          || before.renewal_request_state != after.renewal_request_state
          || before.renewal_deal_cursor != after.renewal_deal_cursor
          || before.renewal_request_direction != after.renewal_request_direction
          || before.renewal_request_volume_before != after.renewal_request_volume_before
          || before.active != after.active
          || before.first_direction != after.first_direction
          || before.cycle_mode != after.cycle_mode
          || before.cycle_index != after.cycle_index
          || before.pending_index != after.pending_index
          || before.reversal_count != after.reversal_count
          || before.pending_ticket != after.pending_ticket
           || before.reverse_retry_after != after.reverse_retry_after
           || before.reverse_retry_count != after.reverse_retry_count
           || before.reverse_pending_error != after.reverse_pending_error
          || before.pair_parent_id != after.pair_parent_id
          || before.pair_peer_id != after.pair_peer_id
          || before.launch_confirmed != after.launch_confirmed
          || before.launch_attempted != after.launch_attempted
          || before.launch_failed != after.launch_failed
          || before.market_request_unresolved != after.market_request_unresolved
          || before.market_request_exposure_hydrated != after.market_request_exposure_hydrated
          || before.launch_error != after.launch_error
          || before.market_request_direction != after.market_request_direction
          || before.market_request_sequence != after.market_request_sequence
          || before.launch_retry_after != after.launch_retry_after
          || before.launch_log_time != after.launch_log_time
          || before.launch_event_id != after.launch_event_id
          || before.market_request_time != after.market_request_time
          || before.market_request_volume_before != after.market_request_volume_before
          || before.box_signal_bar_time != after.box_signal_bar_time
          || before.box_signal_id != after.box_signal_id

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
          || before.favorable_grid_pending_price != after.favorable_grid_pending_price;
  }

void MultiSaveGroup(MultiGroupState &group)
  {
   if(!group.dirty)
      return;
   const string prefix = MultiStatePrefix(group.id);
   if(group.basket_mode_at_start==3) R3Put(R3Prefix()+".next",g_multi_next_id);
   GlobalVariableSet(prefix + ".bmode", group.basket_mode_at_start);
   GlobalVariableSet(prefix + ".bfam", group.basket_family_id);
   GlobalVariableSet(prefix + ".stopseq", group.stop_event_sequence);
   GlobalVariableSet(prefix + ".rrs", group.renewal_request_state);
   GlobalVariableSet(prefix + ".rhi", (double)(group.renewal_deal_cursor >> 32));
   GlobalVariableSet(prefix + ".rlo", (double)(group.renewal_deal_cursor & (ulong)0xFFFFFFFF));
   GlobalVariableSet(prefix + ".rrd", group.renewal_request_direction);
   GlobalVariableSet(prefix + ".rrv", group.renewal_request_volume_before);
   GlobalVariableSet(prefix + ".active", group.active ? 1.0 : 0.0);
   GlobalVariableSet(prefix + ".first", group.first_direction);
   GlobalVariableSet(prefix + ".mode", group.cycle_mode);
   GlobalVariableSet(prefix + ".index", group.cycle_index);
   GlobalVariableSet(prefix + ".pendingindex", group.pending_index);
   GlobalVariableSet(prefix + ".reversals", group.reversal_count);
   GlobalVariableSet(prefix + ".pendingticket", group.pending_ticket);
   GlobalVariableSet(prefix + ".revretry", (double)group.reverse_retry_after);
   GlobalVariableSet(prefix + ".revcount", group.reverse_retry_count);
   GlobalVariableSet(prefix + ".reverror", group.reverse_pending_error);
   GlobalVariableSet(prefix + ".pairparent", group.pair_parent_id);
   GlobalVariableSet(prefix + ".pairpeer", group.pair_peer_id);
   GlobalVariableSet(prefix + ".launchconfirmed", group.launch_confirmed ? 1.0 : 0.0);
   GlobalVariableSet(prefix + ".launchattempted", group.launch_attempted ? 1.0 : 0.0);
   GlobalVariableSet(prefix + ".launchfailed", group.launch_failed ? 1.0 : 0.0);
   GlobalVariableSet(prefix + ".mru", group.market_request_unresolved ? 1.0 : 0.0);
   GlobalVariableSet(prefix + ".mrt", (double)group.market_request_time);
   GlobalVariableSet(prefix + ".mrd", group.market_request_direction);
   GlobalVariableSet(prefix + ".mrvb", group.market_request_volume_before);
   GlobalVariableSet(prefix + ".mrs", group.market_request_sequence);
   GlobalVariableSet(prefix + ".mrh", group.market_request_exposure_hydrated ? 1.0 : 0.0);
   GlobalVariableSet(prefix + ".launcherror", group.launch_error);
   GlobalVariableSet(prefix + ".launchretry", (double)group.launch_retry_after);
   GlobalVariableSet(prefix + ".launchlogtime", (double)group.launch_log_time);
   GlobalVariableSet(prefix + ".launchevent", group.launch_event_id);
   GlobalVariableSet(prefix + ".boxbar", (double)group.box_signal_bar_time);
   GlobalVariableSet(prefix + ".boxsignal", (double)group.box_signal_id);

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
   // The source marker is written before this record. If MT4 stopped between
   // those writes, reconstruct the missing opposite group from the source.
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
   // The reconstructed ID is now durable, so the marker can be retired.
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
      // Keep the durable in-flight marker; reconcile by group comment before
      // considering another send after restart.
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
   if(!GlobalVariableCheck(next_key) && !GlobalVariableCheck(R3Prefix()+".next")) return;
   g_multi_next_id=(int)MathMax(1, MathMax(GlobalVariableGet(next_key),GlobalVariableGet(R3Prefix()+".next")));
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
      if(GlobalVariableCheck(prefix + ".bmode"))
         state.basket_mode_at_start = (int)GlobalVariableGet(prefix + ".bmode");
      if(GlobalVariableCheck(prefix + ".bfam"))
         state.basket_family_id = (int)GlobalVariableGet(prefix + ".bfam");
      if(GlobalVariableCheck(prefix + ".stopseq"))
         state.stop_event_sequence = (int)GlobalVariableGet(prefix + ".stopseq");
      state.first_direction = (int)MathRound(GlobalVariableGet(prefix + ".first"));
      state.cycle_mode = (int)MathRound(GlobalVariableGet(prefix + ".mode"));
      state.cycle_index = (int)MathRound(GlobalVariableGet(prefix + ".index"));
      state.pending_index = (int)MathRound(GlobalVariableGet(prefix + ".pendingindex"));
      state.reversal_count = (int)MathRound(GlobalVariableGet(prefix + ".reversals"));
      state.pending_ticket = (int)MathRound(GlobalVariableGet(prefix + ".pendingticket"));
       if(GlobalVariableCheck(prefix + ".revretry"))
          state.reverse_retry_after=(datetime)MathRound(GlobalVariableGet(prefix + ".revretry"));
       if(GlobalVariableCheck(prefix + ".revcount"))
          state.reverse_retry_count=(int)MathRound(GlobalVariableGet(prefix + ".revcount"));
       if(GlobalVariableCheck(prefix + ".reverror"))
          state.reverse_pending_error=(int)MathRound(GlobalVariableGet(prefix + ".reverror"));
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
      if(GlobalVariableCheck(prefix + ".mru"))
         state.market_request_unresolved=GlobalVariableGet(prefix + ".mru")>0.5;
      if(GlobalVariableCheck(prefix + ".launcherror"))
         state.launch_error=(int)MathRound(GlobalVariableGet(prefix + ".launcherror"));
      if(GlobalVariableCheck(prefix + ".mrt"))
         state.market_request_time=(datetime)MathRound(GlobalVariableGet(prefix + ".mrt"));
      if(GlobalVariableCheck(prefix + ".mrd"))
         state.market_request_direction=(int)MathRound(GlobalVariableGet(prefix + ".mrd"));
      if(GlobalVariableCheck(prefix + ".mrvb"))
         state.market_request_volume_before=GlobalVariableGet(prefix + ".mrvb");
      if(GlobalVariableCheck(prefix + ".mrs"))
         state.market_request_sequence=(int)MathRound(GlobalVariableGet(prefix + ".mrs"));
      if(GlobalVariableCheck(prefix + ".mrh"))
         state.market_request_exposure_hydrated=GlobalVariableGet(prefix + ".mrh")>0.5;
      if(GlobalVariableCheck(prefix + ".launchretry"))
         state.launch_retry_after=(datetime)MathRound(GlobalVariableGet(prefix + ".launchretry"));
      if(GlobalVariableCheck(prefix + ".launchlogtime"))
         state.launch_log_time=(datetime)MathRound(GlobalVariableGet(prefix + ".launchlogtime"));
      if(GlobalVariableCheck(prefix + ".launchevent"))
         state.launch_event_id=(int)MathRound(GlobalVariableGet(prefix + ".launchevent"));
         if(GlobalVariableCheck(prefix + ".boxbar"))
            state.box_signal_bar_time=(datetime)MathRound(GlobalVariableGet(prefix + ".boxbar"));
         if(GlobalVariableCheck(prefix + ".boxsignal"))
            state.box_signal_id=(long)MathRound(GlobalVariableGet(prefix + ".boxsignal"));

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
      if(GlobalVariableCheck(prefix + ".rrs"))
         state.renewal_request_state=(int)GlobalVariableGet(prefix + ".rrs");
      if(GlobalVariableCheck(prefix + ".rhi") && GlobalVariableCheck(prefix + ".rlo"))
         state.renewal_deal_cursor=((ulong)GlobalVariableGet(prefix + ".rhi") << 32)
                                  | (ulong)GlobalVariableGet(prefix + ".rlo");
      if(GlobalVariableCheck(prefix + ".rrd"))
         state.renewal_request_direction=(int)GlobalVariableGet(prefix + ".rrd");
      if(GlobalVariableCheck(prefix + ".rrv"))
         state.renewal_request_volume_before=GlobalVariableGet(prefix + ".rrv");
      if(GlobalVariableCheck(prefix + ".rrcommit") && GlobalVariableGet(prefix + ".rrcommit")==0)
         R3ClearRequest(state); // prepared metadata never reached the send boundary
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
   if(group.market_request_unresolved)
      return false;
   RefreshRates();
   const double volume = VolumeNormalize(requested_volume);
   if(volume <= 0.0)
      return false;
   if(!BasketRenewalBeforeLeg(group,(int)type)) return false;
   group.market_request_sequence++;
   if(group.market_request_sequence <= 0)
      group.market_request_sequence = 1;
   group.market_request_unresolved = true;
   group.market_request_exposure_hydrated = false;
   group.market_request_time = TimeCurrent();
   group.market_request_direction = type;
   group.market_request_volume_before = MultiTotalLots(group.id, type);
   group.dirty = true;
   MultiSaveGroup(group);
   const double price = type == OP_BUY ? Ask : Bid;
   ResetLastError();
   const int ticket = OrderSend(Symbol(), type, volume, price, 0, 0.0, 0.0,
                                MultiMarketRequestComment(group), InpMagicNumber,
                                0, clrBlue);
   if(ticket < 0)
     {
      const int error = GetLastError();
      BasketRenewalAfterLeg(group,false,error);
      g_multi_last_send_error=error;
      Print("Multi market order failed, group=", group.id, ", error=", error);
      if(!MultiLaunchErrorIsAmbiguous(error))
        {
         group.market_request_unresolved = false;
         group.market_request_exposure_hydrated = false;
         group.market_request_time = 0;
         group.market_request_volume_before = 0.0;
        }
      group.dirty = true;
      MultiSaveGroup(group);
      if(error == ERR_NOT_ENOUGH_MONEY)
         BeginResetAfterNoMoney();
      return false;
     }
   group.market_request_unresolved = false;
   group.market_request_exposure_hydrated = false;
   group.market_request_time = 0;
   group.market_request_volume_before = 0.0;
   group.dirty = true;
   MultiSaveGroup(group);
   BasketRenewalAfterLeg(group,true,0);
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
    if(FirstOrderLotType == 3)
       return FirstOrderFixedLots;
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
    if(FirstOrderLotType == 3)
       return FirstOrderFixedLots;
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
   if(!IsInitialSpreadAllowed())
      return false;
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
            && MultiIsInitialPendingComment())
           {ticket=OrderTicket();break;}
      if(ticket<=0)
         for(int i=OrdersHistoryTotal()-1;i>=0;i--)
            if(OrderSelect(i,SELECT_BY_POS,MODE_HISTORY) && IsOurMarketOrder()
               && MultiCommentMatches(OrderComment(),group.id)
               && MultiIsInitialPendingComment())
              {ticket=OrderTicket();break;}
      if(ticket>0)
        {
         if(StringFind(OrderComment(),".InitialHigh",0)>=0)
            group.initial_high_ticket=ticket;
         else group.initial_low_ticket=ticket;
         group.dirty=true;
         MultiSaveGroup(group);
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
        {
         if(g_multi_last_send_error!=128) group.launch_attempted=false;
         group.dirty=true;MultiSaveGroup(group);return true;
        }
      if(high_leg) group.initial_high_ticket=reopened;
      else group.initial_low_ticket=reopened;
      group.launch_attempted=false;group.dirty=true;MultiSaveGroup(group);
      return true;
     }
   if(ticket<=0) return false;
   const int status=MultiInitialPendingStatus(ticket,group.id);
   if(status==REVERSE_PENDING_ACTIVE || status==REVERSE_PENDING_UNKNOWN)
      return true;
   if(status!=REVERSE_PENDING_FILLED)
     {group.active=false;group.dirty=true;return false;}
   int pos_ticket=-1,type=OP_BUY;double lots=0.0,entry=0.0,sl=0.0,tp=0.0;
   if(!FindPositionByTicket(ticket,pos_ticket,type,lots,entry,sl,tp))
      return true;
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
   int peer_ticket=peer_index<0 ? -1
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
      else if(peer_status==REVERSE_PENDING_UNKNOWN)
         return true;
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
   // The high_filled && low_filled race is represented by two peer-tagged
   // groups; both live positions are adopted and no third opposite is launched.
   if(group.pair_peer_id!=0)
      return MultiHandlePairedInitialPendingFill(group);
   if(group.initial_high_ticket < 0 && group.initial_low_ticket < 0)
      return false;
   if(!IsInitialSpreadAllowed())
     {
      const int high_active_status = MultiInitialPendingStatus(group.initial_high_ticket, group.id);
      const int low_active_status = MultiInitialPendingStatus(group.initial_low_ticket, group.id);
      if(high_active_status != REVERSE_PENDING_FILLED
         && low_active_status != REVERSE_PENDING_FILLED)
        {
         bool deletion_failed = false;
         for(int index = OrdersTotal() - 1; index >= 0; index--)
           {
            if(!OrderSelect(index, SELECT_BY_POS, MODE_TRADES) || !IsOurPendingOrder()
               || !MultiIsInitialPendingComment()
               || !MultiCommentMatches(OrderComment(), group.id))
               continue;
            const int candidate = OrderTicket();
            if(!OrderDelete(candidate, clrRed))
              {
               Print("Wide-spread multi initial pending cancellation failed, group=",
                     group.id, ", ticket=", candidate, ", error=", GetLastError());
               deletion_failed = true;
              }
           }
         if(deletion_failed)
            return true;
        }
     }
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
      const double previous_high = group.initial_high_price;
      const double previous_low = group.initial_low_price;
      const datetime current_bar = iTime(Symbol(), Period(), 0);
      if(g_multi_last_trigger_bar > 0 && g_multi_last_trigger_bar == current_bar
         && previous_high > 0.0 && previous_low > 0.0
         && IsInitialEntryAllowed())
        {
         if(!IsInitialSpreadAllowed())
            return true;
         const int canceled_high_ticket = group.initial_high_ticket;
         const int canceled_low_ticket = group.initial_low_ticket;
         group.initial_high_ticket = -1;
         group.initial_low_ticket = -1;
         if(MultiPlaceInitialPendingPair(group, previous_high, previous_low,
                                         group.stop_points, 首单手数))
            return true;
         group.initial_high_ticket = canceled_high_ticket;
         group.initial_low_ticket = canceled_low_ticket;
         return true;
        }
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

int MultiReversePendingRetryDelay(const int error, const int attempts)
  {
   if(error == ERR_TRADE_TOO_MANY_ORDERS
      || error == ERR_MARKET_CLOSED || error == ERR_TRADE_DISABLED)
      return 60;
   const bool transient = error == ERR_SERVER_BUSY
                          || error == ERR_TOO_FREQUENT_REQUESTS
                          || error == ERR_TRADE_CONTEXT_BUSY
                          || error == ERR_BROKER_BUSY
                          || error == ERR_OFF_QUOTES || error == ERR_REQUOTE
                          || error == ERR_PRICE_CHANGED || error == ERR_INVALID_PRICE
                          || error == ERR_NO_CONNECTION || error == ERR_TRADE_TIMEOUT;
   if(!transient)
      return 300;
   int delay = 5;
   for(int index = 1; index < attempts && delay < 300; index++)
      delay = (int)MathMin(300, delay * 2);
   return delay;
  }

bool MultiReversePendingRetryAllowed(const MultiGroupState &group)
  {
   if(group.reverse_retry_after > TimeCurrent())
      return false;
   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED)
      || !AccountInfoInteger(ACCOUNT_TRADE_ALLOWED)
      || !AccountInfoInteger(ACCOUNT_TRADE_EXPERT))
      return false;
   if(group.reverse_pending_error == ERR_TRADE_TOO_MANY_ORDERS)
     {
      const int order_limit = (int)AccountInfoInteger(ACCOUNT_LIMIT_ORDERS);
      if(order_limit > 0 && OrdersTotal() >= order_limit)
         return false;
     }
   return true;
  }

void MultiRecordReversePendingFailure(MultiGroupState &group, const int error)
  {
   group.reverse_pending_error = error;
   group.reverse_retry_count++;
   group.reverse_retry_after = TimeCurrent()
                               + MultiReversePendingRetryDelay(error,
                                                              group.reverse_retry_count);
   group.dirty = true;
   MultiSaveGroup(group);
   Print("Multi reverse pending failed, group=", group.id,
         ", error=", error, ", retry_after=",
         TimeToString(group.reverse_retry_after, TIME_DATE|TIME_SECONDS));
  }

void MultiClearReversePendingFailure(MultiGroupState &group)
  {
   if(group.reverse_retry_after == 0 && group.reverse_retry_count == 0
      && group.reverse_pending_error == 0)
      return;
   group.reverse_retry_after = 0;
   group.reverse_retry_count = 0;
   group.reverse_pending_error = 0;
   group.dirty = true;
   MultiSaveGroup(group);
  }

bool MultiPlaceReversePending(MultiGroupState &group, const int current_type)
  {
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
      MultiClearReversePendingFailure(group);
      return true;
     }
   if(!MultiReversePendingRetryAllowed(group))
      return false;
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
   ResetLastError();
   const int ticket = OrderSend(Symbol(), pending_type, volume, entry, 0,
                                pending_sl, pending_tp,
                                MultiGroupComment(group.id, false), InpMagicNumber,
                                0, clrOrange);
   if(ticket < 0)
     {
      const int error = GetLastError();
      MultiRecordReversePendingFailure(group, error);
      return false;
     }
   group.pending_ticket = ticket;
   group.pending_index = next_index;
   MultiClearReversePendingFailure(group);
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
   BasketRenewalPrepareStop(group, group.pending_index,
                            (int)promoted_type, promoted_total, (ulong)filled_ticket);
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
    BasketRenewalSaveTransition(group);
    MultiSetStops(group, promoted_type);
    if(!BasketRenewalConfirmFirstOrder(group, (int)promoted_type, promoted_total)) return true;
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

   if(group.reversal_count >= 最大反手次数)
     {
      BeginResetAfterMaxReversals();
      return true;
     }

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
   BasketRenewalPrepareStop(group,
      (group.cycle_index+1)%CycleLength(group.cycle_mode),
      (int)MultiSequenceDirection(group,(group.cycle_index+1)%CycleLength(group.cycle_mode)),
      next_group_lots);
   group.cumulative_loss_lots += stopped_group_volume;
   group.previous_grid_lots = group.grid_lots;
   const int next_index = (group.cycle_index + 1) % CycleLength(group.cycle_mode);
   const int next_type = MultiSequenceDirection(group, next_index);
   group.reversal_count++;
   group.cycle_index = next_index;
   group.pending_index = -1;
   group.pending_ticket = -1;
   group.transition_target_lots = next_group_lots;
   BasketRenewalSaveTransition(group);
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
   if(!BasketRenewalConfirmFirstOrder(group, (int)type, group.first_lots)) return true;
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

bool MultiRecoverRequestExposure(MultiGroupState &group)
  {
   if(!group.market_request_unresolved)
      return true;
   int ticket = -1;
   int type = OP_BUY;
   double volume = 0.0;
   double entry = 0.0;
   double stop_loss = 0.0;
   double take_profit = 0.0;
   if(!MultiFindPosition(group.id, ticket, type, volume, entry, stop_loss,
                         take_profit))
      return true;
   const double lot_step = MarketInfo(Symbol(), MODE_LOTSTEP);
   const double tolerance = lot_step > 0.0 ? lot_step * 0.5 : 0.0000001;
   const bool new_transition_exposure = !group.market_request_exposure_hydrated
      && group.transition_target_lots > 0.0
      && type == group.market_request_direction;
   if(group.anchor_price <= 0.0 || new_transition_exposure)
     {
      group.anchor_price = entry;
      group.last_entry = entry;
      group.linear_extreme = entry;
     }
   group.market_request_exposure_hydrated = true;
   if(group.first_lots <= 0.0)
      group.first_lots = volume;
   if(group.total_lots < volume)
      group.total_lots = volume;
   if(group.grid_lots <= 0.0)
      group.grid_lots = volume;
   group.dirty = true;
   MultiSaveGroup(group);
   if(!MultiSetStops(group, type) || !MultiStopsVerified(group, type))
     {
      Print("Recovered market request exposure is not protected yet, group=",
            group.id, ", request=", group.market_request_sequence);
      return false;
     }
   return true;
  }

bool MultiReconcileMarketRequest(MultiGroupState &group)
  {
   if(!group.market_request_unresolved)
      return true;
   const double visible_volume = MultiTotalLots(group.id,
                                                 group.market_request_direction);
   const double lot_step = MarketInfo(Symbol(), MODE_LOTSTEP);
   const double tolerance = lot_step > 0.0 ? lot_step * 0.5 : 0.0000001;
   if(visible_volume > group.market_request_volume_before + tolerance)
     {
      group.market_request_unresolved = false;
      group.market_request_exposure_hydrated = false;
      group.market_request_time = 0;
      group.market_request_volume_before = 0.0;
      group.dirty = true;
      MultiSaveGroup(group);
      Print("Multi market request reconciled from open exposure, group=", group.id,
            ", request=", group.market_request_sequence);
      return true;
     }

   const string request_tag = MultiGroupTag(group.id) + ".R"
                              + IntegerToString(group.market_request_sequence);
   for(int index = OrdersHistoryTotal() - 1; index >= 0; index--)
     {
      if(!OrderSelect(index, SELECT_BY_POS, MODE_HISTORY)
         || OrderSymbol() != Symbol() || OrderMagicNumber() != InpMagicNumber
         || OrderType() != group.market_request_direction
         || StringFind(OrderComment(), request_tag) < 0)
         continue;
      // A uniquely tagged historical market order proves that the request
      // executed even if it was closed before the next management pass.
      group.market_request_unresolved = false;
      group.market_request_exposure_hydrated = false;
      group.market_request_time = 0;
      group.market_request_volume_before = 0.0;
      group.transition_target_lots = 0.0;
      group.dirty = true;
      MultiSaveGroup(group);
      Print("Multi market request reconciled from history, group=", group.id,
            ", request=", group.market_request_sequence);
      return true;
     }
   return false;
  }

bool BasketRenewalAdoptInitialMT4(MultiGroupState &group)
  {
   if(group.basket_mode_at_start!=3 || group.pair_parent_id<=0)return false;
   // A confirmed stop stage is already independent of its initial parent.
   if(group.reversal_count>0 || group.cycle_index>0)
     {group.pair_parent_id=0;group.dirty=true;MultiSaveGroup(group);return false;}
   const int parent=R3GroupIndex(group.pair_parent_id);
   const bool parent_ended=parent<0 || !g_multi_groups[parent].active;
   BasketRenewalReconcileRequest(group);
   int ticket=-1,type=OP_BUY;double volume=0,entry=0,sl=0,tp=0;
   const bool live=R3Position(group.id,ticket,type,volume,entry,sl,tp);
   int pt=-1,pd=OP_BUY;double pv=0,pe=0,psl=0,ptp=0;
   const bool parent_ready=!parent_ended
      && R3Position(group.pair_parent_id,pt,pd,pv,pe,psl,ptp)
      && MultiStopsVerified(g_multi_groups[parent],pd);
   if(!live)
     {
      if(R3RequestUnknown(group) || R3HasPending(group.id))return true;
      if(!parent_ended)return !parent_ready;
      BasketFamilyState first;ZeroMemory(first);first.source_id=group.id;
      first.direction=group.first_direction==FIRST_BUY?OP_BUY:OP_SELL;
      volume=R3FirstLotsSince(first,entry);
      if(volume<0)return true;
      if(volume<=R3Tolerance())
        {group.active=false;group.transition_target_lots=0;
         group.dirty=true;MultiSaveGroup(group);return true;}
      type=first.direction;
     }
   const double target=group.transition_target_lots;
   if(group.first_lots<=0 || target>0)R3InitializeChild(group,type,volume,entry);
   if(live && (!MultiSetStops(group,type) || !MultiStopsVerified(group,type)))
     {MultiSaveGroup(group);return true;}
   if(group.renewal_request_state!=1)group.launch_attempted=false;
   if(R3RequestUnknown(group)) {group.dirty=true;MultiSaveGroup(group);return true;}
   // The old manager can complete an initial split while its parent is live.
   // A late partial after that parent ended is adopted without another send.
   if(live && !parent_ended && volume+R3Tolerance()<target)
     {group.dirty=true;MultiSaveGroup(group);return !parent_ready;}
   group.pair_parent_id=0;group.transition_target_lots=0;
   group.launch_confirmed=true;group.dirty=true;MultiSaveGroup(group);
   return true;
  }
void BasketRenewalProtectInitialMT4()
  {
   if(g_reset_pending)return;
   for(int i=0;i<ArraySize(g_multi_groups);i++)
     {
      if(!g_multi_groups[i].active || g_multi_groups[i].basket_mode_at_start!=3
         || g_multi_groups[i].pair_parent_id<=0)continue;
      MultiGroupState group=g_multi_groups[i];
      BasketRenewalAdoptInitialMT4(group);g_multi_groups[i]=group;
     }
  }

bool MultiManageGroup(MultiGroupState &group)
  {
   if(!group.active && group.basket_mode_at_start==3) return false;

   MultiRecoverRequestExposure(group);
   if(!MultiReconcileMarketRequest(group))
     {
      int pending_ticket = -1;
      int pending_type = OP_BUY;
      double pending_volume = 0.0;
      double pending_entry = 0.0;
      double pending_sl = 0.0;
      double pending_tp = 0.0;
      if(MultiFindPosition(group.id, pending_ticket, pending_type,
                           pending_volume, pending_entry, pending_sl,
                           pending_tp))
         if(!MultiSetStops(group, pending_type)
            || !MultiStopsVerified(group, pending_type))
            Print("Unresolved market request exposure is not protected yet, group=",
                  group.id);
      return true;
     }
   BasketRenewalReconcileRequest(group);
   if(BasketRenewalProtectOnly(group)) return true;
   if(BasketRenewalManagesChild(group)) return true;
   if(!BasketRenewalResumeStop(group)) return true;
   if(BasketRenewalAdoptInitialMT4(group))return true;
   if(group.initial_low_direction>group.id && group.initial_high_ticket<0
      && group.initial_low_ticket<0)
      MultiEnsureRecoveredOpposite(group.id);
   if(group.pair_parent_id>0 && group.basket_mode_at_start!=3)
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
      if(group.launch_attempted)
         return true;
      if(!MultiDeletePending(group.id))
         return true;
      const int expected_type = MultiSequenceDirection(group, group.cycle_index);
      g_multi_last_send_error=0;
      group.launch_attempted=true;
      group.dirty=true;
      MultiSaveGroup(group);
      if(!MultiOpenMarket(group, expected_type, group.transition_target_lots))
        {
         MultiRecordLaunchFailure(group,g_multi_last_send_error);
         return true;
        }
      group.launch_confirmed=true;
      group.launch_attempted=false;
      group.launch_failed=false;group.launch_error=0;
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
      if(group.basket_mode_at_start==3 && BasketRenewalFlatTakeProfit(group))
        {
         if(!MultiDeletePending(group.id)) return true;
         group.active=false; return false;
        }
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
         if(group.launch_attempted)
            return true;
         if(group.launch_retry_after>TimeCurrent())
            return true;
         g_multi_last_send_error=0;
         group.launch_attempted=true;
         group.dirty=true;MultiSaveGroup(group);
         if(!MultiOpenMarket(group, type, group.transition_target_lots))
           {
            MultiRecordLaunchFailure(group,g_multi_last_send_error);
            return true;
           }
         group.launch_attempted=false;
         group.launch_failed=false;group.launch_error=0;
         group.launch_retry_after=0;group.launch_attempt_count=0;
         if(!MultiFindPosition(group.id, ticket, type, total, entry,
                               stop_loss, take_profit))
            return true;
        }
      if(total > group.transition_target_lots + tolerance)
         return true;
      group.transition_target_lots = 0.0;
      group.launch_confirmed=true;
      group.launch_attempted=false;
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
      if(!BasketRenewalConfirmFirstOrder(group, (int)type, group.first_lots)) return true;
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
   BasketRenewalPrepareStop(group,
      (group.cycle_index+1)%CycleLength(group.cycle_mode),
      (int)MultiSequenceDirection(group,(group.cycle_index+1)%CycleLength(group.cycle_mode)),
      next_group_lots);
      if(group.basket_mode_at_start!=3)
      group.cumulative_loss_lots += group.total_lots;
      group.previous_grid_lots = group.grid_lots;
      if(!MultiClosePositions(group.id)) return false;
      if(group.basket_mode_at_start==3) group.cumulative_loss_lots += group.total_lots;
      const int next_index = (group.cycle_index + 1) % CycleLength(group.cycle_mode);
      const int next_type = MultiSequenceDirection(group, next_index);
      group.reversal_count++;
      group.cycle_index = next_index;
      group.pending_index = -1;
      group.pending_ticket = -1;
      group.transition_target_lots = next_group_lots;
   BasketRenewalSaveTransition(group);
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
      if(!BasketRenewalConfirmFirstOrder(group, (int)type, group.first_lots)) return true;
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
   if(!BasketRenewalConfirmFirstOrder(group, (int)type, group.first_lots)) return true;
   MultiPlaceReversePending(group, type);
   MultiPlaceGridPending(group, type);
   return true;
  }

void ProcessInitialPendingFillEvent()
  {
   if(g_reset_pending)
      return;
   if(InpDistanceMode == DISTANCE_CANDLE_RANGE
      && (kline_enable_multiple == 1 || IsPairedBasketMode()))
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
   if(CancelInitialPendingPairIfSpreadTooHigh())
      return;
   HandleInitialPendingFill();
  }

bool MultiTryOpenCandleGroup()
  {
   if(IsPairedBasketMode() && (MultiHasActiveGroups() || BasketRenewalHasWork())) return false;
   if(!IsInitialEntryAllowed()) return false;
   if(!IsInitialSpreadAllowed()) return false;
   double previous_high = 0.0;
   double previous_low = 0.0;
   int range_points = 0;
   int first_direction = OP_BUY;
   if(!GetPreviousCandleRange(previous_high, previous_low, range_points))
      return false;
   const datetime current_bar = iTime(Symbol(), Period(), 0);
   const bool once_per_bar = Korder_type == KORDER_ONCE_PER_BAR;
   if(once_per_bar && current_bar > 0
      && current_bar == g_multi_last_trigger_bar)
      return false;
   if(!once_per_bar
      && !GetBreakoutDirection(previous_high, previous_low, first_direction))
      return false;
   const int signal_direction = once_per_bar
      ? (ordertype == ORDERTYPE_FORWARD ? OP_BUY : OP_SELL)
      : first_direction;
   if(IsInitialSignalConsumed(current_bar, signal_direction))
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
    g_multi_groups[new_index] = state;
   if(once_per_bar)
     {
      if(IsPairedBasketMode())
        {
         MultiRemoveGroup(new_index);
         return StartInitialMultiOco(previous_high,previous_low,range_points,首单手数);
        }
       MultiSaveGroup(g_multi_groups[new_index]);
      if(!MultiPlaceInitialPendingPair(state, previous_high, previous_low,
                                       range_points, 首单手数))
        {
          g_multi_groups[new_index] = state;
         PrepareInitialSignal(current_bar, signal_direction);
         MultiRemoveGroup(new_index);
         return false;
        }
      g_multi_groups[new_index] = state;
      MultiSaveGroup(g_multi_groups[new_index]);
      if(current_bar > 0)
         MarkMultiCandleTriggerBar();
      return true;
     }
   if(IsPairedBasketMode())
     {
      MultiRemoveGroup(new_index);
      StartResolvedMultiPair(first_direction, range_points, range_points, 首单手数);
      if(Korder_type == KORDER_ONCE_PER_BAR && current_bar > 0)
         MarkMultiCandleTriggerBar();
      return true;
     }
   state.first_direction = first_direction == OP_BUY ? FIRST_BUY : FIRST_SELL;
    g_multi_groups[new_index] = state;
    MultiSaveGroup(g_multi_groups[new_index]);
    const bool market_opened = MultiOpenMarket(state, first_direction, 首单手数);
   int ticket = -1;
   int type = OP_BUY;
   double total = 0.0;
   double entry = 0.0;
   double stop_loss = 0.0;
   double take_profit = 0.0;
   if(!MultiFindPosition(state.id, ticket, type, total, entry, stop_loss, take_profit))
     {
       g_multi_groups[new_index] = state;
      PrepareInitialSignal(current_bar, signal_direction);
      if(state.market_request_unresolved)
        {
         state.dirty = true;
         g_multi_groups[new_index] = state;
         MultiSaveGroup(g_multi_groups[new_index]);
         return true;
        }
      MultiRemoveGroup(new_index);
      return false;
     }
    if(!market_opened)
       PrepareInitialSignal(current_bar, signal_direction);
   state.anchor_price = entry;
   state.last_entry = entry;
   state.linear_extreme = entry;
   state.first_lots = total;
   state.total_lots = total;
   state.grid_lots = total;
   if(state.market_request_unresolved)
     {
      if(!MultiSetStops(state, type) || !MultiStopsVerified(state, type))
         Print("Ambiguous multi market request exposure is not protected yet, group=",
               state.id);
      state.dirty = true;
      g_multi_groups[new_index] = state;
      MultiSaveGroup(g_multi_groups[new_index]);
      return true;
     }
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
   BasketRenewalBeginBatch();
   bool closed_group = false;
   for(int index = ArraySize(g_multi_groups) - 1; index >= 0; index--)
     {
      const bool was_active = g_multi_groups[index].active;
      MultiGroupState before = g_multi_groups[index];
      MultiManageGroup(g_multi_groups[index]);
      if(g_reset_pending)
        {
         ProcessReset();
         return;
        }
      if(index < 0 || index >= ArraySize(g_multi_groups))
         return;
      if(g_multi_groups[index].id != before.id)
         return;
      if(MultiStateChanged(before, g_multi_groups[index]))
         g_multi_groups[index].dirty = true;
      if(!g_multi_groups[index].active && (was_active || g_multi_groups[index].basket_mode_at_start==3))
        {
         MultiRemoveGroup(index);
         closed_group = true;
        }
      else if(g_multi_groups[index].active && g_multi_groups[index].dirty)
         MultiSaveGroup(g_multi_groups[index]);
      if(g_reset_pending) return;
     }
   BasketRenewalProcess();
   if(closed_group) return;
   MultiTryOpenCandleGroup();
  }

bool MultiHasActiveGroups()
  {
   for(int index=0; index<ArraySize(g_multi_groups); index++)
      if(g_multi_groups[index].active)
         return true;
   return false;
  }

void StartResolvedMultiPair(const int first_type, const int stop_points,
                            const int take_profit_points, const double lots,
                            const datetime signal_bar_time = 0,
                            const long signal_id = 0)

  {
   if(first_type != OP_BUY && first_type != OP_SELL)
      return;
   if(stop_points <= 0 || take_profit_points <= 0 || lots <= 0.0
      || !IsInitialSpreadAllowed())
      return;
   datetime effective_signal_bar = signal_bar_time > 0
                                   ? signal_bar_time : iTime(Symbol(), Period(), 0);
   if(effective_signal_bar <= 0)
      effective_signal_bar = TimeCurrent();
   if(!PrepareInitialSignal(effective_signal_bar, first_type, signal_id))
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
   original.launch_event_id=signal_id > 0 ? (int)(signal_id % 2147483000) : original_id;
   opposite.launch_event_id=original.launch_event_id;
   original.box_signal_bar_time=signal_bar_time;
   opposite.box_signal_bar_time=signal_bar_time;
   original.box_signal_id=signal_id;
   opposite.box_signal_id=signal_id;

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
   if(!BasketRenewalRegisterPair(篮子数量, original_id, original_id, opposite_id))
     { g_multi_groups[original_index].active=false;
       g_multi_groups[original_index+1].active=false; return; }
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
   const datetime signal_bar = iTime(Symbol(), Period(), 0);
   const int signal_direction = ordertype == ORDERTYPE_FORWARD ? OP_BUY : OP_SELL;
   if(!PrepareInitialSignal(signal_bar, signal_direction))
      return false;
   const int index=ArraySize(g_multi_groups);
   if(ArrayResize(g_multi_groups,index+2)!=index+2) return false;
   const int high_id=g_multi_next_id++;
   const int low_id=g_multi_next_id++;
   MultiGroupState high_group,low_group;
   MultiResetState(high_group,high_id);
   MultiResetState(low_group,low_id);
   high_group.first_direction=ordertype==ORDERTYPE_FORWARD ? FIRST_BUY : FIRST_SELL;
   low_group.first_direction=ordertype==ORDERTYPE_FORWARD ? FIRST_SELL : FIRST_BUY;
   high_group.cycle_mode=InpCycleMode; low_group.cycle_mode=InpCycleMode;
   high_group.stop_points=range_points; low_group.stop_points=range_points;
   high_group.take_profit_points=range_points; low_group.take_profit_points=range_points;
   high_group.first_lots=VolumeNormalize(lots);low_group.first_lots=VolumeNormalize(lots);
   high_group.pair_peer_id=low_id; low_group.pair_peer_id=high_id;
   high_group.launch_event_id=high_id; low_group.launch_event_id=high_id;
   high_group.initial_high_price=PriceNormalize(previous_high);
   low_group.initial_low_price=PriceNormalize(previous_low);
   g_multi_groups[index]=high_group; g_multi_groups[index+1]=low_group;
   MultiSaveGroup(g_multi_groups[index]); MultiSaveGroup(g_multi_groups[index+1]);
   if(!BasketRenewalRegisterPair(篮子数量, high_id, high_id, low_id)) return false;
   int high_ticket=-1,low_ticket=-1;
   const int high_type=ordertype==ORDERTYPE_FORWARD ? OP_BUY : OP_SELL;
   const int low_type=ordertype==ORDERTYPE_FORWARD ? OP_SELL : OP_BUY;
   g_multi_groups[index].launch_attempted=true;
   g_multi_groups[index].dirty=true;MultiSaveGroup(g_multi_groups[index]);
   g_multi_last_send_error=0;
   if(!PlaceInitialPendingOrder(high_type,previous_high,range_points,lots,
                                MultiInitialPendingComment(high_id,true),high_ticket))
     {
      if(g_multi_last_send_error==128)
        {MarkMultiCandleTriggerBar();return true;}
      if(g_multi_groups[index].basket_mode_at_start==3)
        {R3ClearRequest(g_multi_groups[index]);R3ClearRequest(g_multi_groups[index+1]);
         MultiSaveGroup(g_multi_groups[index]);MultiSaveGroup(g_multi_groups[index+1]);
         BasketRenewalInitialFailure(high_id,low_id);}
      MultiRemoveGroup(index+1);MultiRemoveGroup(index);return false;
     }
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
        {
         const int rollback_error=GetLastError();
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
         if(g_multi_groups[index+1].basket_mode_at_start==3)
           {R3ClearRequest(g_multi_groups[index+1]);MultiSaveGroup(g_multi_groups[index+1]);}
         MultiRemoveGroup(index+1);
         MarkMultiCandleTriggerBar();
         return true;
        }
      if(g_multi_groups[index].basket_mode_at_start==3)
        {R3ClearRequest(g_multi_groups[index]);R3ClearRequest(g_multi_groups[index+1]);
         MultiSaveGroup(g_multi_groups[index]);MultiSaveGroup(g_multi_groups[index+1]);
         BasketRenewalInitialFailure(high_id,low_id);}
      MultiRemoveGroup(index+1);MultiRemoveGroup(index);return false;
     }
   g_multi_groups[index].initial_high_ticket=high_ticket;
   g_multi_groups[index].launch_attempted=false;
   g_multi_groups[index].dirty=true; MultiSaveGroup(g_multi_groups[index]);
   g_multi_groups[index+1].initial_low_ticket=low_ticket;
   g_multi_groups[index+1].launch_attempted=false;
   g_multi_groups[index+1].dirty=true; MultiSaveGroup(g_multi_groups[index+1]);
   MarkMultiCandleTriggerBar();
   return true;
  }

void ManageAllMultiGroups()
  {
   BasketRenewalBeginBatch();
   for(int index=ArraySize(g_multi_groups)-1; index>=0; index--)
     {
      if(!g_multi_groups[index].active)
        {
         MultiRemoveGroup(index);
         continue;
        }
      MultiGroupState before=g_multi_groups[index];
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
     BasketRenewalProcess();
  }

int OnInit()
  {
#ifdef NMR_PROFILE_BOLLINGER_EXPANSION
   if(带宽比较K线根数 < 1 || 带宽比较K线根数 > 10000
      || 布林带周期 < 2 || 布林带周期 > 10000
      || !MathIsValidNumber(布林带标准差) || 布林带标准差 <= 0.0
      || (带宽距离模式 != BOLL_EXP_PERCENT && 带宽距离模式 != BOLL_EXP_FIXED)
      || (带宽距离模式 == BOLL_EXP_PERCENT
          && (!MathIsValidNumber(带宽距离百分比) || 带宽距离百分比 <= 0.0))
      || (带宽距离模式 == BOLL_EXP_FIXED && (固定止损距离 < 1 || 固定止盈距离 < 1)))
      return INIT_PARAMETERS_INCORRECT;
#endif
#ifdef NMR_PROFILE_AVERAGE_DOUBLE_CANDLE
   if(均值比较K线根数 < 1 || 均值比较K线根数 > 10000
      || !MathIsValidNumber(信号K线距离百分比) || 信号K线距离百分比 <= 0.0)
      return INIT_PARAMETERS_INCORRECT;
#endif

   g_start_operation_minutes[0] = ParseTimeMinutes(开始时间);
   g_end_operation_minutes[0] = ParseTimeMinutes(结束时间);
   g_start_operation_minutes[1] = ParseTimeMinutes(时段2开始时间);
   g_end_operation_minutes[1] = ParseTimeMinutes(时段2结束时间);
   g_start_operation_minutes[2] = ParseTimeMinutes(时段3开始时间);
   g_end_operation_minutes[2] = ParseTimeMinutes(时段3结束时间);
   const double fixed_lot_step = MarketInfo(Symbol(), MODE_LOTSTEP);
   const double fixed_lot_min = MarketInfo(Symbol(), MODE_MINLOT);
   const double fixed_lot_max = MarketInfo(Symbol(), MODE_MAXLOT);
   if(!MathIsValidNumber(FirstOrderFixedLots) || fixed_lot_step <= 0.0
      || FirstOrderFixedLots < fixed_lot_min || FirstOrderFixedLots > fixed_lot_max
      || MathAbs(FirstOrderFixedLots / fixed_lot_step
                 - MathRound(FirstOrderFixedLots / fixed_lot_step)) > 0.000001)
     {
      Print("止损首单固定手数不符合当前品种交易量要求。");
      return INIT_PARAMETERS_INCORRECT;
     }
   if(DynamicStopLossEnable != 0 && DynamicStopLossEnable != 1)
     {
      Print("动态止损必须为0或1。");
      return INIT_PARAMETERS_INCORRECT;
     }
   if(最大首单点差 < 0
       || InpInitialLots <= 0.0 || 首单手数倍数 <= 0.0
       || (FirstOrderLotType != 1 && FirstOrderLotType != 2 && FirstOrderLotType != 3)
       || (FavorableGridEnable != 0 && FavorableGridEnable != 1)
       || (DynamicStopLossEnable != 0 && DynamicStopLossEnable != 1)
        || !MathIsValidNumber(FirstOrderMult) || FirstOrderMult <= 0.0
        || !MathIsValidNumber(FirstOrderFixedLots) || FirstOrderFixedLots <= 0.0
       || InpGridCount < 0 || InpGridCount > MAX_GRID_COUNT
      || InpGridLotMultiplier <= 0.0
      || InpStopLossDistancePoints <= 0 || InpTakeProfitDistancePoints <= 0
       || InpCandleMinRangePoints <= 0 || InpCandleMaxRangePoints < InpCandleMinRangePoints
       || 箱体回看小时数 <= 0 || 箱体回看小时数 > 720
       || 箱体最小高度 <= 0 || 箱体最大高度 < 箱体最小高度
       || (箱体时间模式 != BOX_RANGE_ROLLING && 箱体时间模式 != BOX_RANGE_DAILY_SESSION)
       || ParseTimeMinutes(箱体开始时间) < 0 || ParseTimeMinutes(箱体结束时间) < 0
       || ParseTimeMinutes(箱体开始时间) == ParseTimeMinutes(箱体结束时间)
       || (InpDistanceMode == DISTANCE_BOX_BREAKOUT
           && (PeriodSeconds((ENUM_TIMEFRAMES)BoxRecognitionPeriod()) <= 0
               || 箱体观察窗口K线数 < 箱体最少完整往返 * 2 + 1
               || 箱体ATR周期 <= 0 || !MathIsValidNumber(箱体触碰ATR倍数)
               || 箱体触碰ATR倍数 <= 0.0 || 箱体上沿最少触碰 <= 0
               || 箱体下沿最少触碰 <= 0 || 箱体最少完整往返 <= 0
               || 箱体同侧触碰间隔 <= 0 || 箱体突破最小宽度 <= 0
               || 箱体突破最大宽度 < 箱体突破最小宽度
               || !MathIsValidNumber(箱体突破缓冲ATR倍数)
               || 箱体突破缓冲ATR倍数 <= 0.0))

       || !MathIsValidNumber(布林带止损百分比) || 布林带止损百分比 <= 0.0
       || !MathIsValidNumber(布林带盈亏比) || 布林带盈亏比 <= 0.0
       || 布林带最小止损距离 <= 0 || 布林带最大止损距离 < 布林带最小止损距离
       || InpAverageCandleCount <= 0 || InpAverageStopMultiplier <= 0.0
       || InpAverageTakeProfitMultiplier <= 0.0
       || ZigZag深度 <= 0 || ZigZag偏差 <= 0
       || ZigZag回退 <= 0 || ZigZag回退 >= ZigZag深度
       || ZigZag距离最小值 <= 0 || ZigZag距离最大值 < ZigZag距离最小值
       || !MathIsValidNumber(ZigZag止损百分比) || ZigZag止损百分比 <= 0.0
       || !MathIsValidNumber(ZigZag止盈倍数) || ZigZag止盈倍数 <= 0.0
       || 最大反手次数 < 0
       || (kline_enable_multiple != 0 && kline_enable_multiple != 1)
       || (篮子数量 != 1 && 篮子数量 != 2 && 篮子数量 != 3)
       || (Korder_type != KORDER_ONCE_PER_BAR && Korder_type != KORDER_REPEAT_PER_BAR)
      || g_start_operation_minutes[0] < 0 || g_end_operation_minutes[0] < 0
      || g_start_operation_minutes[1] < 0 || g_end_operation_minutes[1] < 0
      || g_start_operation_minutes[2] < 0 || g_end_operation_minutes[2] < 0)
      return INIT_PARAMETERS_INCORRECT;
   if(!AcquireExecutionOwnership())
      return INIT_FAILED;
   string ownership_error = "";
   if(!ValidateFixedProfileStartupState(ownership_error)
      || !PersistFixedProfileStateOwner())
     {
      if(StringLen(ownership_error) == 0)
         ownership_error = "无法保存固定策略状态身份。";
      Print(ownership_error);
      ReleaseExecutionOwnership();
      return INIT_FAILED;
     }
   g_active_first_direction = InpFirstDirection;
   g_active_cycle_mode = InpCycleMode;
   LoadState();
   MultiLoadGroups();
   BasketRenewalLoad();
   LoadBoxState();

   if(!EventSetTimer(1))
      Print("Unable to start the initial pending OCO timer.");
   return INIT_SUCCEEDED;
  }

void OnTimer()
  {
   if(g_reset_pending && BasketRenewalResetIsPending()) {ProcessReset();return;}
   ProcessInitialPendingFillEvent();
     BasketRenewalProtectInitialMT4();
     BasketRenewalProtectVisible();
  }

void OnTick()
  {
   if(!AcquireExecutionOwnership())
      return;
   if(InpDistanceMode == DISTANCE_CANDLE_RANGE && kline_enable_multiple == 1)
      ManageMultipleCandleGroups();
   else if(IsPairedBasketMode() || MultiHasActiveGroups() || BasketRenewalHasWork())
     {
      if(MultiHasActiveGroups() || BasketRenewalHasWork())
         ManageAllMultiGroups();
      else
         Manage();
     }
   else
      Manage();
  }

void OnDeinit(const int reason)
  {
   EventKillTimer();
   ReleaseExecutionOwnership();
  }
