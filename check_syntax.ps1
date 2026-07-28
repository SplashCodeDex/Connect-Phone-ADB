$errs = $null
$warns = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile("w:\CodeDeX\Connect-Phone-ADB\MSIX_Source\bin\Connect-Engine.ps1", [ref]$null, [ref]$errs)
if ($errs.Count -gt 0) {
    $errs | ForEach-Object { Write-Host "Error: $($_.Message) at Line $($_.Extent.StartLineNumber)" }
} else {
    Write-Host "Syntax OK"
}
