@echo off
:: ============================================================
:: USB Power Management Disabler - Easy Launcher
:: Double-click this file to run the script as Administrator
:: ============================================================

:: Check for admin rights and self-elevate if needed
>nul 2>&1 "%SYSTEMROOT%\system32\cacls.exe" "%SYSTEMROOT%\system32\config\system"

if '%errorlevel%' NEQ '0' (
    echo Requesting Administrator privileges...
    goto UACPrompt
) else ( goto gotAdmin )

:UACPrompt
    echo Set UAC = CreateObject^("Shell.Application"^) > "%temp%\getadmin.vbs"
    echo UAC.ShellExecute "%~s0", "", "", "runas", 1 >> "%temp%\getadmin.vbs"
    "%temp%\getadmin.vbs"
    del "%temp%\getadmin.vbs"
    exit /B

:gotAdmin
    pushd "%CD%"
    CD /D "%~dp0"

:: Run the PowerShell script
echo.
echo ============================================================
echo   Running USB Power Management Disabler Script...
echo ============================================================
echo.

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Disable-USBPowerManagement.ps1"

echo.
echo ============================================================
echo   Script completed. Press any key to close this window.
echo ============================================================
pause >nul
