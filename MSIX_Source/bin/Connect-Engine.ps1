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
    function adb { ConnectPhone-adb.exe @args }
} else {
    function adb { & "$PSScriptRoot\adb.exe" @args }
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
    } catch {
        # Fallback to legacy balloon tip
        $script:notifyIcon.BalloonTipTitle = $Title
        $script:notifyIcon.BalloonTipText = $Message
        $script:notifyIcon.BalloonTipIcon = [System.Windows.Forms.ToolTipIcon]::Info
        $script:notifyIcon.ShowBalloonTip(4000)
    }
}

# Spatial UI WPF Overlay
$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        WindowStyle="None" AllowsTransparency="True" Background="Transparent"
        Topmost="True" ShowInTaskbar="False" SizeToContent="WidthAndHeight"
        ResizeMode="NoResize">
    <Window.Resources>
        <Style x:Key="SpatialListItem" TargetType="Button">
            <Setter Property="Background" Value="Transparent"/>
            <Setter Property="Foreground" Value="White"/>
            <Setter Property="BorderThickness" Value="0"/>
            <Setter Property="Padding" Value="16,10"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border x:Name="border" Background="{TemplateBinding Background}" CornerRadius="10" Padding="{TemplateBinding Padding}" Margin="8,1" RenderTransformOrigin="0.5,0.5">
                            <Border.RenderTransform>
                                <ScaleTransform ScaleX="1" ScaleY="1" x:Name="btnScale" />
                            </Border.RenderTransform>
                            <ContentPresenter HorizontalAlignment="Stretch" VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="border" Property="Background" Value="#2C2C2E"/>
                            </Trigger>
                            <Trigger Property="IsPressed" Value="True">
                                <Setter TargetName="border" Property="Background" Value="#3A3A3C"/>
                            </Trigger>
                            <EventTrigger RoutedEvent="PreviewMouseDown">
                                <BeginStoryboard>
                                    <Storyboard>
                                        <DoubleAnimation Storyboard.TargetName="btnScale" Storyboard.TargetProperty="ScaleX" To="0.97" Duration="0:0:0.05" />
                                        <DoubleAnimation Storyboard.TargetName="btnScale" Storyboard.TargetProperty="ScaleY" To="0.97" Duration="0:0:0.05" />
                                    </Storyboard>
                                </BeginStoryboard>
                            </EventTrigger>
                            <EventTrigger RoutedEvent="PreviewMouseUp">
                                <BeginStoryboard>
                                    <Storyboard>
                                        <DoubleAnimation Storyboard.TargetName="btnScale" Storyboard.TargetProperty="ScaleX" To="1.0" Duration="0:0:0.1" />
                                        <DoubleAnimation Storyboard.TargetName="btnScale" Storyboard.TargetProperty="ScaleY" To="1.0" Duration="0:0:0.1" />
                                    </Storyboard>
                                </BeginStoryboard>
                            </EventTrigger>
                            <EventTrigger RoutedEvent="MouseLeave">
                                <BeginStoryboard>
                                    <Storyboard>
                                        <DoubleAnimation Storyboard.TargetName="btnScale" Storyboard.TargetProperty="ScaleX" To="1.0" Duration="0:0:0.1" />
                                        <DoubleAnimation Storyboard.TargetName="btnScale" Storyboard.TargetProperty="ScaleY" To="1.0" Duration="0:0:0.1" />
                                    </Storyboard>
                                </BeginStoryboard>
                            </EventTrigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
        <Style x:Key="QuickActionBtn" TargetType="Button">
            <Setter Property="Background" Value="#2C2C2E"/>
            <Setter Property="Foreground" Value="White"/>
            <Setter Property="BorderThickness" Value="0"/>
            <Setter Property="Width" Value="52"/>
            <Setter Property="Height" Value="52"/>
            <Setter Property="FontFamily" Value="Segoe Fluent Icons, Segoe MDL2 Assets"/>
            <Setter Property="FontSize" Value="20"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border x:Name="border" Background="{TemplateBinding Background}" CornerRadius="20" RenderTransformOrigin="0.5,0.5">
                            <Border.RenderTransform>
                                <ScaleTransform ScaleX="1" ScaleY="1" x:Name="btnScale" />
                            </Border.RenderTransform>
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="border" Property="Background" Value="#3A3A3C"/>
                            </Trigger>
                            <EventTrigger RoutedEvent="PreviewMouseDown">
                                <BeginStoryboard>
                                    <Storyboard>
                                        <DoubleAnimation Storyboard.TargetName="btnScale" Storyboard.TargetProperty="ScaleX" To="0.85" Duration="0:0:0.05" />
                                        <DoubleAnimation Storyboard.TargetName="btnScale" Storyboard.TargetProperty="ScaleY" To="0.85" Duration="0:0:0.05" />
                                    </Storyboard>
                                </BeginStoryboard>
                            </EventTrigger>
                            <EventTrigger RoutedEvent="PreviewMouseUp">
                                <BeginStoryboard>
                                    <Storyboard>
                                        <DoubleAnimation Storyboard.TargetName="btnScale" Storyboard.TargetProperty="ScaleX" To="1.0" Duration="0:0:0.1" />
                                        <DoubleAnimation Storyboard.TargetName="btnScale" Storyboard.TargetProperty="ScaleY" To="1.0" Duration="0:0:0.1" />
                                    </Storyboard>
                                </BeginStoryboard>
                            </EventTrigger>
                            <EventTrigger RoutedEvent="MouseLeave">
                                <BeginStoryboard>
                                    <Storyboard>
                                        <DoubleAnimation Storyboard.TargetName="btnScale" Storyboard.TargetProperty="ScaleX" To="1.0" Duration="0:0:0.1" />
                                        <DoubleAnimation Storyboard.TargetName="btnScale" Storyboard.TargetProperty="ScaleY" To="1.0" Duration="0:0:0.1" />
                                    </Storyboard>
                                </BeginStoryboard>
                            </EventTrigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
    </Window.Resources>
    <Border Background="Transparent" Padding="0">
        <Border Background="#1C1C1E" CornerRadius="34" BorderBrush="#333333" BorderThickness="1">
            <StackPanel Width="270" Margin="0,12">
                <StackPanel Orientation="Horizontal" HorizontalAlignment="Center" Margin="0,4,0,12">
                    <Button Name="btnQAConnect" Style="{StaticResource QuickActionBtn}" Margin="5,0" ToolTip="Connect ADB">
                        <TextBlock Text="&#xE71B;" />
                    </Button>
                    <Button Name="btnQADisconnect" Style="{StaticResource QuickActionBtn}" Margin="5,0" ToolTip="Disconnect">
                        <TextBlock Text="&#xE7E8;" />
                    </Button>
                    <Button Name="btnQAPull" Style="{StaticResource QuickActionBtn}" Margin="5,0" ToolTip="Phone Files">
                        <TextBlock Text="&#xE896;" />
                    </Button>
                    <Button Name="btnQAAuto" Style="{StaticResource QuickActionBtn}" Margin="5,0" ToolTip="Toggle Auto-Connect">
                        <TextBlock Name="txtQAAuto" Text="&#xE895;" />
                    </Button>
                </StackPanel>
                
                <Separator Background="#2C2C2E" Height="1" Margin="16,0" />
                <StackPanel Orientation="Horizontal" Margin="24,10,24,10">
                    <TextBlock Name="txtStatus" Text="Status: Initializing..." Foreground="#A0A0A0" FontSize="13" FontFamily="Segoe UI" VerticalAlignment="Center" />
                    <Button Name="btnCopyIP" Background="Transparent" BorderThickness="0" Foreground="#A0A0A0" FontFamily="Segoe Fluent Icons, Segoe MDL2 Assets" FontSize="14" ToolTip="Copy IP:Port" Cursor="Hand" Visibility="Collapsed" VerticalAlignment="Center" Margin="6,0,0,0">
                        <TextBlock Text="&#xE8C8;" />
                        <Button.Template>
                            <ControlTemplate TargetType="Button">
                                <Border x:Name="border" Background="Transparent" CornerRadius="4" Padding="4">
                                    <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                                </Border>
                                <ControlTemplate.Triggers>
                                    <Trigger Property="IsMouseOver" Value="True">
                                        <Setter TargetName="border" Property="Background" Value="#3A3A3C"/>
                                        <Setter Property="Foreground" Value="White"/>
                                    </Trigger>
                                </ControlTemplate.Triggers>
                            </ControlTemplate>
                        </Button.Template>
                    </Button>
                </StackPanel>
                <Separator Background="#2C2C2E" Height="1" Margin="16,0" />
                
                <Button Name="btnConnect" Style="{StaticResource SpatialListItem}" Margin="0,8,0,0">
                    <Grid>
                        <TextBlock Text="Connect ADB" FontSize="15" FontFamily="Segoe UI" FontWeight="Medium" HorizontalAlignment="Left"/>
                        <TextBlock Text="&#x2318;C" FontSize="14" Foreground="#A0A0A0" HorizontalAlignment="Right" FontFamily="Consolas"/>
                    </Grid>
                </Button>
                
                <Button Name="btnDisconnect" Style="{StaticResource SpatialListItem}" Margin="0,8,0,0">
                    <Grid>
                        <TextBlock Text="Disconnect ADB" FontSize="15" FontFamily="Segoe UI" FontWeight="Medium" HorizontalAlignment="Left"/>
                        <TextBlock Text="&#x2318;D" FontSize="14" Foreground="#A0A0A0" HorizontalAlignment="Right" FontFamily="Consolas"/>
                    </Grid>
                </Button>
                
                <Button Name="btnPull" Style="{StaticResource SpatialListItem}" Margin="0,8,0,0">
                    <Grid>
                        <TextBlock Text="Phone Files" FontSize="15" FontFamily="Segoe UI" FontWeight="Medium" HorizontalAlignment="Left"/>
                        <TextBlock Text="&#x2318;P" FontSize="14" Foreground="#A0A0A0" HorizontalAlignment="Right" FontFamily="Consolas"/>
                    </Grid>
                </Button>
                
                <Separator Background="#2C2C2E" Height="1" Margin="16,8" />
                
                <Button Name="btnExit" Style="{StaticResource SpatialListItem}" Margin="0,0,0,4">
                    <Grid>
                        <TextBlock Text="Exit Engine" FontSize="15" FontFamily="Segoe UI" FontWeight="Medium" Foreground="#FF453A" HorizontalAlignment="Left"/>
                        <TextBlock Text="&#x2318;Q &#x1F5D1;" FontSize="14" Foreground="#FF453A" HorizontalAlignment="Right" FontFamily="Consolas"/>
                    </Grid>
                </Button>
            </StackPanel>
        </Border>
    </Border>
</Window>
"@

$reader = (New-Object System.Xml.XmlNodeReader ([xml]$xaml))
$script:wpfWindow = [System.Windows.Markup.XamlReader]::Load($reader)

$script:txtStatus = $script:wpfWindow.FindName("txtStatus")
$script:txtQAAuto = $script:wpfWindow.FindName("txtQAAuto")

function Update-WpfUI {
    $brushConverter = New-Object System.Windows.Media.BrushConverter
    if (Get-AutoConnectStatus) { 
        $script:txtQAAuto.Foreground = $brushConverter.ConvertFromString("#00E676")
    } else { 
        $script:txtQAAuto.Foreground = [System.Windows.Media.Brushes]::White
    }
    
    $devices = adb devices 2>&1
    if ($devices -match "\bdevice\b") {
        $script:wpfWindow.FindName("btnConnect").Visibility = 'Collapsed'
        $script:wpfWindow.FindName("btnDisconnect").Visibility = 'Visible'
        $script:wpfWindow.FindName("btnQAConnect").Visibility = 'Collapsed'
        $script:wpfWindow.FindName("btnQADisconnect").Visibility = 'Visible'
        $script:wpfWindow.FindName("btnCopyIP").Visibility = 'Visible'
    } else {
        $script:wpfWindow.FindName("btnConnect").Visibility = 'Visible'
        $script:wpfWindow.FindName("btnDisconnect").Visibility = 'Collapsed'
        $script:wpfWindow.FindName("btnQAConnect").Visibility = 'Visible'
        $script:wpfWindow.FindName("btnQADisconnect").Visibility = 'Collapsed'
        $script:wpfWindow.FindName("btnCopyIP").Visibility = 'Collapsed'
    }
}

$script:wpfWindow.Add_Deactivated({
    $script:wpfWindow.Hide()
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
    $script:wpfWindow.Hide()
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
}
$script:wpfWindow.FindName("btnConnect").Add_Click({ Invoke-MenuAction $actionConnect })
$script:wpfWindow.FindName("btnQAConnect").Add_Click({ Invoke-MenuAction $actionConnect })

$actionDisconnect = {
    $script:wpfWindow.Hide()
    $null = adb disconnect 2>&1
    $script:notifyIcon.Icon = $iconRed
    $script:notifyIcon.Text = "Connect ADB: Disconnected"
    $script:txtStatus.Text = "Status: Disconnected"
    Show-Toast -Title "ADB Disconnected" -Message "Severed all wireless connections."
}
$script:wpfWindow.FindName("btnDisconnect").Add_Click({ Invoke-MenuAction $actionDisconnect })
$script:wpfWindow.FindName("btnQADisconnect").Add_Click({ Invoke-MenuAction $actionDisconnect })

$actionPull = {
    $script:wpfWindow.Hide()
    
    $outDir = Join-Path $env:USERPROFILE "Downloads\Phone_ADB"
    if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir | Out-Null }
    
    $statusText = $script:txtStatus.Text
    $target = $null
    
    if ($statusText -match "Connected:\s*(.+)") {
        $target = $Matches[1]
    } else {
        $devicesOutput = adb devices 2>&1
        $connectedDevice = ($devicesOutput | Where-Object { $_ -match '\bdevice\b' -and $_ -notmatch 'List of devices' } | Select-Object -First 1)
        if ($connectedDevice) {
            $target = $connectedDevice.Split()[0].Trim()
        }
    }
    
    if (-not $target) {
        Show-Toast -Title "Pull Failed" -Message "No phone connected."
        return
    }
    
    $pickerXaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Phone Files" Width="450" Height="600" WindowStartupLocation="CenterScreen"
        WindowStyle="SingleBorderWindow" Background="#1C1C1E" Topmost="True">
    <Border Background="#1C1C1E" BorderBrush="#333333" BorderThickness="1">
        <Grid Margin="15">
            <Grid.RowDefinitions>
                <RowDefinition Height="*"/>
                <RowDefinition Height="Auto"/>
            </Grid.RowDefinitions>
            
            <TreeView Name="tvFiles" Grid.Row="0" Background="#1C1C1E" Foreground="White" BorderThickness="0" FontFamily="Segoe UI" FontSize="15" ScrollViewer.HorizontalScrollBarVisibility="Auto">
                <TreeView.Resources>
                    <Style TargetType="TreeViewItem">
                        <Setter Property="Foreground" Value="White"/>
                        <Setter Property="Background" Value="Transparent"/>
                        <Setter Property="Padding" Value="4,4"/>
                    </Style>
                </TreeView.Resources>
            </TreeView>
            
            <Button Name="btnPullItems" Grid.Row="1" Margin="0,15,0,0" Content="Pull Selected Item" Background="#00E676" Foreground="Black" BorderThickness="0" FontWeight="Bold" FontSize="15" Cursor="Hand">
                <Button.Template>
                    <ControlTemplate TargetType="Button">
                        <Border Name="border" Background="{TemplateBinding Background}" CornerRadius="12" Padding="0,14">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="border" Property="Background" Value="#33FF95"/>
                            </Trigger>
                            <Trigger Property="IsPressed" Value="True">
                                <Setter TargetName="border" Property="Background" Value="#00C853"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Button.Template>
            </Button>
        </Grid>
    </Border>
</Window>
"@
    $pickerReader = (New-Object System.Xml.XmlNodeReader ([xml]$pickerXaml))
    $pickerWindow = [System.Windows.Markup.XamlReader]::Load($pickerReader)
    $tvFiles = $pickerWindow.FindName("tvFiles")
    
    try {
        $pickerWindow.Icon = [System.Windows.Media.Imaging.BitmapFrame]::Create([System.Uri]::new("file:///$($PSScriptRoot.Replace('\','/'))/app-icon.ico"))
    } catch {}
    
    function New-TreeNode($name, $path, $isDir) {
        $node = New-Object System.Windows.Controls.TreeViewItem
        if ($isDir) {
            $node.Header = "[DIR] $name"
            $node.Tag = "DIR|$path"
            $node.Items.Add("Loading...") | Out-Null
        } else {
            $node.Header = $name
            $node.Tag = "FILE|$path"
        }
        return $node
    }

    $tvFiles.add_Expanded({
        param($sender, $e)
        $item = $e.Source
        if (-not ($item -is [System.Windows.Controls.TreeViewItem])) { return }
        
        if ($item.Items.Count -eq 1 -and $item.Items[0] -eq "Loading...") {
            $item.Items.Clear()
            
            $tagParts = $item.Tag.Split('|', 2)
            if ($tagParts[0] -ne "DIR") { return }
            $dirPath = $tagParts[1]
            
            $lsOut = adb -s $target shell ls -1aF "`"$dirPath`"" 2>&1 | Where-Object { $_ -match '\S' -and $_ -notmatch '^\.\/?$' -and $_ -notmatch '^\.\.\/?$' }
            
            if ($lsOut -match "Permission denied" -or $lsOut -match "No such file") {
                $item.Items.Add("(Access Denied)") | Out-Null
                return
            }
            
            $dirs = @()
            $files = @()
            foreach ($line in $lsOut) {
                $line = $line.Trim()
                if ($line.EndsWith('/')) {
                    $dirs += $line.TrimEnd('/')
                } else {
                    $clean = $line -replace '[@|*=]$',''
                    $files += $clean
                }
            }
            
            foreach ($d in $dirs) { $item.Items.Add((New-TreeNode $d "$dirPath$d/" $true)) | Out-Null }
            foreach ($f in $files) { $item.Items.Add((New-TreeNode $f "$dirPath$f" $false)) | Out-Null }
            
            if ($item.Items.Count -eq 0) {
                $item.Items.Add("(Empty)") | Out-Null
            }
        }
    })
    
    $rootNode = New-TreeNode "Internal Storage (/sdcard/)" "/sdcard/" $true
    $tvFiles.Items.Add($rootNode) | Out-Null
    $rootNode.IsExpanded = $true
    
    $pickerWindow.FindName("btnPullItems").Add_Click({
        $selected = $tvFiles.SelectedItem
        if ($selected -and $selected -is [System.Windows.Controls.TreeViewItem]) {
            $tagParts = $selected.Tag.Split('|', 2)
            $remotePath = $tagParts[1]
            $name = $selected.Header -replace '^\[DIR\]\s+', ''
            
            Show-Toast -Title "Pulling Data" -Message "Pulling $name in background..."
            
            $jobScript = {
                param($target, $outDir, $remotePath, $adbExe, $iconPath)
                & $adbExe -s $target pull $remotePath $outDir | Out-Null
                
                try {
                    [Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime] | Out-Null
                    [Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom, ContentType = WindowsRuntime] | Out-Null
                    $xmlString = @"
<toast><visual><binding template="ToastGeneric"><text>Pull Complete</text><text>Saved to Downloads\Phone_ADB</text><image placement="appLogoOverride" hint-crop="none" src="file:///$($iconPath -replace '\\', '/')"/></binding></visual></toast>
"@
                    $xml = New-Object Windows.Data.Xml.Dom.XmlDocument
                    $xml.LoadXml($xmlString)
                    $toast = [Windows.UI.Notifications.ToastNotification]::new($xml)
                    $notifier = [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier("Connect ADB")
                    $notifier.Show($toast)
                } catch {}
                
                Invoke-Item $outDir
            }
            if ($PSScriptRoot -match "WindowsApps") {
                $adbExe = "ConnectPhone-adb.exe"
            } else {
                $adbExe = "$PSScriptRoot\adb.exe"
            }
            Start-Job -ScriptBlock $jobScript -ArgumentList $target, $outDir, $remotePath, $adbExe, "$PSScriptRoot\app-icon.ico" | Out-Null
        }
        $pickerWindow.Close()
    })
    
    $pickerWindow.Show()
}
$script:wpfWindow.FindName("btnPull").Add_Click({ Invoke-MenuAction $actionPull })
$script:wpfWindow.FindName("btnQAPull").Add_Click({ Invoke-MenuAction $actionPull })

$actionAuto = {
    $script:wpfWindow.Hide()
    $newState = -not (Get-AutoConnectStatus)
    Set-AutoConnectStatus -Enable $newState
    if ($newState) {
        Show-Toast -Title "Auto-Connect Enabled" -Message "Will auto-connect whenever PC joins phone hotspot."
    } else {
        Show-Toast -Title "Auto-Connect Disabled" -Message "Auto-connection trigger removed."
    }
}
$script:wpfWindow.FindName("btnQAAuto").Add_Click({ Invoke-MenuAction $actionAuto })

$script:wpfWindow.FindName("btnExit").Add_Click({
    $script:wpfWindow.Hide()
    $script:notifyIcon.Visible = $false
    $script:notifyIcon.Dispose()
    [System.Windows.Forms.Application]::Exit()
})

$script:notifyIcon.Add_MouseUp({
    param($sender, $e)
    if ($e.Button -eq 'Right' -or $e.Button -eq 'Left') {
        Update-WpfUI
        $script:wpfWindow.Measure([System.Windows.Size]::new([double]::PositiveInfinity, [double]::PositiveInfinity))
        $script:wpfWindow.Left = [System.Windows.Forms.Cursor]::Position.X - $script:wpfWindow.DesiredSize.Width + 20
        $script:wpfWindow.Top = [System.Windows.Forms.Cursor]::Position.Y - $script:wpfWindow.DesiredSize.Height + 20
        
        if ($script:wpfWindow.Left -lt 0) { $script:wpfWindow.Left = 0 }
        if ($script:wpfWindow.Top -lt 0) { $script:wpfWindow.Top = 0 }
        
        $script:wpfWindow.Show()
        $script:wpfWindow.Activate()
    }
})
# Passive sync initial state on startup
$devices = adb devices 2>&1
if ($devices -match "((?:\d{1,3}\.){3}\d{1,3}:5555)\s+device") {
    $script:notifyIcon.Icon = $iconGreen
    $script:notifyIcon.Text = "Connected: $($Matches[1])"
    $script:txtStatus.Text = "Connected: $($Matches[1])"
} else {
    $script:notifyIcon.Icon = $iconRed
    $script:txtStatus.Text = "Status: Disconnected"
}

# Fix MSIX Version Path Drift: Re-register the task if already enabled so the path points to the new updated folder
if (Get-AutoConnectStatus) {
    Set-AutoConnectStatus -Enable $true
}

Show-Toast -Title "Connect ADB Active" -Message "Right-click tray icon to toggle Auto-Connect ON/OFF or Connect Now."

[System.Windows.Forms.Application]::Run()
