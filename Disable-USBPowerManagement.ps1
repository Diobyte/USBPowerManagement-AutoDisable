<#
.SYNOPSIS
    Disables USB power management settings to prevent Windows from turning off USB devices to save power.

.DESCRIPTION
    This script performs the following:
    1. Disables USB selective suspend in all power plans
    2. Disables "Allow the computer to turn off this device to save power" for all USB controllers and hubs
    3. Configures USB service parameters to prevent selective suspend
    4. Generates a detailed report of USB device power management status
    
    Compatible with Windows 7, 8, 8.1, 10, and 11.

.PARAMETER ReportOnly
    Generates a report of USB device power management status without making any changes.

.PARAMETER NoRestartPrompt
    Skips the restart confirmation prompt at the end of execution.

.PARAMETER EnableLogging
    Enables transcript logging to a timestamped file in the script directory.

.PARAMETER Restore
    Restores USB power management settings to Windows defaults (re-enables power saving).

.PARAMETER ExportReport
    Exports the USB device report to a file. Supported formats: .csv, .json, .txt

.EXAMPLE
    .\Disable-USBPowerManagement.ps1
    Runs the script and disables all USB power management features.

.EXAMPLE
    .\Disable-USBPowerManagement.ps1 -ReportOnly
    Generates a report without making any changes.

.EXAMPLE
    .\Disable-USBPowerManagement.ps1 -EnableLogging -NoRestartPrompt
    Runs with logging enabled and skips the restart prompt (useful for automation).

.EXAMPLE
    .\Disable-USBPowerManagement.ps1 -Restore
    Restores USB power management to Windows default settings.

.EXAMPLE
    .\Disable-USBPowerManagement.ps1 -ReportOnly -ExportReport "C:\Reports\usb-report.csv"
    Generates a report and exports it to a CSV file.

.OUTPUTS
    None. This script does not return any objects but outputs status messages to the console.

.NOTES
    Author: Diobyte
    Requires: Administrator privileges
    Version: 1.4.0
    Date: 2026-01-19
    Compatibility: Windows 7/8/8.1/10/11, PowerShell 3.0+
    License: MIT
    Repository: https://github.com/Diobyte/USBPowerManagement-AutoDisable
#>

#Requires -RunAsAdministrator
#Requires -Version 3.0

[CmdletBinding(DefaultParameterSetName = 'Disable')]
param(
    [Parameter(ParameterSetName = 'Disable', HelpMessage = "Generate report only without making changes")]
    [Parameter(ParameterSetName = 'Report')]
    [switch]$ReportOnly,
    
    [Parameter(ParameterSetName = 'Disable', HelpMessage = "Skip the restart prompt at the end")]
    [Parameter(ParameterSetName = 'Restore')]
    [switch]$NoRestartPrompt,
    
    [Parameter(ParameterSetName = 'Disable', HelpMessage = "Enable transcript logging to file")]
    [Parameter(ParameterSetName = 'Restore')]
    [Parameter(ParameterSetName = 'Report')]
    [switch]$EnableLogging,
    
    [Parameter(ParameterSetName = 'Restore', HelpMessage = "Restore USB power management settings to Windows defaults")]
    [switch]$Restore,
    
    [Parameter(HelpMessage = "Export report to file (CSV, JSON, or TXT)")]
    [ValidateScript({
        $ext = [System.IO.Path]::GetExtension($_).ToLower()
        if ($ext -in @('.csv', '.json', '.txt')) { $true }
        else { throw "ExportReport must be a .csv, .json, or .txt file" }
    })]
    [string]$ExportReport
)

# Set strict mode for better error detection
Set-StrictMode -Version Latest

# Set error handling
$ErrorActionPreference = "Continue"

# Initialize script-level variables
$script:TotalDevicesModified = 0
$script:TotalDevicesFailed = 0

# Ensure we're running in a supported Windows version
$script:osVersion = [System.Environment]::OSVersion.Version
if ($script:osVersion.Major -lt 6 -or ($script:osVersion.Major -eq 6 -and $script:osVersion.Minor -lt 1)) {
    Write-Host "This script requires Windows 7 or later." -ForegroundColor Red
    exit 1
}

# Start transcript logging if enabled
if ($EnableLogging) {
    $logPath = Join-Path $PSScriptRoot "USBPowerManagement_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
    try {
        Start-Transcript -Path $logPath -ErrorAction Stop
        Write-Host "Logging enabled: $logPath" -ForegroundColor Gray
    }
    catch {
        Write-Host "Warning: Could not start transcript logging: $($_.Exception.Message)" -ForegroundColor Yellow
    }
}

# Function to write colored output with proper formatting
# Uses Write-Information with tags for PowerShell 5.0+ compatibility
function Write-Status {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Message,
        
        [Parameter()]
        [ValidateSet("Success", "Error", "Warning", "Info", "Debug")]
        [string]$Type = "Info"
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $formattedMessage = "[$timestamp] [$($Type.ToUpper())] $Message"
    
    # Use Write-Information with tags for PowerShell 5.0+ (allows filtering via -InformationAction)
    if ($PSVersionTable.PSVersion.Major -ge 5) {
        $tags = @("USBPowerManagement", $Type)
        Write-Information -MessageData $formattedMessage -Tags $tags
    }
    
    # Always output to host with color for visual feedback
    switch ($Type) {
        "Success" { Write-Host $formattedMessage -ForegroundColor Green }
        "Error"   { Write-Host $formattedMessage -ForegroundColor Red }
        "Warning" { Write-Host $formattedMessage -ForegroundColor Yellow }
        "Info"    { Write-Host $formattedMessage -ForegroundColor Cyan }
        "Debug"   { Write-Verbose $formattedMessage }
    }
}

# Function to check Windows version
function Get-WindowsVersion {
    try {
        # Try CIM first (PowerShell 3.0+)
        $osInfo = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
        $version = [System.Environment]::OSVersion.Version
        
        Write-Status "Operating System: $($osInfo.Caption)" "Info"
        Write-Status "Version: $($osInfo.Version)" "Info"
        Write-Status "Architecture: $($env:PROCESSOR_ARCHITECTURE)" "Info"
        
        return $version
    }
    catch {
        # Fallback to WMI for older systems or if CIM fails
        try {
            $osInfo = Get-WmiObject -Class Win32_OperatingSystem -ErrorAction Stop
            $version = [System.Environment]::OSVersion.Version
            
            Write-Status "Operating System: $($osInfo.Caption)" "Info"
            Write-Status "Version: $($osInfo.Version)" "Info"
            Write-Status "Architecture: $($env:PROCESSOR_ARCHITECTURE)" "Info"
            
            return $version
        }
        catch {
            # Final fallback - use .NET directly
            $version = [System.Environment]::OSVersion.Version
            Write-Status "Windows Version: $($version.Major).$($version.Minor).$($version.Build)" "Info"
            return $version
        }
    }
}

# Function to disable USB Selective Suspend in all power plans
function Disable-USBSelectiveSuspend {
    [CmdletBinding()]
    param()
    
    Write-Status "Disabling USB Selective Suspend in all power plans..." "Info"
    
    if ($script:ReportOnly) {
        Write-Status "Report-only mode: Skipping power plan modifications" "Info"
        return
    }
    
    try {
        # Check if powercfg exists
        $powercfgPath = Join-Path $env:SystemRoot "System32\powercfg.exe"
        if (-not (Test-Path -LiteralPath $powercfgPath)) {
            Write-Status "powercfg.exe not found. Skipping power plan configuration." "Warning"
            return
        }
        
        # Get all power plans
        $powerPlans = & $powercfgPath /list 2>&1
        
        if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($powerPlans)) {
            Write-Status "Failed to retrieve power plans" "Warning"
            return
        }
        
        # Extract GUIDs of all power plans
        $planGuids = [regex]::Matches($powerPlans, '([a-fA-F0-9]{8}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{12})') | 
                     ForEach-Object { $_.Groups[1].Value } | 
                     Select-Object -Unique
        
        if ($planGuids.Count -eq 0) {
            Write-Status "No power plans found" "Warning"
            return
        }
        
        # USB Settings GUID
        $usbSettingsGuid = "2a737441-1930-4402-8d77-b2bebba308a3"
        # USB Selective Suspend setting GUID
        $usbSelectiveSuspendGuid = "48e6b7a6-50f5-4782-a5d4-53bb8f07e226"
        
        foreach ($planGuid in $planGuids) {
            Write-Status "Processing power plan: $planGuid" "Info"
            
            # Disable USB selective suspend on AC power (0 = Disabled)
            $null = & $powercfgPath /setacvalueindex $planGuid $usbSettingsGuid $usbSelectiveSuspendGuid 0 2>&1
            
            # Disable USB selective suspend on DC (battery) power (0 = Disabled)
            $null = & $powercfgPath /setdcvalueindex $planGuid $usbSettingsGuid $usbSelectiveSuspendGuid 0 2>&1
            
            Write-Status "USB Selective Suspend disabled for plan: $planGuid" "Success"
        }
        
        # Apply changes to active power plan
        $activePlan = & $powercfgPath /getactivescheme 2>&1
        if ($activePlan -match '([a-fA-F0-9]{8}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{12})') {
            $activeGuid = $matches[1]
            $null = & $powercfgPath /setactive $activeGuid 2>&1
            Write-Status "Reactivated current power plan to apply changes" "Success"
        }
        
        Write-Status "USB Selective Suspend has been disabled in all power plans" "Success"
    }
    catch {
        Write-Status "Failed to disable USB Selective Suspend: $($_.Exception.Message)" "Error"
    }
}

# Function to disable power management for USB devices via registry
function Disable-USBDevicePowerManagement {
    [CmdletBinding()]
    param()
    
    Write-Status "Disabling power management for all USB devices..." "Info"
    
    if ($script:ReportOnly) {
        Write-Status "Report-only mode: Skipping device power management modifications" "Info"
        return
    }
    
    $devicesModified = 0
    $devicesFailed = 0
    
    try {
        # Get all USB-related devices using multiple methods for robustness
        # Try CIM first (modern), fallback to WMI (legacy) for compatibility
        try {
            $allDevices = Get-CimInstance -ClassName Win32_PnPEntity -ErrorAction Stop | Where-Object {
                $_.PNPDeviceID -like "USB\*" -or 
                $_.PNPDeviceID -like "USBSTOR\*" -or
                $_.Name -like "*USB*Hub*" -or
                $_.Name -like "*USB*Controller*" -or
                $_.Name -like "*USB*Root*" -or
                $_.Name -like "*Universal Serial Bus*" -or
                $_.Name -like "*eXtensible Host Controller*" -or
                $_.Name -like "*Enhanced Host Controller*" -or
                $_.Name -like "*Open Host Controller*" -or
                $_.Name -like "*Universal Host Controller*"
            }
        }
        catch {
            # Fallback to WMI for older systems or PowerShell Core without CimCmdlets
            # Note: Get-WmiObject is deprecated in PowerShell Core but available in Windows PowerShell
            $allDevices = Get-WmiObject -Class Win32_PnPEntity -ErrorAction SilentlyContinue | Where-Object {
                $_.PNPDeviceID -like "USB\*" -or 
                $_.PNPDeviceID -like "USBSTOR\*" -or
                $_.Name -like "*USB*Hub*" -or
                $_.Name -like "*USB*Controller*" -or
                $_.Name -like "*USB*Root*" -or
                $_.Name -like "*Universal Serial Bus*" -or
                $_.Name -like "*eXtensible Host Controller*" -or
                $_.Name -like "*Enhanced Host Controller*" -or
                $_.Name -like "*Open Host Controller*" -or
                $_.Name -like "*Universal Host Controller*"
            }
        }
        
        $deviceCount = if ($null -eq $allDevices) { 0 } else { @($allDevices).Count }
        Write-Status "Found $deviceCount USB-related devices" "Info"
        
        if ($null -eq $allDevices -or $deviceCount -eq 0) {
            Write-Status "No USB devices found to process" "Warning"
            return
        }
        
        $processedCount = 0
        foreach ($device in $allDevices) {
            $processedCount++
            $deviceId = $device.PNPDeviceID
            $deviceName = if ([string]::IsNullOrEmpty($device.Name)) { "Unknown Device" } else { $device.Name }
            
            if ([string]::IsNullOrEmpty($deviceId)) {
                continue
            }
            
            Write-Status "Processing: $deviceName" "Info"
            
            $deviceKeyFound = $false
            
            # Find the actual registry key for this device
            $enumPath = "HKLM:\SYSTEM\CurrentControlSet\Enum\$deviceId"
            
            # Handle multi-instance devices
            if (Test-Path $enumPath) {
                $subKeys = Get-ChildItem -Path $enumPath -ErrorAction SilentlyContinue
                
                foreach ($subKey in $subKeys) {
                    $deviceParamsPath = Join-Path $subKey.PSPath "Device Parameters"
                    
                    if (Test-Path $deviceParamsPath) {
                        try {
                            # Set EnhancedPowerManagementEnabled to 0 (disabled)
                            Set-ItemProperty -Path $deviceParamsPath -Name "EnhancedPowerManagementEnabled" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
                            
                            # Set SelectiveSuspendEnabled to 0 (disabled)
                            Set-ItemProperty -Path $deviceParamsPath -Name "SelectiveSuspendEnabled" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
                            
                            # Set AllowIdleIrpInD3 to 0 (disabled)
                            Set-ItemProperty -Path $deviceParamsPath -Name "AllowIdleIrpInD3" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
                            
                            $deviceKeyFound = $true
                            $devicesModified++
                            Write-Status "  Modified registry for: $deviceName" "Success"
                        }
                        catch {
                            Write-Status "  Failed to modify registry for: $deviceName - $($_.Exception.Message)" "Warning"
                        }
                    }
                }
            }
            
            if (-not $deviceKeyFound) {
                # Create Device Parameters key if it doesn't exist
                $directPath = "HKLM:\SYSTEM\CurrentControlSet\Enum\$deviceId"
                $subKeysAlt = Get-ChildItem -Path $directPath -ErrorAction SilentlyContinue
                
                foreach ($subKey in $subKeysAlt) {
                    $deviceParamsPath = Join-Path $subKey.PSPath "Device Parameters"
                    
                    try {
                        if (-not (Test-Path $deviceParamsPath)) {
                            New-Item -Path $deviceParamsPath -Force -ErrorAction SilentlyContinue | Out-Null
                        }
                        
                        if (Test-Path $deviceParamsPath) {
                            Set-ItemProperty -Path $deviceParamsPath -Name "EnhancedPowerManagementEnabled" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
                            Set-ItemProperty -Path $deviceParamsPath -Name "SelectiveSuspendEnabled" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
                            Set-ItemProperty -Path $deviceParamsPath -Name "AllowIdleIrpInD3" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
                            
                            $devicesModified++
                            Write-Status "  Created and modified registry for: $deviceName" "Success"
                        }
                    }
                    catch {
                        $devicesFailed++
                        Write-Status "  Could not modify: $deviceName" "Warning"
                    }
                }
            }
        }
        
        Write-Status "Registry modifications complete. Modified: $devicesModified, Skipped/Failed: $devicesFailed" "Info"
        $script:TotalDevicesModified += $devicesModified
        $script:TotalDevicesFailed += $devicesFailed
    }
    catch {
        Write-Status "Error during registry modifications: $($_.Exception.Message)" "Error"
    }
}

# Function to disable power management using Device Manager properties (PnPUtil method)
function Disable-DevicePowerManagementPnP {
    [CmdletBinding()]
    param()
    
    Write-Status "Disabling power management via PnP device properties..." "Info"
    
    if ($script:ReportOnly) {
        Write-Status "Report-only mode: Skipping PnP power management modifications" "Info"
        return
    }
    
    try {
        # Check if Get-PnpDevice cmdlet is available (may not be on older systems)
        $pnpCmdletAvailable = Get-Command Get-PnpDevice -ErrorAction SilentlyContinue
        
        if (-not $pnpCmdletAvailable) {
            Write-Status "Get-PnpDevice cmdlet not available on this system. Using fallback method." "Warning"
            return
        }
        
        # Get USB devices with power management capability
        $devices = Get-PnpDevice | Where-Object {
            ($_.InstanceId -like "USB\*" -or $_.InstanceId -like "USBSTOR\*") -and
            $_.Status -eq "OK"
        }
        
        Write-Status "Found $($devices.Count) active USB PnP devices" "Info"
        
        foreach ($device in $devices) {
            try {
                $instanceId = $device.InstanceId
                $friendlyName = $device.FriendlyName
                
                if ([string]::IsNullOrEmpty($friendlyName)) {
                    $friendlyName = $device.Description
                }
                
                # Get power management capabilities (WMI namespace may not exist on all systems)
                $powerMgmt = $null
                try {
                    $powerMgmt = Get-CimInstance -ClassName MSPower_DeviceEnable -Namespace root\WMI -ErrorAction Stop | 
                                 Where-Object { $_.InstanceName -like "*$($instanceId -replace '\\', '_')*" }
                } catch {
                    # WMI power namespace may not be available on all systems - this is normal
                }
                
                if ($powerMgmt) {
                    # Disable power management
                    foreach ($pm in $powerMgmt) {
                        try {
                            $pm | Set-CimInstance -Property @{ Enable = $false } -ErrorAction SilentlyContinue
                            Write-Status "  Disabled WMI power management for: $friendlyName" "Success"
                        }
                        catch {
                            Write-Status "  Could not disable WMI power management for: $friendlyName" "Warning"
                        }
                    }
                }
                
                # Also try MSPower_DeviceWakeEnable
                $wakeEnable = Get-CimInstance -ClassName MSPower_DeviceWakeEnable -Namespace root\WMI -ErrorAction SilentlyContinue |
                              Where-Object { $_.InstanceName -like "*$($instanceId -replace '\\', '_')*" }
                
                if ($wakeEnable) {
                    foreach ($we in $wakeEnable) {
                        try {
                            # We don't disable wake - just power management
                            # $we | Set-CimInstance -Property @{ Enable = $false } -ErrorAction SilentlyContinue
                        }
                        catch {
                            # Silently continue
                        }
                    }
                }
            }
            catch {
                Write-Status "  Error processing device: $($_.Exception.Message)" "Warning"
            }
        }
    }
    catch {
        Write-Status "Error during PnP power management configuration: $($_.Exception.Message)" "Error"
    }
}

# Function to modify USB hub power management directly
function Disable-USBHubPowerManagement {
    [CmdletBinding()]
    param()
    
    Write-Status "Configuring USB Hub specific power management..." "Info"
    
    if ($script:ReportOnly) {
        Write-Status "Report-only mode: Skipping USB Hub modifications" "Info"
        return
    }
    
    try {
        # Find all USB hubs and root hubs in registry
        $usbEnumPath = "HKLM:\SYSTEM\CurrentControlSet\Enum\USB"
        
        if (Test-Path $usbEnumPath) {
            $usbDevices = Get-ChildItem -Path $usbEnumPath -Recurse -ErrorAction SilentlyContinue
            
            foreach ($item in $usbDevices) {
                if ($item.PSChildName -eq "Device Parameters") {
                    try {
                        # Disable all power management options
                        Set-ItemProperty -Path $item.PSPath -Name "EnhancedPowerManagementEnabled" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
                        Set-ItemProperty -Path $item.PSPath -Name "SelectiveSuspendEnabled" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
                        Set-ItemProperty -Path $item.PSPath -Name "AllowIdleIrpInD3" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
                        Set-ItemProperty -Path $item.PSPath -Name "DeviceSelectiveSuspended" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
                        Set-ItemProperty -Path $item.PSPath -Name "SelectiveSuspendSupported" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
                    }
                    catch {
                        # Continue silently
                    }
                }
            }
            
            Write-Status "USB Hub power management settings updated" "Success"
        }
        
        # Also process USBSTOR devices
        $usbStorPath = "HKLM:\SYSTEM\CurrentControlSet\Enum\USBSTOR"
        
        if (Test-Path $usbStorPath) {
            $usbStorDevices = Get-ChildItem -Path $usbStorPath -Recurse -ErrorAction SilentlyContinue
            
            foreach ($item in $usbStorDevices) {
                if ($item.PSChildName -eq "Device Parameters") {
                    try {
                        Set-ItemProperty -Path $item.PSPath -Name "EnhancedPowerManagementEnabled" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
                        Set-ItemProperty -Path $item.PSPath -Name "SelectiveSuspendEnabled" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
                        Set-ItemProperty -Path $item.PSPath -Name "AllowIdleIrpInD3" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
                    }
                    catch {
                        # Continue silently
                    }
                }
            }
            
            Write-Status "USB Storage power management settings updated" "Success"
        }
    }
    catch {
        Write-Status "Error during USB Hub configuration: $($_.Exception.Message)" "Error"
    }
}

# Function to disable USB power management via services
function Set-USBServicesConfiguration {
    [CmdletBinding()]
    param()
    
    Write-Status "Configuring USB-related service settings..." "Info"
    
    if ($script:ReportOnly) {
        Write-Status "Report-only mode: Skipping USB service modifications" "Info"
        return
    }
    
    try {
        # List of all possible USB service paths to configure
        $usbServices = @(
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
        
        foreach ($service in $usbServices) {
            if (Test-Path $service.Path) {
                $paramsPath = "$($service.Path)\Parameters"
                
                # Create Parameters key if it doesn't exist
                if (-not (Test-Path $paramsPath)) {
                    New-Item -Path $paramsPath -Force -ErrorAction SilentlyContinue | Out-Null
                }
                
                if (Test-Path $paramsPath) {
                    Set-ItemProperty -Path $paramsPath -Name "DisableSelectiveSuspend" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
                    Write-Status "$($service.Name) service selective suspend disabled" "Success"
                }
                
                # Also set at service root level for some drivers
                Set-ItemProperty -Path $service.Path -Name "DisableSelectiveSuspend" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
            }
        }
    }
    catch {
        Write-Status "Error configuring USB services: $($_.Exception.Message)" "Error"
    }
}

# Function to restore USB power management to Windows defaults
function Enable-USBPowerManagement {
    [CmdletBinding()]
    param()
    
    Write-Status "Restoring USB power management to Windows defaults..." "Info"
    
    $devicesRestored = 0
    
    try {
        # Restore USB Selective Suspend in power plans
        Write-Status "Enabling USB Selective Suspend in power plans..." "Info"
        
        $powercfgPath = Join-Path $env:SystemRoot "System32\powercfg.exe"
        if (Test-Path -LiteralPath $powercfgPath) {
            $powerPlans = & $powercfgPath /list 2>&1
            $planGuids = [regex]::Matches($powerPlans, '([a-fA-F0-9]{8}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{12})') | 
                         ForEach-Object { $_.Groups[1].Value } | 
                         Select-Object -Unique
            
            $usbSettingsGuid = "2a737441-1930-4402-8d77-b2bebba308a3"
            $usbSelectiveSuspendGuid = "48e6b7a6-50f5-4782-a5d4-53bb8f07e226"
            
            foreach ($planGuid in $planGuids) {
                # Enable USB selective suspend (1 = Enabled)
                $null = & $powercfgPath /setacvalueindex $planGuid $usbSettingsGuid $usbSelectiveSuspendGuid 1 2>&1
                $null = & $powercfgPath /setdcvalueindex $planGuid $usbSettingsGuid $usbSelectiveSuspendGuid 1 2>&1
            }
            Write-Status "USB Selective Suspend enabled in all power plans" "Success"
        }
        
        # Remove/restore registry settings for USB devices
        Write-Status "Restoring USB device registry settings..." "Info"
        
        $usbEnumPath = "HKLM:\SYSTEM\CurrentControlSet\Enum\USB"
        if (Test-Path $usbEnumPath) {
            $usbDevices = Get-ChildItem -Path $usbEnumPath -Recurse -ErrorAction SilentlyContinue
            
            foreach ($item in $usbDevices) {
                if ($item.PSChildName -eq "Device Parameters") {
                    try {
                        # Remove our custom settings (restore to Windows default behavior)
                        Remove-ItemProperty -Path $item.PSPath -Name "EnhancedPowerManagementEnabled" -Force -ErrorAction SilentlyContinue
                        Remove-ItemProperty -Path $item.PSPath -Name "SelectiveSuspendEnabled" -Force -ErrorAction SilentlyContinue
                        Remove-ItemProperty -Path $item.PSPath -Name "AllowIdleIrpInD3" -Force -ErrorAction SilentlyContinue
                        Remove-ItemProperty -Path $item.PSPath -Name "DeviceSelectiveSuspended" -Force -ErrorAction SilentlyContinue
                        Remove-ItemProperty -Path $item.PSPath -Name "SelectiveSuspendSupported" -Force -ErrorAction SilentlyContinue
                        $devicesRestored++
                    }
                    catch {
                        # Continue silently
                    }
                }
            }
        }
        
        # Restore USBSTOR settings
        $usbStorPath = "HKLM:\SYSTEM\CurrentControlSet\Enum\USBSTOR"
        if (Test-Path $usbStorPath) {
            $usbStorDevices = Get-ChildItem -Path $usbStorPath -Recurse -ErrorAction SilentlyContinue
            
            foreach ($item in $usbStorDevices) {
                if ($item.PSChildName -eq "Device Parameters") {
                    try {
                        Remove-ItemProperty -Path $item.PSPath -Name "EnhancedPowerManagementEnabled" -Force -ErrorAction SilentlyContinue
                        Remove-ItemProperty -Path $item.PSPath -Name "SelectiveSuspendEnabled" -Force -ErrorAction SilentlyContinue
                        Remove-ItemProperty -Path $item.PSPath -Name "AllowIdleIrpInD3" -Force -ErrorAction SilentlyContinue
                        $devicesRestored++
                    }
                    catch {
                        # Continue silently
                    }
                }
            }
        }
        
        # Remove service configuration
        Write-Status "Restoring USB service settings..." "Info"
        
        $usbServices = @(
            "HKLM:\SYSTEM\CurrentControlSet\Services\USB",
            "HKLM:\SYSTEM\CurrentControlSet\Services\usbhub",
            "HKLM:\SYSTEM\CurrentControlSet\Services\usbhub3",
            "HKLM:\SYSTEM\CurrentControlSet\Services\USBXHCI",
            "HKLM:\SYSTEM\CurrentControlSet\Services\usbehci",
            "HKLM:\SYSTEM\CurrentControlSet\Services\usbuhci",
            "HKLM:\SYSTEM\CurrentControlSet\Services\usbohci",
            "HKLM:\SYSTEM\CurrentControlSet\Services\usbccgp",
            "HKLM:\SYSTEM\CurrentControlSet\Services\USBSTOR"
        )
        
        foreach ($servicePath in $usbServices) {
            if (Test-Path $servicePath) {
                $paramsPath = "$servicePath\Parameters"
                if (Test-Path $paramsPath) {
                    Remove-ItemProperty -Path $paramsPath -Name "DisableSelectiveSuspend" -Force -ErrorAction SilentlyContinue
                }
                Remove-ItemProperty -Path $servicePath -Name "DisableSelectiveSuspend" -Force -ErrorAction SilentlyContinue
            }
        }
        
        Write-Status "USB power management restored for $devicesRestored device entries" "Success"
        Write-Status "USB services restored to defaults" "Success"
    }
    catch {
        Write-Status "Error during restore: $($_.Exception.Message)" "Error"
    }
}

# Function to generate report of USB devices and their power status
function Get-USBPowerReport {
    [CmdletBinding()]
    param(
        [string]$ExportPath
    )
    
    Write-Status "Generating USB device power management report..." "Info"
    
    # Collect device data for potential export
    $reportData = @()
    
    Write-Host ("`n" + ("=" * 80)) -ForegroundColor Cyan
    Write-Host "USB DEVICE POWER MANAGEMENT REPORT" -ForegroundColor Cyan
    Write-Host ("=" * 80) -ForegroundColor Cyan
    
    # Check if Get-PnpDevice is available
    $pnpCmdletAvailable = Get-Command Get-PnpDevice -ErrorAction SilentlyContinue
    
    if (-not $pnpCmdletAvailable) {
        # Fallback to WMI/CIM method
        try {
            $devices = Get-CimInstance -ClassName Win32_PnPEntity -ErrorAction Stop | Where-Object {
                ($_.PNPDeviceID -like "USB\*" -or $_.PNPDeviceID -like "USBSTOR\*") -and
                $_.Status -eq "OK"
            } | Select-Object @{N='FriendlyName';E={$_.Name}}, @{N='Description';E={$_.Description}}, @{N='InstanceId';E={$_.PNPDeviceID}}, Status
        }
        catch {
            # Final fallback to WMI
            $devices = Get-WmiObject -Class Win32_PnPEntity -ErrorAction SilentlyContinue | Where-Object {
                ($_.PNPDeviceID -like "USB\*" -or $_.PNPDeviceID -like "USBSTOR\*") -and
                $_.Status -eq "OK"
            } | Select-Object @{N='FriendlyName';E={$_.Name}}, @{N='Description';E={$_.Description}}, @{N='InstanceId';E={$_.PNPDeviceID}}, Status
        }
    } else {
        $devices = Get-PnpDevice | Where-Object {
            ($_.InstanceId -like "USB\*" -or $_.InstanceId -like "USBSTOR\*") -and
            $_.Status -eq "OK"
        } | Select-Object FriendlyName, Description, InstanceId, Status
    }
    
    $counter = 1
    foreach ($device in $devices) {
        $name = if ($device.FriendlyName) { $device.FriendlyName } else { $device.Description }
        Write-Host "`n$counter. $name" -ForegroundColor White
        Write-Host "   Instance ID: $($device.InstanceId)" -ForegroundColor Gray
        
        # Initialize device report entry
        $deviceReport = [PSCustomObject]@{
            Number = $counter
            Name = $name
            InstanceId = $device.InstanceId
            Status = $device.Status
            EnhancedPowerManagement = "Not Set"
            SelectiveSuspend = "Not Set"
        }
        
        # Check registry settings
        $instancePath = $device.InstanceId
        $regPath = "HKLM:\SYSTEM\CurrentControlSet\Enum\$instancePath"
        
        $subKeys = Get-ChildItem -Path $regPath -ErrorAction SilentlyContinue
        foreach ($subKey in $subKeys) {
            $deviceParamsPath = Join-Path $subKey.PSPath "Device Parameters"
            if (Test-Path $deviceParamsPath) {
                $enhancedPM = Get-ItemProperty -Path $deviceParamsPath -Name "EnhancedPowerManagementEnabled" -ErrorAction SilentlyContinue
                $selectiveSuspend = Get-ItemProperty -Path $deviceParamsPath -Name "SelectiveSuspendEnabled" -ErrorAction SilentlyContinue
                
                if ($enhancedPM) {
                    $pmStatus = if ($enhancedPM.EnhancedPowerManagementEnabled -eq 0) { "Disabled" } else { "Enabled" }
                    $deviceReport.EnhancedPowerManagement = $pmStatus
                    Write-Host "   Enhanced Power Management: $pmStatus" -ForegroundColor $(if ($pmStatus -eq "Disabled") { "Green" } else { "Yellow" })
                }
                if ($selectiveSuspend) {
                    $ssStatus = if ($selectiveSuspend.SelectiveSuspendEnabled -eq 0) { "Disabled" } else { "Enabled" }
                    $deviceReport.SelectiveSuspend = $ssStatus
                    Write-Host "   Selective Suspend: $ssStatus" -ForegroundColor $(if ($ssStatus -eq "Disabled") { "Green" } else { "Yellow" })
                }
            }
        }
        
        $reportData += $deviceReport
        $counter++
    }
    
    Write-Host ("`n" + ("=" * 80)) -ForegroundColor Cyan
    
    # Export report if path specified
    if ($ExportPath) {
        try {
            $extension = [System.IO.Path]::GetExtension($ExportPath).ToLower()
            
            switch ($extension) {
                '.csv' {
                    $reportData | Export-Csv -Path $ExportPath -NoTypeInformation -Encoding UTF8
                    Write-Status "Report exported to CSV: $ExportPath" "Success"
                }
                '.json' {
                    $reportData | ConvertTo-Json -Depth 3 | Out-File -FilePath $ExportPath -Encoding UTF8
                    Write-Status "Report exported to JSON: $ExportPath" "Success"
                }
                '.txt' {
                    $txtContent = @()
                    $txtContent += "USB POWER MANAGEMENT REPORT"
                    $txtContent += "Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
                    $txtContent += "=" * 80
                    $txtContent += ""
                    
                    foreach ($item in $reportData) {
                        $txtContent += "$($item.Number). $($item.Name)"
                        $txtContent += "   Instance ID: $($item.InstanceId)"
                        $txtContent += "   Status: $($item.Status)"
                        $txtContent += "   Enhanced Power Management: $($item.EnhancedPowerManagement)"
                        $txtContent += "   Selective Suspend: $($item.SelectiveSuspend)"
                        $txtContent += ""
                    }
                    
                    $txtContent | Out-File -FilePath $ExportPath -Encoding UTF8
                    Write-Status "Report exported to TXT: $ExportPath" "Success"
                }
            }
        }
        catch {
            Write-Status "Failed to export report: $($_.Exception.Message)" "Error"
        }
    }
    
    return $reportData
}

# Main execution
function Main {
    [CmdletBinding()]
    param()
    
    # Store parameters at script level for use in functions
    $script:ReportOnly = $ReportOnly
    
    Write-Host ("`n" + ("=" * 80)) -ForegroundColor Cyan
    Write-Host "USB POWER MANAGEMENT CONFIGURATION SCRIPT" -ForegroundColor Cyan
    if ($Restore) {
        Write-Host "Mode: RESTORE (Re-enabling USB power management)" -ForegroundColor Yellow
    } elseif ($ReportOnly) {
        Write-Host "Mode: REPORT ONLY (No changes will be made)" -ForegroundColor Yellow
    } else {
        Write-Host "Disabling 'Allow computer to turn off device to save power'" -ForegroundColor Cyan
    }
    Write-Host ("=" * 80) -ForegroundColor Cyan
    Write-Host ""
    
    # Check for admin privileges
    $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    
    if (-not $isAdmin) {
        Write-Status "This script requires Administrator privileges. Please run as Administrator." "Error"
        exit 1
    }
    
    Write-Status "Running with Administrator privileges" "Success"
    
    # Display Windows version info
    Get-WindowsVersion | Out-Null
    Write-Host ""
    
    # Handle Restore mode
    if ($Restore) {
        Enable-USBPowerManagement
        Write-Host ""
        
        # Generate report
        Get-USBPowerReport -ExportPath $ExportReport
        
        Write-Host ""
        Write-Host ("=" * 80) -ForegroundColor Green
        Write-Status "USB Power Management restore complete!" "Success"
        Write-Status "Windows default power management settings have been restored." "Info"
        Write-Status "A system restart is recommended for all changes to take effect." "Warning"
        Write-Host ("=" * 80) -ForegroundColor Green
        Write-Host ""
    }
    else {
        # Step 1: Disable USB Selective Suspend in power plans
        Disable-USBSelectiveSuspend
        Write-Host ""
        
        # Step 2: Disable power management via registry for all USB devices
        Disable-USBDevicePowerManagement
        Write-Host ""
        
        # Step 3: Configure USB Hub specific settings
        Disable-USBHubPowerManagement
        Write-Host ""
        
        # Step 4: Disable power management via PnP/WMI
        Disable-DevicePowerManagementPnP
        Write-Host ""
        
        # Step 5: Configure USB services
        Set-USBServicesConfiguration
        Write-Host ""
        
        # Step 6: Generate report
        Get-USBPowerReport -ExportPath $ExportReport
        
        Write-Host ""
        Write-Host ("=" * 80) -ForegroundColor Green
        if ($ReportOnly) {
            Write-Status "USB Power Management report complete!" "Success"
            Write-Status "No changes were made (report-only mode)." "Info"
        } else {
            Write-Status "USB Power Management configuration complete!" "Success"
            Write-Status "Devices modified: $script:TotalDevicesModified" "Info"
            if ($script:TotalDevicesFailed -gt 0) {
                Write-Status "Devices skipped/failed: $script:TotalDevicesFailed" "Warning"
            }
            Write-Status "A system restart is recommended for all changes to take effect." "Warning"
        }
        Write-Host ("=" * 80) -ForegroundColor Green
        Write-Host ""
    }
    
    # Prompt for restart (only if changes were made)
    if (-not $ReportOnly -and -not $NoRestartPrompt) {
        try {
            # Check if running in interactive mode (exclude ISE, VS Code, and other non-console hosts)
            $nonInteractiveHosts = 'ISE|Code|ServerRemoteHost|integratedConsoleHost'
            if ([Environment]::UserInteractive -and $Host.Name -notmatch $nonInteractiveHosts -and [Console]::IsInputRedirected -eq $false) {
                $restart = Read-Host "Would you like to restart the computer now? (Y/N)"
                if ($restart -eq 'Y' -or $restart -eq 'y') {
                    Write-Status "Restarting computer in 10 seconds... Press Ctrl+C to cancel." "Warning"
                    Start-Sleep -Seconds 10
                    Restart-Computer -Force
                }
                else {
                    Write-Status "Please remember to restart your computer for all changes to take full effect." "Info"
                }
            }
            else {
                Write-Status "Running in non-interactive mode. Please restart manually for changes to take effect." "Info"
            }
        }
        catch {
            Write-Status "Please restart your computer manually for all changes to take full effect." "Info"
        }
    }
    
    # Stop transcript if it was started
    if ($EnableLogging) {
        try { Stop-Transcript -ErrorAction SilentlyContinue } catch { }
    }
}

# Run the script
Main
