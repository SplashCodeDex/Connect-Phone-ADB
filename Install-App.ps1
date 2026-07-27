# Requires Admin privileges to install to LocalMachine Root
if (-Not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Warning "Restarting script with Administrator privileges..."
    Start-Process pwsh -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    exit
}

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$CertPath = Join-Path $ScriptDir "CodeDeX.cer"
$AppPath = Join-Path $ScriptDir "ConnectPhoneADB.msix"

if (Test-Path $CertPath) {
    Write-Host "Installing Certificate to Trusted Root..."
    Import-Certificate -FilePath $CertPath -CertStoreLocation "Cert:\LocalMachine\Root" | Out-Null
    Write-Host "Certificate installed successfully."
} else {
    Write-Error "Could not find CodeDeX.cer in $ScriptDir"
}

if (Test-Path $AppPath) {
    Write-Host "Installing/Updating MSIX package..."
    Add-AppxPackage -Path $AppPath -ForceUpdateFromAnyVersion -ForceApplicationShutdown
    Write-Host "App installed/updated successfully."
} else {
    Write-Error "Could not find ConnectPhoneADB.msix in $ScriptDir"
}

Write-Host "Press any key to exit..."
$null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
