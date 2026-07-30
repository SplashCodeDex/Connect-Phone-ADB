$sw = [System.Diagnostics.Stopwatch]::StartNew()
$proc = New-Object System.Diagnostics.Process
$proc.StartInfo.FileName = "adb.exe"
$proc.StartInfo.Arguments = "devices -l"
$proc.StartInfo.UseShellExecute = $false
$proc.StartInfo.RedirectStandardOutput = $true
$proc.StartInfo.CreateNoWindow = $true
$proc.Start() | Out-Null
Write-Host "Process.Start() took $($sw.ElapsedMilliseconds) ms"
$sw.Restart()
