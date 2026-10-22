#property strict
#property version   "1.00"
#property description "不管涨跌：AverageCandleHeight固定策略"
#define NMR_PROFILE_AVERAGE_CANDLE_HEIGHT
#define NMR_PROFILE_DISPLAY_NAME "平均K线高度"
#define NMR_INCLUDE_BOLLINGER_INPUTS
#define NMR_FIXED_PROFILE_ID 3
#define NMR_FIXED_DISTANCE_MODE DISTANCE_AVERAGE_CANDLE_RANGE
#define NMR_MAGIC_DEFAULT 2026101103
void MultiClearAll();
void StartResolvedMultiPair(const int first_type, const int stop_points,
                            const int take_profit_points, const double lots,
                            const datetime signal_bar_time = 0,
                            const long signal_id = 0);
bool MultiHasActiveGroups();
#include "NoMatterRiseFall_MT4_Core.mqh"
