$myBytes = [System.Text.Encoding]::UTF8.GetBytes('{"alias":"test"}')
$gw = (Get-NetRoute -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue | Where-Object NextHop -match '^[0-9\.]+$' | Select-Object -First 1).NextHop
if ($gw) {
    Write-Host "Gateway: $gw"
    $u = [System.Net.Sockets.UdpClient]::new()
    $u.Client.SetSocketOption([System.Net.Sockets.SocketOptionLevel]::Socket, [System.Net.Sockets.SocketOptionName]::ReuseAddress, $true)
    $u.Client.Bind([System.Net.IPEndPoint]::new([System.Net.IPAddress]::Any, 53317))
    [void]$u.Send($myBytes, $myBytes.Length, $gw, 53317)
    Write-Host "Sent"
    $u.Dispose()
}
