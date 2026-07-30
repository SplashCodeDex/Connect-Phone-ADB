$action = [System.Threading.WaitCallback]{
    Write-Host "In thread pool"
}
[System.Threading.ThreadPool]::QueueUserWorkItem($action) | Out-Null
Start-Sleep -Seconds 1
