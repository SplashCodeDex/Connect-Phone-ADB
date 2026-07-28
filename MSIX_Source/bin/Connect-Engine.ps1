<#
.SYNOPSIS
    Connect Phone ADB - Core Engine & Tray Application
.DESCRIPTION
    Manages wireless ADB hotspot connections, provides a clean System Tray UI with Auto-Connect ON/OFF toggle,
    and handles Windows Task Scheduler integration.
#>

param(
    [switch]$Background,
    [switch]$ConnectOnly
)

$mutexName = "Global\CodeDeX_ConnectPhoneADB_Engine"
$mutex = New-Object System.Threading.Mutex($false, $mutexName)
if (-not $mutex.WaitOne(0, $false)) {
    # Another instance is already running
    exit
}

if ($PSScriptRoot -match "WindowsApps") {
    $global:AdbExePath = "ConnectPhone-adb.exe"
} else {
    $global:AdbExePath = "$PSScriptRoot\adb.exe"
}
function adb { & $global:AdbExePath @args }

# Force STA Mode Threading for Windows Forms & Tray Icons
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing



Add-Type -AssemblyName PresentationFramework

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$env:ADB_MDNS_OPENSCREEN = 1
$TaskName = "AutoConnectADB_Hotspot"
$ScriptPath = $PSCommandPath

# Function: Connect ADB to Gateway
function Invoke-AdbConnect {
    $GatewayIP = (Get-NetRoute -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue | 
                  Where-Object { $_.NextHop -ne '0.0.0.0' -and $_.NextHop -ne '::' } | 
                  Select-Object -First 1 -ExpandProperty NextHop)
    
    if (-not $GatewayIP) {
        if ($ConnectOnly) {
            $null = adb disconnect 2>&1
            return @{ Success = $false; Message = "No IP provided." }
        }
        
        Add-Type -AssemblyName Microsoft.VisualBasic
        $GatewayIP = [Microsoft.VisualBasic.Interaction]::InputBox("Not on Phone Hotspot. Enter Phone IP manually (e.g. 192.168.1.15):", "Connect ADB")
        if (-not $GatewayIP) {
            $null = adb disconnect 2>&1
            return @{ Success = $false; Message = "No IP provided." }
        }
    }
    
    $target = "${GatewayIP}:5555"
    
    # Smart Polling: Check if already connected to prevent UI freezing
    $devices = adb devices 2>&1
    if ($devices -match [regex]::Escape($target) + "\s+device") {
        return @{ Success = $true; Target = $target; IP = $GatewayIP }
    }

    # Not connected, try to connect
    $null = adb start-server 2>&1
    $result = adb connect $target 2>&1
    
    if ($result -like "*connected to*" -or (adb devices) -match [regex]::Escape($target)) {
        return @{ Success = $true; Target = $target; IP = $GatewayIP }
    } else {
        # Clear ghost target if unreachable
        $null = adb disconnect $target 2>&1
        return @{ Success = $false; Message = "Could not reach ADB daemon on $target" }
    }
}

# If called for ConnectOnly (e.g. from background Task Scheduler trigger)
if ($ConnectOnly) {
    $res = Invoke-AdbConnect
    exit
}

# Prevent multiple tray instances
$createdNew = $false
$mutex = New-Object System.Threading.Mutex($true, "ConnectPhoneADBTrayMutex", [ref]$createdNew)
if (-not $createdNew) {
    # If already running, trigger immediate connection check
    $res = Invoke-AdbConnect
    exit
}

# Check Task Scheduler Auto-Connect status
function Get-AutoConnectStatus {
    $task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    return ($task -ne $null -and $task.State -ne "Disabled")
}

function Set-AutoConnectStatus([bool]$Enable) {
    $service = New-Object -ComObject Schedule.Service
    $service.Connect()
    $folder = $service.GetFolder("\")
    
    if ($Enable) {
        $Query = @"
<QueryList>
  <Query Id="0" Path="Microsoft-Windows-WLAN-AutoConfig/Operational">
    <Select Path="Microsoft-Windows-WLAN-AutoConfig/Operational">*[System[(EventID=8001)]]</Select>
  </Query>
</QueryList>
"@
        $taskDef = $service.NewTask(0)
        $trigger = $taskDef.Triggers.Create(0)
        $trigger.Subscription = $Query
        
        $action = $taskDef.Actions.Create(0)
        $action.Path = "powershell.exe"
        $action.Arguments = "-ExecutionPolicy Bypass -NoProfile -WindowStyle Hidden -File `"$ScriptPath`" -ConnectOnly"
        
        $taskDef.Settings.ExecutionTimeLimit = "PT0S"
        $taskDef.Settings.DisallowStartIfOnBatteries = $false
        $taskDef.Settings.StopIfGoingOnBatteries = $false
        
        $folder.RegisterTaskDefinition($TaskName, $taskDef, 6, $null, $null, 3) | Out-Null
    } else {
        try {
            $folder.DeleteTask($TaskName, 0)
        } catch {}
    }
}

# Create System Tray Icon
$script:notifyIcon = New-Object System.Windows.Forms.NotifyIcon
$script:notifyIcon.Text = "Connect ADB: Initializing..."

function Create-StatusIcon([System.Drawing.Color]$Color) {
    $iconPath = Join-Path $PSScriptRoot "app-icon.ico"
    if (Test-Path $iconPath) {
        $baseIcon = [System.Drawing.Icon]::ExtractAssociatedIcon($iconPath)
        $bmp = $baseIcon.ToBitmap()
        $g = [System.Drawing.Graphics]::FromImage($bmp)
        $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        
        # Overlay a colored status indicator dot in the bottom right corner
        $brushBorder = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::Black)
        $g.FillEllipse($brushBorder, 18, 18, 12, 12)
        $brushStatus = New-Object System.Drawing.SolidBrush($Color)
        $g.FillEllipse($brushStatus, 20, 20, 8, 8)
        
        $hIcon = $bmp.GetHicon()
        $icon = [System.Drawing.Icon]::FromHandle($hIcon)
        $g.Dispose()
        $bmp.Dispose()
        $baseIcon.Dispose()
        return $icon
    } else {
        $bmp = New-Object System.Drawing.Bitmap(16, 16)
        $g = [System.Drawing.Graphics]::FromImage($bmp)
        $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $brushBg = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(25, 25, 35))
        $g.FillEllipse($brushBg, 0, 0, 15, 15)
        $brushStatus = New-Object System.Drawing.SolidBrush($Color)
        $g.FillEllipse($brushStatus, 3, 3, 10, 10)
        $hIcon = $bmp.GetHicon()
        $icon = [System.Drawing.Icon]::FromHandle($hIcon)
        $g.Dispose()
        $bmp.Dispose()
        return $icon
    }
}

$iconGreen = Create-StatusIcon ([System.Drawing.Color]::FromArgb(0, 230, 118))
$iconYellow = Create-StatusIcon ([System.Drawing.Color]::FromArgb(255, 214, 0))
$iconRed = Create-StatusIcon ([System.Drawing.Color]::FromArgb(255, 23, 68))

$script:notifyIcon.Icon = $iconYellow
$script:notifyIcon.Visible = $true

function Show-Toast {
    param([string]$Title, [string]$Message)
    try {
        [Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime] | Out-Null
        [Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom, ContentType = WindowsRuntime] | Out-Null
        $escTitle = [System.Security.SecurityElement]::Escape($Title)
        $escMsg = [System.Security.SecurityElement]::Escape($Message)
        $xmlString = @"
<toast>
  <visual>
    <binding template="ToastGeneric">
      <text>$escTitle</text>
      <text>$escMsg</text>
      <image placement="appLogoOverride" hint-crop="none" src="file:///$($PSScriptRoot -replace '\\', '/')/app-icon.ico"/>
    </binding>
  </visual>
</toast>
"@
        $xml = New-Object Windows.Data.Xml.Dom.XmlDocument
        $xml.LoadXml($xmlString)
        $toast = [Windows.UI.Notifications.ToastNotification]::new($xml)
        $notifier = [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier("Connect ADB")
        $notifier.Show($toast)
    } catch {}
}

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
            
            <!-- Show Close Button when expanded -->
            <ObjectAnimationUsingKeyFrames Storyboard.TargetName="btnCloseMenu" Storyboard.TargetProperty="Visibility">
                <DiscreteObjectKeyFrame KeyTime="0:0:0" Value="{x:Static Visibility.Visible}" />
            </ObjectAnimationUsingKeyFrames>
            <DoubleAnimation Storyboard.TargetName="btnCloseMenu" Storyboard.TargetProperty="Opacity" From="0" To="1" Duration="0:0:0.4" BeginTime="0:0:0.3" />
            
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
            
            <!-- Hide Close Button when contracting -->
            <DoubleAnimation Storyboard.TargetName="btnCloseMenu" Storyboard.TargetProperty="Opacity" To="0" Duration="0:0:0.3" />
            <ObjectAnimationUsingKeyFrames Storyboard.TargetName="btnCloseMenu" Storyboard.TargetProperty="Visibility">
                <DiscreteObjectKeyFrame KeyTime="0:0:0.4" Value="{x:Static Visibility.Collapsed}" />
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
            <Border Background="Transparent" Cursor="Hand" ToolTip="{Binding Name}" Margin="10" RenderTransformOrigin="0.5,0.5">
                <Border.RenderTransform>
                    <TransformGroup>
                        <ScaleTransform ScaleX="1" ScaleY="1" x:Name="itemScale" />
                        <TranslateTransform X="0" Y="0" x:Name="itemTrans" />
                    </TransformGroup>
                </Border.RenderTransform>
                <StackPanel Width="100" Height="100">
                    <TextBlock FontFamily="Segoe Fluent Icons, Segoe MDL2 Assets" Text="&#xE8B7;" Foreground="{DynamicResource SecondaryBrush}" FontSize="50" HorizontalAlignment="Center" Margin="0,5,0,0"/>
                    <TextBlock Text="{Binding Name}" Foreground="{DynamicResource PrimaryTextBrush}" TextAlignment="Center" TextWrapping="Wrap" MaxHeight="35" TextTrimming="CharacterEllipsis" FontSize="12" Margin="0,5,0,0"/>
                </StackPanel>
                <Border.Triggers>
                    <EventTrigger RoutedEvent="MouseEnter">
                        <BeginStoryboard>
                            <Storyboard>
                                <DoubleAnimation Storyboard.TargetName="itemScale" Storyboard.TargetProperty="ScaleX" To="1.08" Duration="0:0:0.5" EasingFunction="{StaticResource HoverEase}" />
                                <DoubleAnimation Storyboard.TargetName="itemScale" Storyboard.TargetProperty="ScaleY" To="1.08" Duration="0:0:0.5" EasingFunction="{StaticResource HoverEase}" />
                                <DoubleAnimation Storyboard.TargetName="itemTrans" Storyboard.TargetProperty="Y" To="-5" Duration="0:0:0.5" EasingFunction="{StaticResource HoverEase}" />
                            </Storyboard>
                        </BeginStoryboard>
                    </EventTrigger>
                    <EventTrigger RoutedEvent="MouseLeave">
                        <BeginStoryboard>
                            <Storyboard>
                                <DoubleAnimation Storyboard.TargetName="itemScale" Storyboard.TargetProperty="ScaleX" To="1.0" Duration="0:0:0.5" EasingFunction="{StaticResource HoverEase}" />
                                <DoubleAnimation Storyboard.TargetName="itemScale" Storyboard.TargetProperty="ScaleY" To="1.0" Duration="0:0:0.5" EasingFunction="{StaticResource HoverEase}" />
                                <DoubleAnimation Storyboard.TargetName="itemTrans" Storyboard.TargetProperty="Y" To="0" Duration="0:0:0.5" EasingFunction="{StaticResource HoverEase}" />
                            </Storyboard>
                        </BeginStoryboard>
                    </EventTrigger>
                    <EventTrigger RoutedEvent="PreviewMouseDown">
                        <BeginStoryboard>
                            <Storyboard>
                                <DoubleAnimation Storyboard.TargetName="itemScale" Storyboard.TargetProperty="ScaleX" To="0.92" Duration="0:0:0.1" />
                                <DoubleAnimation Storyboard.TargetName="itemScale" Storyboard.TargetProperty="ScaleY" To="0.92" Duration="0:0:0.1" />
                                <DoubleAnimation Storyboard.TargetName="itemTrans" Storyboard.TargetProperty="Y" To="5" Duration="0:0:0.1" />
                            </Storyboard>
                        </BeginStoryboard>
                    </EventTrigger>
                    <EventTrigger RoutedEvent="PreviewMouseUp">
                        <BeginStoryboard>
                            <Storyboard>
                                <DoubleAnimation Storyboard.TargetName="itemScale" Storyboard.TargetProperty="ScaleX" To="1.08" Duration="0:0:0.5" EasingFunction="{StaticResource HoverEase}" />
                                <DoubleAnimation Storyboard.TargetName="itemScale" Storyboard.TargetProperty="ScaleY" To="1.08" Duration="0:0:0.5" EasingFunction="{StaticResource HoverEase}" />
                                <DoubleAnimation Storyboard.TargetName="itemTrans" Storyboard.TargetProperty="Y" To="-5" Duration="0:0:0.5" EasingFunction="{StaticResource HoverEase}" />
                            </Storyboard>
                        </BeginStoryboard>
                    </EventTrigger>
                </Border.Triggers>
            </Border>
        </DataTemplate>
        <DataTemplate x:Key="FileGridTemplate">
            <Border Background="Transparent" Cursor="Hand" ToolTip="{Binding Name}" Margin="10" RenderTransformOrigin="0.5,0.5">
                <Border.RenderTransform>
                    <TransformGroup>
                        <ScaleTransform ScaleX="1" ScaleY="1" x:Name="itemScale" />
                        <TranslateTransform X="0" Y="0" x:Name="itemTrans" />
                    </TransformGroup>
                </Border.RenderTransform>
                <StackPanel Width="100" Height="100">
                    <TextBlock FontFamily="Segoe Fluent Icons, Segoe MDL2 Assets" Text="&#xE7C3;" Foreground="{DynamicResource SecondaryTextBrush}" FontSize="50" HorizontalAlignment="Center" Margin="0,5,0,0"/>
                    <TextBlock Text="{Binding Name}" Foreground="{DynamicResource PrimaryTextBrush}" TextAlignment="Center" TextWrapping="Wrap" MaxHeight="35" TextTrimming="CharacterEllipsis" FontSize="12" Margin="0,5,0,0"/>
                </StackPanel>
                <Border.Triggers>
                    <EventTrigger RoutedEvent="MouseEnter">
                        <BeginStoryboard>
                            <Storyboard>
                                <DoubleAnimation Storyboard.TargetName="itemScale" Storyboard.TargetProperty="ScaleX" To="1.08" Duration="0:0:0.5" EasingFunction="{StaticResource HoverEase}" />
                                <DoubleAnimation Storyboard.TargetName="itemScale" Storyboard.TargetProperty="ScaleY" To="1.08" Duration="0:0:0.5" EasingFunction="{StaticResource HoverEase}" />
                                <DoubleAnimation Storyboard.TargetName="itemTrans" Storyboard.TargetProperty="Y" To="-5" Duration="0:0:0.5" EasingFunction="{StaticResource HoverEase}" />
                            </Storyboard>
                        </BeginStoryboard>
                    </EventTrigger>
                    <EventTrigger RoutedEvent="MouseLeave">
                        <BeginStoryboard>
                            <Storyboard>
                                <DoubleAnimation Storyboard.TargetName="itemScale" Storyboard.TargetProperty="ScaleX" To="1.0" Duration="0:0:0.5" EasingFunction="{StaticResource HoverEase}" />
                                <DoubleAnimation Storyboard.TargetName="itemScale" Storyboard.TargetProperty="ScaleY" To="1.0" Duration="0:0:0.5" EasingFunction="{StaticResource HoverEase}" />
                                <DoubleAnimation Storyboard.TargetName="itemTrans" Storyboard.TargetProperty="Y" To="0" Duration="0:0:0.5" EasingFunction="{StaticResource HoverEase}" />
                            </Storyboard>
                        </BeginStoryboard>
                    </EventTrigger>
                    <EventTrigger RoutedEvent="PreviewMouseDown">
                        <BeginStoryboard>
                            <Storyboard>
                                <DoubleAnimation Storyboard.TargetName="itemScale" Storyboard.TargetProperty="ScaleX" To="0.92" Duration="0:0:0.1" />
                                <DoubleAnimation Storyboard.TargetName="itemScale" Storyboard.TargetProperty="ScaleY" To="0.92" Duration="0:0:0.1" />
                                <DoubleAnimation Storyboard.TargetName="itemTrans" Storyboard.TargetProperty="Y" To="5" Duration="0:0:0.1" />
                            </Storyboard>
                        </BeginStoryboard>
                    </EventTrigger>
                    <EventTrigger RoutedEvent="PreviewMouseUp">
                        <BeginStoryboard>
                            <Storyboard>
                                <DoubleAnimation Storyboard.TargetName="itemScale" Storyboard.TargetProperty="ScaleX" To="1.08" Duration="0:0:0.5" EasingFunction="{StaticResource HoverEase}" />
                                <DoubleAnimation Storyboard.TargetName="itemScale" Storyboard.TargetProperty="ScaleY" To="1.08" Duration="0:0:0.5" EasingFunction="{StaticResource HoverEase}" />
                                <DoubleAnimation Storyboard.TargetName="itemTrans" Storyboard.TargetProperty="Y" To="-5" Duration="0:0:0.5" EasingFunction="{StaticResource HoverEase}" />
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
        
        <Grid Name="FileExplorer" Grid.Column="0" Visibility="Collapsed" Opacity="0" Margin="15,25,15,15">
            <Grid.RenderTransform>
                <TranslateTransform x:Name="fileTrans" X="150" />
            </Grid.RenderTransform>
            <Grid.RowDefinitions>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="*"/>
            </Grid.RowDefinitions>
            <StackPanel Orientation="Horizontal" Margin="5,0,0,15">
                <Button Name="btnUpDir" Background="Transparent" BorderThickness="0" Foreground="{DynamicResource PrimaryTextBrush}" FontFamily="Segoe Fluent Icons, Segoe MDL2 Assets" FontSize="20" Content="&#xE72B;" Cursor="Hand" ToolTip="Up Directory" Margin="0,0,15,0" />
                <TextBlock Name="txtCurrentDir" Text="/sdcard/" FontSize="18" Foreground="{DynamicResource PrimaryTextBrush}" FontWeight="SemiBold" VerticalAlignment="Center" />
            </StackPanel>
            
            <ListBox Name="lbFiles" Grid.Row="1" Background="Transparent" BorderThickness="0" ScrollViewer.HorizontalScrollBarVisibility="Disabled" ScrollViewer.VerticalScrollBarVisibility="Auto">
                <ListBox.ItemsPanel>
                    <ItemsPanelTemplate>
                        <WrapPanel IsItemsHost="True" Orientation="Horizontal" />
                    </ItemsPanelTemplate>
                </ListBox.ItemsPanel>
            </ListBox>
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
                
                <!-- Exit Engine: docked at bottom so it never moves -->
                <StackPanel DockPanel.Dock="Bottom">
                    <Separator Background="{DynamicResource SecondaryBackgroundBrush}" Height="1" Margin="16,8" />
                    <Button Name="btnExit" Style="{StaticResource SpatialListItem}" Margin="0,0,0,4">
                        <Grid>
                            <TextBlock Text="Exit Engine" FontSize="15" FontFamily="Segoe UI" FontWeight="Medium" Foreground="{DynamicResource AccentBrush}" HorizontalAlignment="Left"/>
                            <TextBlock Text="&#x2318;Q &#x1F5D1;" FontSize="14" Foreground="{DynamicResource AccentBrush}" HorizontalAlignment="Right" FontFamily="Consolas"/>
                        </Grid>
                    </Button>
                </StackPanel>
                
                <!-- Main content fills remaining space -->
                <StackPanel>
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
                    <Button Name="btnQATheme" Style="{StaticResource QuickActionBtn}" Margin="3,0" ToolTip="Toggle Theme">
                        <TextBlock Text="&#xE793;" />
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
                
                <!-- Nearby Users Section -->
                <TextBlock Text="Nearby Users" FontSize="13" Foreground="{DynamicResource SecondaryTextBrush}" FontWeight="SemiBold" Margin="12,12,0,4" />

                <!-- User Joe (always visible when contracted) -->
                <Button x:Name="btnUserJoe" Style="{StaticResource SpatialListItem}" Margin="0,2,0,2">
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
                            <Ellipse Width="12" Height="12" Fill="{DynamicResource SecondaryBrush}" Stroke="#1D1226" StrokeThickness="2" HorizontalAlignment="Right" VerticalAlignment="Bottom" />
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
                            <Ellipse Fill="{DynamicResource PrimaryBrush}" />
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
                            <Ellipse Fill="{DynamicResource PrimaryBrush}" />
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
                                <Ellipse Width="12" Height="12" Fill="{DynamicResource SecondaryBrush}" Stroke="#1D1226" StrokeThickness="2" HorizontalAlignment="Right" VerticalAlignment="Bottom" />
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
                                <Ellipse Width="12" Height="12" Fill="#4CAF50" Stroke="#1D1226" StrokeThickness="2" HorizontalAlignment="Right" VerticalAlignment="Bottom" />
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
                                <Ellipse Width="12" Height="12" Fill="#4CAF50" Stroke="#1D1226" StrokeThickness="2" HorizontalAlignment="Right" VerticalAlignment="Bottom" />
                            </Grid>
                            
                            <StackPanel Grid.Column="1" VerticalAlignment="Center">
                                <TextBlock Text="Kwame Asante" FontSize="15" FontFamily="Segoe UI" FontWeight="Medium" Foreground="{DynamicResource PrimaryTextBrush}"/>
                                <TextBlock Text="Global · via Hotspot" FontSize="12" Foreground="{DynamicResource SecondaryTextBrush}" />
                            </StackPanel>
                        </Grid>
                    </Button>
                </StackPanel>
                
                </StackPanel>
                
                </DockPanel>
        </Border>
        </Border>
    </Grid>
    </Border>
</Window>
"@

$reader = (New-Object System.Xml.XmlNodeReader ([xml]$xaml))
$script:wpfWindow = [System.Windows.Markup.XamlReader]::Load($reader)

$global:CurrentTheme = "DarkTheme"
function Set-AppTheme {
    param([string]$ThemeName)
    $themePath = Join-Path $PSScriptRoot "..\Themes\$ThemeName.xaml"
    if (Test-Path $themePath) {
        $xmlReader = [System.Xml.XmlReader]::Create($themePath)
        $resourceDict = [System.Windows.Markup.XamlReader]::Load($xmlReader)
        $script:wpfWindow.Resources.MergedDictionaries.Clear()
        $script:wpfWindow.Resources.MergedDictionaries.Add($resourceDict)
        $xmlReader.Close()
        $global:CurrentTheme = $ThemeName
    }
}
function Get-SystemTheme {
    try {
        $regKey = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize"
        $val = Get-ItemPropertyValue -Path $regKey -Name "AppsUseLightTheme" -ErrorAction SilentlyContinue
        if ($val -eq 1) { return "LightTheme" }
    } catch {}
    return "DarkTheme"
}

Set-AppTheme (Get-SystemTheme)

$script:txtStatus = $script:wpfWindow.FindName("txtStatus")
$script:txtQAAuto = $script:wpfWindow.FindName("txtQAAuto")

$script:lbFiles = $script:wpfWindow.FindName("lbFiles")
$script:txtCurrentDir = $script:wpfWindow.FindName("txtCurrentDir")
$script:btnUpDir = $script:wpfWindow.FindName("btnUpDir")
$script:currentTarget = ""
$script:adbOutputSub = $null
$script:adbLsProc = $null

function Load-Directory($dirPath) {
    $script:txtCurrentDir.Text = $dirPath
    $script:lbFiles.Items.Clear()
    
    if ($script:adbLsProc -and -not $script:adbLsProc.HasExited) {
        try { $script:adbLsProc.Kill() } catch {}
    }
    
    $proc = New-Object System.Diagnostics.Process
    $proc.StartInfo.FileName = "adb.exe"
    $proc.StartInfo.Arguments = "-s $($script:currentTarget) shell ls -1aF `"$dirPath`""
    $proc.StartInfo.UseShellExecute = $false
    $proc.StartInfo.RedirectStandardOutput = $true
    $proc.StartInfo.CreateNoWindow = $true
    
    $action = {
        $e = $Event.SourceEventArgs
        if ($e.Data) {
            $line = $e.Data.Trim()
            if ($line -eq "./" -or $line -eq "../") { return }
            
            $isDir = $line.EndsWith("/")
            $name = $line.TrimEnd('/', '*', '@', '=')
            if ($isDir) {
                $full = $dirPath + $name + "/"
                $template = $script:wpfWindow.Resources["FolderGridTemplate"]
            } else {
                $full = $dirPath + $name
                $template = $script:wpfWindow.Resources["FileGridTemplate"]
            }
            
            $script:wpfWindow.Dispatcher.Invoke([Action]{
                $idx = $script:lbFiles.Items.Count
                
                $item = New-Object System.Windows.Controls.ListBoxItem
                $item.Content = @{ Name = $name; FullPath = $full; IsDir = $isDir }
                $item.ContentTemplate = $template
                $item.Tag = $full
                
                # Staggered Entrance Animation Setup
                $trans = New-Object System.Windows.Media.TranslateTransform
                $trans.Y = 80
                $item.RenderTransform = $trans
                $item.Opacity = 0
                
                $delay = [TimeSpan]::FromMilliseconds($idx * 35) # 35ms stagger per item
                
                $daY = New-Object System.Windows.Media.Animation.DoubleAnimation
                $daY.To = 0
                $daY.Duration = [TimeSpan]::FromSeconds(0.6)
                $daY.BeginTime = $delay
                $daY.EasingFunction = $script:wpfWindow.Resources["HoverEase"]
                
                $daOp = New-Object System.Windows.Media.Animation.DoubleAnimation
                $daOp.To = 1
                $daOp.Duration = [TimeSpan]::FromSeconds(0.4)
                $daOp.BeginTime = $delay
                
                $trans.BeginAnimation([System.Windows.Media.TranslateTransform]::YProperty, $daY)
                $item.BeginAnimation([System.Windows.Controls.ListBoxItem]::OpacityProperty, $daOp)
                
                $script:lbFiles.Items.Add($item)
            })
        }
    }
    if ($script:adbOutputSub) { Unregister-Event -SourceIdentifier $script:adbOutputSub.Name -ErrorAction SilentlyContinue }
    $script:adbOutputSub = Register-ObjectEvent -InputObject $proc -EventName OutputDataReceived -Action $action
    $proc.Start() | Out-Null
    $script:adbLsProc = $proc
    $proc.BeginOutputReadLine()
}

$script:btnUpDir.Add_Click({
    $curr = $script:txtCurrentDir.Text
    if ($curr -ne "/sdcard/" -and $curr.Length -gt 1) {
        $trimmed = $curr.TrimEnd('/')
        $lastSlash = $trimmed.LastIndexOf('/')
        if ($lastSlash -ge 0) {
            $newDir = $trimmed.Substring(0, $lastSlash + 1)
            Load-Directory $newDir
        }
    }
})

$script:lbFiles.Add_MouseDoubleClick({
    $sel = $script:lbFiles.SelectedItem
    if ($sel) {
        $data = $sel.Content
        if ($data.IsDir) {
            Load-Directory $data.FullPath
        } else {
            $remotePath = $data.FullPath
            $outDir = Join-Path $env:USERPROFILE "Downloads\Phone_ADB"
            if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Force -Path $outDir }
            
            $actionBg = {
                param($exePath, $tgt, $rem, $out)
                Start-Process $exePath -ArgumentList "-s $tgt pull `"$rem`" `"$out`"" -Wait -NoNewWindow
                Start-Process "explorer.exe" -ArgumentList "`"$out`""
            }
            
            Start-Job -ScriptBlock $actionBg -ArgumentList $global:AdbExePath, $script:currentTarget, $remotePath, $outDir
            
            $script:wpfWindow.Hide()
        }
    }
})


function Invoke-MenuAction([scriptblock]$Action) {
    & $Action
}

$script:wpfWindow.FindName("btnCopyIP").Add_Click({
    $statusText = $script:txtStatus.Text
    if ($statusText -match "Connected:\s*(.+)") {
        try {
            Set-Clipboard -Value $Matches[1] -ErrorAction Stop
            Show-Toast -Title "Copied" -Message "IP Address copied to clipboard: $($Matches[1])"
        } catch {
            Show-Toast -Title "Clipboard Error" -Message "Could not copy IP. Your clipboard is locked by another app."
        }
    }
})

$actionConnect = {
    $res = Invoke-AdbConnect
    if ($res.Success) {
        $script:notifyIcon.Icon = $iconGreen
        $script:notifyIcon.Text = "Connected: $($res.Target)"
        $script:txtStatus.Text = "Connected: $($res.Target)"
        Show-Toast -Title "ADB Connected" -Message "Successfully connected to $($res.Target)"
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
        $statusText = $script:txtStatus.Text
        if ($statusText -match "Connected:\s*(.+)") {
            $target = $Matches[1]
        }
        
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
$script:wpfWindow.FindName("btnQATheme").Add_Click({
    if ($global:CurrentTheme -eq "DarkTheme") {
        Set-AppTheme "LightTheme"
    } else {
        Set-AppTheme "DarkTheme"
    }
})


$script:wpfWindow.FindName("btnExit").Add_Click({
    $script:wpfWindow.Hide()
    $script:notifyIcon.Visible = $false
    $script:notifyIcon.Dispose()
    Stop-Process -Name "adb", "scrcpy" -ErrorAction SilentlyContinue
    [System.Windows.Forms.Application]::Exit()
})

$script:wpfWindow.Add_KeyDown({
    param($sender, $e)
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

function Update-WpfUI {
    param([string[]]$DevicesOutput)
    
    if (-not $DevicesOutput) {
        $DevicesOutput = adb devices 2>&1
    }

    $brushConverter = New-Object System.Windows.Media.BrushConverter
    $qaAutoText = $script:wpfWindow.FindName("txtQAAuto")
    if ($null -ne $qaAutoText) {
        if ($script:AutoConnectEnabled) { 
            $qaAutoText.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, "SecondaryBrush")
        } else { 
            $qaAutoText.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, "PrimaryTextBrush")
        }
    }
    
    $connectedDevice = ($DevicesOutput | Where-Object { $_ -match ':5555\s+device' })
    if (-not $connectedDevice) { $connectedDevice = ($DevicesOutput | Where-Object { $_ -match '\bdevice\b' -and $_ -notmatch 'List of devices' }) }
    $connectedDevice = $connectedDevice | Select-Object -First 1

    if ($connectedDevice) {
        $target = $connectedDevice.Split()[0].Trim()
        $script:notifyIcon.Icon = $iconGreen
        $script:notifyIcon.Text = "Connected: $target"
        $script:txtStatus.Text = "Connected: $target"
        $script:wpfWindow.FindName("btnQAConnect").Visibility = 'Collapsed'
        $script:wpfWindow.FindName("btnQADisconnect").Visibility = 'Visible'
        $script:wpfWindow.FindName("btnCopyIP").Visibility = 'Visible'
    } else {
        $script:notifyIcon.Icon = $iconRed
        $script:notifyIcon.Text = "Disconnected"
        $script:txtStatus.Text = "Status: Disconnected"
        $script:wpfWindow.FindName("btnQAConnect").Visibility = 'Visible'
        $script:wpfWindow.FindName("btnQADisconnect").Visibility = 'Collapsed'
        $script:wpfWindow.FindName("btnCopyIP").Visibility = 'Collapsed'
    }
}

$script:lastDeactivated = [DateTime]::MinValue

# Click-outside closes menu ONLY when contracted (not expanded)
$script:wpfWindow.Add_Deactivated({
    if ($script:wpfWindow.IsVisible) {
        # If menu is expanded, do NOT close on click-outside (use Close button instead)
        if ($script:wpfWindow.FindName("FileExplorer").Visibility -eq 'Visible') { return }
        $now = [DateTime]::Now
        if (($now - $script:lastDeactivated).TotalMilliseconds -gt 200) {
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
    if ($e.Button -eq 'Right' -or $e.Button -eq 'Left') {
        $now = [DateTime]::Now
        if ($script:wpfWindow.IsVisible -or (($now - $script:lastDeactivated).TotalMilliseconds -lt 300)) {
            $script:wpfWindow.Hide()
            return
        }
        
        try {
            Update-WpfUI
        } catch {}
        
        $workArea = [System.Windows.SystemParameters]::WorkArea
        $script:wpfWindow.Left = $workArea.Right  - 1420 - 12
        $script:wpfWindow.Top  = $workArea.Bottom - 760 - 12
        $script:wpfWindow.Topmost = $true
        
        $script:lastDeactivated = [DateTime]::Now
        $script:wpfWindow.Show()
        $script:wpfWindow.Activate()
        $script:wpfWindow.Resources["PopIn"].Begin($script:wpfWindow)
    }
})
# Passive sync initial state on startup
$script:AutoConnectEnabled = Get-AutoConnectStatus
Update-WpfUI

# Fix MSIX Version Path Drift: Re-register the task if already enabled so the path points to the new updated folder
if ($script:AutoConnectEnabled) {
    Set-AutoConnectStatus -Enable $true
}

Show-Toast -Title "Connect ADB Active" -Message "Right-click tray icon to toggle Auto-Connect ON/OFF or Connect Now."

[System.Windows.Forms.Application]::Run()
