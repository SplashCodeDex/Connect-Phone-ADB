
function adb { & $global:AdbExePath @args }
Export-ModuleMember -Function adb

function Invoke-AdbConnect {
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
    
    $target = "${GatewayIP}:5555"
    
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
    Write-Trace "Starting mDNS Discovery Job..."
    
    $job = Start-Job -ScriptBlock {
        param($adbPath)
        while ($true) {
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
            Start-Sleep -Seconds 15
        }
    } -ArgumentList $global:AdbExePath
    
    Register-ObjectEvent -InputObject $job -EventName StateChanged -Action {
        Write-Trace "mDNS Job state changed: $( $sender.State )"
    } | Out-Null
    
    # We will poll the job in the main runspace or WPF timer if needed, or let the job trigger connects
    # Actually, the job can't easily trigger the UI runspace directly without IPC.
    # We can just have a runspace timer poll the job's receive output.
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
