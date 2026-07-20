# Termux XFCE

<div align="center">

[한국어](README.md) &nbsp;|&nbsp; **[English](README.en.md)**

[![Android](https://img.shields.io/badge/Android-Termux-3DDC84?logo=android)](https://termux.dev)
[![Arch](https://img.shields.io/badge/Arch-aarch64-0070C0)](https://github.com/yanghoeg/Termux_XFCE)
[![License](https://img.shields.io/badge/License-MIT-yellow)](LICENSE)

</div>

---

Bash script that automatically installs **XFCE desktop environment** on Termux for Android.  
Derived from [phoenixbyrd/Termux_XFCE](https://github.com/phoenixbyrd/Termux_XFCE).

**Tested devices**: Galaxy Fold6 (Adreno 750, SD 8 Gen3), Galaxy Tab S9 Ultra (Adreno 740, SD 8 Gen2)

## Features

- **Termux native first** — XFCE, Firefox, GPU acceleration all installed as Termux native
- **Optional proot** — Ubuntu / Arch Linux / none
- **Hexagonal Architecture** — distro abstraction keeps Ubuntu & Arch code unified
- **Idempotent** — already installed items are skipped automatically
- **GPU acceleration** — Zink + Turnip auto-activated for Adreno 6xx/7xx/8xx
- **Termux API integration** — Android clipboard sync, battery monitor, brightness/volume control
- **zsh + Powerlevel10k** — set as default shell with autosuggestions & syntax-highlighting

## Installation

> **Just run `install.sh` — every option is asked interactively.**  
> The flags & env vars are only for non-interactive / scripted installs.

```bash
# one-liner (auto clones repo then runs — interactive)
curl -sL https://raw.githubusercontent.com/yanghoeg/Termux_XFCE/main/install.sh | bash
```

```bash
# non-interactive: with options
bash install.sh --distro ubuntu --user <username>
bash install.sh --distro archlinux --user <username>
bash install.sh --no-proot          # Termux native only
bash install.sh --distro archlinux --user <username> --proot-only  # add 2nd distro
```

```bash
# non-interactive: via environment variables
DISTRO=ubuntu USERNAME=<username> bash install.sh
```

| Option | Env var | Description |
|--------|---------|-------------|
| `--distro ubuntu\|archlinux` | `DISTRO=` | proot distro |
| `--user <name>` | `USERNAME=` | proot username |
| `--no-proot` | `SKIP_PROOT=true` | Termux native only |
| `--proot-only` | `PROOT_ONLY=true` | proot only (for adding a 2nd distro) |

> GPU acceleration, Korean input, and other optional components are managed via `app-installer` after installation.

## Usage

```bash
startXFCE          # Start XFCE desktop
ubuntu             # Enter Ubuntu proot
archlinux          # Enter Arch Linux proot
prun libreoffice   # Run proot app from Termux terminal
cp2menu            # Copy proot .desktop files to XFCE menu
app-installer      # GUI for installing/removing extra apps
```

## GPU Acceleration

Hardware acceleration via **Zink (OpenGL→Vulkan) + Turnip driver** on Adreno GPUs (Snapdragon 6xx/7xx/8xx).  
Applied automatically to every bash/zsh session after installation.

```bash
echo $MESA_LOADER_DRIVER_OVERRIDE   # → zink
gpu-info                             # Show GPU model
hud glxgears                         # FPS overlay
```

| Variable | Value | Role |
|----------|-------|------|
| `MESA_LOADER_DRIVER_OVERRIDE` | `zink` | Force OpenGL → Vulkan (Zink) |
| `TU_DEBUG` | `noconform` | Disable Turnip conformance checks |
| `ZINK_DESCRIPTORS` | `lazy` | Optimize descriptor updates |
| `MESA_NO_ERROR` | `1` | Disable GL error checks |
| `MESA_GL_VERSION_OVERRIDE` | `4.6COMPAT` | Advertise OpenGL 4.6 compat |
| `MESA_GLES_VERSION_OVERRIDE` | `3.2` | Advertise GLES 3.2 |
| `GSK_RENDERER` | `cairo` | GTK4 Cairo renderer (prevents GLX crash) |

> **Note**: If the XFCE4 compositor (xfwm4) causes a black screen,  
> go to Settings → Window Manager Tweaks → Compositor → uncheck "Enable display compositing"

## Termux API Integration

**Termux:API** package and APK are installed automatically. **Termux:Float** APK is also included.

### Auto-enabled

- **Clipboard sync** — Android↔X11 bidirectional clipboard sync daemon starts automatically with XFCE

### Available via App Installer

| Tool | Description |
|------|-------------|
| Conky Battery | Display battery level & temperature in Conky widget |
| Brightness Control | Screen brightness slider for XFCE panel |
| Volume Control | Media volume slider for XFCE panel |
| Notification | Send notifications to Android notification bar |
| TTS Speech | Text-to-speech via Android TTS engine |
| Speech Recognition | Speech-to-text via Android STT engine |
| Wallpaper Sync | Apply XFCE wallpaper to Android home screen |

## App Installer

Install/remove extra apps, system tools, and Termux API tools via a tabbed GUI:

```bash
app-installer          # Full UI (tabs: Apps | System | Termux API | Wine)
app-installer wine     # Wine apps only
```

- **Tabbed UI** — Apps / System / Termux API / Wine tabs
- **Search** — type to filter by name/description (yad notebook, zenity fallback)
- **Termux native first** — GIMP, Inkscape, Thunderbird install as native
- **proot auto-routing** — VLC, LibreOffice etc. install inside proot

Source: [yanghoeg/App-Installer](https://github.com/yanghoeg/App-Installer) (Git Submodule)

## Shell (zsh + Powerlevel10k)

The installer sets **zsh** as the default shell and configures Powerlevel10k automatically.

```bash
p10k configure        # Reconfigure p10k prompt

# Auto-installed aliases
ll          # eza -alhgF
ls          # eza -lF --icons
cat         # bat
gpu-info    # show Adreno GPU model
zink        # run app with Zink forced
hud         # run app with FPS overlay
```

## What Gets Installed

### Termux Native (always)

| Category | Packages |
|----------|----------|
| Base utils | wget, unzip, dbus, pulseaudio, yad, termux-api, xclip |
| XFCE | xfce4, xfce4-goodies, firefox, papirus-icon-theme, termux-x11-nightly |
| CLI | git, zsh, eza, bat, fzf, ripgrep, fd, zoxide, lazygit, git-delta, starship, atuin, zellij, htop, btop, procs, dust, duf, ncdu, yazi, glow, tealdeer, xh, onefetch, jq, neofetch |
| APKs | Termux:X11, Termux:API, Termux:Float |

### proot (optional)

| distro | base | entry command |
|--------|------|---------------|
| ubuntu | Ubuntu (proot-distro) | `ubuntu` |
| archlinux | Arch Linux (proot-distro) | `archlinux` |

## Tests

```bash
bash tests/run_tests.sh              # all 343+ tests
bash tests/run_tests.sh domain_termux
bash tests/run_tests.sh e2e_install
```

## Android System Optimization

### Disable Phantom Process Killer (Android 12+)

```bash
adb shell "/system/bin/device_config put activity_manager max_phantom_processes 2147483647"
```

### Disable Battery Optimization

**Android Settings → Apps → Termux** (and Termux:X11) → Battery → **Unrestricted**.

---

## Known Issues

### Termux:X11 — Right-click / Arrow Keys Broken After Switching Apps

Android stops sending key-release events when an app loses focus, causing Alt key to get stuck. ([#781](https://github.com/termux/termux-x11/issues/781))

**Workarounds**: Press Alt once, Super+I to reset input, or use swipe gesture instead of Alt+Tab.

> Samsung DeX: Termux:X11 → Preferences → Keyboard → "Intercept system shortcuts".

---

## Project Structure

```
Termux_XFCE/
├── install.sh                    ← entry point + DI container
├── ports/                        ← contract definitions (interfaces)
├── adapters/
│   ├── input/                    ← CLI args / interactive prompts
│   └── output/                   ← pkg adapters, UI, script builders
├── domain/
│   ├── packages.sh               ← package list definitions
│   ├── termux_env.sh             ← Termux environment (API APKs, clipboard sync)
│   ├── xfce_env.sh               ← XFCE setup
│   ├── proot_env.sh              ← proot logic (Ubuntu/Arch common)
│   └── locale_ko.sh              ← Korean locale (LD_PRELOAD gettext hook)
├── tests/                        ← 343+ automated tests
└── app-installer/                ← extra app GUI (Git Submodule)
    ├── install.sh                ← yad notebook tabbed GUI
    └── domain/installers/        ← per-app install scripts (31 apps)
```

## Contributing

Bug reports and PRs are welcome via GitHub Issues / Pull Requests.
