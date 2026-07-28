param(
    [string]$SourceFile = "$PSScriptRoot\MSIX_Source\bin\Connect-Engine.ps1",
    [string]$BindingsFile = "$PSScriptRoot\MSIX_Source\bin\TrayUIBindings.ps1"
)

$lines = Get-Content $SourceFile
$startIdx = -1
$endIdx = -1

for ($i = 0; $i -lt $lines.Count; $i++) {
    # Find the start of the bindings (usually right after the XamlReader::Load logic)
    if ($lines[$i] -match '\$script:wpfWindow\.FindName\(' -and $startIdx -eq -1) {
        # The first event binding
        $startIdx = $i
    }
    
    # Find the end of the bindings (right before passive sync initial state on startup)
    if ($lines[$i] -match '# Passive sync initial state on startup') {
        $endIdx = $i - 1
        break
    }
}

if ($startIdx -gt 0 -and $endIdx -gt 0) {
    # Extract Bindings
    $bindingsContent = $lines[$startIdx..$endIdx]
    [System.IO.File]::WriteAllLines($BindingsFile, $bindingsContent, [System.Text.Encoding]::UTF8)

    Write-Host "Bindings extracted to $BindingsFile"

    # Rewrite main script
    $newLines = @()
    $newLines += $lines[0..($startIdx - 1)]
    $newLines += "    # Load UI Bindings in current scope"
    $newLines += "    . `"`$PSScriptRoot\TrayUIBindings.ps1`""
    $newLines += $lines[($endIdx + 1)..($lines.Count - 1)]

    [System.IO.File]::WriteAllLines($SourceFile, $newLines, [System.Text.Encoding]::UTF8)
    Write-Host "Main script rewritten."
} else {
    Write-Host "Bindings block not found."
}
