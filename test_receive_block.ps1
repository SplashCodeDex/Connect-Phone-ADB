$job = Start-Job { Write-Output "A"; Start-Sleep -Seconds 5; Write-Output "B" }
Start-Sleep -Seconds 1
Write-Host "Receiving A..."
Receive-Job -Job $job | Out-Null
Write-Host "Received A. Starting stopwatch for second receive..."
$sw = [System.Diagnostics.Stopwatch]::StartNew()
$out2 = Receive-Job -Job $job
Write-Host "Received B in $($sw.ElapsedMilliseconds)ms"
