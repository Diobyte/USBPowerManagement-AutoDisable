<div align="center">

# 🔌 USB Power Management Auto-Disable

### Stop Windows from randomly disconnecting your USB devices

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![PowerShell](https://img.shields.io/badge/PowerShell-3.0%2B-blue.svg)](https://docs.microsoft.com/en-us/powershell/)
[![Windows](https://img.shields.io/badge/Windows-7%20%7C%208%20%7C%2010%20%7C%2011-0078D6.svg)](https://www.microsoft.com/windows)
[![Version](https://img.shields.io/badge/Version-1.4.1-green.svg)](CHANGELOG.md)

**[Quick Start](#-quick-start)** · **[Features](#-features)** · **[Documentation](#-documentation)** · **[Troubleshooting](#-troubleshooting)**

</div>

---

## 😤 The Problem

Windows has a "helpful" feature that turns off USB devices to save power. Unfortunately, this causes:

| Issue | Symptom |
|-------|---------|
| 🖱️ **Peripherals freeze** | Mouse, keyboard, or headset stops responding |
| 💾 **Drives disconnect** | External drives unmount unexpectedly |
| 🎮 **Gaming interruptions** | Controllers disconnect mid-game |
| 📁 **Data corruption** | File transfers interrupted |
| 🔊 **Audio dropouts** | USB audio devices cut out |

**This tool fixes all of these issues with one click.**

---

## 🚀 Quick Start

### Step 1: Download

```
git clone https://github.com/Diobyte/USBPowerManagement-AutoDisable.git
```

Or [download the ZIP](https://github.com/Diobyte/USBPowerManagement-AutoDisable/archive/refs/heads/main.zip) and extract it.

### Step 2: Run

Choose your preferred method:

<table>
<tr>
<td width="50%">

### 🖥️ GUI (Recommended)

**Double-click:** `Run-GUI.bat`

Or run the standalone: `USBPowerManagement-GUI.exe`

</td>
<td width="50%">

### ⌨️ Command Line

**Double-click:** `Run-DisableUSBPowerManagement.bat`

Or run in PowerShell (Admin):
```powershell
.\Disable-USBPowerManagement.ps1
```

</td>
</tr>
</table>

### Step 3: Restart

Restart your computer for changes to take full effect.

> ✅ **That's it!** Your USB devices will no longer randomly disconnect.

---

## ✨ Features

<table>
<tr>
<td>

### 🎯 Core Features
- ✅ Disables USB Selective Suspend
- ✅ Disables "Turn off device to save power"
- ✅ Works on all USB controllers & hubs
- ✅ Configures USB service parameters

</td>
<td>

### 🛡️ Safety Features
- ✅ Report-only mode (preview changes)
- ✅ One-click restore to defaults
- ✅ WhatIf support for testing
- ✅ Detailed logging option

</td>
</tr>
<tr>
<td>

### 💻 Compatibility
- ✅ Windows 7, 8, 8.1, 10, 11
- ✅ PowerShell 3.0+
- ✅ 32-bit and 64-bit systems
- ✅ Laptops and desktops

</td>
<td>

### 📊 Reporting
- ✅ Visual device status display
- ✅ Export to CSV, JSON, or TXT
- ✅ Power management status per device
- ✅ Activity logging

</td>
</tr>
</table>

---

## 📖 Documentation

### GUI Interface

The GUI provides an easy way to manage USB power settings:

| Button | Action |
|--------|--------|
| **Disable Power Mgmt** | Disables all USB power management (main action) |
| **Restore Defaults** | Reverts to Windows default settings |
| **Refresh** | Refreshes the USB device list |
| **Export Log** | Saves the activity log to a file |

The device list shows:
- 🟢 **Green** = Power management disabled (good!)
- 🔴 **Red** = Power management enabled (will be fixed)
- ⚫ **Gray** = Status unknown

---

### Command Line Options

```powershell
# Preview changes without applying them
.\Disable-USBPowerManagement.ps1 -ReportOnly

# Apply changes silently (for automation)
.\Disable-USBPowerManagement.ps1 -NoRestartPrompt

# Save detailed log to file
.\Disable-USBPowerManagement.ps1 -EnableLogging

# Undo changes and restore Windows defaults
.\Disable-USBPowerManagement.ps1 -Restore

# Export device report
.\Disable-USBPowerManagement.ps1 -ReportOnly -ExportReport "report.csv"

# Test what would happen (dry run)
.\Disable-USBPowerManagement.ps1 -WhatIf
```

### Parameter Reference

| Parameter | Description |
|-----------|-------------|
| `-ReportOnly` | Show status without making changes |
| `-NoRestartPrompt` | Don't ask to restart (for scripts/automation) |
| `-EnableLogging` | Save output to timestamped log file |
| `-Restore` | Restore Windows default power management |
| `-ExportReport <path>` | Export report to .csv, .json, or .txt |
| `-WhatIf` | Preview changes without applying |
| `-Confirm` | Prompt before each change |

---

## 📁 Project Files

| File | Description |
|------|-------------|
| 📄 `Disable-USBPowerManagement.ps1` | Main CLI script |
| 🖥️ `USBPowerManagement-GUI.ps1` | GUI version (PowerShell) |
| 📦 `USBPowerManagement-GUI.exe` | GUI version (Standalone EXE) |
| 🚀 `Run-DisableUSBPowerManagement.bat` | CLI launcher (auto-elevates) |
| 🚀 `Run-GUI.bat` | GUI launcher (auto-elevates) |
| 🔨 `Build-GUI-EXE.bat` | Builds the standalone EXE |
| 🧪 `tests/` | Pester unit tests |

---

## 🔧 What It Does (Technical)

<details>
<summary><b>Click to expand technical details</b></summary>

### 1. Power Plan Configuration
Disables USB Selective Suspend in **all** Windows power plans:
- Both AC (plugged in) and DC (battery) modes
- Uses `powercfg.exe` with proper GUIDs

### 2. Device Registry Settings
For every USB device, sets:
```
EnhancedPowerManagementEnabled = 0
SelectiveSuspendEnabled = 0
AllowIdleIrpInD3 = 0
DeviceSelectiveSuspended = 0
SelectiveSuspendSupported = 0
```

### 3. USB Service Configuration
Configures `DisableSelectiveSuspend = 1` for:
- `USBHUB` / `USBHUB3` (Hub drivers)
- `USBXHCI` (USB 3.0 controller)
- `USBEHCI` (USB 2.0 controller)
- `USBUHCI` / `USBOHCI` (USB 1.1 controllers)
- `USBSTOR` (USB storage)
- `USBCCGP` (Composite devices)

### 4. WMI Power Management
Disables `MSPower_DeviceEnable` for USB devices via WMI/CIM.

</details>

---

## 🐛 Troubleshooting

<details>
<summary><b>"Execution Policy" error</b></summary>

Run this command first:
```powershell
Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process
```
Then run the script again.

</details>

<details>
<summary><b>"Access Denied" error</b></summary>

The script must run as Administrator:
1. Right-click `Run-GUI.bat` or `Run-DisableUSBPowerManagement.bat`
2. Select **"Run as administrator"**

</details>

<details>
<summary><b>Devices still disconnecting after running</b></summary>

1. **Restart your computer** - Changes require a reboot
2. **Update USB drivers** - Old drivers may override settings
3. **Try different USB ports** - Hardware issues with specific ports
4. **Check cables/hubs** - Faulty cables or unpowered hubs cause issues
5. **Run again** - Some devices need multiple passes

</details>

<details>
<summary><b>Batch file opens and closes immediately</b></summary>

Right-click the `.bat` file and select **"Run as administrator"**.

</details>

<details>
<summary><b>Want to undo the changes?</b></summary>

**GUI:** Click the **"Restore Defaults"** button

**CLI:**
```powershell
.\Disable-USBPowerManagement.ps1 -Restore
```

</details>

---

## ⚠️ Important Notes

| Note | Details |
|------|---------|
| 🔄 **Restart Required** | Restart your PC after running for full effect |
| 🔋 **Battery Impact** | May slightly reduce laptop battery life |
| ✅ **Safe to Re-run** | Running multiple times is harmless |
| ↩️ **Reversible** | Use `-Restore` or GUI button to undo |

---

## 🤝 Contributing

Contributions welcome! See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

## 📄 License

MIT License - see [LICENSE](LICENSE) for details.

## 📬 Support

1. Check [Troubleshooting](#-troubleshooting) above
2. Search [existing issues](../../issues)
3. Open a [new issue](../../issues/new) with system details

---

<div align="center">

**⭐ If this helped you, please star the repo!**

Made with ❤️ by [Diobyte](https://github.com/Diobyte)

</div>
