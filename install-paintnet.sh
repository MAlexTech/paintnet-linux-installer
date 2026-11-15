#!/usr/bin/env bash
# ==============================================================================
# Universal, Idempotent Paint.NET-on-WINE Installer & GPU Optimizer for Linux
# By: MAlexTech
# Distros: Arch / Manjaro / CachyOS, Ubuntu / Mint / Pop!_OS / Debian, Fedora, openSUSE
# GPUs:    NVIDIA, AMD (RADV), Intel iGPU/Arc (ANV), Hybrid Laptops + llvmpipe
# Based on: paintdotnet/Paint.NET-on-WINE & bluesillybeard/Paint.NET-Wine-Patches
# ==============================================================================

set -euo pipefail

GITHUB_USER="${GITHUB_USER:-MAlexTech}"

PDN_BASE_DIR="$HOME/.local/share/paintdotnet"
PDN_APP_DIR="$PDN_BASE_DIR/app"
PDN_PREFIX="$PDN_BASE_DIR/wineprefix"
PDN_VERSION_FILE="$PDN_BASE_DIR/.installed_version"
PDN_THEME_MODE_FILE="$PDN_BASE_DIR/.theme_mode"
PDN_SETUP_MARKER="$PDN_PREFIX/.pdn_setup_done"
PDN_THEME_MARKER="$PDN_PREFIX/.pdn_theme_v2"
PDN_LEGACY_THEME_MARKER="$PDN_PREFIX/.pdn_theme_v1"
PDN_DXVK_ORIG="$PDN_APP_DIR/dxvk.conf"
PDN_DXVK_FAST="$PDN_BASE_DIR/dxvk-fast.conf"
PDN_ICON_PATH="$HOME/.local/share/icons/hicolor/256x256/apps/paintdotnet.png"
PDN_DESKTOP_FILE="$HOME/.local/share/applications/paintdotnet.desktop"
RUNNER_PATH="/usr/local/bin/wine-runner"
PDN_API_URL="https://api.github.com/repos/paintdotnet/Paint.NET-on-WINE/releases"

MIN_WINE_MAJOR=11
MIN_WINE_MINOR=21

FORCE_DOWNLOAD=false
REINIT_PREFIX=false
FORCE_DEPS=false
FORCE_GPU_FILTER=""
THEME_ARG=""
SHOW_AVATAR=true
BANNER_SHOWN=false
UNINSTALL=false

HAS_NVIDIA=false
HAS_AMD=false
HAS_INTEL=false

TEMP_PATHS=()
cleanup() {
    local p
    for p in "${TEMP_PATHS[@]}"; do
        [ -n "$p" ] && rm -rf "$p"
    done
}
trap cleanup EXIT

usage() {
    cat << USAGE
Usage: $(basename "$0") [OPTIONS]

Universal, idempotent installer & GPU optimizer for Paint.NET-on-WINE on Linux.
Safe to run multiple times; skips already-completed steps automatically.

Options:
  -t, --theme <win|gtk>   Dialog theme: 'win' (default Windows/Wine style)
                          or 'gtk' (dark Linux-matched palette, RGB 48 48 51)
  -f, --force             Force re-download of Paint.NET and re-apply prefix setup
  -u, --uninstall         Remove Paint.NET, its Wine prefix, desktop entry, and runner
  -h, --help              Show this help message

Advanced options:
  --reinit-prefix         Re-run Wine prefix setup, DXVK, and d3dcompiler_47
  --force-deps            Force running the system package manager check
  --force-gpu <NAME>      Pin DXVK to a specific GPU name (e.g. NVIDIA, AMD, Intel)
  --no-avatar             Skip fetching/displaying the GitHub avatar banner
USAGE
}

set_theme_arg() {
    local val="${1,,}"
    if [ "$val" != "win" ] && [ "$val" != "gtk" ]; then
        echo "[-] Error: Invalid theme '$1'. Expected 'win' or 'gtk'."
        usage
        exit 1
    fi
    THEME_ARG="$val"
}

while [ $# -gt 0 ]; do
    case "$1" in
        -t|--theme|--theam)
            if [ -z "${2:-}" ]; then
                echo "[-] Error: $1 requires an argument ('win' or 'gtk')."
                exit 1
            fi
            set_theme_arg "$2"
            shift
            ;;
        --theme=*|--theam=*)
            set_theme_arg "${1#*=}"
            ;;
        -f|--force)
            FORCE_DOWNLOAD=true
            REINIT_PREFIX=true
            ;;
        -u|--uninstall)
            UNINSTALL=true
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        --reinit-prefix)
            REINIT_PREFIX=true
            ;;
        --force-deps)
            FORCE_DEPS=true
            ;;
        --force-gpu)
            if [ -z "${2:-}" ]; then
                echo "[-] Error: --force-gpu requires a GPU name (e.g. NVIDIA, AMD, Intel)."
                exit 1
            fi
            FORCE_GPU_FILTER="$2"
            shift
            ;;
        --force-gpu=*)
            FORCE_GPU_FILTER="${1#*=}"
            ;;
        --no-avatar)
            SHOW_AVATAR=false
            ;;
        *)
            echo "[-] Unknown option: $1"
            usage
            exit 1
            ;;
    esac
    shift
done

if [ "$EUID" -eq 0 ]; then
    echo "[-] Error: Do NOT run this script as root/sudo directly."
    echo "    Run it as your normal user; sudo will be requested only when needed."
    exit 1
fi

show_startup_banner() {
    [ "$SHOW_AVATAR" = true ] || return 0
    [ "$BANNER_SHOWN" = true ] && return 0

    local cache_dir="$HOME/.cache/paintnet-installer"
    local avatar_file="$cache_dir/github-avatar.png"
    local avatar_url="https://github.com/${GITHUB_USER}.png?size=128"

    mkdir -p "$cache_dir"
    if command -v curl >/dev/null 2>&1; then
        if [ ! -f "$avatar_file" ] || [ -n "$(find "$avatar_file" -mmin +1440 2>/dev/null || true)" ]; then
            curl -fsSL --max-time 3 -o "${avatar_file}.tmp" "$avatar_url" 2>/dev/null \
                && mv -f "${avatar_file}.tmp" "$avatar_file" \
                || rm -f "${avatar_file}.tmp"
        fi
    fi

    if [ -s "$avatar_file" ] && command -v chafa >/dev/null 2>&1; then
        echo ""
        chafa -s 24x12 "$avatar_file" 2>/dev/null || true
        echo "  Paint.NET-on-WINE Installer  •  github.com/${GITHUB_USER}"
        echo ""
        BANNER_SHOWN=true
    fi
}

do_uninstall() {
    echo "[*] Uninstalling Paint.NET-on-WINE..."
    if [ -d "$PDN_PREFIX" ] && command -v wineserver >/dev/null 2>&1; then
        WINEPREFIX="$PDN_PREFIX" wineserver -k >/dev/null 2>&1 || true
    fi
    rm -rf "$PDN_BASE_DIR"
    rm -f "$PDN_DESKTOP_FILE" "$PDN_ICON_PATH"
    if [ -f "$RUNNER_PATH" ]; then
        echo "[*] Removing $RUNNER_PATH (requires sudo)..."
        sudo rm -f "$RUNNER_PATH"
    fi
    if command -v update-desktop-database >/dev/null 2>&1; then
        update-desktop-database "$HOME/.local/share/applications" 2>/dev/null || true
    fi
    echo "[+] Paint.NET-on-WINE removed (your default ~/.wine was untouched)."
}

if [ "$UNINSTALL" = true ]; then
    show_startup_banner
    do_uninstall
    exit 0
fi

detect_distro_family() {
    if [ ! -r /etc/os-release ]; then
        echo "unknown"
        return
    fi
    # shellcheck disable=SC1091
    . /etc/os-release
    local id_all="${ID:-} ${ID_LIKE:-}"
    case " $id_all " in
        *" arch "*|*" cachyos "*|*" manjaro "*|*" endeavouros "*|*" garuda "*)
            echo "arch"
            ;;
        *" ubuntu "*|*" debian "*|*" linuxmint "*|*" pop "*|*" neon "*|*" zorin "*)
            echo "debian"
            ;;
        *" fedora "*|*" rhel "*|*" centos "*|*" rocky "*|*" almalinux "*|*" nobara "*)
            echo "fedora"
            ;;
        *" opensuse"*|*" suse "*)
            echo "opensuse"
            ;;
        *)
            echo "unknown"
            ;;
    esac
}

detect_gpus() {
    grep -ql "0x10de" /sys/bus/pci/devices/*/vendor 2>/dev/null && HAS_NVIDIA=true || true
    grep -ql "0x1002" /sys/bus/pci/devices/*/vendor 2>/dev/null && HAS_AMD=true || true
    grep -ql "0x8086" /sys/bus/pci/devices/*/vendor 2>/dev/null && HAS_INTEL=true || true

    local found=()
    [ "$HAS_NVIDIA" = true ] && found+=("NVIDIA")
    [ "$HAS_AMD" = true ] && found+=("AMD")
    [ "$HAS_INTEL" = true ] && found+=("Intel")

    if [ ${#found[@]} -gt 0 ]; then
        echo "[*] Detected GPU hardware: ${found[*]}"
    else
        echo "[*] No discrete/integrated PCI GPU vendor matched; software rendering will be used."
    fi
}

has_llvmpipe() {
    command -v vulkaninfo >/dev/null 2>&1 && vulkaninfo --summary 2>/dev/null | grep -qi "llvmpipe"
}

vulkan_has_pattern() {
    local pattern="$1"
    command -v vulkaninfo >/dev/null 2>&1 && vulkaninfo --summary 2>/dev/null | grep -qiE "$pattern"
}

arch_pkg_installed() {
    pacman -Qq "$1" >/dev/null 2>&1
}

all_core_deps_present() {
    local cmd
    for cmd in wine winetricks cabextract curl jq unzip vulkaninfo chafa; do
        command -v "$cmd" >/dev/null 2>&1 || return 1
    done
    has_llvmpipe || return 1
    return 0
}

install_winehq_apt() {
    # shellcheck disable=SC1091
    . /etc/os-release
    local repo_os="" codename=""

    if [[ " ${ID:-} ${ID_LIKE:-} " == *" ubuntu "* ]] || [ -n "${UBUNTU_CODENAME:-}" ]; then
        repo_os="ubuntu"
        codename="${UBUNTU_CODENAME:-${VERSION_CODENAME:-}}"
    elif [ "${ID:-}" = "debian" ] || [[ " ${ID_LIKE:-} " == *" debian "* ]]; then
        repo_os="debian"
        codename="${VERSION_CODENAME:-}"
    fi

    if [ -z "$repo_os" ] || [ -z "$codename" ]; then
        return 1
    fi

    local sources_url="https://dl.winehq.org/wine-builds/${repo_os}/dists/${codename}/winehq-${codename}.sources"
    if ! curl -fsSLI "$sources_url" >/dev/null 2>&1; then
        echo "[!] WineHQ repository source not found for ${repo_os}/${codename}."
        return 1
    fi

    echo "    -> Adding official WineHQ repository (${repo_os}/${codename}) for Wine >= ${MIN_WINE_MAJOR}.${MIN_WINE_MINOR}..."
    sudo mkdir -pm755 /etc/apt/keyrings
    curl -fsSL https://dl.winehq.org/wine-builds/winehq.key | sudo tee /etc/apt/keyrings/winehq-archive.key >/dev/null
    curl -fsSL "$sources_url" | sudo tee "/etc/apt/sources.list.d/winehq-${codename}.sources" >/dev/null
    sudo apt-get update
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y --install-recommends winehq-staging
    return 0
}

install_dependencies() {
    local family
    family=$(detect_distro_family)

    local need_gpu_pkg=false
    if [ "$family" = "arch" ]; then
        if [ "$HAS_NVIDIA" = true ] && ! vulkan_has_pattern "nvidia" && ! arch_pkg_installed nvidia-utils; then need_gpu_pkg=true; fi
        if [ "$HAS_AMD" = true ] && ! vulkan_has_pattern "amd|radv|radeon" && ! arch_pkg_installed vulkan-radeon; then need_gpu_pkg=true; fi
        if [ "$HAS_INTEL" = true ] && ! vulkan_has_pattern "intel" && ! arch_pkg_installed vulkan-intel; then need_gpu_pkg=true; fi
    fi

    if [ "$FORCE_DEPS" = false ] && [ "$need_gpu_pkg" = false ] && all_core_deps_present; then
        echo "[+] Step 1/6: Core dependencies, GPU Vulkan & llvmpipe already present (skipping package manager)."
        return
    fi

    echo "[*] Step 1/6: Installing system dependencies (distro family: $family)..."

    case "$family" in
        arch)
            local has_multilib=false
            pacman -Sl multilib >/dev/null 2>&1 && has_multilib=true

            local pkgs=(
                wine-staging wine-gecko wine-mono winetricks cabextract
                curl jq unzip icoutils chafa
                vulkan-icd-loader vulkan-swrast vulkan-tools
                gst-plugins-base gst-plugins-good
            )
            if [ "$has_multilib" = true ]; then
                pkgs+=(
                    lib32-vulkan-icd-loader lib32-vulkan-swrast
                    lib32-libpulse lib32-alsa-plugins lib32-gnutls
                    lib32-fontconfig lib32-freetype2
                )
            else
                echo "[!] Note: 'multilib' repo is disabled in /etc/pacman.conf; installing 64-bit packages only."
            fi

            if [ "$HAS_NVIDIA" = true ] && ! arch_pkg_installed nvidia-utils; then
                pkgs+=(nvidia-utils)
                [ "$has_multilib" = true ] && pkgs+=(lib32-nvidia-utils)
            fi
            if [ "$HAS_AMD" = true ] && ! arch_pkg_installed vulkan-radeon; then
                pkgs+=(vulkan-radeon)
                [ "$has_multilib" = true ] && pkgs+=(lib32-vulkan-radeon)
            fi
            if [ "$HAS_INTEL" = true ] && ! arch_pkg_installed vulkan-intel; then
                pkgs+=(vulkan-intel)
                [ "$has_multilib" = true ] && pkgs+=(lib32-vulkan-intel)
            fi

            sudo pacman -S --noconfirm --needed "${pkgs[@]}"
            ;;

        debian)
            sudo dpkg --add-architecture i386
            sudo apt-get update
            local pkgs=(
                winetricks cabextract curl jq unzip icoutils chafa
                libvulkan1 libvulkan1:i386
                mesa-vulkan-drivers mesa-vulkan-drivers:i386
                vulkan-tools
            )
            sudo DEBIAN_FRONTEND=noninteractive apt-get install -y "${pkgs[@]}"

            if ! command -v wine >/dev/null 2>&1; then
                if ! install_winehq_apt; then
                    echo "[!] Falling back to distro 'wine' package (may be older than ${MIN_WINE_MAJOR}.${MIN_WINE_MINOR})."
                    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y wine wine32:i386 || sudo DEBIAN_FRONTEND=noninteractive apt-get install -y wine
                fi
            fi
            ;;

        fedora)
            local pkgs=(
                winetricks cabextract curl jq unzip icoutils chafa
                mesa-vulkan-drivers vulkan-loader vulkan-tools
            )
            if ! command -v wine >/dev/null 2>&1; then
                pkgs+=(wine)
            fi
            sudo dnf install -y "${pkgs[@]}"
            sudo dnf install -y --skip-unavailable mesa-vulkan-drivers.i686 vulkan-loader.i686 2>/dev/null || true
            ;;

        opensuse)
            local pkgs=(
                winetricks cabextract curl jq unzip icoutils chafa
                libvulkan_lvp libvulkan1 vulkan-tools
            )
            [ "$HAS_AMD" = true ] && pkgs+=(libvulkan_radeon)
            [ "$HAS_INTEL" = true ] && pkgs+=(libvulkan_intel)
            if ! command -v wine >/dev/null 2>&1; then
                pkgs+=(wine)
            fi
            sudo zypper --non-interactive install --no-recommends "${pkgs[@]}"
            ;;

        *)
            echo "[!] Unsupported distro for automatic package installation."
            echo "    Install manually: wine (>= ${MIN_WINE_MAJOR}.${MIN_WINE_MINOR}), winetricks, cabextract, curl, jq, unzip, Vulkan + Mesa llvmpipe."
            local cmd
            for cmd in wine winetricks cabextract curl jq unzip; do
                if ! command -v "$cmd" >/dev/null 2>&1; then
                    echo "[-] Missing required command: $cmd"
                    exit 1
                fi
            done
            ;;
    esac
}

verify_environment() {
    local ver major minor
    ver=$(wine --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+' | head -n 1 || echo "0.0")
    major=${ver%%.*}
    minor=${ver#*.}

    if (( 10#$major < MIN_WINE_MAJOR || (10#$major == MIN_WINE_MAJOR && 10#$minor < MIN_WINE_MINOR) )); then
        echo "[!] WARNING: Paint.NET-on-WINE requires Wine >= ${MIN_WINE_MAJOR}.${MIN_WINE_MINOR} (detected: ${ver})."
        echo "    On Ubuntu/Debian, remove distro wine and install 'winehq-staging' from https://dl.winehq.org/"
    else
        echo "[+] Wine version OK: ${ver}"
    fi

    if command -v vulkaninfo >/dev/null 2>&1; then
        echo "[*] Visible Vulkan devices:"
        vulkaninfo --summary 2>/dev/null | grep -E "deviceName|driverName" | sed 's/^/    /' || true

        if ! has_llvmpipe; then
            echo "[!] WARNING: Mesa llvmpipe not detected (needed by Paint.NET-on-WINE for software rendering)."
        fi
        if [ "$HAS_NVIDIA" = true ] && ! vulkan_has_pattern "nvidia"; then
            echo "[!] WARNING: NVIDIA GPU present, but NVIDIA Vulkan driver was not detected."
            echo "    Ensure proprietary NVIDIA drivers (and 32-bit Vulkan libs) are installed."
        fi
    fi
}

enable_ntsync() {
    echo "[*] Step 2/6: Checking kernel NTSYNC..."
    if [ -c /dev/ntsync ]; then
        echo "[+] /dev/ntsync is active."
    else
        if sudo modprobe ntsync 2>/dev/null && [ -c /dev/ntsync ]; then
            echo "[+] Loaded kernel module: ntsync."
        else
            echo "[!] Kernel ntsync unavailable (will fall back to FSYNC/ESYNC)."
            return
        fi
    fi

    if [ -d /etc/modules-load.d ] && [ ! -f /etc/modules-load.d/ntsync.conf ]; then
        echo "ntsync" | sudo tee /etc/modules-load.d/ntsync.conf >/dev/null
        echo "    -> Enabled persistent ntsync in /etc/modules-load.d/ntsync.conf"
    fi
}

find_pdn_exe() {
    [ -d "$PDN_APP_DIR" ] || return 0
    find "$PDN_APP_DIR" -maxdepth 2 -iname "paintdotnet.exe" -print -quit
}

download_and_extract_pdn() {
    echo "[*] Step 3/6: Checking Paint.NET-on-WINE releases..."
    local release_json pdn_tag pdn_url installed_tag existing_exe

    release_json=$(curl -fsSL "$PDN_API_URL")
    pdn_tag=$(echo "$release_json" | jq -r '.[0].tag_name // empty')
    pdn_url=$(echo "$release_json" \
        | jq -r '.[0].assets[] | select((.name | test("portable"; "i")) and (.name | test("x64.*\\.zip$"; "i"))) | .browser_download_url' \
        | head -n 1)

    if [ -z "$pdn_tag" ] || [ -z "$pdn_url" ] || [ "$pdn_url" = "null" ]; then
        echo "[-] Failed to resolve latest x64 portable archive from GitHub API."
        exit 1
    fi

    installed_tag=""
    [ -f "$PDN_VERSION_FILE" ] && installed_tag=$(cat "$PDN_VERSION_FILE" 2>/dev/null || true)
    existing_exe=$(find_pdn_exe)

    if [ "$FORCE_DOWNLOAD" = false ] && [ "$installed_tag" = "$pdn_tag" ] && [ -n "$existing_exe" ]; then
        echo "[+] Already up-to-date ($pdn_tag). Skipping download."
        return
    fi

    echo "    -> Downloading $pdn_tag..."
    mkdir -p "$PDN_APP_DIR"
    local temp_zip
    temp_zip=$(mktemp --suffix=.zip)
    TEMP_PATHS+=("$temp_zip")

    curl -fL --progress-bar -o "$temp_zip" "$pdn_url"

    echo "    -> Extracting to $PDN_APP_DIR..."
    local rc=0
    unzip -q -o "$temp_zip" -d "$PDN_APP_DIR" || rc=$?
    if [ "$rc" -ne 0 ] && [ "$rc" -ne 1 ]; then
        echo "[-] Extraction failed with exit code $rc"
        exit "$rc"
    fi

    echo "$pdn_tag" > "$PDN_VERSION_FILE"
    echo "[+] Installed Paint.NET-on-WINE ($pdn_tag). Remember: experimental builds expire after 12 weeks."
}

apply_wine_dialog_theme() {
    local target_theme="$THEME_ARG"
    if [ -z "$target_theme" ]; then
        if [ -f "$PDN_THEME_MODE_FILE" ]; then
            target_theme=$(cat "$PDN_THEME_MODE_FILE" 2>/dev/null || echo "win")
        else
            target_theme="win"
        fi
    fi

    if [ "$target_theme" = "win" ]; then
        if [ -f "$PDN_THEME_MARKER" ] || [ -f "$PDN_LEGACY_THEME_MARKER" ]; then
            echo "[*] Applying 'win' theme (restoring default Windows/Wine styles)..."
            (
                export WINEPREFIX="$PDN_PREFIX"
                export WINEDEBUG="-all"
                export WINEDLLOVERRIDES="mscoree,mshtml="
                wine reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\ThemeManager" /v ThemeActive /t REG_SZ /d "1" /f </dev/null >/dev/null
            )
            rm -f "$PDN_THEME_MARKER" "$PDN_LEGACY_THEME_MARKER"
        fi
        echo "win" > "$PDN_THEME_MODE_FILE"
        return
    fi

    if [ -f "$PDN_THEME_MARKER" ] && [ "$REINIT_PREFIX" = false ]; then
        echo "[+] Theme 'gtk' (dark Wine dialogs, RGB 48 48 51) already applied."
        echo "gtk" > "$PDN_THEME_MODE_FILE"
        return
    fi

    echo "[*] Applying 'gtk' theme to Wine dialogs (dark palette, workspace RGB 48 48 51)..."
    local tmp_reg
    tmp_reg=$(mktemp --suffix=.reg)
    TEMP_PATHS+=("$tmp_reg")

    cat << 'REG' > "$tmp_reg"
Windows Registry Editor Version 5.00

[HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\ThemeManager]
"ThemeActive"="0"

[HKEY_CURRENT_USER\Control Panel\Colors]
"ActiveBorder"="48 48 51"
"ActiveTitle"="49 54 59"
"AppWorkSpace"="48 48 51"
"Background"="48 48 51"
"ButtonAlternateFace"="48 48 51"
"ButtonDkShadow"="20 22 25"
"ButtonFace"="49 54 59"
"ButtonHilight"="75 82 90"
"ButtonLight"="60 66 73"
"ButtonShadow"="29 32 36"
"ButtonText"="239 240 241"
"GradientActiveTitle"="49 54 59"
"GradientInactiveTitle"="48 48 51"
"GrayText"="130 138 146"
"Hilight"="61 174 233"
"HilightText"="255 255 255"
"HotTrackingColor"="61 174 233"
"InactiveBorder"="48 48 51"
"InactiveTitle"="48 48 51"
"InactiveTitleText"="160 166 172"
"InfoText"="239 240 241"
"InfoWindow"="43 47 51"
"Menu"="43 47 51"
"MenuBar"="49 54 59"
"MenuHilight"="61 174 233"
"MenuText"="239 240 241"
"Scrollbar"="48 48 51"
"TitleText"="239 240 241"
"Window"="43 47 51"
"WindowFrame"="29 32 36"
"WindowText"="239 240 241"
REG

    (
        export WINEPREFIX="$PDN_PREFIX"
        export WINEDEBUG="-all"
        export WINEDLLOVERRIDES="mscoree,mshtml="
        wine regedit /S "$tmp_reg" </dev/null >/dev/null
    )
    rm -f "$PDN_LEGACY_THEME_MARKER"
    touch "$PDN_THEME_MARKER"
    echo "gtk" > "$PDN_THEME_MODE_FILE"
}

configure_prefix() {
    if [ "$REINIT_PREFIX" = false ] && [ -f "$PDN_PREFIX/system.reg" ] && [ -f "$PDN_SETUP_MARKER" ]; then
        echo "[+] Step 4/6: Wine prefix already configured (skipping; pass --reinit-prefix to rebuild)."
        apply_wine_dialog_theme
        return
    fi

    echo "[*] Step 4/6: Configuring dedicated Wine prefix ($PDN_PREFIX)..."
    mkdir -p "$PDN_PREFIX"
    export WINEPREFIX="$PDN_PREFIX"
    wineserver -k >/dev/null 2>&1 || true

    WINEDLLOVERRIDES="mscoree,mshtml=" wineboot --init
    wineserver -w

    # Paint.NET 5.2+ requires Windows 11 mode
    winecfg -v win11

    # Enable ClearType, dark theme hint, and Paint.NET GPU acceleration
    wine reg add "HKCU\Control Panel\Desktop" /v FontSmoothing /t REG_SZ /d 2 /f >/dev/null
    wine reg add "HKCU\Control Panel\Desktop" /v FontSmoothingType /t REG_DWORD /d 2 /f >/dev/null
    wine reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize" /v AppsUseLightTheme /t REG_DWORD /d 0 /f >/dev/null
    wine reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize" /v SystemUsesLightTheme /t REG_DWORD /d 0 /f >/dev/null
    wine reg add "HKCU\Software\paint.net" /v "UI/EnableHardwareAcceleration" /t REG_SZ /d "True" /f >/dev/null
    wine reg add "HKCU\Software\paint.net" /v "UI/EnableAnimations" /t REG_SZ /d "False" /f >/dev/null

    echo "    -> Installing DXVK and d3dcompiler_47..."
    if command -v setup_dxvk >/dev/null 2>&1; then
        setup_dxvk install
    else
        winetricks -q dxvk
    fi
    winetricks -q d3dcompiler_47
    wineserver -w

    touch "$PDN_SETUP_MARKER"
    apply_wine_dialog_theme
    echo "[+] Wine prefix ready."
}

build_dxvk_config() {
    local tmp_dxvk
    tmp_dxvk=$(mktemp)
    TEMP_PATHS+=("$tmp_dxvk")

    if [ -f "$PDN_DXVK_ORIG" ]; then
        grep -vE '^\s*(dxgi\.syncInterval|dxvk\.enableGraphicsPipelineLibrary|dxvk\.numCompilerThreads|dxvk\.tearFree|d3d11\.relaxedBarriers|d3d11\.maxFrameLatency|dxvk\.deviceFilter)\s*=' "$PDN_DXVK_ORIG" > "$tmp_dxvk" || true
    fi

    cat << 'DXVK' >> "$tmp_dxvk"

# --- Universal GPU & Startup-Safe Latency Optimizations ---
dxvk.enableGraphicsPipelineLibrary = False
dxvk.numCompilerThreads = 0
dxgi.syncInterval = 0
dxvk.tearFree = False
d3d11.relaxedBarriers = True
DXVK

    if [ -n "$FORCE_GPU_FILTER" ]; then
        echo "dxvk.deviceFilter = \"$FORCE_GPU_FILTER\"" >> "$tmp_dxvk"
        echo "[*] Applied DXVK GPU filter: $FORCE_GPU_FILTER"
    fi

    if [ -f "$PDN_DXVK_FAST" ] && cmp -s "$tmp_dxvk" "$PDN_DXVK_FAST"; then
        echo "[+] $PDN_DXVK_FAST already up-to-date."
    else
        cp "$tmp_dxvk" "$PDN_DXVK_FAST"
        echo "[+] Generated $PDN_DXVK_FAST."
    fi
}

deploy_runner() {
    echo "[*] Step 5/6: Checking $RUNNER_PATH..."
    local tmp_runner
    tmp_runner=$(mktemp)
    TEMP_PATHS+=("$tmp_runner")

    cat << 'RUNNER' > "$tmp_runner"
#!/usr/bin/env bash
set -e

SHOW_HUD=false
FORCE_DGPU=false
PICK_FILE=false
STARTUP_WAKEUP=false

while [ $# -gt 0 ]; do
    case "$1" in
        --hud)
            SHOW_HUD=true
            shift
            ;;
        --dgpu)
            FORCE_DGPU=true
            shift
            ;;
        --pick)
            PICK_FILE=true
            shift
            ;;
        --wakeup)
            STARTUP_WAKEUP=true
            shift
            ;;
        *)
            break
            ;;
    esac
done

if [ -z "${1:-}" ]; then
    exec wine winecfg
fi

FILE_ARG="$1"
shift

export WINEPREFIX="${WINEPREFIX:-$HOME/.wine}"
export STAGING_SHARED_MEMORY=1

# Synchronization: NTSYNC -> FSYNC/ESYNC fallback
if [ -c /dev/ntsync ]; then
    export WINENTSYNC=1
else
    export WINEFSYNC=1
    export WINEESYNC=1
fi

# Persistent DXVK, NVIDIA, and Mesa (AMD/Intel) shader caches
mkdir -p "$HOME/.cache/dxvk" "$HOME/.cache/nvidia_gl" "$HOME/.cache/mesa_shader_cache"
export DXVK_STATE_CACHE=1
export DXVK_STATE_CACHE_PATH="$HOME/.cache/dxvk"

export __GL_SHADER_DISK_CACHE=1
export __GL_SHADER_DISK_CACHE_SKIP_CLEANUP=1
export __GL_SHADER_DISK_CACHE_PATH="$HOME/.cache/nvidia_gl"
export __GL_THREADED_OPTIMIZATIONS=1

export MESA_SHADER_CACHE_DISABLE=false
export MESA_SHADER_CACHE_MAX_SIZE=2G
export MESA_SHADER_CACHE_DIR="$HOME/.cache/mesa_shader_cache"

if [ "$FORCE_DGPU" = true ]; then
    export __NV_PRIME_RENDER_OFFLOAD=1
    export __VK_LAYER_NV_optimus=NVIDIA_only
    export __GLX_VENDOR_LIBRARY_NAME=nvidia
    export DRI_PRIME=1
fi

if [ "$SHOW_HUD" = true ]; then
    export DXVK_HUD="devinfo,fps,frametimes,gpuload"
fi

REAL_FILE="$(realpath "$FILE_ARG" 2>/dev/null || echo "$FILE_ARG")"
FILE_DIR="$(dirname "$REAL_FILE")"
FILE_NAME="$(basename "$REAL_FILE")"
EXTENSION="${FILE_NAME##*.}"
EXTENSION_LOWER="$(echo "$EXTENSION" | tr '[:upper:]' '[:lower:]')"

if [ -d "$FILE_DIR" ]; then
    cd "$FILE_DIR"
fi

if [[ "$FILE_NAME" =~ ^[Pp]aint[Dd]ot[Nn]et\.exe$ ]]; then
    CUSTOM_PDN_BASE="$HOME/.local/share/paintdotnet"
    CUSTOM_PDN_PREFIX="$CUSTOM_PDN_BASE/wineprefix"
    CUSTOM_PDN_APP="$CUSTOM_PDN_BASE/app"

    [ -d "$CUSTOM_PDN_PREFIX" ] && export WINEPREFIX="$CUSTOM_PDN_PREFIX"

    if [ -f "$CUSTOM_PDN_BASE/dxvk-fast.conf" ]; then
        export DXVK_CONFIG_FILE="$CUSTOM_PDN_BASE/dxvk-fast.conf"
    elif [ -f "$CUSTOM_PDN_APP/dxvk.conf" ]; then
        export DXVK_CONFIG_FILE="$CUSTOM_PDN_APP/dxvk.conf"
    fi

    export WINEDLLOVERRIDES="${WINEDLLOVERRIDES:-mshtml=;d3dcompiler_47=n}"
    export WINEDEBUG="${WINEDEBUG:--all}"
    export DOTNET_EnableDiagnostics=0

    # Keep wineserver warm for 5 min so subsequent launches are fast
    wineserver -p300 >/dev/null 2>&1 || true

    # Optional native Linux file picker before launch (--pick)
    if [ "$PICK_FILE" = true ]; then
        PICKED=""
        START_DIR="${HOME}/Pictures"
        [ -d "$START_DIR" ] || START_DIR="$HOME"
        if command -v kdialog >/dev/null 2>&1; then
            PICKED=$(kdialog --getopenfilename "$START_DIR" "Images (*.png *.jpg *.jpeg *.webp *.bmp *.gif *.tiff *.pdn)|All files (*)" 2>/dev/null || true)
        elif command -v zenity >/dev/null 2>&1; then
            PICKED=$(zenity --file-selection --title="Open Image in Paint.NET" --filename="$START_DIR/" --file-filter="Images | *.png *.jpg *.jpeg *.webp *.bmp *.gif *.tiff *.pdn" --file-filter="All files | *" 2>/dev/null || true)
        fi
        if [ -n "$PICKED" ]; then
            WIN_PICKED=$(winepath -w "$PICKED" 2>/dev/null || echo "$PICKED")
            set -- "$@" "$WIN_PICKED"
        fi
    fi

    # Optional ~30Hz WM_MOUSEMOVE startup redraw helper (requires xdotool)
    if [ "$STARTUP_WAKEUP" = true ] && command -v xdotool >/dev/null 2>&1; then
        (
            sleep 1.2
            for _ in $(seq 1 75); do
                xdotool mousemove_relative -- 1 0 2>/dev/null || break
                sleep 0.016
                xdotool mousemove_relative -- -1 0 2>/dev/null || break
                sleep 0.017
            done
        ) &
    fi
else
    export DXVK_ENABLE_NVAPI="${DXVK_ENABLE_NVAPI:-1}"
fi

if [ "$EXTENSION_LOWER" = "msi" ]; then
    RUN_CMD=(wine msiexec /i "$REAL_FILE" "$@")
else
    RUN_CMD=(wine "$REAL_FILE" "$@")
fi

if command -v gamemoderun >/dev/null 2>&1; then
    exec gamemoderun "${RUN_CMD[@]}"
else
    exec "${RUN_CMD[@]}"
fi
RUNNER

    if [ -f "$RUNNER_PATH" ] && cmp -s "$tmp_runner" "$RUNNER_PATH" && [ -x "$RUNNER_PATH" ]; then
        echo "[+] $RUNNER_PATH already up-to-date (skipping sudo)."
    else
        echo "    -> Installing/updating $RUNNER_PATH (requires sudo)..."
        sudo install -m 0755 "$tmp_runner" "$RUNNER_PATH"
    fi
}

install_icon() {
    local ico_file icon_value="applications-graphics"
    ico_file=$(find "$PDN_APP_DIR" -maxdepth 2 -iname "*.ico" -print -quit || true)

    if [ -n "$ico_file" ]; then
        mkdir -p "$(dirname "$PDN_ICON_PATH")"
        if command -v icotool >/dev/null 2>&1; then
            local tmp_dir best_png
            tmp_dir=$(mktemp -d)
            TEMP_PATHS+=("$tmp_dir")
            if icotool -x "$ico_file" -o "$tmp_dir" 2>/dev/null; then
                best_png=$(find "$tmp_dir" -maxdepth 1 -name '*.png' -printf '%s %p\n' 2>/dev/null | sort -nr | head -n 1 | cut -d' ' -f2- || true)
                if [ -n "$best_png" ] && [ -f "$best_png" ]; then
                    cp "$best_png" "$PDN_ICON_PATH"
                    icon_value="$PDN_ICON_PATH"
                fi
            fi
        elif command -v magick >/dev/null 2>&1; then
            if magick "${ico_file}[4]" "$PDN_ICON_PATH" 2>/dev/null || magick "$ico_file" -thumbnail 256x256 "$PDN_ICON_PATH" 2>/dev/null; then
                icon_value="$PDN_ICON_PATH"
            fi
        fi
    fi
    echo "$icon_value"
}

create_desktop_entry() {
    local pdn_exe="$1"
    echo "[*] Step 6/6: Creating/updating desktop entry..."
    local icon_val
    icon_val=$(install_icon)
    mkdir -p "$HOME/.local/share/applications"

    cat << DESKTOP > "$PDN_DESKTOP_FILE"
[Desktop Entry]
Name=Paint.NET
Comment=Image and photo editing software (Wine)
Exec=$RUNNER_PATH "$pdn_exe" %F
Icon=$icon_val
Terminal=false
Type=Application
Categories=Graphics;2DGraphics;RasterGraphics;
MimeType=image/png;image/jpeg;image/bmp;image/gif;image/webp;image/tiff;
StartupNotify=true
DESKTOP

    if command -v update-desktop-database >/dev/null 2>&1; then
        update-desktop-database "$HOME/.local/share/applications" 2>/dev/null || true
    fi
}

# --- Main flow ---
show_startup_banner
detect_gpus
install_dependencies
show_startup_banner
verify_environment
enable_ntsync
download_and_extract_pdn

PDN_EXE=$(find_pdn_exe)
if [ -z "$PDN_EXE" ]; then
    echo "[-] Error: Could not locate paintdotnet.exe inside $PDN_APP_DIR."
    exit 1
fi

configure_prefix
build_dxvk_config
deploy_runner
create_desktop_entry "$PDN_EXE"

echo "=============================================================================="
echo "[+] Paint.NET-on-WINE setup complete!"
echo "    - Executable:  $PDN_EXE"
echo "    - Prefix:      $PDN_PREFIX"
echo "    - DXVK config: $PDN_DXVK_FAST"
echo "    - Runner:      $RUNNER_PATH"
echo "    - Help:        $0 -h"
echo "=============================================================================="
