
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

$script:wpfWindow.FindName("btnDeviceGalaxy").Add_Click({ $script:isMockMode = $true; Invoke-MenuAction $actionPull })
$script:wpfWindow.FindName("btnDeviceWindows").Add_Click({ $script:isMockMode = $true; Invoke-MenuAction $actionPull })
