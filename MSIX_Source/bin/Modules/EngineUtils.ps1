
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
        

        $target = Get-ConnectedDeviceTarget
        if (-not $target) {
            $lines = @()
        } else {
            $ip = $target.Split(':')[0]
            try {
                $uri = "https://${ip}:53317/api/dex/browse?path=" + [uri]::EscapeDataString($dirPath)
                [Net.ServicePointManager]::ServerCertificateValidationCallback = {$true}
                $res = Invoke-RestMethod -Uri $uri -Method Get -ErrorAction Stop
                
                $lines = @()
                if ($res) {
                    foreach ($f in $res) {
                        $name = $f.name
                        if ($f.isDirectory) {
                            $lines += "$name/"
                        } else {
                            $lines += $name
                        }
                    }
                }
            } catch {
                Write-Trace "Browse Error: $_"
                $lines = @()
            }
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

