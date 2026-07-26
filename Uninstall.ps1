Write-Host "Uninstalling Connect Phone ADB..." -ForegroundColor Cyan

# 1. Remove Task Scheduler
Unregister-ScheduledTask -TaskName "AutoConnectADB_Hotspot" -Confirm:$false -ErrorAction SilentlyContinue
Write-Host "Removed Task Scheduler background trigger." -ForegroundColor Green

# 2. Remove Registry Context Menus
$regFile = "HKCU:\Software\Classes\*\shell\SendToPhoneADB"
$regDir = "HKCU:\Software\Classes\Directory\shell\SendToPhoneADB"
if (Test-Path $regFile) { Remove-Item -Path $regFile -Recurse -Force -ErrorAction SilentlyContinue }
if (Test-Path $regDir) { Remove-Item -Path $regDir -Recurse -Force -ErrorAction SilentlyContinue }
Write-Host "Removed 'Send to Phone' context menus." -ForegroundColor Green

# 3. Remove Startup Run Key
$regRunPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
Remove-ItemProperty -Path $regRunPath -Name "ConnectPhoneADB" -ErrorAction SilentlyContinue
Write-Host "Removed Windows Startup entry." -ForegroundColor Green

# 4. Remove Shortcuts
$desktopPath = [Environment]::GetFolderPath("Desktop")
$startMenuPrograms = "C:\Users\NicoDex\AppData\Roaming\Microsoft\Windows\Start Menu\Programs"
Remove-Item -Path "$desktopPath\Connect Phone ADB.lnk" -Force -ErrorAction SilentlyContinue
Remove-Item -Path "$startMenuPrograms\Connect Phone ADB.lnk" -Force -ErrorAction SilentlyContinue
Write-Host "Removed Desktop and Start Menu shortcuts." -ForegroundColor Green

Write-Host "`nUninstall Complete!" -ForegroundColor Cyan
Write-Host "You can now safely delete the C:\Users\NicoDex\Connect-Phone-ADB folder." -ForegroundColor Yellow
Write-Host "Press any key to exit..."
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
