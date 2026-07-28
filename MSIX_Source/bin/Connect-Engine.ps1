<#
.SYNOPSIS
    Connect Phone ADB - Core Engine & Tray Application
.DESCRIPTION
    Manages wireless ADB hotspot connections, provides a clean System Tray UI with Auto-Connect ON/OFF toggle,
    and handles Windows Task Scheduler integration.
#>

param(
    [switch]$Background,
    [switch]$ConnectOnly,
    [switch]$SelfTest
)

Import-Module "$PSScriptRoot\Modules\EngineUtils.psm1" -Force
Import-Module "$PSScriptRoot\Modules\AdbManager.psm1" -Force
Import-Module "$PSScriptRoot\Modules\TaskScheduler.psm1" -Force
Import-Module "$PSScriptRoot\Modules\UIComponents.psm1" -Force
$mutexName = "Global\CodeDeX_ConnectPhoneADB_Engine"
$script:engineMutex = New-Object System.Threading.Mutex($false, $mutexName)
if (-not $script:engineMutex.WaitOne(0, $false)) {
    # Another instance is already running
    exit
}

if ($PSScriptRoot -match "WindowsApps") {
    $global:AdbExePath = "ConnectPhone-adb.exe"
} else {
    $global:AdbExePath = "$PSScriptRoot\adb.exe"
}

# Force STA Mode Threading for Windows Forms & Tray Icons
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing



Add-Type -AssemblyName PresentationFramework

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$env:ADB_MDNS_OPENSCREEN = 1
$TaskName = "AutoConnectADB_Hotspot"
$ScriptPath = $PSCommandPath

# Function: Connect ADB to Gateway

# If called for ConnectOnly (e.g. from background Task Scheduler trigger)
if ($ConnectOnly) {
    $res = Invoke-AdbConnect
    exit
}

# Prevent multiple tray instances
$createdNew = $false
$script:trayMutex = New-Object System.Threading.Mutex($true, "ConnectPhoneADBTrayMutex", [ref]$createdNew)
if (-not $createdNew) {
    # If already running, trigger immediate connection check
    $res = Invoke-AdbConnect
    exit
}

# Check Task Scheduler Auto-Connect status


# Create System Tray Icon
$script:notifyIcon = New-Object System.Windows.Forms.NotifyIcon
$script:notifyIcon.Text = "Connect ADB: Initializing..."


$iconGreen = Create-StatusIcon ([System.Drawing.Color]::FromArgb(0, 230, 118))
$iconYellow = Create-StatusIcon ([System.Drawing.Color]::FromArgb(255, 214, 0))
$iconRed = Create-StatusIcon ([System.Drawing.Color]::FromArgb(255, 23, 68))

$script:notifyIcon.Icon = $iconYellow
$script:notifyIcon.Visible = $true


# Spatial UI WPF Overlay
$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        x:Name="winSpatial"
        WindowStyle="None" Background="Transparent" AllowsTransparency="True"
        Topmost="True" ShowInTaskbar="False"
        Width="1420" Height="760"
        ResizeMode="NoResize">
    <Window.Resources>
            <!-- Minimal Spatial ScrollBar Style -->
            <Style TargetType="ScrollBar">
                <Setter Property="Background" Value="Transparent"/>
                <Setter Property="Width" Value="2"/>
                <Setter Property="Template">
                    <Setter.Value>
                        <ControlTemplate TargetType="ScrollBar">
                            <Grid Background="Transparent">
                                <Track x:Name="PART_Track" IsDirectionReversed="True">
                                    <Track.DecreaseRepeatButton>
                                        <RepeatButton Command="ScrollBar.PageUpCommand" Opacity="0" Focusable="False"/>
                                    </Track.DecreaseRepeatButton>
                                    <Track.IncreaseRepeatButton>
                                        <RepeatButton Command="ScrollBar.PageDownCommand" Opacity="0" Focusable="False"/>
                                    </Track.IncreaseRepeatButton>
                                    <Track.Thumb>
                                        <Thumb>
                                            <Thumb.Template>
                                                <ControlTemplate TargetType="Thumb">
                                                    <Border Background="{DynamicResource TertiaryBackgroundBrush}" CornerRadius="1" Margin="0,40" />
                                                </ControlTemplate>
                                            </Thumb.Template>
                                        </Thumb>
                                    </Track.Thumb>
                                </Track>
                            </Grid>
                        </ControlTemplate>
                    </Setter.Value>
                </Setter>
                <Style.Triggers>
                    <Trigger Property="Orientation" Value="Horizontal">
                        <Setter Property="Width" Value="Auto"/>
                        <Setter Property="Height" Value="2"/>
                        <Setter Property="Template">
                            <Setter.Value>
                                <ControlTemplate TargetType="ScrollBar">
                                    <Grid Background="Transparent">
                                        <Track x:Name="PART_Track" IsDirectionReversed="False">
                                            <Track.DecreaseRepeatButton>
                                                <RepeatButton Command="ScrollBar.PageLeftCommand" Opacity="0" Focusable="False"/>
                                            </Track.DecreaseRepeatButton>
                                            <Track.IncreaseRepeatButton>
                                                <RepeatButton Command="ScrollBar.PageDownCommand" Opacity="0" Focusable="False"/>
                                            </Track.IncreaseRepeatButton>
                                            <Track.Thumb>
                                                <Thumb>
                                                    <Thumb.Template>
                                                        <ControlTemplate TargetType="Thumb">
                                                            <Border Background="{DynamicResource TertiaryBackgroundBrush}" CornerRadius="1" Margin="40,0" />
                                                        </ControlTemplate>
                                                    </Thumb.Template>
                                                </Thumb>
                                            </Track.Thumb>
                                        </Track>
                                    </Grid>
                                </ControlTemplate>
                            </Setter.Value>
                        </Setter>
                    </Trigger>
                </Style.Triggers>
            </Style>
        
        <BackEase x:Key="HoverEase" Amplitude="1.22" EasingMode="EaseOut" />
        <BackEase x:Key="PopInEase" Amplitude="3.53" EasingMode="EaseOut" />
        <ElasticEase x:Key="BouncyEase" Oscillations="1" Springiness="7" EasingMode="EaseOut" />
        <Storyboard x:Key="ExpandMenu">
            <!-- Window Size Expansion with ElasticEase (reduced 35% from original) -->
            <DoubleAnimation Storyboard.TargetName="mainBorder" Storyboard.TargetProperty="Width" By="754" Duration="0:0:0.8" EasingFunction="{StaticResource BouncyEase}" />
            <DoubleAnimation Storyboard.TargetName="mainBorder" Storyboard.TargetProperty="Height" By="195" Duration="0:0:0.8" EasingFunction="{StaticResource BouncyEase}" />
            
            <!-- Parallax on File Explorer: Slide from Right to Left while fading -->
            <DoubleAnimation Storyboard.TargetName="fileTrans" Storyboard.TargetProperty="X" From="150" To="0" Duration="0:0:0.8" EasingFunction="{StaticResource BouncyEase}" />
            <DoubleAnimation Storyboard.TargetName="FileExplorer" Storyboard.TargetProperty="Opacity" To="1" Duration="0:0:0.6" BeginTime="0:0:0.1"/>
            <ObjectAnimationUsingKeyFrames Storyboard.TargetName="FileExplorer" Storyboard.TargetProperty="Visibility">
                <DiscreteObjectKeyFrame KeyTime="0:0:0" Value="{x:Static Visibility.Visible}" />
            </ObjectAnimationUsingKeyFrames>
            
            <!-- Show Close Button and Top Profile when expanded, hide Bottom Profile -->
            <ObjectAnimationUsingKeyFrames Storyboard.TargetName="btnCloseMenu" Storyboard.TargetProperty="Visibility">
                <DiscreteObjectKeyFrame KeyTime="0:0:0" Value="{x:Static Visibility.Visible}" />
            </ObjectAnimationUsingKeyFrames>
            <DoubleAnimation Storyboard.TargetName="btnCloseMenu" Storyboard.TargetProperty="Opacity" From="0" To="1" Duration="0:0:0.4" BeginTime="0:0:0.3" />
            
            <ObjectAnimationUsingKeyFrames Storyboard.TargetName="btnProfileBottom" Storyboard.TargetProperty="Visibility">
                <DiscreteObjectKeyFrame KeyTime="0:0:0" Value="{x:Static Visibility.Collapsed}" />
            </ObjectAnimationUsingKeyFrames>
            <ObjectAnimationUsingKeyFrames Storyboard.TargetName="btnProfileTop" Storyboard.TargetProperty="Visibility">
                <DiscreteObjectKeyFrame KeyTime="0:0:0" Value="{x:Static Visibility.Visible}" />
            </ObjectAnimationUsingKeyFrames>
            <DoubleAnimation Storyboard.TargetName="btnProfileTop" Storyboard.TargetProperty="Opacity" From="0" To="1" Duration="0:0:0.4" BeginTime="0:0:0.3" />
            
            <!-- Show Nearby Expand Users when expanded -->
            <ObjectAnimationUsingKeyFrames Storyboard.TargetName="NearbyExpandPanel" Storyboard.TargetProperty="Visibility">
                <DiscreteObjectKeyFrame KeyTime="0:0:0.2" Value="{x:Static Visibility.Visible}" />
            </ObjectAnimationUsingKeyFrames>
            <DoubleAnimation Storyboard.TargetName="NearbyExpandPanel" Storyboard.TargetProperty="Opacity" From="0" To="1" Duration="0:0:0.5" BeginTime="0:0:0.3" />
            
            <!-- Subtle Parallax on Main Menu: Slide Right slightly -->
            <DoubleAnimation Storyboard.TargetName="menuTrans" Storyboard.TargetProperty="X" From="-30" To="0" Duration="0:0:0.8" EasingFunction="{StaticResource BouncyEase}" />
        </Storyboard>
        <Storyboard x:Key="ContractMenu">
            <DoubleAnimation Storyboard.TargetName="mainBorder" Storyboard.TargetProperty="Width" By="-754" Duration="0:0:0.8" EasingFunction="{StaticResource BouncyEase}" />
            <DoubleAnimation Storyboard.TargetName="mainBorder" Storyboard.TargetProperty="Height" By="-195" Duration="0:0:0.8" EasingFunction="{StaticResource BouncyEase}" />
            
            <DoubleAnimation Storyboard.TargetName="fileTrans" Storyboard.TargetProperty="X" To="150" Duration="0:0:0.8" EasingFunction="{StaticResource BouncyEase}" />
            <DoubleAnimation Storyboard.TargetName="FileExplorer" Storyboard.TargetProperty="Opacity" To="0" Duration="0:0:0.4" />
            <ObjectAnimationUsingKeyFrames Storyboard.TargetName="FileExplorer" Storyboard.TargetProperty="Visibility">
                <DiscreteObjectKeyFrame KeyTime="0:0:0.8" Value="{x:Static Visibility.Collapsed}" />
            </ObjectAnimationUsingKeyFrames>
            
            <!-- Hide Close Button and Top Profile when contracting, show Bottom Profile -->
            <DoubleAnimation Storyboard.TargetName="btnCloseMenu" Storyboard.TargetProperty="Opacity" To="0" Duration="0:0:0.3" />
            <ObjectAnimationUsingKeyFrames Storyboard.TargetName="btnCloseMenu" Storyboard.TargetProperty="Visibility">
                <DiscreteObjectKeyFrame KeyTime="0:0:0.4" Value="{x:Static Visibility.Collapsed}" />
            </ObjectAnimationUsingKeyFrames>
            
            <DoubleAnimation Storyboard.TargetName="btnProfileTop" Storyboard.TargetProperty="Opacity" To="0" Duration="0:0:0.3" />
            <ObjectAnimationUsingKeyFrames Storyboard.TargetName="btnProfileTop" Storyboard.TargetProperty="Visibility">
                <DiscreteObjectKeyFrame KeyTime="0:0:0.4" Value="{x:Static Visibility.Collapsed}" />
            </ObjectAnimationUsingKeyFrames>
            <ObjectAnimationUsingKeyFrames Storyboard.TargetName="btnProfileBottom" Storyboard.TargetProperty="Visibility">
                <DiscreteObjectKeyFrame KeyTime="0:0:0.4" Value="{x:Static Visibility.Visible}" />
            </ObjectAnimationUsingKeyFrames>
            
            <!-- Hide Nearby Expand Users when contracting -->
            <DoubleAnimation Storyboard.TargetName="NearbyExpandPanel" Storyboard.TargetProperty="Opacity" To="0" Duration="0:0:0.3" />
            <ObjectAnimationUsingKeyFrames Storyboard.TargetName="NearbyExpandPanel" Storyboard.TargetProperty="Visibility">
                <DiscreteObjectKeyFrame KeyTime="0:0:0.4" Value="{x:Static Visibility.Collapsed}" />
            </ObjectAnimationUsingKeyFrames>
        </Storyboard>    
        
        <Storyboard x:Key="PopIn">
            <DoubleAnimation Storyboard.TargetName="winScale" Storyboard.TargetProperty="ScaleX" From="0.85" To="1.0" Duration="0:0:0.5" EasingFunction="{StaticResource BouncyEase}" />
            <DoubleAnimation Storyboard.TargetName="winScale" Storyboard.TargetProperty="ScaleY" From="0.85" To="1.0" Duration="0:0:0.5" EasingFunction="{StaticResource BouncyEase}" />
            <DoubleAnimation Storyboard.TargetName="winTrans" Storyboard.TargetProperty="Y" From="15" To="0" Duration="0:0:0.5" EasingFunction="{StaticResource BouncyEase}" />
            <DoubleAnimation Storyboard.TargetName="mainBorder" Storyboard.TargetProperty="Opacity" From="0" To="1" Duration="0:0:0.15" />
        </Storyboard>
        
        <DataTemplate x:Key="FolderGridTemplate">
            <Border x:Name="folderBorder" Background="Transparent" CornerRadius="8" Cursor="Hand" ToolTip="{Binding Name}" Margin="6" Padding="4" RenderTransformOrigin="0.5,0.5">
                <Border.RenderTransform>
                    <TransformGroup>
                        <ScaleTransform ScaleX="1" ScaleY="1" x:Name="itemScale" />
                        <TranslateTransform X="0" Y="0" x:Name="itemTrans" />
                    </TransformGroup>
                </Border.RenderTransform>
                <StackPanel Width="85" Height="90">
                    <TextBlock FontFamily="Segoe Fluent Icons, Segoe MDL2 Assets" Text="&#xE8B7;" Foreground="{DynamicResource SecondaryBrush}" FontSize="42" HorizontalAlignment="Center" Margin="0,5,0,0"/>
                    <TextBlock Text="{Binding Name}" Foreground="{DynamicResource PrimaryTextBrush}" TextAlignment="Center" TextWrapping="Wrap" MaxHeight="35" TextTrimming="CharacterEllipsis" FontSize="12" Margin="0,8,0,0" FontWeight="Medium"/>
                </StackPanel>
                <Border.Triggers>
                    <EventTrigger RoutedEvent="MouseEnter">
                        <BeginStoryboard>
                            <Storyboard>
                                <DoubleAnimation Storyboard.TargetName="folderBorder" Storyboard.TargetProperty="(UIElement.RenderTransform).(TransformGroup.Children)[0].(ScaleTransform.ScaleX)" To="1.05" Duration="0:0:0.3" EasingFunction="{StaticResource HoverEase}" />
                                <DoubleAnimation Storyboard.TargetName="folderBorder" Storyboard.TargetProperty="(UIElement.RenderTransform).(TransformGroup.Children)[0].(ScaleTransform.ScaleY)" To="1.05" Duration="0:0:0.3" EasingFunction="{StaticResource HoverEase}" />
                                <DoubleAnimation Storyboard.TargetName="folderBorder" Storyboard.TargetProperty="(UIElement.RenderTransform).(TransformGroup.Children)[1].(TranslateTransform.Y)" To="-2" Duration="0:0:0.3" EasingFunction="{StaticResource HoverEase}" />
                            </Storyboard>
                        </BeginStoryboard>
                    </EventTrigger>
                    <EventTrigger RoutedEvent="MouseLeave">
                        <BeginStoryboard>
                            <Storyboard>
                                <DoubleAnimation Storyboard.TargetName="folderBorder" Storyboard.TargetProperty="(UIElement.RenderTransform).(TransformGroup.Children)[0].(ScaleTransform.ScaleX)" To="1.0" Duration="0:0:0.4" EasingFunction="{StaticResource HoverEase}" />
                                <DoubleAnimation Storyboard.TargetName="folderBorder" Storyboard.TargetProperty="(UIElement.RenderTransform).(TransformGroup.Children)[0].(ScaleTransform.ScaleY)" To="1.0" Duration="0:0:0.4" EasingFunction="{StaticResource HoverEase}" />
                                <DoubleAnimation Storyboard.TargetName="folderBorder" Storyboard.TargetProperty="(UIElement.RenderTransform).(TransformGroup.Children)[1].(TranslateTransform.Y)" To="0" Duration="0:0:0.4" EasingFunction="{StaticResource HoverEase}" />
                            </Storyboard>
                        </BeginStoryboard>
                    </EventTrigger>
                    <EventTrigger RoutedEvent="PreviewMouseDown">
                        <BeginStoryboard>
                            <Storyboard>
                                <DoubleAnimation Storyboard.TargetName="folderBorder" Storyboard.TargetProperty="(UIElement.RenderTransform).(TransformGroup.Children)[0].(ScaleTransform.ScaleX)" To="0.94" Duration="0:0:0.1" />
                                <DoubleAnimation Storyboard.TargetName="folderBorder" Storyboard.TargetProperty="(UIElement.RenderTransform).(TransformGroup.Children)[0].(ScaleTransform.ScaleY)" To="0.94" Duration="0:0:0.1" />
                            </Storyboard>
                        </BeginStoryboard>
                    </EventTrigger>
                    <EventTrigger RoutedEvent="PreviewMouseUp">
                        <BeginStoryboard>
                            <Storyboard>
                                <DoubleAnimation Storyboard.TargetName="folderBorder" Storyboard.TargetProperty="(UIElement.RenderTransform).(TransformGroup.Children)[0].(ScaleTransform.ScaleX)" To="1.05" Duration="0:0:0.3" EasingFunction="{StaticResource HoverEase}" />
                                <DoubleAnimation Storyboard.TargetName="folderBorder" Storyboard.TargetProperty="(UIElement.RenderTransform).(TransformGroup.Children)[0].(ScaleTransform.ScaleY)" To="1.05" Duration="0:0:0.3" EasingFunction="{StaticResource HoverEase}" />
                            </Storyboard>
                        </BeginStoryboard>
                    </EventTrigger>
                </Border.Triggers>
            </Border>
        </DataTemplate>
        <DataTemplate x:Key="FileGridTemplate">
            <Border x:Name="fileBorder" Background="Transparent" CornerRadius="8" Cursor="Hand" ToolTip="{Binding Name}" Margin="6" Padding="4" RenderTransformOrigin="0.5,0.5">
                <Border.RenderTransform>
                    <TransformGroup>
                        <ScaleTransform ScaleX="1" ScaleY="1" x:Name="itemScale" />
                        <TranslateTransform X="0" Y="0" x:Name="itemTrans" />
                    </TransformGroup>
                </Border.RenderTransform>
                <StackPanel Width="85" Height="90">
                    <TextBlock FontFamily="Segoe Fluent Icons, Segoe MDL2 Assets" Text="&#xE7C3;" Foreground="{DynamicResource SecondaryTextBrush}" FontSize="42" HorizontalAlignment="Center" Margin="0,5,0,0"/>
                    <TextBlock Text="{Binding Name}" Foreground="{DynamicResource PrimaryTextBrush}" TextAlignment="Center" TextWrapping="Wrap" MaxHeight="35" TextTrimming="CharacterEllipsis" FontSize="12" Margin="0,8,0,0" Opacity="0.85"/>
                </StackPanel>
                <Border.Triggers>
                    <EventTrigger RoutedEvent="MouseEnter">
                        <BeginStoryboard>
                            <Storyboard>
                                <DoubleAnimation Storyboard.TargetName="fileBorder" Storyboard.TargetProperty="(UIElement.RenderTransform).(TransformGroup.Children)[0].(ScaleTransform.ScaleX)" To="1.05" Duration="0:0:0.3" EasingFunction="{StaticResource HoverEase}" />
                                <DoubleAnimation Storyboard.TargetName="fileBorder" Storyboard.TargetProperty="(UIElement.RenderTransform).(TransformGroup.Children)[0].(ScaleTransform.ScaleY)" To="1.05" Duration="0:0:0.3" EasingFunction="{StaticResource HoverEase}" />
                                <DoubleAnimation Storyboard.TargetName="fileBorder" Storyboard.TargetProperty="(UIElement.RenderTransform).(TransformGroup.Children)[1].(TranslateTransform.Y)" To="-2" Duration="0:0:0.3" EasingFunction="{StaticResource HoverEase}" />
                            </Storyboard>
                        </BeginStoryboard>
                    </EventTrigger>
                    <EventTrigger RoutedEvent="MouseLeave">
                        <BeginStoryboard>
                            <Storyboard>
                                <DoubleAnimation Storyboard.TargetName="fileBorder" Storyboard.TargetProperty="(UIElement.RenderTransform).(TransformGroup.Children)[0].(ScaleTransform.ScaleX)" To="1.0" Duration="0:0:0.4" EasingFunction="{StaticResource HoverEase}" />
                                <DoubleAnimation Storyboard.TargetName="fileBorder" Storyboard.TargetProperty="(UIElement.RenderTransform).(TransformGroup.Children)[0].(ScaleTransform.ScaleY)" To="1.0" Duration="0:0:0.4" EasingFunction="{StaticResource HoverEase}" />
                                <DoubleAnimation Storyboard.TargetName="fileBorder" Storyboard.TargetProperty="(UIElement.RenderTransform).(TransformGroup.Children)[1].(TranslateTransform.Y)" To="0" Duration="0:0:0.4" EasingFunction="{StaticResource HoverEase}" />
                            </Storyboard>
                        </BeginStoryboard>
                    </EventTrigger>
                    <EventTrigger RoutedEvent="PreviewMouseDown">
                        <BeginStoryboard>
                            <Storyboard>
                                <DoubleAnimation Storyboard.TargetName="fileBorder" Storyboard.TargetProperty="(UIElement.RenderTransform).(TransformGroup.Children)[0].(ScaleTransform.ScaleX)" To="0.94" Duration="0:0:0.1" />
                                <DoubleAnimation Storyboard.TargetName="fileBorder" Storyboard.TargetProperty="(UIElement.RenderTransform).(TransformGroup.Children)[0].(ScaleTransform.ScaleY)" To="0.94" Duration="0:0:0.1" />
                            </Storyboard>
                        </BeginStoryboard>
                    </EventTrigger>
                    <EventTrigger RoutedEvent="PreviewMouseUp">
                        <BeginStoryboard>
                            <Storyboard>
                                <DoubleAnimation Storyboard.TargetName="fileBorder" Storyboard.TargetProperty="(UIElement.RenderTransform).(TransformGroup.Children)[0].(ScaleTransform.ScaleX)" To="1.05" Duration="0:0:0.3" EasingFunction="{StaticResource HoverEase}" />
                                <DoubleAnimation Storyboard.TargetName="fileBorder" Storyboard.TargetProperty="(UIElement.RenderTransform).(TransformGroup.Children)[0].(ScaleTransform.ScaleY)" To="1.05" Duration="0:0:0.3" EasingFunction="{StaticResource HoverEase}" />
                            </Storyboard>
                        </BeginStoryboard>
                    </EventTrigger>
                </Border.Triggers>
            </Border>
        </DataTemplate>
        <Style x:Key="SpatialListItem" TargetType="Button">
            <Setter Property="Background" Value="Transparent"/>
            <Setter Property="Foreground" Value="{DynamicResource PrimaryTextBrush}"/>
            <Setter Property="BorderThickness" Value="0"/>
            <Setter Property="Padding" Value="16,10"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border x:Name="border" Background="{TemplateBinding Background}" CornerRadius="12" Padding="{TemplateBinding Padding}" Margin="8,1" RenderTransformOrigin="0.5,0.5">
                            <Border.RenderTransform>
                                <TransformGroup>
                                    <ScaleTransform ScaleX="1" ScaleY="1" x:Name="btnScale" />
                                    <TranslateTransform X="0" Y="0" x:Name="btnTrans" />
                                </TransformGroup>
                            </Border.RenderTransform>
                            <ContentPresenter HorizontalAlignment="Stretch" VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="border" Property="Background" Value="{DynamicResource TertiaryBackgroundBrush}"/>
                            </Trigger>
                            <Trigger Property="IsPressed" Value="True">
                                <Setter TargetName="border" Property="Background" Value="{DynamicResource BorderBrush}"/>
                            </Trigger>
                            <EventTrigger RoutedEvent="MouseEnter">
                                <BeginStoryboard>
                                    <Storyboard>
                                        <DoubleAnimation Storyboard.TargetName="btnTrans" Storyboard.TargetProperty="X" To="6" Duration="0:0:0.5" EasingFunction="{StaticResource HoverEase}" />
                                    </Storyboard>
                                </BeginStoryboard>
                            </EventTrigger>
                            <EventTrigger RoutedEvent="PreviewMouseDown">
                                <BeginStoryboard>
                                    <Storyboard>
                                        <DoubleAnimation Storyboard.TargetName="btnScale" Storyboard.TargetProperty="ScaleX" To="0.96" Duration="0:0:0.1" />
                                        <DoubleAnimation Storyboard.TargetName="btnScale" Storyboard.TargetProperty="ScaleY" To="0.96" Duration="0:0:0.1" />
                                        <DoubleAnimation Storyboard.TargetName="btnTrans" Storyboard.TargetProperty="X" To="12" Duration="0:0:0.1" />
                                    </Storyboard>
                                </BeginStoryboard>
                            </EventTrigger>
                            <EventTrigger RoutedEvent="PreviewMouseUp">
                                <BeginStoryboard>
                                    <Storyboard>
                                        <DoubleAnimation Storyboard.TargetName="btnScale" Storyboard.TargetProperty="ScaleX" To="1.0" Duration="0:0:0.5" EasingFunction="{StaticResource HoverEase}" />
                                        <DoubleAnimation Storyboard.TargetName="btnScale" Storyboard.TargetProperty="ScaleY" To="1.0" Duration="0:0:0.5" EasingFunction="{StaticResource HoverEase}" />
                                        <DoubleAnimation Storyboard.TargetName="btnTrans" Storyboard.TargetProperty="X" To="6" Duration="0:0:0.5" EasingFunction="{StaticResource HoverEase}" />
                                    </Storyboard>
                                </BeginStoryboard>
                            </EventTrigger>
                            <EventTrigger RoutedEvent="MouseLeave">
                                <BeginStoryboard>
                                    <Storyboard>
                                        <DoubleAnimation Storyboard.TargetName="btnScale" Storyboard.TargetProperty="ScaleX" To="1.0" Duration="0:0:0.5" EasingFunction="{StaticResource HoverEase}" />
                                        <DoubleAnimation Storyboard.TargetName="btnScale" Storyboard.TargetProperty="ScaleY" To="1.0" Duration="0:0:0.5" EasingFunction="{StaticResource HoverEase}" />
                                        <DoubleAnimation Storyboard.TargetName="btnTrans" Storyboard.TargetProperty="X" To="0" Duration="0:0:0.5" EasingFunction="{StaticResource HoverEase}" />
                                    </Storyboard>
                                </BeginStoryboard>
                            </EventTrigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
        <Style x:Key="QuickActionBtn" TargetType="Button">
            <Setter Property="Background" Value="{DynamicResource SecondaryBackgroundBrush}"/>
            <Setter Property="Foreground" Value="{DynamicResource PrimaryTextBrush}"/>
            <Setter Property="BorderThickness" Value="0"/>
            <Setter Property="Width" Value="56"/>
            <Setter Property="Height" Value="44"/>
            <Setter Property="FontFamily" Value="Segoe Fluent Icons, Segoe MDL2 Assets"/>
            <Setter Property="FontSize" Value="20"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border x:Name="border" Background="{TemplateBinding Background}" CornerRadius="20" RenderTransformOrigin="0.5,0.5">
                            <Border.RenderTransform>
                                <TransformGroup>
                                    <ScaleTransform ScaleX="1" ScaleY="1" x:Name="btnScale" />
                                    <TranslateTransform X="0" Y="0" x:Name="btnTrans" />
                                </TransformGroup>
                            </Border.RenderTransform>
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="border" Property="Background" Value="{DynamicResource TertiaryBackgroundBrush}"/>
                            </Trigger>
                            <EventTrigger RoutedEvent="MouseEnter">
                                <BeginStoryboard>
                                    <Storyboard>
                                        <DoubleAnimation Storyboard.TargetName="btnScale" Storyboard.TargetProperty="ScaleX" To="1.08" Duration="0:0:0.5" EasingFunction="{StaticResource HoverEase}" />
                                        <DoubleAnimation Storyboard.TargetName="btnScale" Storyboard.TargetProperty="ScaleY" To="1.08" Duration="0:0:0.5" EasingFunction="{StaticResource HoverEase}" />
                                        <DoubleAnimation Storyboard.TargetName="btnTrans" Storyboard.TargetProperty="Y" To="-3" Duration="0:0:0.5" EasingFunction="{StaticResource HoverEase}" />
                                    </Storyboard>
                                </BeginStoryboard>
                            </EventTrigger>
                            <EventTrigger RoutedEvent="PreviewMouseDown">
                                <BeginStoryboard>
                                    <Storyboard>
                                        <DoubleAnimation Storyboard.TargetName="btnScale" Storyboard.TargetProperty="ScaleX" To="0.85" Duration="0:0:0.1" />
                                        <DoubleAnimation Storyboard.TargetName="btnScale" Storyboard.TargetProperty="ScaleY" To="0.85" Duration="0:0:0.1" />
                                        <DoubleAnimation Storyboard.TargetName="btnTrans" Storyboard.TargetProperty="Y" To="3" Duration="0:0:0.1" />
                                    </Storyboard>
                                </BeginStoryboard>
                            </EventTrigger>
                            <EventTrigger RoutedEvent="PreviewMouseUp">
                                <BeginStoryboard>
                                    <Storyboard>
                                        <DoubleAnimation Storyboard.TargetName="btnScale" Storyboard.TargetProperty="ScaleX" To="1.08" Duration="0:0:0.5" EasingFunction="{StaticResource HoverEase}" />
                                        <DoubleAnimation Storyboard.TargetName="btnScale" Storyboard.TargetProperty="ScaleY" To="1.08" Duration="0:0:0.5" EasingFunction="{StaticResource HoverEase}" />
                                        <DoubleAnimation Storyboard.TargetName="btnTrans" Storyboard.TargetProperty="Y" To="-3" Duration="0:0:0.5" EasingFunction="{StaticResource HoverEase}" />
                                    </Storyboard>
                                </BeginStoryboard>
                            </EventTrigger>
                            <EventTrigger RoutedEvent="MouseLeave">
                                <BeginStoryboard>
                                    <Storyboard>
                                        <DoubleAnimation Storyboard.TargetName="btnScale" Storyboard.TargetProperty="ScaleX" To="1.0" Duration="0:0:0.5" EasingFunction="{StaticResource HoverEase}" />
                                        <DoubleAnimation Storyboard.TargetName="btnScale" Storyboard.TargetProperty="ScaleY" To="1.0" Duration="0:0:0.5" EasingFunction="{StaticResource HoverEase}" />
                                        <DoubleAnimation Storyboard.TargetName="btnTrans" Storyboard.TargetProperty="Y" To="0" Duration="0:0:0.5" EasingFunction="{StaticResource HoverEase}" />
                                    </Storyboard>
                                </BeginStoryboard>
                            </EventTrigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
    </Window.Resources>
    <Border x:Name="mainBorder" HorizontalAlignment="Right" VerticalAlignment="Bottom" CornerRadius="34" BorderBrush="{DynamicResource BorderBrush}" BorderThickness="1" Background="{DynamicResource PrimaryBackgroundGradient}" RenderTransformOrigin="0.5,1">
        <Border.RenderTransform>
            <TransformGroup>
                <ScaleTransform ScaleX="1" ScaleY="1" x:Name="winScale" />
                <TranslateTransform Y="0" x:Name="winTrans" />
            </TransformGroup>
        </Border.RenderTransform>

        <Grid>
        <Grid.ColumnDefinitions>
            <ColumnDefinition Width="*" />
            <ColumnDefinition Width="Auto" />
        </Grid.ColumnDefinitions>
        
        <Grid Name="FileExplorer" Grid.Column="0" Visibility="Collapsed" Opacity="0" Margin="24,24,15,15">
            <Grid.RenderTransform>
                <TranslateTransform x:Name="fileTrans" X="150" />
            </Grid.RenderTransform>
            <Grid.RowDefinitions>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="*"/>
            </Grid.RowDefinitions>
            
            <Grid Grid.Row="0" Margin="0,0,0,15">
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="Auto" />
                    <ColumnDefinition Width="*" />
                    <ColumnDefinition Width="Auto" />
                </Grid.ColumnDefinitions>
                
                <Button Name="btnUpDir" Grid.Column="0" Background="{DynamicResource TertiaryBackgroundBrush}" BorderThickness="0" Foreground="{DynamicResource PrimaryTextBrush}" FontFamily="Segoe Fluent Icons, Segoe MDL2 Assets" FontSize="16" Content="&#xE898;" Cursor="Hand" ToolTip="Up Directory" Margin="0,0,12,0" VerticalAlignment="Center" Padding="12">
                    <Button.Template>
                        <ControlTemplate TargetType="Button">
                            <Border Background="{TemplateBinding Background}" CornerRadius="18">
                                <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                            </Border>
                        </ControlTemplate>
                    </Button.Template>
                </Button>
                
                <Border Grid.Column="1" Background="{DynamicResource TertiaryBackgroundBrush}" CornerRadius="20" Padding="14,8">
                    <Grid>
                        <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="Auto"/>
                            <ColumnDefinition Width="*"/>
                        </Grid.ColumnDefinitions>
                        <TextBlock Text="&#xE721;" FontFamily="Segoe Fluent Icons, Segoe MDL2 Assets" FontSize="14" Foreground="{DynamicResource SecondaryTextBrush}" VerticalAlignment="Center" Margin="0,0,8,0" />
                        <TextBox Name="txtSearch" Grid.Column="1" Text="Search files..." FontSize="14" Foreground="{DynamicResource SecondaryTextBrush}" CaretBrush="{DynamicResource PrimaryTextBrush}" Background="Transparent" BorderThickness="0" FontWeight="SemiBold" VerticalAlignment="Center" FontFamily="Segoe UI" Padding="0" Margin="0" />
                    </Grid>
                </Border>
                
                <Button Name="btnProfileTop" Grid.Column="2" Style="{StaticResource SpatialListItem}" Margin="12,0,12,0" ToolTip="Sign in with Google (Premium)" VerticalAlignment="Center" Padding="0" Visibility="Collapsed" Opacity="0">
                    <Grid>
                        <Ellipse Width="34" Height="34">
                            <Ellipse.Fill>
                                <ImageBrush ImageSource="file:///$($PSScriptRoot -replace '\\', '/')/../Assets/ProfileAvatar.jpg" Stretch="UniformToFill" AlignmentY="Top" />
                            </Ellipse.Fill>
                        </Ellipse>
                    </Grid>
                </Button>
            </Grid>
            
            <ListBox Name="lbFiles" Grid.Row="1" SelectionMode="Extended" Background="Transparent" BorderThickness="0" ScrollViewer.HorizontalScrollBarVisibility="Disabled" ScrollViewer.VerticalScrollBarVisibility="Hidden" Padding="0,0,10,0">
                <ListBox.ItemContainerStyle>
                    <Style TargetType="ListBoxItem">
                        <Setter Property="Background" Value="Transparent"/>
                        <Setter Property="BorderBrush" Value="Transparent"/>
                        <Setter Property="BorderThickness" Value="1"/>
                        <Setter Property="Padding" Value="2"/>
                        <Setter Property="Margin" Value="2"/>
                        <Setter Property="FocusVisualStyle" Value="{x:Null}"/>
                        <Setter Property="Template">
                            <Setter.Value>
                                <ControlTemplate TargetType="ListBoxItem">
                                    <Border Name="itemBorder" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="10" SnapsToDevicePixels="True">
                                        <ContentPresenter />
                                    </Border>
                                    <ControlTemplate.Triggers>
                                        <Trigger Property="IsMouseOver" Value="True">
                                            <Setter TargetName="itemBorder" Property="Background" Value="{DynamicResource ItemHoverBrush}"/>
                                        </Trigger>
                                        <Trigger Property="IsSelected" Value="True">
                                            <Setter TargetName="itemBorder" Property="Background" Value="{DynamicResource ItemSelectedBrush}"/>
                                            <Setter TargetName="itemBorder" Property="BorderBrush" Value="{DynamicResource ItemSelectedBorderBrush}"/>
                                        </Trigger>
                                        <MultiTrigger>
                                            <MultiTrigger.Conditions>
                                                <Condition Property="IsSelected" Value="True"/>
                                                <Condition Property="IsMouseOver" Value="True"/>
                                            </MultiTrigger.Conditions>
                                            <Setter TargetName="itemBorder" Property="Background" Value="{DynamicResource ItemSelectedHoverBrush}"/>
                                            <Setter TargetName="itemBorder" Property="BorderBrush" Value="{DynamicResource ItemSelectedBorderBrush}"/>
                                        </MultiTrigger>
                                    </ControlTemplate.Triggers>
                                </ControlTemplate>
                            </Setter.Value>
                        </Setter>
                    </Style>
                </ListBox.ItemContainerStyle>
                <ListBox.ItemsPanel>
                    <ItemsPanelTemplate>
                        <WrapPanel IsItemsHost="True" Orientation="Horizontal" />
                    </ItemsPanelTemplate>
                </ListBox.ItemsPanel>
            </ListBox>
            
            <!-- Empty Folder State Overlay -->
            <StackPanel Name="emptyFolderState" Grid.Row="1" VerticalAlignment="Center" HorizontalAlignment="Center" Visibility="Collapsed" Opacity="0">
                <TextBlock FontFamily="Segoe Fluent Icons, Segoe MDL2 Assets" Text="&#xE8B7;" Foreground="{DynamicResource SecondaryTextBrush}" FontSize="48" HorizontalAlignment="Center" Opacity="0.4" Margin="0,0,0,10"/>
                <TextBlock Text="This folder is empty" FontSize="14" Foreground="{DynamicResource SecondaryTextBrush}" FontWeight="Medium" HorizontalAlignment="Center" Opacity="0.6"/>
            </StackPanel>
            
            <!-- Subtle Floating Dock for Download Status & Location Change -->
            <Border Name="dockDownloadToast" Grid.Row="1" VerticalAlignment="Bottom" HorizontalAlignment="Center" Margin="0,0,0,15" Background="{DynamicResource SecondaryBackgroundBrush}" BorderBrush="{DynamicResource BorderBrush}" BorderThickness="1" CornerRadius="20" Padding="14,8" Visibility="Collapsed" Opacity="0" RenderTransformOrigin="0.5,1">
                <Border.RenderTransform>
                    <TransformGroup>
                        <ScaleTransform x:Name="dockScale" ScaleX="0.8" ScaleY="0.8" />
                        <TranslateTransform x:Name="dockTrans" Y="25" />
                    </TransformGroup>
                </Border.RenderTransform>
                <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
                    <TextBlock FontFamily="Segoe Fluent Icons, Segoe MDL2 Assets" Text="&#xE8F4;" Foreground="{DynamicResource SecondaryBrush}" FontSize="14" VerticalAlignment="Center" Margin="0,0,8,0" />
                    <TextBlock Name="txtDownloadToast" Text="Saved to Downloads\dex" FontSize="13" Foreground="{DynamicResource PrimaryTextBrush}" FontWeight="Medium" VerticalAlignment="Center" Margin="0,0,12,0" />
                    <Button Name="btnChangeDownloadPath" Content="Change" FontSize="12" FontWeight="SemiBold" Foreground="{DynamicResource PrimaryBrush}" Background="Transparent" BorderThickness="0" Cursor="Hand" VerticalAlignment="Center"/>
                </StackPanel>
            </Border>
        </Grid>
        
        <Border Grid.Column="1" Background="Transparent" Padding="0">
            <Border.RenderTransform>
                <TranslateTransform x:Name="menuTrans" X="0" />
            </Border.RenderTransform>
            <Border Background="Transparent" CornerRadius="34">
                <DockPanel Margin="8,12" LastChildFill="True">
                
                <!-- Close Button: docked at top-right, hidden when contracted -->
                <Button Name="btnCloseMenu" DockPanel.Dock="Top" HorizontalAlignment="Right" Background="Transparent" BorderThickness="0" Foreground="{DynamicResource SecondaryTextBrush}" FontFamily="Segoe Fluent Icons, Segoe MDL2 Assets" FontSize="14" ToolTip="Close" Cursor="Hand" Margin="0,0,8,0" Visibility="Collapsed" Opacity="0">
                    <TextBlock Text="&#xE711;" />
                    <Button.Template>
                        <ControlTemplate TargetType="Button">
                            <Border x:Name="border" Background="Transparent" CornerRadius="12" Padding="6,4" RenderTransformOrigin="0.5,0.5">
                                <Border.RenderTransform>
                                    <ScaleTransform ScaleX="1" ScaleY="1" x:Name="closeScale" />
                                </Border.RenderTransform>
                                <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                            </Border>
                            <ControlTemplate.Triggers>
                                <Trigger Property="IsMouseOver" Value="True">
                                    <Setter TargetName="border" Property="Background" Value="{DynamicResource TertiaryBackgroundBrush}"/>
                                    <Setter Property="Foreground" Value="{DynamicResource AccentBrush}"/>
                                </Trigger>
                                <EventTrigger RoutedEvent="MouseEnter">
                                    <BeginStoryboard>
                                        <Storyboard>
                                            <DoubleAnimation Storyboard.TargetName="closeScale" Storyboard.TargetProperty="ScaleX" To="1.15" Duration="0:0:0.3" EasingFunction="{StaticResource HoverEase}" />
                                            <DoubleAnimation Storyboard.TargetName="closeScale" Storyboard.TargetProperty="ScaleY" To="1.15" Duration="0:0:0.3" EasingFunction="{StaticResource HoverEase}" />
                                        </Storyboard>
                                    </BeginStoryboard>
                                </EventTrigger>
                                <EventTrigger RoutedEvent="MouseLeave">
                                    <BeginStoryboard>
                                        <Storyboard>
                                            <DoubleAnimation Storyboard.TargetName="closeScale" Storyboard.TargetProperty="ScaleX" To="1.0" Duration="0:0:0.3" EasingFunction="{StaticResource HoverEase}" />
                                            <DoubleAnimation Storyboard.TargetName="closeScale" Storyboard.TargetProperty="ScaleY" To="1.0" Duration="0:0:0.3" EasingFunction="{StaticResource HoverEase}" />
                                        </Storyboard>
                                    </BeginStoryboard>
                                </EventTrigger>
                            </ControlTemplate.Triggers>
                        </ControlTemplate>
                    </Button.Template>
                </Button>
                
                <!-- Exit Engine & Profile: docked at bottom so it never moves -->
                <StackPanel DockPanel.Dock="Bottom">
                    <Separator Background="{DynamicResource SecondaryBackgroundBrush}" Height="1" Margin="16,8" />
                    <Grid Margin="0,0,0,4">
                        <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="Auto" />
                            <ColumnDefinition Width="*" />
                        </Grid.ColumnDefinitions>
                        
                        <Button Name="btnProfileBottom" Grid.Column="0" Style="{StaticResource SpatialListItem}" Margin="16,0,4,0" ToolTip="Sign in with Google (Premium)" VerticalAlignment="Center" Padding="0">
                            <Grid>
                                <Ellipse Width="34" Height="34">
                                    <Ellipse.Fill>
                                        <ImageBrush ImageSource="file:///$($PSScriptRoot -replace '\\', '/')/../Assets/ProfileAvatar.jpg" Stretch="UniformToFill" AlignmentY="Top" />
                                    </Ellipse.Fill>
                                </Ellipse>
                            </Grid>
                        </Button>
                        
                        <Button Name="btnExit" Grid.Column="1" Style="{StaticResource SpatialListItem}">
                            <Grid>
                                <TextBlock Name="txtExitBtn" Text="Exit Engine" FontSize="15" FontFamily="Segoe UI" FontWeight="Medium" Foreground="{DynamicResource AccentBrush}" HorizontalAlignment="Left" VerticalAlignment="Center"/>
                                <TextBlock Text="&#x2318;Q" FontSize="14" Foreground="{DynamicResource AccentBrush}" HorizontalAlignment="Right" FontFamily="Consolas" VerticalAlignment="Center"/>
                            </Grid>
                        </Button>
                    </Grid>
                </StackPanel>
                
                <!-- Main content fills remaining space -->
                <DockPanel LastChildFill="True">
                    <StackPanel DockPanel.Dock="Top">
                        <StackPanel Orientation="Horizontal" HorizontalAlignment="Center" Margin="0,4,0,12">
                    <Button Name="btnQAConnect" Style="{StaticResource QuickActionBtn}" Margin="3,0" ToolTip="Connect ADB">
                        <TextBlock Text="&#xE71B;" />
                    </Button>
                    <Button Name="btnQADisconnect" Style="{StaticResource QuickActionBtn}" Margin="3,0" ToolTip="Disconnect">
                        <TextBlock Text="&#xE7E8;" />
                    </Button>
                    <Button Name="btnQAMirror" Style="{StaticResource QuickActionBtn}" Margin="3,0" ToolTip="Mirror Phone">
                        <TextBlock Text="&#xE8EA;" />
                    </Button>
                    <Button Name="btnQAPull" Style="{StaticResource QuickActionBtn}" Margin="3,0" ToolTip="Phone Files">
                        <TextBlock Text="&#xE8B7;" />
                    </Button>
                    <Button Name="btnQAAuto" Style="{StaticResource QuickActionBtn}" Margin="3,0" ToolTip="Toggle Auto-Connect">
                        <TextBlock Name="txtQAAuto" Text="&#xE895;" />
                    </Button>
                </StackPanel>
                
                <Separator Background="{DynamicResource SecondaryBackgroundBrush}" Height="1" Margin="16,0" />
                <StackPanel Orientation="Horizontal" Margin="24,10,24,10">
                    <TextBlock Name="txtStatus" Text="Status: Initializing..." Foreground="{DynamicResource SecondaryTextBrush}" FontSize="13" FontFamily="Segoe UI" VerticalAlignment="Center" />
                    <Button Name="btnCopyIP" Background="Transparent" BorderThickness="0" Foreground="{DynamicResource SecondaryTextBrush}" FontFamily="Segoe Fluent Icons, Segoe MDL2 Assets" FontSize="14" ToolTip="Copy IP:Port" Cursor="Hand" Visibility="Collapsed" VerticalAlignment="Center" Margin="6,0,0,0">
                        <TextBlock Text="&#xE8C8;" />
                        <Button.Template>
                            <ControlTemplate TargetType="Button">
                                <Border x:Name="border" Background="Transparent" CornerRadius="4" Padding="4">
                                    <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                                </Border>
                                <ControlTemplate.Triggers>
                                    <Trigger Property="IsMouseOver" Value="True">
                                        <Setter TargetName="border" Property="Background" Value="{DynamicResource TertiaryBackgroundBrush}"/>
                                        <Setter Property="Foreground" Value="{DynamicResource PrimaryTextBrush}"/>
                                    </Trigger>
                                </ControlTemplate.Triggers>
                            </ControlTemplate>
                        </Button.Template>
                    </Button>
                </StackPanel>
                <Separator Background="{DynamicResource SecondaryBackgroundBrush}" Height="1" Margin="16,0" />
                    </StackPanel>
                
                    <!-- Nearby Users Section -->
                    <ScrollViewer VerticalScrollBarVisibility="Hidden" PanningMode="VerticalOnly">
                        <StackPanel Margin="0,0,0,8">
                            <TextBlock Text="Nearby Users" FontSize="13" Foreground="{DynamicResource SecondaryTextBrush}" FontWeight="SemiBold" Margin="12,12,0,4" />

                <!-- User Joe (always visible when contracted) -->
                <Button x:Name="btnUserJoe" Style="{StaticResource SpatialListItem}" Margin="0,2,0,2">
                    <Button.ContextMenu>
                        <ContextMenu x:Name="menuUserJoe" Background="{DynamicResource SecondaryBackgroundBrush}" Foreground="{DynamicResource PrimaryTextBrush}" BorderBrush="{DynamicResource BorderBrush}" BorderThickness="1" HasDropShadow="True">
                            <MenuItem x:Name="menuItemTheme" Header="Toggle Theme" />
                        </ContextMenu>
                    </Button.ContextMenu>
                    <Grid>
                        <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="Auto" />
                            <ColumnDefinition Width="*" />
                        </Grid.ColumnDefinitions>
                        
                        <Grid Width="38" Height="38" Margin="0,0,12,0">
                            <Ellipse>
                                <Ellipse.Fill>
                                    <ImageBrush ImageSource="file:///$($PSScriptRoot -replace '\\', '/')/../Assets/JoeAvatar.jpg" Stretch="UniformToFill" AlignmentY="Top" />
                                </Ellipse.Fill>
                            </Ellipse>
                            <Ellipse Width="12" Height="12" Fill="{DynamicResource SecondaryBrush}" Stroke="{DynamicResource SecondaryBackgroundBrush}" StrokeThickness="2" HorizontalAlignment="Right" VerticalAlignment="Bottom" />
                        </Grid>
                        
                        <StackPanel Grid.Column="1" VerticalAlignment="Center">
                            <TextBlock Text="Joe Belfiore" FontSize="15" FontFamily="Segoe UI" FontWeight="Medium" Foreground="{DynamicResource PrimaryTextBrush}"/>
                            <TextBlock Text="joe.belfiore@gmail.com" FontSize="13" Foreground="{DynamicResource SecondaryTextBrush}" />
                        </StackPanel>
                    </Grid>
                </Button>

                <!-- Device: Galaxy S21 (unhidden, original phone icon avatar) -->
                <Button x:Name="btnDeviceGalaxy" Style="{StaticResource SpatialListItem}" Margin="0,2,0,2">
                    <Grid>
                        <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="Auto" />
                            <ColumnDefinition Width="*" />
                            <ColumnDefinition Width="Auto" />
                        </Grid.ColumnDefinitions>
                        
                        <Grid Width="38" Height="38" Margin="0,0,12,0">
                            <Ellipse Fill="{DynamicResource SecondaryBrush}" />
                            <TextBlock Text="&#xE8EA;" FontFamily="Segoe Fluent Icons, Segoe MDL2 Assets" Foreground="{DynamicResource PrimaryTextBrush}" FontSize="18" HorizontalAlignment="Center" VerticalAlignment="Center" />
                        </Grid>
                        
                        <StackPanel Grid.Column="1" VerticalAlignment="Center">
                            <TextBlock Text="Galaxy S21" FontSize="15" FontFamily="Segoe UI" FontWeight="Medium" Foreground="{DynamicResource PrimaryTextBrush}"/>
                        </StackPanel>
                        
                        <TextBlock Grid.Column="2" Text="&#xE8EA;" FontFamily="Segoe Fluent Icons, Segoe MDL2 Assets" Foreground="{DynamicResource SecondaryTextBrush}" FontSize="18" VerticalAlignment="Center" Margin="0,0,8,0" />
                    </Grid>
                </Button>

                <!-- Device: Windows (always visible when contracted) -->
                <Button x:Name="btnDeviceWindows" Style="{StaticResource SpatialListItem}" Margin="0,2,0,2">
                    <Grid>
                        <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="Auto" />
                            <ColumnDefinition Width="*" />
                        </Grid.ColumnDefinitions>
                        
                        <Grid Width="38" Height="38" Margin="0,0,12,0">
                            <Ellipse Fill="{DynamicResource SecondaryBrush}" />
                            <TextBlock Text="&#xE7F8;" FontFamily="Segoe Fluent Icons, Segoe MDL2 Assets" Foreground="{DynamicResource PrimaryTextBrush}" FontSize="18" HorizontalAlignment="Center" VerticalAlignment="Center" />
                        </Grid>
                        
                        <StackPanel Grid.Column="1" VerticalAlignment="Center">
                            <TextBlock Text="Windows" FontSize="15" FontFamily="Segoe UI" FontWeight="Medium" Foreground="{DynamicResource PrimaryTextBrush}"/>
                        </StackPanel>
                    </Grid>
                </Button>

                <!-- Nearby Expand Panel: hidden when contracted, staggers in when expanded -->
                <StackPanel x:Name="NearbyExpandPanel" Visibility="Collapsed" Opacity="0">
                    <Separator Background="{DynamicResource SecondaryBackgroundBrush}" Height="1" Margin="16,6" />

                    <!-- User 1 -->
                    <Button x:Name="btnUser1" Style="{StaticResource SpatialListItem}" Margin="0,2,0,2">
                        <Grid>
                            <Grid.ColumnDefinitions>
                                <ColumnDefinition Width="Auto" />
                                <ColumnDefinition Width="*" />
                            </Grid.ColumnDefinitions>
                            
                            <Grid Width="38" Height="38" Margin="0,0,12,0">
                                <Ellipse>
                                    <Ellipse.Fill>
                                        <ImageBrush ImageSource="file:///$($PSScriptRoot -replace '\\', '/')/../Assets/User1Avatar.png" Stretch="UniformToFill" AlignmentY="Top" />
                                    </Ellipse.Fill>
                                </Ellipse>
                                <Ellipse Width="12" Height="12" Fill="{DynamicResource SecondaryBrush}" Stroke="{DynamicResource SecondaryBackgroundBrush}" StrokeThickness="2" HorizontalAlignment="Right" VerticalAlignment="Bottom" />
                            </Grid>
                            
                            <StackPanel Grid.Column="1" VerticalAlignment="Center">
                                <TextBlock Text="Ama Serwaa" FontSize="15" FontFamily="Segoe UI" FontWeight="Medium" Foreground="{DynamicResource PrimaryTextBrush}"/>
                                <TextBlock Text="Local Network" FontSize="12" Foreground="{DynamicResource SecondaryTextBrush}" />
                            </StackPanel>
                        </Grid>
                    </Button>

                    <!-- User 2 -->
                    <Button x:Name="btnUser2" Style="{StaticResource SpatialListItem}" Margin="0,2,0,2">
                        <Grid>
                            <Grid.ColumnDefinitions>
                                <ColumnDefinition Width="Auto" />
                                <ColumnDefinition Width="*" />
                            </Grid.ColumnDefinitions>
                            
                            <Grid Width="38" Height="38" Margin="0,0,12,0">
                                <Ellipse>
                                    <Ellipse.Fill>
                                        <ImageBrush ImageSource="file:///$($PSScriptRoot -replace '\\', '/')/../Assets/User2Avatar.png" Stretch="UniformToFill" AlignmentY="Top" />
                                    </Ellipse.Fill>
                                </Ellipse>
                                <Ellipse Width="12" Height="12" Fill="{DynamicResource SecondaryBrush}" Stroke="{DynamicResource SecondaryBackgroundBrush}" StrokeThickness="2" HorizontalAlignment="Right" VerticalAlignment="Bottom" />
                            </Grid>
                            
                            <StackPanel Grid.Column="1" VerticalAlignment="Center">
                                <TextBlock Text="Akua Donkor" FontSize="15" FontFamily="Segoe UI" FontWeight="Medium" Foreground="{DynamicResource PrimaryTextBrush}"/>
                                <TextBlock Text="Local Network" FontSize="12" Foreground="{DynamicResource SecondaryTextBrush}" />
                            </StackPanel>
                        </Grid>
                    </Button>

                    <!-- User 3 -->
                    <Button x:Name="btnUser3" Style="{StaticResource SpatialListItem}" Margin="0,2,0,2">
                        <Grid>
                            <Grid.ColumnDefinitions>
                                <ColumnDefinition Width="Auto" />
                                <ColumnDefinition Width="*" />
                            </Grid.ColumnDefinitions>
                            
                            <Grid Width="38" Height="38" Margin="0,0,12,0">
                                <Ellipse>
                                    <Ellipse.Fill>
                                        <ImageBrush ImageSource="file:///$($PSScriptRoot -replace '\\', '/')/../Assets/User3Avatar.jpg" Stretch="UniformToFill" AlignmentY="Top" />
                                    </Ellipse.Fill>
                                </Ellipse>
                                <Ellipse Width="12" Height="12" Fill="{DynamicResource SecondaryBrush}" Stroke="{DynamicResource SecondaryBackgroundBrush}" StrokeThickness="2" HorizontalAlignment="Right" VerticalAlignment="Bottom" />
                            </Grid>
                            
                            <StackPanel Grid.Column="1" VerticalAlignment="Center">
                                <TextBlock Text="Kwame Asante" FontSize="15" FontFamily="Segoe UI" FontWeight="Medium" Foreground="{DynamicResource PrimaryTextBrush}"/>
                                <TextBlock Text="Global · via Hotspot" FontSize="12" Foreground="{DynamicResource SecondaryTextBrush}" />
                            </StackPanel>
                        </Grid>
                    </Button>
                </StackPanel>
                        </StackPanel>
                    </ScrollViewer>
                </DockPanel>
                
                </DockPanel>
        </Border>
        </Border>
    </Grid>
    </Border>
</Window>
"@

# Fail fast: if the XAML fails to parse/load, $script:wpfWindow stays null and the tray icon
# would keep running as a zombie that silently ignores every click. Exit loudly instead.
try {
    $reader = New-Object System.Xml.XmlNodeReader ([xml]$xaml)
    $script:wpfWindow = [System.Windows.Markup.XamlReader]::Load($reader)
    if ($null -eq $script:wpfWindow) { throw "XamlReader returned a null window." }
    $reader.Close()
} catch {
    $script:wpfWindow = $null
    $script:WindowLoadError = $_.Exception.Message
}

# Never-dead tray: if the spatial UI fails to load, degrade to a minimal WinForms
# fallback menu so core ADB features keep working instead of a silent zombie icon.
if ($null -eq $script:wpfWindow) {
    if ($SelfTest) {
        Write-Output "SELFTEST FATAL: $script:WindowLoadError"
        $script:notifyIcon.Visible = $false
        $script:notifyIcon.Dispose()
        exit 1
    }
    [System.Windows.MessageBox]::Show("Connect Phone ADB could not load its spatial interface and is running in fallback mode.`n`n$script:WindowLoadError", "Connect Phone ADB - Fallback Mode", 'OK', 'Warning') | Out-Null

    $script:notifyIcon.Text = "Connect ADB (Fallback Mode)"
    $fallbackMenu = New-Object System.Windows.Forms.ContextMenuStrip

    $miConnect = $fallbackMenu.Items.Add("Connect ADB Now")
    $miConnect.Add_Click({
        $res = Invoke-AdbConnect
        if ($res.Success) {
            $script:notifyIcon.Icon = $iconGreen
            $script:notifyIcon.Text = "Connected: $($res.Name)"
            Show-Toast -Title "ADB Connected" -Message "Successfully connected to $($res.Name)"
        } else {
            $script:notifyIcon.Icon = $iconRed
            $script:notifyIcon.Text = "Disconnected"
            Show-Toast -Title "Connection Failed" -Message $res.Message
        }
    })

    $miAuto = $fallbackMenu.Items.Add("Auto-Connect on Hotspot")
    $miAuto.Checked = Get-AutoConnectStatus
    $miAuto.CheckOnClick = $true
    $miAuto.Add_Click({
        Set-AutoConnectStatus -Enable (-not (Get-AutoConnectStatus))
        $miAuto.Checked = Get-AutoConnectStatus
        Show-Toast -Title "Auto-Connect" -Message $(if ($miAuto.Checked) { "Enabled - will connect when PC joins phone hotspot." } else { "Disabled." })
    })

    $miExit = $fallbackMenu.Items.Add("Exit Engine")
    $miExit.Add_Click({
        $script:notifyIcon.Visible = $false
        $script:notifyIcon.Dispose()
        [System.Windows.Forms.Application]::Exit()
    })

    $script:notifyIcon.ContextMenuStrip = $fallbackMenu
    [System.Windows.Forms.Application]::Run()
    exit
}

$global:CurrentTheme = "DarkTheme"

Set-AppTheme (Get-SystemTheme)

$script:txtStatus = $script:wpfWindow.FindName("txtStatus")
$script:txtQAAuto = $script:wpfWindow.FindName("txtQAAuto")

$script:lbFiles = $script:wpfWindow.FindName("lbFiles")


$script:txtSearch = $script:wpfWindow.FindName("txtSearch")
$script:txtSearch.Add_GotFocus({
    if ($script:txtSearch.Text -eq "Search files...") {
        $script:txtSearch.Text = ""
        $script:txtSearch.Foreground = $script:wpfWindow.FindResource("PrimaryTextBrush")
    }
})
$script:txtSearch.Add_LostFocus({
    if ([string]::IsNullOrWhiteSpace($script:txtSearch.Text)) {
        $script:txtSearch.Text = "Search files..."
        $script:txtSearch.Foreground = $script:wpfWindow.FindResource("SecondaryTextBrush")
    }
})
$script:searchTimer = New-Object System.Windows.Threading.DispatcherTimer
$script:searchTimer.Interval = [TimeSpan]::FromMilliseconds(150)
$script:searchTimer.Add_Tick({
    $script:searchTimer.Stop()
    $query = $script:txtSearch.Text.ToLower()
    if ($query -eq "search files...") { $query = "" }
    foreach ($item in $script:lbFiles.Items) {
        $name = if ($item.Content -and $item.Content.Name) { $item.Content.Name.ToLower() } else { "" }
        if ([string]::IsNullOrWhiteSpace($query) -or $name.Contains($query)) {
            $item.Visibility = 'Visible'
        } else {
            $item.Visibility = 'Collapsed'
        }
    }
})

$script:txtSearch.Add_TextChanged({
    if ($null -ne $script:searchTimer) {
        $script:searchTimer.Stop()
        $script:searchTimer.Start()
    }
})

$script:btnUpDir = $script:wpfWindow.FindName("btnUpDir")
$script:currentTarget = ""
$script:currentDirPath = "/sdcard/"
$script:adbLsProc = $null

$script:isLoadingDir = $false


$script:btnUpDir.Add_Click({
    $curr = $script:currentDirPath
    if ($curr -ne "/sdcard/" -and $curr.Length -gt 1) {
        $trimmed = $curr.TrimEnd('/')
        $lastSlash = $trimmed.LastIndexOf('/')
        if ($lastSlash -ge 0) {
            $newDir = $trimmed.Substring(0, $lastSlash + 1)
            Load-Directory $newDir
        }
    }
})

$script:customDownloadPath = ""
$script:dockTimer = $null


$btnChange = $script:wpfWindow.FindName("btnChangeDownloadPath")
if ($null -ne $btnChange) {
    $btnChange.Add_Click({
        Add-Type -AssemblyName System.Windows.Forms
        $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
        $dialog.Description = "Select Download Destination Directory"
        if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            $script:customDownloadPath = $dialog.SelectedPath
            $dispName = [System.IO.Path]::GetFileName($script:customDownloadPath)
            if ([string]::IsNullOrWhiteSpace($dispName)) { $dispName = $script:customDownloadPath }
            Show-DownloadDockToast $dispName
        }
    })
}

$script:lastDoubleClickTime = 0

$script:lbFiles.Add_MouseDoubleClick({
    # Edge Case 15: Double-Click Speed Threshold Guard
    $now = [DateTime]::Now.Ticks / [TimeSpan]::TicksPerMillisecond
    if ($now - $script:lastDoubleClickTime -lt 400) { return }
    $script:lastDoubleClickTime = $now
    
    $selectedItems = $script:lbFiles.SelectedItems
    if ($null -ne $selectedItems -and $selectedItems.Count -gt 0) {
        # Check if a single folder is double clicked
        if ($selectedItems.Count -eq 1) {
            $sel = $selectedItems[0]
            if ($null -ne $sel -and $null -ne $sel.Content) {
                $data = $sel.Content
                if ($data.IsDir) {
                    Load-Directory $data.FullPath
                    return
                }
            }
        }
        
        # Batch pull all selected file items
        $fileItems = @($selectedItems | Where-Object { $null -ne $_.Content -and -not $_.Content.IsDir })
        if ($fileItems.Count -eq 0) { return }
        
        $outDir = if ($script:customDownloadPath) { 
            $script:customDownloadPath 
        } else { 
            Join-Path $env:USERPROFILE "Downloads\dex" 
        }
        
        try {
            if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Force -Path $outDir | Out-Null }
        } catch {
            $outDir = Join-Path $env:TEMP "dex"
            if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Force -Path $outDir | Out-Null }
        }
        
        $remotePaths = $fileItems | ForEach-Object { $_.Content.FullPath }
        
        $actionBatchBg = {
            param($exePath, $tgt, $remPaths, $out)
            foreach ($rem in $remPaths) {
                Start-Process $exePath -ArgumentList "-s $tgt pull `"$rem`" `"$out`"" -Wait -NoNewWindow
            }
            Start-Process "explorer.exe" -ArgumentList "`"$out`""
        }
        
        Start-Job -ScriptBlock $actionBatchBg -ArgumentList $global:AdbExePath, $script:currentTarget, $remotePaths, $outDir
        
        $dispName = if ($script:customDownloadPath) { 
            [System.IO.Path]::GetFileName($script:customDownloadPath) 
        } else { 
            "Downloads\dex" 
        }
        
        if ($fileItems.Count -gt 1) {
            Show-DownloadDockToast "$($fileItems.Count) files to $dispName"
        } else {
            Show-DownloadDockToast $dispName
        }
    }
})



$script:wpfWindow.FindName("btnCopyIP").Add_Click({
    if (-not [string]::IsNullOrWhiteSpace($script:currentTarget)) {
        try {
            Set-Clipboard -Value $script:currentTarget -ErrorAction Stop
            Show-Toast -Title "Copied" -Message "IP Address copied to clipboard: $($script:currentTarget)"
            
            $btnCopyIP = $script:wpfWindow.FindName("btnCopyIP")
            if ($null -ne $btnCopyIP) {
                $tb = $btnCopyIP.Content
                if ($tb -is [System.Windows.Controls.TextBlock]) {
                    $tb.Text = [char]0x2713
                    $tb.Foreground = $script:wpfWindow.FindResource("SecondaryBrush")
                    
                    $timer = New-Object System.Windows.Threading.DispatcherTimer
                    $timer.Interval = [TimeSpan]::FromSeconds(1.5)
                    $timer.Add_Tick({
                        $tb.Text = [char]0xE8C8
                        $tb.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, "SecondaryTextBrush")
                        $timer.Stop()
                    })
                    $timer.Start()
                }
            }
        } catch {
            Show-Toast -Title "Clipboard Error" -Message "Could not copy IP. Your clipboard is locked by another app."
        }
    }
})

$actionConnect = {
    $res = Invoke-AdbConnect
    if ($res.Success) {
        $script:currentTarget = $res.Target
        $script:notifyIcon.Icon = $iconGreen
        $script:notifyIcon.Text = "Connected: $($res.Name)"
        $script:txtStatus.Text = "Connected: $($res.Name)"
        Show-Toast -Title "ADB Connected" -Message "Successfully connected to $($res.Name)"
    } else {
        $script:notifyIcon.Icon = $iconRed
        $script:notifyIcon.Text = "Disconnected"
        $script:txtStatus.Text = "Status: $($res.Message)"
        Show-Toast -Title "Connection Failed" -Message $res.Message
    }
    Update-WpfUI
}
$script:wpfWindow.FindName("btnQAConnect").Add_Click({ Invoke-MenuAction $actionConnect })

$actionDisconnect = {
    $null = adb disconnect 2>&1
    $script:notifyIcon.Icon = $iconRed
    $script:notifyIcon.Text = "Connect ADB: Disconnected"
    $script:txtStatus.Text = "Status: Disconnected"
    Show-Toast -Title "ADB Disconnected" -Message "Severed all wireless connections."
    Update-WpfUI
}
$script:wpfWindow.FindName("btnQADisconnect").Add_Click({ Invoke-MenuAction $actionDisconnect })

$actionMirror = {
    $statusText = $script:txtStatus.Text
    $target = $null
    
    if ($statusText -match "Connected:\s*(.+)") {
        $target = $Matches[1]
    } else {
        $devicesOutput = adb devices 2>&1
        $connectedDevice = ($devicesOutput | Where-Object { $_ -match ':5555\s+device' })
        if (-not $connectedDevice) { $connectedDevice = ($devicesOutput | Where-Object { $_ -match '\bdevice\b' -and $_ -notmatch 'List of devices' }) }
        $connectedDevice = $connectedDevice | Select-Object -First 1
        if ($connectedDevice) {
            $target = $connectedDevice.Split()[0].Trim()
        }
    }
    
    if (-not $target) {
        Show-Toast -Title "Mirror Failed" -Message "No phone connected over ADB."
        Update-WpfUI
        return
    }
    
    $scrcpyExe = Get-Command scrcpy.exe -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source
    if (-not $scrcpyExe -and (Test-Path "$PSScriptRoot\scrcpy.exe")) {
        $scrcpyExe = "$PSScriptRoot\scrcpy.exe"
    }
    
    if ($scrcpyExe) {
        Show-Toast -Title "Mirroring Phone" -Message "Launching zero-latency screen mirror for $target..."
        Start-Process -FilePath $scrcpyExe -ArgumentList "-s `"$target`" --window-title `"Connect Phone ADB - Screen Mirror ($target)`"" -WindowStyle Normal
    } else {
        Show-Toast -Title "Mirroring Requires scrcpy" -Message "scrcpy.exe not found in PATH or app directory. Place scrcpy.exe in PATH to mirror."
    }
    Update-WpfUI
}
$script:wpfWindow.FindName("btnQAMirror").Add_Click({ Invoke-MenuAction $actionMirror })

$actionPull = {
    $statusText = $script:txtStatus.Text
    $target = $null
    
    if ($statusText -match "Connected:\s*(.+)") {
        $target = $Matches[1]
    } else {
        $devicesOutput = adb devices 2>&1
        $connectedDevice = ($devicesOutput | Where-Object { $_ -match ':5555\s+device' })
        if (-not $connectedDevice) { $connectedDevice = ($devicesOutput | Where-Object { $_ -match '\bdevice\b' -and $_ -notmatch 'List of devices' }) }
        $connectedDevice = $connectedDevice | Select-Object -First 1
        if ($connectedDevice) {
            $target = $connectedDevice.Split()[0].Trim()
        }
    }
    
    if (-not $target) {
        & $actionConnect
        $target = $script:currentTarget
        
        if (-not $target) {
            return
        }
    }
    
    $script:currentTarget = $target
    
    if ($script:wpfWindow.FindName("FileExplorer").Visibility -eq 'Visible') {
        $sb = $script:wpfWindow.Resources["ContractMenu"]
        $sb.Begin($script:wpfWindow)
        return
    }
    
    $mainBorder = $script:wpfWindow.FindName("mainBorder")
    if ([double]::IsNaN($mainBorder.Width)) { $mainBorder.Width = $mainBorder.ActualWidth }
    if ([double]::IsNaN($mainBorder.Height)) { $mainBorder.Height = $mainBorder.ActualHeight }
    
    $sb = $script:wpfWindow.Resources["ExpandMenu"]
    $sb.Begin($script:wpfWindow)
    
    $script:wpfWindow.Dispatcher.Invoke([Action]{ Load-Directory "/sdcard/" })
}
$script:wpfWindow.FindName("btnQAPull").Add_Click({ Invoke-MenuAction $actionPull })

$actionAuto = {
    $newState = -not (Get-AutoConnectStatus)
    Set-AutoConnectStatus -Enable $newState
    if ($newState) {
        Show-Toast -Title "Auto-Connect Enabled" -Message "Will auto-connect whenever PC joins phone hotspot."
    } else {
        Show-Toast -Title "Auto-Connect Disabled" -Message "Auto-connection trigger removed."
    }
    Update-WpfUI
}
$script:wpfWindow.FindName("btnQAAuto").Add_Click({ Invoke-MenuAction $actionAuto })

$script:wpfWindow.FindName("btnUserJoe").Add_Click({
    $btn = $script:wpfWindow.FindName("btnUserJoe")
    $btn.ContextMenu.PlacementTarget = $btn
    $btn.ContextMenu.IsOpen = $true
})

$script:wpfWindow.FindName("menuItemTheme").Add_Click({
    if ($global:CurrentTheme -eq "DarkTheme") {
        Set-AppTheme "LightTheme"
    } else {
        Set-AppTheme "DarkTheme"
    }
})

$btnTopProfile = $script:wpfWindow.FindName("btnProfileTop")
if ($null -ne $btnTopProfile) {
    $btnTopProfile.Add_Click({
        $joeBtn = $script:wpfWindow.FindName("btnUserJoe")
        if ($null -ne $joeBtn -and $null -ne $joeBtn.ContextMenu) {
            $joeBtn.ContextMenu.PlacementTarget = $btnTopProfile
            $joeBtn.ContextMenu.IsOpen = $true
        }
    })
}

# Edge Case 11 & 14: lbFiles KeyDown for Ctrl+A (visible only), Escape deselect, and Enter key execution
$script:lbFiles.Add_KeyDown({
    param($sender, $e)
    if ($e.Key -eq [System.Windows.Input.Key]::A -and ($e.KeyboardDevice.Modifiers -band [System.Windows.Input.ModifierKeys]::Control)) {
        foreach ($item in $script:lbFiles.Items) {
            if ($item.Visibility -eq 'Visible') {
                $item.IsSelected = $true
            } else {
                $item.IsSelected = $false
            }
        }
        $e.Handled = $true
    } elseif ($e.Key -eq [System.Windows.Input.Key]::Escape) {
        $script:lbFiles.UnselectAll()
        $e.Handled = $true
    }
})

$script:wpfWindow.FindName("btnExit").Add_Click({
    $txtExitBtn = $script:wpfWindow.FindName("txtExitBtn")
    $btnProfileBottom = $script:wpfWindow.FindName("btnProfileBottom")
    $isShift = [System.Windows.Input.Keyboard]::Modifiers -match 'Shift'
    
    if ($isShift) {
        # Proceed to exit immediately
    } elseif ($txtExitBtn.Text -eq "Exit Engine") {
        $txtExitBtn.Text = "Click to Cancel / Shift+Click to Exit"
        $btnProfileBottom.Visibility = 'Collapsed'
        
        $script:exitTimer = New-Object System.Windows.Threading.DispatcherTimer
        $script:exitTimer.Interval = [TimeSpan]::FromSeconds(3)
        $script:exitTimer.Add_Tick({
            $txtExitBtn.Text = "Exit Engine"
            $btnProfileBottom.Visibility = 'Visible'
            $script:exitTimer.Stop()
        })
        $script:exitTimer.Start()
        return
    } else {
        # Cancel the exit state
        $txtExitBtn.Text = "Exit Engine"
        $btnProfileBottom.Visibility = 'Visible'
        if ($null -ne $script:exitTimer) { $script:exitTimer.Stop() }
        return
    }
    
    if ($null -ne $script:exitTimer) { $script:exitTimer.Stop() }
    
    # Edge Case 20: Job and process cleanup on exit
    Get-Job | ForEach-Object { try { Stop-Job $_; Remove-Job $_ } catch {} }
    if ($script:adbLsProc -and -not $script:adbLsProc.HasExited) {
        try { $script:adbLsProc.Kill() } catch {}
    }
    
    $script:wpfWindow.Hide()
    $script:notifyIcon.Visible = $false
    $script:notifyIcon.Dispose()
    Stop-Process -Name "adb", "scrcpy" -ErrorAction SilentlyContinue
    [System.Windows.Forms.Application]::Exit()
})

$script:wpfWindow.Add_KeyDown({
    param($sender, $e)
    # Don't intercept keys when typing in the search bar or any text box
    $isInputFocused = ($null -ne $script:txtSearch) -and (
        $script:txtSearch.IsKeyboardFocused -or 
        $script:txtSearch.IsKeyboardFocusWithin -or 
        $script:txtSearch.IsFocused -or 
        ($null -ne $e.OriginalSource -and $e.OriginalSource.GetType().FullName -match "TextBox")
    )
    if ($isInputFocused) {
        if ($e.Key -eq [System.Windows.Input.Key]::Escape) {
            if ($script:txtSearch.Text -and $script:txtSearch.Text -ne "Search files...") {
                $script:txtSearch.Text = ""
            } else {
                [System.Windows.Input.Keyboard]::ClearFocus()
            }
            $e.Handled = $true
        }
        return
    }
    if ($e.Key -eq [System.Windows.Input.Key]::Escape) {
        $script:wpfWindow.Hide()
        $script:lastDeactivated = [DateTime]::Now
        $script:wpfWindow.FindName("mainBorder").Width = [double]::NaN
        $script:wpfWindow.FindName("mainBorder").Height = [double]::NaN
        $script:wpfWindow.FindName("FileExplorer").Visibility = 'Collapsed'
        $script:wpfWindow.FindName("FileExplorer").Opacity = 0
        $script:wpfWindow.FindName("fileTrans").X = 150
        $script:wpfWindow.FindName("menuTrans").X = 0
        $script:wpfWindow.FindName("btnCloseMenu").Visibility = 'Collapsed'
        $script:wpfWindow.FindName("btnCloseMenu").Opacity = 0
        $script:wpfWindow.FindName("NearbyExpandPanel").Visibility = 'Collapsed'
        $script:wpfWindow.FindName("NearbyExpandPanel").Opacity = 0
        $e.Handled = $true
    } elseif (($e.Key -eq [System.Windows.Input.Key]::Up -and ($e.KeyboardDevice.Modifiers -band [System.Windows.Input.ModifierKeys]::Alt)) -or ($e.Key -eq [System.Windows.Input.Key]::Back)) {
        # Edge Case 25: Alt + Up Arrow / Backspace navigates Up Directory
        if ($script:wpfWindow.FindName("FileExplorer").Visibility -eq 'Visible' -and $null -ne $script:btnUpDir) {
            $script:btnUpDir.RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent)))
            $e.Handled = $true
        }
    } elseif ($e.Key -eq [System.Windows.Input.Key]::C) {
        if ($script:wpfWindow.FindName("btnQAConnect").Visibility -eq 'Visible') {
            Invoke-MenuAction $actionConnect
        }
        $e.Handled = $true
    } elseif ($e.Key -eq [System.Windows.Input.Key]::D) {
        if ($script:wpfWindow.FindName("btnQADisconnect").Visibility -eq 'Visible') {
            Invoke-MenuAction $actionDisconnect
        }
        $e.Handled = $true
    } elseif ($e.Key -eq [System.Windows.Input.Key]::M) {
        Invoke-MenuAction $actionMirror
        $e.Handled = $true
    } elseif ($e.Key -eq [System.Windows.Input.Key]::P) {
        Invoke-MenuAction $actionPull
        $e.Handled = $true
    } elseif ($e.Key -eq [System.Windows.Input.Key]::Q) {
        $script:wpfWindow.Hide()
        $script:notifyIcon.Visible = $false
        $script:notifyIcon.Dispose()
        Stop-Process -Name "adb", "scrcpy" -ErrorAction SilentlyContinue
        [System.Windows.Forms.Application]::Exit()
        $e.Handled = $true
    }
})


$script:lastDeactivated = [DateTime]::MinValue


# Click-outside closes menu ONLY when contracted (not expanded)
$script:wpfWindow.Add_Deactivated({
    Write-Trace "Deactivated fired! IsVisible: $($script:wpfWindow.IsVisible)"
    if ($script:wpfWindow.IsVisible) {
        # If menu is expanded, do NOT close on click-outside (use Close button instead)
        if ($script:wpfWindow.FindName("FileExplorer").Visibility -eq 'Visible') { return }
        $now = [DateTime]::Now
        Write-Trace "Deactivated - Ms since last: $(($now - $script:lastDeactivated).TotalMilliseconds)"
        if (($now - $script:lastDeactivated).TotalMilliseconds -gt 200) {
            Write-Trace "Deactivated: Hiding window"
            $script:wpfWindow.Hide()
            $script:lastDeactivated = $now
        }
    }
})

# Close button handler (only visible when expanded)
$script:wpfWindow.FindName("btnCloseMenu").Add_Click({
    $script:wpfWindow.Hide()
    $script:lastDeactivated = [DateTime]::Now
    $script:wpfWindow.FindName("mainBorder").Width = [double]::NaN
    $script:wpfWindow.FindName("mainBorder").Height = [double]::NaN
    $script:wpfWindow.FindName("FileExplorer").Visibility = 'Collapsed'
    $script:wpfWindow.FindName("FileExplorer").Opacity = 0
    $script:wpfWindow.FindName("fileTrans").X = 150
    $script:wpfWindow.FindName("menuTrans").X = 0
    $script:wpfWindow.FindName("btnCloseMenu").Visibility = 'Collapsed'
    $script:wpfWindow.FindName("btnCloseMenu").Opacity = 0
    $script:wpfWindow.FindName("NearbyExpandPanel").Visibility = 'Collapsed'
    $script:wpfWindow.FindName("NearbyExpandPanel").Opacity = 0
})

$script:notifyIcon.Add_MouseUp({
    param($sender, $e)
    Write-Trace "MouseUp fired! Button: $($e.Button)"
    if ($e.Button -eq 'Right' -or $e.Button -eq 'Left') {
        $now = [DateTime]::Now
        Write-Trace "IsVisible: $($script:wpfWindow.IsVisible) | Ms since lastDeactivated: $(($now - $script:lastDeactivated).TotalMilliseconds)"
        if ($script:wpfWindow.IsVisible -or (($now - $script:lastDeactivated).TotalMilliseconds -lt 300)) {
            Write-Trace "MouseUp: Hiding window (debounce or visible)"
            $script:wpfWindow.Hide()
            return
        }
        
        try {
            Update-WpfUI
        } catch { Write-Trace "Update-WpfUI error: $_" }
        
        # Edge Case 27 & 28: Dynamic work area bounds clipping protection & window activation focus
        $workArea = [System.Windows.SystemParameters]::WorkArea
        $winWidth = if ($script:wpfWindow.Width -gt 0 -and -not [double]::IsNaN($script:wpfWindow.Width)) { $script:wpfWindow.Width } else { 1420 }
        $winHeight = if ($script:wpfWindow.Height -gt 0 -and -not [double]::IsNaN($script:wpfWindow.Height)) { $script:wpfWindow.Height } else { 760 }
        
        $left = $workArea.Right - $winWidth - 12
        $top = $workArea.Bottom - $winHeight - 12
        
        if ($left -lt $workArea.Left) { $left = $workArea.Left + 12 }
        if ($top -lt $workArea.Top) { $top = $workArea.Top + 12 }
        
        $script:wpfWindow.Left = $left
        $script:wpfWindow.Top = $top
        $script:wpfWindow.Topmost = $true
        
        $script:lastDeactivated = [DateTime]::Now
        $script:wpfWindow.Show()
        $script:wpfWindow.Activate()
        $script:wpfWindow.Focus()
        $script:wpfWindow.Resources["PopIn"].Begin($script:wpfWindow)
    }
})
# Passive sync initial state on startup
$script:AutoConnectEnabled = Get-AutoConnectStatus
Update-WpfUI

if ($SelfTest) {
    # Headless self-diagnostics: prove the full tray-click -> window-show pipeline works end to end.
    # Used by CI (Validate Build workflow) and can be run locally: Connect-Engine.ps1 -SelfTest
    $stWindowCreated = ($null -ne $script:wpfWindow)
    $stTrayVisible = [bool]$script:notifyIcon.Visible
    $stShown = $false
    try {
        $eArgs = New-Object System.Windows.Forms.MouseEventArgs([System.Windows.Forms.MouseButtons]::Left, 1, 0, 0, 0)
        $invokeArgs = [Array]::CreateInstance([object], 1)
        $invokeArgs.SetValue($eArgs, 0)
        $script:notifyIcon.GetType().GetMethod('OnMouseUp', [System.Reflection.BindingFlags]'NonPublic,Instance').Invoke($script:notifyIcon, $invokeArgs)
        $stShown = [bool]$script:wpfWindow.IsVisible
    } catch {
        Write-Output "SELFTEST EXCEPTION: $($_.Exception.Message)"
    }
    $stOk = $stWindowCreated -and $stTrayVisible -and $stShown
    Write-Output ("SELFTEST WindowCreated={0} TrayVisible={1} WindowShownAfterTrayClick={2}" -f $stWindowCreated, $stTrayVisible, $stShown)
    if ($script:wpfWindow.IsVisible) { $script:wpfWindow.Hide() }
    $script:notifyIcon.Visible = $false
    $script:notifyIcon.Dispose()
    exit $(if ($stOk) { 0 } else { 1 })
}

# Fix MSIX Version Path Drift: Re-register the task if already enabled so the path points to the new updated folder
if ($script:AutoConnectEnabled) {
    Set-AutoConnectStatus -Enable $true
}

Show-Toast -Title "Connect ADB Active" -Message "Right-click tray icon to toggle Auto-Connect ON/OFF or Connect Now."

[System.Windows.Forms.Application]::Run()
