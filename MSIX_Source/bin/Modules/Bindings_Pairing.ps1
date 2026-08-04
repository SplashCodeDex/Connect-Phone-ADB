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
            $script:wpfWindow.FindName("btnSettingsQrCode").Visibility = 'Visible'
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


