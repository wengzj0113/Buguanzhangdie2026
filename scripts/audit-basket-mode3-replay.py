"""Audit first-order fills read from actual deal history, not request messages."""
import argparse
import json
import math
from pathlib import Path
import re


def audit(data):
    mode, step = data['mode'], float(data['volume_step'])
    if mode not in (2, 3) or not math.isfinite(step) or step <= 0:
        raise ValueError('invalid audit mode or volume step')
    if data.get('unresolved_events'):
        raise ValueError(f"unresolved events: {data['unresolved_events']}")
    events = data['events']
    if (mode == 2 and events) or (mode == 3 and not events):
        raise ValueError('mode2 must not renew; mode3 must exercise renewal')
    keys, children = set(), set()
    for e in events:
        key = tuple(e[k] for k in ('family', 'generation', 'source', 'stopseq'))
        child_key = e['family'], e['child']
        if key in keys or child_key in children:
            raise ValueError(f'{key}: duplicated event or child')
        keys.add(key)
        children.add(child_key)
        if e['child'] <= 0 or e['child'] == e['source'] or not e['peer_finished_in_event_batch']:
            raise ValueError(f'{key}: invalid identity or unfinished peer')
        p, c = e['primary_direction'], e['child_direction']
        if p not in ('buy', 'sell') or c not in ('buy', 'sell') or p == c:
            raise ValueError(f'{key}: directions are not opposite')
        totals = []
        for field in ('primary_first_deals', 'child_first_deals'):
            fills = e[field]
            if not fills or any(not math.isfinite(v) or v <= 0 for v in fills):
                raise ValueError(f'{key}: missing/invalid actual fills')
            totals.append(math.fsum(fills))
        if abs(totals[0] - totals[1]) > step * .5 + 1e-9:
            raise ValueError(f'{key}: unequal actual first volumes {totals}')
        if any(e[k] != 0 for k in ('child_cycle_at_start', 'child_reversals_at_start', 'child_loss_lots_at_start')):
            raise ValueError(f'{key}: child inherited source progress')
        if not e['primary_protected'] or not e['child_protected']:
            raise ValueError(f'{key}: unverified protection')
    return dict(passed=True, events_checked=len(events), unresolved_count=0)


def parse_journal(text, *, mode, volume_step=.01):
    fills, bindings, consumed = {}, {}, set()
    for line in text.splitlines():
        if '[R3_' not in line:
            continue
        f = dict(re.findall(r'\[([A-Z_]+)=([^\]]*)\]', line))
        if not all(k in f for k in ('F', 'GEN', 'SOURCE', 'SEQ')):
            continue
        key = tuple(int(f[k]) for k in ('F', 'GEN', 'SOURCE', 'SEQ'))
        if '[R3_NO_RENEWAL]' in line:
            consumed.add(key)
        elif '[R3_FIRST]' in line:
            records = fills.setdefault(key, {}).setdefault(f['ROLE'], {})
            record = dict(volume=float(f['VOLUME']), direction=int(f['DIR']),
                          protected=float(f['SL']) > 0 and float(f['TP']) > 0,
                          cycle=int(f['CYCLE']), reversals=int(f['REV']),
                          loss=float(f['LOSS']), group=int(f['GROUP']))
            if f['DEAL'] in records and records[f['DEAL']] != record:
                raise ValueError(f'{key}: conflicting deal evidence')
            records[f['DEAL']] = record
        elif '[R3_BIND]' in line and f.get('PAIRED') == '1':
            key = (key[0], key[1] - 1, key[2], key[3])
            value = int(f['CHILD']), f.get('PEER_FINISHED') == '1'
            if key in bindings and bindings[key] != value:
                raise ValueError(f'{key}: conflicting binding')
            bindings[key] = value
    events = []
    for key, (child, peer_finished) in bindings.items():
        roles = fills.get(key, {})
        p, c = list(roles.get('SOURCE', {}).values()), list(roles.get('CHILD', {}).values())
        if not p or not c:
            raise ValueError(f'{key}: binding without actual first-order deals')
        if any(v['group'] != key[2] for v in p) or any(v['group'] != child for v in c):
            raise ValueError(f'{key}: fills belong to another group')
        if len({v['direction'] for v in p}) != 1 or len({v['direction'] for v in c}) != 1:
            raise ValueError(f'{key}: mixed directions')
        events.append(dict(family=key[0], generation=key[1], source=key[2], stopseq=key[3], child=child,
                           peer_finished_in_event_batch=peer_finished,
                           primary_direction='buy' if p[0]['direction'] == 0 else 'sell',
                           child_direction='buy' if c[0]['direction'] == 0 else 'sell',
                           primary_first_deals=[v['volume'] for v in p], child_first_deals=[v['volume'] for v in c],
                           primary_cycle_after=p[0]['cycle'], child_cycle_at_start=c[0]['cycle'],
                           child_reversals_at_start=c[0]['reversals'], child_loss_lots_at_start=c[0]['loss'],
                           primary_protected=all(v['protected'] for v in p), child_protected=all(v['protected'] for v in c),
                           primary_deal_ids=list(roles['SOURCE']), child_deal_ids=list(roles['CHILD'])))
    return dict(mode=mode, volume_step=volume_step, events=events,
                unresolved_events=[list(k) for k in fills if k not in bindings and k not in consumed])


def main():
    parser = argparse.ArgumentParser()
    source = parser.add_mutually_exclusive_group(required=True)
    source.add_argument('--input', type=Path)
    source.add_argument('--journal', type=Path)
    parser.add_argument('--mode', type=int, default=3)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--normalized-output', type=Path)
    parser.add_argument('--minimum-events', type=int, default=1)
    args = parser.parse_args()
    try:
        data = (json.loads(args.input.read_text(encoding='utf-8-sig')) if args.input else
                parse_journal(args.journal.read_text(encoding='utf-8-sig'), mode=args.mode))
        if args.normalized_output:
            args.normalized_output.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding='utf-8')
        result = audit(data)
        if data['mode'] == 3 and result['events_checked'] < args.minimum_events:
            raise ValueError('insufficient renewal coverage')
    except (ValueError, KeyError, TypeError) as error:
        result = dict(passed=False, error=str(error))
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding='utf-8')
    print(json.dumps(result, ensure_ascii=False))
    return 0 if result['passed'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
