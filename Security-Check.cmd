@echo off
setlocal
powershell.exe -NoProfile -File "%~dp0tools\Security-Check.ps1" -ScanWithDefender
echo.
pause
