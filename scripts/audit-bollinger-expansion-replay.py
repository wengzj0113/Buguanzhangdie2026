"""Audit actual initial groups and first broker protection modifications in saved MT5 journals."""
import argparse
import datetime
import json
from pathlib import Path
import re


def audit(root: Path):
    results = []
    probe_ratios = {}
    probe = root / "probe-lazy-signals.log"
    if probe.exists():
        for bar, ratio in re.findall(r"\[BAR=([^\]]+)\].*\[RATIO=([\d.]+)\]", probe.read_text(encoding="utf-8-sig")):
            probe_ratios[bar] = float(ratio)
    for case, baskets in (("percent", 1), ("fixed", 2), ("midline_reject", 0)):
        candidates = sorted(root.glob(f"BollingerExpansion_{case}_*.log"))
        if not candidates:
            raise RuntimeError(f"Missing journal for {case}")
        path = candidates[-1]
        log = path.read_text(encoding="utf-8-sig")
        current = None
        seen = set()
        entries = []
        signals = {}
        modifications = {}
        consumed_bars = set()
        independent_signals = 0
        for line in log.splitlines():
            signal = re.search(
                r"\[BOLLINGER_EXPANSION_SIGNAL\]\[BAR=([^\]]+)\].*"
                r"\[SL_POINTS=(\d+)\]\[TP_POINTS=(\d+)\]", line
            )
            if signal:
                current = (signal[1], int(signal[2]), int(signal[3]))
                assert signal[1] not in signals, f"Repeated signal: {case} {signal[1]}"
                signals[signal[1]] = 0
                if probe_ratios:
                    next_bar = datetime.datetime.strptime(signal[1], "%Y.%m.%d %H:%M") + datetime.timedelta(minutes=5)
                    ratio = re.search(r"\[WIDTH_POINTS=([\d.]+)\]\[AVERAGE_POINTS=([\d.]+)\]", line)
                    assert abs(float(ratio[1]) / float(ratio[2]) - probe_ratios[next_bar.strftime("%Y.%m.%d %H:%M")]) < 1e-7
                    independent_signals += 1
            if "[EVENT=SIGNAL_READY]" in line:
                event_time = re.search(r"\t(\d{4}\.\d{2}\.\d{2} \d{2}:\d{2}):\d{2}   ", line)[1]
                time = datetime.datetime.strptime(event_time, "%Y.%m.%d %H:%M")
                bar = time.replace(minute=time.minute // 5 * 5)
                assert bar not in consumed_bars, f"Repeated signal consumption: {case} {bar}"
                consumed_bars.add(bar)
            if "[EVENT=POSITION_CONFIRMED]" in line:
                sid = re.search(r"\[SIGNAL_ID=(\d+)\]", line)[1]
                position = int(re.search(r"\[POSITION=(\d+)\]", line)[1])
                if sid not in seen:
                    assert current is not None
                    seen.add(sid)
                    entries.append((current, position))
                    signals[current[0]] += 1
            modified = re.search(
                r"position modified \[#(\d+) (buy|sell) [\d.]+ XAUUSD "
                r"([\d.]+) sl: ([\d.]+) tp: ([\d.]+)\]", line
            )
            if modified:
                modifications.setdefault(int(modified[1]), tuple(float(modified[i]) for i in (3, 4, 5)))
        assert signals and len(consumed_bars) == len(signals), (case, signals, consumed_bars)
        if case == "midline_reject" and probe_ratios:
            expected = set()
            for bar, ratio in probe_ratios.items():
                time = datetime.datetime.strptime(bar, "%Y.%m.%d %H:%M")
                if ratio >= 2 and 1 <= time.hour < 23:
                    expected.add((time - datetime.timedelta(minutes=5)).strftime("%Y.%m.%d %H:%M"))
            assert set(signals) == expected, (case, "Missing later signals", expected - set(signals))
        assert all(value == baskets for value in signals.values()), (case, signals)
        for (bar, sl_points, tp_points), position in entries:
            entry, sl, tp = modifications[position]
            assert abs(abs(entry - sl) - sl_points * .01) < .010001, (case, bar, position, "SL")
            assert abs(abs(tp - entry) - tp_points * .01) < .010001, (case, bar, position, "TP")
        report = path.with_suffix(".htm").read_text(encoding="utf-16")
        trades = int(re.search(r"交易总计:</td>\s*<td nowrap><b>(\d+)", report)[1])
        deals = int(re.search(r"总成交:</td>\s*<td nowrap><b>(\d+)", report)[1])
        results.append(dict(case=case, signal_bars=len(signals), consumed_bars=len(consumed_bars),
                            independent_probe_signals_verified=independent_signals,
                            initial_groups=len(entries), initial_protection_verified=len(entries),
                            closed_trades=trades, deals=deals))
    (root / "trade-audit.json").write_text(json.dumps(results, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps(results, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("directory", type=Path)
    audit(parser.parse_args().directory)
