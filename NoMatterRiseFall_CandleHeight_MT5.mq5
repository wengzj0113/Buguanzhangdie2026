#property strict
#property version   "1.00"
#property description "不管涨跌：CandleHeight固定策略"
#define NMR_PROFILE_CANDLE_HEIGHT
#define NMR_PROFILE_DISPLAY_NAME "K线高度"
#define NMR_FIXED_PROFILE_ID 2
#define NMR_FIXED_DISTANCE_MODE DISTANCE_CANDLE_RANGE
#define NMR_MAGIC_DEFAULT 2026101110
#include <Trade/Trade.mqh>
#include "NoMatterRiseFall_MT5_Core.mqh"
