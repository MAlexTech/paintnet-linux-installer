<div align="center">

# Paint.NET-on-WINE Linux Installer

**Universal, idempotent installer, updater & GPU optimizer for running Paint.NET 5.2+ on Linux at 200+ FPS.**

[![Bash](https://img.shields.io/badge/Script-Bash-4EAA25?style=for-the-badge&logo=gnubash&logoColor=white)](install-paintnet.sh)
[![Linux](https://img.shields.io/badge/Linux-Arch%20%7C%20Ubuntu%20%7C%20Debian%20%7C%20Fedora%20%7C%20SUSE-FCC624?style=for-the-badge&logo=linux&logoColor=black)](#supported-systems--gpus)
[![Wine](https://img.shields.io/badge/Wine-11.21%2B-722F37?style=for-the-badge)](#quick-start)
[![GPU](https://img.shields.io/badge/GPU-NVIDIA%20%7C%20AMD%20%7C%20Intel-76B900?style=for-the-badge&logo=nvidia&logoColor=white)](#supported-systems--gpus)

Built upon [`paintdotnet/Paint.NET-on-WINE`](https://github.com/paintdotnet/Paint.NET-on-WINE) and [`bluesillybeard/Paint.NET-Wine-Patches`](https://github.com/bluesillybeard/Paint.NET-Wine-Patches).

</div>

---

## Why This Script?

Running Paint.NET on Linux normally suffers from Direct2D/WARP crashes, slow Wine cold boots, 60 FPS VSync locks, and broken hardware acceleration. This single script automates everything safely and **idempotently** — run it once to install, or re-run it anytime to update without breaking your prefix or plugins.

### Key Highlights
- **Unlocked Canvas Performance:** Uncaps DXVK frame pacing (`dxgi.syncInterval = 0`), enables persistent shader caches (DXVK, NVIDIA, Mesa), and enables kernel **NTSYNC** (`/dev/ntsync`) with automatic `FSYNC`/`ESYNC` fallback.
- **Zero Black-Frame Startup:** Uses synchronous first-frame pipeline compilation backed by `DXVK_STATE_CACHE=1`, forces `UI/EnableHardwareAcceleration = True`, and keeps `wineserver` warm (`wineserver -p300`).
- **Truly Idempotent:** Tracks installed release tags (`.installed_version`), prefix completion (`.pdn_setup_done`), theme choice (`.theme_mode`), installed packages, and compares runner checksums (`cmp -s`) before calling `sudo`.
- **Desktop & Terminal Polish:** Displays your cached GitHub avatar in the terminal via `chafa`, extracts the 256×256 icon, registers image MIME types, and installs a feature-rich `/usr/local/bin/wine-runner`.

---

## Quick Start

```bash
git clone https://github.com/MAlexTech/paintnet-linux-installer.git
cd paintnet-linux-installer
chmod +x install-paintnet.sh
./install-paintnet.sh
```

> [!TIP]
> Re-run `./install-paintnet.sh` anytime to check for newer `Paint.NET-on-WINE` releases. Subsequent runs skip already-completed steps and finish in ~1 second without asking for `sudo`.

> [!NOTE]
> Upstream `Paint.NET-on-WINE` experimental builds expire after **12 weeks** — running this script again updates only the app binaries while keeping your Wine prefix intact.

---

## Supported Systems & GPUs

### Linux Distributions
| Distribution Family | Package Manager | Notes |
| :--- | :--- | :--- |
| **Arch / Manjaro / CachyOS / EndeavourOS** | `pacman` | Installs `wine-staging`, auto-detects `multilib` for 32-bit libs |
| **Ubuntu / Linux Mint / Pop!\_OS / Debian** | `apt` | Enables `i386`, auto-adds official **WineHQ Staging** repo if Wine is missing (`>= 11.21`) |
| **Fedora / Nobara / RHEL-based** | `dnf` | Installs Wine, Mesa Vulkan drivers, and 32-bit loaders |
| **openSUSE** | `zypper` | Installs Wine, `libvulkan_lvp`, and vendor Vulkan ICDs |
| **Other distros** | Manual | Verifies required binaries (`wine`, `winetricks`, `cabextract`, `curl`, `jq`, `unzip`) |

### Graphics & Rendering
| GPU / Mode | Optimization Applied |
| :--- | :--- |
| **NVIDIA** | Checks/installs Vulkan ICD (`nvidia-utils` on Arch), enables `__GL_SHADER_DISK_CACHE` & threaded GL |
| **AMD (RADV)** | Checks/installs `vulkan-radeon` / `mesa-vulkan-drivers`, configures `MESA_SHADER_CACHE` |
| **Intel iGPU / Arc (ANV)** | Checks/installs `vulkan-intel` / `mesa-vulkan-drivers`, configures `MESA_SHADER_CACHE` |
| **Hybrid Laptops** | Supports `--dgpu` PRIME render offload flag in `wine-runner` |
| **Mesa `llvmpipe`** | Verified automatically (required by `Paint.NET-on-WINE` for software/WARP fallback) |

---

## CLI Reference

### Installer (`./install-paintnet.sh`)

| Flag | Description |
| :--- | :--- |
| `-t, --theme <win\|gtk>` | Switch Wine dialog theme: `win` *(default Windows/Wine style)* or `gtk` *(dark palette, workspace RGB `48 48 51`)* — remembered across updates |
| `-f, --force` | Force re-download of Paint.NET and re-apply Wine prefix configuration |
| `-u, --uninstall` | Remove Paint.NET, its isolated prefix, `.desktop` entry, and `/usr/local/bin/wine-runner` *(leaves `~/.wine` untouched)* |
| `-h, --help` | Show help message and all available flags |

<details>
<summary><b>Advanced Installer Flags</b></summary>

| Flag | Description |
| :--- | :--- |
| `--reinit-prefix` | Re-run Wine prefix initialization, DXVK, and `d3dcompiler_47` |
| `--force-deps` | Force running the system package manager dependency check |
| `--force-gpu <NAME>` | Pin `dxvk.deviceFilter` to a specific GPU name (e.g. `"NVIDIA"`, `"AMD"`, `"Intel"`) |
| `--no-avatar` | Skip fetching and rendering the GitHub terminal avatar banner |

</details>

### Launcher (`wine-runner`)

```bash
wine-runner ~/.local/share/paintdotnet/app/paintdotnet.exe
```

| Flag | Description |
| :--- | :--- |
| `--pick` | Open a native Linux file picker (`kdialog` / `zenity`) before launching Paint.NET |
| `--wakeup` | Trigger ~30 Hz startup redraws (`xdotool`) to avoid idle blank panels on startup |
| `--hud` | Enable DXVK HUD (`devinfo`, FPS, frametimes, GPU load) to verify active GPU |
| `--dgpu` | Force dedicated GPU via PRIME offload on hybrid graphics laptops |

---

<details>
<summary><b>Files & Paths Managed on Disk</b></summary>

- **App & isolated Wine prefix:** `~/.local/share/paintdotnet/` (`app/`, `wineprefix/`, `dxvk-fast.conf`)
- **Runner wrapper:** `/usr/local/bin/wine-runner`
- **Desktop entry & icon:** `~/.local/share/applications/paintdotnet.desktop`, `~/.local/share/icons/hicolor/256x256/apps/paintdotnet.png`
- **Shader & avatar caches:** `~/.cache/dxvk/`, `~/.cache/nvidia_gl/`, `~/.cache/mesa_shader_cache/`, `~/.cache/paintnet-installer/`
- **Kernel module persistence (if supported):** `/etc/modules-load.d/ntsync.conf`

</details>

## Credits
- [`paintdotnet/Paint.NET-on-WINE`](https://github.com/paintdotnet/Paint.NET-on-WINE) — Official experimental Wine-compatible Paint.NET builds
- [`bluesillybeard/Paint.NET-Wine-Patches`](https://github.com/bluesillybeard/Paint.NET-Wine-Patches) — Wine compatibility research and patches
