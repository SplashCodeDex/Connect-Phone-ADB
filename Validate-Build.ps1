<#
.SYNOPSIS
    Validate-Build.ps1 - Pre-flight build gate for Connect Phone ADB
.DESCRIPTION
    Catches the exact class of bugs that shipped as the "dead tray icon" saga (v1.9.4.x-1.9.9.0):
    malformed engine XAML (e.g. a missing </Button> closing tag), missing FindName targets,
    broken resource references, missing assets, BOM-less encoding that PowerShell 5.1 misreads,
    and invalid manifests. Exits with code 1 on ANY failure so PackMSIX.ps1 / CI can hard-abort.
.NOTES
    Must run on an STA thread (WPF XamlReader requirement). Self-relaunches under
    Windows PowerShell -STA if invoked from an MTA host (e.g. pwsh 7).
#>
[CmdletBinding()]
param()

# WPF window creation requires STA. pwsh 7 defaults to MTA - relaunch under powershell.exe -STA.
if ([System.Threading.Thread]::CurrentThread.GetApartmentState() -ne 'STA') {
    Write-Host "Re-launching validator under STA (Windows PowerShell)..." -ForegroundColor DarkGray
    powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File $PSCommandPath
    exit $LASTEXITCODE
}

$root = $PSScriptRoot
$script:Passes = 0
$script:Failures = 0

function Gate {
    param([string]$Name, [bool]$Ok, [string]$Detail = "")
    if ($Ok) {
        $script:Passes++
        Write-Host "  [PASS] $Name" -ForegroundColor Green
    } else {
        $script:Failures++
        Write-Host "  [FAIL] $Name" -ForegroundColor Red
        if ($Detail) { Write-Host "         $Detail" -ForegroundColor DarkYellow }
    }
}

Add-Type -AssemblyName PresentationFramework

$enginePath   = Join-Path $root 'MSIX_Source\bin\Connect-Engine.ps1'
$manifestPath = Join-Path $root 'MSIX_Source\AppxManifest.xml'
$themesDir    = Join-Path $root 'MSIX_Source\Themes'
$assetsDir    = Join-Path $root 'MSIX_Source\Assets'

Write-Host "`n=== 1. PowerShell syntax ===" -ForegroundColor Cyan
$prodScripts = @(
    'MSIX_Source\bin\Connect-Engine.ps1',
    'PackMSIX.ps1',
    'SignMSIX.ps1',
    'Install-App.ps1',
    'Validate-Build.ps1'
)
foreach ($rel in $prodScripts) {
    $p = Join-Path $root $rel
    if (-not (Test-Path $p)) { Gate "PS syntax: $rel" $false "File not found"; continue }
    $errs = $null
    [System.Management.Automation.Language.Parser]::ParseFile($p, [ref]$null, [ref]$errs) | Out-Null
    $detail = ($errs | Select-Object -First 3 | ForEach-Object { "Line $($_.Extent.StartLineNumber): $($_.Message)" }) -join ' | '
    Gate "PS syntax: $rel" ($errs.Count -eq 0) $detail
}

Write-Host "`n=== 2. Engine encoding (PS 5.1 reads BOM-less files as ANSI) ===" -ForegroundColor Cyan
$engineBytes = [System.IO.File]::ReadAllBytes($enginePath)
$hasUtf8Bom = ($engineBytes.Length -ge 3 -and $engineBytes[0] -eq 0xEF -and $engineBytes[1] -eq 0xBB -and $engineBytes[2] -eq 0xBF)
$hasUtf16Bom = ($engineBytes.Length -ge 2 -and (($engineBytes[0] -eq 0xFF -and $engineBytes[1] -eq 0xFE) -or ($engineBytes[0] -eq 0xFE -and $engineBytes[1] -eq 0xFF)))
$engineRaw = [System.IO.File]::ReadAllText($enginePath)
$hasNonAscii = $engineRaw -match '[^\x00-\x7F]'
Gate "Engine has BOM (or is pure ASCII)" ($hasUtf8Bom -or $hasUtf16Bom -or -not $hasNonAscii) `
    "File contains non-ASCII characters but has no BOM - PowerShell 5.1 will misread it (mojibake)."

Write-Host "`n=== 3. Engine XAML full load (the 'dead tray' detector) ===" -ForegroundColor Cyan
$script:Win = $null
$xaml = $null
$xStart = $engineRaw.IndexOf('<Window xmlns=')
$xEnd = $engineRaw.IndexOf('</Window>') + 9
Gate "Engine XAML block located" ($xStart -ge 0 -and $xEnd -gt $xStart)
if ($xStart -ge 0 -and $xEnd -gt $xStart) {
    $xaml = $engineRaw.Substring($xStart, $xEnd - $xStart)
    # Substitute the here-string interpolation exactly like the engine does at runtime
    $needle = @'
$($PSScriptRoot -replace '\\', '/')
'@
    $binFwd = (Join-Path $root 'MSIX_Source\bin') -replace '\\', '/'
    $xaml = $xaml.Replace($needle, $binFwd)
    $loadErr = $null
    try {
        $reader = New-Object System.Xml.XmlNodeReader ([xml]$xaml)
        $script:Win = [System.Windows.Markup.XamlReader]::Load($reader)
        $reader.Close()
    } catch { $loadErr = $_ }
    Gate "Engine XAML parses & loads via XamlReader" ($null -ne $script:Win) `
        $(if ($loadErr) { $loadErr.Exception.Message } else { "" })
}

Write-Host "`n=== 4. Theme dictionaries ===" -ForegroundColor Cyan
$themeKeys = @{}
$themeKeySets = @{}
Get-ChildItem (Join-Path $themesDir '*.xaml') -ErrorAction SilentlyContinue | ForEach-Object {
    try {
        $xr = [System.Xml.XmlReader]::Create($_.FullName)
        $dict = [System.Windows.Markup.XamlReader]::Load($xr)
        $xr.Close()
        foreach ($k in $dict.Keys) { $themeKeys[$k] = $true }
        $themeKeySets[$_.BaseName] = @($dict.Keys)
        Gate "Theme loads: $($_.Name) ($($dict.Keys.Count) keys)" ($dict -is [System.Windows.ResourceDictionary])
    } catch { Gate "Theme loads: $($_.Name)" $false $_.Exception.Message }
}

# Theme parity: every theme must expose the identical key set, or switching themes crashes at runtime
$themeNames = @($themeKeySets.Keys)
if ($themeNames.Count -ge 2) {
    $refName = $themeNames[0]
    $refKeys = @($themeKeySets[$refName])
    foreach ($other in ($themeNames | Select-Object -Skip 1)) {
        $otherKeys = @($themeKeySets[$other])
        $onlyRef   = @($refKeys   | Where-Object { $otherKeys -notcontains $_ })
        $onlyOther = @($otherKeys | Where-Object { $refKeys   -notcontains $_ })
        $parityOk = ($onlyRef.Count -eq 0 -and $onlyOther.Count -eq 0)
        $detail = ""
        if ($onlyRef.Count -gt 0)   { $detail += "Only in ${refName}: $($onlyRef -join ', '). " }
        if ($onlyOther.Count -gt 0) { $detail += "Only in ${other}: $($onlyOther -join ', ')." }
        Gate "Theme parity: $refName vs $other" $parityOk $detail
    }
}

Write-Host "`n=== 5. FindName targets exist in XAML ===" -ForegroundColor Cyan
if ($null -ne $script:Win) {
    $nameSet = @{}
    [regex]::Matches($xaml, '(?<![\w:.])Name="([^"]+)"') | ForEach-Object { $nameSet[$_.Groups[1].Value] = $true }
    [regex]::Matches($xaml, 'x:Name="([^"]+)"')          | ForEach-Object { $nameSet[$_.Groups[1].Value] = $true }
    $findNames = [regex]::Matches($engineRaw, 'FindName\(\s*"([^"]+)"\s*\)') |
        ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique
    $missingNames = @($findNames | Where-Object { -not $nameSet.ContainsKey($_) })
    Gate "All $($findNames.Count) FindName(`"X`") references exist in XAML" ($missingNames.Count -eq 0) `
        ("Missing: " + ($missingNames -join ', '))
} else {
    Gate "FindName cross-check" $false "Skipped - window failed to load in check 3."
}

Write-Host "`n=== 6. Resource references resolve ===" -ForegroundColor Cyan
if ($null -ne $script:Win) {
    $keySet = @{}
    foreach ($k in $script:Win.Resources.Keys) { $keySet[$k] = $true }
    foreach ($k in $themeKeys.Keys) { $keySet[$k] = $true }

    $refs = @()
    $refs += [regex]::Matches($engineRaw, 'Resources\["([^"]+)"\]')                 | ForEach-Object { $_.Groups[1].Value }
    $refs += [regex]::Matches($engineRaw, 'FindResource\(\s*"([^"]+)"')             | ForEach-Object { $_.Groups[1].Value }
    $refs += [regex]::Matches($engineRaw, 'SetResourceReference\([^,]+,\s*"([^"]+)"') | ForEach-Object { $_.Groups[1].Value }
    $refs += [regex]::Matches($xaml, '\{(?:Dynamic|Static)Resource\s+([^}\s]+)')    | ForEach-Object { $_.Groups[1].Value }
    $refs = $refs | Sort-Object -Unique
    $missingRefs = @($refs | Where-Object { -not $keySet.ContainsKey($_) })
    Gate "All $($refs.Count) resource references resolve (window + themes)" ($missingRefs.Count -eq 0) `
        ("Missing: " + ($missingRefs -join ', '))
} else {
    Gate "Resource cross-check" $false "Skipped - window failed to load in check 3."
}

Write-Host "`n=== 7. Referenced assets exist ===" -ForegroundColor Cyan
$assetRefs = @()
if ($xaml) { $assetRefs += [regex]::Matches($xaml, 'Assets[/\\]([^\s"<>]+)') | ForEach-Object { $_.Groups[1].Value } }
if (Test-Path $manifestPath) {
    $manifestRaw = [System.IO.File]::ReadAllText($manifestPath)
    $assetRefs += [regex]::Matches($manifestRaw, 'Assets[/\\]([^\s"<>]+)') | ForEach-Object { $_.Groups[1].Value }
}
$assetRefs = $assetRefs | Sort-Object -Unique
$missingAssets = @($assetRefs | Where-Object { -not (Test-Path (Join-Path $assetsDir $_)) })
Gate "All $($assetRefs.Count) referenced assets exist in MSIX_Source\Assets" ($missingAssets.Count -eq 0) `
    ("Missing: " + ($missingAssets -join ', '))

Write-Host "`n=== 8. AppxManifest ===" -ForegroundColor Cyan
$manifestErr = $null
$manifestXml = $null
try { $manifestXml = [xml](Get-Content $manifestPath -Raw) } catch { $manifestErr = $_ }
Gate "AppxManifest.xml is well-formed XML" ($null -ne $manifestXml) $(if ($manifestErr) { $manifestErr.Exception.Message } else { "" })
if ($manifestXml) {
    $ver = $manifestXml.Package.Identity.Version
    Gate "Identity Version present ($ver)" ([bool]$ver -and $ver -match '^\d+\.\d+\.\d+\.\d+$')
}

Write-Host "`n==================================================" -ForegroundColor Cyan
if ($script:Failures -gt 0) {
    Write-Host "  VALIDATION FAILED: $($script:Failures) gate(s) failed, $($script:Passes) passed." -ForegroundColor Red
    Write-Host "  DO NOT PACK. Fix the failures above first." -ForegroundColor Red
    exit 1
} else {
    Write-Host "  VALIDATION PASSED: all $($script:Passes) gates green." -ForegroundColor Green
    exit 0
}
