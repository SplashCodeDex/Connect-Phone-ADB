$endpoint = New-Object System.Net.IPEndPoint([System.Net.IPAddress]::Any, 53317)
$client = New-Object System.Net.Sockets.UdpClient(53317)
$client.Client.ReceiveTimeout = 5000
try {
    $bytes = $client.Receive([ref]$endpoint)
    $json = [System.Text.Encoding]::UTF8.GetString($bytes)
    Write-Host "Discovered device at $($endpoint.Address): $json"
} catch {
    Write-Host "No UDP broadcast received in 5s. Error: $_"
} finally {
    $client.Close()
}
