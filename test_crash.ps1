$proc = New-Object System.Diagnostics.Process
$proc.StartInfo.FileName = "cmd.exe"
$proc.StartInfo.Arguments = "/c echo hello"
$proc.StartInfo.UseShellExecute = $false
$proc.StartInfo.RedirectStandardOutput = $true
$proc.StartInfo.CreateNoWindow = $true
$proc.EnableRaisingEvents = $true
$proc.Add_Exited({
    Write-Host "Exited fired"
    $out = $proc.StandardOutput.ReadToEnd()
    Write-Host "Output: $out"
    $proc.Dispose()
})
$proc.Start() | Out-Null
Start-Sleep -Seconds 2
