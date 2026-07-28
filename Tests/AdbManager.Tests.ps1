$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$utilsPath = Join-Path $here "..\MSIX_Source\bin\Modules\EngineUtils.psm1"
Import-Module $utilsPath -Force
$modulePath = Join-Path $here "..\MSIX_Source\bin\Modules\AdbManager.psm1"
Import-Module $modulePath -Force

Describe "AdbManager Module" {
    
    function Write-Trace { }
    
    Context "Invoke-AdbConnect" {
        It "Returns Success if already connected with name" {
            Mock -CommandName adb -ModuleName AdbManager -MockWith {
                return "List of devices attached`r`n192.168.1.15:5555      device product:s21 model:SM_G991U device:q2q"
            }
            
            $global:AdbExePath = "mock-adb.exe"
            Mock -CommandName Get-NetRoute -ModuleName AdbManager -MockWith {
                return [PSCustomObject]@{ NextHop = '192.168.1.15' }
            }
            
            $result = Invoke-AdbConnect
            $result.Success | Should Be $true
            $result.Name | Should Be "SM G991U"
        }
        
        It "Returns Success if already connected without name" {
            Mock -CommandName adb -ModuleName AdbManager -MockWith {
                return "List of devices attached`r`n192.168.1.15:5555      device"
            }
            
            Mock -CommandName Get-NetRoute -ModuleName AdbManager -MockWith {
                return [PSCustomObject]@{ NextHop = '192.168.1.15' }
            }
            
            $result = Invoke-AdbConnect
            $result.Success | Should Be $true
            $result.Name | Should Be "192.168.1.15:5555"
        }
        
        It "Returns Failure if device is unreachable" {
            Mock -CommandName adb -ModuleName AdbManager -MockWith {
                if ($args[0] -eq 'devices') {
                    return "List of devices attached"
                } elseif ($args[0] -eq 'connect') {
                    return "failed to connect to '192.168.1.15:5555': Connection refused"
                }
            }
            
            Mock -CommandName Get-NetRoute -ModuleName AdbManager -MockWith {
                return [PSCustomObject]@{ NextHop = '192.168.1.15' }
            }
            
            $result = Invoke-AdbConnect
            $result.Success | Should Be $false
            $result.Message | Should Match "Could not reach ADB daemon"
        }
    }
    
    Context "Invoke-AdbPair" {
        It "Returns True if successfully paired" {
            Mock -CommandName adb -ModuleName AdbManager -MockWith {
                return "Successfully paired to 192.168.1.15:43511 [guid=abc123def456]"
            }
            
            $result = Invoke-AdbPair -Target "192.168.1.15:43511" -Pin "123456"
            $result | Should Be $true
        }
        
        It "Returns False if pairing failed" {
            Mock -CommandName adb -ModuleName AdbManager -MockWith {
                return "Failed: Unable to start pairing client."
            }
            
            $result = Invoke-AdbPair -Target "192.168.1.15:43511" -Pin "000000"
            $result | Should Be $false
        }
    }
}
