# Counter-Strike 1.6 - Browser Edition

Play **Counter-Strike 1.6 in your browser** using the [Xash3D FWGS engine](https://github.com/FWGS/xash3d-fwgs), compiled to WebAssembly by [WebXash3D-FWGS](https://github.com/yohimik/webxash3d-fwgs).

You need your own legally obtained copy of the game data. One script per OS downloads it from Steam (anonymous login) and builds `valve.zip` for you.

---

## Project structure

```text
.
├── get_cs_assets/
│   ├── download-assets-linux.sh   # Linux (any distro) + macOS
│   ├── download-assets-win.bat    # Windows 10/11 launcher (double-click)
│   ├── download-assets-win.ps1    # Windows worker (called by the .bat)
│   ├── cs/                        # downloaded game files   (generated, git-ignored)
│   └── steamcmd/                  # SteamCMD                (generated, git-ignored)
├── index.html                     # game page
├── valve.zip                      # asset pack              (generated, git-ignored)
├── .gitignore
├── .gitattributes
└── README.md
```

---

## Quick start

You need ~3 GB free disk space and [Node.js](https://nodejs.org/en/download) (only to serve the page; Python works too, see step 2).

### 1. Build `valve.zip`

The script installs SteamCMD, downloads CS 1.6, retries automatically (Steam's app 90 often fails the first attempts), and writes `valve.zip` next to `index.html`.

#### Windows 10 / 11

Double-click `get_cs_assets\download-assets-win.bat`.

#### Linux (Ubuntu/Debian/Mint, Fedora/RHEL/Alma/Rocky, Arch/Manjaro, openSUSE, ...)

```bash
bash get_cs_assets/download-assets-linux.sh
```

If 32-bit libraries are missing, the script shows the exact `apt`/`dnf`/`yum`/`pacman`/`zypper` command and asks before running it with `sudo` (`-y` skips the question).

On Arch, enable the `[multilib]` repository in `/etc/pacman.conf` first.

#### macOS

```bash
bash get_cs_assets/download-assets-linux.sh
```

SteamCMD for macOS is 32-bit and cannot run on macOS 10.15+, so the script uses **Docker** (Docker Desktop or Colima must be running).

The same Docker fallback is used automatically on ARM Linux, Alpine and NixOS.

#### Script options

| Option | Effect |
| --- | --- |
| `-y`, `--yes` | Linux/macOS: do not ask before installing packages |
| `-f`, `--force` / `-Force` (Windows) | Re-download / re-validate even if `cs/` already looks complete |

Re-running is safe: if `cs/valve` and `cs/cstrike` already exist, the download is skipped and only `valve.zip` is rebuilt.

#### No Steam download possible? (Docker missing, Apple Silicon issues, offline machine)

Copy the `valve` and `cstrike` folders from a Steam install of Counter-Strike 1.6 (`steamapps/common/Half-Life/` on Windows/Linux) into `get_cs_assets/cs/`, then run the script again. It detects them and only builds `valve.zip`.

`valve.zip` must contain `valve/` and `cstrike/` **at its top level**. `index.html` checks this and tells you if it is wrong.

### 2. Serve the folder

Run from the project root (the folder containing `index.html` and `valve.zip`).

Local only (recommended):

```bash
npx serve -l tcp://127.0.0.1:8080
```

Reachable on your LAN:

```bash
npx serve -l 8080
```

No Node.js? Python works as well:

```bash
python3 -m http.server 8080 --bind 127.0.0.1    # Windows: py -m http.server 8080 --bind 127.0.0.1
```

### 3. Play

1. Open <http://localhost:8080>.
2. Wait until the assets are fetched and extracted (the pack is large and is held in RAM; use a desktop Chrome, Edge or Firefox with free memory).
3. Click **Go Fullscreen** (or **Play in Window**).

---

## Troubleshooting

| Symptom | Fix |
| --- | --- |
| Page says `valve.zip was not found` | Run step 1; `valve.zip` must sit next to `index.html`. |
| Page says `valve.zip must contain the 'valve' and 'cstrike' folders` | Rebuild with the script, or re-zip so both folders are at the zip root. |
| Page lists CDN files with `HTTP 404` | The pinned engine/client versions at the top of `index.html` no longer match what the CDN hosts. Try `?engine=X.Y.Z&client=X.Y.Z` in the URL, then update `DEFAULT_ENGINE_VERSION` / `DEFAULT_CLIENT_VERSION`. |
| `WebGL2 is not available` | Enable hardware acceleration in the browser; update GPU drivers. |
| Windows: `npx` blocked ("running scripts is disabled") | Use `npx.cmd serve ...` or a Command Prompt instead of PowerShell. |
| SteamCMD keeps failing (`state is 0x202`, `Missing configuration`) | Normal for the first tries; the script retries 6 times. Re-run it if it still fails (progress is kept). |
| Linux: `No such file or directory` when SteamCMD starts | 32-bit libraries are missing; run the command the script prints. |
| Windows: path under OneDrive | Move the project to a plain folder such as `C:\dev\cs1.6-browser`. |

---

**Note:** The CS 1.6 assets are not included in this project. Users must provide their own legally owned copy of the game. This project is for non-commercial, non-profit purposes only. Counter-Strike and Half-Life are trademarks of Valve Corporation.
