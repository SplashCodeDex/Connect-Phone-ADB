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

function adb { & "$PSScriptRoot\adb.exe" @args }

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
        Add-Type -AssemblyName Microsoft.VisualBasic
        $GatewayIP = [Microsoft.VisualBasic.Interaction]::InputBox("Not on Phone Hotspot. Enter Phone IP manually (e.g. 192.168.1.15):", "Connect Phone")
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
$script:notifyIcon.Text = "Connect Phone: Initializing..."

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
        $notifier = [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier("Connect Phone")
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
                        <Border x:Name="border" Background="{TemplateBinding Background}" CornerRadius="10" Padding="{TemplateBinding Padding}" Margin="8,1">
                            <ContentPresenter HorizontalAlignment="Stretch" VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="border" Property="Background" Value="#2C2C2E"/>
                            </Trigger>
                            <Trigger Property="IsPressed" Value="True">
                                <Setter TargetName="border" Property="Background" Value="#3A3A3C"/>
                            </Trigger>
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
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border x:Name="border" Background="{TemplateBinding Background}" CornerRadius="20">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="border" Property="Background" Value="#3A3A3C"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
    </Window.Resources>
    <Border Background="Transparent" Padding="20">
        <Border Background="#1C1C1E" CornerRadius="34" BorderBrush="#333333" BorderThickness="1">
            <Border.Effect>
                <DropShadowEffect BlurRadius="25" ShadowDepth="8" Opacity="0.5" Color="Black" />
            </Border.Effect>
            <StackPanel Width="270" Margin="0,12">
                <StackPanel Orientation="Horizontal" HorizontalAlignment="Center" Margin="0,4,0,12">
                    <Button Name="btnQAConnect" Style="{StaticResource QuickActionBtn}" Margin="5,0" ToolTip="Connect">
                        <TextBlock Text="&#x1F517;" FontSize="20"/>
                    </Button>
                    <Button Name="btnQADisconnect" Style="{StaticResource QuickActionBtn}" Margin="5,0" ToolTip="Disconnect">
                        <TextBlock Text="&#x26A1;" FontSize="20"/>
                    </Button>
                    <Button Name="btnQAPull" Style="{StaticResource QuickActionBtn}" Margin="5,0" ToolTip="Pull Downloads">
                        <TextBlock Text="&#x1F4E5;" FontSize="20"/>
                    </Button>
                    <Button Name="btnQAAuto" Style="{StaticResource QuickActionBtn}" Margin="5,0" ToolTip="Toggle Auto-Connect">
                        <TextBlock Name="txtQAAuto" Text="&#x1F504;" FontSize="20"/>
                    </Button>
                </StackPanel>
                
                <Separator Background="#2C2C2E" Height="1" Margin="16,0" />
                <TextBlock Name="txtStatus" Text="Status: Initializing..." Foreground="#A0A0A0" FontSize="13" Margin="24,10,24,10" FontFamily="Segoe UI" />
                <Separator Background="#2C2C2E" Height="1" Margin="16,0" />
                
                <Button Name="btnConnect" Style="{StaticResource SpatialListItem}" Margin="0,8,0,0">
                    <Grid>
                        <TextBlock Text="Connect Phone" FontSize="15" FontFamily="Segoe UI" FontWeight="Medium" HorizontalAlignment="Left"/>
                        <TextBlock Text="⌘C" FontSize="14" Foreground="#A0A0A0" HorizontalAlignment="Right" FontFamily="Consolas"/>
                    </Grid>
                </Button>
                
                <Button Name="btnDisconnect" Style="{StaticResource SpatialListItem}" Margin="0,8,0,0">
                    <Grid>
                        <TextBlock Text="Disconnect Phone" FontSize="15" FontFamily="Segoe UI" FontWeight="Medium" HorizontalAlignment="Left"/>
                        <TextBlock Text="⌘D" FontSize="14" Foreground="#A0A0A0" HorizontalAlignment="Right" FontFamily="Consolas"/>
                    </Grid>
                </Button>
                
                <Button Name="btnPull" Style="{StaticResource SpatialListItem}" Margin="0,8,0,0">
                    <Grid>
                        <TextBlock Text="Pull Downloads" FontSize="15" FontFamily="Segoe UI" FontWeight="Medium" HorizontalAlignment="Left"/>
                        <TextBlock Text="⌘P" FontSize="14" Foreground="#A0A0A0" HorizontalAlignment="Right" FontFamily="Consolas"/>
                    </Grid>
                </Button>
                
                <Separator Background="#2C2C2E" Height="1" Margin="16,8" />
                
                <Button Name="btnExit" Style="{StaticResource SpatialListItem}" Margin="0,0,0,4">
                    <Grid>
                        <TextBlock Text="Exit Engine" FontSize="15" FontFamily="Segoe UI" FontWeight="Medium" Foreground="#FF453A" HorizontalAlignment="Left"/>
                        <TextBlock Text="⌘Q &#x1F5D1;" FontSize="14" Foreground="#FF453A" HorizontalAlignment="Right" FontFamily="Consolas"/>
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
    } else {
        $script:wpfWindow.FindName("btnConnect").Visibility = 'Visible'
        $script:wpfWindow.FindName("btnDisconnect").Visibility = 'Collapsed'
        $script:wpfWindow.FindName("btnQAConnect").Visibility = 'Visible'
        $script:wpfWindow.FindName("btnQADisconnect").Visibility = 'Collapsed'
    }
}

$script:wpfWindow.Add_Deactivated({
    $script:wpfWindow.Hide()
})

function Invoke-MenuAction([scriptblock]$Action) {
    $script:wpfWindow.Hide()
    & $Action
}

$actionConnect = {
    $res = Invoke-AdbConnect
    if ($res.Success) {
        $script:notifyIcon.Icon = $iconGreen
        $script:notifyIcon.Text = "Connected: $($res.Target)"
        $script:txtStatus.Text = "Connected: $($res.Target)"
        Show-Toast -Title "Phone Connected" -Message "Successfully connected to $($res.Target)"
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
    $null = adb disconnect 2>&1
    $script:notifyIcon.Icon = $iconRed
    $script:notifyIcon.Text = "Connect Phone: Disconnected"
    $script:txtStatus.Text = "Status: Disconnected"
    Show-Toast -Title "Phone Disconnected" -Message "Severed all wireless connections."
}
$script:wpfWindow.FindName("btnDisconnect").Add_Click({ Invoke-MenuAction $actionDisconnect })
$script:wpfWindow.FindName("btnQADisconnect").Add_Click({ Invoke-MenuAction $actionDisconnect })

$actionPull = {
    $outDir = Join-Path $env:USERPROFILE "Downloads\Phone_ADB"
    if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir | Out-Null }
    
    $files = adb shell ls -1 "/sdcard/Download" 2>&1 | Where-Object { $_ -match '\S' } | ForEach-Object { $_.Trim() }
    if (-not $files -or $files -match "No such file") {
        Show-Toast -Title "Pull Failed" -Message "Could not read /sdcard/Download"
        return
    }
    
    $pickerXaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        Title="Select files to pull" Width="400" Height="500" Background="#1C1C1E" WindowStartupLocation="CenterScreen">
    <Grid Margin="10">
        <Grid.RowDefinitions>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>
        <ListBox Name="lstFiles" Background="#2C2C2E" Foreground="White" SelectionMode="Extended" BorderThickness="0" Margin="0,0,0,10"/>
        <Button Name="btnPullItems" Grid.Row="1" Content="Pull Selected Files" Background="#00E676" Foreground="Black" Padding="10" BorderThickness="0" FontWeight="Bold" Cursor="Hand"/>
    </Grid>
</Window>
"@
    $pickerReader = (New-Object System.Xml.XmlNodeReader ([xml]$pickerXaml))
    $pickerWindow = [System.Windows.Markup.XamlReader]::Load($pickerReader)
    $lstFiles = $pickerWindow.FindName("lstFiles")
    
    foreach ($f in $files) { $null = $lstFiles.Items.Add($f) }
    
    $pickerWindow.FindName("btnPullItems").Add_Click({
        $selected = $lstFiles.SelectedItems
        if ($selected.Count -gt 0) {
            Show-Toast -Title "Pulling Downloads" -Message "Pulling $($selected.Count) items..."
            foreach ($item in $selected) {
                # Escape spaces for the remote shell path, but not for the local path
                $remotePath = "/sdcard/Download/$item" -replace ' ', '\ '
                $null = adb pull $remotePath $outDir 2>&1
            }
            Show-Toast -Title "Pull Complete" -Message "Saved to Downloads\Phone_ADB"
            Invoke-Item $outDir
        }
        $pickerWindow.Close()
    })
    
    $pickerWindow.ShowDialog() | Out-Null
}
$script:wpfWindow.FindName("btnPull").Add_Click({ Invoke-MenuAction $actionPull })
$script:wpfWindow.FindName("btnQAPull").Add_Click({ Invoke-MenuAction $actionPull })

$actionAuto = {
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
# Sync initial state & start
$initialRes = Invoke-AdbConnect
if ($initialRes.Success) {
    $script:notifyIcon.Icon = $iconGreen
    $script:notifyIcon.Text = "Connected: $($initialRes.Target)"
    $script:txtStatus.Text = "Connected: $($initialRes.Target)"
} else {
    $script:notifyIcon.Icon = $iconRed
    $script:notifyIcon.Text = "Connect Phone: Disconnected"
    $script:txtStatus.Text = "Status: Disconnected"
}

Show-Toast -Title "Connect Phone Active" -Message "Right-click tray icon to toggle Auto-Connect ON/OFF or Connect Now."

[System.Windows.Forms.Application]::Run()
