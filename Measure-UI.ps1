
Add-Type -AssemblyName PresentationFramework
$xaml = Get-Content 'w:\CodeDeX\Connect-Phone-ADB\MSIX_Source\Themes\MainWindow.xaml' -Raw
$win = [System.Windows.Markup.XamlReader]::Parse($xaml)
$mb = $win.FindName('mainBorder')
$mb.Measure([System.Windows.Size]::new(9999, 9999))
Write-Output 'Desired Width:'
Write-Output $mb.DesiredSize.Width
Write-Output 'Desired Height:'
Write-Output $mb.DesiredSize.Height

