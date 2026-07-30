$allXaml = (Get-Content MSIX_Source\Themes\*.xaml) -join "
"
$allPs1 = (Get-ChildItem MSIX_Source\bin\*.ps1, MSIX_Source\bin\Modules\*.ps* | Get-Content) -join "
"

function Check-Keys($file) {
    $keys = @()
    (Get-Content $file) | Select-String -Pattern "x:Key="([^"]+)"" | ForEach-Object {
        $keys += $_.Matches.Groups[1].Value
    }
    $keys = $keys | Select-Object -Unique
    $dead = @()
    foreach ($key in $keys) {
        if ($allXaml -match "Resource $key\b" -or $allXaml -match "TargetName="$key"" -or $allPs1 -match ""$key"" -or $allPs1 -match "'$key'") {
            # Used
        } else {
            $dead += $key
        }
    }
    if ($dead.Count -gt 0) {
        Write-Output "
Dead Keys in $file: "
        $dead
    }
}
Check-Keys "MSIX_Source\Themes\DarkTheme.xaml"
Check-Keys "MSIX_Source\Themes\LightTheme.xaml"
Check-Keys "MSIX_Source\Themes\MainWindowResources.xaml"
