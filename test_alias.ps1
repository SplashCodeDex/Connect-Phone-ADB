Continue = 'Stop'
try {
    $proc = New-Object System.Diagnostics.Process
    $proc.StartInfo.FileName = 'ConnectPhone-adb.exe'
    $proc.StartInfo.Arguments = 'devices'
    $proc.StartInfo.UseShellExecute = $false
    $proc.StartInfo.RedirectStandardOutput = $true
    $proc.StartInfo.CreateNoWindow = $true
    $proc.Start() | Out-Null
    Write-Host 'STARTED'
} catch {
    Write-Host "ERROR: $($_.Exception.Message)"
}
