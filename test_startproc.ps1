Continue = 'Stop'
try {
    Start-Process 'ConnectPhone-adb.exe' -ArgumentList 'devices' -Wait -NoNewWindow
    Write-Host 'SUCCESS'
} catch {
    Write-Host "ERROR: $($_.Exception.Message)"
}
