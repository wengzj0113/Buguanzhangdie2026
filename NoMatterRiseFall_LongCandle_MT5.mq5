#property strict
#property version   "1.00"
#property description "不管涨跌：LongCandle固定策略"
#define NMR_PROFILE_LONG_CANDLE
#define NMR_PROFILE_DISPLAY_NAME "长K线市价"
#define NMR_FIXED_PROFILE_ID 4
#define NMR_FIXED_DISTANCE_MODE DISTANCE_LONG_CANDLE
#define NMR_MAGIC_DEFAULT 2026101112
#include <Trade/Trade.mqh>
#include "NoMatterRiseFall_MT5_Core.mqh"
