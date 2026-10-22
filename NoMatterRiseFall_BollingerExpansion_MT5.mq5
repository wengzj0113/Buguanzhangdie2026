#property strict
#property version   "1.00"
#property description "不管涨跌：BollingerExpansion固定策略"
#define NMR_PROFILE_BOLLINGER_EXPANSION
#define NMR_INCLUDE_BOLLINGER_INPUTS
#define NMR_PROFILE_DISPLAY_NAME "布林带宽度倍增"
#define NMR_FIXED_PROFILE_ID 10
#define NMR_FIXED_DISTANCE_MODE DISTANCE_BOLLINGER_EXPANSION
#define NMR_MAGIC_DEFAULT 2026101812
#include <Trade/Trade.mqh>
#include "NoMatterRiseFall_MT5_Core.mqh"
