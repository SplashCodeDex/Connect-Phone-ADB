param(
    [string]$SourceFile = "$PSScriptRoot\MSIX_Source\bin\Connect-Engine.ps1",
    [string]$ThemesDir = "$PSScriptRoot\MSIX_Source\Themes"
)

$lines = Get-Content $SourceFile
$xamlStart = 0
$xamlEnd = 0

for ($i = 0; $i -lt $lines.Count; $i++) {
    if ($lines[$i] -match '\$xaml = @"') {
        $xamlStart = $i + 1
    }
    elseif ($lines[$i] -match '^"@' -and $xamlStart -gt 0 -and $xamlEnd -eq 0) {
        $xamlEnd = $i - 1
        break
    }
}

if ($xamlStart -gt 0 -and $xamlEnd -gt 0) {
    # Extract XAML
    $xamlContent = $lines[$xamlStart..$xamlEnd]
    $xamlFile = Join-Path $ThemesDir "MainWindow.xaml"
    [System.IO.File]::WriteAllLines($xamlFile, $xamlContent, [System.Text.Encoding]::UTF8)

    Write-Host "XAML extracted to $xamlFile"

    # Rewrite main script
    $newLines = @()
    $newLines += $lines[0..($xamlStart - 2)]
    
    # Insert XAML load code
    $newLines += "    `$xamlFile = Join-Path `$PSScriptRoot `"..\Themes\MainWindow.xaml`""
    $newLines += "    `$xaml = [System.IO.File]::ReadAllText(`$xamlFile)"
    
    $newLines += $lines[($xamlEnd + 2)..($lines.Count - 1)]

    [System.IO.File]::WriteAllLines($SourceFile, $newLines, [System.Text.Encoding]::UTF8)
    Write-Host "Main script rewritten."
} else {
    Write-Host "XAML block not found."
}
