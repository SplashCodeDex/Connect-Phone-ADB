
Add-Type -AssemblyName PresentationFramework
$xaml = @'
<Window xmlns='http://schemas.microsoft.com/winfx/2006/xaml/presentation' xmlns:x='http://schemas.microsoft.com/winfx/2006/xaml'>
    <Window.Resources>
        <Storyboard x:Key='TestSb'>
            <DoubleAnimation Storyboard.TargetProperty='Width' By='100' Duration='0:0:1' />
        </Storyboard>
    </Window.Resources>
</Window>
'@
$win = [System.Windows.Markup.XamlReader]::Parse($xaml)
$sb = $win.Resources['TestSb'].Clone()
$sb.Children[0].By = $null
$sb.Children[0].To = 675
Write-Output 'To value is:'
Write-Output $sb.Children[0].To

