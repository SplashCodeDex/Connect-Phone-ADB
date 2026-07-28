param(
    [string]$SourceFile = "$PSScriptRoot\MSIX_Source\bin\Connect-Engine.ps1",
    [string]$ModulesDir = "$PSScriptRoot\MSIX_Source\bin\Modules"
)

$ast = [System.Management.Automation.Language.Parser]::ParseFile($SourceFile, [ref]$null, [ref]$null)

$functions = $ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)

$AdbManager = @('adb', 'Invoke-AdbConnect')
$TaskScheduler = @('Get-AutoConnectStatus', 'Set-AutoConnectStatus')
$UIComponents = @('Create-StatusIcon', 'Show-Toast', 'Set-AppTheme', 'Get-SystemTheme', 'Show-DownloadDockToast', 'Invoke-MenuAction', 'Update-WpfUI')
$EngineUtils = @('Write-Trace', 'Load-Directory')

$AdbContent = ""
$TaskContent = ""
$UIContent = ""
$UtilsContent = ""

# Track the lines we want to remove from the main script
$linesToRemove = @()

foreach ($func in $functions) {
    $name = $func.Name
    $text = $func.Extent.Text
    
    # AST lines are 1-based
    $startLine = $func.Extent.StartLineNumber
    $endLine = $func.Extent.EndLineNumber
    
    for ($i = $startLine; $i -le $endLine; $i++) {
        $linesToRemove += $i
    }

    if ($name -in $AdbManager) { $AdbContent += "`r`n$text`r`nExport-ModuleMember -Function $name`r`n" }
    elseif ($name -in $TaskScheduler) { $TaskContent += "`r`n$text`r`nExport-ModuleMember -Function $name`r`n" }
    elseif ($name -in $UIComponents) { $UIContent += "`r`n$text`r`nExport-ModuleMember -Function $name`r`n" }
    elseif ($name -in $EngineUtils) { $UtilsContent += "`r`n$text`r`nExport-ModuleMember -Function $name`r`n" }
    else {
        Write-Host "Uncategorized function: $name"
    }
}

# Write modules
Set-Content -Path (Join-Path $ModulesDir "AdbManager.psm1") -Value $AdbContent -Encoding UTF8
Set-Content -Path (Join-Path $ModulesDir "TaskScheduler.psm1") -Value $TaskContent -Encoding UTF8
Set-Content -Path (Join-Path $ModulesDir "UIComponents.psm1") -Value $UIContent -Encoding UTF8
Set-Content -Path (Join-Path $ModulesDir "EngineUtils.ps1") -Value $UtilsContent -Encoding UTF8

# Rewrite main script without functions
$originalLines = Get-Content $SourceFile
$newLines = @()

for ($i = 0; $i -lt $originalLines.Count; $i++) {
    $lineNumber = $i + 1
    
    if ($lineNumber -notin $linesToRemove) {
        $newLines += $originalLines[$i]
    }
}

# Find where to insert imports
$insertIndex = 0
for ($i = 0; $i -lt $newLines.Count; $i++) {
    if ($newLines[$i] -match '\$mutexName') {
        $insertIndex = $i
        break
    }
}

$imports = @(
    ". `"`$PSScriptRoot\Modules\EngineUtils.ps1`"",
    "Import-Module `"`$PSScriptRoot\Modules\AdbManager.psm1`" -Force",
    "Import-Module `"`$PSScriptRoot\Modules\TaskScheduler.psm1`" -Force",
    "Import-Module `"`$PSScriptRoot\Modules\UIComponents.psm1`" -Force"
)

$finalLines = $newLines[0..($insertIndex-1)] + $imports + $newLines[$insertIndex..($newLines.Count-1)]

Set-Content -Path $SourceFile -Value $finalLines -Encoding UTF8

Write-Host "Split complete!"
