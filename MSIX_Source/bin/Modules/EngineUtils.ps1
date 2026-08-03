if (-not ("ThumbHelper" -as [type])) {
    $thumbCode = @"
using System;
using System.Runtime.InteropServices;
using System.Windows.Interop;
using System.Windows.Media.Imaging;
using System.Windows;

public class ThumbHelper {
    [DllImport("shell32.dll", CharSet = CharSet.Unicode, PreserveSig = false)]
    public static extern void SHCreateItemFromParsingName(string path, IntPtr pbc, [MarshalAs(UnmanagedType.LPStruct)] Guid riid, out object ppv);

    [DllImport("gdi32.dll")]
    public static extern bool DeleteObject(IntPtr hObject);

    public static BitmapSource GetThumb(string path, int size) {
        Guid iid = new Guid("bcc18b79-ba16-442f-80c4-8a15c3ed75a8");
        object item;
        SHCreateItemFromParsingName(path, IntPtr.Zero, iid, out item);
        
        IntPtr hBitmap;
        // SIIGBF_MEMORYONLY (0x2) is safer for performance, but 0x0 will fetch or generate
        ((dynamic)item).GetImage(new System.Drawing.Size(size, size), 0x0, out hBitmap);
        
        BitmapSource bs = Imaging.CreateBitmapSourceFromHBitmap(hBitmap, IntPtr.Zero, Int32Rect.Empty, BitmapSizeOptions.FromEmptyOptions());
        bs.Freeze();
        DeleteObject(hBitmap);
        return bs;
    }
}
"@
    try {
        Add-Type -TypeDefinition $thumbCode -ReferencedAssemblies "System.Drawing", "PresentationCore", "WindowsBase", "Microsoft.CSharp" -ErrorAction SilentlyContinue
    } catch {}
}

function Load-ThumbnailAsync($targetItem, $fullPath, $fileName, $isDir, $metaStr) {
    if ($isDir -or -not ("ThumbHelper" -as [type])) { return }
    $action = [System.Action]{
        try {
            $bs = $null
            if ($fileName -match '\.(jpg|jpeg|png|webp|bmp)$') {
                $bmp = New-Object System.Windows.Media.Imaging.BitmapImage
                $bmp.BeginInit()
                $bmp.UriSource = New-Object System.Uri("file:///$fullPath")
                $bmp.DecodePixelWidth = 100
                $bmp.CacheOption = [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad
                $bmp.EndInit()
                $bmp.Freeze()
                $bs = $bmp
            } else {
                $bs = [ThumbHelper]::GetThumb($fullPath, 100)
            }
            if ($bs) {
                $uiAction = [System.Action]{
                    $targetItem.Content = [PSCustomObject]@{ Name = $fileName; FullPath = $fullPath; IsDir = $isDir; Meta = $metaStr; Thumb = $bs; NoThumb = 'Collapsed' }
                }
                $script:wpfWindow.Dispatcher.Invoke($uiAction)
            }
        } catch {
            # Silently fail for unsupported files
        }
    }
    $null = $action.BeginInvoke($null, $null)
}

function Load-Directory($dirPath) {
    if ($script:isLoadingDir) { return }
    $script:isLoadingDir = $true
    
    try {
        if ($null -ne $script:searchTimer) { $script:searchTimer.Stop() }
        
        # Auto-reset search bar text so the new directory displays all items cleanly
        if ($null -ne $script:txtSearch) {
            $script:txtSearch.Text = "Search transfers..."
            $script:txtSearch.Foreground = $script:wpfWindow.FindResource("SecondaryTextBrush")
        }
        
        # Edge Case 27: Normalize and sanitize directory path
        $isLocal = [System.IO.Path]::IsPathRooted($dirPath) -and $dirPath -match '^[A-Za-z]:\\'
        if (-not $isLocal) {
            $dirPath = ($dirPath -replace '(?<!:)/+', '/').Trim()
            if (-not $dirPath.StartsWith("/")) { $dirPath = "/" + $dirPath }
            if (-not $dirPath.EndsWith("/")) { $dirPath = $dirPath + "/" }
        } else {
            if (-not $dirPath.EndsWith("\")) { $dirPath = $dirPath + "\" }
        }
        
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
        if ($isLocal) {
            $lines = @()
            $script:localFileMeta = @{}
            if (Test-Path $dirPath) {
                Get-ChildItem -Path $dirPath -File | Sort-Object LastWriteTime -Descending | Select-Object -First 50 | ForEach-Object {
                    $lines += $_.Name
                    $bytes = $_.Length
                    if ($bytes -ge 1GB) { $sz = "{0:N1} GB" -f ($bytes / 1GB) }
                    elseif ($bytes -ge 1MB) { $sz = "{0:N1} MB" -f ($bytes / 1MB) }
                    elseif ($bytes -ge 1KB) { $sz = "{0:N0} KB" -f ($bytes / 1KB) }
                    else { $sz = "$bytes B" }
                    $dt = $_.LastWriteTime.ToString("MMM d, h:mm tt")
                    $script:localFileMeta[$_.Name] = "$sz · $dt"
                }
            }
        } elseif ($script:isMockMode) {
            $lines = @("DeX_Transfers/")
            for ($i = 1; $i -le 49; $i++) {
                $ext = if ($i % 4 -eq 0) { ".pdf" } elseif ($i % 3 -eq 0) { ".mp4" } elseif ($i % 2 -eq 0) { ".png" } else { ".jpg" }
                $lines += "dummy_file_$i$ext"
            }
        } elseif (-not $target) {
            $lines = @()
        } else {
            $ip = $target.Split(':')[0]
            try {
                $uri = "https://${ip}:53317/api/dex/browse?path=" + [uri]::EscapeDataString($dirPath)
                [Net.ServicePointManager]::ServerCertificateValidationCallback = {$true}
                
                $token = $null
                $trustLevel = if ($script:omniPeers -and $script:omniPeers[$ip]) { $script:omniPeers[$ip].TrustLevel } else { "Guest" }
                if ($trustLevel -eq "Auto-Trusted") {
                    $token = "dex_static_placeholder_hash_123"
                } else {
                    $settingsPath = Join-Path $PSScriptRoot "..\..\appsettings.json"
                    if (Test-Path $settingsPath) {
                        try { $token = (Get-Content $settingsPath -Raw | ConvertFrom-Json -AsHashtable)[$ip] } catch {}
                    }
                }
                
                $headers = @{}
                if ($token) { $headers["Authorization"] = "Bearer $token" }
                
                $res = Invoke-RestMethod -Uri $uri -Method Get -Headers $headers -TimeoutSec 3 -ErrorAction Stop
                
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
            $isDir = $line.EndsWith("/") -or $line.EndsWith("\")
            $name = $line.TrimEnd('/', '\', '*', '@', '=')
            if ($isDir) {
                $full = if ($isLocal) { $dirPath + $name + "\" } else { $dirPath + $name + "/" }
                $template = $script:wpfWindow.Resources["FolderGridTemplate"]
            } else {
                $full = $dirPath + $name
                $template = $script:wpfWindow.Resources["FileGridTemplate"]
            }
            
            $meta = if ($isLocal -and $script:localFileMeta[$name]) { $script:localFileMeta[$name] } else { "" }
            $item = New-Object System.Windows.Controls.ListBoxItem
            $item.Content = [PSCustomObject]@{ Name = $name; FullPath = $full; IsDir = $isDir; Meta = $meta; Thumb = $null; NoThumb = 'Visible' }
            $item.ContentTemplate = $template
            $item.Tag = $full
            
            if ($isLocal) {
                $ctx = $script:wpfWindow.Resources["TransferContextMenu"]
                if ($ctx) { $item.ContextMenu = $ctx }
                
                # Kick off async thumbnail generation
                Load-ThumbnailAsync $item $full $name $isDir $meta
            }
            
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

