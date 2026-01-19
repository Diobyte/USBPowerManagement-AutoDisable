@echo off
setlocal EnableDelayedExpansion
chcp 65001 >nul 2>&1
:: ============================================================
:: USB Power Management Disabler - GUI Launcher
:: Double-click this file to run the GUI version
:: ============================================================

title USB Power Management Disabler GUI

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

:: Check if EXE version exists, use it preferentially
if exist "%~dp0USBPowerManagement-GUI.exe" (
    start "" "%~dp0USBPowerManagement-GUI.exe"
    exit /B 0
)

:: Fall back to PowerShell script
if exist "%~dp0USBPowerManagement-GUI.ps1" (
    powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0USBPowerManagement-GUI.ps1"
    exit /B 0
)

:: Neither found
echo.
echo ============================================================
echo   ERROR: GUI files not found!
echo   Please ensure USBPowerManagement-GUI.ps1 or .exe exists.
echo ============================================================
echo.
pause
exit /B 1
