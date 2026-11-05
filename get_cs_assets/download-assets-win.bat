@echo off
setlocal
title Counter-Strike 1.6 asset downloader
set "PS1=%~dp0download-assets-win.ps1"
if not exist "%PS1%" goto :missing
powershell -NoProfile -ExecutionPolicy Bypass -File "%PS1%" %*
set "RC=%ERRORLEVEL%"
echo.
if "%RC%"=="0" goto :ok
echo [x] Failed with exit code %RC%. Scroll up for details.
goto :end
:ok
echo [*] Finished successfully. valve.zip is ready in the project folder.
:end
pause
exit /b %RC%
:missing
echo [x] Cannot find %PS1%
echo     Keep download-assets-win.bat and download-assets-win.ps1 in the same folder.
pause
exit /b 1
