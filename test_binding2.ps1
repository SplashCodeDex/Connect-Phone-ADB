Continue = 'Stop'
Add-Type -AssemblyName PresentationFramework
$xaml = @"
<Window xmlns='http://schemas.microsoft.com/winfx/2006/xaml/presentation' Title='Test' Width='300' Height='200'>
    <ListBox Name='lb'>
        <ListBox.ItemTemplate>
            <DataTemplate>
                <TextBlock Name='tb' Text='{Binding Name}' Foreground='Black' FontSize='20' />
            </DataTemplate>
        </ListBox.ItemTemplate>
    </ListBox>
</Window>
"@
$w = [System.Windows.Markup.XamlReader]::Parse($xaml)
$lb = $w.FindName('lb')

$item1 = New-Object System.Windows.Controls.ListBoxItem
$item1.Content = [PSCustomObject]@{ Name = 'PSCustomObject Item' }
$lb.Items.Add($item1)

$w.Loaded += {
    $lb.UpdateLayout()
    $cp = [System.Windows.Media.VisualTreeHelper]::GetChild($lb, 0) # Border
    # ... actually this is too complex to parse the visual tree in PowerShell
    $w.Close()
}
$w.ShowDialog() | Out-Null
Write-Host "Done"

