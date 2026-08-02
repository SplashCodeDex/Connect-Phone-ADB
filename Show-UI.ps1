Add-Type -AssemblyName PresentationFramework
[xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="DeX - Receive" Width="420" Height="160" WindowStartupLocation="Manual"
        Background="Transparent" WindowStyle="None" ResizeMode="NoResize" Topmost="True" AllowsTransparency="True">
    <Border Background="#1E1E1E" CornerRadius="12" BorderBrush="#333333" BorderThickness="1" Margin="10" RenderTransformOrigin="0.5,0.5">
        <Border.RenderTransform>
            <ScaleTransform ScaleX="0.8" ScaleY="0.8"/>
        </Border.RenderTransform>
        <Border.Triggers>
            <EventTrigger RoutedEvent="Loaded">
                <BeginStoryboard>
                    <Storyboard>
                        <DoubleAnimation Storyboard.TargetProperty="(UIElement.RenderTransform).(ScaleTransform.ScaleX)" To="1.0" Duration="0:0:0.4">
                            <DoubleAnimation.EasingFunction><BackEase Amplitude="0.6" EasingMode="EaseOut"/></DoubleAnimation.EasingFunction>
                        </DoubleAnimation>
                        <DoubleAnimation Storyboard.TargetProperty="(UIElement.RenderTransform).(ScaleTransform.ScaleY)" To="1.0" Duration="0:0:0.4">
                            <DoubleAnimation.EasingFunction><BackEase Amplitude="0.6" EasingMode="EaseOut"/></DoubleAnimation.EasingFunction>
                        </DoubleAnimation>
                        <DoubleAnimation Storyboard.TargetProperty="Opacity" From="0" To="1" Duration="0:0:0.2"/>
                    </Storyboard>
                </BeginStoryboard>
            </EventTrigger>
        </Border.Triggers>
        <Border.Effect>
            <DropShadowEffect Color="Black" BlurRadius="15" ShadowDepth="0" Opacity="0.5"/>
        </Border.Effect>
        <Border.Resources>
            <Style TargetType="Button">
                <Setter Property="RenderTransformOrigin" Value="0.5,0.5"/>
                <Setter Property="RenderTransform">
                    <Setter.Value>
                        <ScaleTransform ScaleX="1.0" ScaleY="1.0"/>
                    </Setter.Value>
                </Setter>
                <Setter Property="Template">
                    <Setter.Value>
                        <ControlTemplate TargetType="Button">
                            <Border Background="{TemplateBinding Background}" CornerRadius="6">
                                <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                            </Border>
                        </ControlTemplate>
                    </Setter.Value>
                </Setter>
                <Style.Triggers>
                    <EventTrigger RoutedEvent="MouseEnter">
                        <BeginStoryboard>
                            <Storyboard>
                                <DoubleAnimation Storyboard.TargetProperty="(UIElement.RenderTransform).(ScaleTransform.ScaleX)" To="1.08" Duration="0:0:0.2">
                                    <DoubleAnimation.EasingFunction><BackEase Amplitude="1.2" EasingMode="EaseOut"/></DoubleAnimation.EasingFunction>
                                </DoubleAnimation>
                                <DoubleAnimation Storyboard.TargetProperty="(UIElement.RenderTransform).(ScaleTransform.ScaleY)" To="1.08" Duration="0:0:0.2">
                                    <DoubleAnimation.EasingFunction><BackEase Amplitude="1.2" EasingMode="EaseOut"/></DoubleAnimation.EasingFunction>
                                </DoubleAnimation>
                            </Storyboard>
                        </BeginStoryboard>
                    </EventTrigger>
                    <EventTrigger RoutedEvent="MouseLeave">
                        <BeginStoryboard>
                            <Storyboard>
                                <DoubleAnimation Storyboard.TargetProperty="(UIElement.RenderTransform).(ScaleTransform.ScaleX)" To="1.0" Duration="0:0:0.2">
                                    <DoubleAnimation.EasingFunction><BackEase Amplitude="0.5" EasingMode="EaseOut"/></DoubleAnimation.EasingFunction>
                                </DoubleAnimation>
                                <DoubleAnimation Storyboard.TargetProperty="(UIElement.RenderTransform).(ScaleTransform.ScaleY)" To="1.0" Duration="0:0:0.2">
                                    <DoubleAnimation.EasingFunction><BackEase Amplitude="0.5" EasingMode="EaseOut"/></DoubleAnimation.EasingFunction>
                                </DoubleAnimation>
                            </Storyboard>
                        </BeginStoryboard>
                    </EventTrigger>
                </Style.Triggers>
            </Style>
        </Border.Resources>
        <Grid Margin="20,15,20,15">
            <Grid.RowDefinitions>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="*" />
                <RowDefinition Height="Auto"/>
            </Grid.RowDefinitions>
            
            <TextBlock Text="Incoming Transfer" FontSize="18" FontWeight="Bold" Foreground="#FFFFFF" Grid.Row="0" Margin="0,0,0,5"/>
            <TextBlock Text="Pixel 7 Pro (Trusted) wants to send 4 file(s)." FontSize="18" Foreground="#A0A0A0" Grid.Row="1" Margin="0,0,0,15" TextTrimming="CharacterEllipsis"/>
            
            <StackPanel Grid.Row="2" Orientation="Horizontal" HorizontalAlignment="Right">
                <Button Name="btnDecline" Content="Decline" Width="80" Height="32" Margin="0,0,12,0" FontSize="14" Background="#333333" Foreground="#FFFFFF" BorderThickness="0"/>
                <Button Name="btnAccept" Content="Accept" Width="80" Height="32" FontSize="14" Background="#00E676" Foreground="Black" BorderThickness="0" FontWeight="Bold"/>
            </StackPanel>
        </Grid>
    </Border>
</Window>
"@

$reader = (New-Object System.Xml.XmlNodeReader $xaml)
$win = [Windows.Markup.XamlReader]::Load($reader)

$win.Add_Loaded({
    $workArea = [System.Windows.SystemParameters]::WorkArea
    $win.Left = $workArea.Right - $win.Width - 13
    $win.Top = $workArea.Bottom - $win.Height - 13
    if ($win.Left -lt $workArea.Left) { $win.Left = $workArea.Left + 13 }
    if ($win.Top -lt $workArea.Top) { $win.Top = $workArea.Top + 13 }
})

$btnDecline = $win.FindName("btnDecline")
$btnAccept = $win.FindName("btnAccept")

$closeWithAnimation = {
    $sb = New-Object System.Windows.Media.Animation.Storyboard
    
    $scaleXAnim = New-Object System.Windows.Media.Animation.DoubleAnimation
    $scaleXAnim.To = 0.8
    $scaleXAnim.Duration = [TimeSpan]::FromMilliseconds(250)
    $easeIn = New-Object System.Windows.Media.Animation.BackEase
    $easeIn.Amplitude = 0.5
    $easeIn.EasingMode = [System.Windows.Media.Animation.EasingMode]::EaseIn
    $scaleXAnim.EasingFunction = $easeIn
    [System.Windows.Media.Animation.Storyboard]::SetTarget($scaleXAnim, $win.Content)
    [System.Windows.Media.Animation.Storyboard]::SetTargetProperty($scaleXAnim, [System.Windows.PropertyPath]::new("(UIElement.RenderTransform).(ScaleTransform.ScaleX)"))
    $sb.Children.Add($scaleXAnim)

    $scaleYAnim = New-Object System.Windows.Media.Animation.DoubleAnimation
    $scaleYAnim.To = 0.8
    $scaleYAnim.Duration = [TimeSpan]::FromMilliseconds(250)
    $scaleYAnim.EasingFunction = $easeIn
    [System.Windows.Media.Animation.Storyboard]::SetTarget($scaleYAnim, $win.Content)
    [System.Windows.Media.Animation.Storyboard]::SetTargetProperty($scaleYAnim, [System.Windows.PropertyPath]::new("(UIElement.RenderTransform).(ScaleTransform.ScaleY)"))
    $sb.Children.Add($scaleYAnim)

    $opacityAnim = New-Object System.Windows.Media.Animation.DoubleAnimation
    $opacityAnim.To = 0
    $opacityAnim.Duration = [TimeSpan]::FromMilliseconds(200)
    [System.Windows.Media.Animation.Storyboard]::SetTarget($opacityAnim, $win)
    [System.Windows.Media.Animation.Storyboard]::SetTargetProperty($opacityAnim, [System.Windows.PropertyPath]::new("Opacity"))
    $sb.Children.Add($opacityAnim)

    $sb.Add_Completed({ $win.Close() })
    $sb.Begin()
}

$btnDecline.Add_Click($closeWithAnimation)
$btnAccept.Add_Click($closeWithAnimation)
$win.Add_MouseLeftButtonDown({ $win.DragMove() })

$win.ShowDialog() | Out-Null
