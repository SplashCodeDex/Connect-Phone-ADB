Add-Type -AssemblyName System.Windows.Forms
$icon = New-Object System.Windows.Forms.NotifyIcon
$icon.Add_MouseUp({
    param($s, $e)
    Write-Host "SENDER:" $s
    Write-Host "E:" $e
    Write-Host "THIS:" $this
    Write-Host "US:" $_
})
$e_args = New-Object System.Windows.Forms.MouseEventArgs([System.Windows.Forms.MouseButtons]::Left, 1, 0, 0, 0)
$icon.GetType().GetMethod('OnMouseUp', [System.Reflection.BindingFlags]'NonPublic,Instance').Invoke($icon, [object[]]@($e_args))
