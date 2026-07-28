Continue = 'Stop'
Add-Type -AssemblyName PresentationFramework
$xaml = @"
<Window xmlns='http://schemas.microsoft.com/winfx/2006/xaml/presentation' Title='Test' Width='300' Height='200'>
    <ListBox Name='lb'>
        <ListBox.ItemTemplate>
            <DataTemplate>
                <TextBlock Text='{Binding Name}' Foreground='Black' FontSize='20' />
            </DataTemplate>
        </ListBox.ItemTemplate>
    </ListBox>
</Window>
"@
$w = [System.Windows.Markup.XamlReader]::Parse($xaml)
$lb = $w.FindName('lb')

$item1 = New-Object System.Windows.Controls.ListBoxItem
$item1.Content = @{ Name = 'Hashtable Item' }
$lb.Items.Add($item1)

$item2 = New-Object System.Windows.Controls.ListBoxItem
$item2.Content = [PSCustomObject]@{ Name = 'PSCustomObject Item' }
$lb.Items.Add($item2)

$w.Loaded += {
    Start-Sleep -Seconds 1
    Write-Host "Window Loaded"
    $w.Close()
}
$w.ShowDialog() | Out-Null

