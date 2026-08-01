$pfxPath = Join-Path $PSScriptRoot "CodeDeX.pfx"
if (-not (Test-Path $pfxPath)) {
    $cert = New-SelfSignedCertificate -Type Custom -Subject "CN=CodeDeX" -KeyUsage DigitalSignature -FriendlyName "CodeDeX Developer Cert" -CertStoreLocation "Cert:\CurrentUser\My" -TextExtension @("2.5.29.37={text}1.3.6.1.5.5.7.3.3", "2.5.29.19={text}")
    $pwd = ConvertTo-SecureString -String "1234" -Force -AsPlainText
    Export-PfxCertificate -Cert $cert -FilePath $pfxPath -Password $pwd
    Export-Certificate -Cert $cert -FilePath (Join-Path $PSScriptRoot "CodeDeX.cer")
}

$signtool = (Get-ChildItem "C:\Program Files (x86)\Windows Kits\10\bin\*\x64\signtool.exe" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1).FullName
if (-not $signtool) { throw "signtool.exe not found. Please install the Windows 10/11 SDK." }

& $signtool sign /fd SHA256 /a /f (Join-Path $PSScriptRoot "CodeDeX.pfx") /p "1234" (Join-Path $PSScriptRoot "DeX.msix")
if ($LASTEXITCODE -ne 0) { throw "signtool sign failed (exit code $LASTEXITCODE)." }

# ── Verify the signature before shipping ──
& $signtool verify /pa (Join-Path $PSScriptRoot "DeX.msix")
if ($LASTEXITCODE -ne 0) { throw "Signature verification FAILED - do not distribute this MSIX." }
Write-Host "Signature verified OK." -ForegroundColor Green
