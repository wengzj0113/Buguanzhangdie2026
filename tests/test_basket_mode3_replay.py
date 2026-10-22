import importlib.util
from pathlib import Path
import copy
import pytest

PATH = Path(__file__).resolve().parents[1] / 'scripts/audit-basket-mode3-replay.py'


def audit_module():
    assert PATH.exists(), 'the actual-fill auditor is required'
    spec = importlib.util.spec_from_file_location('basket_auditor', PATH)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def valid():
    return dict(mode=3, volume_step=.01, unresolved_events=[], events=[dict(
        family=1, generation=0, source=2, stopseq=1, child=3,
        peer_finished_in_event_batch=True,
        primary_direction='buy', child_direction='sell',
        primary_first_deals=[.02, .01], child_first_deals=[.03],
        primary_cycle_after=1, child_cycle_at_start=0, child_reversals_at_start=0,
        child_loss_lots_at_start=0., primary_protected=True, child_protected=True,
    )])


def test_actual_split_first_orders_are_accepted():
    assert audit_module().audit(valid())['passed']


@pytest.mark.parametrize('change', [
    {'child_first_deals': [.02]}, {'child_direction': 'buy'},
    {'child_cycle_at_start': 1}, {'child_reversals_at_start': 1},
    {'child_loss_lots_at_start': .01}, {'primary_protected': False},
    {'child_protected': False}, {'peer_finished_in_event_batch': False},
    {'primary_first_deals': []}, {'child_first_deals': [float('nan')]},
])
def test_invalid_actual_fill_evidence_is_rejected(change):
    data = valid()
    data['events'][0].update(change)
    with pytest.raises(ValueError):
        audit_module().audit(data)


def test_duplicate_event_and_child_ids_are_rejected():
    data = valid()
    data['events'].append(copy.deepcopy(data['events'][0]))
    with pytest.raises(ValueError):
        audit_module().audit(data)
    data['events'][1]['stopseq'] = 2
    with pytest.raises(ValueError):
        audit_module().audit(data)


def test_mode3_empty_or_unresolved_is_not_a_pass():
    data = valid()
    data['events'] = []
    with pytest.raises(ValueError):
        audit_module().audit(data)
    data = valid()
    data['unresolved_events'] = ['unknown receipt']
    with pytest.raises(ValueError):
        audit_module().audit(data)


def test_mode2_no_renewal_control():
    assert audit_module().audit(dict(mode=2, volume_step=.01, events=[], unresolved_events=[]))['passed']


def test_log_parser_requires_real_deals_for_both_sides():
    parser = audit_module().parse_journal
    lines = (
        '[R3_FIRST][F=1][GEN=0][SOURCE=2][SEQ=1][ROLE=SOURCE][GROUP=2][DEAL=20][DIR=0][VOLUME=0.03][SL=90][TP=110][CYCLE=1][REV=1][LOSS=0.01]\n'
        '[R3_FIRST][F=1][GEN=0][SOURCE=2][SEQ=1][ROLE=CHILD][GROUP=3][DEAL=21][DIR=1][VOLUME=0.03][SL=110][TP=90][CYCLE=0][REV=0][LOSS=0]\n'
        '[R3_BIND][F=1][GEN=1][SOURCE=2][SEQ=1][CHILD=3][DIR=1][LOTS=0.03][PAIRED=1][PEER_FINISHED=1]'
    )
    assert audit_module().audit(parser(lines, mode=3))['passed']
    with pytest.raises(ValueError):
        audit_module().audit(parser(lines.splitlines()[-1], mode=3))
