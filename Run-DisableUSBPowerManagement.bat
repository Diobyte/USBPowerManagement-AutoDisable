@echo off
setlocal EnableDelayedExpansion
chcp 65001 >nul 2>&1
:: ============================================================
:: USB Power Management Disabler - Easy Launcher
:: Double-click this file to run the script as Administrator
:: Version: 1.4.0
:: Author: Diobyte
:: Repository: https://github.com/Diobyte/USBPowerManagement-AutoDisable
:: 
:: Exit Codes:
::   0 - Success
::   1 - Error (missing script, no admin rights, or script failure)
:: ============================================================

title USB Power Management Disabler

:: Check for admin rights and self-elevate if needed
>nul 2>&1 "%SYSTEMROOT%\system32\cacls.exe" "%SYSTEMROOT%\system32\config\system"

if '%errorlevel%' NEQ '0' (
    echo Requesting Administrator privileges...
    goto UACPrompt
) else ( goto gotAdmin )

:UACPrompt
    echo Set UAC = CreateObject^("Shell.Application"^) > "%temp%\getadmin.vbs"
    echo UAC.ShellExecute "%~s0", "", "", "runas", 1 >> "%temp%\getadmin.vbs"
    cscript //nologo "%temp%\getadmin.vbs"
    del /q "%temp%\getadmin.vbs" >nul 2>&1
    exit /B 0

:gotAdmin
    pushd "%CD%"
    CD /D "%~dp0"

:: Verify PowerShell script exists
if not exist "%~dp0Disable-USBPowerManagement.ps1" (
    echo.
    echo ============================================================
    echo   ERROR: Disable-USBPowerManagement.ps1 not found!
    echo   Please ensure the script is in the same directory.
    echo ============================================================
    echo.
    pause
    exit /B 1
)

:: Verify PowerShell is available
where powershell.exe >nul 2>&1
if %errorlevel% NEQ 0 (
    echo.
    echo ============================================================
    echo   ERROR: PowerShell is not available on this system!
    echo   Please install PowerShell 3.0 or later.
    echo ============================================================
    echo.
    pause
    exit /B 1
)

:: Run the PowerShell script
echo.
echo ============================================================
echo   USB Power Management Disabler
echo   Running script with Administrator privileges...
echo ============================================================
echo.

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Disable-USBPowerManagement.ps1"

set SCRIPT_EXIT_CODE=%errorlevel%

echo.
if %SCRIPT_EXIT_CODE% EQU 0 (
    echo ============================================================
    echo   Script completed successfully!
    echo   Press any key to close this window.
    echo ============================================================
) else (
    echo ============================================================
    echo   Script completed with warnings or errors.
    echo   Exit code: %SCRIPT_EXIT_CODE%
    echo   Press any key to close this window.
    echo ============================================================
)
pause >nul
exit /B %SCRIPT_EXIT_CODE%
