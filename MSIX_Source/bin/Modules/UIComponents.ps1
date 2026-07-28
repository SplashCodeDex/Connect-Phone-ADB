
function Create-StatusIcon([System.Drawing.Color]$Color) {
    $iconPath = Join-Path $PSScriptRoot "app-icon.ico"
    if (Test-Path $iconPath) {
        $baseIcon = [System.Drawing.Icon]::ExtractAssociatedIcon($iconPath)
        $bmp = $baseIcon.ToBitmap()
        $g = [System.Drawing.Graphics]::FromImage($bmp)
        $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        
        # Overlay a colored status indicator dot in the bottom right corner
        $brushBorder = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::Black)
        $g.FillEllipse($brushBorder, 18, 18, 12, 12)
        $brushStatus = New-Object System.Drawing.SolidBrush($Color)
        $g.FillEllipse($brushStatus, 20, 20, 8, 8)
        
        $hIcon = $bmp.GetHicon()
        $icon = [System.Drawing.Icon]::FromHandle($hIcon)
        $g.Dispose()
        $bmp.Dispose()
        $baseIcon.Dispose()
        return $icon
    } else {
        $bmp = New-Object System.Drawing.Bitmap(16, 16)
        $g = [System.Drawing.Graphics]::FromImage($bmp)
        $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $brushBg = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(25, 25, 35))
        $g.FillEllipse($brushBg, 0, 0, 15, 15)
        $brushStatus = New-Object System.Drawing.SolidBrush($Color)
        $g.FillEllipse($brushStatus, 3, 3, 10, 10)
        $hIcon = $bmp.GetHicon()
        $icon = [System.Drawing.Icon]::FromHandle($hIcon)
        $g.Dispose()
        $bmp.Dispose()
        return $icon
    }
}
#Export-ModuleMember -Function Create-StatusIcon

function Show-Toast {
    param([string]$Title, [string]$Message)
    try {
        [Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime] | Out-Null
        [Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom, ContentType = WindowsRuntime] | Out-Null
        $escTitle = [System.Security.SecurityElement]::Escape($Title)
        $escMsg = [System.Security.SecurityElement]::Escape($Message)
        $xmlString = @"
<toast>
  <visual>
    <binding template="ToastGeneric">
      <text>$escTitle</text>
      <text>$escMsg</text>
      <image placement="appLogoOverride" hint-crop="none" src="file:///$($PSScriptRoot -replace '\\', '/')/app-icon.ico"/>
    </binding>
  </visual>
</toast>
"@
        $xml = New-Object Windows.Data.Xml.Dom.XmlDocument
        $xml.LoadXml($xmlString)
        $toast = [Windows.UI.Notifications.ToastNotification]::new($xml)
        $notifier = [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier("Connect ADB")
        $notifier.Show($toast)
    } catch {}
}
#Export-ModuleMember -Function Show-Toast

function Set-AppTheme {
    param([string]$ThemeName)
    $themePath = Join-Path $PSScriptRoot "..\Themes\$ThemeName.xaml"
    if (Test-Path $themePath) {
        $xmlReader = [System.Xml.XmlReader]::Create($themePath)
        $resourceDict = [System.Windows.Markup.XamlReader]::Load($xmlReader)
        $script:wpfWindow.Resources.MergedDictionaries.Clear()
        $script:wpfWindow.Resources.MergedDictionaries.Add($resourceDict)
        $xmlReader.Close()
        $global:CurrentTheme = $ThemeName
    }
}
#Export-ModuleMember -Function Set-AppTheme

function Get-SystemTheme {
    try {
        $regKey = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize"
        $val = Get-ItemPropertyValue -Path $regKey -Name "AppsUseLightTheme" -ErrorAction SilentlyContinue
        if ($val -eq 1) { return "LightTheme" }
    } catch {}
    return "DarkTheme"
}
#Export-ModuleMember -Function Get-SystemTheme

function Show-DownloadDockToast([string]$pathText) {
    $dock = $script:wpfWindow.FindName("dockDownloadToast")
    $txt = $script:wpfWindow.FindName("txtDownloadToast")
    if ($null -ne $dock -and $null -ne $txt) {
        # Edge Case 23: Truncate long path text with middle ellipsis while preserving full path in ToolTip
        $dispText = $pathText
        if ($dispText.Length -gt 35) {
            $dispText = $dispText.Substring(0, 15) + "..." + $dispText.Substring($dispText.Length - 15)
        }
        $txt.Text = "Saved to $dispText"
        $txt.ToolTip = $pathText
        $dock.Visibility = 'Visible'
        
        $tg = $dock.RenderTransform
        $dockScale = $null
        $dockTrans = $null
        if ($tg -is [System.Windows.Media.TransformGroup]) {
            $dockScale = $tg.Children[0]
            $dockTrans = $tg.Children[1]
        }
        
        # Bouncy BackEase overshoot for dynamic spring entrance
        $bouncyEase = New-Object System.Windows.Media.Animation.BackEase
        $bouncyEase.Amplitude = 0.6
        $bouncyEase.EasingMode = [System.Windows.Media.Animation.EasingMode]::EaseOut
        
        $daOp = New-Object System.Windows.Media.Animation.DoubleAnimation
        $daOp.To = 1.0
        $daOp.Duration = [TimeSpan]::FromSeconds(0.25)
        $dock.BeginAnimation([System.Windows.UIElement]::OpacityProperty, $daOp)
        
        if ($null -ne $dockTrans) {
            $daY = New-Object System.Windows.Media.Animation.DoubleAnimation
            $daY.To = 0.0
            $daY.Duration = [TimeSpan]::FromSeconds(0.45)
            $daY.EasingFunction = $bouncyEase
            $dockTrans.BeginAnimation([System.Windows.Media.TranslateTransform]::YProperty, $daY)
        }
        if ($null -ne $dockScale) {
            $daS = New-Object System.Windows.Media.Animation.DoubleAnimation
            $daS.To = 1.0
            $daS.Duration = [TimeSpan]::FromSeconds(0.45)
            $daS.EasingFunction = $bouncyEase
            $dockScale.BeginAnimation([System.Windows.Media.ScaleTransform]::ScaleXProperty, $daS)
            $dockScale.BeginAnimation([System.Windows.Media.ScaleTransform]::ScaleYProperty, $daS)
        }
        
        if ($null -ne $script:dockTimer) { $script:dockTimer.Stop() }
        $script:dockTimer = New-Object System.Windows.Threading.DispatcherTimer
        $script:dockTimer.Interval = [TimeSpan]::FromSeconds(4)
        $script:dockTimer.Add_Tick({
            $script:dockTimer.Stop()
            
            $easeIn = New-Object System.Windows.Media.Animation.CubicEase
            $easeIn.EasingMode = [System.Windows.Media.Animation.EasingMode]::EaseIn
            
            $fadeOut = New-Object System.Windows.Media.Animation.DoubleAnimation
            $fadeOut.To = 0.0
            $fadeOut.Duration = [TimeSpan]::FromSeconds(0.35)
            $fadeOut.EasingFunction = $easeIn
            $fadeOut.Add_Completed({
                $dock.Visibility = 'Collapsed'
            })
            
            $dock.BeginAnimation([System.Windows.UIElement]::OpacityProperty, $fadeOut)
            if ($null -ne $dockTrans) {
                $daYExit = New-Object System.Windows.Media.Animation.DoubleAnimation
                $daYExit.To = 25.0
                $daYExit.Duration = [TimeSpan]::FromSeconds(0.35)
                $daYExit.EasingFunction = $easeIn
                $dockTrans.BeginAnimation([System.Windows.Media.TranslateTransform]::YProperty, $daYExit)
            }
            if ($null -ne $dockScale) {
                $daSExit = New-Object System.Windows.Media.Animation.DoubleAnimation
                $daSExit.To = 0.8
                $daSExit.Duration = [TimeSpan]::FromSeconds(0.35)
                $daSExit.EasingFunction = $easeIn
                $dockScale.BeginAnimation([System.Windows.Media.ScaleTransform]::ScaleXProperty, $daSExit)
                $dockScale.BeginAnimation([System.Windows.Media.ScaleTransform]::ScaleYProperty, $daSExit)
            }
        })
        
        # Edge Case 19: Pause auto-hide while mouse hovers over dock
        $dock.Add_MouseEnter({
            if ($null -ne $script:dockTimer) { $script:dockTimer.Stop() }
        })
        $dock.Add_MouseLeave({
            if ($null -ne $script:dockTimer) {
                $script:dockTimer.Stop()
                $script:dockTimer.Start()
            }
        })
        
        $script:dockTimer.Start()
    }
}
#Export-ModuleMember -Function Show-DownloadDockToast

function Invoke-MenuAction([scriptblock]$Action) {
    & $Action
}
#Export-ModuleMember -Function Invoke-MenuAction

function Update-WpfUI {
    param([string[]]$DevicesOutput)
    
    trap {
        Write-Trace "Update-WpfUI Trap: $($_.Exception.Message) at line $($_.InvocationInfo.ScriptLineNumber)"
        continue
    }
    
    if (-not $DevicesOutput) {
        $DevicesOutput = adb devices -l 2>&1
    }

    $brushConverter = New-Object System.Windows.Media.BrushConverter
    $qaAutoText = $script:wpfWindow.FindName("txtQAAuto")
    if ($null -ne $qaAutoText) {
        if ($script:AutoConnectEnabled) { 
            $qaAutoText.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, "SecondaryBrush")
        } else { 
            $qaAutoText.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, "PrimaryTextBrush")
        }
    }
    
    $connectedDevice = ($DevicesOutput | Where-Object { $_ -match ':5555\s+device' })
    if (-not $connectedDevice) { $connectedDevice = ($DevicesOutput | Where-Object { $_ -match '\bdevice\b' -and $_ -notmatch 'List of devices' }) }
    $connectedDevice = $connectedDevice | Select-Object -First 1

    if ($connectedDevice) {
        $target = $connectedDevice.Split()[0].Trim()
        $devName = $target
        if ($connectedDevice -match 'model:([^\s]+)') {
            $devName = $Matches[1] -replace '_', ' '
        }
        $script:currentTarget = $target
        $script:notifyIcon.Icon = $iconGreen
        $script:notifyIcon.Text = "Connected: $devName"
        $script:txtStatus.Text = "Connected: $devName"
        $script:wpfWindow.FindName("btnQAConnect").Visibility = 'Collapsed'
        $script:wpfWindow.FindName("btnQADisconnect").Visibility = 'Visible'
        $script:wpfWindow.FindName("btnCopyIP").Visibility = 'Visible'
    } else {
        $script:notifyIcon.Icon = $iconRed
        $script:notifyIcon.Text = "Disconnected"
        $script:txtStatus.Text = "Status: Disconnected"
        $script:wpfWindow.FindName("btnQAConnect").Visibility = 'Visible'
        $script:wpfWindow.FindName("btnQADisconnect").Visibility = 'Collapsed'
        $script:wpfWindow.FindName("btnCopyIP").Visibility = 'Collapsed'
    }
}
#Export-ModuleMember -Function Update-WpfUI

