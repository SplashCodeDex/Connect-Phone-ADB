$w = $null
try {
    $w.Left = 12
    Write-Host "Success"
} catch {
    Write-Host "Error: $($_.Exception.Message)"
}
