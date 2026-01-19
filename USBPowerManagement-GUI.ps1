<# 
    USB Power Management Disabler - GUI Version
    Author: Diobyte
    Version: 1.3.0
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
        $pnpDevices = Get-CimInstance -ClassName Win32_PnPEntity -ErrorAction SilentlyContinue | Where-Object {
            $_.PNPDeviceID -like "USB\*" -or 
            $_.PNPDeviceID -like "USBSTOR\*" -or
            $_.Name -like "*USB*Hub*" -or
            $_.Name -like "*USB*Controller*" -or
            $_.Name -like "*USB*Root*"
        }
        
        foreach ($device in $pnpDevices) {
            if ($null -eq $device.PNPDeviceID) { continue }
            
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
                Name = $device.Name
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
        $allDevices = Get-CimInstance -ClassName Win32_PnPEntity -ErrorAction SilentlyContinue | Where-Object {
            $_.PNPDeviceID -like "USB\*" -or 
            $_.PNPDeviceID -like "USBSTOR\*" -or
            $_.Name -like "*USB*Hub*" -or
            $_.Name -like "*USB*Controller*"
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

function Start-DisablePowerManagement {
    $script:DisableButton.Enabled = $false
    $script:RefreshButton.Enabled = $false
    $script:ProgressBar.Value = 0
    $script:LogTextBox.Clear()
    
    Write-Log "Starting USB Power Management configuration..." "Info"
    Write-Log "Running with Administrator privileges" "Success"
    
    $script:ProgressBar.Value = 10
    Disable-USBSelectiveSuspend
    
    Disable-USBDevicePowerManagement
    
    Set-USBHubPowerManagement
    
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
    
    try {
        $devices = Get-USBDevices
    } catch {
        $devices = @()
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
$MainForm.Text = "USB Power Management Disabler v1.3.0"
$MainForm.Size = New-Object System.Drawing.Size(800, 650)
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
$script:DeviceListView.Size = New-Object System.Drawing.Size(725, 180)
$script:DeviceListView.View = "Details"
$script:DeviceListView.FullRowSelect = $true
$script:DeviceListView.GridLines = $true
$script:DeviceListView.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$script:DeviceListView.Columns.Add("Device Name", 450) | Out-Null
$script:DeviceListView.Columns.Add("Status", 100) | Out-Null
$script:DeviceListView.Columns.Add("Power Mgmt", 150) | Out-Null
$DeviceGroup.Controls.Add($script:DeviceListView)

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
$script:StatusLabel.Size = New-Object System.Drawing.Size(300, 25)
$script:StatusLabel.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$script:StatusLabel.ForeColor = [System.Drawing.Color]::Gray
$ButtonPanel.Controls.Add($script:StatusLabel)

$script:RefreshButton = New-Object System.Windows.Forms.Button
$script:RefreshButton.Text = "Refresh"
$script:RefreshButton.Location = New-Object System.Drawing.Point(480, 5)
$script:RefreshButton.Size = New-Object System.Drawing.Size(120, 30)
$script:RefreshButton.Font = New-Object System.Drawing.Font("Segoe UI", 10)
$script:RefreshButton.Add_Click({ Update-DeviceList })
$ButtonPanel.Controls.Add($script:RefreshButton)

$script:DisableButton = New-Object System.Windows.Forms.Button
$script:DisableButton.Text = "Disable Power Mgmt"
$script:DisableButton.Location = New-Object System.Drawing.Point(610, 5)
$script:DisableButton.Size = New-Object System.Drawing.Size(135, 30)
$script:DisableButton.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
$script:DisableButton.BackColor = [System.Drawing.Color]::FromArgb(0, 120, 215)
$script:DisableButton.ForeColor = [System.Drawing.Color]::White
$script:DisableButton.FlatStyle = "Flat"
$script:DisableButton.Add_Click({ Start-DisablePowerManagement })
$ButtonPanel.Controls.Add($script:DisableButton)

# Load devices
Update-DeviceList

# Show form
[System.Windows.Forms.Application]::Run($MainForm)
