. "$PSScriptRoot\TrayUIHandlers.ps1"
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
        
        # ADB Decoupled: The file downloading backend is being migrated away from ADB.
        # Hook up the new HTTP/QUIC/thru backend here to download $remotePaths to $outDir
        $actionBatchBg = {
            param($remPaths, $out)
            # Placeholder for new backend execution
            # e.g. Start-Process "thru.exe" -ArgumentList "receive ..."
            Start-Process "explorer.exe" -ArgumentList "`"$out`""
        }
        
        Start-Job -ScriptBlock $actionBatchBg -ArgumentList $remotePaths, $outDir
        
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
    $btnSettingsConnectNow.Add_Click({ Invoke-MenuAction $actionConnect })
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
        $txtTheme = $script:wpfWindow.FindName("txtSettingsTheme")
        if ($txtTheme) {
            $txtTheme.Text = if ($global:CurrentTheme -eq "DarkTheme") { "Dark" } else { "Light" }
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
        Start-Process "https://github.com/SplashCodeDex/Connect-Phone-ADB"
        $script:wpfWindow.Hide()
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
        $settingsPanel = $script:wpfWindow.FindName("SettingsPanel")
        $fileExplorer = $script:wpfWindow.FindName("FileExplorer")
        
        # If settings is visible, contract it instead of hiding the whole window
        if ($settingsPanel.Visibility -eq 'Visible') {
            $sb = $script:wpfWindow.Resources["ContractSettings"].Clone()
            $sb.Children[0].By = $null
            $sb.Children[0].To = if ($script:contractedWidth) { $script:contractedWidth } else { 300 }
            $sb.Begin($script:wpfWindow)
            $e.Handled = $true
            return
        }
        
        # Edge Case: Reset all expanded panels before hiding
        $script:wpfWindow.Hide()
        $script:lastDeactivated = [DateTime]::Now
        Reset-SpatialPanels
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
        if ($script:wpfWindow.FindName("SettingsPanel").Visibility -eq 'Visible') { return }
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
    $settingsPanel = $script:wpfWindow.FindName("SettingsPanel")
    $fileExplorer = $script:wpfWindow.FindName("FileExplorer")
    
    # If settings is visible, contract it instead of hiding the whole window
    if ($settingsPanel.Visibility -eq 'Visible') {
        $sb = $script:wpfWindow.Resources["ContractSettings"].Clone()
        $sb.Children[0].By = $null
        $sb.Children[0].To = if ($script:contractedWidth) { $script:contractedWidth } else { 300 }
        $sb.Begin($script:wpfWindow)
        return
    }
    
    # If FileExplorer is visible, contract it instead of hiding the whole window (consistent UX)
    if ($fileExplorer.Visibility -eq 'Visible') {
        $sb = $script:wpfWindow.Resources["ContractMenu"].Clone()
        $sb.Children[0].By = $null
        $sb.Children[0].To = if ($script:contractedWidth) { $script:contractedWidth } else { 300 }
        $sb.Begin($script:wpfWindow)
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
        Write-Trace "IsVisible: $($script:wpfWindow.IsVisible) | Ms since lastDeactivated: $(($now - $script:lastDeactivated).TotalMilliseconds)"
        if ($script:wpfWindow.IsVisible -or (($now - $script:lastDeactivated).TotalMilliseconds -lt 300)) {
            # Edge Case: If window was visible with expanded panels, fully reset state on hide
            Write-Trace "MouseUp: Hiding window (debounce or visible)"
            $script:wpfWindow.Hide()
            Reset-SpatialPanels
            return
        }
        
        try {
            $proc = New-Object System.Diagnostics.Process
            $proc.StartInfo.FileName = "adb.exe"
            $proc.StartInfo.Arguments = "devices -l"
            $proc.StartInfo.UseShellExecute = $false
            $proc.StartInfo.RedirectStandardOutput = $true
            $proc.StartInfo.CreateNoWindow = $true
            $proc.EnableRaisingEvents = $true
            $proc.Add_Exited({
                $out = $proc.StandardOutput.ReadToEnd() -split "`r?`n"
                $script:wpfWindow.Dispatcher.InvokeAsync([Action]{
                    try { Update-WpfUI -DevicesOutput $out } catch {}
                }) | Out-Null
                $proc.Dispose()
            })
            $proc.Start() | Out-Null
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
            try {
                $sb = $script:wpfWindow.FindResource("PopIn")
                if ($sb) { $sb.Begin($script:wpfWindow) }
            } catch { Write-Trace "PopIn trigger failed: $_" }
        })
    }
})


