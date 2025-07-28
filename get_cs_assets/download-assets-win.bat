@echo off
setlocal

:: Folder where SteamCMD will be installed
set STEAMCMDDIR=%~dp0steamcmd
set CSINSTALLDIR=%~dp0cs

echo.
echo [*] Checking for SteamCMD...

if not exist "%STEAMCMDDIR%\steamcmd.exe" (
    echo [*] SteamCMD not found. Downloading...
    mkdir "%STEAMCMDDIR%"
    powershell -Command "Invoke-WebRequest -Uri https://steamcdn-a.akamaihd.net/client/installer/steamcmd.zip -OutFile steamcmd.zip"
    powershell -Command "Expand-Archive -Path steamcmd.zip -DestinationPath '%STEAMCMDDIR%'"
    del steamcmd.zip
    echo [*] SteamCMD installed successfully.
) else (
    echo [*] SteamCMD already installed.
)

echo.
echo [*] Downloading Counter-Strike 1.6 assets...
"%STEAMCMDDIR%\steamcmd.exe" +login anonymous +force_install_dir "%CSINSTALLDIR%" +app_update 90 validate +quit

echo.
echo [*] CS 1.6 assets downloaded to: %CSINSTALLDIR%
echo [*] You can now zip the 'valve' and 'cstrike' folders into valve.zip for the web project.

pause
