Add-Type -AssemblyName System.Windows.Forms

$notifyIcon = New-Object System.Windows.Forms.NotifyIcon
$eArgs = New-Object System.Windows.Forms.MouseEventArgs([System.Windows.Forms.MouseButtons]::Left, 1, 0, 0, 0)

try {
    $notifyIcon.GetType().GetMethod('OnMouseUp', [System.Reflection.BindingFlags]'NonPublic,Instance').Invoke($notifyIcon, [object[]]@($eArgs))
    Write-Host "Success with object[]"
} catch {
    Write-Host "Failed with object[]: $_"
}

try {
    $invokeArgs = [Array]::CreateInstance([object], 1)
    $invokeArgs.SetValue($eArgs, 0)
    $notifyIcon.GetType().GetMethod('OnMouseUp', [System.Reflection.BindingFlags]'NonPublic,Instance').Invoke($notifyIcon, $invokeArgs)
    Write-Host "Success with CreateInstance"
} catch {
    Write-Host "Failed with CreateInstance: $_"
}

