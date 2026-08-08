[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

try {
    Write-Host "Starting MSIX Signing Process..." -ForegroundColor Cyan

    $msixPath = Join-Path $PSScriptRoot "DeX.msix"
    if (-not (Test-Path $msixPath)) {
        throw "Target MSIX package not found at: $msixPath"
    }

    $pfxPath = Join-Path $PSScriptRoot "CodeDeX.pfx"
    if (-not (Test-Path $pfxPath)) {
        Write-Host "Generating new CodeDeX developer certificate..." -ForegroundColor Yellow
        $cert = New-SelfSignedCertificate -Type Custom -Subject "CN=CodeDeX" -KeyUsage DigitalSignature -FriendlyName "CodeDeX Developer Cert" -CertStoreLocation "Cert:\CurrentUser\My" -TextExtension @("2.5.29.37={text}1.3.6.1.5.5.7.3.3", "2.5.29.19={text}")
        $pwd = ConvertTo-SecureString -String "1234" -Force -AsPlainText
        Export-PfxCertificate -Cert $cert -FilePath $pfxPath -Password $pwd
        Export-Certificate -Cert $cert -FilePath (Join-Path $PSScriptRoot "CodeDeX.cer")
        Write-Host "Certificate generated successfully." -ForegroundColor Green
    }

    # robustly find signtool.exe
    $sdkPaths = @(
        "C:\Program Files (x86)\Windows Kits\10\bin\*\x64\signtool.exe",
        "C:\Program Files\Windows Kits\10\bin\*\x64\signtool.exe"
    )
    $signtool = $null
    foreach ($path in $sdkPaths) {
        $signtool = (Get-ChildItem $path -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1).FullName
        if ($signtool) { break }
    }

    if (-not $signtool) { 
        throw "signtool.exe not found. Please install the Windows 10/11 SDK." 
    }

    Write-Host "Signing MSIX package..." -ForegroundColor Cyan
    & $signtool sign /fd SHA256 /a /f $pfxPath /p "1234" $msixPath
    if ($LASTEXITCODE -ne 0) { 
        throw "signtool sign failed (exit code $LASTEXITCODE)." 
    }

    # ── Verify the signature before shipping ──
    Write-Host "Verifying signature..." -ForegroundColor Cyan
    & $signtool verify /pa $msixPath
    if ($LASTEXITCODE -ne 0) { 
        throw "Signature verification FAILED - do not distribute this MSIX." 
    }
    
    Write-Host "Signature verified OK. Ready for distribution." -ForegroundColor Green
}
catch {
    Write-Host "`n[ERROR] SignMSIX.ps1 failed:" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    exit 1
}
