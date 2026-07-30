Add-Type -AssemblyName PresentationFramework
$w = New-Object System.Windows.Window
try {
    $frame = New-Object System.Windows.Threading.DispatcherFrame
    $w.Dispatcher.BeginInvoke([System.Windows.Threading.DispatcherPriority]::SystemIdle, [Action]{ $frame.Continue = $false }) | Out-Null
    [System.Windows.Threading.Dispatcher]::PushFrame($frame)
    Write-Host "SUCCESS"
} catch {
    Write-Host "ERROR: $_"
}
