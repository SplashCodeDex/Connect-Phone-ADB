<#
.SYNOPSIS
    DeX - Core Engine & Tray Application
.DESCRIPTION
    Manages wireless ADB hotspot connections, provides a clean System Tray UI with Auto-Connect ON/OFF toggle,
    and handles Windows Task Scheduler integration.
#>

param(
    [switch]$Background,
    [switch]$ConnectOnly,
    [switch]$SelfTest
)

. "$PSScriptRoot\Modules\EngineUtils.ps1"
Import-Module "$PSScriptRoot\Modules\AdbManager.psm1" -Force
. "$PSScriptRoot\Modules\TaskScheduler.ps1"
. "$PSScriptRoot\Modules\UIComponents.ps1"
$mutexName = "Global\CodeDeX_DeX_Engine"
$script:showUiEvent = New-Object System.Threading.EventWaitHandle($false, [System.Threading.EventResetMode]::AutoReset, "Global\CodeDeX_DeX_ShowUI")
$script:engineMutex = New-Object System.Threading.Mutex($false, $mutexName)
if (-not $script:engineMutex.WaitOne(0, $false)) {
    if (-not $Background -and -not $SelfTest) { $script:showUiEvent.Set() | Out-Null }
    # Another instance is already running — trigger an immediate connection attempt
    $null = Invoke-AdbConnect
    exit
}

if ($PSScriptRoot -match "WindowsApps") {
    $global:AdbExePath = "DeX-adb.exe"
} else {
    $global:AdbExePath = "$PSScriptRoot\adb.exe"
}

# Force STA Mode Threading for Windows Forms & Tray Icons
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName PresentationFramework

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$env:ADB_MDNS_OPENSCREEN = 1
$TaskName = "AutoConnectADB_Hotspot"
$ScriptPath = $PSCommandPath

# If called for ConnectOnly (e.g. from background Task Scheduler trigger)
if ($ConnectOnly) {
    $res = Invoke-AdbConnect
    exit
}

# Check Task Scheduler Auto-Connect status


# Create System Tray Icon
$script:notifyIcon = New-Object System.Windows.Forms.NotifyIcon
$script:notifyIcon.Text = "Connect ADB: Initializing..."


$iconGreen = Create-StatusIcon ([System.Drawing.Color]::FromArgb(0, 230, 118))
$iconYellow = Create-StatusIcon ([System.Drawing.Color]::FromArgb(255, 214, 0))
$iconRed = Create-StatusIcon ([System.Drawing.Color]::FromArgb(255, 23, 68))

$script:notifyIcon.Icon = $iconYellow
$script:notifyIcon.Visible = $true


# Spatial UI WPF Overlay
    $xamlFile = Join-Path $PSScriptRoot "..\Themes\MainWindow.xaml"
    $xamlRaw = [System.IO.File]::ReadAllText($xamlFile)
    $needle = "`$(`$PSScriptRoot -replace '\\', '/')"
    $binFwd = $PSScriptRoot -replace '\\', '/'
    $xaml = $xamlRaw.Replace($needle, $binFwd)

# Fail fast: if the XAML fails to parse/load, $script:wpfWindow stays null and the tray icon
# would keep running as a zombie that silently ignores every click. Exit loudly instead.
try {
    $reader = New-Object System.Xml.XmlNodeReader ([xml]$xaml)
    $script:wpfWindow = [System.Windows.Markup.XamlReader]::Load($reader)
    if ($null -eq $script:wpfWindow) { throw "XamlReader returned a null window." }
    $reader.Close()
} catch {
    $script:wpfWindow = $null
    $script:WindowLoadError = $_.Exception.Message
}

# Never-dead tray: if the spatial UI fails to load, degrade to a minimal WinForms
# fallback menu so core ADB features keep working instead of a silent zombie icon.
if ($null -eq $script:wpfWindow) {
    if ($SelfTest) {
        Write-Output "SELFTEST FATAL: $script:WindowLoadError"
        $script:notifyIcon.Visible = $false
        $script:notifyIcon.Dispose()
        exit 1
    }
    [System.Windows.MessageBox]::Show("DeX could not load its spatial interface and is running in fallback mode.`n`n$script:WindowLoadError", "DeX - Fallback Mode", 'OK', 'Warning') | Out-Null

    $script:notifyIcon.Text = "Connect ADB (Fallback Mode)"
    $fallbackMenu = New-Object System.Windows.Forms.ContextMenuStrip

    $miConnect = $fallbackMenu.Items.Add("Connect ADB Now")
    $miConnect.Add_Click({
        $res = Invoke-AdbConnect
        if ($res.Success) {
            $script:notifyIcon.Icon = $iconGreen
            $script:notifyIcon.Text = "Connected: $($res.Name)"
            Show-Toast -Title "ADB Connected" -Message "Successfully connected to $($res.Name)"
        } else {
            $script:notifyIcon.Icon = $iconRed
            $script:notifyIcon.Text = "Disconnected"
            Show-Toast -Title "Connection Failed" -Message $res.Message
        }
    })

    $miAuto = $fallbackMenu.Items.Add("Auto-Connect on Hotspot")
    $miAuto.Checked = Get-AutoConnectStatus
    $miAuto.CheckOnClick = $true
    $miAuto.Add_Click({
        Set-AutoConnectStatus -Enable (-not (Get-AutoConnectStatus))
        $miAuto.Checked = Get-AutoConnectStatus
        Show-Toast -Title "Auto-Connect" -Message $(if ($miAuto.Checked) { "Enabled - will connect when PC joins phone hotspot." } else { "Disabled." })
    })

    $miExit = $fallbackMenu.Items.Add("Exit Engine")
    $miExit.Add_Click({
        $script:notifyIcon.Visible = $false
        $script:notifyIcon.Dispose()
        [System.Windows.Forms.Application]::Exit()
    })

    $script:notifyIcon.ContextMenuStrip = $fallbackMenu
    [System.Windows.Forms.Application]::Run()
    exit
}

$themeFile = Join-Path $env:LOCALAPPDATA "DeX\theme.json"
if (Test-Path $themeFile) {
    try {
        $cfg = Get-Content $themeFile -Raw | ConvertFrom-Json
        $global:CurrentTheme = $cfg.CurrentTheme
        $global:AppThemeMode = $cfg.AppThemeMode
    } catch {}
}
if (-not $global:CurrentTheme) { $global:CurrentTheme = "DarkTheme" }
if (-not $global:AppThemeMode) { $global:AppThemeMode = "System" }

if ($global:AppThemeMode -eq "System") {
    Set-AppTheme (Get-SystemTheme)
} else {
    Set-AppTheme $global:CurrentTheme
}
[Microsoft.Win32.SystemEvents]::add_UserPreferenceChanged({
    param($sender, $e)
    if ($global:AppThemeMode -eq "System") {
        $t = Get-SystemTheme
        if ($global:CurrentTheme -ne $t) { Set-AppTheme $t }
    }
})

    # Load UI Bindings in current scope
    . "$PSScriptRoot\TrayUIBindings.ps1"
# Passive sync initial state on startup
$script:AutoConnectEnabled = Get-AutoConnectStatus
Update-WpfUI

if ($SelfTest) {
    # Headless self-diagnostics: prove the full tray-click -> window-show pipeline works end to end.
    # Used by CI (Validate Build workflow) and can be run locally: Connect-Engine.ps1 -SelfTest
    $stWindowCreated = ($null -ne $script:wpfWindow)
    $stTrayVisible = [bool]$script:notifyIcon.Visible
    $stShown = $false
    try {
        $eArgs = New-Object System.Windows.Forms.MouseEventArgs([System.Windows.Forms.MouseButtons]::Left, 1, 0, 0, 0)
        $invokeArgs = [Array]::CreateInstance([object], 1)
        $invokeArgs.SetValue($eArgs, 0)
        $script:notifyIcon.GetType().GetMethod('OnMouseUp', [System.Reflection.BindingFlags]'NonPublic,Instance').Invoke($script:notifyIcon, $invokeArgs)
        
        # Give the Dispatcher.BeginInvoke time to execute the Show()
        $waitCount = 0
        while (-not $script:wpfWindow.IsVisible -and $waitCount -lt 20) {
            $frame = New-Object System.Windows.Threading.DispatcherFrame
            $script:wpfWindow.Dispatcher.BeginInvoke([System.Windows.Threading.DispatcherPriority]::SystemIdle, [Action]{ $frame.Continue = $false }) | Out-Null
            [System.Windows.Threading.Dispatcher]::PushFrame($frame)
            Start-Sleep -Milliseconds 50
            $waitCount++
        }
        
        $stShown = [bool]$script:wpfWindow.IsVisible
    } catch {
        Write-Output "SELFTEST EXCEPTION: $($_.Exception.ToString())"
    }
    $stOk = $stWindowCreated -and $stTrayVisible -and $stShown
    Write-Output ("SELFTEST WindowCreated={0} TrayVisible={1} WindowShownAfterTrayClick={2}" -f $stWindowCreated, $stTrayVisible, $stShown)
    if ($script:wpfWindow.IsVisible) { $script:wpfWindow.Hide() }
    $script:notifyIcon.Visible = $false
    $script:notifyIcon.Dispose()
    exit $(if ($stOk) { 0 } else { 1 })
}

# Fix MSIX Version Path Drift: Re-register the task if already enabled so the path points to the new updated folder
if ($script:AutoConnectEnabled) {
    Set-AutoConnectStatus -Enable $true
}

# Transfer notifications queue (file received events from C# LocalSendServer)
$script:transferQueue = [System.Collections.Concurrent.ConcurrentQueue[object]]::new()
$script:mdnsQueue = [System.Collections.Concurrent.ConcurrentQueue[object]]::new()

# Start mDNS & Omni-Mesh auto-discovery
$script:mdnsJob = $null
$script:omniPeers = @{}



$script:mdnsJob = Start-MdnsDiscovery -Queue $script:mdnsQueue

$mdnsTimer = New-Object System.Windows.Threading.DispatcherTimer
$mdnsTimer.Interval = [TimeSpan]::FromSeconds(2)
$mdnsTimer.Add_Tick({
    # 1. Check Transfer Server Job
        $t = $null
        while ($script:transferQueue.TryDequeue([ref]$t)) {
            if ($t.Type -eq 'TransferComplete') {
                Show-Toast -Title "File Received" -Message "Saved to: $($t.File)"
                $fe = $script:wpfWindow.FindName("FileExplorer")
                if ($fe -and $fe.Visibility -eq 'Visible' -and $script:currentDirPath -match '^[A-Za-z]:\\') {
                    $script:wpfWindow.Dispatcher.InvokeAsync([Action]{ Load-Directory $script:currentDirPath }) | Out-Null
                }
            } elseif ($t.Type -eq 'Error') {
                Write-Trace $t.Message
            }
        }
        
        # 2. Check Discovery Job
        $received = @()
        $m = $null
        while ($script:mdnsQueue.TryDequeue([ref]$m)) {
            $received += $m
        }
        
        if ($received.Count -gt 0) {
            $uniqueServices = $received | Sort-Object -Property Type, IPPort -Unique
                
                # Check for Pairing
                $pairingTargets = $uniqueServices | Where-Object { $_.Type -eq 'Pairing' } | Select-Object -ExpandProperty IPPort
                foreach ($pt in $pairingTargets) {
                    Write-Trace "mDNS Poller found Pairing Target: $pt"
                    if (-not $script:pairedHistory) { $script:pairedHistory = @{} }
                    if (-not $script:pairedHistory[$pt]) {
                        $pin = Show-PairingPrompt -IPPort $pt
                        if ($pin) {
                            $success = Invoke-AdbPair -Target $pt -Pin $pin
                            if ($success) { $script:pairedHistory[$pt] = $true }
                        } else {
                            $script:pairedHistory[$pt] = $true
                        }
                    }
                }

                # Check for Connect
                $connectTargets = $uniqueServices | Where-Object { $_.Type -eq 'Connect' } | Select-Object -ExpandProperty IPPort
                foreach ($ct in $connectTargets) {
                    Write-Trace "mDNS Poller found Connect Target: $ct"
                    if ($script:currentTarget -ne $ct) {
                        Invoke-AdbConnect -Target $ct
                    }
                }
                
                # Check for OmniMesh
                $omniTargets = $uniqueServices | Where-Object { $_.Type -eq 'OmniMesh' }
                foreach ($omni in $omniTargets) {
                    $ip = $omni.IPPort -replace ':[0-9]+$',''
                    $existing = $script:omniPeers[$ip]
                    $trustLevel = if ($omni.IdentityHash -and $omni.IdentityHash -eq "dex_static_placeholder_hash_123") { "Auto-Trusted" } else { "Guest" }
                    $script:omniPeers[$ip] = @{
                        Name         = $omni.Name
                        LastSeen     = Get-Date
                        Type         = $omni.DeviceType
                        Model        = if ($omni.Model)   { $omni.Model }   elseif ($existing) { $existing.Model }   else { $null }
                        Battery      = if ($existing) { $existing.Battery } else { $null }
                        TelemetryAge = if ($existing) { $existing.TelemetryAge } else { [datetime]::MinValue }
                        TrustLevel   = $trustLevel
                    }
                }
                
                # Update Live Peers dynamically via ItemsControl (infinite scrolling rows)
                $livePeers = @()
                foreach ($ip in $script:omniPeers.Keys) {
                    $peer = $script:omniPeers[$ip]
                    if ((Get-Date) - $peer.LastSeen -lt [timespan]::FromSeconds(15)) {
                        
                        # Stale telemetry refresh: re-query battery if >60s old and device is the active ADB target
                        $connectedIP = ($script:currentTarget -replace ':.*','')
                        if ($ip -eq $connectedIP -and
                            $peer.TelemetryAge -and
                            (Get-Date) - $peer.TelemetryAge -gt [timespan]::FromSeconds(60)) {
                            try {
                                $batLine = (& $global:AdbExePath -s "${ip}:5555" shell dumpsys battery 2>$null) |
                                           Where-Object { $_ -match '^\s*level:' } | Select-Object -First 1
                                if ($batLine -match '(\d+)') {
                                    $peer.Battery      = $matches[1]
                                    $peer.TelemetryAge = Get-Date
                                }
                            } catch {}
                        }
                        
                        $subText = if ($peer.Model -and $peer.Battery) {
                            "$([char]0xE8EA) $($peer.Model)  $([char]0xE83F) $($peer.Battery)%"
                        } elseif ($peer.Model) {
                            "$([char]0xE8EA) $($peer.Model)"
                        } else {
                            "OmniMesh"
                        }
                        
                        $livePeers += @{
                            Name      = $peer.Name
                            SubText   = $subText
                            IconGlyph = "$([char]0xE8EA)"
                            IP        = $ip
                        }
                    }
                }
                
                $ic = $script:wpfWindow.FindName("icLivePeers")
                if ($ic) { $ic.ItemsSource = $livePeers }
                
            }

            # Poll Pairing Requests
            try {
                $pairReqs = Invoke-RestMethod -Uri "http://127.0.0.1:53318/local/pairing-requests" -TimeoutSec 1 -ErrorAction Stop
                if ($pairReqs -and $pairReqs.Count -gt 0) {
                    $req = $pairReqs[0]
                    # Show PIN UI overlay if not already showing
                    if ($script:wpfWindow.FindName("pinViewPanel").Visibility -ne 'Visible') {
                        $script:wpfWindow.FindName("txtPinTitle").Text = "Pairing Request"
                        $script:wpfWindow.FindName("txtPinSubtitle").Text = "from $($req.alias)"
                        $script:wpfWindow.FindName("txtPinCode").Text = $req.pin
                        $script:wpfWindow.FindName("txtPinStatus").Text = "Waiting for you to accept..."
                        
                        $script:wpfWindow.FindName("btnPinAccept").Visibility = 'Visible'
                        $script:wpfWindow.FindName("btnPinAcceptOnce").Visibility = 'Visible'
                        $btnPinCancel = $script:wpfWindow.FindName("btnPinCancel")
                        $btnPinCancel.Visibility = 'Visible'
                        $btnPinCancel.Content = "Cancel"
                        try { $script:wpfWindow.Dispatcher.Invoke({ $script:wpfWindow.FindName("menuViewsContainer").FindResource("SlideInPinAnim").Begin($script:wpfWindow) }) } catch {}
                        
                        $script:activePairRequest = $req
                    }
                }
            } catch { }

            # Poll robust UDP devices (LocalSendServer Gateway Unicast fallback)
            # This runs INDEPENDENTLY of mDNS — every tick, unconditionally.
            try {
                $udpRes = Invoke-RestMethod -Uri "http://127.0.0.1:53318/local/devices" -TimeoutSec 2 -ErrorAction Stop
                if ($udpRes) {
                    $icUdp = $script:wpfWindow.FindName("icUdpPeers")
                    if ($icUdp) {
                        $liveUdp = @()
                        $updatedLivePeers = $false
                        foreach ($p in $udpRes) {
                            $dt = [datetimeOffset]::FromUnixTimeMilliseconds($p.lastSeen).UtcDateTime
                            if (([datetime]::UtcNow) - $dt -lt [timespan]::FromSeconds(30)) {
                                if ($p.isPaired -or $p.isAutoTrusted) {
                                    if (-not $script:omniPeers.Contains($p.ip)) {
                                        $livePeers += @{
                                            Name      = $p.info.alias
                                            SubText   = "$([char]0xE8EA) $($p.info.deviceModel)"
                                            IconGlyph = "$([char]0xE8EA)"
                                            IP        = $p.ip
                                        }
                                        $updatedLivePeers = $true
                                    }
                                } else {
                                    if (-not $script:omniPeers.Contains($p.ip)) {
                                        $liveUdp += @{
                                            Ip = $p.ip
                                            Alias = $p.info.alias
                                            DeviceModel = $p.info.deviceModel
                                            DeviceType = $p.info.deviceType
                                            Fingerprint = $p.info.fingerprint
                                        }
                                    }
                                }
                            }
                        }
                        
                        if ($updatedLivePeers) {
                            $ic = $script:wpfWindow.FindName("icLivePeers")
                            if ($ic) { $ic.ItemsSource = $livePeers }
                        }
                        
                        # Only update UI when the device set actually changes (prevents re-triggering Loaded animation)
                        $newFingerprint = ($liveUdp | ForEach-Object { "$($_['Ip']):$($_['Alias'])" } | Sort-Object) -join ','
                        if ($newFingerprint -ne $script:lastUdpFingerprint) {
                            $icUdp.ItemsSource = $liveUdp
                            $script:lastUdpFingerprint = $newFingerprint
                        }
                    }
                }
            } catch { }
    })
    $mdnsTimer.Start()

if ($Background) {
    Show-Toast -Title "Connect ADB Active" -Message "Right-click tray icon to toggle Auto-Connect ON/OFF or Connect Now."
}

$uiTimer = New-Object System.Windows.Threading.DispatcherTimer
$uiTimer.Interval = [TimeSpan]::FromMilliseconds(150)
$uiTimer.Add_Tick({
    if ($script:showUiEvent.WaitOne(0)) {
        if ($script:wpfWindow.IsVisible) {
            $script:wpfWindow.Topmost = $true
            $script:wpfWindow.Activate()
            $script:wpfWindow.Focus()
        } else {
            $eArgs = New-Object System.Windows.Forms.MouseEventArgs([System.Windows.Forms.MouseButtons]::Left, 1, 0, 0, 0)
            $invokeArgs = [Array]::CreateInstance([object], 1)
            $invokeArgs.SetValue($eArgs, 0)
            $script:notifyIcon.GetType().GetMethod('OnMouseUp', [System.Reflection.BindingFlags]'NonPublic,Instance').Invoke($script:notifyIcon, $invokeArgs)
        }
    }
})
$uiTimer.Start()
if (-not $Background -and -not $SelfTest) { $script:showUiEvent.Set() | Out-Null }

[System.Windows.Forms.Application]::add_ApplicationExit({
    if ($script:mdnsJob -and $script:mdnsJob.PowerShell) {
        Write-Trace "Disposing mDNS Runspace..."
        $script:mdnsJob.PowerShell.Dispose()
    }
    # Transfer server is hosted by DeXShareTarget.exe (C# LocalSendServer) — no PS runspace to dispose
})

[System.Windows.Forms.Application]::Run()




