
try {
    $content = Get-Content MSIX_Source\bin\Connect-Engine.ps1 -Raw
    $content = $content.Replace('[System.Windows.Forms.Application]::Run()', 'Write-Host "REACHED END OF SCRIPT"')
    $content = $content.Replace('Global\CodeDeX_ConnectPhoneADB_Engine', 'Global\CodeDeX_ConnectPhoneADB_Engine_TEST')
    $content = $content.Replace('ConnectPhoneADBTrayMutex', 'ConnectPhoneADBTrayMutex_TEST')
    Invoke-Expression $content
} catch {
    Write-Host "ERROR: $($_.Exception.Message)"
}
