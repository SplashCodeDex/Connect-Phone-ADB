param([string]$Configuration = "Release")

$ProjDir = Join-Path $PSScriptRoot "ConnectPhoneShareTarget"
Write-Host "Building C# Project ($Configuration)..."
Set-Location $ProjDir
dotnet build -c $Configuration
Set-Location $PSScriptRoot

$SourceDir = Join-Path $ProjDir "bin\$Configuration\net10.0-windows10.0.22000.0"
if (Test-Path $SourceDir) {
    Copy-Item -Path "$SourceDir\*" -Destination (Join-Path $PSScriptRoot "MSIX_Source") -Force -Recurse
}

$makeappx = (Get-ChildItem "C:\Program Files (x86)\Windows Kits\10\bin\*\x64\makeappx.exe" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1).FullName
if (-not $makeappx) { throw "makeappx.exe not found. Please install the Windows 10/11 SDK." }

& $makeappx pack /d (Join-Path $PSScriptRoot "MSIX_Source") /p (Join-Path $PSScriptRoot "ConnectPhoneADB.msix") /o
