try {
    $evt = New-Object System.Threading.EventWaitHandle($false, [System.Threading.EventResetMode]::AutoReset, "Global\CodeDeX_ConnectPhoneADB_ShowUI")
    Write-Host "Event created successfully!"
} catch {
    Write-Host "Error creating event: $_"
}
