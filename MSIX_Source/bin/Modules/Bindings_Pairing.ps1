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
        $entered = $script:wpfWindow.FindName("txtPinInput").Text
        if ($entered -ne $script:activePairRequest.pin) {
            Show-Toast -Title "Pairing Failed" -Message "Incorrect PIN."
            try { Invoke-RestMethod -Uri "http://127.0.0.1:53318/local/pairing-resolve?fingerprint=$($script:activePairRequest.fingerprint)&accept=false" -Method Post } catch {}
            $script:activePairRequest = $null
            try { $script:wpfWindow.FindName("menuViewsContainer").FindResource("SlideOutPinAnim").Begin($script:wpfWindow) } catch {}
            return
        }
        try { Invoke-RestMethod -Uri "http://127.0.0.1:53318/local/pairing-resolve?fingerprint=$($script:activePairRequest.fingerprint)&accept=true&guest=true" -Method Post } catch {}
        $script:activePairRequest = $null
        Show-Toast -Title "Guest Device Added" -Message "Device trusted for a single transfer."
    }
    if ($script:pairWaitTimer) { $script:pairWaitTimer.Stop() }
    try { $script:wpfWindow.FindName("menuViewsContainer").FindResource("SlideOutPinAnim").Begin($script:wpfWindow) } catch {}
})

$script:wpfWindow.FindName("btnPinAccept").Add_Click({
    if ($script:activePairRequest) {
        $entered = $script:wpfWindow.FindName("txtPinInput").Text
        if ($entered -ne $script:activePairRequest.pin) {
            Show-Toast -Title "Pairing Failed" -Message "Incorrect PIN."
            try { Invoke-RestMethod -Uri "http://127.0.0.1:53318/local/pairing-resolve?fingerprint=$($script:activePairRequest.fingerprint)&accept=false" -Method Post } catch {}
            $script:activePairRequest = $null
            try { $script:wpfWindow.FindName("menuViewsContainer").FindResource("SlideOutPinAnim").Begin($script:wpfWindow) } catch {}
            return
        }
        try { Invoke-RestMethod -Uri "http://127.0.0.1:53318/local/pairing-resolve?fingerprint=$($script:activePairRequest.fingerprint)&accept=true" -Method Post } catch {}
        $script:activePairRequest = $null
        Show-Toast -Title "Pairing Successful" -Message "Device trusted and added to Your Devices."
    }
    if ($script:pairWaitTimer) { $script:pairWaitTimer.Stop() }
    try { $script:wpfWindow.FindName("menuViewsContainer").FindResource("SlideOutPinAnim").Begin($script:wpfWindow) } catch {}
})

$script:wpfWindow.AddHandler([System.Windows.Controls.MenuItem]::ClickEvent, [System.Windows.RoutedEventHandler]{
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
            try {
                $targetIp = $dc.Ip
                $targetFp = $dc.Fingerprint
                $initRes = Invoke-RestMethod -Uri "http://127.0.0.1:53318/local/pair-initiate?ip=${targetIp}&fingerprint=${targetFp}" -Method Post -TimeoutSec 5 -ErrorAction Stop
                $pin = $initRes.pin

                if ($pin) {
                    $script:activeOutboundPairIp = $targetIp
                    $script:wpfWindow.FindName("txtPinTitle").Text = "Pairing with $($dc.Alias)"
                    $script:wpfWindow.FindName("txtPinSubtitle").Text = "Ensure they see PIN:"
                    $script:wpfWindow.FindName("txtPinCode").Visibility = 'Visible'
                    $script:wpfWindow.FindName("txtPinInput").Visibility = 'Collapsed'
                    $script:wpfWindow.FindName("txtPinCode").Text = $pin
                    $script:wpfWindow.FindName("txtPinStatus").Text = "Waiting for remote acceptance..."
                    
                    $script:wpfWindow.FindName("btnPinAccept").Visibility = 'Collapsed'
                    $script:wpfWindow.FindName("btnPinAcceptOnce").Visibility = 'Collapsed'
                    $script:wpfWindow.FindName("btnSettingsQrCode").Visibility = 'Visible'
                    $btnPinCancel = $script:wpfWindow.FindName("btnPinCancel")
                    $btnPinCancel.Visibility = 'Visible'
                    $btnPinCancel.Content = "Cancel Request"
                    
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
                    
                    try { $script:wpfWindow.FindName("menuViewsContainer").FindResource("SlideInPinAnim").Begin($script:wpfWindow) } catch {}
                    
                    # We still want to monitor status but through the backend
                    $script:pairWaitTimer = New-Object System.Windows.Threading.DispatcherTimer
                    $script:pairWaitTimer.Interval = [TimeSpan]::FromMilliseconds(1000)
                    $script:pairWaitTimer.Add_Tick({
                        try {
                            $statusRes = Invoke-RestMethod -Uri "http://127.0.0.1:53318/local/pair-status?ip=${targetIp}" -Method Get -ErrorAction Stop
                            if ($statusRes.status -eq "Accepted") {
                                $script:pairWaitTimer.Stop()
                                Show-Toast -Title "Pairing Successful" -Message "Device trusted and added to Your Devices."
                                try { $script:wpfWindow.FindName("menuViewsContainer").FindResource("SlideOutPinAnim").Begin($script:wpfWindow) } catch {}
                            } elseif ($statusRes.status -eq "Rejected" -or $statusRes.status -eq "Failed") {
                                $script:pairWaitTimer.Stop()
                                Show-Toast -Title "Pairing Failed" -Message "The remote device rejected or timed out."
                                try { $script:wpfWindow.FindName("menuViewsContainer").FindResource("SlideOutPinAnim").Begin($script:wpfWindow) } catch {}
                            }
                        } catch {}
                    })
                    $script:pairWaitTimer.Start()
                }
            } catch {
                Show-Toast -Title "Pairing Failed" -Message $_.Exception.Message
            }
        }
    }
})


