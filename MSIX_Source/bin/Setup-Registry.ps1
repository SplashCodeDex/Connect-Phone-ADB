<#
.SYNOPSIS
    Connect Phone ADB - Clean Registry Setup
.DESCRIPTION
    Removes old APK context menu keys and registers ONLY 'Send to Phone' context menu items.
#>

Write-Host "====================================================" -ForegroundColor Cyan
Write-Host " Cleaning Registry & Installing 'Send to Phone'" -ForegroundColor Cyan
Write-Host "====================================================" -ForegroundColor Cyan

# 1. Clean old keys completely
$keysToRemove = @(
    "HKCU:\Software\Classes\.apk\shell\ADBInstall",
    "HKCU:\Software\Classes\.xapk\shell\ADBInstall",
    "HKCU:\Software\Classes\.apks\shell\ADBInstall",
    "HKCU:\Software\Classes\SystemFileAssociations\.apk\shell\ADBInstall",
    "HKCU:\Software\Classes\SystemFileAssociations\.xapk\shell\ADBInstall",
    "HKCU:\Software\Classes\SystemFileAssociations\.apks\shell\ADBInstall",
    "HKCU:\Software\Classes\*\shell\ADBPush",
    "HKCU:\Software\Classes\Directory\shell\ADBPush"
)

foreach ($key in $keysToRemove) {
    if (Test-Path $key) {
        Remove-Item -Path $key -Recurse -Force -ErrorAction SilentlyContinue
        Write-Host "  Removed old key: $key" -ForegroundColor Gray
    }
}

$sendScriptPath = "C:\Users\NicoDex\Connect-Phone-ADB\bin\Send-To-Phone.ps1"

# 2. Register File Right-Click "Send to Phone"
$fileKeyPath = "HKCU:\Software\Classes\*\shell\SendToPhone"
$fileCmdPath = "$fileKeyPath\command"

New-Item -Path $fileKeyPath -Force | Out-Null
Set-ItemProperty -Path $fileKeyPath -Name "(default)" -Value "Send to Phone"
New-Item -Path $fileCmdPath -Force | Out-Null
Set-ItemProperty -Path $fileCmdPath -Name "(default)" -Value "powershell.exe -ExecutionPolicy Bypass -NoProfile -File `"$sendScriptPath`" -FilePath `"%1`""

Write-Host "  Registered File Context Menu: 'Send to Phone'" -ForegroundColor Green

# 3. Register Folder Right-Click "Send Folder to Phone"
$dirKeyPath = "HKCU:\Software\Classes\Directory\shell\SendToPhone"
$dirCmdPath = "$dirKeyPath\command"

New-Item -Path $dirKeyPath -Force | Out-Null
Set-ItemProperty -Path $dirKeyPath -Name "(default)" -Value "Send Folder to Phone"
New-Item -Path $dirCmdPath -Force | Out-Null
Set-ItemProperty -Path $dirCmdPath -Name "(default)" -Value "powershell.exe -ExecutionPolicy Bypass -NoProfile -File `"$sendScriptPath`" -FilePath `"%1`""

Write-Host "  Registered Folder Context Menu: 'Send Folder to Phone'" -ForegroundColor Green

Write-Host "`nSUCCESS! Explorer context menu cleaned & updated!" -ForegroundColor Green
