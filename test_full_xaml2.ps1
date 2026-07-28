$scriptPath = "w:\CodeDeX\Connect-Phone-ADB\MSIX_Source\bin\Connect-Engine.ps1"
$content = Get-Content $scriptPath -Raw
# Extract XAML
$xamlStart = $content.IndexOf("<Window xmlns=")
$xamlEnd = $content.IndexOf("</Window>") + 9
$xaml = $content.Substring($xamlStart, $xamlEnd - $xamlStart)
$xaml = $xaml -replace '(?s)<Ellipse.Fill>.*?</Ellipse.Fill>', '<Ellipse.Fill><SolidColorBrush Color="Red"/></Ellipse.Fill>'

Add-Type -AssemblyName PresentationFramework
$reader = New-Object System.Xml.XmlNodeReader ([xml]$xaml)
$win = [System.Windows.Markup.XamlReader]::Load($reader)

$btn = $win.FindName("btnQAAuto")
if ($btn -eq $null) {
    Write-Host "btnQAAuto is NULL!"
} else {
    Write-Host "btnQAAuto type: $($btn.GetType().FullName)"
}
