param(
    [ValidateSet('MT4', 'MT5', 'Both')]
    [string] $Target = 'Both',
    [ValidateSet('Legacy', 'FixedDistance', 'CandleHeight', 'AverageCandleHeight', 'LongCandle', 'BollingerRange', 'ZigZagSwing', 'BoxHeight', 'BoxBreakout', 'AverageDoubleCandle', 'BollingerExpansion', 'All')]
    [string] $Profile = 'Legacy',
    [string] $MetaEditor4Path,
    [string] $MetaEditor5Path,
    [switch] $ListCompilers,
    [switch] $ListSources
)

$ErrorActionPreference = 'Stop'

function Add-ExistingPath {
    param([System.Collections.Generic.List[string]] $Paths, [string] $Path)

    if ([string]::IsNullOrWhiteSpace($Path)) { return }
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return }

    $resolved = (Resolve-Path -LiteralPath $Path).Path
    if (-not $Paths.Contains($resolved)) { $Paths.Add($resolved) }
}

function Get-InstallLocations {
    param([ValidateSet('MT4', 'MT5')][string] $Platform)

    $locations = [System.Collections.Generic.List[string]]::new()
    $uninstallRoots = @(
        'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall',
        'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall',
        'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall'
    )

    foreach ($uninstallRoot in $uninstallRoots) {
        if (-not (Test-Path $uninstallRoot)) { continue }
        foreach ($entry in (Get-ChildItem $uninstallRoot -ErrorAction SilentlyContinue)) {
            $app = Get-ItemProperty $entry.PSPath -ErrorAction SilentlyContinue
            if (-not $app.DisplayName) { continue }
            $isMatch = if ($Platform -eq 'MT5') {
                $app.DisplayName -match '(?i)MetaTrader\s*5|MT5'
            } else {
                $app.DisplayName -match '(?i)MetaTrader\s*4|MT4'
            }
            if ($isMatch -and $app.InstallLocation) { $locations.Add([string]$app.InstallLocation) }
        }
    }

    return $locations
}

function Find-MetaEditor {
    param(
        [ValidateSet('MT4', 'MT5')][string] $Platform,
        [string] $ExplicitPath
    )

    $paths = [System.Collections.Generic.List[string]]::new()
    $environmentPath = if ($Platform -eq 'MT4') { $env:METAEDITOR_MT4_PATH } else { $env:METAEDITOR_MT5_PATH }
    Add-ExistingPath $paths $ExplicitPath
    Add-ExistingPath $paths $environmentPath

    $programRoots = @($env:ProgramFiles, ${env:ProgramFiles(x86)}, $env:LOCALAPPDATA)
    $preferredNames = if ($Platform -eq 'MT5') {
        @('MetaEditor64.exe', 'metaeditor64.exe')
    } else {
        @('metaeditor.exe', 'MetaEditor.exe')
    }

    foreach ($programRoot in $programRoots) {
        if (-not $programRoot -or -not (Test-Path -LiteralPath $programRoot)) { continue }
        foreach ($preferredName in $preferredNames) {
            $preferredFolder = if ($Platform -eq 'MT5') { 'MetaTrader 5' } else { 'MetaTrader 4 IC Markets Global' }
            Add-ExistingPath $paths (Join-Path (Join-Path $programRoot $preferredFolder) $preferredName)
        }

        $installDirs = Get-ChildItem -LiteralPath $programRoot -Directory -ErrorAction SilentlyContinue |
            Where-Object {
                if ($Platform -eq 'MT5') { $_.Name -match '(?i)MetaTrader.*5|MT5' }
                else { $_.Name -match '(?i)MetaTrader.*4|MT4' }
            }
        foreach ($installDir in $installDirs) {
            foreach ($preferredName in $preferredNames) {
                Add-ExistingPath $paths (Join-Path $installDir.FullName $preferredName)
            }
        }
    }

    foreach ($installLocation in (Get-InstallLocations $Platform)) {
        foreach ($preferredName in $preferredNames) {
            Add-ExistingPath $paths (Join-Path $installLocation $preferredName)
        }
    }

    if ($paths.Count -eq 0) {
        $overrideName = if ($Platform -eq 'MT4') { 'METAEDITOR_MT4_PATH' } else { 'METAEDITOR_MT5_PATH' }
        $parameterName = if ($Platform -eq 'MT4') { '-MetaEditor4Path' } else { '-MetaEditor5Path' }
        throw "Could not find the $Platform MetaEditor. Set $overrideName or pass $parameterName."
    }

    return $paths[0]
}

function Invoke-MetaEditorCompile {
    param(
        [ValidateSet('MT4', 'MT5')][string] $Platform,
        [string] $EditorPath,
        [string] $SourcePath
    )

    $source = (Resolve-Path -LiteralPath $SourcePath).Path
    $extension = if ($Platform -eq 'MT4') { '.ex4' } else { '.ex5' }
    $output = [System.IO.Path]::ChangeExtension($source, $extension)
    $logDirectory = Join-Path ([System.IO.Path]::GetTempPath()) 'CodexMetaEditorLogs'
    New-Item -ItemType Directory -Path $logDirectory -Force | Out-Null
    $log = Join-Path $logDirectory ("{0}_{1:yyyyMMdd_HHmmss}_{2}.log" -f $Platform, (Get-Date), [guid]::NewGuid().ToString('N'))
    $compileStarted = (Get-Date).ToUniversalTime()

    $process = Start-Process -FilePath $EditorPath `
        -ArgumentList @("/compile:`"$source`"", "/log:`"$log`"") `
        -WindowStyle Hidden -Wait -PassThru

    if (-not (Test-Path -LiteralPath $log -PathType Leaf)) {
        throw "$Platform MetaEditor did not create a compile log. Editor: $EditorPath"
    }

    $logText = Get-Content -LiteralPath $log -Raw
    $result = [regex]::Match($logText, 'Result:\s*(\d+)\s+errors?,\s*(\d+)\s+warnings?', 'IgnoreCase')
    if (-not $result.Success) {
        throw "$Platform compile log did not contain a final error/warning summary. Log: $log"
    }

    $errors = [int]$result.Groups[1].Value
    $warnings = [int]$result.Groups[2].Value
    # MetaEditor builds may return process exit code 1 despite a successful compile.
    # The final compiler result line is the authoritative success signal.
    if ($errors -ne 0) {
        throw "$Platform compile failed: $errors errors, $warnings warnings. Log: $log"
    }
    if (-not (Test-Path -LiteralPath $output -PathType Leaf)) {
        throw "$Platform compile reported success but did not create $output. Log: $log"
    }

    $outputFile = Get-Item -LiteralPath $output
    if ($outputFile.Length -le 0 -or $outputFile.LastWriteTimeUtc -lt $compileStarted.AddSeconds(-2)) {
        throw "$Platform compile output is empty or was not refreshed: $output. Log: $log"
    }

    Write-Output ("{0}: 0 errors, {1} warnings; generated {2}" -f $Platform, $warnings, $output)
    Write-Output ("Compiler log: {0}" -f $log)
}

function Get-CompileSources {
    param(
        [string] $Root,
        [ValidateSet('MT4', 'MT5', 'Both')][string] $Target,
        [ValidateSet('Legacy', 'FixedDistance', 'CandleHeight', 'AverageCandleHeight', 'LongCandle', 'BollingerRange', 'ZigZagSwing', 'BoxHeight', 'BoxBreakout', 'AverageDoubleCandle', 'BollingerExpansion', 'All')][string] $Profile
    )

    $profiles = if ($Profile -eq 'All') {
        @('FixedDistance', 'CandleHeight', 'AverageCandleHeight', 'LongCandle', 'BollingerRange', 'ZigZagSwing', 'BoxHeight', 'BoxBreakout', 'AverageDoubleCandle', 'BollingerExpansion')
    } elseif ($Profile -eq 'Legacy') {
        @('Legacy')
    } else {
        @($Profile)
    }
    $platforms = if ($Target -eq 'Both') { @('MT4', 'MT5') } else { @($Target) }
    $sources = [System.Collections.Generic.List[object]]::new()

    foreach ($platform in $platforms) {
        $extension = if ($platform -eq 'MT4') { '.mq4' } else { '.mq5' }
        $outputExtension = if ($platform -eq 'MT4') { '.ex4' } else { '.ex5' }
        foreach ($profileName in $profiles) {
            $baseName = if ($profileName -eq 'Legacy') {
                "NoMatterRiseFall_$platform"
            } else {
                "NoMatterRiseFall_${profileName}_$platform"
            }
            $sourcePath = Join-Path $Root ($baseName + $extension)
            if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) {
                throw "Expected source file was not found: $sourcePath"
            }
            $sources.Add([pscustomobject]@{
                Profile = $profileName
                Platform = $platform
                SourcePath = (Resolve-Path -LiteralPath $sourcePath).Path
                OutputPath = [System.IO.Path]::ChangeExtension((Resolve-Path -LiteralPath $sourcePath).Path, $outputExtension)
            })
        }
    }

    return $sources.ToArray()
}

try {
    if ($ListCompilers) {
        @{
            MT4 = Find-MetaEditor -Platform MT4 -ExplicitPath $MetaEditor4Path
            MT5 = Find-MetaEditor -Platform MT5 -ExplicitPath $MetaEditor5Path
        } | ConvertTo-Json -Compress
        exit 0
    }

    $root = Split-Path -Parent $PSScriptRoot
    $sources = @(Get-CompileSources -Root $root -Target $Target -Profile $Profile)
    if ($ListSources) {
        @{ Sources = @($sources | ForEach-Object {
            [pscustomobject]@{
                Profile = $_.Profile
                Platform = $_.Platform
                SourcePath = $_.SourcePath
                OutputPath = $_.OutputPath
            }
        }) } | ConvertTo-Json -Compress -Depth 4
        exit 0
    }

    foreach ($source in $sources) {
        $platform = $source.Platform
        $editorPath = if ($platform -eq 'MT4') {
            Find-MetaEditor -Platform MT4 -ExplicitPath $MetaEditor4Path
        } else {
            Find-MetaEditor -Platform MT5 -ExplicitPath $MetaEditor5Path
        }
        Invoke-MetaEditorCompile -Platform $platform -EditorPath $editorPath -SourcePath $source.SourcePath
    }
} catch {
    [Console]::Error.WriteLine($_.Exception.Message)
    exit 1
}
