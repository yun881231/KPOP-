@echo off
setlocal
set "PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if not exist "%PS%" set "PS=powershell"
"%PS%" -NoProfile -ExecutionPolicy Bypass -File "%~dp0app\scripts\scan_assets.ps1"
echo.
echo Opening the game in your default browser...
start "" "%~dp0app\index.html"
timeout /t 3 >nul
