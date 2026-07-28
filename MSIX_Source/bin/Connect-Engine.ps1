<#
.SYNOPSIS
    Connect Phone ADB - Core Engine & Tray Application
.DESCRIPTION
    Manages wireless ADB hotspot connections, provides a clean System Tray UI with Auto-Connect ON/OFF toggle,
    and handles Windows Task Scheduler integration.
#>

param(
    [switch]$Background,
    [switch]$ConnectOnly,
    [switch]$SelfTest
)

Import-Module "$PSScriptRoot\Modules\EngineUtils.psm1" -Force
Import-Module "$PSScriptRoot\Modules\AdbManager.psm1" -Force
Import-Module "$PSScriptRoot\Modules\TaskScheduler.psm1" -Force
Import-Module "$PSScriptRoot\Modules\UIComponents.psm1" -Force
$mutexName = "Global\CodeDeX_ConnectPhoneADB_Engine"
$script:engineMutex = New-Object System.Threading.Mutex($false, $mutexName)
if (-not $script:engineMutex.WaitOne(0, $false)) {
    # Another instance is already running
    exit
}

if ($PSScriptRoot -match "WindowsApps") {
    $global:AdbExePath = "ConnectPhone-adb.exe"
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

# Function: Connect ADB to Gateway

# If called for ConnectOnly (e.g. from background Task Scheduler trigger)
if ($ConnectOnly) {
    $res = Invoke-AdbConnect
    exit
}

# Prevent multiple tray instances
$createdNew = $false
$script:trayMutex = New-Object System.Threading.Mutex($true, "ConnectPhoneADBTrayMutex", [ref]$createdNew)
if (-not $createdNew) {
    # If already running, trigger immediate connection check
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
    [System.Windows.MessageBox]::Show("Connect Phone ADB could not load its spatial interface and is running in fallback mode.`n`n$script:WindowLoadError", "Connect Phone ADB - Fallback Mode", 'OK', 'Warning') | Out-Null

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

$global:CurrentTheme = "DarkTheme"

Set-AppTheme (Get-SystemTheme)

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
        $stShown = [bool]$script:wpfWindow.IsVisible
    } catch {
        Write-Output "SELFTEST EXCEPTION: $($_.Exception.Message)"
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

# Start mDNS auto-discovery if Auto-Connect is enabled
$script:mdnsJob = $null
if ($script:AutoConnectEnabled) {
    $script:mdnsJob = Start-MdnsDiscovery
    
    $mdnsTimer = New-Object System.Windows.Threading.DispatcherTimer
    $mdnsTimer.Interval = [TimeSpan]::FromSeconds(5)
    $mdnsTimer.Add_Tick({
        if ($null -ne $script:mdnsJob) {
            $received = Receive-Job -Job $script:mdnsJob -Keep
            if ($received) {
                # Distinct by Type and IPPort
                $uniqueServices = $received | Sort-Object -Property Type, IPPort -Unique
                
                # Check for Pairing first
                $pairingTargets = $uniqueServices | Where-Object { $_.Type -eq 'Pairing' } | Select-Object -ExpandProperty IPPort
                foreach ($pt in $pairingTargets) {
                    Write-Trace "mDNS Poller found Pairing Target: $pt"
                    # Prevent endless prompts for the same IP
                    if (-not $script:pairedHistory) { $script:pairedHistory = @{} }
                    if (-not $script:pairedHistory[$pt]) {
                        $pin = Show-PairingPrompt -IPPort $pt
                        if ($pin) {
                            $success = Invoke-AdbPair -Target $pt -Pin $pin
                            if ($success) { $script:pairedHistory[$pt] = $true }
                        } else {
                            # User cancelled, don't ask again this session
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
                
                # Clear the job buffer so we don't re-process old ones endlessly
                Receive-Job -Job $script:mdnsJob | Out-Null
            }
        }
    })
    $mdnsTimer.Start()
}

Show-Toast -Title "Connect ADB Active" -Message "Right-click tray icon to toggle Auto-Connect ON/OFF or Connect Now."
[System.Windows.Forms.Application]::Run()
