@echo off
setlocal
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\Repair-All.ps1"
echo.
echo Press any key to close this recovery window.
pause >nul
