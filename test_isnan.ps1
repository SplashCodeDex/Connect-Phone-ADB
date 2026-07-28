try {
    [double]::IsNaN($null)
    Write-Host "Success"
} catch {
    Write-Host "Error: $($_.Exception.Message)"
}
