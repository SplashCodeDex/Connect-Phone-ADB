Continue = 'Stop'
Add-Type -AssemblyName PresentationFramework
$content = Get-Content MSIX_Source\bin\Connect-Engine.ps1 -Raw
$content = $content.Replace('[System.Windows.Forms.Application]::Run()', '
    Write-Output "TRIGGERING TRAY ICON..."
    $e = New-Object System.Windows.Forms.MouseEventArgs([System.Windows.Forms.MouseButtons]::Left, 1, 0, 0, 0)
    $script:notifyIcon.GetType().GetMethod("OnMouseUp", [System.Reflection.BindingFlags]"NonPublic, Instance").Invoke($script:notifyIcon, @( [object]$null, $e ))
    Write-Output "TRAY ICON TRIGGERED."
    Write-Output "WINDOW ISVISIBLE: $($script:wpfWindow.IsVisible)"
')
$content = $content.Replace('Global\CodeDeX_ConnectPhoneADB_Engine', 'Global\CodeDeX_ConnectPhoneADB_Engine_TEST')
$content = $content.Replace('ConnectPhoneADBTrayMutex', 'ConnectPhoneADBTrayMutex_TEST')

try {
    $env:PSScriptRoot = "W:\CodeDeX\Connect-Phone-ADB\MSIX_Source\bin"
    Invoke-Expression $content
} catch {
    Write-Output "ERROR: $($_.Exception.Message)"
}
