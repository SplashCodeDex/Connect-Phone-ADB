Continue = 'Stop'
Add-Type -AssemblyName PresentationFramework
$content = Get-Content MSIX_Source\bin\Connect-Engine.ps1 -Raw
$content = $content -replace 'ShowDialog\(\)', ''
$content = $content -replace '\ = ".*?"', '$mutexName = "test_mutex_debug"'
Invoke-Expression $content

$script:currentTarget = '10.204.190.114:5555'
Load-Directory '/sdcard/'
Start-Sleep -Seconds 3
Write-Output "lbFiles count: $($script:lbFiles.Items.Count)"
$script:wpfWindow.Close()

