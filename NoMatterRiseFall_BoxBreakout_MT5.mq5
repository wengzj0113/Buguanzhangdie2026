#property strict
#property version   "1.00"
#property description "不管涨跌：BoxBreakout固定策略"
#define NMR_PROFILE_BOX_BREAKOUT
#define NMR_PROFILE_DISPLAY_NAME "箱体确认突破"
#define NMR_FIXED_PROFILE_ID 8
#define NMR_FIXED_DISTANCE_MODE DISTANCE_BOX_BREAKOUT
#define NMR_MAGIC_DEFAULT 2026101116
#include <Trade/Trade.mqh>
#include "NoMatterRiseFall_MT5_Core.mqh"
