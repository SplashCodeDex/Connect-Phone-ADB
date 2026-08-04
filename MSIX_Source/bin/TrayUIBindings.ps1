. "$PSScriptRoot\TrayUIHandlers.ps1"
$script:txtStatus = $script:wpfWindow.FindName("txtStatus")
$script:pnlAdbStatus = $script:wpfWindow.FindName("pnlAdbStatus")
$script:topActionsPanel = $script:wpfWindow.FindName("TopActionsPanel")
$script:txtQAAuto = $script:wpfWindow.FindName("txtQAAuto")

$script:lbFiles = $script:wpfWindow.FindName("lbFiles")


$script:txtSearch = $script:wpfWindow.FindName("txtSearch")
$script:txtSearch.Add_GotFocus({
    if ($script:txtSearch.Text -eq "Search transfers...") {
        $script:txtSearch.Text = ""
        $script:txtSearch.Foreground = $script:wpfWindow.FindResource("PrimaryTextBrush")
    }
})
$script:txtSearch.Add_LostFocus({
    if ([string]::IsNullOrWhiteSpace($script:txtSearch.Text)) {
        $script:txtSearch.Text = "Search transfers..."
        $script:txtSearch.Foreground = $script:wpfWindow.FindResource("SecondaryTextBrush")
    }
})
$script:searchTimer = New-Object System.Windows.Threading.DispatcherTimer
$script:searchTimer.Interval = [TimeSpan]::FromMilliseconds(150)
$script:searchTimer.Add_Tick({
    $script:searchTimer.Stop()
    $query = $script:txtSearch.Text.ToLower()
    if ($query -eq "search transfers...") { $query = "" }
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
$script:currentDirPath = ""
$script:adbLsProc = $null

$script:isLoadingDir = $false
$script:isShowingMenu = $false
$script:showMenuGuardTimer = $null
$script:lastMouseUpTime = [DateTime]::MinValue


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
        
        $firstPath = $fileItems[0].Content.FullPath
        if ([System.IO.Path]::IsPathRooted($firstPath) -and $firstPath -match '^[A-Za-z]:\\') {
            $dangerousExts = @('.exe','.bat','.cmd','.ps1','.vbs','.vbe','.msi','.scr','.com','.pif','.wsf')
            $missing = @()
            foreach ($item in $fileItems) {
                $fp = $item.Content.FullPath
                if (-not (Test-Path $fp)) {
                    $missing += $item
                } else {
                    $ext = [System.IO.Path]::GetExtension($fp).ToLower()
                    if ($dangerousExts -contains $ext) {
                        Start-Process explorer.exe -ArgumentList "/select,`"$fp`""
                    } else {
                        Start-Process $fp
                    }
                }
            }
            if ($missing.Count -gt 0) {
                $missing | ForEach-Object { $script:lbFiles.Items.Remove($_) }
                Show-DownloadDockToast "$($missing.Count) file(s) missing."
            }
            return
        }
        
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
            param($remPaths, $out, $ip)
            
            $wc = New-Object System.Net.WebClient
            [Net.ServicePointManager]::ServerCertificateValidationCallback = {$true}
            
            foreach ($rp in $remPaths) {
                try {
                    $fileName = [System.IO.Path]::GetFileName($rp)
                    if (-not $fileName) { $fileName = $rp.Split('/')[-1] }
                    $destPath = Join-Path $out $fileName
                    $uri = "https://${ip}:53317/api/dex/pull?path=" + [uri]::EscapeDataString($rp)
                    
                    $wc.DownloadFile($uri, $destPath)
                } catch {
                    # Silent fail on bg job
                }
            }
            if ($wc) { $wc.Dispose() }
            Start-Process "explorer.exe" -ArgumentList "`"$out`""
        }
        
        $target = Get-ConnectedDeviceTarget
        if ($target) {
            $ip = $target.Split(':')[0]
            Start-Job -ScriptBlock $actionBatchBg -ArgumentList $remotePaths, $outDir, $ip
        }
        
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

$script:wpfWindow.FindName("btnDeviceGalaxy").Add_Click({ $script:isMockMode = $true; Invoke-MenuAction $actionPull })
$script:wpfWindow.FindName("btnDeviceWindows").Add_Click({ $script:isMockMode = $true; Invoke-MenuAction $actionPull })

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
                    $tb.Foreground = $script:wpfWindow.FindResource("SuccessBrush")
                    
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

# Settings Panel Button Handlers
# Auto-Connect toggle in settings
$btnSettingsAutoConnect = $script:wpfWindow.FindName("btnSettingsAutoConnect")
if ($btnSettingsAutoConnect) {
    $btnSettingsAutoConnect.Add_Click({
        Invoke-MenuAction $actionAuto
        # Update badge after toggle
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
    })
}

# Connect Now button in settings
$btnSettingsConnectNow = $script:wpfWindow.FindName("btnSettingsConnectNow")
if ($btnSettingsConnectNow) {
    $btnSettingsConnectNow.Add_Click({
        Invoke-MenuAction $actionConnect
    })
}

# QR Code button in settings
$btnSettingsQrCode = $script:wpfWindow.FindName("btnSettingsQrCode")
if ($btnSettingsQrCode) {
    $btnSettingsQrCode.Add_Click({
        $pinCodeContent = $script:wpfWindow.FindName("pinCodeContent")
        $qrCodeContent = $script:wpfWindow.FindName("qrCodeContent")
        $txtQrBtnIcon = $script:wpfWindow.FindName("txtQrBtnIcon")
        $txtQrBtnText = $script:wpfWindow.FindName("txtQrBtnText")

        if ($qrCodeContent.Visibility -eq 'Visible') {
            $qrCodeContent.Visibility = 'Collapsed'
            $pinCodeContent.Visibility = 'Visible'
            $txtQrBtnIcon.Text = [char]0xE765
            $txtQrBtnText.Text = "QR CODE"
        } else {
            $ip = [System.Net.Dns]::GetHostAddresses([System.Net.Dns]::GetHostName()) | Where-Object { $_.AddressFamily -eq 'InterNetwork' -and -not [System.Net.IPAddress]::IsLoopback($_) } | Select-Object -First 1 -ExpandProperty IPAddressToString
            if ($ip) {
                $imgQrCode = $script:wpfWindow.FindName("imgQrCode")
                if ($imgQrCode) {
                    $bitmap = New-Object System.Windows.Media.Imaging.BitmapImage
                    $bitmap.BeginInit()
                    $bitmap.UriSource = New-Object Uri("http://127.0.0.1:53318/local/qr?ip=$ip")
                    $bitmap.CacheOption = [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad
                    $bitmap.EndInit()
                    $imgQrCode.Source = $bitmap
                }
                $pinCodeContent.Visibility = 'Collapsed'
                $qrCodeContent.Visibility = 'Visible'
                $txtQrBtnIcon.Text = [char]0xE338
                $txtQrBtnText.Text = "Request PIN"
            } else {
                Show-Toast -Title "Network Error" -Message "Could not determine local IP address."
            }
        }
    })
}

# DND toggle in settings
$script:isDndEnabled = $false
$btnSettingsDnd = $script:wpfWindow.FindName("btnSettingsDnd")
if ($btnSettingsDnd) {
    $btnSettingsDnd.Add_Click({
        $script:isDndEnabled = -not $script:isDndEnabled
        $stateStr = if ($script:isDndEnabled) { "true" } else { "false" }
        try { Invoke-RestMethod -Uri "http://127.0.0.1:53318/local/dnd?enabled=$stateStr" -Method Post } catch {}
        
        $txtBadge = $script:wpfWindow.FindName("txtBadgeDnd")
        $badge = $script:wpfWindow.FindName("badgeDnd")
        if ($txtBadge -and $badge) {
            $txtBadge.Text = if ($script:isDndEnabled) { "ON" } else { "OFF" }
            if ($script:isDndEnabled) {
                $badge.Background = $script:wpfWindow.FindResource("DangerBrush")
                $txtBadge.Foreground = [System.Windows.Media.Brushes]::White
            } else {
                $badge.Background = $script:wpfWindow.FindResource("AccentBrush")
                $txtBadge.Foreground = $script:wpfWindow.FindResource("SecondaryTextBrush")
            }
        }
    })
}

# Theme toggle in settings
$btnSettingsTheme = $script:wpfWindow.FindName("btnSettingsTheme")
if ($btnSettingsTheme) {
    $btnSettingsTheme.Add_Click({
        $global:AppThemeMode = "Manual"
        if ($global:CurrentTheme -eq "DarkTheme") {
            Set-AppTheme "LightTheme"
        } else {
            Set-AppTheme "DarkTheme"
        }
    })
}

# Wiggle Toggle button in settings
$btnSettingsWiggleToggle = $script:wpfWindow.FindName("btnSettingsWiggleToggle")
if ($btnSettingsWiggleToggle) {
    $btnSettingsWiggleToggle.Add_Click({
        $script:wiggleEnabled = -not $script:wiggleEnabled
        $txtSettingsWiggleToggle = $script:wpfWindow.FindName("txtSettingsWiggleToggle")
        if ($txtSettingsWiggleToggle) {
            $txtSettingsWiggleToggle.Text = if ($script:wiggleEnabled) { "Enabled" } else { "Disabled" }
        }
    })
}

# Download Path button in settings
$btnSettingsDownloadPath = $script:wpfWindow.FindName("btnSettingsDownloadPath")
if ($btnSettingsDownloadPath) {
    $btnSettingsDownloadPath.Add_Click({
        Add-Type -AssemblyName System.Windows.Forms
        $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
        $dialog.Description = "Select Download Destination Directory"
        if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            $script:customDownloadPath = $dialog.SelectedPath
            $txtDlPath = $script:wpfWindow.FindName("txtSettingsDownloadPath")
            if ($txtDlPath) {
                $txtDlPath.Text = $script:customDownloadPath
            }
            Show-Toast -Title "Download Location" -Message "Files will be saved to: $($script:customDownloadPath)"
        }
    })
}

# About button in settings
$btnSettingsAbout = $script:wpfWindow.FindName("btnSettingsAbout")
if ($btnSettingsAbout) {
    $btnSettingsAbout.Add_Click({
        Start-Process "https://github.com/SplashCodeDex/DeX"
        $script:wpfWindow.Hide()
    })
}

# Reset Identity & Trust button in settings
$btnSettingsResetIdentity = $script:wpfWindow.FindName("btnSettingsResetIdentity")
if ($btnSettingsResetIdentity) {
    $btnSettingsResetIdentity.Add_Click({
        Remove-Item "$env:LOCALAPPDATA\DeX\identity.json" -Force -ErrorAction SilentlyContinue
        [System.Windows.MessageBox]::Show("Trust identity reset. DeX will now restart.", "DeX", 'OK', 'Information') | Out-Null
        $script:notifyIcon.Visible = $false
        $script:notifyIcon.Dispose()
        [System.Windows.Forms.Application]::Exit()
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
        $btnExit = $script:wpfWindow.FindName("btnExit")
        $parentGrid = $btnExit.Parent
        $parentGrid.Width = $parentGrid.ActualWidth # Prevent layout popping
        
        $txtExitBtn.Text = "Cancel / Shift+Click Exit"
        
        $ease = New-Object System.Windows.Media.Animation.CubicEase; $ease.EasingMode = 'EaseOut'
        
        if ($btnProfileBottom.Visibility.ToString() -eq 'Visible') {
            $animExpand = New-Object System.Windows.Media.Animation.ThicknessAnimation
            $animExpand.To = New-Object System.Windows.Thickness(-62, 0, 0, 0)
            $animExpand.Duration = [TimeSpan]::FromSeconds(0.3)
            $animExpand.EasingFunction = $ease
            $btnExit.BeginAnimation([System.Windows.FrameworkElement]::MarginProperty, $animExpand)
            
            $btnProfileBottom.RenderTransformOrigin = New-Object System.Windows.Point(0.5, 0.5)
            $scale = New-Object System.Windows.Media.ScaleTransform
            $btnProfileBottom.RenderTransform = $scale
            $animScale = New-Object System.Windows.Media.Animation.DoubleAnimation
            $animScale.To = 0.6
            $animScale.Duration = [TimeSpan]::FromSeconds(0.3)
            $animScale.EasingFunction = $ease
            $scale.BeginAnimation([System.Windows.Media.ScaleTransform]::ScaleXProperty, $animScale)
            $scale.BeginAnimation([System.Windows.Media.ScaleTransform]::ScaleYProperty, $animScale)
        }
        
        $btnExit.Background = $script:wpfWindow.FindResource("AccentBrush")
        
        $script:exitTimer = New-Object System.Windows.Threading.DispatcherTimer
        $script:exitTimer.Interval = [TimeSpan]::FromSeconds(3)
        $script:exitTimer.Add_Tick({
            $tTxt = $script:wpfWindow.FindName("txtExitBtn")
            $tBtn = $script:wpfWindow.FindName("btnExit")
            $tAvatar = $script:wpfWindow.FindName("btnProfileBottom")
            
            $tTxt.Text = "Exit Engine"
            
            $easeOut = New-Object System.Windows.Media.Animation.CubicEase; $easeOut.EasingMode = 'EaseOut'
            $animContract = New-Object System.Windows.Media.Animation.ThicknessAnimation
            $animContract.To = New-Object System.Windows.Thickness(0)
            $animContract.Duration = [TimeSpan]::FromSeconds(0.3)
            $animContract.EasingFunction = $easeOut
            $tBtn.BeginAnimation([System.Windows.FrameworkElement]::MarginProperty, $animContract)
            
            if ($null -ne $tAvatar.RenderTransform -and $tAvatar.RenderTransform -is [System.Windows.Media.ScaleTransform]) {
                $animScaleBack = New-Object System.Windows.Media.Animation.DoubleAnimation
                $animScaleBack.To = 1.0
                $animScaleBack.Duration = [TimeSpan]::FromSeconds(0.3)
                $animScaleBack.EasingFunction = $easeOut
                $tAvatar.RenderTransform.BeginAnimation([System.Windows.Media.ScaleTransform]::ScaleXProperty, $animScaleBack)
                $tAvatar.RenderTransform.BeginAnimation([System.Windows.Media.ScaleTransform]::ScaleYProperty, $animScaleBack)
            }
            
            $tBtn.ClearValue([System.Windows.Controls.Control]::BackgroundProperty)
            $tBtn.Parent.Width = [Double]::NaN
            
            $script:exitTimer.Stop()
        })
        $script:exitTimer.Start()
        return
    } else {
        # Cancel the exit state
        $txtExitBtn.Text = "Exit Engine"
        $btnExit = $script:wpfWindow.FindName("btnExit")
        
        $easeOut = New-Object System.Windows.Media.Animation.CubicEase; $easeOut.EasingMode = 'EaseOut'
        $animContract = New-Object System.Windows.Media.Animation.ThicknessAnimation
        $animContract.To = New-Object System.Windows.Thickness(0)
        $animContract.Duration = [TimeSpan]::FromSeconds(0.3)
        $animContract.EasingFunction = $easeOut
        $btnExit.BeginAnimation([System.Windows.FrameworkElement]::MarginProperty, $animContract)
        
        if ($null -ne $btnProfileBottom.RenderTransform -and $btnProfileBottom.RenderTransform -is [System.Windows.Media.ScaleTransform]) {
            $animScaleBack = New-Object System.Windows.Media.Animation.DoubleAnimation
            $animScaleBack.To = 1.0
            $animScaleBack.Duration = [TimeSpan]::FromSeconds(0.3)
            $animScaleBack.EasingFunction = $easeOut
            $btnProfileBottom.RenderTransform.BeginAnimation([System.Windows.Media.ScaleTransform]::ScaleXProperty, $animScaleBack)
            $btnProfileBottom.RenderTransform.BeginAnimation([System.Windows.Media.ScaleTransform]::ScaleYProperty, $animScaleBack)
        }
        
        $btnExit.ClearValue([System.Windows.Controls.Control]::BackgroundProperty)
        $btnExit.Parent.Width = [Double]::NaN
        
        if ($null -ne $script:exitTimer) { $script:exitTimer.Stop() }
        return
    }
    
    if ($null -ne $script:exitTimer) { $script:exitTimer.Stop() }
    Invoke-ExitEngine
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
            if ($script:txtSearch.Text -and $script:txtSearch.Text -ne "Search transfers...") {
                $script:txtSearch.Text = ""
            } else {
                [System.Windows.Input.Keyboard]::ClearFocus()
            }
            $e.Handled = $true
        }
        return
    }
    if ($e.Key -eq [System.Windows.Input.Key]::Escape) {
        $settingsPanel = $script:wpfWindow.FindName("SettingsPanel")
        $fileExplorer = $script:wpfWindow.FindName("FileExplorer")
        
        # If settings is visible, contract it instead of hiding the whole window
        if ($settingsPanel.Visibility -eq 'Visible') {
            $sb = $script:wpfWindow.Resources["ContractSettings"].Clone()
            $sb.Children[0].By = $null
            $sb.Children[0].To = if ($script:contractedWidth) { $script:contractedWidth } else { 300 }
            $sb.Begin($script:wpfWindow, $true)
            $e.Handled = $true
            return
        }
        
        # Edge Case: Reset all expanded panels before hiding
        $script:wpfWindow.Hide()
        $script:lastDeactivated = [DateTime]::Now
        Reset-SpatialPanels
        $e.Handled = $true
    } elseif (($e.Key -eq [System.Windows.Input.Key]::Up -and ($e.KeyboardDevice.Modifiers -band [System.Windows.Input.ModifierKeys]::Alt)) -or ($e.Key -eq [System.Windows.Input.Key]::Back)) {
        # Edge Case 25: Alt + Up Arrow / Backspace navigates Up Directory (remote mode only)
        if ($script:wpfWindow.FindName("FileExplorer").Visibility -eq 'Visible' -and $null -ne $script:btnUpDir -and $script:currentDirPath -notmatch '^[A-Za-z]:\\') {
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
        Invoke-ExitEngine
        $e.Handled = $true
    }
})


$script:lastDeactivated = [DateTime]::MinValue


$script:dragPill = $script:wpfWindow.FindName("dragPill")
$script:btnToggleTopmost = $script:wpfWindow.FindName("btnToggleTopmost")

if ($script:dragPill) {
    $script:dragPill.Add_MouseLeftButtonDown({
        if ($_.ClickCount -eq 2) {
            if ($script:hasBeenDragged) {
                if ($script:isLocationPinned) {
                    $anim = New-Object System.Windows.Media.Animation.ThicknessAnimation
                    $anim.To = "5,0,-5,0"
                    $anim.Duration = [TimeSpan]::FromSeconds(0.05)
                    $anim.AutoReverse = $true
                    $anim.RepeatBehavior = New-Object System.Windows.Media.Animation.RepeatBehavior(3)
                    if ($script:btnToggleTopmost) { $script:btnToggleTopmost.BeginAnimation([System.Windows.FrameworkElement]::MarginProperty, $anim) }
                } else {
                    $winWidth = if ($script:wpfWindow.Width -gt 0 -and -not [double]::IsNaN($script:wpfWindow.Width)) { $script:wpfWindow.Width } else { 1420 }
                    $winHeight = if ($script:wpfWindow.Height -gt 0 -and -not [double]::IsNaN($script:wpfWindow.Height)) { $script:wpfWindow.Height } else { 760 }
                    $workArea = [System.Windows.SystemParameters]::WorkArea
                    $left = $workArea.Right - $winWidth + 13
                    $top = $workArea.Bottom - $winHeight + 13
                    if ($left -lt $workArea.Left) { $left = $workArea.Left - 13 }
                    if ($top -lt $workArea.Top) { $top = $workArea.Top - 13 }
                    
                    $ease = $script:wpfWindow.FindResource("BouncyEase")
                    $animX = New-Object System.Windows.Media.Animation.DoubleAnimation -Property @{ From = $script:wpfWindow.Left; To = $left; Duration = "0:0:0.45"; EasingFunction = $ease; FillBehavior = "Stop" }
                    $animY = New-Object System.Windows.Media.Animation.DoubleAnimation -Property @{ From = $script:wpfWindow.Top; To = $top; Duration = "0:0:0.45"; EasingFunction = $ease; FillBehavior = "Stop" }
                    
                    $script:wpfWindow.Left = $left
                    $script:wpfWindow.Top = $top
                    
                    $script:wpfWindow.BeginAnimation([System.Windows.Window]::LeftProperty, $animX)
                    $script:wpfWindow.BeginAnimation([System.Windows.Window]::TopProperty, $animY)
                    
                    $script:hasBeenDragged = $false
                }
            }
            $_.Handled = $true
        } else {
            $topPanel = $script:wpfWindow.FindName("TopActionsPanel")
            $dragPillAccent = $script:wpfWindow.FindName("dragPillAccent")
            if ($dragPillAccent) {
                $anim = New-Object System.Windows.Media.Animation.DoubleAnimation
                $anim.To = 1
                $anim.Duration = [TimeSpan]::FromSeconds(0.1)
                $dragPillAccent.BeginAnimation([System.Windows.UIElement]::OpacityProperty, $anim)
            }
            if ($topPanel) {
                try { $topPanel.FindResource("ShowPinAnim").Begin($script:wpfWindow) } catch {}
            }
            if ($null -eq $script:pinTimer) {
                $script:pinTimer = New-Object System.Windows.Threading.DispatcherTimer
                $script:pinTimer.Interval = [TimeSpan]::FromSeconds(3)
                $script:pinTimer.Add_Tick({
                    if (-not $script:isLocationPinned) {
                        $topPanel = $script:wpfWindow.FindName("TopActionsPanel")
                        if ($topPanel) {
                            try { $topPanel.FindResource("HidePinAnim").Begin($script:wpfWindow) } catch {}
                        }
                    }
                    $script:pinTimer.Stop()
                })
            }
            if (-not $script:isLocationPinned) {
                $script:pinTimer.Stop()
                $script:pinTimer.Start()
            }
            
            if ($_.ButtonState -eq [System.Windows.Input.MouseButtonState]::Pressed) {
                $script:hasBeenDragged = $true
                try { $script:wpfWindow.DragMove() } catch {}
                
                if ($dragPillAccent) {
                    $anim2 = New-Object System.Windows.Media.Animation.DoubleAnimation
                    $anim2.To = 0
                    $anim2.Duration = [TimeSpan]::FromSeconds(0.15)
                    $dragPillAccent.BeginAnimation([System.Windows.UIElement]::OpacityProperty, $anim2)
                }
            }
        }
    })
}

if ($script:btnToggleTopmost) {
    $script:btnToggleTopmost.Add_Click({
        $script:isLocationPinned = -not $script:isLocationPinned
        
        if ($script:isLocationPinned) {
            $this.ToolTip = "Unpin Location"
            if ($script:pinTimer) { $script:pinTimer.Stop() }
        } else {
            $this.ToolTip = "Pin Location"
            if ($script:pinTimer) {
                $script:pinTimer.Stop()
                $script:pinTimer.Start()
            }
        }
    })
}


# Click-outside closes menu ONLY when contracted (not expanded)
$script:wpfWindow.Add_Deactivated({
    # Guard: suppress Deactivated during show+PopIn animation to prevent double-flash
    if ($script:isShowingMenu) { return }
    Write-Trace "Deactivated fired! IsVisible: $($script:wpfWindow.IsVisible)"
    if ($script:wpfWindow.IsVisible) {
        # If menu is expanded, do NOT close on click-outside (use Close button instead)
        if ($script:wpfWindow.FindName("FileExplorer").Visibility -eq 'Visible') { return }
        if ($script:wpfWindow.FindName("SettingsPanel").Visibility -eq 'Visible') { return }
        $now = [DateTime]::Now
        Write-Trace "Deactivated - Ms since last: $(($now - $script:lastDeactivated).TotalMilliseconds)"
        if (($now - $script:lastDeactivated).TotalMilliseconds -gt 200) {
            Write-Trace "Deactivated: Hiding window"
            try { $script:wpfWindow.FindResource("PopIn").Stop($script:wpfWindow) } catch {}
            $script:wpfWindow.Hide()
            $script:lastDeactivated = $now
        }
    }
})

# Close button handler (only visible when expanded)
$script:wpfWindow.FindName("btnCloseMenu").Add_Click({
    $settingsPanel = $script:wpfWindow.FindName("SettingsPanel")
    $fileExplorer = $script:wpfWindow.FindName("FileExplorer")
    
    # If settings is visible, contract it instead of hiding the whole window
    if ($settingsPanel.Visibility -eq 'Visible') {
        $sb = $script:wpfWindow.Resources["ContractSettings"].Clone()
        $sb.Children[0].By = $null
        $sb.Children[0].To = if ($script:contractedWidth) { $script:contractedWidth } else { 300 }
        $sb.Begin($script:wpfWindow, $true)
        return
    }
    
    # If FileExplorer is visible, contract it instead of hiding the whole window (consistent UX)
    if ($fileExplorer.Visibility -eq 'Visible') {
        $sb = $script:wpfWindow.Resources["ContractMenu"].Clone()
        $sb.Children[0].By = $null
        $sb.Children[0].To = if ($script:contractedWidth) { $script:contractedWidth } else { 300 }
        $sb.Begin($script:wpfWindow, $true)
        $btnQAPull = $script:wpfWindow.FindName("btnQAPull")
        if ($btnQAPull) { $btnQAPull.IsChecked = $false }
        return
    }
    
    # Edge Case: Reset all expanded panels before hiding
    $script:wpfWindow.Hide()
    $script:lastDeactivated = [DateTime]::Now
    Reset-SpatialPanels
})

$script:notifyIcon.Add_MouseUp({
    param($sender, $e)
    Write-Trace "MouseUp fired! Button: $($e.Button)"
    if ($e.Button -eq 'Right' -or $e.Button -eq 'Left') {
        $now = [DateTime]::Now
        # Debounce: reject double-fired MouseUp events from a single physical click
        if (($now - $script:lastMouseUpTime).TotalMilliseconds -lt 300) {
            Write-Trace "MouseUp: Debounced (too fast)"
            return
        }
        $script:lastMouseUpTime = $now
        Write-Trace "IsVisible: $($script:wpfWindow.IsVisible) | Ms since lastDeactivated: $(($now - $script:lastDeactivated).TotalMilliseconds)"
        if ($script:wpfWindow.IsVisible -or (($now - $script:lastDeactivated).TotalMilliseconds -lt 400)) {
            # Edge Case: If window was visible with expanded panels, fully reset state on hide
            Write-Trace "MouseUp: Hiding window (debounce or visible)"
            $script:wpfWindow.Hide()
            Reset-SpatialPanels
            $script:lastDeactivated = $now
            return
        }
        
        try {
            $proc = New-Object System.Diagnostics.Process
            $proc.StartInfo.FileName = "adb.exe"
            $proc.StartInfo.Arguments = "devices -l"
            $proc.StartInfo.UseShellExecute = $false
            $proc.StartInfo.RedirectStandardOutput = $true
            $proc.StartInfo.CreateNoWindow = $true
            $proc.Start() | Out-Null
            
            # Non-blocking poll on UI thread to avoid ThreadPool RunspaceStateException crashes
            $timer = New-Object System.Windows.Threading.DispatcherTimer
            $timer.Interval = [TimeSpan]::FromMilliseconds(50)
            $timer.Add_Tick({
                if ($proc.HasExited) {
                    $timer.Stop()
                    try {
                        $out = $proc.StandardOutput.ReadToEnd() -split "`r?`n"
                        Update-WpfUI -DevicesOutput $out
                    } catch {}
                    $proc.Dispose()
                }
            })
            $timer.Start()
        } catch { Write-Trace "Update-WpfUI error: $_" }
        
        # Edge Case 27 & 28: Dynamic work area bounds clipping protection & window activation focus
        # Also reset containers to contracted state so PopIn shows clean window
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
        
        $workArea = [System.Windows.SystemParameters]::WorkArea
        $winWidth = if ($script:wpfWindow.Width -gt 0 -and -not [double]::IsNaN($script:wpfWindow.Width)) { $script:wpfWindow.Width } else { 1420 }
        $winHeight = if ($script:wpfWindow.Height -gt 0 -and -not [double]::IsNaN($script:wpfWindow.Height)) { $script:wpfWindow.Height } else { 760 }
        
        if (-not $script:isLocationPinned) {
            $left = $workArea.Right - $winWidth + 13
            $top = $workArea.Bottom - $winHeight + 13
            
            if ($left -lt $workArea.Left) { $left = $workArea.Left - 13 }
            if ($top -lt $workArea.Top) { $top = $workArea.Top - 13 }
            
            $script:wpfWindow.Left = $left
            $script:wpfWindow.Top = $top
        }
        $script:wpfWindow.Topmost = $true
        
        $script:lastDeactivated = [DateTime]::Now
        
        $script:wpfWindow.FindName("winScale").ScaleX = 0.85
        $script:wpfWindow.FindName("winScale").ScaleY = 0.85
        $script:wpfWindow.FindName("winTrans").Y = 15
        $script:wpfWindow.FindName("menuTrans").Y = 20
        $script:wpfWindow.FindName("menuContentTrans").Y = 35
        $script:wpfWindow.FindName("menuContentPanel").Opacity = 0
        $script:wpfWindow.FindName("mainBorder").Opacity = 0

        try {
            $sb = $script:wpfWindow.FindResource("PopIn")
            if ($sb) {
                $sb.Begin($script:wpfWindow, $true)
                $sb.Pause($script:wpfWindow)
            }
        } catch { Write-Trace "PopIn pre-trigger failed: $_" }

        # Guard: suppress Deactivated during show+animate to prevent double-flash race
        if ($script:showMenuGuardTimer) { $script:showMenuGuardTimer.Stop() }
        $script:isShowingMenu = $true

        $script:wpfWindow.Show()
        $script:wpfWindow.Activate()
        $script:wpfWindow.Focus()
        
        try {
            if ($sb) { $sb.Resume($script:wpfWindow) }
        } catch { Write-Trace "PopIn resume failed: $_" }

        # Clear the guard after PopIn animation completes (~800ms covers the longest 750ms tween)
        $script:showMenuGuardTimer = New-Object System.Windows.Threading.DispatcherTimer
        $script:showMenuGuardTimer.Interval = [TimeSpan]::FromMilliseconds(800)
        $script:showMenuGuardTimer.Add_Tick({
            $script:isShowingMenu = $false
            $script:showMenuGuardTimer.Stop()
        })
        $script:showMenuGuardTimer.Start()
    }
})

# --- Wiggle-to-Open Feature ---
try {
    Add-Type -TypeDefinition @"
    using System;
    using System.Runtime.InteropServices;
    public class Win32Input {
        [DllImport("user32.dll")]
        public static extern short GetAsyncKeyState(int vKey);
        [DllImport("user32.dll")]
        public static extern int GetSystemMetrics(int nIndex);
    }
"@
} catch {}

$script:wiggleHistory = @()
$script:wiggleEnabled = $true
$script:wiggleReversalsThreshold = 3
$script:wiggleGraceTicks = 0
$script:wiggleLastTick = [DateTime]::Now
$script:wiggleTimer = New-Object System.Windows.Threading.DispatcherTimer
$script:wiggleTimer.Interval = [TimeSpan]::FromMilliseconds(20)

$script:wiggleTimer.Add_Tick({
    if ($script:wpfWindow.IsVisible) {
        if ($script:openedViaWiggle) {
            $btn = if ([Win32Input]::GetSystemMetrics(23) -ne 0) { 0x02 } else { 0x01 }
            $isDown = ([Win32Input]::GetAsyncKeyState($btn) -band 0x8000) -ne 0
            if (-not $isDown) {
                $script:openedViaWiggle = $false
                # Run at Background priority so WPF Drop events fire first before we hide
                $script:wpfWindow.Dispatcher.InvokeAsync({
                    if ($script:wpfWindow.IsVisible) {
                        $script:wpfWindow.Hide()
                        Reset-SpatialPanels
                        $script:lastDeactivated = [DateTime]::Now
                    }
                }, [System.Windows.Threading.DispatcherPriority]::Background) | Out-Null
            }
        }
        return
    }
    
    $now = [DateTime]::Now
    if (($now - $script:wiggleLastTick).TotalMilliseconds -gt 150) {
        $script:wiggleHistory = @()
    }
    $script:wiggleLastTick = $now

    $btn = if ([Win32Input]::GetSystemMetrics(23) -ne 0) { 0x02 } else { 0x01 }
    $isDown = ([Win32Input]::GetAsyncKeyState($btn) -band 0x8000) -ne 0
    if (-not $isDown) {
        $script:wiggleGraceTicks++
        if ($script:wiggleGraceTicks -gt 2) {
            $script:wiggleHistory = @()
        }
        return
    }
    $script:wiggleGraceTicks = 0

    $pos = [System.Windows.Forms.Cursor]::Position
    $script:wiggleHistory += $pos.X
    if ($script:wiggleHistory.Count -gt 20) {
        # Keep last 1 second of history (20 * 50ms = 1000ms)
        $script:wiggleHistory = $script:wiggleHistory[-20..-1]
    }

    # Wiggle detection logic: count direction reversals
    if ($script:wiggleHistory.Count -ge 5) {
        $reversals = 0
        $lastDir = 0 # 1 for right, -1 for left
        $minX = $script:wiggleHistory[0]
        $maxX = $script:wiggleHistory[0]
        
        for ($i = 1; $i -lt $script:wiggleHistory.Count; $i++) {
            $prev = $script:wiggleHistory[$i-1]
            $curr = $script:wiggleHistory[$i]
            if ($curr -lt $minX) { $minX = $curr }
            if ($curr -gt $maxX) { $maxX = $curr }
            
            $diff = $curr - $prev
            if ([Math]::Abs($diff) -gt 5) { # Minimum delta to be considered a movement
                $dir = if ($diff -gt 0) { 1 } else { -1 }
                if ($lastDir -ne 0 -and $dir -ne $lastDir) {
                    $reversals++
                }
                $lastDir = $dir
            }
        }
        
        $totalDist = $maxX - $minX
        # A wiggle is threshold or more reversals in a localized area (< 150 pixels)
        if ($script:wiggleEnabled -and $reversals -ge $script:wiggleReversalsThreshold -and $totalDist -lt 150) {
            # Wiggle detected! Reset history
            $script:wiggleHistory = @()
            
            # Show the menu near the cursor
            if (-not $script:wpfWindow.IsVisible) {
                # Prepare animations if needed
                $script:wpfWindow.FindName("winScale").ScaleX = 0.85
                $script:wpfWindow.FindName("winScale").ScaleY = 0.85
                $script:wpfWindow.FindName("winTrans").Y = 15
                $script:wpfWindow.FindName("menuTrans").Y = 20
                $script:wpfWindow.FindName("menuContentTrans").Y = 35
                $script:wpfWindow.FindName("menuContentPanel").Opacity = 0
                $script:wpfWindow.FindName("mainBorder").Opacity = 0
                
                # Show only nearby devices (dummies) for Wiggle menu
                $script:wpfWindow.FindName("TopActionsPanel").Visibility = 'Collapsed'
                $script:wpfWindow.FindName("btnUserJoe").Visibility = 'Collapsed'
                $script:wpfWindow.FindName("btnDeviceGalaxy").Visibility = 'Collapsed'
                $script:wpfWindow.FindName("btnDeviceWindows").Visibility = 'Collapsed'
                $script:wpfWindow.FindName("NearbyExpandPanel").Visibility = 'Visible'
                $script:wpfWindow.FindName("NearbyExpandPanel").Opacity = 1
                $script:openedViaWiggle = $true

                try {
                    $sb = $script:wpfWindow.FindResource("PopIn")
                    if ($sb) {
                        $sb.Begin($script:wpfWindow, $true)
                        $sb.Pause($script:wpfWindow)
                    }
                } catch {}

                # Setup position (center window loosely around cursor)
                $winWidth = if ($script:wpfWindow.Width -gt 0 -and -not [double]::IsNaN($script:wpfWindow.Width)) { $script:wpfWindow.Width } else { 1420 }
                $winHeight = if ($script:wpfWindow.Height -gt 0 -and -not [double]::IsNaN($script:wpfWindow.Height)) { $script:wpfWindow.Height } else { 760 }
                
                $targetLeft = $pos.X - ($winWidth / 2)
                $targetTop = $pos.Y - ($winHeight / 2)
                
                # Keep within work area of the correct monitor
                $workArea = [System.Windows.Forms.Screen]::FromPoint($pos).WorkingArea
                if ($targetLeft -lt $workArea.Left) { $targetLeft = $workArea.Left }
                if ($targetTop -lt $workArea.Top) { $targetTop = $workArea.Top }
                if ($targetLeft + $winWidth -gt $workArea.Right) { $targetLeft = $workArea.Right - $winWidth }
                if ($targetTop + $winHeight -gt $workArea.Bottom) { $targetTop = $workArea.Bottom - $winHeight }
                
                $script:wpfWindow.Left = $targetLeft
                $script:wpfWindow.Top = $targetTop
                $script:wpfWindow.Topmost = $true
                
                $script:wpfWindow.Show()
                # (Activate removed to prevent dragging focus loss)

                try {
                    if ($sb) { $sb.Resume($script:wpfWindow) }
                } catch {}
            }
        }
    }
})
$script:wiggleTimer.Start()

$ctxMenu = $script:wpfWindow.Resources["TransferContextMenu"]
if ($ctxMenu) {
    $ctxMenu.AddHandler([System.Windows.Controls.MenuItem]::ClickEvent, [System.Windows.RoutedEventHandler]{
        param($sender, $e)
        $menuItem = $e.OriginalSource
        $listBoxItem = $ctxMenu.PlacementTarget
        if ($null -eq $listBoxItem -or $listBoxItem -isnot [System.Windows.Controls.ListBoxItem]) { return }
        $path = $listBoxItem.Tag
        
        $dangerousExts = @('.exe','.bat','.cmd','.ps1','.vbs','.vbe','.msi','.scr','.com','.pif','.wsf')
        switch ($menuItem.Name) {
            "CtxOpen" {
                if (-not (Test-Path $path)) {
                    Show-DownloadDockToast "File is missing."
                    $script:lbFiles.Items.Remove($listBoxItem)
                    return
                }
                $ext = [System.IO.Path]::GetExtension($path).ToLower()
                if ($dangerousExts -contains $ext) {
                    Start-Process explorer.exe -ArgumentList "/select,"$path""
                } else {
                    Start-Process $path
                }
            }
            "CtxOpenFolder" {
                Start-Process explorer.exe -ArgumentList "/select,"$path""
            }
            "CtxCopyPath" {
                [System.Windows.Clipboard]::SetText($path)
            }
            "CtxDelete" {
                if (Test-Path $path) { Remove-Item -LiteralPath $path -Force }
                $script:lbFiles.Items.Remove($listBoxItem)
            }
        }
    })
}

# --- PIN Pairing Handlers ---
$script:wpfWindow.FindName("btnPinCancel").Add_Click({
    if ($script:activePairRequest) {
        try { Invoke-RestMethod -Uri "http://127.0.0.1:53318/local/pairing-resolve?fingerprint=$($script:activePairRequest.fingerprint)&accept=false" -Method Post } catch {}
        $script:activePairRequest = $null
    }
    if ($script:pairWaitTimer) { $script:pairWaitTimer.Stop() }
    if ($script:isOutgoingPairRequest -and $script:activeOutgoingPairJob) {
        $script:activeOutgoingPairJob | Stop-Job
        $script:activeOutgoingPairJob | Remove-Job
        $script:activeOutgoingPairJob = $null
        $script:isOutgoingPairRequest = $false
    }
    try { $script:wpfWindow.FindName("menuViewsContainer").FindResource("SlideOutPinAnim").Begin($script:wpfWindow) } catch {}
})

$script:wpfWindow.FindName("btnPinAcceptOnce").Add_Click({
    if ($script:activePairRequest) {
        try { Invoke-RestMethod -Uri "http://127.0.0.1:53318/local/pairing-resolve?fingerprint=$($script:activePairRequest.fingerprint)&accept=true&guest=true" -Method Post } catch {}
        $script:activePairRequest = $null
        Show-Toast -Title "Guest Device Added" -Message "Device trusted for a single transfer."
    }
    if ($script:pairWaitTimer) { $script:pairWaitTimer.Stop() }
    try { $script:wpfWindow.FindName("menuViewsContainer").FindResource("SlideOutPinAnim").Begin($script:wpfWindow) } catch {}
})

$script:wpfWindow.FindName("btnPinAccept").Add_Click({
    if ($script:activePairRequest) {
        try { Invoke-RestMethod -Uri "http://127.0.0.1:53318/local/pairing-resolve?fingerprint=$($script:activePairRequest.fingerprint)&accept=true" -Method Post } catch {}
        $script:activePairRequest = $null
        Show-Toast -Title "Pairing Successful" -Message "Device trusted and added to Your Devices."
    }
    if ($script:pairWaitTimer) { $script:pairWaitTimer.Stop() }
    try { $script:wpfWindow.FindName("menuViewsContainer").FindResource("SlideOutPinAnim").Begin($script:wpfWindow) } catch {}
})

$script:wpfWindow.Add_Click({
    param($sender, $e)
    $src = $e.OriginalSource
    if ($src -is [System.Windows.Controls.MenuItem]) {
        $menuItem = $src
        if ($menuItem.Name -eq "menuRename") {
            $fp = $menuItem.Tag
            if ($fp) {
                Add-Type -AssemblyName Microsoft.VisualBasic
                $alias = [Microsoft.VisualBasic.Interaction]::InputBox("Enter new alias for this device:", "Rename Device", "")
                if (![string]::IsNullOrWhiteSpace($alias)) {
                    try { Invoke-RestMethod -Uri "http://127.0.0.1:53318/local/alias?fingerprint=$fp&alias=$alias" -Method Post } catch {}
                    Show-Toast -Title "Device Renamed" -Message "New alias saved."
                }
            }
        }
        elseif ($menuItem.Name -eq "menuForget") {
            $fp = $menuItem.Tag
            if ($fp) {
                try { Invoke-RestMethod -Uri "http://127.0.0.1:53318/local/unpair?fingerprint=$fp" -Method Post } catch {}
                Show-Toast -Title "Device Forgotten" -Message "Device has been unpaired."
            }
        }
        $e.Handled = $true
        return
    }
    
    if ($src -is [System.Windows.Controls.Button] -or $src -is [System.Windows.Controls.RadioButton]) {
        $dc = $src.DataContext
        if ($null -ne $dc -and $dc -is [System.Collections.Hashtable] -and $dc.Contains("Fingerprint") -and $dc.Contains("Alias") -and $dc.Contains("Ip")) {
            # Discovered Device Clicked -> Initiate Pairing
            $pin = (Get-Random -Minimum 100000 -Maximum 999999).ToString()
            $script:wpfWindow.FindName("txtPinTitle").Text = "Pairing with $($dc.Alias)"
            $script:wpfWindow.FindName("txtPinSubtitle").Text = "Ensure they see PIN:"
            $script:wpfWindow.FindName("txtPinCode").Text = $pin
            $script:wpfWindow.FindName("txtPinStatus").Text = "Waiting for remote acceptance..."
            try { $script:wpfWindow.FindName("menuViewsContainer").FindResource("SlideInPinAnim").Begin($script:wpfWindow) } catch {}
            
            # Hide Cancel/Accept buttons when WE initiate
            $script:wpfWindow.FindName("btnPinAccept").Visibility = 'Collapsed'
            $script:wpfWindow.FindName("btnPinAcceptOnce").Visibility = 'Collapsed'
            $btnPinCancel = $script:wpfWindow.FindName("btnPinCancel")
            $btnPinCancel.Visibility = 'Visible'
            $btnPinCancel.Content = "Cancel Request"
            
            $targetIp = $dc.Ip
            $myAlias = [Environment]::MachineName
            
            # Get local fingerprint
            $identityFile = Join-Path $env:LOCALAPPDATA "DeX\identity.json"
            $myFp = "unknown"
            if (Test-Path $identityFile) {
                try { $myFp = (Get-Content $identityFile -Raw | ConvertFrom-Json).fingerprint } catch {}
            }
            
            $bgJob = {
                param($ip, $alias, $fp, $pin)
                try {
                    [Net.ServicePointManager]::ServerCertificateValidationCallback = {$true}
                    $json = @{ alias=$alias; fingerprint=$fp; pin=$pin } | ConvertTo-Json -Compress
                    Invoke-RestMethod -Uri "https://${ip}:53317/api/localsend/v2/pair-prompt" -Method Post -Body $json -ContentType "application/json" -TimeoutSec 30
                    return $true
                } catch { return $false }
            }
            $job = Start-Job -ScriptBlock $bgJob -ArgumentList $targetIp, $myAlias, $myFp, $pin
            $script:activeOutgoingPairJob = $job
            $script:isOutgoingPairRequest = $true
            
            $script:pairWaitTimer = New-Object System.Windows.Threading.DispatcherTimer
            $script:pairWaitTimer.Interval = [TimeSpan]::FromMilliseconds(500)
            $script:pairWaitTimer.Add_Tick({
                if ($job.State -eq 'Completed') {
                                        $res = Receive-Job -Job $job
                    if ($res -ne "success") {
                        Show-Toast -Title "Pairing Failed" -Message "The remote device rejected or timed out."
                    }
                    $script:isOutgoingPairRequest = $false
                    $script:activeOutgoingPairJob = $null
                    $script:pairWaitTimer.Stop()
                    try { $script:wpfWindow.FindName("menuViewsContainer").FindResource("SlideOutPinAnim").Begin($script:wpfWindow) } catch {}
                } elseif ($job.State -ne 'Running') {
                    $script:pairWaitTimer.Stop()
                    try { $script:wpfWindow.FindName("menuViewsContainer").FindResource("SlideOutPinAnim").Begin($script:wpfWindow) } catch {}
                }
            })
            $script:pairWaitTimer.Start()
        }
    }
})


