$files = Get-ChildItem -Path .\MSIX_Source\bin -Filter *.ps1 -Recurse
foreach ($f in $files) {
    $c = [System.IO.File]::ReadAllText($f.FullName)
    [System.IO.File]::WriteAllText($f.FullName, $c, [System.Text.Encoding]::UTF8)
}
Write-Host "BOM fixed."
.\Validate-Build.ps1
