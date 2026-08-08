
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
$script:wpfWindow.Add_PreviewMouseLeftButtonUp({
    param($sender, $e)
    $element = $e.OriginalSource
    while ($element -and $element -isnot [System.Windows.Controls.Primitives.ButtonBase]) {
        $element = [System.Windows.Media.VisualTreeHelper]::GetParent($element)
    }
    
    if ($element -and $element -is [System.Windows.Controls.Primitives.ButtonBase]) {
        # Check if the Button has an IP Tag (Omni-Mesh device)
        if ($element.Tag -and $element.Tag -match '^\d+\.\d+\.\d+\.\d+') {
            $ip = $element.Tag -replace ':.*', ''
            
            # Check if this device is in the Discovered Devices (Guest) list
            $icUdpPeers = $script:wpfWindow.FindName("icUdpPeers")
            $targetPeer = $null
            if ($icUdpPeers -and $icUdpPeers.ItemsSource) {
                $targetPeer = $icUdpPeers.ItemsSource | Where-Object { $_.Ip -eq $ip } | Select-Object -First 1
            }
            $isGuest = ($targetPeer -ne $null)

            if ($isGuest) {
                try {
                    $script:activeOutboundPairIp = $ip
                    $script:activeOutboundPairFp = $targetPeer.Fingerprint
                    
                    $script:wpfWindow.FindName("txtPinTitle").Text = "Pairing with $($targetPeer.Alias)"
                    $script:wpfWindow.FindName("txtPinSubtitle").Text = "Select an option below to connect"
                    
                    $script:wpfWindow.FindName("btnPinAccept").Visibility = 'Collapsed'
                    $script:wpfWindow.FindName("btnPinAcceptOnce").Visibility = 'Collapsed'
                    $script:wpfWindow.FindName("btnSettingsQrCode").Visibility = 'Visible'
                    $script:wpfWindow.FindName("btnPinCancel").Visibility = 'Visible'
                    
                    # Show QR Code initially instead of PIN
                    $localIp = [System.Net.Dns]::GetHostAddresses([System.Net.Dns]::GetHostName()) | Where-Object { $_.AddressFamily -eq 'InterNetwork' -and -not [System.Net.IPAddress]::IsLoopback($_) } | Select-Object -First 1 -ExpandProperty IPAddressToString
                    if ($localIp) {
                        $imgQrCode = $script:wpfWindow.FindName("imgQrCode")
                        if ($imgQrCode) {
                            $bitmap = New-Object System.Windows.Media.Imaging.BitmapImage
                            $bitmap.BeginInit()
                            $bitmap.UriSource = New-Object Uri("http://127.0.0.1:53318/local/qr?ip=$localIp")
                            $bitmap.CacheOption = [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad
                            $bitmap.EndInit()
                            $imgQrCode.Source = $bitmap
                        }
                        $script:wpfWindow.FindName("pinCodeContent").Visibility = 'Collapsed'
                        $script:wpfWindow.FindName("qrCodeContent").Visibility = 'Visible'
                        
                        $txtQrBtnIcon = $script:wpfWindow.FindName("txtQrBtnIcon")
                        if ($txtQrBtnIcon) { $txtQrBtnIcon.Visibility = 'Collapsed' }
                        $txtQrBtnText = $script:wpfWindow.FindName("txtQrBtnText")
                        if ($txtQrBtnText) { $txtQrBtnText.Text = "Request PIN" }
                    }
                    
                    # Stop any running timer from previous sessions
                    if ($script:pairWaitTimer) { $script:pairWaitTimer.Stop() }
                    
                    # Reset progress bar to full (100)
                    $pb = $script:wpfWindow.FindName("pbPinTimeout")
                    if ($pb) { 
                        $pb.BeginAnimation([System.Windows.Controls.Primitives.RangeBase]::ValueProperty, $null)
                        $pb.Value = 100 
                    }

                    try { $script:wpfWindow.FindName("menuViewsContainer").FindResource("SlideInPinAnim").Begin($script:wpfWindow) } catch {}
                    
                    $e.Handled = $true
                    return
                } catch {
                    Show-Toast -Title "Pairing Failed" -Message $_.Exception.Message
                    $e.Handled = $true
                    return
                }
            }

            # If not a guest (already in Live Peers), connect ADB
            $res = Invoke-AdbConnect -Target $ip
            if ($res.Success) {
                Invoke-MenuAction $actionPull
            } else {
                Show-Toast -Title "Connection Failed" -Message $res.Message
            }
            
            $e.Handled = $true
        }
    }
})
