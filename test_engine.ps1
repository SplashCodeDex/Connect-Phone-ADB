Continue = 'Stop'
Add-Type -AssemblyName PresentationFramework
$content = Get-Content MSIX_Source\bin\Connect-Engine.ps1 -Raw
$content = $content -replace '\[System.Windows.Forms.Application\]::Run\(\)', 'Write-Host "REACHED END OF SCRIPT"'
$content = $content -replace '\ = ".*?"', '$mutexName = "test_mutex_engine"'
Invoke-Expression $content

