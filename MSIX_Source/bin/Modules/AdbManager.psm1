
function adb { & $global:AdbExePath @args }
Export-ModuleMember -Function adb

function Invoke-AdbConnect {
    [CmdletBinding()]
    param(
        [string]$Target,
        [switch]$ConnectOnly
    )

    $GatewayIP = $null
    if ([string]::IsNullOrWhiteSpace($Target)) {
        $GatewayIP = (Get-NetRoute -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue | 
                      Where-Object { $_.NextHop -ne '0.0.0.0' -and $_.NextHop -ne '::' } | 
                      Select-Object -First 1 -ExpandProperty NextHop)
        
        if (-not $GatewayIP) {
            if ($ConnectOnly) {
                $null = adb disconnect 2>&1
                return @{ Success = $false; Message = "No IP provided." }
            }
            
            Add-Type -AssemblyName Microsoft.VisualBasic
            $GatewayIP = [Microsoft.VisualBasic.Interaction]::InputBox("Not on Phone Hotspot. Enter Phone IP manually (e.g. 192.168.1.15):", "Connect ADB")
            if (-not $GatewayIP) {
                $null = adb disconnect 2>&1
                return @{ Success = $false; Message = "No IP provided." }
            }
        }
        
        $Target = "${GatewayIP}:5555"
    } else {
        if ($Target -match '^([0-9\.]+):') {
            $GatewayIP = $Matches[1]
        }
    }
    
    # Smart Polling: Check if already connected to prevent UI freezing
    $devices = (adb devices -l 2>&1) | Out-String
    if ($devices -match ([regex]::Escape($target) + "\s+device.*?model:([^\s]+)")) {
        $devName = $Matches[1] -replace '_', ' '
        return @{ Success = $true; Target = $target; IP = $GatewayIP; Name = $devName }
    } elseif ($devices -match ([regex]::Escape($target) + "\s+device")) {
        return @{ Success = $true; Target = $target; IP = $GatewayIP; Name = $target }
    }

    # Not connected, try to connect
    $null = adb start-server 2>&1
    $result = adb connect $target 2>&1
    
    $devices = (adb devices -l 2>&1) | Out-String
    if ($result -like "*connected to*" -or $devices -match ([regex]::Escape($target) + "\s+device")) {
        $devName = $target
        if ($devices -match ([regex]::Escape($target) + "\s+device.*?model:([^\s]+)")) {
            $devName = $Matches[1] -replace '_', ' '
        }
        return @{ Success = $true; Target = $target; IP = $GatewayIP; Name = $devName }
    } else {
        # Clear ghost target if unreachable
        $null = adb disconnect $target 2>&1
        return @{ Success = $false; Message = "Could not reach ADB daemon on $target" }
    }
}
Export-ModuleMember -Function Invoke-AdbConnect


function Start-MdnsDiscovery {
    Write-Trace "Starting Omni-Mesh Discovery Job (mDNS + UDP Multicast)..."
    
    $job = Start-Job -ScriptBlock {
        param($adbPath, $computerName)
        
        # 1. Setup UDP Multicast Listener
        $udpClient = New-Object System.Net.Sockets.UdpClient
        $udpClient.Client.SetSocketOption([System.Net.Sockets.SocketOptionLevel]::Socket, [System.Net.Sockets.SocketOptionName]::ReuseAddress, $true)
        $udpClient.Client.Bind([System.Net.IPEndPoint]::new([System.Net.IPAddress]::Any, 53317))
        $mcastIp = [System.Net.IPAddress]::Parse("224.0.0.167")
        $udpClient.JoinMulticastGroup($mcastIp)
        
        # 2. Setup UDP Sender
        $targetEp = [System.Net.IPEndPoint]::new($mcastIp, 53317)
        $sendUdp = New-Object System.Net.Sockets.UdpClient
        $payloadString = "{ `"id`": `"$computerName`", `"type`": `"pc`" }"
        $payload = [System.Text.Encoding]::UTF8.GetBytes($payloadString)
        
        $lastMdns = [datetime]::MinValue
        $lastBroadcast = [datetime]::MinValue

        while ($true) {
            $now = Get-Date

            # A. Listen for incoming Omni-Mesh packets (non-blocking)
            while ($udpClient.Available -gt 0) {
                $remoteEp = $null
                $bytes = $udpClient.Receive([ref]$remoteEp)
                $msg = [System.Text.Encoding]::UTF8.GetString($bytes)
                
                if ($msg -match '"type"\s*:\s*"(pc|phone)"') {
                    $devType = $matches[1]
                    $devId = "Unknown"
                    if ($msg -match '"id"\s*:\s*"([^"]+)"') { $devId = $matches[1] }
                    
                    Write-Output @{ Type = 'OmniMesh'; IPPort = "$($remoteEp.Address):53317"; DeviceType = $devType; Name = $devId }
                }
            }

            # B. Broadcast Omni-Mesh beacon (every 5 seconds)
            if ($now - $lastBroadcast -gt [timespan]::FromSeconds(5)) {
                # Multicast LAN
                $null = $sendUdp.Send($payload, $payload.Length, $targetEp)
                
                # Hotspot Piercer: Direct Unicast to Gateway
                $gw = (Get-NetRoute -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue | Where-Object NextHop -match '^[0-9\.]+$' | Select-Object -First 1).NextHop
                if ($gw -and $gw -ne '0.0.0.0') {
                    $gwEp = [System.Net.IPEndPoint]::new([System.Net.IPAddress]::Parse($gw), 53317)
                    $null = $sendUdp.Send($payload, $payload.Length, $gwEp)
                }
                
                $lastBroadcast = $now
            }
            
            # C. ADB mDNS Services polling (every 15 seconds)
            if ($now - $lastMdns -gt [timespan]::FromSeconds(15)) {
                $output = & $adbPath mdns services 2>&1
                if ($null -ne $output) {
                    $lines = $output -split '`r?`n'
                    foreach ($line in $lines) {
                        if ($line -match '_adb-tls-connect\._tcp\.\s+([0-9\.]+:[0-9]+)') {
                            Write-Output @{ Type = 'Connect'; IPPort = $matches[1] }
                        }
                        if ($line -match '_adb-tls-pairing\._tcp\.\s+([0-9\.]+:[0-9]+)') {
                            Write-Output @{ Type = 'Pairing'; IPPort = $matches[1] }
                        }
                    }
                }
                $lastMdns = $now
            }
            
            Start-Sleep -Milliseconds 500
        }
    } -ArgumentList $global:AdbExePath, $env:COMPUTERNAME
    
    Register-ObjectEvent -InputObject $job -EventName StateChanged -Action {
        Write-Trace "Omni-Mesh Job state changed: $( $sender.State )"
    } | Out-Null
    
    return $job
}

Export-ModuleMember -Function Start-MdnsDiscovery

function Invoke-AdbPair {
    param(
        [Parameter(Mandatory=$true)][string]$Target,
        [Parameter(Mandatory=$true)][string]$Pin
    )
    
    $null = adb start-server 2>&1
    $result = adb pair $Target $Pin 2>&1
    
    if ($result -match 'Successfully paired to') {
        return $true
    } else {
        Write-Trace "Pairing failed: $result"
        return $false
    }
}
Export-ModuleMember -Function Invoke-AdbPair

function Start-OmniTransferServer {
    param(
        [string]$DownloadPath = "$env:USERPROFILE\Downloads\dex"
    )
    
    Write-Trace "Starting Omni-Mesh Transfer Server on port 53318..."
    
    $job = Start-Job -ScriptBlock {
        param($dlPath)
        
        $port = 53318
        $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Any, $port)
        $listener.Start()
        
        while ($true) {
            if ($listener.Pending()) {
                $client = $listener.AcceptTcpClient()
                $stream = $client.GetStream()
                
                try {
                    # BinaryReader prevents buffer read-ahead corruption
                    $br = [System.IO.BinaryReader]::new($stream)
                    
                    # 1. Read Int32 (Header Length)
                    $headerLen = $br.ReadInt32()
                    if ($headerLen -gt 0 -and $headerLen -lt 1048576) {
                        # 2. Read JSON Header
                        $headerBytes = $br.ReadBytes($headerLen)
                        $headerJson = [System.Text.Encoding]::UTF8.GetString($headerBytes)
                        $header = $headerJson | ConvertFrom-Json
                        
                        if ($header.filename) {
                            $safeName = [System.IO.Path]::GetFileName($header.filename)
                            $outPath = Join-Path $dlPath $safeName
                            
                            # 3. Stream raw file bytes to disk
                            $fs = [System.IO.File]::Create($outPath)
                            $stream.CopyTo($fs)
                            $fs.Close()
                            
                            Write-Output @{ Type = 'TransferComplete'; File = $outPath; From = $client.Client.RemoteEndPoint.ToString() }
                        }
                    }
                } catch {
                    Write-Error "Omni-Mesh Transfer failed: $_"
                } finally {
                    $client.Close()
                }
            }
            Start-Sleep -Milliseconds 200
        }
    } -ArgumentList $DownloadPath
    
    Register-ObjectEvent -InputObject $job -EventName StateChanged -Action {
        Write-Trace "Omni-Mesh Transfer Job state changed: $( $sender.State )"
    } | Out-Null
    
    return $job
}
Export-ModuleMember -Function Start-OmniTransferServer
