$e = New-Object System.Windows.Forms.MouseEventArgs([System.Windows.Forms.MouseButtons]::Left, 1, 0, 0, 0)
Write-Output "Button is: $($e.Button)"
if ($e.Button -eq 'Left') {
    Write-Output "Comparison with 'Left' worked."
} else {
    Write-Output "Comparison with 'Left' FAILED."
}

if ($e.Button -eq [System.Windows.Forms.MouseButtons]::Left) {
    Write-Output "Comparison with enum worked."
}
