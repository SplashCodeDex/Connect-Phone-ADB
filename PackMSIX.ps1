param([string]$Configuration = "Release")

# ── Enforce UTF-8 BOM on Engine (PS 5.1 requirement for non-ASCII chars) ──
$enginePath = Join-Path $PSScriptRoot "MSIX_Source\bin\Connect-Engine.ps1"
if (Test-Path $enginePath) {
    $engineBytes = [System.IO.File]::ReadAllBytes($enginePath)
    $hasBom = ($engineBytes.Length -ge 3 -and $engineBytes[0] -eq 0xEF -and $engineBytes[1] -eq 0xBB -and $engineBytes[2] -eq 0xBF)
    if (-not $hasBom) {
        Write-Host "Auto-fixing missing UTF-8 BOM on Connect-Engine.ps1..." -ForegroundColor Yellow
        $content = [System.IO.File]::ReadAllText($enginePath)
        $bom = [byte[]](0xEF, 0xBB, 0xBF)
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($content)
        [System.IO.File]::WriteAllBytes($enginePath, ($bom + $bytes))
    }
}

# ── Build Gate: refuse to pack broken sources (XAML/syntax/resource/asset checks) ──
$validator = Join-Path $PSScriptRoot "Validate-Build.ps1"
if (Test-Path $validator) {
    & $validator
    if ($LASTEXITCODE -ne 0) {
        Write-Host "`n[PACK ABORTED] Validate-Build failed. Fix the errors above first." -ForegroundColor Red
        exit 1
    }
    Write-Host ""
}

$ProjDir = Join-Path $PSScriptRoot "ConnectPhoneShareTarget"
Write-Host "Building C# Project ($Configuration)..."
Set-Location $ProjDir
dotnet build -c $Configuration
Set-Location $PSScriptRoot

$SourceDir = Join-Path $ProjDir "bin\$Configuration\net10.0-windows10.0.22000.0"
if (Test-Path $SourceDir) {
    Copy-Item -Path "$SourceDir\*" -Destination (Join-Path $PSScriptRoot "MSIX_Source") -Force -Recurse
}

# Sync Version from AppxManifest to AppInstaller
$ManifestPath = Join-Path $PSScriptRoot "MSIX_Source\AppxManifest.xml"
$InstallerPath = Join-Path $PSScriptRoot "ConnectPhoneADB.appinstaller"
if ((Test-Path $ManifestPath) -and (Test-Path $InstallerPath)) {
    [xml]$manifestXml = Get-Content $ManifestPath
    $version = $manifestXml.Package.Identity.Version
    
    [xml]$installerXml = Get-Content $InstallerPath
    $installerXml.AppInstaller.Version = $version
    $installerXml.AppInstaller.MainPackage.Version = $version
    $installerXml.Save($InstallerPath)
    Write-Host "Synced AppInstaller version to $version"
}

$makeappx = (Get-ChildItem "C:\Program Files (x86)\Windows Kits\10\bin\*\x64\makeappx.exe" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1).FullName
if (-not $makeappx) { throw "makeappx.exe not found. Please install the Windows 10/11 SDK." }

& $makeappx pack /d (Join-Path $PSScriptRoot "MSIX_Source") /p (Join-Path $PSScriptRoot "ConnectPhoneADB.msix") /o
if ($LASTEXITCODE -ne 0) { throw "makeappx pack failed (exit code $LASTEXITCODE)." }

# ── Post-pack verification: packaged engine must match the validated source byte-for-byte ──
Add-Type -AssemblyName System.IO.Compression.FileSystem
$msixPath = Join-Path $PSScriptRoot "ConnectPhoneADB.msix"
$zip = [System.IO.Compression.ZipFile]::OpenRead($msixPath)
try {
    $engineEntry = $zip.Entries | Where-Object { $_.FullName -eq 'bin/Connect-Engine.ps1' } | Select-Object -First 1
    if (-not $engineEntry) { throw "bin\Connect-Engine.ps1 is missing from the package." }
    $tmpEngine = Join-Path $env:TEMP "packaged-engine-verify.ps1"
    [System.IO.Compression.ZipFileExtensions]::ExtractToFile($engineEntry, $tmpEngine, $true)

    $manifestEntry = $zip.Entries | Where-Object { $_.FullName -eq 'AppxManifest.xml' } | Select-Object -First 1
    if (-not $manifestEntry) { throw "AppxManifest.xml is missing from the package." }
    $tmpManifest = Join-Path $env:TEMP "packaged-manifest-verify.xml"
    [System.IO.Compression.ZipFileExtensions]::ExtractToFile($manifestEntry, $tmpManifest, $true)
} finally {
    $zip.Dispose()
}
$srcHash = (Get-FileHash (Join-Path $PSScriptRoot "MSIX_Source\bin\Connect-Engine.ps1") -Algorithm SHA256).Hash
$pkgHash = (Get-FileHash $tmpEngine -Algorithm SHA256).Hash
if ($srcHash -ne $pkgHash) { throw "POST-PACK VERIFY FAILED: packaged Connect-Engine.ps1 differs from MSIX_Source (packaging corruption)." }
try { $null = [xml](Get-Content $tmpManifest -Raw) } catch { throw "POST-PACK VERIFY FAILED: packaged AppxManifest.xml is not well-formed." }
Remove-Item $tmpEngine, $tmpManifest -Force -ErrorAction SilentlyContinue
Write-Host "Post-pack verification passed (packaged engine matches source, manifest well-formed)." -ForegroundColor Green
