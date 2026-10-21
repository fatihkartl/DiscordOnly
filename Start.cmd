@echo off
setlocal EnableExtensions
cd /d "%~dp0"
if not exist "%~dp0Start-Silent.vbs" (
    echo [ERROR] Start-Silent.vbs bulunamadi. ZIP dosyasini tamamen cikarin.
    pause
    exit /b 1
)
start "" wscript.exe "%~dp0Start-Silent.vbs"
exit /b 0
