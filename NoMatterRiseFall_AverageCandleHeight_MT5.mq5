#property strict
#property version   "1.00"
#property description "不管涨跌：AverageCandleHeight固定策略"
#define NMR_PROFILE_AVERAGE_CANDLE_HEIGHT
#define NMR_PROFILE_DISPLAY_NAME "平均K线高度"
#define NMR_INCLUDE_BOLLINGER_INPUTS
#define NMR_FIXED_PROFILE_ID 3
#define NMR_FIXED_DISTANCE_MODE DISTANCE_AVERAGE_CANDLE_RANGE
#define NMR_MAGIC_DEFAULT 2026101111
#include <Trade/Trade.mqh>
#include "NoMatterRiseFall_MT5_Core.mqh"
