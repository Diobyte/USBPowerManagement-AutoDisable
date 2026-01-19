@echo off
setlocal EnableDelayedExpansion
chcp 65001 >nul 2>&1
:: ============================================================
:: USB Power Management Disabler - GUI Launcher
:: Double-click this file to run the GUI version
:: Version: 1.4.1
:: Author: Diobyte
:: Repository: https://github.com/Diobyte/USBPowerManagement-AutoDisable
::
:: Exit Codes:
::   0 - Success
::   1 - Error (missing files, no admin rights, or failure)
:: ============================================================

title USB Power Management Disabler GUI

:: Check for admin rights using modern method (net session)
>nul 2>&1 net session

if %errorlevel% NEQ 0 (
    echo Requesting Administrator privileges...
    goto UACPrompt
) else ( goto gotAdmin )

:UACPrompt
    set "_vbsFile=%temp%\getadmin_%RANDOM%%RANDOM%.vbs"
    set "_batchFile=%~f0"
    set "_batchDir=%~dp0"
    echo Set UAC = CreateObject^("Shell.Application"^) > "!_vbsFile!"
    if not exist "!_vbsFile!" (
        echo Failed to create elevation script. Check temp folder permissions.
        pause
        exit /B 1
    )
    echo UAC.ShellExecute "!_batchFile!", "", "!_batchDir!", "runas", 1 >> "!_vbsFile!"
    cscript //nologo "!_vbsFile!" 2>nul
    del /q "!_vbsFile!" >nul 2>&1
    exit /B 0

:gotAdmin
    CD /D "%~dp0"

:: Check if EXE version exists, use it preferentially
if exist "%~dp0USBPowerManagement-GUI.exe" (
    start "" /WAIT "%~dp0USBPowerManagement-GUI.exe"
    if %errorlevel% NEQ 0 (
        echo EXE failed to run, trying PowerShell script...
        goto TryPowerShell
    )
    exit /B 0
)

:TryPowerShell
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
