Continue = 'Stop'
Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName System.Drawing
$xaml = Get-Content MSIX_Source\bin\Connect-Engine.ps1 -Raw
$xaml = ($xaml -split '$xaml = @"')[1].Split('"@')[0]
$w = [System.Windows.Markup.XamlReader]::Parse($xaml)
$FileExplorer = $w.FindName('FileExplorer')
$FileExplorer.Visibility = 'Visible'
$FileExplorer.Opacity = 1

$lbFiles = $w.FindName('lbFiles')
$lbFiles.Items.Clear()

$item = New-Object System.Windows.Controls.ListBoxItem
$item.Content = [PSCustomObject]@{ Name = 'TestFolder'; FullPath = '/sdcard/TestFolder/'; IsDir = $true }
$item.ContentTemplate = $w.Resources['FolderGridTemplate']
$item.Opacity = 1
$lbFiles.Items.Add($item)

$w.Width = 600
$w.Height = 400

$w.Loaded += {
    Start-Sleep -Seconds 1
    $bmp = New-Object System.Drawing.Bitmap(600, 400)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.CopyFromScreen($w.Left, $w.Top, 0, 0, $bmp.Size)
    $bmp.Save('W:\CodeDeX\Connect-Phone-ADB\debug_wpf.png')
    $w.Close()
}
$w.ShowDialog() | Out-Null

