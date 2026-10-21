@echo off
setlocal EnableExtensions
cd /d "%~dp0"
echo DiscordOnly startup diagnostics
powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File "%~dp0app\launcher.ps1"
set "RET=%ERRORLEVEL%"
echo.
echo Exit code: %RET%
echo Note: The GUI runs as a separate administrator process after UAC approval.
echo.
if exist "%LOCALAPPDATA%\DiscordOnly\startup-error.log" (
  echo ----- LAST STARTUP ERROR -----
  powershell.exe -NoProfile -Command "Get-Content -LiteralPath (Join-Path $env:LOCALAPPDATA 'DiscordOnly\startup-error.log') -Tail 45"
) else (
  echo No startup-error.log file was created.
)
echo.
pause
exit /b %RET%
