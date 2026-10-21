@echo off
setlocal
cd /d "%~dp0"
echo DiscordOnly - DNS diagnostics ^(read only^)
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\Diagnose-DNS.ps1"
echo.
pause
