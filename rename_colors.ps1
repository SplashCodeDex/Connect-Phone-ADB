$content = Get-Content "MSIX_Source\bin\Connect-Engine.ps1" -Raw

$replacements = @{
    'MenuBackgroundGradient' = 'PrimaryBackgroundGradient'
    'MenuBackgroundBrush' = 'SecondaryBackgroundBrush'
    'HoverBackgroundBrush' = 'TertiaryBackgroundBrush'
    'MenuBorderBrush' = 'BorderBrush'
    'BrandBrush' = 'PrimaryBrush'
    'FolderIconBrush' = 'SecondaryBrush'
    'SuccessBrush' = 'SecondaryBrush'
    'DangerBrush' = 'AccentBrush'
    'MutedTextBrush' = 'SecondaryTextBrush'
    'FileIconBrush' = 'SecondaryTextBrush'
}

foreach ($key in $replacements.Keys) {
    $content = $content.Replace($key, $replacements[$key])
}

Set-Content "MSIX_Source\bin\Connect-Engine.ps1" $content -NoNewline
