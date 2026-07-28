Add-Type -AssemblyName System.Windows.Forms
$icon = New-Object System.Windows.Forms.NotifyIcon
$icon.Icon = [System.Drawing.SystemIcons]::Information
$icon.Visible = $true
$icon.Add_MouseClick({
    param($s, $e)
    Out-File -FilePath "$PSScriptRoot\tray_trace.txt" -InputObject "Type of e: $($e.GetType().FullName)`nValue of Button: $($e.Button)" -Append
})
$icon.Add_MouseUp({
    param($s, $e)
    Out-File -FilePath "$PSScriptRoot\tray_trace.txt" -InputObject "MouseUp - Type of e: $($e.GetType().FullName)`nValue of Button: $($e.Button)" -Append
})
$e_sim = New-Object System.Windows.Forms.MouseEventArgs([System.Windows.Forms.MouseButtons]::Left, 1, 0, 0, 0)
$icon.GetType().GetMethod('OnMouseClick', [System.Reflection.BindingFlags]'NonPublic,Instance').Invoke($icon, @($e_sim))
$icon.GetType().GetMethod('OnMouseUp', [System.Reflection.BindingFlags]'NonPublic,Instance').Invoke($icon, @($e_sim))
Start-Sleep -Seconds 1
