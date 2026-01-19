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

.PARAMETER WhatIf
    Shows what changes would be made without actually making them.
    Use this to preview the script's actions before committing changes.

.PARAMETER Confirm
    Prompts for confirmation before making each change.

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

.EXAMPLE
    .\Disable-USBPowerManagement.ps1 -WhatIf
    Shows what changes would be made without actually applying them.

.OUTPUTS
    None. This script does not return any objects but outputs status messages to the console.

.NOTES
    Author: Diobyte
    Requires: Administrator privileges
    Version: 1.4.1
    Date: 2026-01-19
    Compatibility: Windows 7/8/8.1/10/11, PowerShell 3.0+
    License: MIT
    Repository: https://github.com/Diobyte/USBPowerManagement-AutoDisable
#>

#Requires -RunAsAdministrator
#Requires -Version 3.0

[CmdletBinding(DefaultParameterSetName = 'Disable', SupportsShouldProcess = $true)]
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

# Script-level version constant (centralized for easy updates)
$script:VERSION = "1.4.1"

# Set strict mode for better error detection
Set-StrictMode -Version Latest

# Set error handling
$ErrorActionPreference = "Continue"

# Script-level constants for USB power management GUIDs
# USB_SETTINGS_GUID: Power settings subgroup for USB settings in Windows power plans
# USB_SELECTIVE_SUSPEND_GUID: Setting for USB selective suspend feature (0=Disabled, 1=Enabled)
$script:USB_SETTINGS_GUID = "2a737441-1930-4402-8d77-b2bebba308a3"
$script:USB_SELECTIVE_SUSPEND_GUID = "48e6b7a6-50f5-4782-a5d4-53bb8f07e226"

# USB service registry paths
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

# USB device name filter patterns
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

# Helper function to test if a device matches USB patterns
function Test-USBDevice {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $Device
    )
    
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

# Initialize script-level variables
$script:TotalDevicesModified = 0
$script:TotalDevicesFailed = 0
$script:ReportOnly = $false

# Ensure we're running in a supported Windows version
$osVersion = [System.Environment]::OSVersion.Version
if ($osVersion.Major -lt 6 -or ($osVersion.Major -eq 6 -and $osVersion.Minor -lt 1)) {
    Write-Host "This script requires Windows 7 or later (Windows Vista and earlier are not supported)." -ForegroundColor Red
    if ($EnableLogging) {
        try { Stop-Transcript -ErrorAction SilentlyContinue } catch { }
    }
    exit 1
}

# Start transcript logging if enabled
if ($EnableLogging) {
    # Use PSScriptRoot if available, otherwise fall back to current directory
    $scriptDir = if (-not [string]::IsNullOrEmpty($PSScriptRoot)) { $PSScriptRoot } else { $PWD.Path }
    $logPath = Join-Path $scriptDir "USBPowerManagement_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
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
    [CmdletBinding(SupportsShouldProcess = $true)]
    param()
    
    Write-Status "Disabling USB Selective Suspend in all power plans..." "Info"
    
    if ($script:ReportOnly) {
        Write-Status "Report-only mode: Skipping power plan modifications" "Info"
        return
    }
    
    if (-not $PSCmdlet.ShouldProcess("All Power Plans", "Disable USB Selective Suspend")) {
        return
    }
    
    try {
        # Check if powercfg exists
        $powercfgPath = Join-Path -Path $env:SystemRoot -ChildPath "System32\powercfg.exe"
        if (-not (Test-Path -LiteralPath $powercfgPath -PathType Leaf)) {
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
        $planGuids = @([regex]::Matches($powerPlans, '([a-fA-F0-9]{8}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{12})') | 
                     ForEach-Object { $_.Groups[1].Value } | 
                     Select-Object -Unique)
        
        if ($planGuids.Count -eq 0) {
            Write-Status "No power plans found" "Warning"
            return
        }
        
        foreach ($planGuid in $planGuids) {
            Write-Status "Processing power plan: $planGuid" "Info"
            
            # Disable USB selective suspend on AC power (0 = Disabled)
            $null = & $powercfgPath /setacvalueindex $planGuid $script:USB_SETTINGS_GUID $script:USB_SELECTIVE_SUSPEND_GUID 0 2>&1
            
            # Disable USB selective suspend on DC (battery) power (0 = Disabled)
            $null = & $powercfgPath /setdcvalueindex $planGuid $script:USB_SETTINGS_GUID $script:USB_SELECTIVE_SUSPEND_GUID 0 2>&1
            
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

# Helper function to set power management properties on a device registry path
function Set-DevicePowerManagementParams {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ParamsPath,
        [Parameter(Mandatory = $true)]
        [string]$DeviceDisplayName
    )
    
    if (-not $PSCmdlet.ShouldProcess($ParamsPath, "Set power management properties for $DeviceDisplayName")) {
        return $false
    }
    
    try {
        # Create Device Parameters key if it doesn't exist
        if (-not (Test-Path -LiteralPath $ParamsPath -ErrorAction SilentlyContinue)) {
            New-Item -Path $ParamsPath -Force -ErrorAction Stop | Out-Null
            Write-Status "  Created Device Parameters key for: $DeviceDisplayName" "Info"
        }
        
        # Set all power management properties to disabled (0)
        Set-ItemProperty -LiteralPath $ParamsPath -Name "EnhancedPowerManagementEnabled" -Value 0 -Type DWord -Force -ErrorAction Stop
        Set-ItemProperty -LiteralPath $ParamsPath -Name "SelectiveSuspendEnabled" -Value 0 -Type DWord -Force -ErrorAction Stop
        Set-ItemProperty -LiteralPath $ParamsPath -Name "AllowIdleIrpInD3" -Value 0 -Type DWord -Force -ErrorAction Stop
        return $true
    }
    catch {
        Write-Status "  Failed to modify registry for: $DeviceDisplayName - $($_.Exception.Message)" "Warning"
        return $false
    }
}

# Function to disable power management for USB devices via registry
function Disable-USBDevicePowerManagement {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param()
    
    Write-Status "Disabling power management for all USB devices..." "Info"
    
    if ($script:ReportOnly) {
        Write-Status "Report-only mode: Skipping device power management modifications" "Info"
        return
    }
    
    if (-not $PSCmdlet.ShouldProcess("All USB Devices", "Disable Power Management")) {
        return
    }
    
    $devicesModified = 0
    $devicesFailed = 0
    
    try {
        # Get all USB-related devices using multiple methods for robustness
        # Try CIM first (modern), fallback to WMI (legacy) for compatibility
        try {
            $allDevices = Get-CimInstance -ClassName Win32_PnPEntity -ErrorAction Stop | Where-Object { Test-USBDevice $_ }
        }
        catch {
            # Fallback to WMI for older systems or PowerShell Core without CimCmdlets
            $allDevices = Get-WmiObject -Class Win32_PnPEntity -ErrorAction SilentlyContinue | Where-Object { Test-USBDevice $_ }
        }
        
        $deviceCount = if ($null -eq $allDevices) { 0 } else { @($allDevices).Count }
        Write-Status "Found $deviceCount USB-related devices" "Info"
        
        if ($null -eq $allDevices -or $deviceCount -eq 0) {
            Write-Status "No USB devices found to process" "Warning"
            return
        }
        
        foreach ($device in $allDevices) {
            $deviceId = $device.PNPDeviceID
            $deviceName = if (-not [string]::IsNullOrWhiteSpace($device.Name)) { $device.Name } else { "Unknown Device" }
            
            if ([string]::IsNullOrEmpty($deviceId)) {
                continue
            }
            
            Write-Status "Processing: $deviceName" "Info"
            
            # Find the actual registry key for this device
            $enumPath = "HKLM:\SYSTEM\CurrentControlSet\Enum\$deviceId"
            
            if (-not (Test-Path -LiteralPath $enumPath -ErrorAction SilentlyContinue)) {
                Write-Status "  Registry path not found for: $deviceName" "Warning"
                $devicesFailed++
                continue
            }
            
            $deviceModified = $false
            
            # First, check if Device Parameters exists directly under the device path
            $directParamsPath = Join-Path -Path $enumPath -ChildPath "Device Parameters"
            if (Test-Path -LiteralPath $directParamsPath -ErrorAction SilentlyContinue) {
                $deviceModified = Set-DevicePowerManagementParams -ParamsPath $directParamsPath -DeviceDisplayName $deviceName
            }
            
            # Also process subkeys for multi-instance devices
            $subKeys = Get-ChildItem -LiteralPath $enumPath -ErrorAction SilentlyContinue
            foreach ($subKey in $subKeys) {
                # Skip if this is not a device instance subkey (e.g., skip "Device Parameters" itself)
                if ($subKey.PSChildName -eq "Device Parameters") { continue }
                
                $deviceParamsPath = Join-Path -Path $subKey.PSPath -ChildPath "Device Parameters"
                if (Set-DevicePowerManagementParams -ParamsPath $deviceParamsPath -DeviceDisplayName $deviceName) {
                    $deviceModified = $true
                }
            }
            
            if ($deviceModified) {
                $devicesModified++
                Write-Status "  Modified registry for: $deviceName" "Success"
            } else {
                $devicesFailed++
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
    [CmdletBinding(SupportsShouldProcess = $true)]
    param()
    
    Write-Status "Disabling power management via PnP device properties..." "Info"
    
    if ($script:ReportOnly) {
        Write-Status "Report-only mode: Skipping PnP power management modifications" "Info"
        return
    }
    
    if (-not $PSCmdlet.ShouldProcess("USB PnP Devices", "Disable WMI Power Management")) {
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
                
                # Note: MSPower_DeviceWakeEnable is intentionally NOT modified.
                # Wake-on-USB is a separate feature from power saving and disabling it
                # could prevent USB devices from waking the computer from sleep,
                # which is usually desirable behavior users want to keep.
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
    [CmdletBinding(SupportsShouldProcess = $true)]
    param()
    
    Write-Status "Configuring USB Hub specific power management..." "Info"
    
    if ($script:ReportOnly) {
        Write-Status "Report-only mode: Skipping USB Hub modifications" "Info"
        return
    }
    
    if (-not $PSCmdlet.ShouldProcess("USB Hub Registry Settings", "Disable Power Management")) {
        return
    }
    
    try {
        # Find all USB hubs and root hubs in registry
        $usbEnumPath = "HKLM:\SYSTEM\CurrentControlSet\Enum\USB"
        
        if (Test-Path -LiteralPath $usbEnumPath) {
            $usbDevices = Get-ChildItem -LiteralPath $usbEnumPath -Recurse -ErrorAction SilentlyContinue
            
            foreach ($item in $usbDevices) {
                if ($item.PSChildName -eq "Device Parameters") {
                    try {
                        # Disable all power management options
                        Set-ItemProperty -LiteralPath $item.PSPath -Name "EnhancedPowerManagementEnabled" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
                        Set-ItemProperty -LiteralPath $item.PSPath -Name "SelectiveSuspendEnabled" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
                        Set-ItemProperty -LiteralPath $item.PSPath -Name "AllowIdleIrpInD3" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
                        Set-ItemProperty -LiteralPath $item.PSPath -Name "DeviceSelectiveSuspended" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
                        Set-ItemProperty -LiteralPath $item.PSPath -Name "SelectiveSuspendSupported" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
                    }
                    catch {
                        Write-Verbose "Could not modify USB hub settings at: $($item.PSPath) - $($_.Exception.Message)"
                    }
                }
            }
            
            Write-Status "USB Hub power management settings updated" "Success"
        }
        
        # Also process USBSTOR devices
        $usbStorPath = "HKLM:\SYSTEM\CurrentControlSet\Enum\USBSTOR"
        
        if (Test-Path -LiteralPath $usbStorPath) {
            $usbStorDevices = Get-ChildItem -LiteralPath $usbStorPath -Recurse -ErrorAction SilentlyContinue
            
            foreach ($item in $usbStorDevices) {
                if ($item.PSChildName -eq "Device Parameters") {
                    try {
                        Set-ItemProperty -LiteralPath $item.PSPath -Name "EnhancedPowerManagementEnabled" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
                        Set-ItemProperty -LiteralPath $item.PSPath -Name "SelectiveSuspendEnabled" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
                        Set-ItemProperty -LiteralPath $item.PSPath -Name "AllowIdleIrpInD3" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
                    }
                    catch {
                        Write-Verbose "Could not modify USBSTOR settings at: $($item.PSPath) - $($_.Exception.Message)"
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
    [CmdletBinding(SupportsShouldProcess = $true)]
    param()
    
    Write-Status "Configuring USB-related service settings..." "Info"
    
    if ($script:ReportOnly) {
        Write-Status "Report-only mode: Skipping USB service modifications" "Info"
        return
    }
    
    if (-not $PSCmdlet.ShouldProcess("USB Service Registry Settings", "Configure DisableSelectiveSuspend")) {
        return
    }
    
    try {
        foreach ($service in $script:USB_SERVICE_PATHS) {
            if (Test-Path -LiteralPath $service.Path) {
                $paramsPath = "$($service.Path)\Parameters"
                
                # Create Parameters key if it doesn't exist
                if (-not (Test-Path -LiteralPath $paramsPath)) {
                    New-Item -Path $paramsPath -Force -ErrorAction SilentlyContinue | Out-Null
                }
                
                if (Test-Path -LiteralPath $paramsPath) {
                    Set-ItemProperty -LiteralPath $paramsPath -Name "DisableSelectiveSuspend" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
                    Write-Status "$($service.Name) service selective suspend disabled" "Success"
                }
                
                # Also set at service root level for some drivers
                Set-ItemProperty -LiteralPath $service.Path -Name "DisableSelectiveSuspend" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
            }
        }
    }
    catch {
        Write-Status "Error configuring USB services: $($_.Exception.Message)" "Error"
    }
}

# Function to restore USB power management to Windows defaults
function Enable-USBPowerManagement {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param()
    
    Write-Status "Restoring USB power management to Windows defaults..." "Info"
    
    if (-not $PSCmdlet.ShouldProcess("USB Power Management Settings", "Restore to Windows Defaults")) {
        return
    }
    
    $devicesRestored = 0
    
    try {
        # Restore USB Selective Suspend in power plans
        Write-Status "Enabling USB Selective Suspend in power plans..." "Info"
        
        $powercfgPath = Join-Path $env:SystemRoot "System32\powercfg.exe"
        if (Test-Path -LiteralPath $powercfgPath) {
            $powerPlans = & $powercfgPath /list 2>&1
            # Wrap in @() to ensure array even for single power plan (PowerShell 2.0/3.0 compatibility)
            $planGuids = @([regex]::Matches($powerPlans, '([a-fA-F0-9]{8}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{12})') | 
                         ForEach-Object { $_.Groups[1].Value } | 
                         Select-Object -Unique)
            
            foreach ($planGuid in $planGuids) {
                # Enable USB selective suspend (1 = Enabled)
                $null = & $powercfgPath /setacvalueindex $planGuid $script:USB_SETTINGS_GUID $script:USB_SELECTIVE_SUSPEND_GUID 1 2>&1
                $null = & $powercfgPath /setdcvalueindex $planGuid $script:USB_SETTINGS_GUID $script:USB_SELECTIVE_SUSPEND_GUID 1 2>&1
            }
            Write-Status "USB Selective Suspend enabled in all power plans" "Success"
        }
        
        # Remove/restore registry settings for USB devices
        Write-Status "Restoring USB device registry settings..." "Info"
        
        $usbEnumPath = "HKLM:\SYSTEM\CurrentControlSet\Enum\USB"
        if (Test-Path -LiteralPath $usbEnumPath) {
            $usbDevices = Get-ChildItem -LiteralPath $usbEnumPath -Recurse -ErrorAction SilentlyContinue
            
            foreach ($item in $usbDevices) {
                if ($item.PSChildName -eq "Device Parameters") {
                    try {
                        # Remove our custom settings (restore to Windows default behavior)
                        Remove-ItemProperty -LiteralPath $item.PSPath -Name "EnhancedPowerManagementEnabled" -Force -ErrorAction SilentlyContinue
                        Remove-ItemProperty -LiteralPath $item.PSPath -Name "SelectiveSuspendEnabled" -Force -ErrorAction SilentlyContinue
                        Remove-ItemProperty -LiteralPath $item.PSPath -Name "AllowIdleIrpInD3" -Force -ErrorAction SilentlyContinue
                        Remove-ItemProperty -LiteralPath $item.PSPath -Name "DeviceSelectiveSuspended" -Force -ErrorAction SilentlyContinue
                        Remove-ItemProperty -LiteralPath $item.PSPath -Name "SelectiveSuspendSupported" -Force -ErrorAction SilentlyContinue
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
        if (Test-Path -LiteralPath $usbStorPath) {
            $usbStorDevices = Get-ChildItem -LiteralPath $usbStorPath -Recurse -ErrorAction SilentlyContinue
            
            foreach ($item in $usbStorDevices) {
                if ($item.PSChildName -eq "Device Parameters") {
                    try {
                        Remove-ItemProperty -LiteralPath $item.PSPath -Name "EnhancedPowerManagementEnabled" -Force -ErrorAction SilentlyContinue
                        Remove-ItemProperty -LiteralPath $item.PSPath -Name "SelectiveSuspendEnabled" -Force -ErrorAction SilentlyContinue
                        Remove-ItemProperty -LiteralPath $item.PSPath -Name "AllowIdleIrpInD3" -Force -ErrorAction SilentlyContinue
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
        $name = if (-not [string]::IsNullOrWhiteSpace($device.FriendlyName)) { $device.FriendlyName } 
                elseif (-not [string]::IsNullOrWhiteSpace($device.Description)) { $device.Description } 
                else { "Unknown USB Device" }
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
        
        # Helper to read power management properties from a Device Parameters path
        # Returns a hashtable with EnhancedPM and SelectiveSuspend values, or $null if not found
        $readPowerProps = {
            param($paramsPath)
            $result = @{ Found = $false; EnhancedPM = $null; SelectiveSuspend = $null }
            if (Test-Path -LiteralPath $paramsPath -ErrorAction SilentlyContinue) {
                $enhancedPM = Get-ItemProperty -LiteralPath $paramsPath -Name "EnhancedPowerManagementEnabled" -ErrorAction SilentlyContinue
                $selectiveSuspend = Get-ItemProperty -LiteralPath $paramsPath -Name "SelectiveSuspendEnabled" -ErrorAction SilentlyContinue
                
                if ($enhancedPM) {
                    $result.EnhancedPM = if ($enhancedPM.EnhancedPowerManagementEnabled -eq 0) { "Disabled" } else { "Enabled" }
                    $result.Found = $true
                }
                if ($selectiveSuspend) {
                    $result.SelectiveSuspend = if ($selectiveSuspend.SelectiveSuspendEnabled -eq 0) { "Disabled" } else { "Enabled" }
                    $result.Found = $true
                }
            }
            return $result
        }
        
        # First check direct Device Parameters path
        $directParamsPath = Join-Path -Path $regPath -ChildPath "Device Parameters"
        $powerProps = & $readPowerProps $directParamsPath
        
        # Also check subkeys for multi-instance devices (only if not found above)
        if (-not $powerProps.Found) {
            $subKeys = Get-ChildItem -LiteralPath $regPath -ErrorAction SilentlyContinue
            foreach ($subKey in $subKeys) {
                # Skip Device Parameters key itself
                if ($subKey.PSChildName -eq "Device Parameters") { continue }
                
                $deviceParamsPath = Join-Path $subKey.PSPath "Device Parameters"
                $powerProps = & $readPowerProps $deviceParamsPath
                if ($powerProps.Found) {
                    break  # Found settings, stop searching
                }
            }
        }
        
        # Update device report with found values and display
        if ($powerProps.EnhancedPM) {
            $deviceReport.EnhancedPowerManagement = $powerProps.EnhancedPM
            Write-Host "   Enhanced Power Management: $($powerProps.EnhancedPM)" -ForegroundColor $(if ($powerProps.EnhancedPM -eq "Disabled") { "Green" } else { "Yellow" })
        }
        if ($powerProps.SelectiveSuspend) {
            $deviceReport.SelectiveSuspend = $powerProps.SelectiveSuspend
            Write-Host "   Selective Suspend: $($powerProps.SelectiveSuspend)" -ForegroundColor $(if ($powerProps.SelectiveSuspend -eq "Disabled") { "Green" } else { "Yellow" })
        }
        
        $reportData += $deviceReport
        $counter++
    }
    
    Write-Host ("`n" + ("=" * 80)) -ForegroundColor Cyan
    
    # Export report if path specified
    if ($ExportPath) {
        try {
            # Validate parent directory exists
            $parentDir = [System.IO.Path]::GetDirectoryName($ExportPath)
            if (-not [string]::IsNullOrEmpty($parentDir) -and -not (Test-Path -LiteralPath $parentDir)) {
                Write-Status "Creating export directory: $parentDir" "Info"
                New-Item -Path $parentDir -ItemType Directory -Force -ErrorAction Stop | Out-Null
            }
            
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
    
    # Copy parameter to script scope so child functions (Disable-USBSelectiveSuspend, etc.)
    # can check if we're in report-only mode without needing parameter passing
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
            $isInteractive = $false
            
            try {
                $isInteractive = [Environment]::UserInteractive -and 
                                 $Host.Name -notmatch $nonInteractiveHosts -and 
                                 -not [Console]::IsInputRedirected -and
                                 -not [Console]::IsOutputRedirected
            }
            catch {
                # Console properties may not be available in all hosts
                $isInteractive = $false
            }
            
            if ($isInteractive) {
                $restart = Read-Host "Would you like to restart the computer now? (Y/N)"
                if ($restart -eq 'Y' -or $restart -eq 'y') {
                    Write-Status "Restarting computer in 10 seconds... Press Ctrl+C to cancel." "Warning"
                    Start-Sleep -Seconds 10
                    try {
                        Restart-Computer -Force -ErrorAction Stop
                    }
                    catch {
                        Write-Status "Failed to restart computer: $($_.Exception.Message)" "Error"
                        Write-Status "Please restart your computer manually for all changes to take full effect." "Warning"
                    }
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
