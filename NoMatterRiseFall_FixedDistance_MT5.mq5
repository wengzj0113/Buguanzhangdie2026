#property strict
#property version   "1.00"
#property description "不管涨跌：FixedDistance固定策略"
#define NMR_PROFILE_FIXED_DISTANCE
#define NMR_PROFILE_DISPLAY_NAME "固定距离"
#define NMR_INCLUDE_BOLLINGER_INPUTS
#define NMR_FIXED_PROFILE_ID 1
#define NMR_FIXED_DISTANCE_MODE DISTANCE_FIXED
#define NMR_MAGIC_DEFAULT 2026101109
#include <Trade/Trade.mqh>
#include "NoMatterRiseFall_MT5_Core.mqh"
