# Contributing to USB Power Management Auto-Disable

First off, thank you for considering contributing to this project! 🎉

## Table of Contents

- [Code of Conduct](#code-of-conduct)
- [How Can I Contribute?](#how-can-i-contribute)
  - [Reporting Bugs](#reporting-bugs)
  - [Suggesting Enhancements](#suggesting-enhancements)
  - [Pull Requests](#pull-requests)
- [Style Guidelines](#style-guidelines)
  - [PowerShell Style Guide](#powershell-style-guide)
  - [Commit Messages](#commit-messages)
- [Testing](#testing)

## Code of Conduct

This project and everyone participating in it is governed by our commitment to creating a welcoming environment. Please be respectful and constructive in all interactions.

## How Can I Contribute?

### Reporting Bugs

Before creating bug reports, please check existing issues to avoid duplicates.

When creating a bug report, please include:

1. **System Information:**
   - Windows version (e.g., Windows 11 22H2)
   - PowerShell version (`$PSVersionTable.PSVersion`)
   - Architecture (x64/x86/ARM64)

2. **Steps to Reproduce:**
   - Exact commands you ran
   - Expected behavior
   - Actual behavior

3. **Error Messages:**
   - Full error text (if any)
   - Screenshot of the issue (if applicable)

4. **Additional Context:**
   - USB devices connected
   - Any relevant system configuration

**Bug Report Template:**

> **Bug Description**  
> A clear description of what the bug is.
>
> **System Information**  
> - Windows Version:  
> - PowerShell Version:  
> - Architecture:  
>
> **Steps to Reproduce**  
> 1.  
> 2.  
> 3.  
>
> **Expected Behavior**  
> What you expected to happen.
>
> **Actual Behavior**  
> What actually happened.
>
> **Error Messages**  
> Paste any error messages here
>
> **Additional Context**  
> Any other relevant information.

### Suggesting Enhancements

Enhancement suggestions are welcome! Please include:

1. **Use Case:** Why is this enhancement needed?
2. **Proposed Solution:** How would it work?
3. **Alternatives Considered:** What other approaches did you consider?
4. **Compatibility:** Would this affect compatibility with any Windows versions?

### Pull Requests

1. **Fork the Repository**
   ```bash
   git clone https://github.com/YOUR-USERNAME/USBPowerManagement-AutoDisable.git
   ```

2. **Create a Feature Branch**
   ```bash
   git checkout -b feature/your-feature-name
   ```

3. **Make Your Changes**
   - Follow the [PowerShell Style Guide](#powershell-style-guide)
   - Test on multiple Windows versions if possible
   - Update documentation if needed

4. **Commit Your Changes**
   ```bash
   git commit -m "feat: add your feature description"
   ```

5. **Push and Create PR**
   ```bash
   git push origin feature/your-feature-name
   ```
   Then create a Pull Request on GitHub.

## Style Guidelines

### PowerShell Style Guide

Follow these conventions for consistency:

#### Naming Conventions
```powershell
# Functions: Use Verb-Noun format with PascalCase
function Get-USBDevices { }
function Disable-PowerManagement { }

# Variables: Use PascalCase for global, camelCase for local
$GlobalConfig = @{}
$localVariable = "value"

# Parameters: Use PascalCase
param(
    [string]$DeviceName,
    [int]$TimeoutSeconds
)
```

#### Code Formatting
```powershell
# Use 4 spaces for indentation (not tabs)
function Example {
    if ($condition) {
        # Code here
    }
}

# Use braces on the same line
if ($condition) {
    # Good
}

# Not this:
if ($condition)
{
    # Avoid
}

# Include spaces around operators
$result = $a + $b  # Good
$result=$a+$b      # Bad
```

#### Error Handling
```powershell
# Use try-catch with meaningful error messages
try {
    # Risky operation
}
catch {
    Write-Status "Failed to perform action: $($_.Exception.Message)" "Error"
}

# Prefer -ErrorAction over $ErrorActionPreference for specific commands
Get-Item -Path $path -ErrorAction SilentlyContinue
```

#### Documentation
```powershell
# Include comment-based help for functions
<#
.SYNOPSIS
    Brief description of the function.

.DESCRIPTION
    Detailed description of what the function does.

.PARAMETER ParameterName
    Description of the parameter.

.EXAMPLE
    Example-Function -Parameter "Value"
    Description of what this example does.

.OUTPUTS
    Describe what the function returns.
#>
function Example-Function {
    # Function body
}
```

### Commit Messages

Follow the [Conventional Commits](https://www.conventionalcommits.org/) specification:

```
<type>(<scope>): <description>

[optional body]

[optional footer]
```

**Types:**
- `feat`: New feature
- `fix`: Bug fix
- `docs`: Documentation changes
- `style`: Code style changes (formatting, etc.)
- `refactor`: Code refactoring
- `test`: Adding or modifying tests
- `chore`: Maintenance tasks

**Examples:**
```
feat: add support for USB4 devices
fix: handle devices without Device Parameters registry key
docs: update README with Windows 11 specific instructions
refactor: consolidate registry modification functions
```

## Testing

Before submitting a PR, please test your changes:

### Running Pester Tests

The project includes automated Pester tests. Run them locally before submitting:

```powershell
# Install Pester if not already installed
Install-Module -Name Pester -Force -Scope CurrentUser -MinimumVersion 5.0.0

# Run all tests
Import-Module Pester
$config = New-PesterConfiguration
$config.Run.Path = "./tests"
$config.Output.Verbosity = "Detailed"
Invoke-Pester -Configuration $config
```

### Manual Testing Checklist

- [ ] Script runs without errors on Windows 10
- [ ] Script runs without errors on Windows 11
- [ ] Admin privilege check works correctly
- [ ] UAC prompt works in batch file
- [ ] All USB devices are detected
- [ ] Power management settings are applied
- [ ] Report generation works correctly
- [ ] Restart prompt functions properly

### Test Environments

If possible, test on:
- Windows 10 (20H2 or later)
- Windows 11 (21H2 or later)
- Both PowerShell 5.1 and PowerShell 7+

### Reporting Test Results

Include test results in your PR:
```markdown
## Test Results

| Environment | Result | Notes |
|-------------|--------|-------|
| Windows 11 22H2, PS 5.1 | ✅ Pass | |
| Windows 10 21H2, PS 5.1 | ✅ Pass | |
| Windows 11, PS 7.4 | ✅ Pass | Minor warning about CIM |
```

---

Thank you for contributing! 🙏
