param(
    [string] $SourceRoot = (Split-Path -Parent $PSScriptRoot),
    [string] $TerminalRoot = (Join-Path (Split-Path -Parent $PSScriptRoot) 'mt5_isolated_test'),
    [string] $OutputRoot = (Join-Path (Split-Path -Parent $PSScriptRoot) 'validation\basket-mode3-2026-10-20'),
    [int] $TimeoutSeconds = 180,
    [int] $Scenario = 0,
    [switch] $Core,
    [switch] $Candle,
    [switch] $SkipCompile
)
$ErrorActionPreference = 'Stop'
function Get-TesterLogSnapshot {
    param([string]$Path)
    $lines=@(Get-Content -LiteralPath $Path)
    [pscustomobject]@{Count=$lines.Count;First=$(if($lines.Count){$lines[0]}else{''});Last=$(if($lines.Count){$lines[-1]}else{''})}
}
function Read-TesterLogSince {
    param([string]$Path,$Snapshot)
    $lines=@(Get-Content -LiteralPath $Path)
    $skip=0
    if($null -ne $Snapshot -and $Snapshot.Count -gt 0 -and $lines.Count -ge $Snapshot.Count -and
        $lines[0] -eq $Snapshot.First -and $lines[$Snapshot.Count-1] -eq $Snapshot.Last) {
        $skip=$Snapshot.Count
    }
    # Tester agents can clean the daily log on startup, even when the new log
    # grows longer than the previous one. An old line offset is then invalid.
    $lines | Select-Object -Skip $skip | ForEach-Object {$_.ToString()}
}
$OutputRoot = [IO.Path]::GetFullPath($OutputRoot)
$terminal = Join-Path $TerminalRoot 'terminal64.exe'
if (-not (Test-Path -LiteralPath $terminal)) { throw 'Isolated terminal missing.' }
if (Get-CimInstance Win32_Process -Filter "name='terminal64.exe'" | Where-Object {$_.ExecutablePath -eq $terminal}) {
    throw 'The isolated terminal is in use; no existing process will be interrupted.'
}
New-Item -ItemType Directory -Force -Path $OutputRoot | Out-Null
if($Candle){$Core=$true}
$base = if($Candle){'BasketMode3Probe_Candle_MT5'}elseif($Core){'BasketMode3Probe_Core_MT5'}else{'BasketMode3Probe_MT5'}
$tag = if($Candle){"candle-case$Scenario"}elseif($Core){"core-case$Scenario"}else{"canonical-case$Scenario"}
$probe = Join-Path $SourceRoot ("validation\basket-mode3-2026-10-20\$base.mq5")
$compileLog = Join-Path $OutputRoot ($tag+'-compile.log')
$binary = [IO.Path]::ChangeExtension($probe,'.ex5')
$dependencies=@($probe,(Join-Path $SourceRoot 'NoMatterRiseFall_BasketRenewal.mqh'),(Join-Path $SourceRoot 'validation\basket-mode3-2026-10-20\BasketMode3Probe_MT5.mq5'))
$dependencies+=if($Core){Join-Path $SourceRoot 'NoMatterRiseFall_MT5_Core.mqh'}else{Join-Path $SourceRoot 'NoMatterRiseFall_MT5.mq5'}
if($Core){$dependencies+=Join-Path $SourceRoot $(if($Candle){'NoMatterRiseFall_CandleHeight_MT5.mq5'}else{'NoMatterRiseFall_FixedDistance_MT5.mq5'})}
if(-not $SkipCompile){
    $compilers=(& (Join-Path $PSScriptRoot 'compile-mql.ps1') -ListCompilers | ConvertFrom-Json)
    $editor=$compilers.MT5
    $compileStarted=Get-Date
    Start-Process -FilePath $editor -ArgumentList @("/compile:`"$probe`"", "/log:`"$compileLog`"") -WindowStyle Hidden -Wait | Out-Null
    if ((Get-Content -LiteralPath $compileLog -Raw) -notmatch 'Result: 0 errors') { throw 'Probe compile failed.' }
    if(-not (Test-Path -LiteralPath $binary) -or (Get-Item -LiteralPath $binary).LastWriteTime -lt $compileStarted.AddSeconds(-2)){throw 'Probe bytecode not refreshed.'}
} else {
    foreach($dependency in $dependencies){if((Get-Item -LiteralPath $binary).LastWriteTime -lt (Get-Item -LiteralPath $dependency).LastWriteTime){throw 'Probe bytecode is stale; compile required.'}}
}
$sourceHashes=@($dependencies | Select-Object -Unique | ForEach-Object {[pscustomobject]@{Path=$_;SHA256=(Get-FileHash -LiteralPath $_).Hash}})
$testerBinary=Join-Path $TerminalRoot ("MQL5\Experts\$base.ex5")
Copy-Item -LiteralPath $binary -Destination $testerBinary -Force
if((Get-FileHash -LiteralPath $testerBinary).Hash -ne (Get-FileHash -LiteralPath $binary).Hash){throw 'Tester binary hash mismatch.'}
$setName='BasketMode3Probe.set'
$baskets=if($Scenario -eq 2){1}elseif($Scenario -eq 30){2}else{3}
$lotType=if($Scenario -in @(8,37,41,51,54)){2}elseif($Scenario -in @(38,39,42,52,55)){3}else{1}
$typeMultiplier=if($lotType -eq 2){1.5}else{2}
$initialLot=if($Scenario -in @(8,24,37,41,51,54)){0.02}else{0.01}
$grid=if($Scenario -eq 41){3}elseif($Scenario -in @(40,42)){2}else{0}
$cycle=if($Scenario -eq 40){3}elseif($Scenario -eq 41){2}elseif($Scenario -eq 42){1}else{0}
$dynamic=if($Scenario -eq 41){1}else{0}
$favorable=if($Scenario -eq 42){1}else{0}
$distance=if($Scenario -eq 43){1}else{0}
$deposit=if($Scenario -eq 49){1}else{1000000}
$magic=2026102091+$Scenario+$(if($Core){100}else{0})
$settings=@"
ProbeScenario=$Scenario
篮子数量=$baskets
首单手数=$initialLot
止损首单类型=$lotType
首单类型2倍数=$typeMultiplier
止损首单固定手数=0.03
循环模式=$cycle
最大反手次数=10
网格数量=$grid
动态止损=$dynamic
有利方向加单=$favorable
止盈移动模式=$dynamic
距离模式=$distance
K线开单模式=0
K线多组=0
K线最小高度=50
K线最大高度=5000
订单识别编号=$magic
固定止损距离=500
固定止盈距离=500
开始时间=00:00
结束时间=23:59
v_enable=0
"@
Set-Content -LiteralPath (Join-Path $TerminalRoot ('MQL5\Profiles\Tester\'+$setName)) -Value $settings -Encoding Unicode
Set-Content -LiteralPath (Join-Path $OutputRoot ($tag+'.set')) -Value $settings -Encoding Unicode
$name=$base+'_'+$tag+'_'+(Get-Date -Format 'yyyyMMdd_HHmmss')
$ini=Join-Path $OutputRoot ($name+'.ini')
$config=@"
[Tester]
Expert=$base.ex5
ExpertParameters=$setName
Symbol=XAUUSD
Period=M5
Model=0
FromDate=2026.01.02
ToDate=2026.01.03
Deposit=$deposit
Currency=USD
Leverage=100
ExecutionMode=0
Optimization=0
Visual=0
Report=$name
ReplaceReport=1
ShutdownTerminal=0
"@
Set-Content -LiteralPath $ini -Value $config -Encoding ASCII
$date=Get-Date -Format 'yyyyMMdd'
$offsets=@{}
foreach($log in Get-ChildItem (Join-Path $TerminalRoot ("Tester\Agent-*\logs\$date.log")) -ErrorAction SilentlyContinue){
    $offsets[$log.FullName]=Get-TesterLogSnapshot $log.FullName
}
$started=Get-Date
$proc=Start-Process -FilePath $terminal -ArgumentList @('/portable',('/config:'+$ini)) -WorkingDirectory $TerminalRoot -WindowStyle Hidden -PassThru
try {
    $report=Join-Path $TerminalRoot ($name+'.htm')
    $deadline=(Get-Date).AddSeconds($TimeoutSeconds)
    while((Get-Date) -lt $deadline){
        if((Test-Path -LiteralPath $report) -and (Get-Item -LiteralPath $report).LastWriteTime -ge $started){break}
        if(-not (Get-Process -Id $proc.Id -ErrorAction SilentlyContinue)){break}
        Start-Sleep -Seconds 1
    }
    if(-not (Test-Path -LiteralPath $report)){throw 'Probe report timeout.'}
    $lines=@()
    foreach($log in Get-ChildItem (Join-Path $TerminalRoot ("Tester\Agent-*\logs\$date.log"))){
        $snapshot=if($offsets.ContainsKey($log.FullName)){$offsets[$log.FullName]}else{$null}
        $lines+=@(Read-TesterLogSince $log.FullName $snapshot)
    }
    $journal=$lines -join [Environment]::NewLine
    Set-Content -LiteralPath (Join-Path $OutputRoot 'probe.log') -Value $journal -Encoding UTF8
    Set-Content -LiteralPath (Join-Path $OutputRoot ($tag+'.log')) -Value $journal -Encoding UTF8
    Copy-Item -LiteralPath $report -Destination (Join-Path $OutputRoot ($tag+'.htm')) -Force
    if($journal -match 'R3_PROBE_FAIL|array out of range|zero divide|critical error'){throw 'Native probe failed; inspect probe.log.'}
    if($journal -notmatch 'R3_PROBE_PASS'){throw 'Native probe did not reach its assertions.'}
    if($Scenario -notin @(5,9,10,15,16,19,20,21,24,25,27,28,29,35,46,47,48,49,56,57,58,59,60,61,62,64,65,66,67)){
        $auditMode=if($Scenario -eq 30){2}else{3}
        & uv run -- python (Join-Path $SourceRoot 'scripts\audit-basket-mode3-replay.py') --journal (Join-Path $OutputRoot ($tag+'.log')) --mode $auditMode --minimum-events 2 --normalized-output (Join-Path $OutputRoot ($tag+'-audit-input.json')) --output (Join-Path $OutputRoot ($tag+'-audit-result.json'))
        if($LASTEXITCODE -ne 0){throw 'Actual first-fill audit failed.'}
    }
    [pscustomobject]@{Scenario=$Scenario;Core=[bool]$Core;Passed=$true;BinarySHA256=(Get-FileHash -LiteralPath $binary).Hash;Sources=$sourceHashes;Journal=(Join-Path $OutputRoot ($tag+'.log'))} | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $OutputRoot ($tag+'-result.json')) -Encoding UTF8
    Write-Output "Native mode3 probe passed: $tag."
} finally {
    if(Get-Process -Id $proc.Id -ErrorAction SilentlyContinue){Stop-Process -Id $proc.Id -Force}
}
