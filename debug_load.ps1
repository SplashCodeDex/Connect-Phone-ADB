Continue = 'Stop'
Add-Type -AssemblyName PresentationFramework
$content = Get-Content MSIX_Source\bin\Connect-Engine.ps1 -Raw
$content = $content -replace 'ShowDialog\(\)', ''
$content = $content -replace '\ = ".*?"', '$mutexName = "test_mutex_debug"'
Invoke-Expression $content
$script:currentTarget = '10.204.190.114:5555'

$log = "W:\CodeDeX\Connect-Phone-ADB\debug_log.txt"
Out-File -FilePath $log -InputObject "Starting debug..."

function Load-Directory-Debug($dirPath) {
    Out-File -FilePath $log -InputObject "Load-Directory called with $dirPath" -Append
    $proc = New-Object System.Diagnostics.Process
    $proc.StartInfo.FileName = $global:AdbExePath
    $proc.StartInfo.Arguments = "-s $($script:currentTarget) shell ls -1aF `"$dirPath`""
    $proc.StartInfo.UseShellExecute = $false
    $proc.StartInfo.RedirectStandardOutput = $true
    $proc.StartInfo.CreateNoWindow = $true
    
    $action = {
        $e = $Event.SourceEventArgs
        if ($e.Data) {
            Out-File -FilePath $log -InputObject "Received line: $($e.Data)" -Append
            $line = $e.Data.Trim()
            if ($line -eq "./" -or $line -eq "../") { return }
            
            $isDir = $line.EndsWith("/")
            $name = $line.TrimEnd('/', '*', '@', '=')
            
            $script:wpfWindow.Dispatcher.Invoke([Action]{
                $item = New-Object System.Windows.Controls.ListBoxItem
                $item.Content = @{ Name = $name; FullPath = "full"; IsDir = $isDir }
                $script:lbFiles.Items.Add($item)
                Out-File -FilePath $log -InputObject "Added item $name to lbFiles. Count: $($script:lbFiles.Items.Count)" -Append
            })
        }
    }
    
    $script:adbOutputSub = Register-ObjectEvent -InputObject $proc -EventName OutputDataReceived -Action $action
    $proc.Start() | Out-Null
    $proc.BeginOutputReadLine()
}

Load-Directory-Debug '/sdcard/'
Start-Sleep -Seconds 3
Out-File -FilePath $log -InputObject "Final lbFiles Count: $($script:lbFiles.Items.Count)" -Append
$script:wpfWindow.Close()

