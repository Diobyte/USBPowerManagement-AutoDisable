<# 
    USB Power Management Disabler - GUI Version
    Author: Diobyte
    Version: 1.4.0
#>

# Hide console window when running as EXE
Add-Type -Name Window -Namespace Console -MemberDefinition '
[DllImport("Kernel32.dll")]
public static extern IntPtr GetConsoleWindow();
[DllImport("user32.dll")]
public static extern bool ShowWindow(IntPtr hWnd, Int32 nCmdShow);
'
$consolePtr = [Console.Window]::GetConsoleWindow()
[Console.Window]::ShowWindow($consolePtr, 0) | Out-Null

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

[System.Windows.Forms.Application]::EnableVisualStyles()

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
            $pnpDevices = Get-CimInstance -ClassName Win32_PnPEntity -ErrorAction Stop | Where-Object {
                $_.PNPDeviceID -like "USB\*" -or 
                $_.PNPDeviceID -like "USBSTOR\*" -or
                $_.Name -like "*USB*Hub*" -or
                $_.Name -like "*USB*Controller*" -or
                $_.Name -like "*USB*Root*"
            }
        }
        catch {
            # Fallback to WMI for older systems or if CIM fails
            $pnpDevices = Get-WmiObject -Class Win32_PnPEntity -ErrorAction SilentlyContinue | Where-Object {
                $_.PNPDeviceID -like "USB\*" -or 
                $_.PNPDeviceID -like "USBSTOR\*" -or
                $_.Name -like "*USB*Hub*" -or
                $_.Name -like "*USB*Controller*" -or
                $_.Name -like "*USB*Root*"
            }
        }
        
        foreach ($device in $pnpDevices) {
            if ($null -eq $device.PNPDeviceID) { continue }
            
            $deviceName = if ([string]::IsNullOrEmpty($device.Name)) { "Unknown USB Device" } else { $device.Name }
            $powerStatus = "Unknown"
            $instancePath = $device.PNPDeviceID
            $regPath = "HKLM:\SYSTEM\CurrentControlSet\Enum\$instancePath"
            
            $subKeys = Get-ChildItem -Path $regPath -ErrorAction SilentlyContinue
            foreach ($subKey in $subKeys) {
                $deviceParamsPath = Join-Path $subKey.PSPath "Device Parameters"
                if (Test-Path $deviceParamsPath) {
                    $enhancedPM = Get-ItemProperty -Path $deviceParamsPath -Name "EnhancedPowerManagementEnabled" -ErrorAction SilentlyContinue
                    if ($null -ne $enhancedPM) {
                        $powerStatus = if ($enhancedPM.EnhancedPowerManagementEnabled -eq 0) { "Disabled" } else { "Enabled" }
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
    } catch { }
    
    return $devices
}

function Disable-USBSelectiveSuspend {
    Write-Log "Disabling USB Selective Suspend in power plans..." "Info"
    
    try {
        $powercfgPath = Join-Path $env:SystemRoot "System32\powercfg.exe"
        if (-not (Test-Path $powercfgPath)) {
            Write-Log "powercfg.exe not found" "Warning"
            return
        }
        
        $powerPlans = & $powercfgPath /list 2>&1
        $planGuids = [regex]::Matches($powerPlans, '([a-fA-F0-9]{8}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{12})') | 
                     ForEach-Object { $_.Groups[1].Value } | Select-Object -Unique
        
        $usbSettingsGuid = "2a737441-1930-4402-8d77-b2bebba308a3"
        $usbSelectiveSuspendGuid = "48e6b7a6-50f5-4782-a5d4-53bb8f07e226"
        
        foreach ($planGuid in $planGuids) {
            & $powercfgPath /setacvalueindex $planGuid $usbSettingsGuid $usbSelectiveSuspendGuid 0 2>&1 | Out-Null
            & $powercfgPath /setdcvalueindex $planGuid $usbSettingsGuid $usbSelectiveSuspendGuid 0 2>&1 | Out-Null
        }
        
        $activePlan = & $powercfgPath /getactivescheme 2>&1
        if ($activePlan -match '([a-fA-F0-9]{8}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{12})') {
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
    
    try {
        # Try CIM first, fallback to WMI for compatibility
        try {
            $allDevices = Get-CimInstance -ClassName Win32_PnPEntity -ErrorAction Stop | Where-Object {
                $_.PNPDeviceID -like "USB\*" -or 
                $_.PNPDeviceID -like "USBSTOR\*" -or
                $_.Name -like "*USB*Hub*" -or
                $_.Name -like "*USB*Controller*" -or
                $_.Name -like "*USB*Root*" -or
                $_.Name -like "*Universal Serial Bus*" -or
                $_.Name -like "*eXtensible Host Controller*" -or
                $_.Name -like "*Enhanced Host Controller*"
            }
        }
        catch {
            $allDevices = Get-WmiObject -Class Win32_PnPEntity -ErrorAction SilentlyContinue | Where-Object {
                $_.PNPDeviceID -like "USB\*" -or 
                $_.PNPDeviceID -like "USBSTOR\*" -or
                $_.Name -like "*USB*Hub*" -or
                $_.Name -like "*USB*Controller*" -or
                $_.Name -like "*USB*Root*" -or
                $_.Name -like "*Universal Serial Bus*" -or
                $_.Name -like "*eXtensible Host Controller*" -or
                $_.Name -like "*Enhanced Host Controller*"
            }
        }
        
        $deviceArray = @($allDevices)
        $totalDevices = $deviceArray.Count
        if ($totalDevices -eq 0) { $totalDevices = 1 }
        $currentDevice = 0
        
        foreach ($device in $deviceArray) {
            $currentDevice++
            if ($null -ne $script:ProgressBar) {
                $script:ProgressBar.Value = [math]::Min(($currentDevice / $totalDevices) * 70, 70)
            }
            [System.Windows.Forms.Application]::DoEvents()
            
            $deviceId = $device.PNPDeviceID
            if ([string]::IsNullOrEmpty($deviceId)) { continue }
            
            $enumPath = "HKLM:\SYSTEM\CurrentControlSet\Enum\$deviceId"
            
            if (Test-Path $enumPath) {
                $subKeys = Get-ChildItem -Path $enumPath -ErrorAction SilentlyContinue
                
                foreach ($subKey in $subKeys) {
                    $deviceParamsPath = Join-Path $subKey.PSPath "Device Parameters"
                    
                    try {
                        if (-not (Test-Path $deviceParamsPath)) {
                            New-Item -Path $deviceParamsPath -Force -ErrorAction SilentlyContinue | Out-Null
                        }
                        
                        if (Test-Path $deviceParamsPath) {
                            Set-ItemProperty -Path $deviceParamsPath -Name "EnhancedPowerManagementEnabled" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
                            Set-ItemProperty -Path $deviceParamsPath -Name "SelectiveSuspendEnabled" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
                            Set-ItemProperty -Path $deviceParamsPath -Name "AllowIdleIrpInD3" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
                            $script:DevicesModified++
                        }
                    } catch {
                        $script:DevicesFailed++
                        Write-Log "  Failed: $($_.Exception.Message)" "Warning"
                    }
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
    if ($null -ne $script:ProgressBar) { $script:ProgressBar.Value = 75 }
    [System.Windows.Forms.Application]::DoEvents()
    
    try {
        $usbEnumPath = "HKLM:\SYSTEM\CurrentControlSet\Enum\USB"
        
        if (Test-Path $usbEnumPath) {
            $usbDevices = Get-ChildItem -Path $usbEnumPath -Recurse -ErrorAction SilentlyContinue
            
            foreach ($item in $usbDevices) {
                if ($item.PSChildName -eq "Device Parameters") {
                    try {
                        Set-ItemProperty -Path $item.PSPath -Name "EnhancedPowerManagementEnabled" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
                        Set-ItemProperty -Path $item.PSPath -Name "SelectiveSuspendEnabled" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
                        Set-ItemProperty -Path $item.PSPath -Name "AllowIdleIrpInD3" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
                        Set-ItemProperty -Path $item.PSPath -Name "DeviceSelectiveSuspended" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
                        Set-ItemProperty -Path $item.PSPath -Name "SelectiveSuspendSupported" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
                    } catch { }
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
    if ($null -ne $script:ProgressBar) { $script:ProgressBar.Value = 80 }
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
                $friendlyName = if ([string]::IsNullOrEmpty($device.FriendlyName)) { $device.Description } else { $device.FriendlyName }
                
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
                            $pm | Set-CimInstance -Property @{ Enable = $false } -ErrorAction SilentlyContinue
                            $wmiConfigured++
                        } catch { }
                    }
                }
            } catch { }
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
    if ($null -ne $script:ProgressBar) { $script:ProgressBar.Value = 85 }
    [System.Windows.Forms.Application]::DoEvents()
    
    try {
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
                
                if (-not (Test-Path $paramsPath)) {
                    New-Item -Path $paramsPath -Force -ErrorAction SilentlyContinue | Out-Null
                }
                
                if (Test-Path $paramsPath) {
                    Set-ItemProperty -Path $paramsPath -Name "DisableSelectiveSuspend" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
                }
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
    if ($null -ne $script:ProgressBar) { $script:ProgressBar.Value = 10 }
    [System.Windows.Forms.Application]::DoEvents()
    
    try {
        # Restore USB Selective Suspend in power plans
        Write-Log "Enabling USB Selective Suspend in power plans..." "Info"
        
        $powercfgPath = Join-Path $env:SystemRoot "System32\powercfg.exe"
        if (Test-Path $powercfgPath) {
            $powerPlans = & $powercfgPath /list 2>&1
            $planGuids = [regex]::Matches($powerPlans, '([a-fA-F0-9]{8}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{12})') | 
                         ForEach-Object { $_.Groups[1].Value } | Select-Object -Unique
            
            $usbSettingsGuid = "2a737441-1930-4402-8d77-b2bebba308a3"
            $usbSelectiveSuspendGuid = "48e6b7a6-50f5-4782-a5d4-53bb8f07e226"
            
            foreach ($planGuid in $planGuids) {
                & $powercfgPath /setacvalueindex $planGuid $usbSettingsGuid $usbSelectiveSuspendGuid 1 2>&1 | Out-Null
                & $powercfgPath /setdcvalueindex $planGuid $usbSettingsGuid $usbSelectiveSuspendGuid 1 2>&1 | Out-Null
            }
            Write-Log "USB Selective Suspend enabled in all power plans" "Success"
        }
        
        if ($null -ne $script:ProgressBar) { $script:ProgressBar.Value = 40 }
        [System.Windows.Forms.Application]::DoEvents()
        
        # Remove registry settings
        Write-Log "Restoring USB device registry settings..." "Info"
        $devicesRestored = 0
        
        $usbEnumPath = "HKLM:\SYSTEM\CurrentControlSet\Enum\USB"
        if (Test-Path $usbEnumPath) {
            $usbDevices = Get-ChildItem -Path $usbEnumPath -Recurse -ErrorAction SilentlyContinue
            
            foreach ($item in $usbDevices) {
                if ($item.PSChildName -eq "Device Parameters") {
                    try {
                        Remove-ItemProperty -Path $item.PSPath -Name "EnhancedPowerManagementEnabled" -Force -ErrorAction SilentlyContinue
                        Remove-ItemProperty -Path $item.PSPath -Name "SelectiveSuspendEnabled" -Force -ErrorAction SilentlyContinue
                        Remove-ItemProperty -Path $item.PSPath -Name "AllowIdleIrpInD3" -Force -ErrorAction SilentlyContinue
                        Remove-ItemProperty -Path $item.PSPath -Name "DeviceSelectiveSuspended" -Force -ErrorAction SilentlyContinue
                        Remove-ItemProperty -Path $item.PSPath -Name "SelectiveSuspendSupported" -Force -ErrorAction SilentlyContinue
                        $devicesRestored++
                    } catch { }
                }
            }
        }
        
        if ($null -ne $script:ProgressBar) { $script:ProgressBar.Value = 70 }
        [System.Windows.Forms.Application]::DoEvents()
        
        # Restore USBSTOR
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
                    } catch { }
                }
            }
        }
        
        if ($null -ne $script:ProgressBar) { $script:ProgressBar.Value = 85 }
        [System.Windows.Forms.Application]::DoEvents()
        
        # Remove service configuration
        Write-Log "Restoring USB service settings..." "Info"
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
    
    $script:ProgressBar.Value = 100
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
        Restart-Computer -Force
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
    
    $script:ProgressBar.Value = 10
    Disable-USBSelectiveSuspend
    
    Disable-USBDevicePowerManagement
    
    Set-USBHubPowerManagement
    
    Disable-DevicePowerManagementPnP
    
    Set-USBServicesConfiguration
    
    $script:ProgressBar.Value = 100
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
        Restart-Computer -Force
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
        return
    }
    
    foreach ($device in $devices) {
        if ($null -eq $device.Name) { continue }
        
        $item = New-Object System.Windows.Forms.ListViewItem($device.Name)
        $item.SubItems.Add($device.Status) | Out-Null
        $item.SubItems.Add($device.PowerManagement) | Out-Null
        $item.Checked = $true  # Check all items by default
        $item.Tag = $device.DeviceID  # Store device ID for operations
        
        if ($device.PowerManagement -eq "Disabled") {
            $item.ForeColor = [System.Drawing.Color]::Green
        } elseif ($device.PowerManagement -eq "Enabled") {
            $item.ForeColor = [System.Drawing.Color]::Red
        }
        
        $script:DeviceListView.Items.Add($item) | Out-Null
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
            $psi.FileName = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
            $psi.Arguments = $MyInvocation.MyCommand.Definition
            $psi.Verb = "runas"
            $psi.UseShellExecute = $true
            [System.Diagnostics.Process]::Start($psi) | Out-Null
        } catch { }
    }
    exit
}

# Build GUI
$MainForm = New-Object System.Windows.Forms.Form
$MainForm.Text = "USB Power Management Disabler v1.4.0"
$MainForm.Size = New-Object System.Drawing.Size(800, 670)
$MainForm.StartPosition = "CenterScreen"
$MainForm.FormBorderStyle = "FixedSingle"
$MainForm.MaximizeBox = $false
$MainForm.BackColor = [System.Drawing.Color]::WhiteSmoke

# Header
$HeaderPanel = New-Object System.Windows.Forms.Panel
$HeaderPanel.Location = New-Object System.Drawing.Point(0, 0)
$HeaderPanel.Size = New-Object System.Drawing.Size(800, 70)
$HeaderPanel.BackColor = [System.Drawing.Color]::FromArgb(0, 120, 215)
$MainForm.Controls.Add($HeaderPanel)

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
$MainForm.Controls.Add($AdminLabel)

# Device group
$DeviceGroup = New-Object System.Windows.Forms.GroupBox
$DeviceGroup.Text = "USB Devices"
$DeviceGroup.Location = New-Object System.Drawing.Point(20, 110)
$DeviceGroup.Size = New-Object System.Drawing.Size(745, 220)
$DeviceGroup.Font = New-Object System.Drawing.Font("Segoe UI", 10)
$MainForm.Controls.Add($DeviceGroup)

$script:DeviceListView = New-Object System.Windows.Forms.ListView
$script:DeviceListView.Location = New-Object System.Drawing.Point(10, 25)
$script:DeviceListView.Size = New-Object System.Drawing.Size(725, 155)
$script:DeviceListView.View = "Details"
$script:DeviceListView.FullRowSelect = $true
$script:DeviceListView.GridLines = $true
$script:DeviceListView.CheckBoxes = $true
$script:DeviceListView.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$script:DeviceListView.Columns.Add("Device Name", 430) | Out-Null
$script:DeviceListView.Columns.Add("Status", 100) | Out-Null
$script:DeviceListView.Columns.Add("Power Mgmt", 150) | Out-Null
$DeviceGroup.Controls.Add($script:DeviceListView)

# Select All / Deselect All buttons for device list
$SelectAllButton = New-Object System.Windows.Forms.Button
$SelectAllButton.Text = "Select All"
$SelectAllButton.Location = New-Object System.Drawing.Point(10, 185)
$SelectAllButton.Size = New-Object System.Drawing.Size(80, 25)
$SelectAllButton.Font = New-Object System.Drawing.Font("Segoe UI", 8)
$SelectAllButton.Add_Click({
    foreach ($item in $script:DeviceListView.Items) {
        $item.Checked = $true
    }
})
$DeviceGroup.Controls.Add($SelectAllButton)

$DeselectAllButton = New-Object System.Windows.Forms.Button
$DeselectAllButton.Text = "Deselect All"
$DeselectAllButton.Location = New-Object System.Drawing.Point(95, 185)
$DeselectAllButton.Size = New-Object System.Drawing.Size(80, 25)
$DeselectAllButton.Font = New-Object System.Drawing.Font("Segoe UI", 8)
$DeselectAllButton.Add_Click({
    foreach ($item in $script:DeviceListView.Items) {
        $item.Checked = $false
    }
})
$DeviceGroup.Controls.Add($DeselectAllButton)

$SelectionInfoLabel = New-Object System.Windows.Forms.Label
$SelectionInfoLabel.Text = "Check devices to include in operations"
$SelectionInfoLabel.Location = New-Object System.Drawing.Point(185, 188)
$SelectionInfoLabel.Size = New-Object System.Drawing.Size(300, 20)
$SelectionInfoLabel.Font = New-Object System.Drawing.Font("Segoe UI", 8)
$SelectionInfoLabel.ForeColor = [System.Drawing.Color]::Gray
$DeviceGroup.Controls.Add($SelectionInfoLabel)

# Progress bar
$script:ProgressBar = New-Object System.Windows.Forms.ProgressBar
$script:ProgressBar.Location = New-Object System.Drawing.Point(20, 340)
$script:ProgressBar.Size = New-Object System.Drawing.Size(745, 25)
$script:ProgressBar.Style = "Continuous"
$MainForm.Controls.Add($script:ProgressBar)

# Log group
$LogGroup = New-Object System.Windows.Forms.GroupBox
$LogGroup.Text = "Activity Log"
$LogGroup.Location = New-Object System.Drawing.Point(20, 375)
$LogGroup.Size = New-Object System.Drawing.Size(745, 180)
$LogGroup.Font = New-Object System.Drawing.Font("Segoe UI", 10)
$MainForm.Controls.Add($LogGroup)

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
$MainForm.Controls.Add($ButtonPanel)

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

# Add tooltip for restore button
$tooltip = New-Object System.Windows.Forms.ToolTip
$tooltip.SetToolTip($script:RestoreButton, "Restore Windows default USB power management settings")
$tooltip.SetToolTip($script:DisableButton, "Disable power management to prevent USB disconnections")
$tooltip.SetToolTip($script:ExportLogButton, "Save the activity log to a file")
$tooltip.SetToolTip($SelectAllButton, "Select all devices in the list")
$tooltip.SetToolTip($DeselectAllButton, "Deselect all devices in the list")
$tooltip.SetToolTip($script:RefreshButton, "Refresh the USB device list")

# Load devices
Update-DeviceList

# Show form
[System.Windows.Forms.Application]::Run($MainForm)
