@echo off
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\Repair-DNS.ps1"
if errorlevel 1 pause
