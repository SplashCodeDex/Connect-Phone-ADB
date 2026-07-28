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


$script:wpfWindow.FindName("btnPopTheme").Add_Click({
    if ($global:CurrentTheme -eq "DarkTheme") {
        Set-AppTheme "LightTheme"
    } else {
        Set-AppTheme "DarkTheme"
    }
})

$popAvatar = $script:wpfWindow.FindName("popAvatar")
$btnTopProfile = $script:wpfWindow.FindName("btnProfileTop")
$btnProfileBottom = $script:wpfWindow.FindName("btnProfileBottom")
if ($btnTopProfile) { $btnTopProfile.Add_Click({ $popAvatar.IsOpen = $true }) }
if ($btnProfileBottom) { $btnProfileBottom.Add_Click({ $popAvatar.IsOpen = $true }) }



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
        Invoke-MenuAction $actionConnect
        $e.Handled = $true
    } elseif ($e.Key -eq [System.Windows.Input.Key]::D) {
        Invoke-MenuAction $actionDisconnect
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
        
        $script:wpfWindow.Dispatcher.BeginInvoke([System.Windows.Threading.DispatcherPriority]::ApplicationIdle, [Action]{
            $script:lastDeactivated = [DateTime]::Now
            $script:wpfWindow.Show()
            $script:wpfWindow.Activate()
            $script:wpfWindow.Focus()
            $script:wpfWindow.Resources["PopIn"].Begin($script:wpfWindow)
        })
    }
})


function Show-PairingPrompt {
    param([string]$IPPort)
    
    $xaml = @"
    <Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
            xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
            Title="Pair Device" Width="400" Height="220" WindowStartupLocation="CenterScreen"
            Background="{DynamicResource PrimaryBackgroundGradient}" Foreground="{DynamicResource PrimaryTextBrush}" 
            WindowStyle="None" Topmost="True" ResizeMode="NoResize"
            BorderBrush="{DynamicResource BorderBrush}" BorderThickness="1" AllowsTransparency="True">
        <Window.Resources>
            <Style TargetType="Button">
                <Setter Property="Background" Value="{DynamicResource SecondaryBackgroundBrush}"/>
                <Setter Property="Foreground" Value="{DynamicResource PrimaryTextBrush}"/>
                <Setter Property="BorderBrush" Value="{DynamicResource BorderBrush}"/>
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
                        <Setter Property="Background" Value="{DynamicResource TertiaryBackgroundBrush}"/>
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
            <TextBlock Text="Pair New Device (mDNS)" FontWeight="Bold" FontSize="18" Foreground="{DynamicResource PrimaryBrush}" Grid.Row="0" Margin="0,0,0,5"/>
            <TextBlock Text="IP: $IPPort" FontSize="13" Foreground="{DynamicResource SecondaryTextBrush}" Grid.Row="1" Margin="0,0,0,15"/>
            <StackPanel Grid.Row="2">
                <TextBlock Text="Enter 6-digit Wi-Fi pairing code:" FontSize="13" Margin="0,0,0,5" Foreground="{DynamicResource PrimaryTextBrush}"/>
                <TextBox x:Name="txtPin" Height="34" FontSize="18" Background="{DynamicResource SecondaryBackgroundBrush}" Foreground="{DynamicResource PrimaryTextBrush}" 
                         BorderThickness="1" BorderBrush="{DynamicResource BorderBrush}" Padding="5,4,0,0" VerticalContentAlignment="Center" MaxLength="6"/>
            </StackPanel>
            <StackPanel Orientation="Horizontal" HorizontalAlignment="Right" Grid.Row="3" Margin="0,20,0,0">
                <Button x:Name="btnCancel" Content="Cancel" Width="90" Height="32" Margin="0,0,10,0"/>
                <Button x:Name="btnPair" Content="Pair" Width="90" Height="32" Background="{DynamicResource PrimaryBrush}" Foreground="White" BorderThickness="0"/>
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
