# download-assets-win.ps1
#
# Downloads Counter-Strike 1.6 (+ Half-Life "valve" base) with SteamCMD and packs
# it into ..\valve.zip (valve/ and cstrike/ at the zip root) for the browser
# project. Works on Windows 10 / 11 with the built-in Windows PowerShell 5.1.
#
# Normally started through download-assets-win.bat (double-click it).
# NOTE: this file is intentionally pure ASCII (Windows PowerShell 5.1 safe).

[CmdletBinding()]
param([switch]$Force)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'   # makes Invoke-WebRequest much faster on 5.1
try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
} catch { }

$ScriptDir = $PSScriptRoot
if (-not $ScriptDir) { $ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path }
$SteamCmdDir  = Join-Path $ScriptDir 'steamcmd'
$SteamCmdExe  = Join-Path $SteamCmdDir 'steamcmd.exe'
$CsDir        = Join-Path $ScriptDir 'cs'
$ProjectDir   = Split-Path -Parent $ScriptDir
$OutZip       = Join-Path $ProjectDir 'valve.zip'
$SteamCmdUrls = @(
    'https://steamcdn-a.akamaihd.net/client/installer/steamcmd.zip',
    'https://media.steampowered.com/installer/steamcmd.zip'
)
$AppId        = 90
$MaxAttempts  = 6
$MinFreeBytes = 3GB

function Info($m) { Write-Host "[*] $m" -ForegroundColor Green }
function Warn($m) { Write-Host "[!] $m" -ForegroundColor Yellow }
function Fail($m) { throw $m }

function Test-CsReady {
    if (-not (Test-Path -LiteralPath (Join-Path $CsDir 'valve') -PathType Container)) { return $false }
    if (-not (Test-Path -LiteralPath (Join-Path $CsDir 'cstrike') -PathType Container)) { return $false }
    $maps = Join-Path $CsDir 'cstrike\maps'
    if (-not (Test-Path -LiteralPath $maps -PathType Container)) { return $false }
    $bsp = Get-ChildItem -LiteralPath $maps -Filter '*.bsp' -File -ErrorAction SilentlyContinue | Select-Object -First 1
    return [bool]$bsp
}

function Install-SteamCmd {
    if (Test-Path -LiteralPath $SteamCmdExe) {
        Info 'SteamCMD already installed.'
        return
    }
    Info 'SteamCMD not found. Downloading...'
    New-Item -ItemType Directory -Force -Path $SteamCmdDir | Out-Null
    $tmp = Join-Path ([IO.Path]::GetTempPath()) ('steamcmd-' + [guid]::NewGuid().ToString('N') + '.zip')
    $ok = $false
    foreach ($u in $SteamCmdUrls) {
        try {
            Invoke-WebRequest -Uri $u -OutFile $tmp -UseBasicParsing
            if ((Get-Item -LiteralPath $tmp).Length -gt 100000) { $ok = $true; break }
        } catch {
            Warn ("Download from {0} failed: {1}" -f $u, $_.Exception.Message)
        }
    }
    if (-not $ok) {
        Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
        Fail 'Could not download SteamCMD. Check your internet connection / proxy / antivirus and run the script again.'
    }
    try {
        Expand-Archive -LiteralPath $tmp -DestinationPath $SteamCmdDir -Force
    } finally {
        Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
    }
    if (-not (Test-Path -LiteralPath $SteamCmdExe)) { Fail 'steamcmd.exe is missing after extraction.' }
    Info 'SteamCMD installed successfully.'
}

function Get-CsAssets {
    New-Item -ItemType Directory -Force -Path $CsDir | Out-Null
    $argLine = '+force_install_dir "{0}" +login anonymous +app_set_config {1} mod cstrike +app_update {1} validate +quit' -f $CsDir, $AppId

    Info "Downloading Counter-Strike 1.6 assets (SteamCMD app $AppId, mod cstrike). Large download - please wait."
    Info "Early attempts often fail ('state is 0x202' / 'Missing configuration'). That is normal; the script retries."

    $ok = $false
    for ($i = 1; $i -le $MaxAttempts; $i++) {
        Info "SteamCMD attempt $i/$MaxAttempts"
        $p = Start-Process -FilePath $SteamCmdExe -ArgumentList $argLine -NoNewWindow -Wait -PassThru
        $rc = $p.ExitCode
        if (($rc -eq 0) -and (Test-CsReady)) { $ok = $true; break }
        if ($i -lt $MaxAttempts) {
            Warn "Attempt $i did not complete (exit code $rc). Retrying in 3s..."
            Start-Sleep -Seconds 3
        }
    }
    if (-not $ok) {
        Fail "Download failed after $MaxAttempts attempts. Run the script again (progress is kept), or copy the 'valve' and 'cstrike' folders from a Steam install of Counter-Strike 1.6 (steamapps\common\Half-Life) into $CsDir and run it again."
    }
    Info "CS 1.6 assets downloaded to: $CsDir"
}

function New-AssetZip {
    if (-not (Test-CsReady)) { Fail "valve and cstrike folders not found in $CsDir - cannot create the archive." }

    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem

    $tmpZip = Join-Path $ProjectDir ('valve.tmp.' + [guid]::NewGuid().ToString('N') + '.zip')
    $root   = (Resolve-Path -LiteralPath $CsDir).Path.TrimEnd('\')
    Info "Creating $OutZip ... (this can take a few minutes)"

    $fs = $null
    $zip = $null
    $count = 0
    try {
        $fs  = [System.IO.File]::Open($tmpZip, [System.IO.FileMode]::Create)
        $zip = New-Object System.IO.Compression.ZipArchive($fs, [System.IO.Compression.ZipArchiveMode]::Create)
        foreach ($top in @('valve', 'cstrike')) {
            $base = Join-Path $root $top
            foreach ($f in (Get-ChildItem -LiteralPath $base -Recurse -File -Force)) {
                # Forward slashes on purpose: Compress-Archive on PS 5.1 writes backslashes,
                # which breaks the browser extractor.
                $rel   = $f.FullName.Substring($root.Length).TrimStart('\', '/').Replace('\', '/')
                $entry = $zip.CreateEntry($rel, [System.IO.Compression.CompressionLevel]::Fastest)
                $es = $entry.Open()
                $in = [System.IO.File]::OpenRead($f.FullName)
                try { $in.CopyTo($es) } finally { $in.Dispose(); $es.Dispose() }
                $count++
            }
        }
    } catch {
        if ($zip) { $zip.Dispose(); $zip = $null }
        if ($fs)  { $fs.Dispose();  $fs = $null }
        Remove-Item -LiteralPath $tmpZip -Force -ErrorAction SilentlyContinue
        throw
    }
    if ($zip) { $zip.Dispose() }
    if ($fs)  { $fs.Dispose() }

    if ($count -eq 0) {
        Remove-Item -LiteralPath $tmpZip -Force -ErrorAction SilentlyContinue
        Fail 'No files were added to the archive.'
    }
    Move-Item -LiteralPath $tmpZip -Destination $OutZip -Force
    $mb = [math]::Round((Get-Item -LiteralPath $OutZip).Length / 1MB)
    Info "Created $OutZip ($count files, $mb MB)"
}

function Main {
    Info "Project folder : $ProjectDir"
    Info "Game files     : $CsDir"
    Info "Output archive : $OutZip"

    if ($ScriptDir -match 'OneDrive') {
        Warn 'This folder is inside OneDrive. Syncing thousands of game files can slow things down or lock files. Consider a folder like C:\dev\cs1.6-browser.'
    }

    if ((-not $Force) -and (Test-CsReady)) {
        Info "Existing CS 1.6 files found in $CsDir - skipping download (use -Force to re-validate)."
    } else {
        $free = $null
        try { $free = (New-Object System.IO.DriveInfo ([IO.Path]::GetPathRoot($ScriptDir))).AvailableFreeSpace } catch { }
        if (($null -ne $free) -and ($free -lt $MinFreeBytes)) {
            Fail ("Not enough free disk space (need at least 3 GB, have {0} MB)." -f [math]::Round($free / 1MB))
        }
        Install-SteamCmd
        Get-CsAssets
    }

    New-AssetZip

    Write-Host ''
    Info 'Done. Next steps (in a Command Prompt):'
    Write-Host "    cd /d `"$ProjectDir`""
    Write-Host '    npx.cmd serve -l tcp://127.0.0.1:8080'
    Write-Host '    then open http://localhost:8080'
}

try {
    Main
} catch {
    Write-Host ''
    Write-Host ("[x] " + $_.Exception.Message) -ForegroundColor Red
    exit 1
}
exit 0
