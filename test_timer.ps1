Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName System.Windows.Forms

$uiTimer = New-Object System.Windows.Threading.DispatcherTimer
$uiTimer.Interval = [TimeSpan]::FromMilliseconds(500)
$uiTimer.Add_Tick({
    Write-Host "TICK!"
    [System.Windows.Forms.Application]::Exit()
})
$uiTimer.Start()

Write-Host "Starting Application.Run()..."
[System.Windows.Forms.Application]::Run()
Write-Host "Done."
