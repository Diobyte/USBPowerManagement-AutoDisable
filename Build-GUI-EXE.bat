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

echo.
echo ============================================================
echo   USB Power Management GUI - EXE Builder
echo ============================================================
echo.

:: Check for admin using modern method (net session)
>nul 2>&1 net session
if '%errorlevel%' NEQ '0' (
    echo Requesting Administrator privileges...
    set "_vbsFile=%temp%\getadmin_%RANDOM%%RANDOM%.vbs"
    echo Set UAC = CreateObject^("Shell.Application"^) > "%_vbsFile%"
    echo UAC.ShellExecute "%~s0", "", "", "runas", 1 >> "%_vbsFile%"
    cscript //nologo "%_vbsFile%" 2>nul
    if %errorlevel% NEQ 0 (
        echo Failed to request elevation. Please run as Administrator manually.
        pause
        del /q "%_vbsFile%" >nul 2>&1
        exit /B 1
    )
    del /q "%_vbsFile%" >nul 2>&1
    exit /B 0
)

pushd "%CD%"
CD /D "%~dp0"

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

powershell.exe -NoProfile -ExecutionPolicy Bypass -Command ^
    "Invoke-PS2EXE -InputFile '%~dp0USBPowerManagement-GUI.ps1' -OutputFile '%~dp0USBPowerManagement-GUI.exe' -NoConsole -RequireAdmin -Title 'USB Power Management Disabler' -Description 'Disable USB power management to prevent device disconnections' -Company 'Diobyte' -Product 'USB Power Management Disabler' -Version '1.4.1.0' -Copyright '(c) 2026 Diobyte'" 

if exist "%~dp0USBPowerManagement-GUI.exe" (
    echo.
    echo ============================================================
    echo   BUILD SUCCESSFUL!
    echo   Output: USBPowerManagement-GUI.exe
    echo ============================================================
) else (
    echo.
    echo ============================================================
    echo   BUILD FAILED
    echo   Check the error messages above.
    echo ============================================================
)

echo.
popd
pause
