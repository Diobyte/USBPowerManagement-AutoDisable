# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
| 1.1.0 | 2026-01-19 | Enhanced compatibility and features |
| 1.0.0 | 2026-01-15 | Initial release |

## Upgrade Notes

### Upgrading to 1.1.0

No action required. Simply replace the old script files with the new ones. The script is backward compatible and can be run on systems where it was previously executed.

## Roadmap

### Planned for Future Releases

- [ ] GUI version for easier use
- [ ] Undo/restore functionality
- [ ] Per-device selective configuration
- [ ] Scheduled task integration
- [ ] Export/import settings feature
- [ ] Multi-language support
