param([string]$Configuration = "Release")

$SourceDir = "W:\CodeDeX\Connect-Phone-ADB\ConnectPhoneShareTarget\bin\$Configuration\net10.0-windows10.0.19041.0"
if (Test-Path $SourceDir) {
    Copy-Item -Path "$SourceDir\*" -Destination "W:\CodeDeX\Connect-Phone-ADB\MSIX_Source\" -Force -Recurse
}

& "C:\Program Files (x86)\Windows Kits\10\bin\10.0.26100.0\x64\makeappx.exe" pack /d "W:\CodeDeX\Connect-Phone-ADB\MSIX_Source" /p "W:\CodeDeX\Connect-Phone-ADB\ConnectPhoneADB.msix" /o
