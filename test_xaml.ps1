Continue = 'Stop'
Add-Type -AssemblyName PresentationFramework
$xaml = @"
<Window xmlns='http://schemas.microsoft.com/winfx/2006/xaml/presentation' Title='Test'>
    <TextBlock Text='{Binding [Name]}' />
</Window>
"@
try {
    $w = [System.Windows.Markup.XamlReader]::Parse($xaml)
    Write-Output "SUCCESS"
} catch {
    Write-Output "ERROR: $($_.Exception.Message)"
}
