# Security Policy

## Supported Versions

| Version | Supported |
| ------- | --------- |
| 1.4.x   | ✅ Yes    |
| 1.3.x   | ✅ Yes    |
| 1.2.x   | ⚠️ Limited |
| 1.1.x   | ❌ No     |
| 1.0.x   | ❌ No     |

## Reporting a Vulnerability

If you discover a security vulnerability in this project, please report it responsibly:

1. **Do NOT** open a public GitHub issue for security vulnerabilities
2. Use GitHub's [private vulnerability reporting](https://docs.github.com/en/code-security/security-advisories/guidance-on-reporting-and-writing/privately-reporting-a-security-vulnerability) feature (preferred)
3. Include as much detail as possible:
   - Description of the vulnerability
   - Steps to reproduce
   - Potential impact
   - Suggested fix (if any)

## Security Considerations

This script requires and runs with Administrator privileges because it:

- Modifies Windows power plan settings via `powercfg.exe`
- Writes to the Windows Registry (`HKLM:\SYSTEM\CurrentControlSet\...`)
- Configures system service parameters

### What the Script Does NOT Do

- Does not connect to the internet
- Does not download or execute external code
- Does not collect or transmit any user data
- Does not modify system files outside of registry settings
- Does not disable Windows security features

### Best Practices

1. **Always download from the official repository**: https://github.com/Diobyte/USBPowerManagement-AutoDisable
2. **Review the script** before running it on your system
3. **Keep the script updated** to the latest version
4. **Run only with necessary privileges** - the script will request elevation only when needed

## Acknowledgments

We appreciate responsible disclosure of security issues and will acknowledge reporters in our releases (unless anonymity is requested).
