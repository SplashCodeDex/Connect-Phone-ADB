Add-Type -AssemblyName PresentationFramework
try {
    [System.Windows.Threading.Dispatcher]::PushFrame($null)
} catch {
    Write-Host "ERROR: $_"
}
