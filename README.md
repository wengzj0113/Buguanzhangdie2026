# 不管涨跌 EA

本目录包含同一策略的MT5与MT4版本：

- `NoMatterRiseFall_MT5.mq5` / `NoMatterRiseFall_MT5.ex5`
- `NoMatterRiseFall_MT4.mq4` / `NoMatterRiseFall_MT4.ex4`

策略在当前品种没有本EA订单时按 `InpFirstDirection` 开首单；随后在当前单止损价位挂反向止损单，手数为当前手数乘 `InpReverseMultiplier`。止盈后删除反向挂单并结束本轮。

默认参数：首单0.01手、反向倍数2.0、止损500点、止盈500点。参数均可在EA输入项中调整。

这是递增手数策略，连续止损会快速增加风险，请先在模拟盘和策略测试器中验证经纪商的最小手数、手数上限、止损距离和保证金条件。
