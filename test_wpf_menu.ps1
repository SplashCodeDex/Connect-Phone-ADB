Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        WindowStyle="None" AllowsTransparency="True" Background="Transparent"
        Topmost="True" ShowInTaskbar="False" SizeToContent="WidthAndHeight">
    <Border Background="#1C1C1E" CornerRadius="20" Padding="8" BorderBrush="#2C2C2E" BorderThickness="1">
        <StackPanel Width="220">
            <Button Background="Transparent" BorderThickness="0" Foreground="White" Padding="12,10" HorizontalContentAlignment="Left">
                <TextBlock Text="Connect ADB" FontSize="14" />
            </Button>
            <Button Background="Transparent" BorderThickness="0" Foreground="White" Padding="12,10" HorizontalContentAlignment="Left">
                <TextBlock Text="Disconnect" FontSize="14" />
            </Button>
            <Separator Background="#333333" Margin="0,4" />
            <Button Background="Transparent" BorderThickness="0" Foreground="#FF453A" Padding="12,10" HorizontalContentAlignment="Left">
                <TextBlock Text="Exit" FontSize="14" />
            </Button>
        </StackPanel>
    </Border>
</Window>
"@

$reader = (New-Object System.Xml.XmlNodeReader ([xml]$xaml))
$window = [System.Windows.Markup.XamlReader]::Load($reader)

$window.Add_Deactivated({
    $window.DialogResult = $false
})

$icon = New-Object System.Windows.Forms.NotifyIcon
$icon.Icon = [System.Drawing.SystemIcons]::Information
$icon.Visible = $true

$icon.Add_MouseClick({
    param($sender, $e)
    if ($e.Button -eq 'Right' -or $e.Button -eq 'Left') {
        # Position at cursor
        $window.Left = [System.Windows.Forms.Cursor]::Position.X - 220
        $window.Top = [System.Windows.Forms.Cursor]::Position.Y - 200
        $window.ShowDialog() | Out-Null
    }
})

Write-Host "Right click the tray icon to test WPF menu."
[System.Windows.Forms.Application]::Run()
