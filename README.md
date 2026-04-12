# Termux XFCE

<div align="center">

**[English](README.md)** &nbsp;|&nbsp; [한국어](README.ko.md)

[![Android](https://img.shields.io/badge/Android-Termux-3DDC84?logo=android)](https://termux.dev)
[![Arch](https://img.shields.io/badge/Arch-aarch64-0070C0)](https://github.com/yanghoeg/Termux_XFCE)
[![License](https://img.shields.io/badge/License-MIT-yellow)](LICENSE)

</div>

---

Bash script that automatically installs **XFCE desktop environment** on Termux for Android.  
Derived from [phoenixbyrd/Termux_XFCE](https://github.com/phoenixbyrd/Termux_XFCE).

**Tested devices**: Galaxy Fold6 (Adreno 750, SD 8 Gen3), Galaxy Tab S9 Ultra (Adreno 740, SD 8 Gen2)

## Features

- **Termux native first** — XFCE, Firefox, fcitx5-hangul, GPU acceleration all installed as Termux native
- **Optional proot** — Ubuntu / Arch Linux / none
- **Hexagonal Architecture** — distro abstraction keeps Ubuntu & Arch code unified
- **Idempotent** — already installed items are skipped automatically
- **GPU acceleration** — Zink + Turnip auto-activated for Adreno 6xx/7xx/8xx
- **zsh + Powerlevel10k** — set as default shell with autosuggestions & syntax-highlighting

## Installation

```bash
# one-liner (auto clones repo then runs)
curl -sL https://raw.githubusercontent.com/yanghoeg/Termux_XFCE/main/install.sh | bash
```

```bash
# with options
bash install.sh --distro ubuntu --user yanghoeg --gpu
bash install.sh --distro archlinux --user yanghoeg
bash install.sh --no-proot          # Termux native only
bash install.sh --distro ubuntu --user yanghoeg --gpu --gpu-dev
```

```bash
# via environment variables
DISTRO=ubuntu USERNAME=yanghoeg INSTALL_GPU=true bash install.sh
```

| Option | Env var | Description |
|--------|---------|-------------|
| `--distro ubuntu\|archlinux` | `DISTRO=` | proot distro |
| `--user <name>` | `USERNAME=` | proot username |
| `--no-proot` | `SKIP_PROOT=true` | Termux native only |
| `--gpu` | `INSTALL_GPU=true` | Install GPU acceleration |
| `--gpu-dev` | `INSTALL_GPU_DEV=true` | Install GPU dev tools |

## Usage

```bash
startXFCE          # Start XFCE desktop
ubuntu             # Enter Ubuntu proot
archlinux          # Enter Arch Linux proot
prun code          # Run proot app from Termux terminal
cp2menu            # Copy proot .desktop files to XFCE menu
app-installer      # GUI for installing/removing extra apps
```

## GPU Acceleration

Hardware acceleration via **Zink (OpenGL→Vulkan) + Turnip driver** on Adreno GPUs (Snapdragon 6xx/7xx/8xx).  
Applied automatically to every bash/zsh session after installation.

> **Why Zink, not glamor?**  
> `glamor_egl` (X11 OpenGL acceleration) requires a DRI3-capable driver, but Termux:X11 Xwayland does not expose DRI3 for Adreno.  
> Zink routes OpenGL calls through Vulkan (Turnip), which **does** work via `/dev/kgsl-3d0` — the only path to hardware acceleration on Adreno today.

> **GTK4 apps crashing? (zenity, etc.)**  
> Zink + Turnip fails to create a GLX swap chain with Termux:X11 nightly APK → `GLXBadCurrentWindow`.  
> Fixed by `GSK_RENDERER=cairo` (Cairo software renderer for GTK4). Already set automatically.  
> Use `glmark2-es2` (EGL) instead of `glmark2` (GLX).

```bash
# Verify Zink is active
echo $MESA_LOADER_DRIVER_OVERRIDE   # → zink

# Show GPU model
gpu-info
# or directly:
cat /sys/class/kgsl/kgsl-3d0/gpu_model

# FPS overlay
hud glxgears

# Explicit Zink (same as always-on, useful for overrides)
zink glxgears
```

| Variable | Value | Role |
|----------|-------|------|
| `MESA_LOADER_DRIVER_OVERRIDE` | `zink` | Force OpenGL → Vulkan (Zink) |
| `TU_DEBUG` | `noconform` | Disable Turnip conformance checks |
| `ZINK_DESCRIPTORS` | `lazy` | Optimize descriptor updates |
| `MESA_NO_ERROR` | `1` | Disable GL error checks |
| `MESA_GL_VERSION_OVERRIDE` | `4.6COMPAT` | Advertise OpenGL 4.6 compat |
| `MESA_GLES_VERSION_OVERRIDE` | `3.2` | Advertise GLES 3.2 |
| `MESA_VK_WSI_PRESENT_MODE` | `immediate` | Disable Vulkan VSync (lower latency) |
| `GSK_RENDERER` | `cairo` | GTK4 Cairo renderer (prevents GLX crash) |
| `GALLIUM_HUD` | `fps` | FPS overlay (`hud` alias) |

> **Note**: If the XFCE4 compositor (xfwm4) causes a black screen,  
> go to Settings → Window Manager Tweaks → Compositor → uncheck "Enable display compositing"

## Shell (zsh + Powerlevel10k)

The installer sets **zsh** as the default shell and configures Powerlevel10k automatically.

```bash
# Reconfigure p10k prompt
p10k configure

# Aliases installed automatically
ll          # eza -alhgF
ls          # eza -lF --icons
cat         # bat
gpu-info    # show Adreno GPU model
zink        # run app with Zink forced
hud         # run app with FPS overlay
zrunhud     # proot app + FPS + GPU
shutdown    # kill -9 -1 (terminate all Termux processes)
```

## What Gets Installed

### Termux Native (always)

| Category | Packages |
|----------|----------|
| Base utils | wget, unzip, dbus, pulseaudio |
| XFCE | xfce4, xfce4-goodies, firefox, papirus-icon-theme, termux-x11-nightly |
| CLI | git, zsh, eza, bat, jq, neofetch |
| Korean IME | fcitx5, fcitx5-hangul, fcitx5-configtool |
| GPU (optional) | mesa, mesa-vulkan-icd-freedreno, vulkan-loader-generic, mesa-vulkan-icd-swrast |

### proot (optional)

| distro | base | entry command |
|--------|------|---------------|
| ubuntu | Ubuntu (proot-distro) | `ubuntu` |
| archlinux | Arch Linux (proot-distro) | `archlinux` |

## App Installer

Extra apps (VLC, LibreOffice, Thunderbird, etc.) can be installed via the GUI:

```bash
app-installer
```

Source: [yanghoeg/App-Installer](https://github.com/yanghoeg/App-Installer) (Git Submodule)

## Tests

```bash
bash tests/run_tests.sh              # all 122 tests
bash tests/run_tests.sh domain_termux
bash tests/run_tests.sh app_installer
```

| Suite | Count | Coverage |
|-------|-------|----------|
| ports | 7 | adapter contract compliance |
| adapters | 12 | pkg_termux, ui_terminal |
| domain_termux | 25 | termux_env logic |
| domain_xfce | 19 | xfce_env logic |
| domain_proot | 25 | proot_env logic |
| app_installer | 34 | installer script validation |
| **Total** | **122** | **All pass on real device** |

## Fix Signal 9 Crashes

If Termux is force-killed, disable phantom process limit via ADB:

```bash
adb shell "/system/bin/device_config put activity_manager max_phantom_processes 2147483647"
```

Run via [LADB](https://github.com/hyperio546/ladb-builds/releases) or a direct ADB connection in Termux.

---

## Project Structure

```
Termux_XFCE/
├── install.sh                    ← entry point + DI container
├── ports/
│   ├── pkg_manager.sh            ← package manager contract
│   └── ui.sh                     ← UI contract
├── adapters/
│   ├── input/
│   │   ├── cli.sh                ← CLI arg / env var parsing
│   │   └── interactive.sh        ← interactive prompts
│   └── output/
│       ├── pkg_termux.sh         ← Termux pkg adapter
│       ├── pkg_ubuntu.sh         ← Ubuntu apt adapter
│       ├── pkg_arch.sh           ← Arch pacman adapter
│       ├── ui_terminal.sh        ← echo-based UI
│       └── ui_zenity.sh          ← zenity GUI UI
├── domain/
│   ├── packages.sh               ← package list definitions
│   ├── termux_env.sh             ← Termux environment logic
│   ├── xfce_env.sh               ← XFCE setup logic
│   └── proot_env.sh              ← proot logic (Ubuntu/Arch common)
├── tests/                        ← 122 automated tests
└── app-installer/                ← extra app GUI (Git Submodule)
```

## Branch Strategy

| Branch | Purpose |
|--------|---------|
| `main` | Stable — real-device tested, for end users |
| `dev` | Development — merged to main after tests pass |

## Contributing

Bug reports and PRs are welcome via GitHub Issues / Pull Requests.
