$scriptPath = "w:\CodeDeX\Connect-Phone-ADB\MSIX_Source\bin\Connect-Engine.ps1"
$content = Get-Content $scriptPath -Raw
# Extract XAML
$xamlStart = $content.IndexOf("<Window xmlns=")
$xamlEnd = $content.IndexOf("</Window>") + 9
$xaml = $content.Substring($xamlStart, $xamlEnd - $xamlStart)
$xaml = $xaml -replace '\$\(.*\)', 'C:/test'

Add-Type -AssemblyName PresentationFramework
$reader = New-Object System.Xml.XmlNodeReader ([xml]$xaml)
$win = [System.Windows.Markup.XamlReader]::Load($reader)

$tb = $win.FindName("txtQAAuto")
if ($tb -eq $null) {
    Write-Host "txtQAAuto is NULL!"
} else {
    Write-Host "txtQAAuto type: $($tb.GetType().FullName)"
}
