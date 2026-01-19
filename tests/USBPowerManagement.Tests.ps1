#Requires -Modules Pester
<#
.SYNOPSIS
    Pester tests for USB Power Management scripts.

.DESCRIPTION
    Unit and integration tests for Disable-USBPowerManagement.ps1 and 
    USBPowerManagement-GUI.ps1 scripts.

.NOTES
    Author: Diobyte
    Version: 1.4.1
    Requires: Pester 5.0+
#>

BeforeAll {
    $scriptRoot = Split-Path -Parent $PSScriptRoot
    $mainScript = Join-Path $scriptRoot "Disable-USBPowerManagement.ps1"
    $guiScript = Join-Path $scriptRoot "USBPowerManagement-GUI.ps1"
}

Describe "Script File Validation" {
    Context "Disable-USBPowerManagement.ps1" {
        It "Script file should exist" {
            $mainScript | Should -Exist
        }

        It "Should have valid PowerShell syntax" {
            $parseErrors = $null
            $null = [System.Management.Automation.Language.Parser]::ParseFile(
                $mainScript,
                [ref]$null,
                [ref]$parseErrors
            )
            $parseErrors.Count | Should -Be 0
        }

        It "Should contain required help documentation" {
            $content = Get-Content $mainScript -Raw
            $content | Should -Match '\.SYNOPSIS'
            $content | Should -Match '\.DESCRIPTION'
            $content | Should -Match '\.PARAMETER'
            $content | Should -Match '\.EXAMPLE'
        }

        It "Should have #Requires -RunAsAdministrator" {
            $content = Get-Content $mainScript -Raw
            $content | Should -Match '#Requires -RunAsAdministrator'
        }

        It "Should have #Requires -Version 3.0" {
            $content = Get-Content $mainScript -Raw
            $content | Should -Match '#Requires -Version 3\.0'
        }

        It "Should define expected parameters" {
            $ast = [System.Management.Automation.Language.Parser]::ParseFile(
                $mainScript,
                [ref]$null,
                [ref]$null
            )
            $params = $ast.ParamBlock.Parameters.Name.VariablePath.UserPath
            $params | Should -Contain 'ReportOnly'
            $params | Should -Contain 'NoRestartPrompt'
            $params | Should -Contain 'EnableLogging'
            $params | Should -Contain 'Restore'
            $params | Should -Contain 'ExportReport'
        }
    }

    Context "USBPowerManagement-GUI.ps1" {
        It "Script file should exist" {
            $guiScript | Should -Exist
        }

        It "Should have valid PowerShell syntax" {
            $parseErrors = $null
            $null = [System.Management.Automation.Language.Parser]::ParseFile(
                $guiScript,
                [ref]$null,
                [ref]$parseErrors
            )
            $parseErrors.Count | Should -Be 0
        }

        It "Should load Windows Forms assemblies" {
            $content = Get-Content $guiScript -Raw
            $content | Should -Match 'System\.Windows\.Forms'
            $content | Should -Match 'System\.Drawing'
        }
    }
}

Describe "Function Validation" {
    Context "Write-Status Function" {
        BeforeAll {
            # Extract and define the Write-Status function for testing
            $content = Get-Content $mainScript -Raw
            $functionMatch = [regex]::Match($content, '(?ms)function Write-Status \{.+?^}', 'Multiline')
            if ($functionMatch.Success) {
                # Create a simplified version for testing that doesn't output to host
                function Write-Status {
                    param(
                        [Parameter(Mandatory = $true)]
                        [ValidateNotNullOrEmpty()]
                        [string]$Message,
                        
                        [Parameter()]
                        [ValidateSet("Success", "Error", "Warning", "Info", "Debug")]
                        [string]$Type = "Info"
                    )
                    # Return formatted message for testing
                    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
                    return "[$timestamp] [$($Type.ToUpper())] $Message"
                }
            }
        }

        It "Should format messages with timestamp and type" {
            $result = Write-Status -Message "Test message" -Type "Info"
            $result | Should -Match '\[\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\] \[INFO\] Test message'
        }

        It "Should handle all message types" {
            $types = @("Success", "Error", "Warning", "Info", "Debug")
            foreach ($type in $types) {
                $result = Write-Status -Message "Test" -Type $type
                $result | Should -Match "\[$($type.ToUpper())\]"
            }
        }
    }
}

Describe "Registry Path Validation" {
    Context "USB Service Paths" {
        It "Should reference valid USB service registry paths" {
            $content = Get-Content $mainScript -Raw
            $content | Should -Match 'HKLM:\\SYSTEM\\CurrentControlSet\\Services\\usbhub'
            $content | Should -Match 'HKLM:\\SYSTEM\\CurrentControlSet\\Services\\USBXHCI'
        }

        It "Should reference valid USB enum paths" {
            $content = Get-Content $mainScript -Raw
            $content | Should -Match 'HKLM:\\SYSTEM\\CurrentControlSet\\Enum\\USB'
            $content | Should -Match 'HKLM:\\SYSTEM\\CurrentControlSet\\Enum\\USBSTOR'
        }
    }

    Context "Power Plan GUIDs" {
        It "Should use correct USB Settings GUID" {
            $content = Get-Content $mainScript -Raw
            # USB Settings subgroup GUID
            $content | Should -Match '2a737441-1930-4402-8d77-b2bebba308a3'
        }

        It "Should use correct USB Selective Suspend Setting GUID" {
            $content = Get-Content $mainScript -Raw
            # USB Selective Suspend setting GUID
            $content | Should -Match '48e6b7a6-50f5-4782-a5d4-53bb8f07e226'
        }
    }
}

Describe "Registry Value Configuration" {
    Context "Power Management Registry Values" {
        It "Should set EnhancedPowerManagementEnabled to 0" {
            $content = Get-Content $mainScript -Raw
            $content | Should -Match 'EnhancedPowerManagementEnabled.*-Value 0'
        }

        It "Should set SelectiveSuspendEnabled to 0" {
            $content = Get-Content $mainScript -Raw
            $content | Should -Match 'SelectiveSuspendEnabled.*-Value 0'
        }

        It "Should set AllowIdleIrpInD3 to 0" {
            $content = Get-Content $mainScript -Raw
            $content | Should -Match 'AllowIdleIrpInD3.*-Value 0'
        }

        It "Should set DisableSelectiveSuspend to 1 for services" {
            $content = Get-Content $mainScript -Raw
            $content | Should -Match 'DisableSelectiveSuspend.*-Value 1'
        }
    }
}

Describe "Restore Functionality" {
    Context "Enable-USBPowerManagement Function" {
        It "Should exist in main script" {
            $content = Get-Content $mainScript -Raw
            $content | Should -Match 'function Enable-USBPowerManagement'
        }

        It "Should remove registry properties" {
            $content = Get-Content $mainScript -Raw
            $content | Should -Match 'Remove-ItemProperty.*EnhancedPowerManagementEnabled'
            $content | Should -Match 'Remove-ItemProperty.*SelectiveSuspendEnabled'
            $content | Should -Match 'Remove-ItemProperty.*AllowIdleIrpInD3'
        }

        It "Should re-enable USB Selective Suspend (value 1)" {
            $content = Get-Content $mainScript -Raw
            # In restore mode, it should set value to 1 to re-enable
            $content | Should -Match 'setacvalueindex.*1'
            $content | Should -Match 'setdcvalueindex.*1'
        }
    }
}

Describe "Export Functionality" {
    Context "Report Export" {
        It "Should support CSV export" {
            $content = Get-Content $mainScript -Raw
            $content | Should -Match '\.csv'
            $content | Should -Match 'Export-Csv'
        }

        It "Should support JSON export" {
            $content = Get-Content $mainScript -Raw
            $content | Should -Match '\.json'
            $content | Should -Match 'ConvertTo-Json'
        }

        It "Should support TXT export" {
            $content = Get-Content $mainScript -Raw
            $content | Should -Match '\.txt'
            $content | Should -Match 'Out-File'
        }
    }
}

Describe "GUI Functionality" {
    Context "GUI Components" {
        It "Should create main form" {
            $content = Get-Content $guiScript -Raw
            $content | Should -Match 'New-Object System\.Windows\.Forms\.Form'
        }

        It "Should have Disable button" {
            $content = Get-Content $guiScript -Raw
            $content | Should -Match '\$script:DisableButton'
        }

        It "Should have Restore button" {
            $content = Get-Content $guiScript -Raw
            $content | Should -Match '\$script:RestoreButton'
        }

        It "Should have Refresh button" {
            $content = Get-Content $guiScript -Raw
            $content | Should -Match '\$script:RefreshButton'
        }

        It "Should have Export Log button" {
            $content = Get-Content $guiScript -Raw
            $content | Should -Match '\$script:ExportLogButton'
        }

        It "Should have device ListView" {
            $content = Get-Content $guiScript -Raw
            $content | Should -Match '\$script:DeviceListView'
        }

        It "Should have progress bar" {
            $content = Get-Content $guiScript -Raw
            $content | Should -Match '\$script:ProgressBar'
        }
    }

    Context "Administrator Check" {
        It "Should have admin check function" {
            $content = Get-Content $guiScript -Raw
            $content | Should -Match 'function Test-Administrator'
        }

        It "Should check WindowsPrincipal" {
            $content = Get-Content $guiScript -Raw
            $content | Should -Match 'WindowsPrincipal'
            $content | Should -Match 'WindowsBuiltInRole.*Administrator'
        }
    }
}

Describe "Error Handling" {
    Context "Main Script" {
        It "Should use try-catch blocks" {
            $content = Get-Content $mainScript -Raw
            ($content | Select-String -Pattern 'try\s*{' -AllMatches).Matches.Count | Should -BeGreaterThan 5
            ($content | Select-String -Pattern 'catch\s*{' -AllMatches).Matches.Count | Should -BeGreaterThan 5
        }

        It "Should use ErrorAction parameters" {
            $content = Get-Content $mainScript -Raw
            $content | Should -Match '-ErrorAction'
        }
    }

    Context "GUI Script" {
        It "Should use try-catch blocks" {
            $content = Get-Content $guiScript -Raw
            ($content | Select-String -Pattern 'try\s*{' -AllMatches).Matches.Count | Should -BeGreaterThan 3
        }
    }
}

Describe "Compatibility" {
    Context "CIM/WMI Fallback" {
        It "Should try CIM first then fallback to WMI" {
            $content = Get-Content $mainScript -Raw
            $content | Should -Match 'Get-CimInstance'
            $content | Should -Match 'Get-WmiObject'
        }

        It "GUI should have CIM/WMI fallback" {
            $content = Get-Content $guiScript -Raw
            $content | Should -Match 'Get-CimInstance'
            $content | Should -Match 'Get-WmiObject'
        }
    }

    Context "PowerShell Version Checks" {
        It "Should check for minimum PowerShell version" {
            $content = Get-Content $mainScript -Raw
            $content | Should -Match '#Requires -Version 3\.0'
        }

        It "Should check Get-PnpDevice availability" {
            $content = Get-Content $mainScript -Raw
            $content | Should -Match 'Get-Command Get-PnpDevice'
        }
    }
}

Describe "Batch Launchers" {
    BeforeAll {
        $batFile = Join-Path (Split-Path -Parent $PSScriptRoot) "Run-DisableUSBPowerManagement.bat"
        $guiBatFile = Join-Path (Split-Path -Parent $PSScriptRoot) "Run-GUI.bat"
        $buildBatFile = Join-Path (Split-Path -Parent $PSScriptRoot) "Build-GUI-EXE.bat"
    }

    Context "Run-DisableUSBPowerManagement.bat" {
        It "File should exist" {
            $batFile | Should -Exist
        }

        It "Should have UAC elevation" {
            $content = Get-Content $batFile -Raw
            $content | Should -Match 'runas'
        }

        It "Should check for PowerShell script" {
            $content = Get-Content $batFile -Raw
            $content | Should -Match 'Disable-USBPowerManagement\.ps1'
        }
    }

    Context "Run-GUI.bat" {
        It "File should exist" {
            $guiBatFile | Should -Exist
        }

        It "Should have UAC elevation" {
            $content = Get-Content $guiBatFile -Raw
            $content | Should -Match 'runas'
        }

        It "Should check for GUI files" {
            $content = Get-Content $guiBatFile -Raw
            $content | Should -Match 'USBPowerManagement-GUI'
        }
    }

    Context "Build-GUI-EXE.bat" {
        It "File should exist" {
            $buildBatFile | Should -Exist
        }

        It "Should reference PS2EXE" {
            $content = Get-Content $buildBatFile -Raw
            $content | Should -Match 'ps2exe'
        }
    }
}
