@echo off
setlocal EnableDelayedExpansion
:: ============================================================
:: Build USB Power Management GUI to EXE
:: Requires PS2EXE module
:: Version: 1.4.1
:: Author: Diobyte
:: Repository: https://github.com/Diobyte/USBPowerManagement-AutoDisable
:: ============================================================

title Building USB Power Management GUI...

:: Change to script directory first
CD /D "%~dp0"

echo.
echo ============================================================
echo   USB Power Management GUI - EXE Builder
echo ============================================================
echo.

:: Check for admin using modern method (net session)
>nul 2>&1 net session
if %errorlevel% NEQ 0 (
    echo This script requires Administrator privileges.
    echo.
    echo Right-click on this file and select "Run as administrator"
    echo.
    pause
    exit /B 1
)

echo Running with Administrator privileges...
echo.

echo Checking for NuGet provider and PS2EXE module...
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command ^
    "$null = [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; ^
    if (-not (Get-PackageProvider -Name NuGet -ListAvailable -ErrorAction SilentlyContinue)) { ^
        Write-Host 'Installing NuGet provider...' -ForegroundColor Yellow; ^
        Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope CurrentUser | Out-Null ^
    }; ^
    if (-not (Get-Module -ListAvailable -Name ps2exe)) { ^
        Write-Host 'Installing PS2EXE module...' -ForegroundColor Yellow; ^
        Install-Module -Name ps2exe -Force -Scope CurrentUser -AllowClobber ^
    } else { ^
        Write-Host 'PS2EXE module found.' -ForegroundColor Green ^
    }"

echo.
echo Building EXE...
echo.

:: Delete old EXE to ensure we can detect build failures properly
if exist "USBPowerManagement-GUI.exe" del /q "USBPowerManagement-GUI.exe" >nul 2>&1

powershell.exe -NoProfile -ExecutionPolicy Bypass -Command ^
    "Import-Module ps2exe; $ErrorActionPreference = 'Stop'; try { Invoke-PS2EXE -InputFile 'USBPowerManagement-GUI.ps1' -OutputFile 'USBPowerManagement-GUI.exe' -NoConsole -RequireAdmin -Title 'USB Power Management Disabler' -Description 'Disable USB power management to prevent device disconnections' -Company 'Diobyte' -Product 'USB Power Management Disabler' -Version '1.4.1.0' -Copyright '(c) 2026 Diobyte'; exit 0 } catch { Write-Host ('Build error: ' + $_.Exception.Message) -ForegroundColor Red; exit 1 }"

set BUILD_EXIT_CODE=%errorlevel%

if %BUILD_EXIT_CODE% NEQ 0 (
    echo.
    echo ============================================================
    echo   BUILD FAILED
    echo   PS2EXE returned error code: %BUILD_EXIT_CODE%
    echo   Check the error messages above.
    echo ============================================================
    echo.
    pause
    exit /B 1
)

if exist "USBPowerManagement-GUI.exe" (
    :: Verify file size is greater than 0
    for %%A in ("USBPowerManagement-GUI.exe") do (
        if %%~zA GTR 0 (
            echo.
            echo ============================================================
            echo   BUILD SUCCESSFUL!
            echo   Output: USBPowerManagement-GUI.exe
            echo   Size: %%~zA bytes
            echo ============================================================
        ) else (
            echo.
            echo ============================================================
            echo   BUILD FAILED
            echo   Output file is empty ^(0 bytes^).
            echo ============================================================
            del /q "USBPowerManagement-GUI.exe" >nul 2>&1
            echo.
            pause
            exit /B 1
        )
    )
) else (
    echo.
    echo ============================================================
    echo   BUILD FAILED
    echo   Output file was not created.
    echo   Check the error messages above.
    echo ============================================================
    echo.
    pause
    exit /B 1
)

echo.
pause
