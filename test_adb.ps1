Continue = 'Stop'
$proc = New-Object System.Diagnostics.Process
$proc.StartInfo.FileName = 'W:\CodeDeX\Connect-Phone-ADB\MSIX_Source\bin\adb.exe'
$proc.StartInfo.Arguments = '-s 10.204.190.114:5555 shell ls -1aF "/sdcard/"'
$proc.StartInfo.UseShellExecute = $false
$proc.StartInfo.RedirectStandardOutput = $true
$proc.StartInfo.RedirectStandardError = $true
$proc.StartInfo.CreateNoWindow = $true
$proc.Start() | Out-Null
$out = $proc.StandardOutput.ReadToEnd()
$err = $proc.StandardError.ReadToEnd()
$proc.WaitForExit()
Write-Output "OUT: $out"
Write-Output "ERR: $err"

