from pathlib import Path
import json
import subprocess


ROOT = Path(__file__).resolve().parents[1]


def ps_function(text, name):
    start = text.index('function ' + name + ' ')
    opening = text.index('{', start)
    depth, end = 1, opening + 1
    while depth:
        depth += (text[end] == '{') - (text[end] == '}')
        end += 1
    return text[start:end]


def test_log_collection_handles_agent_log_cleanup(tmp_path):
    runner = (ROOT / 'scripts/test-basket-mode3-mt5.ps1').read_text(encoding='utf-8-sig')
    functions = '\n'.join(ps_function(runner, name) for name in (
        'Get-TesterLogSnapshot', 'Read-TesterLogSince'))
    script = tmp_path / 'check.ps1'
    script.write_text(functions + r'''
$log=Join-Path $PSScriptRoot 'agent.log'
@('old header','old end') | Set-Content -LiteralPath $log
$snapshot=Get-TesterLogSnapshot $log
'new line' | Add-Content -LiteralPath $log
$appended=@(Read-TesterLogSince $log $snapshot)
@('cleaned header','actual first fill','actual child fill','pass') | Set-Content -LiteralPath $log
$rotated=@(Read-TesterLogSince $log $snapshot)
@('old header','changed content','actual pass') | Set-Content -LiteralPath $log
$sameHeader=@(Read-TesterLogSince $log $snapshot)
@{appended=$appended;rotated=$rotated;sameHeader=$sameHeader} | ConvertTo-Json -Compress
''', encoding='utf-8-sig')
    result = subprocess.run(['powershell.exe', '-NoProfile', '-File', str(script)],
                            check=True, capture_output=True, text=True)
    data = json.loads(result.stdout)
    assert data['appended'] == ['new line']
    assert data['rotated'] == ['cleaned header', 'actual first fill', 'actual child fill', 'pass']
    assert data['sameHeader'] == ['old header', 'changed content', 'actual pass']
