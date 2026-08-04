$files = Get-ChildItem -Path 'w:\CodeDeX\DeX\MSIX_Source\bin' -Include *.ps1,*.psm1 -Recurse
$totalErrs = 0
foreach ($f in $files) {
    $errs = $null
    [System.Management.Automation.Language.Parser]::ParseFile($f.FullName, [ref]$null, [ref]$errs) | Out-Null
    if ($errs.Count -gt 0) {
        Write-Host "Errors in $($f.Name):"
        foreach ($e in $errs) { Write-Host "  $($e.Message)" }
        $totalErrs += $errs.Count
    }
}
Write-Host "Total syntax errors: $totalErrs"
