# USB Power Management Auto-Disable

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![PowerShell](https://img.shields.io/badge/PowerShell-3.0%2B-blue.svg)](https://docs.microsoft.com/en-us/powershell/)
[![Windows](https://img.shields.io/badge/Windows-7%20%7C%208%20%7C%208.1%20%7C%2010%20%7C%2011-0078D6.svg)](https://www.microsoft.com/windows)

A comprehensive PowerShell script to disable Windows USB power management settings, preventing USB devices from being turned off to save power.

## 🎯 Problem Solved

Windows has a built-in feature that allows it to turn off USB devices to save power. While this can extend battery life on laptops, it often causes issues such as:

- USB devices randomly disconnecting
- External drives unmounting unexpectedly
- USB peripherals (mice, keyboards, headsets) becoming unresponsive
- Data transfer interruptions
- Gaming controllers disconnecting mid-game

This script automatically disables all USB power-saving features across your system.

## ✨ Features

- **Disables USB Selective Suspend** in all power plans (AC and battery)
- **Disables "Allow the computer to turn off this device to save power"** for all USB controllers and hubs
- **Modifies registry settings** for enhanced USB power management
- **Configures USB service parameters** to prevent selective suspend
- **Generates a detailed report** of all USB devices and their power management status
- **Cross-version compatibility** - Works on Windows 7, 8, 8.1, 10, and 11
- **PowerShell 3.0+ compatible** with fallbacks for older systems

## 📋 Requirements

- **Operating System:** Windows 7, 8, 8.1, 10, or 11
- **PowerShell:** Version 3.0 or later (included in Windows 8+)
- **Privileges:** Administrator rights required

## 🚀 Quick Start

### Option 1: GUI Version (Recommended)

1. Download or clone this repository
2. Double-click `Run-GUI.bat` (or `USBPowerManagement-GUI.exe` if available)
3. Accept the UAC prompt for administrator privileges
4. View your USB devices and their power management status
5. Click **"Disable Power Management"** button
6. Restart your computer when prompted

![GUI Screenshot](docs/gui-screenshot.png)

### Option 2: Double-Click (Command Line)

1. Download or clone this repository
2. Double-click `Run-DisableUSBPowerManagement.bat`
3. Accept the UAC prompt for administrator privileges
4. Wait for the script to complete
5. Restart your computer when prompted

### Option 3: PowerShell Direct

1. Open PowerShell as Administrator
2. Navigate to the script directory:
   ```powershell
   cd "C:\path\to\USBPowerManagement-AutoDisable"
   ```
3. Run the script:
   ```powershell
   .\Disable-USBPowerManagement.ps1
   ```

### Option 4: One-Line Command

Run in an elevated PowerShell:
```powershell
Set-ExecutionPolicy Bypass -Scope Process -Force; .\Disable-USBPowerManagement.ps1
```

### Advanced Usage

> 💡 **Tip:** Run with `-ReportOnly` first to see what changes will be made without modifying your system.

The script supports several parameters for advanced use cases:

```powershell
# Generate a report without making any changes (recommended to run first)
.\Disable-USBPowerManagement.ps1 -ReportOnly

# Run without the restart prompt (useful for automation)
.\Disable-USBPowerManagement.ps1 -NoRestartPrompt

# Enable logging to a timestamped file
.\Disable-USBPowerManagement.ps1 -EnableLogging

# Combine parameters
.\Disable-USBPowerManagement.ps1 -NoRestartPrompt -EnableLogging
```

| Parameter | Description |
|-----------|-------------|
| `-ReportOnly` | Generate a report of USB power management status without making changes |
| `-NoRestartPrompt` | Skip the restart prompt at the end of execution |
| `-EnableLogging` | Save output to a timestamped log file in the script directory |

## 📁 Files

| File | Description |
|------|-------------|
| `Disable-USBPowerManagement.ps1` | Main PowerShell script (command line) |
| `USBPowerManagement-GUI.ps1` | GUI version PowerShell script |
| `USBPowerManagement-GUI.exe` | Compiled GUI executable (after build) |
| `Run-DisableUSBPowerManagement.bat` | Command line launcher with auto-elevation |
| `Run-GUI.bat` | GUI launcher with auto-elevation |
| `Build-GUI-EXE.bat` | Script to compile GUI to standalone EXE |
| `README.md` | This documentation file |
| `LICENSE` | MIT License |
| `CHANGELOG.md` | Version history |
| `CONTRIBUTING.md` | Contribution guidelines |
| `SECURITY.md` | Security policy |

## 🔧 What the Script Does

### 1. Power Plan Configuration
Disables USB Selective Suspend in all Windows power plans for both AC and battery power modes.

### 2. Registry Modifications
Sets the following registry values for all USB devices:
- `EnhancedPowerManagementEnabled = 0`
- `SelectiveSuspendEnabled = 0`
- `AllowIdleIrpInD3 = 0`
- `DeviceSelectiveSuspended = 0`
- `SelectiveSuspendSupported = 0`

### 3. USB Service Configuration
Configures these USB-related services:
- USBHUB / USBHUB3
- USBXHCI (USB 3.0)
- USBEHCI (USB 2.0)
- USBUHCI / USBOHCI (USB 1.1)
- USBSTOR (USB Storage)
- USBCCGP (USB Composite)

### 4. WMI Power Management
Disables power management via Windows Management Instrumentation (WMI) for supported devices.

## 📊 Output Example

```
================================================================================
USB POWER MANAGEMENT CONFIGURATION SCRIPT
Disabling 'Allow computer to turn off device to save power'
================================================================================

[2026-01-19 10:30:00] [SUCCESS] Running with Administrator privileges
[2026-01-19 10:30:00] [INFO] Operating System: Microsoft Windows 11 Pro
[2026-01-19 10:30:00] [INFO] Version: 10.0.22631
[2026-01-19 10:30:01] [SUCCESS] USB Selective Suspend disabled for all power plans
[2026-01-19 10:30:02] [SUCCESS] Modified registry for: Intel(R) USB 3.0 eXtensible Host Controller
[2026-01-19 10:30:02] [SUCCESS] Modified registry for: USB Root Hub (USB 3.0)
...
[2026-01-19 10:30:05] [SUCCESS] USB Power Management configuration complete!
[2026-01-19 10:30:05] [WARNING] A system restart is recommended for all changes to take effect.
```

## ⚠️ Important Notes

1. **Restart Required:** A system restart is recommended after running the script for all changes to take effect.

2. **Battery Impact:** On laptops, disabling USB power management may slightly reduce battery life.

3. **Reversibility:** The script makes registry changes that can be reversed by:
   - Re-enabling "Allow the computer to turn off this device" manually in Device Manager
   - Re-enabling USB Selective Suspend in Power Options

4. **Safe to Re-run:** The script can be run multiple times safely. It will simply reapply the settings.

## 🐛 Troubleshooting

### Script won't run / Execution Policy Error
```powershell
Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process
```

### "Access Denied" errors
Ensure you're running as Administrator. Right-click PowerShell → "Run as administrator"

### Some devices still disconnect
1. Check if the device has its own power management drivers
2. Update USB controller drivers
3. Try a different USB port (USB 2.0 vs 3.0)
4. Check for faulty USB cables or hubs

### Script shows warnings but completes
Warnings are normal for devices that don't support certain power management features. The script handles this gracefully.

## 🤝 Contributing

Contributions are welcome! Please see [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🙏 Acknowledgments

- Microsoft documentation on USB power management
- Windows PowerShell community

## 📬 Support

If you encounter issues or have suggestions:
1. Check the [Troubleshooting](#-troubleshooting) section
2. Search existing [Issues](../../issues)
3. Open a new issue with detailed information about your system and the problem

---

**⭐ If this script helped you, consider giving it a star!**
