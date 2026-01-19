@echo off
setlocal EnableDelayedExpansion
chcp 65001 >nul 2>&1
:: ============================================================
:: USB Power Management Disabler - GUI Launcher
:: Double-click this file to run the GUI version
:: Version: 1.4.0
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

if '%errorlevel%' NEQ '0' (
    echo Requesting Administrator privileges...
    goto UACPrompt
) else ( goto gotAdmin )

:UACPrompt
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

:gotAdmin
    pushd "%CD%"
    CD /D "%~dp0"

:: Check if EXE version exists, use it preferentially
if exist "%~dp0USBPowerManagement-GUI.exe" (
    start "" "%~dp0USBPowerManagement-GUI.exe"
    popd
    exit /B 0
)

:: Fall back to PowerShell script
if exist "%~dp0USBPowerManagement-GUI.ps1" (
    powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0USBPowerManagement-GUI.ps1"
    popd
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
popd
exit /B 1
