#property strict
#property version   "1.00"
#property description "不管涨跌：BollingerRange固定策略"
#define NMR_PROFILE_BOLLINGER_RANGE
#define NMR_PROFILE_DISPLAY_NAME "布林带区间"
#define NMR_INCLUDE_BOLLINGER_INPUTS
#define NMR_FIXED_PROFILE_ID 5
#define NMR_FIXED_DISTANCE_MODE DISTANCE_BOLLINGER_RANGE
#define NMR_MAGIC_DEFAULT 2026101113
#include <Trade/Trade.mqh>
#include "NoMatterRiseFall_MT5_Core.mqh"
