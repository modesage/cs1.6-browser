#!/bin/bash

STEAMCMDDIR="./steamcmd"
CSINSTALLDIR="./cs"

echo
echo "[*] Checking for SteamCMD..."

# Install SteamCMD if missing
if [ ! -f "$STEAMCMDDIR/steamcmd.sh" ]; then
    echo "[*] SteamCMD not found. Downloading..."
    mkdir -p "$STEAMCMDDIR"
    curl -sSL "https://steamcdn-a.akamaihd.net/client/installer/steamcmd_osx.tar.gz" -o steamcmd.tar.gz
    tar -xvzf steamcmd.tar.gz -C "$STEAMCMDDIR" --strip-components=1
    rm steamcmd.tar.gz
    echo "[*] SteamCMD installed successfully."
else
    echo "[*] SteamCMD already installed."
fi

echo
echo "[*] Downloading Counter-Strike 1.6 assets..."
"$STEAMCMDDIR/steamcmd.sh" +login anonymous +force_install_dir "$CSINSTALLDIR" +app_update 90 validate +quit

echo
echo "[*] CS 1.6 assets downloaded to: $CSINSTALLDIR"
echo "[*] You can now zip the 'valve' and 'cstrike' folders into valve.zip for the web project."