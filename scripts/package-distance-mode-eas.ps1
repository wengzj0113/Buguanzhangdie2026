param(
    [string] $SourceRoot = (Split-Path -Parent $PSScriptRoot),
    [string] $OutputRoot = (Join-Path (Split-Path -Parent $PSScriptRoot) 'dist\DistanceModeEAs')
)

$ErrorActionPreference = 'Stop'
$profiles = @(
    'FixedDistance',
    'CandleHeight',
    'AverageCandleHeight',
    'LongCandle',
    'BollingerRange',
    'ZigZagSwing',
    'BoxHeight',
    'BoxBreakout',
    'AverageDoubleCandle',
    'BollingerExpansion'
)

function Copy-RequiredFile {
    param([string] $Source, [string] $Destination)

    if (-not (Test-Path -LiteralPath $Source -PathType Leaf)) {
        throw "Required release file is missing: $Source"
    }
    $item = Get-Item -LiteralPath $Source
    if ($item.Length -le 0) {
        throw "Required release file is empty: $Source"
    }
    $destinationDirectory = Split-Path -Parent $Destination
    New-Item -ItemType Directory -Path $destinationDirectory -Force | Out-Null
    Copy-Item -LiteralPath $Source -Destination $Destination -Force
}

foreach ($profile in $profiles) {
    foreach ($platform in @('MT4', 'MT5')) {
        $extension = if ($platform -eq 'MT4') { '.mq4' } else { '.mq5' }
        $bytecodeExtension = if ($platform -eq 'MT4') { '.ex4' } else { '.ex5' }
        $sourceBase = "NoMatterRiseFall_${profile}_${platform}"
        $expertsDirectory = Join-Path (Join-Path (Join-Path $OutputRoot $profile) $platform) 'Experts'
        Copy-RequiredFile (Join-Path $SourceRoot ($sourceBase + $extension)) (Join-Path $expertsDirectory ($sourceBase + $extension))
        Copy-RequiredFile (Join-Path $SourceRoot ($sourceBase + $bytecodeExtension)) (Join-Path $expertsDirectory ($sourceBase + $bytecodeExtension))
        $coreName = if ($platform -eq 'MT4') { 'NoMatterRiseFall_MT4_Core.mqh' } else { 'NoMatterRiseFall_MT5_Core.mqh' }
        Copy-RequiredFile (Join-Path $SourceRoot $coreName) (Join-Path $expertsDirectory $coreName)
        Copy-RequiredFile (Join-Path $SourceRoot 'NoMatterRiseFall_BasketRenewal.mqh') (Join-Path $expertsDirectory 'NoMatterRiseFall_BasketRenewal.mqh')

        $notePath = Join-Path (Join-Path $OutputRoot $profile) 'README.txt'
        if (-not (Test-Path -LiteralPath $notePath -PathType Leaf)) {
            $note = @"
$profile is a fixed-distance-mode EA package.

Install the compiled file from $platform\Experts into the matching terminal's Experts folder.
Each profile/platform build has its own default Magic number. Keep distinct Magic numbers when running several profiles on the same account and symbol. A scope already reserved or holding unowned orders is rejected at initialization.
Review the profile-specific inputs and shared risk/order inputs before enabling AutoTrading.
"@
            Set-Content -LiteralPath $notePath -Value $note -Encoding UTF8
        }
    }
}

$zigzagMt4 = Join-Path $SourceRoot 'Indicators\MT4\ZigZag.ex4'
$zigzagMt5 = Join-Path $SourceRoot 'Indicators\MT5\Examples\ZigZag.ex5'
Copy-RequiredFile $zigzagMt4 (Join-Path (Join-Path (Join-Path (Join-Path $OutputRoot 'ZigZagSwing') 'MT4') 'Indicators') 'ZigZag.ex4')
Copy-RequiredFile $zigzagMt5 (Join-Path (Join-Path (Join-Path (Join-Path $OutputRoot 'ZigZagSwing') 'MT5') 'Indicators\Examples') 'ZigZag.ex5')

Write-Output "Packaged ten fixed profiles for MT4 and MT5 under $OutputRoot"
