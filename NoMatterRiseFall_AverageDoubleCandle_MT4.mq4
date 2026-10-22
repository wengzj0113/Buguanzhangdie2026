#property strict
#property version   "1.00"
#property description "不管涨跌：AverageDoubleCandle固定策略"
#define NMR_PROFILE_AVERAGE_DOUBLE_CANDLE
#define NMR_PROFILE_DISPLAY_NAME "均值两倍K线"
#define NMR_FIXED_PROFILE_ID 9
#define NMR_FIXED_DISTANCE_MODE DISTANCE_AVERAGE_DOUBLE_CANDLE
#define NMR_MAGIC_DEFAULT 2026101801
void MultiClearAll();
void StartResolvedMultiPair(const int first_type, const int stop_points,
                            const int take_profit_points, const double lots,
                            const datetime signal_bar_time = 0,
                            const long signal_id = 0);
bool MultiHasActiveGroups();
#include "NoMatterRiseFall_MT4_Core.mqh"
