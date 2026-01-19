<# 
    USB Power Management Disabler - GUI Version
    Author: Diobyte
    Version: 1.4.1
#>

# Hide console window when running as EXE
Add-Type -Name Window -Namespace Console -MemberDefinition '
[DllImport("Kernel32.dll")]
public static extern IntPtr GetConsoleWindow();
[DllImport("user32.dll")]
public static extern bool ShowWindow(IntPtr hWnd, Int32 nCmdShow);
'
$consolePtr = [Console.Window]::GetConsoleWindow()
if ($consolePtr -ne [IntPtr]::Zero) {
    [Console.Window]::ShowWindow($consolePtr, 0) | Out-Null
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

[System.Windows.Forms.Application]::EnableVisualStyles()

# Script-level constants for USB power management GUIDs
# USB_SETTINGS_GUID: Power settings subgroup for USB settings in Windows power plans
# USB_SELECTIVE_SUSPEND_GUID: Setting for USB selective suspend feature
$script:USB_SETTINGS_GUID = "2a737441-1930-4402-8d77-b2bebba308a3"
$script:USB_SELECTIVE_SUSPEND_GUID = "48e6b7a6-50f5-4782-a5d4-53bb8f07e226"

# USB service registry paths (consistent structure with CLI script)
$script:USB_SERVICE_PATHS = @(
    @{ Path = "HKLM:\SYSTEM\CurrentControlSet\Services\USB"; Name = "USB" },
    @{ Path = "HKLM:\SYSTEM\CurrentControlSet\Services\usbhub"; Name = "USBHUB" },
    @{ Path = "HKLM:\SYSTEM\CurrentControlSet\Services\usbhub3"; Name = "USBHUB3" },
    @{ Path = "HKLM:\SYSTEM\CurrentControlSet\Services\USBXHCI"; Name = "USBXHCI (USB 3.0)" },
    @{ Path = "HKLM:\SYSTEM\CurrentControlSet\Services\usbehci"; Name = "USBEHCI (USB 2.0)" },
    @{ Path = "HKLM:\SYSTEM\CurrentControlSet\Services\usbuhci"; Name = "USBUHCI (USB 1.1)" },
    @{ Path = "HKLM:\SYSTEM\CurrentControlSet\Services\usbohci"; Name = "USBOHCI (USB 1.1)" },
    @{ Path = "HKLM:\SYSTEM\CurrentControlSet\Services\usbccgp"; Name = "USBCCGP (Composite)" },
    @{ Path = "HKLM:\SYSTEM\CurrentControlSet\Services\USBSTOR"; Name = "USBSTOR (Storage)" }
)

# USB device name filter patterns (shared across functions)
$script:USB_DEVICE_PATTERNS = @(
    "*USB*Hub*",
    "*USB*Controller*",
    "*USB*Root*",
    "*Universal Serial Bus*",
    "*eXtensible Host Controller*",
    "*Enhanced Host Controller*",
    "*Open Host Controller*",
    "*Universal Host Controller*"
)

# Helper function to test if a device matches USB patterns (shared across functions)
function Test-USBDevice {
    param($Device)
    
    # Check by PNPDeviceID prefix
    if ($Device.PNPDeviceID -like "USB\*" -or $Device.PNPDeviceID -like "USBSTOR\*") {
        return $true
    }
    
    # Check by device name patterns
    foreach ($pattern in $script:USB_DEVICE_PATTERNS) {
        if ($Device.Name -like $pattern) {
            return $true
        }
    }
    
    return $false
}

# Global variables
$script:DevicesModified = 0
$script:DevicesFailed = 0
$script:LogTextBox = $null
$script:DeviceListView = $null
$script:ProgressBar = $null
$script:StatusLabel = $null
$script:DisableButton = $null
$script:RefreshButton = $null
$script:RestoreButton = $null
$script:ExportLogButton = $null
$script:MainForm = $null

# Progress bar phase constants (percentages for each operation phase)
# Phases are distributed to show smoother progress during the disable operation:
# - Selective Suspend: 0-15% (quick registry operation)
# - Device Enumeration: 15-60% (main bulk of work, varies by device count)
# - Hub Configuration: 60-75% (registry sweep)
# - WMI Configuration: 75-85% (optional, may skip on some systems)
# - Service Configuration: 85-95% (registry operations)
# - Complete: 100%
$script:PROGRESS_SELECTIVE_SUSPEND = 15
$script:PROGRESS_DEVICE_ENUM_START = 15
$script:PROGRESS_DEVICE_ENUM_END = 60
$script:PROGRESS_RESTORE_PHASE2 = 40
$script:PROGRESS_DEVICE_ENUM = 60
$script:PROGRESS_HUB_CONFIG = 75
$script:PROGRESS_WMI_CONFIG = 85
$script:PROGRESS_SERVICE_CONFIG = 95
$script:PROGRESS_COMPLETE = 100

function Test-Administrator {
    try {
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = New-Object Security.Principal.WindowsPrincipal($identity)
        return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch {
        return $false
    }
}

function Write-Log {
    param([string]$Message, [string]$Type = "Info")
    
    if ($null -eq $script:LogTextBox) { return }
    if ([string]::IsNullOrWhiteSpace($Message)) { return }
    
    $timestamp = Get-Date -Format "HH:mm:ss"
    $color = switch ($Type) {
        "Success" { [System.Drawing.Color]::Green }
        "Error"   { [System.Drawing.Color]::Red }
        "Warning" { [System.Drawing.Color]::DarkOrange }
        default   { [System.Drawing.Color]::Black }
    }
    
    $script:LogTextBox.SelectionStart = $script:LogTextBox.TextLength
    $script:LogTextBox.SelectionLength = 0
    $script:LogTextBox.SelectionColor = $color
    $script:LogTextBox.AppendText("[$timestamp] $Message`r`n")
    $script:LogTextBox.ScrollToCaret()
    [System.Windows.Forms.Application]::DoEvents()
}

function Get-USBDevices {
    $devices = @()
    
    try {
        # Try CIM first (modern), fallback to WMI (legacy) for compatibility
        try {
            $pnpDevices = Get-CimInstance -ClassName Win32_PnPEntity -ErrorAction Stop | Where-Object { Test-USBDevice $_ }
        }
        catch {
            # Fallback to WMI for older systems or if CIM fails
            Write-Verbose "CIM query failed, falling back to WMI: $($_.Exception.Message)"
            $pnpDevices = Get-WmiObject -Class Win32_PnPEntity -ErrorAction SilentlyContinue | Where-Object { Test-USBDevice $_ }
        }
        
        foreach ($device in $pnpDevices) {
            if ($null -eq $device.PNPDeviceID) { continue }
            
            $deviceName = if (-not [string]::IsNullOrWhiteSpace($device.Name)) { $device.Name } else { "Unknown USB Device" }
            $powerStatus = "Unknown"
            $instancePath = $device.PNPDeviceID
            $regPath = "HKLM:\SYSTEM\CurrentControlSet\Enum\$instancePath"
            
            # First check Device Parameters directly under the device path
            $directParamsPath = Join-Path -Path $regPath -ChildPath "Device Parameters"
            if (Test-Path -LiteralPath $directParamsPath -ErrorAction SilentlyContinue) {
                $enhancedPM = Get-ItemProperty -LiteralPath $directParamsPath -Name "EnhancedPowerManagementEnabled" -ErrorAction SilentlyContinue
                if ($null -ne $enhancedPM) {
                    $powerStatus = if ($enhancedPM.EnhancedPowerManagementEnabled -eq 0) { "Disabled" } else { "Enabled" }
                }
            }
            
            # Also check subkeys for multi-instance devices (only if not found above)
            if ($powerStatus -eq "Unknown") {
                $subKeys = Get-ChildItem -LiteralPath $regPath -ErrorAction SilentlyContinue
                foreach ($subKey in $subKeys) {
                    # Skip Device Parameters key itself
                    if ($subKey.PSChildName -eq "Device Parameters") { continue }
                    
                    $deviceParamsPath = Join-Path -Path $subKey.PSPath -ChildPath "Device Parameters"
                    if (Test-Path -LiteralPath $deviceParamsPath -ErrorAction SilentlyContinue) {
                        $enhancedPM = Get-ItemProperty -LiteralPath $deviceParamsPath -Name "EnhancedPowerManagementEnabled" -ErrorAction SilentlyContinue
                        if ($null -ne $enhancedPM) {
                            $powerStatus = if ($enhancedPM.EnhancedPowerManagementEnabled -eq 0) { "Disabled" } else { "Enabled" }
                            break  # Exit early once we find a value
                        }
                    }
                }
            }
            
            $devices += [PSCustomObject]@{
                Name = $deviceName
                DeviceID = $device.PNPDeviceID
                Status = $device.Status
                PowerManagement = $powerStatus
            }
        }
    } catch {
        Write-Verbose "Device enumeration failed: $($_.Exception.Message)"
    }
    
    return $devices
}

function Disable-USBSelectiveSuspend {
    Write-Log "Disabling USB Selective Suspend in power plans..." "Info"
    
    try {
        $powercfgPath = Join-Path $env:SystemRoot "System32\powercfg.exe"
        if (-not (Test-Path -LiteralPath $powercfgPath)) {
            Write-Log "powercfg.exe not found" "Warning"
            return
        }
        
        $powerPlans = & $powercfgPath /list 2>&1
        
        if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($powerPlans)) {
            Write-Log "Failed to retrieve power plans" "Warning"
            return
        }
        
        # Wrap in @() to ensure array even for single result
        $planGuids = @([regex]::Matches($powerPlans, '([a-fA-F0-9]{8}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{12})') | 
                     ForEach-Object { $_.Groups[1].Value } | Select-Object -Unique)
        
        if ($planGuids.Count -eq 0) {
            Write-Log "No power plans found" "Warning"
            return
        }
        
        foreach ($planGuid in $planGuids) {
            & $powercfgPath /setacvalueindex $planGuid $script:USB_SETTINGS_GUID $script:USB_SELECTIVE_SUSPEND_GUID 0 2>&1 | Out-Null
            & $powercfgPath /setdcvalueindex $planGuid $script:USB_SETTINGS_GUID $script:USB_SELECTIVE_SUSPEND_GUID 0 2>&1 | Out-Null
        }
        
        # Reactivate current power plan to apply changes
        $activePlan = & $powercfgPath /getactivescheme 2>&1
        if ($null -ne $activePlan -and $activePlan -is [string] -and $activePlan -match '([a-fA-F0-9]{8}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{12})') {
            & $powercfgPath /setactive $matches[1] 2>&1 | Out-Null
        }
        
        Write-Log "USB Selective Suspend disabled in all power plans" "Success"
    } catch {
        Write-Log "Failed: $($_.Exception.Message)" "Error"
    }
}

function Disable-USBDevicePowerManagement {
    Write-Log "Disabling power management for USB devices..." "Info"
    
    $script:DevicesModified = 0
    $script:DevicesFailed = 0
    
    # Helper function to set power management properties on a registry path
    $setDevicePowerParams = {
        param($paramsPath)
        try {
            if (-not (Test-Path -LiteralPath $paramsPath)) {
                New-Item -Path $paramsPath -Force -ErrorAction SilentlyContinue | Out-Null
            }
            if (Test-Path -LiteralPath $paramsPath) {
                Set-ItemProperty -LiteralPath $paramsPath -Name "EnhancedPowerManagementEnabled" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
                Set-ItemProperty -LiteralPath $paramsPath -Name "SelectiveSuspendEnabled" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
                Set-ItemProperty -LiteralPath $paramsPath -Name "AllowIdleIrpInD3" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
                return $true
            }
            return $false
        } catch {
            return $false
        }
    }
    
    try {
        # Try CIM first, fallback to WMI for compatibility
        $allDevices = $null
        try {
            $allDevices = Get-CimInstance -ClassName Win32_PnPEntity -ErrorAction Stop | Where-Object { Test-USBDevice $_ }
        }
        catch {
            $allDevices = Get-WmiObject -Class Win32_PnPEntity -ErrorAction SilentlyContinue | Where-Object { Test-USBDevice $_ }
        }
        
        # Ensure we have a valid array even if queries returned null
        if ($null -eq $allDevices) {
            $deviceArray = @()
        } else {
            $deviceArray = @($allDevices)
        }
        $totalDevices = [Math]::Max($deviceArray.Count, 1)  # Prevent division by zero
        $currentDevice = 0
        
        foreach ($device in $deviceArray) {
            $currentDevice++
            if ($null -ne $script:ProgressBar) {
                # Calculate progress within the device enumeration phase range (15-60%)
                $phaseProgress = ($currentDevice / $totalDevices)
                $progressValue = $script:PROGRESS_DEVICE_ENUM_START + ($phaseProgress * ($script:PROGRESS_DEVICE_ENUM_END - $script:PROGRESS_DEVICE_ENUM_START))
                $script:ProgressBar.Value = [math]::Min([int]$progressValue, $script:PROGRESS_DEVICE_ENUM_END)
            }
            [System.Windows.Forms.Application]::DoEvents()
            
            $deviceId = $device.PNPDeviceID
            if ([string]::IsNullOrEmpty($deviceId)) { continue }
            
            $enumPath = "HKLM:\SYSTEM\CurrentControlSet\Enum\$deviceId"
            
            if (Test-Path -LiteralPath $enumPath) {
                $deviceModified = $false
                
                # First, check if Device Parameters exists directly under the device path
                $directParamsPath = Join-Path -Path $enumPath -ChildPath "Device Parameters"
                if (Test-Path -LiteralPath $directParamsPath -ErrorAction SilentlyContinue) {
                    if (& $setDevicePowerParams $directParamsPath) {
                        $deviceModified = $true
                    }
                }
                
                # Also process subkeys for multi-instance devices
                $subKeys = Get-ChildItem -LiteralPath $enumPath -ErrorAction SilentlyContinue
                
                foreach ($subKey in $subKeys) {
                    # Skip Device Parameters key itself
                    if ($subKey.PSChildName -eq "Device Parameters") { continue }
                    
                    $deviceParamsPath = Join-Path $subKey.PSPath "Device Parameters"
                    
                    if (& $setDevicePowerParams $deviceParamsPath) {
                        $deviceModified = $true
                    }
                }
                
                # Count device only once regardless of how many paths were modified
                if ($deviceModified) {
                    $script:DevicesModified++
                } else {
                    $script:DevicesFailed++
                }
            }
        }
        
        Write-Log "Modified $($script:DevicesModified) devices" "Success"
        if ($script:DevicesFailed -gt 0) {
            Write-Log "Failed to modify $($script:DevicesFailed) devices" "Warning"
        }
    } catch {
        Write-Log "Error: $($_.Exception.Message)" "Error"
    }
}

function Set-USBHubPowerManagement {
    Write-Log "Configuring USB Hub settings..." "Info"
    if ($null -ne $script:ProgressBar) { $script:ProgressBar.Value = $script:PROGRESS_HUB_CONFIG }
    [System.Windows.Forms.Application]::DoEvents()
    
    try {
        $usbEnumPath = "HKLM:\SYSTEM\CurrentControlSet\Enum\USB"
        
        if (Test-Path -LiteralPath $usbEnumPath) {
            $usbDevices = Get-ChildItem -LiteralPath $usbEnumPath -Recurse -ErrorAction SilentlyContinue
            
            foreach ($item in $usbDevices) {
                if ($item.PSChildName -eq "Device Parameters") {
                    try {
                        Set-ItemProperty -LiteralPath $item.PSPath -Name "EnhancedPowerManagementEnabled" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
                        Set-ItemProperty -LiteralPath $item.PSPath -Name "SelectiveSuspendEnabled" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
                        Set-ItemProperty -LiteralPath $item.PSPath -Name "AllowIdleIrpInD3" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
                        Set-ItemProperty -LiteralPath $item.PSPath -Name "DeviceSelectiveSuspended" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
                        Set-ItemProperty -LiteralPath $item.PSPath -Name "SelectiveSuspendSupported" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
                    } catch {
                        # Individual device setting may fail due to permissions - continue with others
                    }
                }
            }
        }
        
        Write-Log "USB Hub settings configured" "Success"
    } catch {
        Write-Log "Error: $($_.Exception.Message)" "Error"
    }
}

function Disable-DevicePowerManagementPnP {
    Write-Log "Configuring WMI power management..." "Info"
    if ($null -ne $script:ProgressBar) { $script:ProgressBar.Value = $script:PROGRESS_WMI_CONFIG }
    [System.Windows.Forms.Application]::DoEvents()
    
    try {
        # Check if Get-PnpDevice cmdlet is available (may not be on older systems)
        $pnpCmdletAvailable = Get-Command Get-PnpDevice -ErrorAction SilentlyContinue
        
        if (-not $pnpCmdletAvailable) {
            Write-Log "Get-PnpDevice not available, skipping WMI configuration" "Warning"
            return
        }
        
        # Get USB devices with power management capability
        $devices = Get-PnpDevice | Where-Object {
            ($_.InstanceId -like "USB\*" -or $_.InstanceId -like "USBSTOR\*") -and
            $_.Status -eq "OK"
        }
        
        $wmiConfigured = 0
        foreach ($device in $devices) {
            try {
                $instanceId = $device.InstanceId
                
                # Get power management capabilities (WMI namespace may not exist on all systems)
                $powerMgmt = $null
                try {
                    $powerMgmt = Get-CimInstance -ClassName MSPower_DeviceEnable -Namespace root\WMI -ErrorAction Stop | 
                                 Where-Object { $_.InstanceName -like "*$($instanceId -replace '\\', '_')*" }
                } catch {
                    # WMI power namespace may not be available - this is normal
                }
                
                if ($powerMgmt) {
                    foreach ($pm in $powerMgmt) {
                        try {
                            $pm | Set-CimInstance -Property @{ Enable = $false } -ErrorAction Stop
                            $wmiConfigured++
                        } catch {
                            # Individual device may fail - continue with others
                        }
                    }
                }
            } catch {
                # Device processing failed - continue with next device
            }
        }
        
        if ($wmiConfigured -gt 0) {
            Write-Log "WMI power management configured for $wmiConfigured devices" "Success"
        } else {
            Write-Log "WMI power management: No configurable devices found" "Info"
        }
    } catch {
        Write-Log "WMI configuration skipped: $($_.Exception.Message)" "Warning"
    }
}

function Set-USBServicesConfiguration {
    Write-Log "Configuring USB services..." "Info"
    if ($null -ne $script:ProgressBar) { $script:ProgressBar.Value = $script:PROGRESS_SERVICE_CONFIG }
    [System.Windows.Forms.Application]::DoEvents()
    
    try {
        foreach ($service in $script:USB_SERVICE_PATHS) {
            $servicePath = $service.Path
            if (Test-Path -LiteralPath $servicePath) {
                $paramsPath = "$servicePath\Parameters"
                
                # Create Parameters key if it doesn't exist
                if (-not (Test-Path -LiteralPath $paramsPath)) {
                    New-Item -Path $paramsPath -Force -ErrorAction SilentlyContinue | Out-Null
                }
                
                if (Test-Path -LiteralPath $paramsPath) {
                    Set-ItemProperty -LiteralPath $paramsPath -Name "DisableSelectiveSuspend" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
                    Write-Log "$($service.Name) service selective suspend disabled" "Success"
                }
                
                # Also set at service root level for some drivers (matching CLI behavior)
                Set-ItemProperty -LiteralPath $servicePath -Name "DisableSelectiveSuspend" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
            }
        }
        
        Write-Log "USB services configured" "Success"
    } catch {
        Write-Log "Error: $($_.Exception.Message)" "Error"
    }
}

function Export-Log {
    $saveDialog = New-Object System.Windows.Forms.SaveFileDialog
    $saveDialog.Filter = "Text files (*.txt)|*.txt|Log files (*.log)|*.log|All files (*.*)|*.*"
    $saveDialog.Title = "Export Activity Log"
    $saveDialog.FileName = "USBPowerManagement_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"
    
    if ($saveDialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        try {
            $script:LogTextBox.Text | Out-File -FilePath $saveDialog.FileName -Encoding UTF8
            Write-Log "Log exported to: $($saveDialog.FileName)" "Success"
            [System.Windows.Forms.MessageBox]::Show(
                "Log exported successfully to:`n$($saveDialog.FileName)",
                "Export Complete",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Information
            )
        } catch {
            Write-Log "Failed to export log: $($_.Exception.Message)" "Error"
            [System.Windows.Forms.MessageBox]::Show(
                "Failed to export log:`n$($_.Exception.Message)",
                "Export Failed",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Error
            )
        }
    }
}

function Enable-USBPowerManagement {
    Write-Log "Restoring USB power management to Windows defaults..." "Info"
    if ($null -ne $script:ProgressBar) { $script:ProgressBar.Value = $script:PROGRESS_SELECTIVE_SUSPEND }
    [System.Windows.Forms.Application]::DoEvents()
    
    try {
        # Restore USB Selective Suspend in power plans
        Write-Log "Enabling USB Selective Suspend in power plans..." "Info"
        
        $powercfgPath = Join-Path $env:SystemRoot "System32\powercfg.exe"
        if (Test-Path -LiteralPath $powercfgPath) {
            $powerPlans = & $powercfgPath /list 2>&1
            # Wrap in @() to ensure array even for single result
            $planGuids = @([regex]::Matches($powerPlans, '([a-fA-F0-9]{8}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{12})') | 
                         ForEach-Object { $_.Groups[1].Value } | Select-Object -Unique)
            
            foreach ($planGuid in $planGuids) {
                & $powercfgPath /setacvalueindex $planGuid $script:USB_SETTINGS_GUID $script:USB_SELECTIVE_SUSPEND_GUID 1 2>&1 | Out-Null
                & $powercfgPath /setdcvalueindex $planGuid $script:USB_SETTINGS_GUID $script:USB_SELECTIVE_SUSPEND_GUID 1 2>&1 | Out-Null
            }
            Write-Log "USB Selective Suspend enabled in all power plans" "Success"
        }
        
        if ($null -ne $script:ProgressBar) { $script:ProgressBar.Value = $script:PROGRESS_RESTORE_PHASE2 }
        [System.Windows.Forms.Application]::DoEvents()
        
        # Remove registry settings
        Write-Log "Restoring USB device registry settings..." "Info"
        $devicesRestored = 0
        
        $usbEnumPath = "HKLM:\SYSTEM\CurrentControlSet\Enum\USB"
        if (Test-Path -LiteralPath $usbEnumPath) {
            $usbDevices = Get-ChildItem -LiteralPath $usbEnumPath -Recurse -ErrorAction SilentlyContinue
            
            foreach ($item in $usbDevices) {
                if ($item.PSChildName -eq "Device Parameters") {
                    try {
                        Remove-ItemProperty -LiteralPath $item.PSPath -Name "EnhancedPowerManagementEnabled" -Force -ErrorAction SilentlyContinue
                        Remove-ItemProperty -LiteralPath $item.PSPath -Name "SelectiveSuspendEnabled" -Force -ErrorAction SilentlyContinue
                        Remove-ItemProperty -LiteralPath $item.PSPath -Name "AllowIdleIrpInD3" -Force -ErrorAction SilentlyContinue
                        Remove-ItemProperty -LiteralPath $item.PSPath -Name "DeviceSelectiveSuspended" -Force -ErrorAction SilentlyContinue
                        Remove-ItemProperty -LiteralPath $item.PSPath -Name "SelectiveSuspendSupported" -Force -ErrorAction SilentlyContinue
                        $devicesRestored++
                    } catch {
                        # Property may not exist - continue with others
                    }
                }
            }
        }
        
        if ($null -ne $script:ProgressBar) { $script:ProgressBar.Value = $script:PROGRESS_DEVICE_ENUM }
        [System.Windows.Forms.Application]::DoEvents()
        
        # Restore USBSTOR
        $usbStorPath = "HKLM:\SYSTEM\CurrentControlSet\Enum\USBSTOR"
        if (Test-Path -LiteralPath $usbStorPath) {
            $usbStorDevices = Get-ChildItem -LiteralPath $usbStorPath -Recurse -ErrorAction SilentlyContinue
            foreach ($item in $usbStorDevices) {
                if ($item.PSChildName -eq "Device Parameters") {
                    try {
                        Remove-ItemProperty -LiteralPath $item.PSPath -Name "EnhancedPowerManagementEnabled" -Force -ErrorAction SilentlyContinue
                        Remove-ItemProperty -LiteralPath $item.PSPath -Name "SelectiveSuspendEnabled" -Force -ErrorAction SilentlyContinue
                        Remove-ItemProperty -LiteralPath $item.PSPath -Name "AllowIdleIrpInD3" -Force -ErrorAction SilentlyContinue
                        $devicesRestored++
                    } catch {
                        # Property may not exist - continue with others
                    }
                }
            }
        }
        
        if ($null -ne $script:ProgressBar) { $script:ProgressBar.Value = $script:PROGRESS_SERVICE_CONFIG }
        [System.Windows.Forms.Application]::DoEvents()
        
        # Remove service configuration
        Write-Log "Restoring USB service settings..." "Info"
        
        foreach ($service in $script:USB_SERVICE_PATHS) {
            $servicePath = $service.Path
            if (Test-Path -LiteralPath $servicePath) {
                $paramsPath = "$servicePath\Parameters"
                if (Test-Path -LiteralPath $paramsPath) {
                    Remove-ItemProperty -LiteralPath $paramsPath -Name "DisableSelectiveSuspend" -Force -ErrorAction SilentlyContinue
                }
                Remove-ItemProperty -LiteralPath $servicePath -Name "DisableSelectiveSuspend" -Force -ErrorAction SilentlyContinue
            }
        }
        
        Write-Log "Restored $devicesRestored device entries" "Success"
        Write-Log "USB services restored to defaults" "Success"
    } catch {
        Write-Log "Error: $($_.Exception.Message)" "Error"
    }
}

function Start-RestorePowerManagement {
    $script:DisableButton.Enabled = $false
    $script:RefreshButton.Enabled = $false
    $script:RestoreButton.Enabled = $false
    $script:ProgressBar.Value = 0
    $script:LogTextBox.Clear()
    
    Write-Log "Starting USB Power Management restore..." "Info"
    Write-Log "Running with Administrator privileges" "Success"
    
    Enable-USBPowerManagement
    
    $script:ProgressBar.Value = $script:PROGRESS_COMPLETE
    Write-Log "" "Info"
    Write-Log "========================================" "Info"
    Write-Log "Restore complete!" "Success"
    Write-Log "Windows default power management restored." "Info"
    Write-Log "A system restart is recommended." "Warning"
    Write-Log "========================================" "Info"
    
    Update-DeviceList
    
    $script:DisableButton.Enabled = $true
    $script:RefreshButton.Enabled = $true
    $script:RestoreButton.Enabled = $true
    
    $result = [System.Windows.Forms.MessageBox]::Show(
        "USB Power Management has been restored to Windows defaults.`n`nWould you like to restart your computer now?",
        "Restore Complete",
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Question
    )
    
    if ($result -eq [System.Windows.Forms.DialogResult]::Yes) {
        Write-Log "Restarting computer in 5 seconds..." "Warning"
        [System.Windows.Forms.Application]::DoEvents()
        Start-Sleep -Seconds 2
        $script:MainForm.Close()
        Start-Sleep -Seconds 3
        try {
            Restart-Computer -Force -ErrorAction Stop
        }
        catch {
            [System.Windows.Forms.MessageBox]::Show(
                "Failed to restart computer: $($_.Exception.Message)`n`nPlease restart manually.",
                "Restart Failed",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Warning
            )
        }
    }
}

function Start-DisablePowerManagement {
    $script:DisableButton.Enabled = $false
    $script:RefreshButton.Enabled = $false
    $script:RestoreButton.Enabled = $false
    $script:ProgressBar.Value = 0
    $script:LogTextBox.Clear()
    
    Write-Log "Starting USB Power Management configuration..." "Info"
    Write-Log "Running with Administrator privileges" "Success"
    
    $script:ProgressBar.Value = $script:PROGRESS_SELECTIVE_SUSPEND
    Disable-USBSelectiveSuspend
    
    Disable-USBDevicePowerManagement
    
    Set-USBHubPowerManagement
    
    Disable-DevicePowerManagementPnP
    
    Set-USBServicesConfiguration
    
    $script:ProgressBar.Value = $script:PROGRESS_COMPLETE
    Write-Log "" "Info"
    Write-Log "========================================" "Info"
    Write-Log "Configuration complete!" "Success"
    Write-Log "Devices modified: $($script:DevicesModified)" "Info"
    Write-Log "A system restart is recommended." "Warning"
    Write-Log "========================================" "Info"
    
    Update-DeviceList
    
    $script:DisableButton.Enabled = $true
    $script:RefreshButton.Enabled = $true
    $script:RestoreButton.Enabled = $true
    
    $result = [System.Windows.Forms.MessageBox]::Show(
        "USB Power Management has been disabled.`n`nWould you like to restart your computer now?",
        "Configuration Complete",
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Question
    )
    
    if ($result -eq [System.Windows.Forms.DialogResult]::Yes) {
        Write-Log "Restarting computer in 5 seconds..." "Warning"
        [System.Windows.Forms.Application]::DoEvents()
        Start-Sleep -Seconds 2
        $script:MainForm.Close()
        Start-Sleep -Seconds 3
        try {
            Restart-Computer -Force -ErrorAction Stop
        }
        catch {
            [System.Windows.Forms.MessageBox]::Show(
                "Failed to restart computer: $($_.Exception.Message)`n`nPlease restart manually.",
                "Restart Failed",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Warning
            )
        }
    }
}

function Update-DeviceList {
    if ($null -eq $script:DeviceListView) { return }
    
    $script:DeviceListView.Items.Clear()
    $script:DeviceListView.BeginUpdate()
    
    try {
        $devices = Get-USBDevices
    } catch {
        $devices = @()
        Write-Log "Failed to enumerate USB devices: $($_.Exception.Message)" "Warning"
    }
    
    if ($null -eq $devices -or $devices.Count -eq 0) {
        if ($null -ne $script:StatusLabel) {
            $script:StatusLabel.Text = "No USB devices found"
        }
        $script:DeviceListView.EndUpdate()
        return
    }
    
    foreach ($device in $devices) {
        if ($null -eq $device.Name) { continue }
        
        $item = New-Object System.Windows.Forms.ListViewItem($device.Name)
        [void]$item.SubItems.Add($device.Status)
        [void]$item.SubItems.Add($device.PowerManagement)
        $item.Tag = $device.DeviceID  # Store device ID for potential future use
        
        # Color code based on power management status
        if ($device.PowerManagement -eq "Disabled") {
            $item.ForeColor = [System.Drawing.Color]::Green
        } elseif ($device.PowerManagement -eq "Enabled") {
            $item.ForeColor = [System.Drawing.Color]::Red
        } else {
            $item.ForeColor = [System.Drawing.Color]::Gray
        }
        
        [void]$script:DeviceListView.Items.Add($item)
    }
    
    if ($null -ne $script:StatusLabel) {
        $script:StatusLabel.Text = "Found $($devices.Count) USB device(s)"
    }
    
    $script:DeviceListView.EndUpdate()
}

# Check admin first
$isAdmin = Test-Administrator

if (-not $isAdmin) {
    $result = [System.Windows.Forms.MessageBox]::Show(
        "This application requires Administrator privileges.`n`nWould you like to restart as Administrator?",
        "Administrator Required",
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Warning
    )
    
    if ($result -eq [System.Windows.Forms.DialogResult]::Yes) {
        try {
            $psi = New-Object System.Diagnostics.ProcessStartInfo
            $currentProcess = [System.Diagnostics.Process]::GetCurrentProcess()
            $exePath = $currentProcess.MainModule.FileName
            
            # Check if running as compiled EXE or PowerShell script
            if ($exePath -like "*powershell*" -or $exePath -like "*pwsh*") {
                # Running as script - re-launch PowerShell with the script
                $psi.FileName = $exePath
                # Get the script path using multiple fallback methods
                $scriptPath = $null
                if ($MyInvocation.MyCommand.Path) {
                    $scriptPath = $MyInvocation.MyCommand.Path
                } elseif ($PSCommandPath) {
                    $scriptPath = $PSCommandPath
                } elseif ($MyInvocation.MyCommand.Definition -and (Test-Path -LiteralPath $MyInvocation.MyCommand.Definition -ErrorAction SilentlyContinue)) {
                    $scriptPath = $MyInvocation.MyCommand.Definition
                }
                
                if (-not [string]::IsNullOrEmpty($scriptPath) -and (Test-Path -LiteralPath $scriptPath -ErrorAction SilentlyContinue)) {
                    $psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$scriptPath`""
                } else {
                    # Final fallback - try to find the script in the current directory
                    $fallbackPath = Join-Path $PWD.Path "USBPowerManagement-GUI.ps1"
                    if (Test-Path -LiteralPath $fallbackPath) {
                        $psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$fallbackPath`""
                    } else {
                        throw "Could not determine script path for elevation. Please run the script directly from its folder or use Run-GUI.bat."
                    }
                }
            } else {
                # Running as compiled EXE - just re-launch the EXE
                $psi.FileName = $exePath
            }
            
            $psi.Verb = "runas"
            $psi.UseShellExecute = $true
            [System.Diagnostics.Process]::Start($psi) | Out-Null
        } catch {
            [System.Windows.Forms.MessageBox]::Show(
                "Failed to elevate privileges: $($_.Exception.Message)",
                "Error",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Error
            )
        }
    }
    exit
}

# Build GUI
$script:MainForm = New-Object System.Windows.Forms.Form
$script:MainForm.Text = "USB Power Management Disabler v1.4.1"
$script:MainForm.Size = New-Object System.Drawing.Size(800, 670)
$script:MainForm.StartPosition = "CenterScreen"
$script:MainForm.FormBorderStyle = "FixedSingle"
$script:MainForm.MaximizeBox = $false
$script:MainForm.BackColor = [System.Drawing.Color]::WhiteSmoke
$script:MainForm.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::Dpi

# Header
$HeaderPanel = New-Object System.Windows.Forms.Panel
$HeaderPanel.Location = New-Object System.Drawing.Point(0, 0)
$HeaderPanel.Size = New-Object System.Drawing.Size(800, 70)
$HeaderPanel.BackColor = [System.Drawing.Color]::FromArgb(0, 120, 215)
$script:MainForm.Controls.Add($HeaderPanel)

$TitleLabel = New-Object System.Windows.Forms.Label
$TitleLabel.Text = "USB Power Management Disabler"
$TitleLabel.Font = New-Object System.Drawing.Font("Segoe UI", 18, [System.Drawing.FontStyle]::Bold)
$TitleLabel.ForeColor = [System.Drawing.Color]::White
$TitleLabel.Location = New-Object System.Drawing.Point(20, 10)
$TitleLabel.AutoSize = $true
$HeaderPanel.Controls.Add($TitleLabel)

$SubtitleLabel = New-Object System.Windows.Forms.Label
$SubtitleLabel.Text = "Prevent Windows from turning off USB devices to save power"
$SubtitleLabel.Font = New-Object System.Drawing.Font("Segoe UI", 10)
$SubtitleLabel.ForeColor = [System.Drawing.Color]::FromArgb(200, 220, 255)
$SubtitleLabel.Location = New-Object System.Drawing.Point(22, 42)
$SubtitleLabel.AutoSize = $true
$HeaderPanel.Controls.Add($SubtitleLabel)

# Admin label
$AdminLabel = New-Object System.Windows.Forms.Label
$AdminLabel.Text = [char]0x2713 + " Running with Administrator privileges"
$AdminLabel.Location = New-Object System.Drawing.Point(20, 80)
$AdminLabel.Size = New-Object System.Drawing.Size(750, 25)
$AdminLabel.Font = New-Object System.Drawing.Font("Segoe UI", 10)
$AdminLabel.ForeColor = [System.Drawing.Color]::Green
$script:MainForm.Controls.Add($AdminLabel)

# Device group
$DeviceGroup = New-Object System.Windows.Forms.GroupBox
$DeviceGroup.Text = "USB Devices (Read-Only View)"
$DeviceGroup.Location = New-Object System.Drawing.Point(20, 110)
$DeviceGroup.Size = New-Object System.Drawing.Size(745, 220)
$DeviceGroup.Font = New-Object System.Drawing.Font("Segoe UI", 10)
$script:MainForm.Controls.Add($DeviceGroup)

$script:DeviceListView = New-Object System.Windows.Forms.ListView
$script:DeviceListView.Location = New-Object System.Drawing.Point(10, 25)
$script:DeviceListView.Size = New-Object System.Drawing.Size(725, 185)
$script:DeviceListView.View = "Details"
$script:DeviceListView.FullRowSelect = $true
$script:DeviceListView.GridLines = $true
$script:DeviceListView.CheckBoxes = $false
$script:DeviceListView.Font = New-Object System.Drawing.Font("Segoe UI", 9)
[void]$script:DeviceListView.Columns.Add("Device Name", 430)
[void]$script:DeviceListView.Columns.Add("Status", 100)
[void]$script:DeviceListView.Columns.Add("Power Mgmt", 150)
$DeviceGroup.Controls.Add($script:DeviceListView)

# Progress bar
$script:ProgressBar = New-Object System.Windows.Forms.ProgressBar
$script:ProgressBar.Location = New-Object System.Drawing.Point(20, 340)
$script:ProgressBar.Size = New-Object System.Drawing.Size(745, 25)
$script:ProgressBar.Style = "Continuous"
$script:MainForm.Controls.Add($script:ProgressBar)

# Log group
$LogGroup = New-Object System.Windows.Forms.GroupBox
$LogGroup.Text = "Activity Log"
$LogGroup.Location = New-Object System.Drawing.Point(20, 375)
$LogGroup.Size = New-Object System.Drawing.Size(745, 180)
$LogGroup.Font = New-Object System.Drawing.Font("Segoe UI", 10)
$script:MainForm.Controls.Add($LogGroup)

$script:LogTextBox = New-Object System.Windows.Forms.RichTextBox
$script:LogTextBox.Location = New-Object System.Drawing.Point(10, 25)
$script:LogTextBox.Size = New-Object System.Drawing.Size(725, 145)
$script:LogTextBox.Font = New-Object System.Drawing.Font("Consolas", 9)
$script:LogTextBox.ReadOnly = $true
$script:LogTextBox.BackColor = [System.Drawing.Color]::White
$LogGroup.Controls.Add($script:LogTextBox)

# Buttons
$ButtonPanel = New-Object System.Windows.Forms.Panel
$ButtonPanel.Location = New-Object System.Drawing.Point(20, 565)
$ButtonPanel.Size = New-Object System.Drawing.Size(745, 40)
$script:MainForm.Controls.Add($ButtonPanel)

$script:StatusLabel = New-Object System.Windows.Forms.Label
$script:StatusLabel.Location = New-Object System.Drawing.Point(0, 10)
$script:StatusLabel.Size = New-Object System.Drawing.Size(200, 25)
$script:StatusLabel.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$script:StatusLabel.ForeColor = [System.Drawing.Color]::Gray
$ButtonPanel.Controls.Add($script:StatusLabel)

$script:ExportLogButton = New-Object System.Windows.Forms.Button
$script:ExportLogButton.Text = "Export Log"
$script:ExportLogButton.Location = New-Object System.Drawing.Point(210, 5)
$script:ExportLogButton.Size = New-Object System.Drawing.Size(90, 30)
$script:ExportLogButton.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$script:ExportLogButton.Add_Click({ Export-Log })
$ButtonPanel.Controls.Add($script:ExportLogButton)

$script:RefreshButton = New-Object System.Windows.Forms.Button
$script:RefreshButton.Text = "Refresh"
$script:RefreshButton.Location = New-Object System.Drawing.Point(310, 5)
$script:RefreshButton.Size = New-Object System.Drawing.Size(90, 30)
$script:RefreshButton.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$script:RefreshButton.Add_Click({ Update-DeviceList })
$ButtonPanel.Controls.Add($script:RefreshButton)

$script:RestoreButton = New-Object System.Windows.Forms.Button
$script:RestoreButton.Text = "Restore Defaults"
$script:RestoreButton.Location = New-Object System.Drawing.Point(410, 5)
$script:RestoreButton.Size = New-Object System.Drawing.Size(115, 30)
$script:RestoreButton.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$script:RestoreButton.BackColor = [System.Drawing.Color]::FromArgb(255, 193, 7)
$script:RestoreButton.ForeColor = [System.Drawing.Color]::Black
$script:RestoreButton.FlatStyle = "Flat"
$script:RestoreButton.Add_Click({ Start-RestorePowerManagement })
$ButtonPanel.Controls.Add($script:RestoreButton)

$script:DisableButton = New-Object System.Windows.Forms.Button
$script:DisableButton.Text = "Disable Power Mgmt"
$script:DisableButton.Location = New-Object System.Drawing.Point(535, 5)
$script:DisableButton.Size = New-Object System.Drawing.Size(135, 30)
$script:DisableButton.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
$script:DisableButton.BackColor = [System.Drawing.Color]::FromArgb(0, 120, 215)
$script:DisableButton.ForeColor = [System.Drawing.Color]::White
$script:DisableButton.FlatStyle = "Flat"
$script:DisableButton.Add_Click({ Start-DisablePowerManagement })
$ButtonPanel.Controls.Add($script:DisableButton)

# Add tooltips
$tooltip = New-Object System.Windows.Forms.ToolTip
$tooltip.SetToolTip($script:RestoreButton, "Restore Windows default USB power management settings")
$tooltip.SetToolTip($script:DisableButton, "Disable power management for all USB devices to prevent disconnections")
$tooltip.SetToolTip($script:ExportLogButton, "Save the activity log to a file")
$tooltip.SetToolTip($script:RefreshButton, "Refresh the USB device list")

# Load devices
Update-DeviceList

# Show form and run application loop
[System.Windows.Forms.Application]::Run($script:MainForm)

# Clean up resources when form closes
# Note: Child controls are automatically disposed when their parent form is disposed
# We only need to dispose the tooltip (not parented) and the form itself
try {
    if ($null -ne $tooltip -and -not $tooltip.IsDisposed) { $tooltip.Dispose() }
    if ($null -ne $script:MainForm -and -not $script:MainForm.IsDisposed) { $script:MainForm.Dispose() }
} catch {
    # Silently ignore disposal errors during cleanup
}
