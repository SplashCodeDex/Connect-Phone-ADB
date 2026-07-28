$f = "w:\CodeDeX\Connect-Phone-ADB\MSIX_Source\bin\Connect-Engine.ps1"
$c = Get-Content $f
for ($i = 260; $i -lt 475; $i++) {
    $c[$i] = $c[$i] -replace 'Duration="0:0:0\.5"', 'Duration="0:0:0.15"'
}
Set-Content $f $c
