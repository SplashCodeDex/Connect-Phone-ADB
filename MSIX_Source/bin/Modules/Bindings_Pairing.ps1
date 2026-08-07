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
    }
})




