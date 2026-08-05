
$script:btnUpDir = $script:wpfWindow.FindName("btnUpDir")
$script:currentTarget = ""
$script:currentDirPath = ""
$script:adbLsProc = $null
$script:explorerMode = $false
$script:grantedFolders = @()
$script:currentFolderUri = $null

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

# Toggle between Transfer History (local Downloads\DeX) and File Explorer Mode (SAF-granted phone folders)
$script:btnToggleExplorerMode = $script:wpfWindow.FindName("btnToggleExplorerMode")
if ($script:btnToggleExplorerMode) {
    $script:btnToggleExplorerMode.Add_Click({
        $script:explorerMode = -not $script:explorerMode
        if ($script:explorerMode) {
            # File Explorer Mode: load granted folders from the Android device
            $target = Get-ConnectedDeviceTarget
            if ($target) {
                $ip = $target.Split(':')[0]
                try {
                    $tokRes = Invoke-RestMethod -Uri "http://127.0.0.1:53318/local/token?ip=$ip" -TimeoutSec 2 -ErrorAction Stop
                    $headers = @{}
                    if ($tokRes.token) { $headers["Authorization"] = "Bearer $($tokRes.token)" }
                    $script:grantedFolders = @(Invoke-RestMethod -Uri "https://${ip}:53317/api/dex/folders" -Headers $headers -TimeoutSec 3 -ErrorAction Stop)
                } catch {
                    $script:grantedFolders = @()
                }
            } else {
                $script:grantedFolders = @()
            }
            
            if ($script:grantedFolders.Count -eq 0) {
                # No folders granted yet — prompt the user to request access
                $target = Get-ConnectedDeviceTarget
                if ($target) {
                    $ip = $target.Split(':')[0]
                    try {
                        $tokRes = Invoke-RestMethod -Uri "http://127.0.0.1:53318/local/token?ip=$ip" -TimeoutSec 2 -ErrorAction Stop
                        $headers = @{}
                        if ($tokRes.token) { $headers["Authorization"] = "Bearer $($tokRes.token)" }
                        Invoke-RestMethod -Uri "https://${ip}:53317/api/dex/grant-folder?name=Downloads" -Method Post -Headers $headers -TimeoutSec 3 -ErrorAction Stop | Out-Null
                        Show-Toast -Title "Folder Access" -Message "Grant a folder on your phone to enable File Explorer mode."
                    } catch {}
                }
                $script:explorerMode = $false
                $script:btnToggleExplorerMode.Content = "&#xE8B7;"
                return
            }
            
            # Show granted folders as the file list
            $script:lbFiles.Items.Clear()
            foreach ($folder in $script:grantedFolders) {
                $item = New-Object System.Windows.Controls.ListBoxItem
                $item.Content = [PSCustomObject]@{ Name = $folder.name; FullPath = $folder.uri; IsDir = $true; Meta = "Phone folder"; Thumb = $null; NoThumb = 'Visible' }
                $item.ContentTemplate = $script:wpfWindow.Resources["FolderGridTemplate"]
                $item.Tag = $folder.uri
                $script:lbFiles.Items.Add($item)
            }
            $script:currentDirPath = "Phone Folders"
            $script:btnToggleExplorerMode.Content = "&#xE8B7;"
            $script:btnToggleExplorerMode.ToolTip = "Switch to Transfer History"
        } else {
            # Transfer History Mode: show local Downloads\DeX
            $outDir = if ($script:customDownloadPath) { $script:customDownloadPath } else { Join-Path $env:USERPROFILE "Downloads\DeX" }
            if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Force -Path $outDir | Out-Null }
            Load-Directory $outDir
            $script:btnToggleExplorerMode.Content = "&#xE8B7;"
            $script:btnToggleExplorerMode.ToolTip = "Toggle File Explorer Mode"
        }
    })
}

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
            Join-Path $env:USERPROFILE "Downloads\DeX" 
        }
        
        try {
            if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Force -Path $outDir | Out-Null }
        } catch {
            $outDir = Join-Path $env:TEMP "dex"
            if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Force -Path $outDir | Out-Null }
        }
        
        $remotePaths = $fileItems | ForEach-Object { $_.Content.FullPath }
        
        $actionBatchBg = {
            param($remPaths, $out, $ip, $localAppData)
            
            $wc = New-Object System.Net.WebClient
            [Net.ServicePointManager]::ServerCertificateValidationCallback = {$true}
            try {
                $tokRes = Invoke-RestMethod -Uri "http://127.0.0.1:53318/local/token?ip=$ip" -TimeoutSec 2 -ErrorAction Stop
                if ($tokRes.token) { $wc.Headers.Add("Authorization", "Bearer $($tokRes.token)") }
            } catch {}
            
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
            Start-Job -ScriptBlock $actionBatchBg -ArgumentList $remotePaths, $outDir, $ip, $env:LOCALAPPDATA
        }
        
        $dispName = if ($script:customDownloadPath) { 
            [System.IO.Path]::GetFileName($script:customDownloadPath) 
        } else { 
            "Downloads\DeX" 
        }
        
        if ($fileItems.Count -gt 1) {
            Show-DownloadDockToast "$($fileItems.Count) files to $dispName"
        } else {
            Show-DownloadDockToast $dispName
        }
    }
})

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
$script:wpfWindow.FindName("btnPushFiles").Add_Click({ Invoke-MenuAction $actionPushFiles })
$script:wpfWindow.FindName("btnPushFolder").Add_Click({ Invoke-MenuAction $actionPushFolder })
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
