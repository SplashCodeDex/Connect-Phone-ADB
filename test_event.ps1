Continue = 'Stop'
$script:myVar = "Hello World"
$timer = New-Object System.Timers.Timer(100)
$action = { Write-Host "Value: $script:myVar" }
Register-ObjectEvent -InputObject $timer -EventName Elapsed -Action $action | Out-Null
$timer.Start()
Start-Sleep -Seconds 1

