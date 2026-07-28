Add-Type -AssemblyName PresentationFramework

function Get-EasePeak ($amplitude) {
    $ease = New-Object System.Windows.Media.Animation.BackEase
    $ease.EasingMode = 'EaseOut'
    $ease.Amplitude = $amplitude
    $maxEase = 0
    for ($i = 0; $i -le 1000; $i++) {
        $t = $i / 1000.0
        $eased = $ease.Ease($t)
        if ($eased -gt $maxEase) { $maxEase = $eased }
    }
    return $maxEase
}

for ($a = 1.0; $a -le 1.5; $a+=0.01) {
    $peak = Get-EasePeak $a
    if ([math]::Round($peak, 2) -eq 1.50) { Write-Host "HoverExit (MaxEase 1.50) -> Amplitude: $a"; break }
}

for ($a = 3.0; $a -le 4.0; $a+=0.01) {
    $peak = Get-EasePeak $a
    if ([math]::Round($peak, 2) -eq 2.80) { Write-Host "PopIn (MaxEase 2.80) -> Amplitude: $a"; break }
}
