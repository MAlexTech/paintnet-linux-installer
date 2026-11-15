# Paint.NET-on-WINE Linux Installer

Universal, **idempotent** installation, update, and GPU optimization script for running **Paint.NET 5.2+ (`Paint.NET-on-WINE`)** on Linux — with unlocked 200+ FPS canvas performance, multi-distro support, and automatic multi-GPU tuning.

Built upon [`paintdotnet/Paint.NET-on-WINE`](https://github.com/paintdotnet/Paint.NET-on-WINE) and [`bluesillybeard/Paint.NET-Wine-Patches`](https://github.com/bluesillybeard/Paint.NET-Wine-Patches).

## Features

- **Multi-distro support:**
  - **Arch Linux / Manjaro / CachyOS / EndeavourOS** (`pacman`, automatic `multilib` detection)
  - **Ubuntu / Linux Mint / Pop!_OS / Debian** (`apt` + `i386` multiarch; automatically configures the official **WineHQ Staging** repository if Wine is missing to meet the `>= 11.21` requirement)
  - **Fedora** (`dnf`) & **openSUSE** (`zypper`), plus a generic fallback check for other distros
- **Multi-GPU & hybrid laptop ready:**
  - Automatically detects **NVIDIA**, **AMD (RADV)**, and **Intel iGPU/Arc (ANV)** hardware alongside **Mesa `llvmpipe`** (required by Paint.NET-on-WINE for software rendering tasks)
  - Configures persistent shader caches for DXVK (`DXVK_STATE_CACHE`), NVIDIA (`__GL_SHADER_DISK_CACHE`), and Mesa (`MESA_SHADER_CACHE`)
  - Includes a `--dgpu` PRIME offload flag in `wine-runner` for hybrid graphics laptops
- **Performance & startup tuning:**
  - Enables kernel **NTSYNC** (`/dev/ntsync`, persisted via `/etc/modules-load.d/ntsync.conf`) with `FSYNC`/`ESYNC` fallback and `STAGING_SHARED_MEMORY=1`
  - Generates `dxvk-fast.conf` (`dxgi.syncInterval = 0`, `tearFree = False`, synchronous first-frame pipeline compilation with persistent state cache to avoid black startup frames)
  - Forces `UI/EnableHardwareAcceleration = True` in the dedicated Windows 11 Wine prefix and keeps `wineserver` warm (`wineserver -p300`) for fast subsequent launches
- **Fully idempotent:**
  - Safe to run repeatedly — tracks release tags (`.installed_version`), prefix state (`.pdn_setup_done`), remembered theme choice (`.theme_mode`), installed packages, and uses `cmp -s` before touching `/usr/local/bin/wine-runner`
- **Desktop & terminal integration:**
  - Displays cached GitHub profile avatar in the terminal via `chafa` on startup
  - Extracts the 256×256 Paint.NET icon, registers a `.desktop` entry with image MIME associations, and deploys `/usr/local/bin/wine-runner`

## Quick Start

```bash
git clone https://github.com/MAlexTech/paintnet-linux-installer.git
cd paintnet-linux-installer
chmod +x install-paintnet.sh
./install-paintnet.sh
```

Re-run `./install-paintnet.sh` anytime to check for and install newer `Paint.NET-on-WINE` builds *(note: upstream experimental builds expire after 12 weeks)*.

## Options

### Installer (`install-paintnet.sh`)
- `-t, --theme <win|gtk>` — Switch Wine dialog theme between `win` *(default Windows/Wine style)* and `gtk` *(dark Linux-matched palette, workspace RGB `48 48 51`)*; remembered across updates
- `-f, --force` — Force re-download of Paint.NET and re-apply Wine prefix setup
- `-u, --uninstall` — Cleanly remove Paint.NET, its isolated prefix, `.desktop` entry, and `/usr/local/bin/wine-runner` *(leaves `~/.wine` untouched)*
- `-h, --help` — Show help message (including advanced flags: `--reinit-prefix`, `--force-deps`, `--force-gpu <NAME>`, `--no-avatar`)

### Launcher (`wine-runner`)
- `wine-runner ~/.local/share/paintdotnet/app/paintdotnet.exe` — Normal launch
- `wine-runner --pick ~/.local/share/paintdotnet/app/paintdotnet.exe` — Pick an image via native Linux dialog (`kdialog` / `zenity`) before launching
- `wine-runner --wakeup ~/.local/share/paintdotnet/app/paintdotnet.exe` — Trigger ~30 Hz startup redraws (`xdotool`)
- `wine-runner --hud ~/.local/share/paintdotnet/app/paintdotnet.exe` — Show DXVK HUD (`devinfo`, FPS, frametimes, GPU load)
- `wine-runner --dgpu ~/.local/share/paintdotnet/app/paintdotnet.exe` — Force dedicated GPU via PRIME offload on hybrid laptops

## Credits
- [`paintdotnet/Paint.NET-on-WINE`](https://github.com/paintdotnet/Paint.NET-on-WINE) — Official experimental Wine-compatible Paint.NET builds
- [`bluesillybeard/Paint.NET-Wine-Patches`](https://github.com/bluesillybeard/Paint.NET-Wine-Patches) — Wine compatibility research
