Add-Type -AssemblyName System.Windows.Forms
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public class TestInput {
    [DllImport("user32.dll")]
    public static extern short GetAsyncKeyState(int vKey);
}
"@

for ($i = 0; $i -lt 50; $i++) {
    $btn = [TestInput]::GetAsyncKeyState(0x01)
    $down = ($btn -band 0x8000) -ne 0
    $pos = [System.Windows.Forms.Cursor]::Position
    Write-Host "BtnDown: $down X: $($pos.X) Y: $($pos.Y)"
    Start-Sleep -Milliseconds 100
}
