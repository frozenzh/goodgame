@echo off
setlocal
rem Use the script directory so double-clicking works from any current folder.
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0run_export_windows.ps1" %*
set "export_exit_code=%errorlevel%"
echo.
pause
exit /b %export_exit_code%
