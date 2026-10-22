param(
    [string] $SourceRoot = (Split-Path -Parent $PSScriptRoot),
    [string] $TerminalRoot = (Join-Path (Split-Path -Parent $PSScriptRoot) 'mt5_isolated_test'),
    [string] $OutputRoot = (Join-Path (Split-Path -Parent $PSScriptRoot) 'validation\average-double-candle-2026-10-18'),
    [int] $TimeoutSeconds = 180
)

$ErrorActionPreference = 'Stop'
$terminal = Join-Path $TerminalRoot 'terminal64.exe'
$binary = Join-Path $SourceRoot 'NoMatterRiseFall_AverageDoubleCandle_MT5.ex5'
if (-not (Test-Path -LiteralPath $terminal) -or -not (Test-Path -LiteralPath $binary)) {
    throw 'The isolated MT5 terminal and freshly compiled EA are required.'
}
if (Get-CimInstance Win32_Process -Filter "name='terminal64.exe'" | Where-Object { $_.ExecutablePath -eq $terminal }) {
    throw 'The isolated terminal is already running. This runner will not interrupt an existing terminal.'
}
New-Item -ItemType Directory -Path $OutputRoot -Force | Out-Null
$testerBinary = Join-Path $TerminalRoot 'MQL5\Experts\NoMatterRiseFall_AverageDoubleCandle_MT5.ex5'
Copy-Item -LiteralPath $binary -Destination $testerBinary -Force
$binaryHash = (Get-FileHash -LiteralPath $binary -Algorithm SHA256).Hash
if ((Get-FileHash -LiteralPath $testerBinary -Algorithm SHA256).Hash -ne $binaryHash) {
    throw 'Tester binary SHA256 does not match the compiled output.'
}

$cases = @(
    @{ Name='single'; N=20; Multiplier=2.0; OrderType=0; Percent=50; Baskets=1; Grid=2; Favorable=0; Dynamic=0; TakeProfit=0; Cycle=0; Magic=2026101891 },
    @{ Name='double'; N=5; Multiplier=1.5; OrderType=1; Percent=25; Baskets=2; Grid=3; Favorable=1; Dynamic=1; TakeProfit=1; Cycle=3; Magic=2026101892 }
)
$logDate = Get-Date -Format 'yyyyMMdd'
$results = @()
foreach ($case in $cases) {
    $name = 'AverageDoubleCandle_' + $case.Name + '_' + $logDate
    $setName = $name + '.set'
    $setPath = Join-Path $TerminalRoot ('MQL5\Profiles\Tester\' + $setName)
    $settings = @"
均值比较K线根数=$($case.N)
均值触发倍数=$($case.Multiplier)
开单方式=$($case.OrderType)
信号K线距离百分比=$($case.Percent)
篮子数量=$($case.Baskets)
首单手数=0.01
循环模式=$($case.Cycle)
最大反手次数=5
网格数量=$($case.Grid)
有利方向加单=$($case.Favorable)
动态止损=$($case.Dynamic)
止盈移动模式=$($case.TakeProfit)
订单识别编号=$($case.Magic)
开始时间=01:00
结束时间=23:00
v_enable=0
"@
    Set-Content -LiteralPath $setPath -Value $settings -Encoding Unicode
    Copy-Item -LiteralPath $setPath -Destination (Join-Path $OutputRoot $setName) -Force
    $ini = Join-Path $TerminalRoot ($name + '.ini')
    $config = @"
[Tester]
Expert=NoMatterRiseFall_AverageDoubleCandle_MT5.ex5
ExpertParameters=$setName
Symbol=XAUUSD
Period=M5
Model=0
FromDate=2026.01.01
ToDate=2026.01.03
Deposit=10000
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
    Copy-Item -LiteralPath $ini -Destination (Join-Path $OutputRoot ($name + '.ini')) -Force
    $offsets = @{}
    foreach ($log in Get-ChildItem (Join-Path $TerminalRoot ('Tester\Agent-*\logs\' + $logDate + '.log')) -ErrorAction SilentlyContinue) {
        $offsets[$log.FullName] = @(Get-Content -LiteralPath $log.FullName).Count
    }
    $report = Join-Path $TerminalRoot ($name + '.htm')
    $started = Get-Date
    Write-Output "Starting MT5 generated-tick backtest: $($case.Name), N=$($case.N), percent=$($case.Percent), baskets=$($case.Baskets)"
    $proc = Start-Process -FilePath $terminal -ArgumentList @('/portable', ('/config:' + $ini)) -WorkingDirectory $TerminalRoot -WindowStyle Hidden -PassThru
    try {
        $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
        $complete = $false
        while ((Get-Date) -lt $deadline) {
            if (Test-Path -LiteralPath $report) {
                if ((Get-Item -LiteralPath $report).LastWriteTime -ge $started) { $complete = $true; break }
            }
            if (-not (Get-Process -Id $proc.Id -ErrorAction SilentlyContinue)) { break }
            Start-Sleep -Seconds 1
        }
        if (-not $complete) { throw "MT5 $($case.Name) did not produce a refreshed report." }
        Start-Sleep -Seconds 2
        $journalLines = @()
        foreach ($log in Get-ChildItem (Join-Path $TerminalRoot ('Tester\Agent-*\logs\' + $logDate + '.log'))) {
            $skip = if ($offsets.ContainsKey($log.FullName)) { $offsets[$log.FullName] } else { 0 }
            $journalLines += @(Get-Content -LiteralPath $log.FullName | Select-Object -Skip $skip)
        }
        $journal = $journalLines -join [Environment]::NewLine
        Set-Content -LiteralPath (Join-Path $OutputRoot ($name + '.log')) -Value $journal -Encoding UTF8
        if ($journal -match 'array out of range|critical error|zero divide|stack overflow|Orders limit reached') {
            throw "Runtime error in MT5 $($case.Name). See saved journal."
        }
        if ($journal -notmatch 'Test passed') { throw "MT5 $($case.Name) has no successful tester completion record." }
        $signals = [regex]::Matches($journal, '\[AVERAGE_DOUBLE_CANDLE_SIGNAL\]\[BAR=([^\]]+)\]\[N=(\d+)\]\[MULTIPLIER=([\d.]+)\]\[RANGE_POINTS=([\d.]+)\]\[AVERAGE_POINTS=([\d.]+)\]\[DIRECTION=(\d+)\]\[PERCENT=([\d.]+)\]\[DISTANCE_POINTS=(\d+)\]')
        if ($signals.Count -lt 1) { throw "MT5 $($case.Name) did not exercise a valid entry signal." }
        $seen = @{}
        foreach ($signal in $signals) {
            $bar = $signal.Groups[1].Value
            if ($seen.ContainsKey($bar)) { throw "Duplicate signal bar logged: $bar" }
            $seen[$bar] = $true
            $n = [int]$signal.Groups[2].Value
            $multiplier = [double]::Parse($signal.Groups[3].Value, [cultureinfo]::InvariantCulture)
            $range = [double]::Parse($signal.Groups[4].Value, [cultureinfo]::InvariantCulture)
            $average = [double]::Parse($signal.Groups[5].Value, [cultureinfo]::InvariantCulture)
            $direction = [int]$signal.Groups[6].Value
            $percent = [double]::Parse($signal.Groups[7].Value, [cultureinfo]::InvariantCulture)
            $distance = [int]$signal.Groups[8].Value
            if ($n -ne $case.N -or $multiplier -ne $case.Multiplier -or $percent -ne $case.Percent -or $range + 0.000001 -lt $multiplier * $average -or $direction -notin @(0, 1)) {
                throw "Invalid signal calculation at $bar"
            }
            $rawDistance = $range * $percent / 100
            if ([Math]::Abs($distance - $rawDistance) -gt 0.500001) { throw "Invalid percentage distance at $bar" }
        }
        foreach ($file in Get-ChildItem -LiteralPath $TerminalRoot -File | Where-Object { $_.BaseName -like ($name + '*') -and $_.Extension -in @('.htm','.png') }) {
            Copy-Item -LiteralPath $file.FullName -Destination (Join-Path $OutputRoot $file.Name) -Force
        }
        $results += [pscustomobject]@{ Case=$case.Name; N=$case.N; Percent=$case.Percent; Baskets=$case.Baskets; SignalBars=$signals.Count; RuntimeErrors=0; Report=($name + '.htm'); BinarySHA256=$binaryHash }
        Write-Output "Passed $($case.Name): $($signals.Count) unique signal bars, threshold and percentage distances verified, no runtime errors."
    } finally {
        $processInfo = Get-CimInstance Win32_Process -Filter ('ProcessId=' + $proc.Id) -ErrorAction SilentlyContinue
        if ($processInfo -and $processInfo.ExecutablePath -eq $terminal) { Stop-Process -Id $proc.Id -Force }
    }
}
$results | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $OutputRoot 'results.json') -Encoding UTF8
$results | Format-Table Case,N,Percent,Baskets,SignalBars,RuntimeErrors -AutoSize
