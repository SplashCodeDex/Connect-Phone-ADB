# Clean old shortcuts & create new Connect Phone ADB shortcuts

$WshShell = New-Object -ComObject WScript.Shell

# Remove old Start Menu folder if exists
$oldStartMenuDir = "C:\Users\NicoDex\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Antigravity ADB"
if (Test-Path $oldStartMenuDir) {
    Remove-Item -Path $oldStartMenuDir -Recurse -Force -ErrorAction SilentlyContinue
}

# Create Start Menu Shortcut
$startMenuPrograms = "C:\Users\NicoDex\AppData\Roaming\Microsoft\Windows\Start Menu\Programs"
$scStart = $WshShell.CreateShortcut("$startMenuPrograms\Connect Phone ADB.lnk")
$scStart.TargetPath = "wscript.exe"
$scStart.Arguments = "`"C:\Users\NicoDex\Connect-Phone-ADB\bin\Start-App.vbs`""
$scStart.Description = "Connect Phone ADB Software"
$scStart.IconLocation = "C:\ICO\yuzu-emu.ico"
$scStart.Save()

# Create Desktop Shortcut
$desktopPath = [Environment]::GetFolderPath("Desktop")
# Clean old desktop shortcut
$oldDesktopLnk = "$desktopPath\Antigravity ADB Manager.lnk"
if (Test-Path $oldDesktopLnk) {
    Remove-Item -Path $oldDesktopLnk -Force -ErrorAction SilentlyContinue
}

$scDesktop = $WshShell.CreateShortcut("$desktopPath\Connect Phone ADB.lnk")
$scDesktop.TargetPath = "wscript.exe"
$scDesktop.Arguments = "`"C:\Users\NicoDex\Connect-Phone-ADB\bin\Start-App.vbs`""
$scDesktop.Description = "Connect Phone ADB Software"
$scDesktop.IconLocation = "C:\ICO\yuzu-emu.ico"
$scDesktop.Save()

Write-Host "✅ Created Start Menu Shortcut: $startMenuPrograms\Connect Phone ADB.lnk" -ForegroundColor Green
Write-Host "✅ Created Desktop Shortcut: $desktopPath\Connect Phone ADB.lnk" -ForegroundColor Green
