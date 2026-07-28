Continue = 'Stop'
Add-Type -AssemblyName PresentationFramework
$xaml = @"
<Window xmlns='http://schemas.microsoft.com/winfx/2006/xaml/presentation' Title='Test' Width='300' Height='200'>
    <Window.Resources>
        <DataTemplate x:Key='TestTemplate'>
            <TextBlock Text='{Binding}' />
        </DataTemplate>
    </Window.Resources>
</Window>
"@
$w = [System.Windows.Markup.XamlReader]::Parse($xaml)
$w.Loaded += {
    $runspace = [runspacefactory]::CreateRunspace()
    $runspace.Open()
    $ps = [powershell]::Create().AddScript({
        param($win)
        try {
            $t = $win.Resources['TestTemplate']
            Write-Host "Success: $t"
        } catch {
            Write-Host "Error: $($_.Exception.Message)"
        }
    }).AddArgument($w)
    $ps.Runspace = $runspace
    $ps.BeginInvoke() | Out-Null
    
    Start-Sleep -Seconds 1
    $w.Close()
}
$w.ShowDialog() | Out-Null

