Continue = 'Stop'
Add-Type -AssemblyName PresentationFramework
$w = [System.Windows.Markup.XamlReader]::Parse("<Window xmlns='http://schemas.microsoft.com/winfx/2006/xaml/presentation' Title='Test' Width='200' Height='100'><Button Name='b' Content='Click Me'/></Window>")
$b = $w.FindName('b')
$b.Add_Click({
    Write-Host 'Button clicked! Starting ping...'
    $proc = New-Object System.Diagnostics.Process
    $proc.StartInfo.FileName = 'ping.exe'
    $proc.StartInfo.Arguments = '127.0.0.1 -n 2'
    $proc.StartInfo.UseShellExecute = $false
    $proc.StartInfo.RedirectStandardOutput = $true
    $proc.StartInfo.CreateNoWindow = $true
    $action = { Write-Host "Output: $($Event.SourceEventArgs.Data)" }
    Register-ObjectEvent -InputObject $proc -EventName OutputDataReceived -Action $action | Out-Null
    $proc.Start() | Out-Null
    $proc.BeginOutputReadLine()
    Start-Sleep -Seconds 1
    $w.Close()
})
$w.Loaded += { $b.RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Button]::ClickEvent))) }
$w.ShowDialog() | Out-Null

