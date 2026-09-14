@echo off
setlocal
set "PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if not exist "%PS%" set "PS=powershell"
echo.
echo  ============================================================
echo    Force overwrite GitHub with your local version
echo  ============================================================
echo.
echo  1) Rebuilds docs (cover images + BGM are refreshed)
echo  2) Commits everything, then force-pushes to GitHub
echo.
echo  This REPLACES what is on GitHub with the files on this PC.
echo  Anything that exists ONLY on GitHub will be lost.
echo.
"%PS%" -NoProfile -ExecutionPolicy Bypass -File "%~dp0app\scripts\git_save.ps1" -Mode force -BuildWeb %*
echo.
pause
