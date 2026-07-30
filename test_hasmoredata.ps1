$job = Start-Job { Write-Output "A"; Start-Sleep -Seconds 2; Write-Output "B" }
Start-Sleep -Seconds 1
Write-Host "HasMoreData before: $($job.HasMoreData)"
$out1 = Receive-Job -Job $job
Write-Host "Received: $out1"
Write-Host "HasMoreData after: $($job.HasMoreData)"
Start-Sleep -Seconds 1
Write-Host "HasMoreData later: $($job.HasMoreData)"
