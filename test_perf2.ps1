Add-Type -AssemblyName PresentationFramework
$sw = [System.Diagnostics.Stopwatch]::StartNew()
$workArea = [System.Windows.SystemParameters]::WorkArea
Write-Host "WorkArea took $($sw.ElapsedMilliseconds) ms"
