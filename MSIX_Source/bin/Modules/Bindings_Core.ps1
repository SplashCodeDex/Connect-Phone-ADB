. "$PSScriptRoot\TrayUIHandlers.ps1"
$script:txtStatus = $script:wpfWindow.FindName("txtStatus")
$script:pnlAdbStatus = $script:wpfWindow.FindName("pnlAdbStatus")
$script:topActionsPanel = $script:wpfWindow.FindName("TopActionsPanel")
$script:txtQAAuto = $script:wpfWindow.FindName("txtQAAuto")

$script:lbFiles = $script:wpfWindow.FindName("lbFiles")



$ctxMenu = $script:wpfWindow.Resources["TransferContextMenu"]
if ($ctxMenu) {
    $ctxMenu.AddHandler([System.Windows.Controls.MenuItem]::ClickEvent, [System.Windows.RoutedEventHandler]{
        param($sender, $e)
        $menuItem = $e.OriginalSource
        $listBoxItem = $ctxMenu.PlacementTarget
        if ($null -eq $listBoxItem -or $listBoxItem -isnot [System.Windows.Controls.ListBoxItem]) { return }
        $path = $listBoxItem.Tag
        
        $dangerousExts = @('.exe','.bat','.cmd','.ps1','.vbs','.vbe','.msi','.scr','.com','.pif','.wsf')
        switch ($menuItem.Name) {
            "CtxOpen" {
                if (-not (Test-Path $path)) {
                    Show-DownloadDockToast "File is missing."
                    $script:lbFiles.Items.Remove($listBoxItem)
                    return
                }
                $ext = [System.IO.Path]::GetExtension($path).ToLower()
                if ($dangerousExts -contains $ext) {
                    Start-Process explorer.exe -ArgumentList "/select,"$path""
                } else {
                    Start-Process $path
                }
            }
            "CtxOpenFolder" {
                Start-Process explorer.exe -ArgumentList "/select,"$path""
            }
            "CtxCopyPath" {
                [System.Windows.Clipboard]::SetText($path)
            }
            "CtxDelete" {
                if (Test-Path $path) { Remove-Item -LiteralPath $path -Force }
                $script:lbFiles.Items.Remove($listBoxItem)
            }
        }
    })
}

