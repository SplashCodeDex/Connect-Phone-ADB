$ErrorActionPreference = "Stop"; Add-Type -AssemblyName PresentationFramework; $xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml">
    <Window.Resources>
        <DataTemplate x:Key="FolderGridTemplate">
            <Border x:Name="folderBorder" Background="Transparent" Width="100" Height="100">
                <Border.Triggers>
                    <EventTrigger RoutedEvent="MouseEnter">
                        <BeginStoryboard>
                            <Storyboard>
                                <ColorAnimation Storyboard.TargetName="folderBorder" Storyboard.TargetProperty="(Border.Background).(SolidColorBrush.Color)" To="#1AFFFFFF" Duration="0:0:0.2" />
                            </Storyboard>
                        </BeginStoryboard>
                    </EventTrigger>
                </Border.Triggers>
            </Border>
        </DataTemplate>
    </Window.Resources>
    <ListBox Name="lb">
    </ListBox>
</Window>
"@
try {
    $w = [System.Windows.Markup.XamlReader]::Parse($xaml)
    $lb = $w.FindName("lb")
    $item = New-Object System.Windows.Controls.ListBoxItem
    $item.ContentTemplate = $w.Resources["FolderGridTemplate"]
    $lb.Items.Add($item)
    $w.Show()
    Start-Sleep -Seconds 1
    $w.Close()
    Write-Host "SUCCESS"
} catch {
    Write-Host "ERROR: $($_.Exception.Message)"
    if ($_.Exception.InnerException) { Write-Host "INNER: $($_.Exception.InnerException.Message)" }
}

