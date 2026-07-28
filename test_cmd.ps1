$ErrorActionPreference = 'Stop'
$adb = 'C:\Program Files\Git\bin\git.exe'
$dirPath = 'W:\CodeDeX\Connect-Phone-ADB'
$proc = New-Object System.Diagnostics.Process
$proc.StartInfo.FileName = 'cmd.exe'
$proc.StartInfo.Arguments = "/c `"`"$adb`" log -n 1 `"$dirPath`"`""
$proc.StartInfo.UseShellExecute = $false
$proc.StartInfo.RedirectStandardOutput = $true
$proc.StartInfo.CreateNoWindow = $true
$proc.Start() | Out-Null
Write-Output $proc.StandardOutput.ReadToEnd()

