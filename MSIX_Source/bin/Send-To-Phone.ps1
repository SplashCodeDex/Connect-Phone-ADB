<#
.SYNOPSIS
    Connect Phone ADB - Send File or Folder to Phone
.DESCRIPTION
    Invoked via Explorer right-click context menu to wirelessly push files or folders to /sdcard/Download/.
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$FilePath,

    [string]$Destination = "/sdcard/Download/"
)

function adb { ConnectPhone-adb.exe @args }

Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue
Add-Type -AssemblyName System.Drawing -ErrorAction SilentlyContinue

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

function Show-Notification {
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
        $notifier = [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier("Connect Phone")
        $notifier.Show($toast)
        return $null
    } catch {
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue
        Add-Type -AssemblyName System.Drawing -ErrorAction SilentlyContinue
        $balloon = New-Object System.Windows.Forms.NotifyIcon
        $iconPath = Join-Path $PSScriptRoot "app-icon.ico"
        if (Test-Path $iconPath) {
            $balloon.Icon = [System.Drawing.Icon]::ExtractAssociatedIcon($iconPath)
        } else {
            $path = Get-Process -id $pid | Select-Object -ExpandProperty Path
            $balloon.Icon = [System.Drawing.Icon]::ExtractAssociatedIcon($path)
        }
        $balloon.BalloonTipIcon = [System.Windows.Forms.ToolTipIcon]::Info
        $balloon.BalloonTipText = $Message
        $balloon.BalloonTipTitle = $Title
        $balloon.Visible = $true
        $balloon.ShowBalloonTip(5000)
        return $balloon
    }
}

if (-not (Test-Path $FilePath)) {
    $b = Show-Notification -Title "Send to Phone Failed" -Message "File not found: $FilePath" -IconType Error
    Start-Sleep -Seconds 3
    if ($b) { $b.Dispose() }
    exit 1
}

$fileName = Split-Path $FilePath -Leaf

# Smart Destination Routing
$isContainer = (Get-Item $FilePath) -is [System.IO.DirectoryInfo]
if (-not $isContainer) {
    $ext = [System.IO.Path]::GetExtension($FilePath).ToLower()
    $audioExts = @('.mp3', '.flac', '.wav', '.m4a', '.ogg', '.aac')
    $videoExts = @('.mp4', '.mkv', '.avi', '.mov', '.webm', '.wmv')
    $imageExts = @('.jpg', '.jpeg', '.png', '.gif', '.webp', '.bmp')
    
    if ($audioExts -contains $ext) {
        $Destination = "/sdcard/Music/"
    } elseif ($videoExts -contains $ext) {
        $Destination = "/sdcard/Movies/"
    } elseif ($imageExts -contains $ext) {
        $Destination = "/sdcard/Pictures/"
    }
}

# Determine Gateway IP
$GatewayIP = (Get-NetRoute -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue | 
              Where-Object { $_.NextHop -ne '0.0.0.0' -and $_.NextHop -ne '::' } | 
              Select-Object -First 1 -ExpandProperty NextHop)

$targetDevice = $null
if ($GatewayIP) {
    $expectedTarget = "${GatewayIP}:5555"
    $devices = adb devices 2>&1
    if ($devices -match [regex]::Escape($expectedTarget) + "\s+device") {
        $targetDevice = $expectedTarget
    } else {
        # Not connected, try to connect
        $null = adb connect $expectedTarget 2>&1
        $devices = adb devices 2>&1
        if ($devices -match [regex]::Escape($expectedTarget) + "\s+device") {
            $targetDevice = $expectedTarget
        }
    }
}

if (-not $targetDevice) {
    # Fallback to any connected device
    $devices = adb devices 2>&1 | Where-Object { $_ -match "\tdevice$" }
    if ($devices) {
        $targetDevice = ($devices[0] -split "\t")[0]
    }
}

if (-not $targetDevice) {
    $b = Show-Notification -Title "Send to Phone Failed" -Message "Phone not connected over ADB/Hotspot."
    Start-Sleep -Seconds 3
    if ($b) { $b.Dispose() }
    exit 1
}

$b1 = Show-Notification -Title "Sending to Phone..." -Message "Transferring $fileName to $Destination"
$startTime = Get-Date
$pushOutput = adb -s $targetDevice push "$FilePath" "$Destination" 2>&1
$elapsed = [math]::Round(((Get-Date) - $startTime).TotalSeconds, 1)
if ($b1) { $b1.Dispose() }

if ($LASTEXITCODE -eq 0 -or $pushOutput -like "*pushed*") {
    $b2 = Show-Notification -Title "Sent to Phone!" -Message "Successfully pushed $fileName (${elapsed}s)"
} else {
    $b2 = Show-Notification -Title "Send to Phone Failed" -Message "Error pushing $fileName"
}
Start-Sleep -Seconds 4
if ($b2) { $b2.Dispose() }
