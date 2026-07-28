$content = Get-Content "MSIX_Source\bin\Connect-Engine.ps1" -Raw

$replacements = @{
    '="#2C2C2E"' = '="{DynamicResource MenuBackgroundBrush}"'
    '="#3A3A3C"' = '="{DynamicResource HoverBackgroundBrush}"'
    '="#333333"' = '="{DynamicResource MenuBorderBrush}"'
    '="#A0A0A0"' = '="{DynamicResource SecondaryTextBrush}"'
    '="#555555"' = '="{DynamicResource MutedTextBrush}"'
    '="#FF453A"' = '="{DynamicResource DangerBrush}"'
    '="#00E676"' = '="{DynamicResource SuccessBrush}"'
    '="#FFD700"' = '="{DynamicResource FolderIconBrush}"'
    '="#6200EE"' = '="{DynamicResource BrandBrush}"'
    'Foreground="White"' = 'Foreground="{DynamicResource PrimaryTextBrush}"'
    'Value="White"' = 'Value="{DynamicResource PrimaryTextBrush}"'
}

foreach ($key in $replacements.Keys) {
    $content = $content.Replace($key, $replacements[$key])
}

Set-Content "MSIX_Source\bin\Connect-Engine.ps1" $content -NoNewline
