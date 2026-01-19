# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.4.0] - 2026-01-19

### Added
- **Restore Feature** - New `-Restore` parameter to revert USB power management to Windows defaults
- **Export Report** - New `-ExportReport` parameter to save reports to CSV, JSON, or TXT files
- **GUI Export Log** - Export activity log button in GUI
- **GUI Restore Button** - Restore defaults button in GUI with amber color styling
- **GUI Select All/Deselect All** - Buttons to quickly select or deselect all devices in the list
- **GUI Checkboxes** - Device list now has checkboxes for individual device selection
- **Tooltips** - Added helpful tooltips to all GUI buttons
- **Pester Tests** - Comprehensive unit tests for core functionality
- **GitHub Actions CI/CD** - Automated PowerShell validation and testing workflow
- **Write-Information Support** - Uses Write-Information with tags for PowerShell 5.0+ compatibility
- `Enable-USBPowerManagement` function for restoring defaults
- `Start-RestorePowerManagement` function in GUI

### Changed
- GUI window slightly taller to accommodate new buttons
- Device list now shows checkboxes (all checked by default)
- Improved button layout with better spacing
- Updated documentation with new parameters and features
- `Write-Status` function now outputs to both Write-Host and Write-Information streams

### Fixed
- Button state management during operations (all buttons now properly disabled/enabled)

## [1.3.0] - 2026-01-19

### Added
- **GUI Version** (`USBPowerManagement-GUI.ps1`) with modern Windows Forms interface
- Standalone EXE compilation support via PS2EXE
- `Build-GUI-EXE.bat` script to compile GUI to standalone executable
- `Run-GUI.bat` launcher for GUI version
- Visual device list showing USB devices and their power management status
- Color-coded device status (green = disabled, red = enabled)
- Progress bar for operation tracking
- Activity log with timestamped, color-coded messages
- Click-to-elevate admin prompt in GUI
- Restart prompt dialog after completion

### Changed
- Updated README with GUI instructions and new file descriptions
- Reorganized Quick Start section to feature GUI as recommended option

## [1.2.0] - 2026-01-19

### Added
- `-ReportOnly` parameter to generate status report without making changes
- `-NoRestartPrompt` parameter to skip the restart confirmation
- `-EnableLogging` parameter for transcript logging to file
- Script-level device modification tracking and summary
- `[CmdletBinding()]` attribute to all functions for better PowerShell integration
- Strict mode (`Set-StrictMode -Version Latest`) for improved code quality
- PowerShell availability check in batch launcher
- UTF-8 code page support in batch launcher
- ISE detection to avoid restart prompt issues

### Changed
- Improved parameter validation with `[ValidateSet()]` attributes
- Enhanced `Write-Status` function with proper CmdletBinding
- Better interactive mode detection for restart prompt
- Registry path checks now use `-LiteralPath` where appropriate
- More informative completion summary with device counts

### Fixed
- Potential issues with PowerShell ISE environment
- Improved error handling in transcript logging

## [1.1.0] - 2026-01-19

### Added
- Comprehensive cross-version compatibility for Windows 7/8/8.1/10/11
- PowerShell 3.0+ support with automatic fallbacks
- CIM to WMI fallback for older systems
- Detailed timestamped logging output
- USB device power management report generation
- Multiple USB service configuration (USBXHCI, USBEHCI, etc.)
- Enhanced error handling with graceful degradation
- Support for USB Storage (USBSTOR) devices
- Interactive restart prompt with countdown

### Changed
- Improved device detection to include all USB controller types
- Enhanced registry modification with multiple fallback paths
- Better status messages with color-coded output
- Updated documentation and help text

### Fixed
- Handling of devices without Device Parameters registry key
- Compatibility with systems lacking PnP cmdlets
- WMI power namespace availability checks

## [1.0.0] - 2026-01-15

### Added
- Initial release
- Disable USB Selective Suspend in all power plans
- Disable "Allow the computer to turn off this device" for USB devices
- Registry-based power management configuration
- Batch file launcher with UAC elevation
- Basic error handling
- Administrator privilege verification

---

## Version History Summary

| Version | Date | Description |
|---------|------|-------------|
| 1.4.0 | 2026-01-19 | Restore feature, export reports, Pester tests, CI/CD |
| 1.3.0 | 2026-01-19 | GUI version with EXE compilation support |
| 1.2.0 | 2026-01-19 | Advanced parameters and improved code quality |
| 1.1.0 | 2026-01-19 | Enhanced compatibility and features |
| 1.0.0 | 2026-01-15 | Initial release |

## Upgrade Notes

### Upgrading to 1.4.0

No action required. New features are additive:
- Use `-Restore` to revert to Windows defaults
- Use `-ExportReport <path>` to save reports
- GUI now has "Export Log" and "Restore Defaults" buttons

### Upgrading to 1.3.0

No action required. The GUI version is a new addition. You can use either:
- `Run-GUI.bat` or `USBPowerManagement-GUI.exe` for the graphical interface
- `Run-DisableUSBPowerManagement.bat` or the PowerShell script for command line

### Upgrading to 1.2.0

No action required. The new parameters (`-ReportOnly`, `-NoRestartPrompt`, `-EnableLogging`) are optional and backward compatible.

### Upgrading to 1.1.0

No action required. Simply replace the old script files with the new ones. The script is backward compatible and can be run on systems where it was previously executed.

## Roadmap

### Planned for Future Releases

- [x] ~~GUI version for easier use~~ ✅ Added in v1.3.0
- [x] ~~Undo/restore functionality~~ ✅ Added in v1.4.0
- [x] ~~Export/import settings feature~~ ✅ Export added in v1.4.0
- [ ] Per-device selective configuration
- [ ] Scheduled task integration
- [ ] Import settings feature
- [ ] Multi-language support
