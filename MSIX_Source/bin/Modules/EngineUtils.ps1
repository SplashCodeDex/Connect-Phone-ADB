
function Load-Directory($dirPath) {
    if ($script:isLoadingDir) { return }
    $script:isLoadingDir = $true
    
    try {
        if ($null -ne $script:searchTimer) { $script:searchTimer.Stop() }
        
        # Auto-reset search bar text so the new directory displays all items cleanly
        if ($null -ne $script:txtSearch) {
            $script:txtSearch.Text = "Search files..."
            $script:txtSearch.Foreground = $script:wpfWindow.FindResource("SecondaryTextBrush")
        }
        
        # Edge Case 27: Normalize and sanitize directory path
        $dirPath = ($dirPath -replace '(?<!:)/+', '/').Trim()
        if (-not $dirPath.StartsWith("/")) { $dirPath = "/" + $dirPath }
        if (-not $dirPath.EndsWith("/")) { $dirPath = $dirPath + "/" }
        
        $script:currentDirPath = $dirPath
        $script:lbFiles.Items.Clear()
        
        if ($null -ne $script:btnUpDir) {
            if ($dirPath -eq "/sdcard/" -or $dirPath -eq "/sdcard") {
                $script:btnUpDir.Opacity = 0.4
                $script:btnUpDir.Cursor = [System.Windows.Input.Cursors]::Arrow
            } else {
                $script:btnUpDir.Opacity = 1.0
                $script:btnUpDir.Cursor = [System.Windows.Input.Cursors]::Hand
            }
        }
        

        
        if ($script:adbLsProc -and -not $script:adbLsProc.HasExited) {
            try { $script:adbLsProc.Kill() } catch {}
        }
        
        $proc = New-Object System.Diagnostics.Process
        $proc.StartInfo.FileName = "cmd.exe"
        $proc.StartInfo.Arguments = "/c `"`"$global:AdbExePath`" -s $($script:currentTarget) shell ls -1aF `"$dirPath`"`""
        $proc.StartInfo.UseShellExecute = $false
        $proc.StartInfo.RedirectStandardOutput = $true
        $proc.StartInfo.CreateNoWindow = $true
        
        $proc.Start() | Out-Null
        $script:adbLsProc = $proc
        
        # Edge Case 22: 5-second timeout guard to prevent hanging ADB processes
        if (-not $proc.WaitForExit(5000)) {
            try { $proc.Kill() } catch {}
            Show-Toast -Title "ADB Timeout" -Message "Device did not respond within 5 seconds."
            return
        }
        $output = $proc.StandardOutput.ReadToEnd()
        
        $lines = $output -split "`n" | ForEach-Object { $_.Trim() } | Where-Object { 
            $_ -ne "" -and 
            $_ -ne "./" -and 
            $_ -ne "../" -and 
            $_ -notmatch "^(ls:|error:|adb:|failed|Permission denied|\* daemon)"
        }
        
        # Edge Case 5: Empty Folder State Toggle
        $emptyOverlay = $script:wpfWindow.FindName("emptyFolderState")
        if ($null -ne $emptyOverlay) {
            if (-not $lines -or $lines.Count -eq 0) {
                $emptyOverlay.Visibility = 'Visible'
                $emptyOverlay.Opacity = 1.0
            } else {
                $emptyOverlay.Visibility = 'Collapsed'
                $emptyOverlay.Opacity = 0.0
            }
        }
        
        $idx = 0
        foreach ($line in $lines) {
            $isDir = $line.EndsWith("/")
            $name = $line.TrimEnd('/', '*', '@', '=')
            if ($isDir) {
                $full = $dirPath + $name + "/"
                $template = $script:wpfWindow.Resources["FolderGridTemplate"]
            } else {
                $full = $dirPath + $name
                $template = $script:wpfWindow.Resources["FileGridTemplate"]
            }
            
            $item = New-Object System.Windows.Controls.ListBoxItem
            $item.Content = [PSCustomObject]@{ Name = $name; FullPath = $full; IsDir = $isDir }
            $item.ContentTemplate = $template
            $item.Tag = $full
            
            # Staggered Entrance Animation
            $trans = New-Object System.Windows.Media.TranslateTransform
            $trans.Y = 80
            $item.RenderTransform = $trans
            $item.Opacity = 0
            
            $delay = [TimeSpan]::FromMilliseconds($idx * 35)
            
            $daY = New-Object System.Windows.Media.Animation.DoubleAnimation
            $daY.To = 0
            $daY.Duration = [TimeSpan]::FromSeconds(0.6)
            $daY.BeginTime = $delay
            $daY.EasingFunction = $script:wpfWindow.Resources["HoverEase"]
            
            $daOp = New-Object System.Windows.Media.Animation.DoubleAnimation
            $daOp.To = 1
            $daOp.Duration = [TimeSpan]::FromSeconds(0.4)
            $daOp.BeginTime = $delay
            
            $trans.BeginAnimation([System.Windows.Media.TranslateTransform]::YProperty, $daY)
            $item.BeginAnimation([System.Windows.Controls.ListBoxItem]::OpacityProperty, $daOp)
            
            $script:lbFiles.Items.Add($item)
            $idx++
        }
    } finally {
        $script:isLoadingDir = $false
    }
}

function global:Write-Trace($msg) {
    # Rotate: keep the log forensically useful by capping it at ~200KB (retains last 500 lines)
    $tracePath = "$env:TEMP\connect-adb-trace.txt"
    try {
        if ((Test-Path $tracePath) -and ((Get-Item $tracePath).Length -gt 200KB)) {
            Get-Content $tracePath -Tail 500 | Set-Content $tracePath
        }
    } catch {}
    Out-File -FilePath $tracePath -InputObject "[$(Get-Date -Format 'HH:mm:ss.fff')] $msg" -Append
}

