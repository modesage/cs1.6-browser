#!/usr/bin/env bash
#
# download-assets-linux.sh  (Linux - any distro - and macOS)
#
# Downloads Counter-Strike 1.6 (+ the Half-Life "valve" base) with SteamCMD and
# packs it into ../valve.zip (valve/ and cstrike/ at the zip root) for the
# browser project.
#
#   Native SteamCMD : x86_64 glibc Linux (Debian/Ubuntu/Mint, Fedora/RHEL/Alma/
#                     Rocky, Arch/Manjaro, openSUSE, ...)
#   Docker fallback : macOS, ARM Linux, Alpine, NixOS, or when 32-bit libs
#                     cannot be installed
#
# Usage: bash download-assets-linux.sh [-y|--yes] [-f|--force] [-h|--help]

set -u
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" || exit 1
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd -P)" || exit 1
STEAMCMD_DIR="$SCRIPT_DIR/steamcmd"
CS_DIR="$SCRIPT_DIR/cs"
OUT_ZIP="$PROJECT_DIR/valve.zip"

STEAMCMD_URLS="https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz https://media.steampowered.com/installer/steamcmd_linux.tar.gz"
DOCKER_IMAGE="steamcmd/steamcmd:latest"
DOCKER_PLATFORM="--platform linux/amd64"
APP_ID=90
MAX_ATTEMPTS=6
MIN_FREE_KB=3145728   # 3 GiB (download + zip)

ASSUME_YES=0
FORCE=0
MODE="native"
PM=""
SUDO=""
LOG_FILE=""
TMP_ZIP=""

# ---------------------------------------------------------------- output ----
if [ -t 1 ]; then
  C_G=$'\033[32m'; C_Y=$'\033[33m'; C_R=$'\033[31m'; C_0=$'\033[0m'
else
  C_G=""; C_Y=""; C_R=""; C_0=""
fi
info() { printf '%s[*]%s %s\n' "$C_G" "$C_0" "$*"; }
warn() { printf '%s[!]%s %s\n' "$C_Y" "$C_0" "$*" >&2; }
die()  { printf '%s[x]%s %s\n' "$C_R" "$C_0" "$*" >&2; exit 1; }

have() { command -v "$1" >/dev/null 2>&1; }

usage() {
  cat <<EOF
Usage: bash download-assets-linux.sh [options]

Downloads Counter-Strike 1.6 + Half-Life base assets via SteamCMD and creates
$OUT_ZIP (valve/ and cstrike/ at the archive root).

Options:
  -y, --yes     Do not ask before installing missing system packages
  -f, --force   Re-download / re-validate even if ./cs already looks complete
  -h, --help    Show this help
EOF
}

cleanup() { [ -n "$TMP_ZIP" ] && rm -f "$TMP_ZIP" 2>/dev/null; return 0; }
trap cleanup EXIT
trap 'echo; die "Interrupted."' INT TERM

# ------------------------------------------------------------------ args ----
for arg in "$@"; do
  case "$arg" in
    -y|--yes)   ASSUME_YES=1 ;;
    -f|--force) FORCE=1 ;;
    -h|--help)  usage; exit 0 ;;
    *)          die "Unknown option: $arg (try --help)" ;;
  esac
done

# ------------------------------------------------------------ environment ----
OS="$(uname -s)"
ARCH="$(uname -m)"
case "$OS" in
  Linux|Darwin) ;;
  MINGW*|MSYS*|CYGWIN*) die "This is Windows. Double-click download-assets-win.bat instead." ;;
  *) die "Unsupported OS '$OS'. Use Linux, macOS or Windows." ;;
esac

OS_ID=""
if [ -r /etc/os-release ]; then
  OS_ID="$( . /etc/os-release 2>/dev/null; printf '%s' "${ID:-}" )"
fi

is_musl() {
  local out
  have ldd || return 1
  out="$(ldd --version 2>&1 || true)"
  printf '%s' "$out" | grep -qi musl
}

cs_ok() {
  [ -d "$CS_DIR/valve" ] && [ -d "$CS_DIR/cstrike" ] \
    && ls "$CS_DIR/cstrike/maps/"*.bsp >/dev/null 2>&1
}

confirm() {
  local ans
  [ "$ASSUME_YES" -eq 1 ] && return 0
  [ -t 0 ] || return 1
  printf '%s [Y/n] ' "$1"
  read -r ans || ans=""
  case "$ans" in ""|y|Y|yes|YES|Yes) return 0 ;; *) return 1 ;; esac
}

detect_sudo() {
  if [ "$(id -u)" -eq 0 ]; then SUDO=""
  elif have sudo; then SUDO="sudo"
  elif have doas; then SUDO="doas"
  else SUDO="__none__"
  fi
}

detect_pm() {
  if   have apt-get;     then PM="apt"
  elif have dnf;         then PM="dnf"
  elif have yum;         then PM="yum"
  elif have pacman;      then PM="pacman"
  elif have zypper;      then PM="zypper"
  else PM=""
  fi
}

check_disk() {
  local avail
  avail="$(df -Pk "$SCRIPT_DIR" 2>/dev/null | awk 'NR==2 {print $4}')"
  case "$avail" in ''|*[!0-9]*) return 0 ;; esac
  if [ "$avail" -lt "$MIN_FREE_KB" ]; then
    die "Not enough free disk space in $SCRIPT_DIR (need at least 3 GiB, have $((avail / 1024)) MiB)."
  fi
}

# ------------------------------------------------------- package handling ----
libs_cmd_display() {
  case "$PM" in
    apt)    echo "sudo apt-get update && sudo apt-get install -y lib32gcc-s1 lib32stdc++6 ca-certificates   (older releases: lib32gcc1)" ;;
    dnf)    echo "sudo dnf install -y glibc.i686 libstdc++.i686" ;;
    yum)    echo "sudo yum install -y glibc.i686 libstdc++.i686" ;;
    pacman) echo "sudo pacman -S --needed lib32-gcc-libs   (enable the [multilib] repo in /etc/pacman.conf first, then: sudo pacman -Syu)" ;;
    zypper) echo "sudo zypper install glibc-32bit libstdc++6-32bit libgcc_s1-32bit" ;;
    *)      echo "install the 32-bit (i386) versions of glibc, libstdc++ and libgcc with your package manager" ;;
  esac
}

have_32bit_libs() {
  local p ldso="" cache
  for p in /lib/ld-linux.so.2 /lib32/ld-linux.so.2 /usr/lib/ld-linux.so.2 \
           /usr/lib32/ld-linux.so.2 /lib/i386-linux-gnu/ld-linux.so.2 \
           /usr/lib/i386-linux-gnu/ld-linux.so.2; do
    if [ -e "$p" ]; then ldso="$p"; break; fi
  done
  [ -n "$ldso" ] || return 1
  # 32-bit entries are listed as "(libc6)", 64-bit ones as "(libc6,x86-64)".
  cache="$(PATH="$PATH:/sbin:/usr/sbin" ldconfig -p 2>/dev/null)" || return 0
  [ -n "$cache" ] || return 0
  printf '%s\n' "$cache" | grep -Eq 'libstdc\+\+\.so\.6 \(libc6\) =>' || return 1
  printf '%s\n' "$cache" | grep -Eq 'libgcc_s\.so\.1 \(libc6\) =>'   || return 1
  return 0
}

install_pkgs() {   # install_pkgs <package...>   (generic names are per-PM below)
  case "$PM" in
    apt)    $SUDO apt-get install -y "$@" ;;
    dnf)    $SUDO dnf install -y "$@" ;;
    yum)    $SUDO yum install -y "$@" ;;
    pacman) $SUDO pacman -S --needed --noconfirm "$@" ;;
    zypper) $SUDO zypper --non-interactive install "$@" ;;
    *)      return 1 ;;
  esac
}

install_32bit_libs() {
  local g
  case "$PM" in
    apt)
      $SUDO apt-get update || warn "apt-get update failed; continuing anyway."
      g="lib32gcc-s1"
      apt-cache show lib32gcc-s1 >/dev/null 2>&1 || g="lib32gcc1"
      $SUDO apt-get install -y "$g" lib32stdc++6 ca-certificates
      ;;
    dnf|yum)
      install_pkgs glibc.i686 libstdc++.i686
      ;;
    pacman)
      if ! pacman -Sl multilib >/dev/null 2>&1; then
        warn "The Arch [multilib] repository is not enabled."
        warn "Uncomment [multilib] + its Include line in /etc/pacman.conf, run 'sudo pacman -Syu', then re-run this script."
        return 1
      fi
      install_pkgs lib32-gcc-libs
      ;;
    zypper)
      install_pkgs glibc-32bit libstdc++6-32bit libgcc_s1-32bit
      ;;
    *)
      return 1
      ;;
  esac
}

ensure_32bit_libs() {
  [ "${SKIP_DEPS_CHECK:-0}" = "1" ] && return 0
  have_32bit_libs && return 0

  warn "32-bit runtime libraries required by SteamCMD are missing."
  detect_pm
  detect_sudo
  if [ -z "$PM" ] || [ "$SUDO" = "__none__" ]; then
    warn "Cannot install them automatically. Run: $(libs_cmd_display)"
    return 1
  fi
  info "Will run: $(libs_cmd_display)"
  if ! confirm "Install the missing packages now?"; then
    warn "Skipped. Install them yourself with: $(libs_cmd_display)"
    return 1
  fi
  install_32bit_libs || return 1
  return 0
}

ensure_downloader() {
  have tar || die "'tar' is required but not installed."
  if have curl || have wget; then return 0; fi
  warn "Neither curl nor wget is installed."
  detect_pm
  detect_sudo
  if [ -n "$PM" ] && [ "$SUDO" != "__none__" ] && confirm "Install curl now?"; then
    [ "$PM" = "apt" ] && { $SUDO apt-get update || true; }
    install_pkgs curl || die "Could not install curl. Install curl or wget and re-run."
  else
    die "Install curl or wget and re-run."
  fi
}

download_file() {   # download_file <url> <dest>
  if have curl; then
    curl -fsSL --retry 3 --retry-delay 2 --connect-timeout 20 -o "$2" "$1"
  elif have wget; then
    wget -q --tries=3 --timeout=30 -O "$2" "$1"
  else
    return 1
  fi
}

install_steamcmd() {
  local tmp url ok=0
  if [ -x "$STEAMCMD_DIR/steamcmd.sh" ]; then
    info "SteamCMD already installed."
    return 0
  fi
  info "SteamCMD not found. Downloading..."
  mkdir -p "$STEAMCMD_DIR" || die "Cannot create $STEAMCMD_DIR"
  tmp="$(mktemp "${TMPDIR:-/tmp}/cs16-steamcmd-dl.XXXXXX")" || die "mktemp failed"
  for url in $STEAMCMD_URLS; do
    if download_file "$url" "$tmp" && tar -tzf "$tmp" >/dev/null 2>&1; then
      ok=1; break
    fi
    warn "Download from $url failed."
  done
  if [ "$ok" -ne 1 ]; then
    rm -f "$tmp"
    die "Could not download SteamCMD. Check your internet connection / proxy and re-run."
  fi
  tar -xzf "$tmp" -C "$STEAMCMD_DIR" || { rm -f "$tmp"; die "Could not extract SteamCMD."; }
  rm -f "$tmp"
  [ -f "$STEAMCMD_DIR/steamcmd.sh" ] || die "steamcmd.sh missing after extraction (unexpected archive layout)."
  chmod +x "$STEAMCMD_DIR/steamcmd.sh" 2>/dev/null
  chmod +x "$STEAMCMD_DIR/linux32/steamcmd" 2>/dev/null
  info "SteamCMD installed successfully."
}

# ----------------------------------------------------------------- docker ----
docker_usable() { have docker && docker info >/dev/null 2>&1; }

require_docker() {
  if ! have docker; then
    if [ "$OS" = "Darwin" ]; then
      die "Docker is required on macOS. Install Docker Desktop (https://www.docker.com/products/docker-desktop/) or Colima ('brew install colima docker && colima start'), then re-run.
    Alternative: copy the 'valve' and 'cstrike' folders from a Steam install of Counter-Strike 1.6 (Windows/Linux: steamapps/common/Half-Life) into $CS_DIR and re-run."
    fi
    die "Docker is required on this system. Install it (https://docs.docker.com/engine/install/) and re-run.
    Alternative: copy the 'valve' and 'cstrike' folders from a Steam install of Counter-Strike 1.6 into $CS_DIR and re-run."
  fi
  if ! docker info >/dev/null 2>&1; then
    die "Docker is installed but not usable. Start Docker (Docker Desktop / 'sudo systemctl start docker') or, on Linux, add yourself to the docker group ('sudo usermod -aG docker \$USER', then log out/in), and re-run."
  fi
}

# ---------------------------------------------------------------- download ----
steamcmd_once() {
  if [ "$MODE" = "docker" ]; then
    # shellcheck disable=SC2086
    docker run --rm $DOCKER_PLATFORM -v "$CS_DIR:/data" "$DOCKER_IMAGE" \
      +force_install_dir /data +login anonymous \
      +app_set_config "$APP_ID" mod cstrike \
      +app_update "$APP_ID" validate +quit
  else
    "$STEAMCMD_DIR/steamcmd.sh" \
      +force_install_dir "$CS_DIR" +login anonymous \
      +app_set_config "$APP_ID" mod cstrike \
      +app_update "$APP_ID" validate +quit
  fi
}

run_attempts() {
  local attempt=1 rc ok=0
  mkdir -p "$CS_DIR" || die "Cannot create $CS_DIR"
  LOG_FILE="$(mktemp "${TMPDIR:-/tmp}/cs16-steamcmd.XXXXXX")" || die "mktemp failed"

  info "Downloading Counter-Strike 1.6 assets (SteamCMD app $APP_ID, mod cstrike). Large download - please wait."
  info "Early attempts often fail with 'state is 0x202' / 'Missing configuration'. That is normal; the script retries."

  while [ "$attempt" -le "$MAX_ATTEMPTS" ]; do
    info "SteamCMD attempt $attempt/$MAX_ATTEMPTS"
    : > "$LOG_FILE"
    steamcmd_once 2>&1 | tee -a "$LOG_FILE"
    rc="${PIPESTATUS[0]}"
    if cs_ok && { [ "$rc" -eq 0 ] || grep -q "Success! App '$APP_ID'" "$LOG_FILE"; }; then
      ok=1
      break
    fi
    if [ "$attempt" -lt "$MAX_ATTEMPTS" ]; then
      warn "Attempt $attempt did not complete (exit code $rc). Retrying in 3s..."
      sleep 3
    fi
    attempt=$((attempt + 1))
  done

  if [ "$ok" -ne 1 ]; then
    warn "Download failed after $MAX_ATTEMPTS attempts. Last SteamCMD log: $LOG_FILE"
    if grep -qi 'disk write failure' "$LOG_FILE"; then
      warn "Hint: 'Disk write failure' - free up disk space or check permissions on $CS_DIR."
    fi
    if grep -qi 'No such file or directory' "$LOG_FILE"; then
      warn "Hint: 'No such file or directory' while starting SteamCMD usually means the 32-bit libraries are missing: $(libs_cmd_display)"
    fi
    if grep -qiE 'timeout|no connection|could not resolve|failed to connect' "$LOG_FILE"; then
      warn "Hint: network problem - check your connection, VPN or proxy."
    fi
    die "Giving up. Re-run the script (progress is kept), or copy valve/ and cstrike/ from a Steam install into $CS_DIR."
  fi

  if [ "$MODE" = "docker" ] && [ "$OS" = "Linux" ]; then
    # Files written by the container are owned by root; hand them back to you.
    # shellcheck disable=SC2086
    docker run --rm $DOCKER_PLATFORM -v "$CS_DIR:/data" --entrypoint chown "$DOCKER_IMAGE" \
      -R "$(id -u):$(id -g)" /data >/dev/null 2>&1 \
      || warn "Could not fix file ownership. If needed: sudo chown -R \"\$(id -u):\$(id -g)\" \"$CS_DIR\""
  fi
  rm -f "$LOG_FILE"
  LOG_FILE=""
  info "CS 1.6 assets downloaded to: $CS_DIR"
}

select_mode() {
  MODE="native"
  if [ "$OS" = "Darwin" ]; then
    MODE="docker"
    info "macOS detected: SteamCMD for macOS is 32-bit only and cannot run on macOS 10.15+, using Docker."
  elif [ "$ARCH" != "x86_64" ] && [ "$ARCH" != "amd64" ]; then
    MODE="docker"
    info "CPU architecture '$ARCH' detected: SteamCMD is x86-only, using Docker."
  elif [ "$OS_ID" = "nixos" ]; then
    MODE="docker"
    info "NixOS detected: using Docker."
  elif [ "$OS_ID" = "alpine" ] || is_musl; then
    MODE="docker"
    info "musl libc detected (SteamCMD needs glibc): using Docker."
  fi
}

prepare_native() {
  ensure_downloader
  if ! ensure_32bit_libs; then
    if docker_usable; then
      warn "Falling back to Docker."
      MODE="docker"
      return 0
    fi
    die "SteamCMD cannot run without the 32-bit libraries. Run: $(libs_cmd_display)
    Then re-run this script. (Alternative: install Docker and re-run.)"
  fi
  install_steamcmd
}

download_assets() {
  check_disk
  select_mode
  if [ "$MODE" = "native" ]; then
    prepare_native
  fi
  if [ "$MODE" = "docker" ]; then
    require_docker
    info "Using Docker image $DOCKER_IMAGE (first run pulls the image)."
  fi
  run_attempts
}

# -------------------------------------------------------------------- zip ----
try_install_zip() {
  detect_pm
  detect_sudo
  [ -n "$PM" ] && [ "$SUDO" != "__none__" ] || return 1
  confirm "No zip tool found. Install 'zip' now?" || return 1
  [ "$PM" = "apt" ] && { $SUDO apt-get update || true; }
  install_pkgs zip
}

make_zip() {
  local dir
  dir="$(dirname "$OUT_ZIP")"
  TMP_ZIP="$dir/valve.tmp.$$.zip"
  rm -f "$TMP_ZIP"

  cs_ok || die "valve/ and cstrike/ not found in $CS_DIR - cannot create the archive."

  if ! have zip && ! have python3 && ! have bsdtar; then
    try_install_zip || true
  fi

  info "Creating $OUT_ZIP ..."
  if have zip; then
    ( cd "$CS_DIR" && zip -r -q -X "$TMP_ZIP" valve cstrike ) || die "zip failed."
  elif have python3; then
    python3 - "$CS_DIR" "$TMP_ZIP" <<'PY' || die "python zip failed."
import os, sys, zipfile
root, out = sys.argv[1], sys.argv[2]
with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED, allowZip64=True) as z:
    for top in ("valve", "cstrike"):
        for dirpath, dirnames, filenames in os.walk(os.path.join(root, top)):
            dirnames.sort()
            for name in sorted(filenames):
                full = os.path.join(dirpath, name)
                if not os.path.exists(full):
                    continue  # broken symlink
                z.write(full, os.path.relpath(full, root).replace(os.sep, "/"))
PY
  elif have bsdtar; then
    bsdtar -a -cf "$TMP_ZIP" -C "$CS_DIR" valve cstrike || die "bsdtar failed."
  else
    die "No zip tool available. Install 'zip' (or python3) and re-run; the downloaded files are kept."
  fi

  [ -s "$TMP_ZIP" ] || die "Archive is empty."
  mv -f "$TMP_ZIP" "$OUT_ZIP" || die "Could not move archive to $OUT_ZIP"
  TMP_ZIP=""
  info "Created $OUT_ZIP ($(du -h "$OUT_ZIP" | cut -f1))"
}

# ------------------------------------------------------------------- main ----
main() {
  info "Project folder : $PROJECT_DIR"
  info "Game files     : $CS_DIR"
  info "Output archive : $OUT_ZIP"

  if [ "$(id -u)" -eq 0 ] && [ -n "${SUDO_USER:-}" ]; then
    warn "Running through sudo makes the files root-owned. Prefer running without sudo; the script asks for it only when needed."
  fi

  if [ "$FORCE" -eq 0 ] && cs_ok; then
    info "Existing CS 1.6 files found in $CS_DIR - skipping download (use --force to re-validate)."
  else
    download_assets
  fi

  make_zip

  echo
  info "Done. Next steps:"
  echo "    cd \"$PROJECT_DIR\""
  echo "    npx serve -l tcp://127.0.0.1:8080      # or: python3 -m http.server 8080 --bind 127.0.0.1"
  echo "    then open http://localhost:8080"
}

main
