#property strict
#property version   "1.00"
#property description "不管涨跌：ZigZagSwing固定策略"
#define NMR_PROFILE_ZIGZAG_SWING
#define NMR_PROFILE_DISPLAY_NAME "ZigZag波段"
#define NMR_FIXED_PROFILE_ID 6
#define NMR_FIXED_DISTANCE_MODE DISTANCE_ZIGZAG_RANGE
#define NMR_MAGIC_DEFAULT 2026101114
#include <Trade/Trade.mqh>
#include "NoMatterRiseFall_MT5_Core.mqh"
