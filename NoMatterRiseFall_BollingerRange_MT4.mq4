#property strict
#property version   "1.00"
#property description "不管涨跌：BollingerRange固定策略"
#define NMR_PROFILE_BOLLINGER_RANGE
#define NMR_PROFILE_DISPLAY_NAME "布林带区间"
#define NMR_INCLUDE_BOLLINGER_INPUTS
#define NMR_FIXED_PROFILE_ID 5
#define NMR_FIXED_DISTANCE_MODE DISTANCE_BOLLINGER_RANGE
#define NMR_MAGIC_DEFAULT 2026101105
void MultiClearAll();
void StartResolvedMultiPair(const int first_type, const int stop_points,
                            const int take_profit_points, const double lots,
                            const datetime signal_bar_time = 0,
                            const long signal_id = 0);
bool MultiHasActiveGroups();
#include "NoMatterRiseFall_MT4_Core.mqh"
