$ErrorActionPreference = 'Stop'
$global:AdbExePath = 'W:\CodeDeX\Connect-Phone-ADB\MSIX_Source\bin\adb.exe'
$dirPath = '/sdcard/'
$proc = New-Object System.Diagnostics.Process
$proc.StartInfo.FileName = 'cmd.exe'
$proc.StartInfo.Arguments = "/c `"`"$global:AdbExePath`" -s 10.204.190.114:5555 shell ls -1aF `"$dirPath`"`""
$proc.StartInfo.UseShellExecute = $false
$proc.StartInfo.RedirectStandardOutput = $true
$proc.StartInfo.CreateNoWindow = $true
$action = {
    $e = $Event.SourceEventArgs
    if ($e.Data) { Write-Output "Data: $($e.Data)" }
}
Register-ObjectEvent -InputObject $proc -EventName OutputDataReceived -Action $action | Out-Null
$proc.Start() | Out-Null
$proc.BeginOutputReadLine()
Start-Sleep -Seconds 2

