. "$PSScriptRoot\Modules\UIComponents.ps1"
function Reset-SpatialPanels {
    try {
        $script:wpfWindow.FindResource("ExpandMenu").Stop($script:wpfWindow)
        $script:wpfWindow.FindResource("ContractMenu").Stop($script:wpfWindow)
        $script:wpfWindow.FindResource("ExpandSettings").Stop($script:wpfWindow)
        $script:wpfWindow.FindResource("ContractSettings").Stop($script:wpfWindow)
        $script:wpfWindow.FindResource("PopIn").Stop($script:wpfWindow)
    } catch {}

    $script:wpfWindow.FindName("mainBorder").Width = [double]::NaN
    $script:wpfWindow.FindName("mainBorder").Height = [double]::NaN
    $script:wpfWindow.FindName("FileExplorer").Visibility = 'Collapsed'
    $script:wpfWindow.FindName("FileExplorer").Opacity = 0
    $script:wpfWindow.FindName("fileTrans").X = 150
    $script:wpfWindow.FindName("SettingsPanel").Visibility = 'Collapsed'
    $script:wpfWindow.FindName("SettingsPanel").Opacity = 0
    $script:wpfWindow.FindName("settingsTrans").X = 150
    $script:wpfWindow.FindName("menuTrans").X = 0
    $script:wpfWindow.FindName("btnCloseMenu").Visibility = 'Collapsed'
    $script:wpfWindow.FindName("btnCloseMenu").Opacity = 0
    $script:wpfWindow.FindName("NearbyExpandPanel").Visibility = 'Collapsed'
    $script:wpfWindow.FindName("NearbyExpandPanel").Opacity = 0
    $script:wpfWindow.FindName("TopActionsPanel").Visibility = 'Visible'
    $script:wpfWindow.FindName("btnUserJoe").Visibility = 'Visible'
    $script:wpfWindow.FindName("btnDeviceGalaxy").Visibility = 'Visible'
    $script:wpfWindow.FindName("btnDeviceWindows").Visibility = 'Visible'
    $btnQAPull = $script:wpfWindow.FindName("btnQAPull")
    if ($btnQAPull) { $btnQAPull.IsChecked = $false }
}

function Invoke-ExitEngine {
    # Edge Case 20: Job and process cleanup on exit
    Get-Job | ForEach-Object { try { Stop-Job $_; Remove-Job $_ } catch {} }
    if ($script:adbLsProc -and -not $script:adbLsProc.HasExited) {
        try { $script:adbLsProc.Kill() } catch {}
    }
    $script:wpfWindow.Hide()
    $script:notifyIcon.Visible = $false
    $script:notifyIcon.Dispose()
    Stop-Process -Name "adb", "scrcpy", "DeXShareTarget" -ErrorAction SilentlyContinue
    [System.Windows.Forms.Application]::Exit()
}

function Get-ConnectedDeviceTarget {
    $statusText = $script:txtStatus.Text
    if ($statusText -match "Connected:\s*(.+)") { return $Matches[1] }
    $devicesOutput = adb devices 2>&1
    $connectedDevice = ($devicesOutput | Where-Object { $_ -match ':5555\s+device' })
    if (-not $connectedDevice) { $connectedDevice = ($devicesOutput | Where-Object { $_ -match '\bdevice\b' -and $_ -notmatch 'List of devices' }) }
    $connectedDevice = $connectedDevice | Select-Object -First 1
    if ($connectedDevice) { return $connectedDevice.Split()[0].Trim() }
    return $null
}
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
$actionDisconnect = {
    $null = adb disconnect 2>&1
    $script:notifyIcon.Icon = $iconRed
    $script:notifyIcon.Text = "Connect ADB: Disconnected"
    $script:txtStatus.Text = "Status: Disconnected"
    Show-Toast -Title "ADB Disconnected" -Message "Severed all wireless connections."
    Update-WpfUI
}
$script:wpfWindow.FindName("btnQAConnect").Add_Click({
    if ($this.IsChecked) {
        Invoke-MenuAction $actionConnect
    } else {
        Invoke-MenuAction $actionDisconnect
    }
})

$script:wpfWindow.Add_PreviewMouseLeftButtonUp({
    param($sender, $e)
    $element = $e.OriginalSource
    while ($element -and $element -isnot [System.Windows.Controls.Button]) {
        $element = [System.Windows.Media.VisualTreeHelper]::GetParent($element)
    }
    
    if ($element -and $element -is [System.Windows.Controls.Button]) {
        # Check if the Button has an IP Tag (Omni-Mesh device)
        if ($element.Tag -and $element.Tag -match '^\d+\.\d+\.\d+\.\d+') {
            $ip = $element.Tag -replace ':.*', ''
            
            # Check Identity and Pairing status
            $trustLevel = if ($script:omniPeers[$ip]) { $script:omniPeers[$ip].TrustLevel } else { "Guest" }
            $wasPreviouslyPaired = $trustLevel -eq "Auto-Trusted"
            if ($trustLevel -eq "Guest") {
                $settingsPath = Join-Path $PSScriptRoot "..\appsettings.json"
                $tokens = @{}
                if (Test-Path $settingsPath) { try { $tokens = Get-Content $settingsPath -Raw | ConvertFrom-Json -AsHashtable } catch {} }
                
                if ($tokens[$ip]) {
                    # Previously paired — token already exists
                    $wasPreviouslyPaired = $true
                } else {
                    try {
                        [Net.ServicePointManager]::ServerCertificateValidationCallback = {$true}
                        [void](Invoke-RestMethod -Uri "https://${ip}:53317/api/dex/pair/request" -Method Post -ErrorAction Stop)
                        
                        Add-Type -AssemblyName Microsoft.VisualBasic
                        $pin = [Microsoft.VisualBasic.Interaction]::InputBox("Enter the 6-digit PIN shown on the target phone:", "DeX Guest Pairing")
                        if ($pin) {
                            $verifyRes = Invoke-RestMethod -Uri "https://${ip}:53317/api/dex/pair/verify" -Method Post -Body (@{ pin = $pin } | ConvertTo-Json -Depth 2) -ContentType "application/json" -ErrorAction Stop
                            $tokens[$ip] = $verifyRes.token
                            $tokens | ConvertTo-Json -Depth 2 | Set-Content $settingsPath
                        } else {
                            $e.Handled = $true
                            return
                        }
                    } catch {
                        Show-Toast -Title "Pairing Failed" -Message $_.Exception.Message
                        $e.Handled = $true
                        return
                    }
                }
            }


            $res = Invoke-AdbConnect -Target $ip
            if ($res.Success) {
                if ($wasPreviouslyPaired) {
                    # Trusted device — auto-expand Transfers panel
                    Invoke-MenuAction $actionPull
                } else {
                    # Just paired for the first time — toast confirmation, don't auto-expand
                    Show-Toast -Title "Paired & Connected" -Message "Successfully paired with $ip"
                    Update-WpfUI
                }
            } else {
                Show-Toast -Title "Connection Failed" -Message $res.Message
            }
            
            $e.Handled = $true
        }
    }
})

$actionMirror = {
        $target = Get-ConnectedDeviceTarget
    
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
        Start-Process -FilePath $scrcpyExe -ArgumentList "-s `"$target`" --window-title `"DeX - Screen Mirror ($target)`"" -WindowStyle Normal
    } else {
        Show-Toast -Title "Mirroring Requires scrcpy" -Message "scrcpy.exe not found in PATH or app directory. Place scrcpy.exe in PATH to mirror."
    }
    Update-WpfUI
}
$script:wpfWindow.FindName("btnQAMirror").Add_Click({ Invoke-MenuAction $actionMirror })

$actionPull = {
    
    if ($script:wpfWindow.FindName("FileExplorer").Visibility -eq 'Visible') {
        $sb = $script:wpfWindow.Resources["ContractMenu"].Clone()
        $sb.Children[0].By = $null
        $sb.Children[0].To = if ($script:contractedWidth) { $script:contractedWidth } else { 300 }
        $sb.Children[1].By = $null
        $sb.Children[1].To = if ($script:contractedHeight) { $script:contractedHeight } else { 500 }
        $sb.Begin($script:wpfWindow, $true)
        $btnQAPull = $script:wpfWindow.FindName("btnQAPull")
        if ($btnQAPull) { $btnQAPull.IsChecked = $false }
        return
    }
    
    $settingsPanel = $script:wpfWindow.FindName("SettingsPanel")
    $isSwapping = ($settingsPanel -and $settingsPanel.Visibility -eq 'Visible')
    if ($isSwapping) {
        # Swap from Settings to File Explorer: collapse settings first, then fall through
        $settingsPanel.Visibility = 'Collapsed'
        $settingsPanel.Opacity = 0
        $script:wpfWindow.FindName("settingsTrans").X = 150
    }
    
    $mainBorder = $script:wpfWindow.FindName("mainBorder")
    if (-not $script:contractedWidth) { $script:contractedWidth = $mainBorder.ActualWidth }
    if (-not $script:contractedHeight) { $script:contractedHeight = $mainBorder.ActualHeight }
    if ([double]::IsNaN($mainBorder.Width)) { $mainBorder.Width = $mainBorder.ActualWidth }
    if ([double]::IsNaN($mainBorder.Height)) { $mainBorder.Height = $mainBorder.ActualHeight }
    
    $sb = $script:wpfWindow.Resources["ExpandMenu"].Clone()
    if ($isSwapping) {
        14, 13, 12, 11, 10, 9, 8, 7 | ForEach-Object { $sb.Children.RemoveAt($_) }
    }
    $sb.Children[0].By = $null
    $sb.Children[0].To = $script:contractedWidth + 754
    $sb.Children[1].By = $null
    $sb.Children[1].To = $script:contractedHeight + 195
    $sb.Begin($script:wpfWindow, $true)
    
    $btnQAPull = $script:wpfWindow.FindName("btnQAPull")
    if ($btnQAPull) { $btnQAPull.IsChecked = $true }
    
    $outDir = if ($script:customDownloadPath) { $script:customDownloadPath } else { Join-Path $env:USERPROFILE "Downloads\dex" }
    if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Force -Path $outDir | Out-Null }
    $script:wpfWindow.Dispatcher.InvokeAsync([Action]{ Load-Directory $outDir }) | Out-Null
}
$script:wpfWindow.FindName("btnQAPull").Add_Click({ Invoke-MenuAction $actionPull })

$actionAuto = {
    $newState = -not (Get-AutoConnectStatus)
    Set-AutoConnectStatus -Enable $newState
    if ($newState) {
        Show-Toast -Title "Auto-Connect Enabled" -Message "Will auto-connect whenever PC joins phone hotspot."
        if (-not $script:mdnsJob) {
            $script:mdnsJob = Start-MdnsDiscovery -Queue $script:mdnsQueue
        }
    } else {
        Show-Toast -Title "Auto-Connect Disabled" -Message "Auto-connection trigger removed."
        if ($script:mdnsJob -and $script:mdnsJob.PowerShell) {
            $script:mdnsJob.PowerShell.Dispose()
            $script:mdnsJob = $null
        }
    }
    Update-WpfUI
}

# Settings Panel Toggle (avatar click expands/contracts settings)
$actionSettings = {
    $settingsPanel = $script:wpfWindow.FindName("SettingsPanel")
    $fileExplorer = $script:wpfWindow.FindName("FileExplorer")
    
    # If settings is already visible, contract it
    if ($settingsPanel.Visibility -eq 'Visible') {
        $sb = $script:wpfWindow.Resources["ContractSettings"].Clone()
        $sb.Children[0].By = $null
        $sb.Children[0].To = if ($script:contractedWidth) { $script:contractedWidth } else { 300 }
        $sb.Children[1].By = $null
        $sb.Children[1].To = if ($script:contractedHeight) { $script:contractedHeight } else { 500 }
        $sb.Begin($script:wpfWindow, $true)
        return
    }
    
    $fileExplorer = $script:wpfWindow.FindName("FileExplorer")
    $isSwapping = ($fileExplorer -and $fileExplorer.Visibility -eq 'Visible')
    
    # If file explorer is visible, collapse it first then fall through to expand settings
    if ($isSwapping) {
        $fileExplorer.Visibility = 'Collapsed'
        $fileExplorer.Opacity = 0
        $script:wpfWindow.FindName("fileTrans").X = 150
        $btnQAPull = $script:wpfWindow.FindName("btnQAPull")
        if ($btnQAPull) { $btnQAPull.IsChecked = $false }
    }
    
    $mainBorder = $script:wpfWindow.FindName("mainBorder")
    if (-not $script:contractedWidth) { $script:contractedWidth = $mainBorder.ActualWidth }
    if (-not $script:contractedHeight) { $script:contractedHeight = $mainBorder.ActualHeight }
    if ([double]::IsNaN($mainBorder.Width)) { $mainBorder.Width = $mainBorder.ActualWidth }
    if ([double]::IsNaN($mainBorder.Height)) { $mainBorder.Height = $mainBorder.ActualHeight }
    
    $sb = $script:wpfWindow.Resources["ExpandSettings"].Clone()
    if ($isSwapping) {
        14, 13, 12, 11, 10, 9, 8, 7 | ForEach-Object { $sb.Children.RemoveAt($_) }
    }
    $sb.Children[0].By = $null
    $sb.Children[0].To = 675
    $sb.Children[1].By = $null
    $sb.Children[1].To = $script:contractedHeight + 195
    $sb.Begin($script:wpfWindow, $true)
    

    
    # Update auto-connect badge
    $txtBadge = $script:wpfWindow.FindName("txtBadgeAutoConnect")
    $badge = $script:wpfWindow.FindName("badgeAutoConnect")
    if ($txtBadge -and $badge) {
        $isEnabled = Get-AutoConnectStatus
        $txtBadge.Text = if ($isEnabled) { "ON" } else { "OFF" }
        if ($isEnabled) {
            $badge.Background = $script:wpfWindow.FindResource("SecondaryBrush")
            $txtBadge.Foreground = $script:wpfWindow.FindResource("SecondaryForegroundBrush")
        } else {
            $badge.Background = $script:wpfWindow.FindResource("DangerBrush")
            $txtBadge.Foreground = [System.Windows.Media.Brushes]::White
        }
    }
    
    # Update download path
    $txtDlPath = $script:wpfWindow.FindName("txtSettingsDownloadPath")
    if ($txtDlPath) {
        $path = if ($script:customDownloadPath) { $script:customDownloadPath } else { "Downloads\dex" }
        $txtDlPath.Text = $path
    }
}

$btnTopProfile = $script:wpfWindow.FindName("btnProfileTop")
$btnProfileBottom = $script:wpfWindow.FindName("btnProfileBottom")
$btnProfileTopSettings = $script:wpfWindow.FindName("btnProfileTopSettings")

# Avatar clicks now open the settings panel instead of the popup
if ($btnTopProfile) { $btnTopProfile.Add_Click({ Invoke-MenuAction $actionSettings }) }
if ($btnProfileBottom) { $btnProfileBottom.Add_Click({ Invoke-MenuAction $actionSettings }) }
if ($btnProfileTopSettings) { $btnProfileTopSettings.Add_Click({ Invoke-MenuAction $actionSettings }) }

function Show-PairingPrompt {
    param([string]$IPPort)
    
    $xaml = @"
    <Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
            xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
            Title="Pair Device" Width="400" Height="220" WindowStartupLocation="CenterScreen"
            Background="{DynamicResource MenuBackgroundGradient}" Foreground="{DynamicResource PrimaryTextBrush}" 
            WindowStyle="None" Topmost="True" ResizeMode="NoResize"
            BorderBrush="{DynamicResource MenuBorderBrush}" BorderThickness="1" AllowsTransparency="True">
        <Window.Resources>
            <Style TargetType="Button">
                <Setter Property="Background" Value="{DynamicResource MenuBackgroundBrush}"/>
                <Setter Property="Foreground" Value="{DynamicResource PrimaryTextBrush}"/>
                <Setter Property="BorderBrush" Value="{DynamicResource MenuBorderBrush}"/>
                <Setter Property="Template">
                    <Setter.Value>
                        <ControlTemplate TargetType="Button">
                            <Border Background="{TemplateBinding Background}" CornerRadius="6" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="1">
                                <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                            </Border>
                        </ControlTemplate>
                    </Setter.Value>
                </Setter>
                <Style.Triggers>
                    <Trigger Property="IsMouseOver" Value="True">
                        <Setter Property="Background" Value="{DynamicResource HoverBackgroundBrush}"/>
                    </Trigger>
                </Style.Triggers>
            </Style>
        </Window.Resources>
        <Grid Margin="20">
            <Grid.RowDefinitions>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="*"/>
            </Grid.RowDefinitions>
            <TextBlock Text="Pair New Device (mDNS)" FontWeight="Bold" FontSize="18" Foreground="{DynamicResource BrandBrush}" Grid.Row="0" Margin="0,0,0,5"/>
            <TextBlock Text="IP: $IPPort" FontSize="13" Foreground="{DynamicResource SecondaryTextBrush}" Grid.Row="1" Margin="0,0,0,15"/>
            <StackPanel Grid.Row="2">
                <TextBlock Text="Enter 6-digit Wi-Fi pairing code:" FontSize="13" Margin="0,0,0,5" Foreground="{DynamicResource PrimaryTextBrush}"/>
                <TextBox x:Name="txtPin" Height="34" FontSize="18" Background="{DynamicResource MenuBackgroundBrush}" Foreground="{DynamicResource PrimaryTextBrush}" 
                         BorderThickness="1" BorderBrush="{DynamicResource MenuBorderBrush}" Padding="5,4,0,0" VerticalContentAlignment="Center" MaxLength="6"/>
            </StackPanel>
            <StackPanel Orientation="Horizontal" HorizontalAlignment="Right" Grid.Row="3" Margin="0,20,0,0">
                <Button x:Name="btnCancel" Content="Cancel" Width="90" Height="32" Margin="0,0,10,0"/>
                <Button x:Name="btnPair" Content="Pair" Width="90" Height="32" Background="{DynamicResource BrandBrush}" Foreground="White" BorderThickness="0"/>
            </StackPanel>
        </Grid>
    </Window>
"@
    
    $reader = New-Object System.Xml.XmlNodeReader ([xml]$xaml)
    $win = [System.Windows.Markup.XamlReader]::Load($reader)
    
    # Inherit theme dictionaries from main window
    foreach ($dict in $script:wpfWindow.Resources.MergedDictionaries) {
        $win.Resources.MergedDictionaries.Add($dict)
    }
    
    $txtPin = $win.FindName("txtPin")
    $btnCancel = $win.FindName("btnCancel")
    $btnPair = $win.FindName("btnPair")
    
    $resultPin = $null
    
    $btnCancel.Add_Click({
        $win.DialogResult = $false
        $win.Close()
    })
    
    $btnPair.Add_Click({
        $script:resultPin = $txtPin.Text.Trim()
        $win.DialogResult = $true
        $win.Close()
    })
    
    # Handle Drag to move
    $win.Add_MouseLeftButtonDown({ $win.DragMove() })
    
    $null = $win.ShowDialog()
    return $script:resultPin
}

$actionPushFiles = {
    try {
        Add-Type -AssemblyName PresentationFramework
        $dlg = New-Object Microsoft.Win32.OpenFileDialog
        $dlg.Multiselect = $true
        $dlg.Title = "Select files to send to Android"
        $result = $dlg.ShowDialog()
        if ($result -eq $true) {
            $targetIp = (Get-ItemProperty "HKCU:\Software\DeX" -Name "LastIp" -ErrorAction SilentlyContinue).LastIp
            if ([string]::IsNullOrEmpty($targetIp)) { $targetIp = "127.0.0.1" }
            $exePath = Join-Path $PSScriptRoot "..\DeXShareTarget.exe"
            $argsList = @("-IP", $targetIp) + $dlg.FileNames
            Start-Process $exePath -ArgumentList $argsList
        }
    } finally {
        $btn = $script:wpfWindow.FindName("btnPushFiles")
        if ($btn) { $btn.IsChecked = $false }
    }
}

$actionPushFolder = {
    try {
        Add-Type -AssemblyName System.Windows.Forms
        $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
        $dlg.Description = "Select a folder to send to Android"
        $result = $dlg.ShowDialog()
        if ($result -eq [System.Windows.Forms.DialogResult]::OK) {
            $targetIp = (Get-ItemProperty "HKCU:\Software\DeX" -Name "LastIp" -ErrorAction SilentlyContinue).LastIp
            if ([string]::IsNullOrEmpty($targetIp)) { $targetIp = "127.0.0.1" }
            $files = Get-ChildItem -Path $dlg.SelectedPath -File -Recurse | Select-Object -ExpandProperty FullName
            if ($files.Count -eq 0) { return }
            $exePath = Join-Path $PSScriptRoot "..\DeXShareTarget.exe"
            $argsList = @("-IP", $targetIp) + $files
            Start-Process $exePath -ArgumentList $argsList
        }
    } finally {
        $btn = $script:wpfWindow.FindName("btnPushFolder")
        if ($btn) { $btn.IsChecked = $false }
    }
}

$script:wpfWindow.FindName("btnPushFiles").Add_Click({ Invoke-MenuAction $actionPushFiles })
$script:wpfWindow.FindName("btnPushFolder").Add_Click({ Invoke-MenuAction $actionPushFolder })

$fileExplorerPanel = $script:wpfWindow.FindName("FileExplorer")
if ($fileExplorerPanel) {
    $fileExplorerPanel.Add_PreviewDragOver({
        $e = $args[1]
        if ($e.Data.GetDataPresent([System.Windows.DataFormats]::FileDrop)) {
            $e.Effects = [System.Windows.DragDropEffects]::Copy
        } else {
            $e.Effects = [System.Windows.DragDropEffects]::None
        }
        $e.Handled = $true
    })

    $fileExplorerPanel.Add_PreviewDrop({
        $e = $args[1]
        if ($e.Data.GetDataPresent([System.Windows.DataFormats]::FileDrop)) {
            $droppedFiles = $e.Data.GetData([System.Windows.DataFormats]::FileDrop)
            if ($droppedFiles -and $droppedFiles.Count -gt 0) {
                $targetIp = (Get-ItemProperty "HKCU:\Software\DeX" -Name "LastIp" -ErrorAction SilentlyContinue).LastIp
                if ([string]::IsNullOrEmpty($targetIp)) { $targetIp = "127.0.0.1" }
                
                $allFiles = @()
                foreach ($path in $droppedFiles) {
                    if (Test-Path $path -PathType Container) {
                        $allFiles += (Get-ChildItem -Path $path -File -Recurse | Select-Object -ExpandProperty FullName)
                    } else {
                        $allFiles += $path
                    }
                }
                
                if ($allFiles.Count -gt 0) {
                    $exePath = Join-Path $PSScriptRoot "..\DeXShareTarget.exe"
                    $argsList = @("-IP", $targetIp) + $allFiles
                    Start-Process $exePath -ArgumentList $argsList
                }
            }
        }
        $e.Handled = $true
    })
}
