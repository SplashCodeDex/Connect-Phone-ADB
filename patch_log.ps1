function Add-Log { param($msg) Write-Output "$([DateTime]::Now.ToString('HH:mm:ss.fff')) - $msg" | Out-File "w:\CodeDeX\Connect-Phone-ADB\perf.log" -Append }
$content = Get-Content "w:\CodeDeX\Connect-Phone-ADB\MSIX_Source\bin\TrayUIBindings.ps1" -Raw
$content = $content -replace 'Write-Trace "MouseUp fired! Button: \$\(\$e\.Button\)"', 'Add-Log "MouseUp Start"; Write-Trace "MouseUp fired! Button: $($e.Button)"'
$content = $content -replace '\$script:wpfWindow\.Show\(\)', 'Add-Log "Window Show Called"; $script:wpfWindow.Show()'
$content = $content -replace 'Write-Trace "Deactivated fired!', 'Add-Log "Deactivated Fired"; Write-Trace "Deactivated fired!'
$content = $content -replace 'Write-Trace "Deactivated: Hiding window"', 'Add-Log "Deactivated: Hiding window"; Write-Trace "Deactivated: Hiding window"'
$content = $content -replace '\$script:wpfWindow\.Hide\(\)\r?\n\s+Reset-SpatialPanels', 'Add-Log "MouseUp: Hiding window (debounce)"; $script:wpfWindow.Hide(); Reset-SpatialPanels'
Set-Content "w:\CodeDeX\Connect-Phone-ADB\MSIX_Source\bin\TrayUIBindings.ps1" $content
