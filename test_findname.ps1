Add-Type -AssemblyName PresentationFramework
$xaml = '<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"><Button Name="btnQAAuto"><TextBlock Name="txtQAAuto" Text="test" /></Button></Window>'
$reader = New-Object System.Xml.XmlNodeReader ([xml]$xaml)
$win = [System.Windows.Markup.XamlReader]::Load($reader)
$tb = $win.FindName('txtQAAuto')
if ($tb -ne $null) {
    Write-Host "Type: $($tb.GetType().FullName)"
    $tb.Foreground = [System.Windows.Media.Brushes]::Red
    Write-Host "Foreground set successfully!"
} else {
    Write-Host "txtQAAuto is null!"
}
