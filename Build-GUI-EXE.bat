@echo off
:: ============================================================
:: Build USB Power Management GUI to EXE
:: Requires PS2EXE module
:: ============================================================

title Building USB Power Management GUI...

echo.
echo ============================================================
echo   USB Power Management GUI - EXE Builder
echo ============================================================
echo.

:: Check for admin (needed for module installation)
>nul 2>&1 "%SYSTEMROOT%\system32\cacls.exe" "%SYSTEMROOT%\system32\config\system"
if '%errorlevel%' NEQ '0' (
    echo Requesting Administrator privileges...
    echo Set UAC = CreateObject^("Shell.Application"^) > "%temp%\getadmin.vbs"
    echo UAC.ShellExecute "%~s0", "", "", "runas", 1 >> "%temp%\getadmin.vbs"
    cscript //nologo "%temp%\getadmin.vbs"
    del /q "%temp%\getadmin.vbs" >nul 2>&1
    exit /B 0
)

pushd "%CD%"
CD /D "%~dp0"

echo Checking for PS2EXE module...
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command ^
    "if (-not (Get-Module -ListAvailable -Name ps2exe)) { Write-Host 'Installing PS2EXE module...' -ForegroundColor Yellow; Install-Module -Name ps2exe -Force -Scope CurrentUser } else { Write-Host 'PS2EXE module found.' -ForegroundColor Green }"

echo.
echo Building EXE...
echo.

powershell.exe -NoProfile -ExecutionPolicy Bypass -Command ^
    "Invoke-PS2EXE -InputFile '%~dp0USBPowerManagement-GUI.ps1' -OutputFile '%~dp0USBPowerManagement-GUI.exe' -NoConsole -RequireAdmin -Title 'USB Power Management Disabler' -Description 'Disable USB power management to prevent device disconnections' -Company 'Diobyte' -Product 'USB Power Management Disabler' -Version '1.3.0.0' -Copyright '(c) 2026 Diobyte'" 

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
pause
