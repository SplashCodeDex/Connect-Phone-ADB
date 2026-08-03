
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
    param(
        [Parameter(Mandatory=$true)]
        [System.Collections.Concurrent.ConcurrentQueue[object]]$Queue
    )
    Write-Trace "Starting Omni-Mesh Discovery Runspace (mDNS + UDP Multicast)..."
    
    $iss = [management.automation.runspaces.initialsessionstate]::CreateDefault2()
    $ps = [powershell]::Create($iss)
    
    $script = {
        param($adbPath, $computerName, $queue)
        
        try {
            $lastMdns = [datetime]::MinValue

            while ($true) {
                $now = Get-Date

                # A. ADB mDNS Services polling (every 15 seconds)
                if ($now - $lastMdns -gt [timespan]::FromSeconds(15)) {
                    $output = & $adbPath mdns services 2>&1
                    if ($null -ne $output) {
                        $lines = $output -split '`r?`n'
                        foreach ($line in $lines) {
                            if ($line -match '_adb-tls-connect\._tcp\.\s+([0-9\.]+:[0-9]+)') {
                                [void]$queue.Enqueue(@{ Type = 'Connect'; IPPort = $matches[1] })
                            }
                            if ($line -match '_adb-tls-pairing\._tcp\.\s+([0-9\.]+:[0-9]+)') {
                                [void]$queue.Enqueue(@{ Type = 'Pairing'; IPPort = $matches[1] })
                            }
                        }
                    }
                    $lastMdns = $now
                }
                
                Start-Sleep -Milliseconds 100
            }
        } catch {
            $queue.Enqueue([pscustomobject]@{ Type = 'Error'; Message = "mDNS polling error: $_" })
        }
    }
    
    [void]$ps.AddScript($script).AddArgument($global:AdbExePath).AddArgument($env:COMPUTERNAME).AddArgument($Queue)
    
    $asyncResult = $ps.BeginInvoke()
    
    return [PSCustomObject]@{
        PowerShell = $ps
        AsyncResult = $asyncResult
    }
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

