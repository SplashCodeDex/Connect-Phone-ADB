Add-Type -AssemblyName System.Drawing
try {
    $icon = [System.Drawing.Icon]::ExtractAssociatedIcon("C:\ICO\yuzu-emu.ico")
    $bmp = $icon.ToBitmap()
    Write-Host "ExtractAssociatedIcon WORKED!"
    exit 0
} catch {
    Write-Host "ExtractAssociatedIcon FAILED: $_"
    exit 1
}
