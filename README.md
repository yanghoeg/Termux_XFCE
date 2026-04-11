# Termux XFCE

<div align="center">

**[한국어](#한국어) · [English](#english)**

[![Android](https://img.shields.io/badge/Android-Termux-3DDC84?logo=android)](https://termux.dev)
[![Arch](https://img.shields.io/badge/Arch-aarch64-0070C0)](https://github.com/yanghoeg/Termux_XFCE)
[![License](https://img.shields.io/badge/License-MIT-yellow)](LICENSE)

</div>

---

## 한국어

Android 기기의 Termux에서 **XFCE 데스크탑 환경**을 자동 설치하는 Bash 스크립트입니다.  
[phoenixbyrd/Termux_XFCE](https://github.com/phoenixbyrd/Termux_XFCE) 에서 파생되었습니다.

**테스트 기기**: Galaxy Fold6 (Adreno 750, SD 8 Gen3), Galaxy Tab S9 Ultra (Adreno 740, SD 8 Gen2)

### 특징

- **Termux native 우선** — XFCE, Firefox, fcitx5-hangul, GPU 가속 모두 Termux 네이티브 설치
- **proot 선택 가능** — Ubuntu / Arch Linux / 없음
- **헥사고날 아키텍처** — distro 추상화로 Ubuntu·Arch 공통 코드 유지
- **멱등성** — 이미 설치된 항목은 자동으로 건너뜀
- **GPU 가속** — Adreno 6xx/7xx/8xx에서 Zink + Turnip 자동 활성화

### 설치

```bash
# one-liner (자동 clone 후 실행)
curl -sL https://raw.githubusercontent.com/yanghoeg/Termux_XFCE/main/install.sh | bash
```

```bash
# 옵션 지정
bash install.sh --distro ubuntu --user yanghoeg --gpu
bash install.sh --distro archlinux --user yanghoeg
bash install.sh --no-proot          # Termux native만
bash install.sh --distro ubuntu --user yanghoeg --gpu --gpu-dev
```

```bash
# 환경변수로 지정
DISTRO=ubuntu USERNAME=yanghoeg INSTALL_GPU=true bash install.sh
```

| 옵션 | 환경변수 | 설명 |
|------|----------|------|
| `--distro ubuntu\|archlinux` | `DISTRO=` | proot distro 선택 |
| `--user <이름>` | `USERNAME=` | proot 사용자 이름 |
| `--no-proot` | `SKIP_PROOT=true` | proot 없이 native만 |
| `--gpu` | `INSTALL_GPU=true` | GPU 가속 패키지 설치 |
| `--gpu-dev` | `INSTALL_GPU_DEV=true` | GPU 개발 도구 설치 |

### 사용법

```bash
startXFCE          # XFCE 데스크탑 시작
ubuntu             # Ubuntu proot 진입
archlinux          # Arch Linux proot 진입
prun code          # proot 앱을 Termux에서 직접 실행
cp2menu            # proot .desktop 파일을 XFCE 메뉴에 복사
app-installer      # 앱 추가 설치/제거 GUI
```

### GPU 가속

Adreno GPU(Snapdragon 6xx/7xx/8xx)에서 **Zink(OpenGL→Vulkan) + Turnip** 드라이버로 하드웨어 가속이 동작합니다.  
설치 후 모든 터미널 세션에서 자동 적용됩니다.

```bash
# 터미널에서 Zink 환경 확인
echo $MESA_LOADER_DRIVER_OVERRIDE   # → zink

# GPU 모델 확인
gpu-info

# FPS HUD 오버레이
hud glxgears

# Zink 명시 지정 (상시 Zink와 동일, 덮어쓰기용)
zink glxgears
```

| 변수 | 값 | 역할 |
|------|----|------|
| `MESA_LOADER_DRIVER_OVERRIDE` | `zink` | OpenGL → Vulkan(Zink) 강제 |
| `TU_DEBUG` | `noconform` | Turnip conformance 체크 비활성 |
| `ZINK_DESCRIPTORS` | `lazy` | 디스크립터 업데이트 최적화 |
| `MESA_NO_ERROR` | `1` | GL 에러 체크 비활성 |
| `GALLIUM_HUD` | `fps` | FPS 오버레이 (`hud` 별칭) |

> **주의**: XFCE4 컴포지터(xfwm4)가 검은 화면을 유발할 경우  
> 설정 → 창관리자(작업) → 컴포지터 → '화면 컴포지팅 활성화' 해제

### 설치 구성

#### Termux Native (항상 설치)

| 분류 | 패키지 |
|------|--------|
| 기본 유틸 | wget, unzip, dbus, pulseaudio |
| XFCE | xfce4, xfce4-goodies, firefox, papirus-icon-theme, termux-x11-nightly |
| CLI | git, eza, bat, jq, neofetch |
| 한글 입력 | fcitx5, fcitx5-hangul, fcitx5-configtool |
| GPU (옵션) | mesa-zink, osmesa-zink, mesa-vulkan-icd-freedreno, vulkan-loader-generic |

#### proot (선택)

| distro | 기반 | 진입 명령 |
|--------|------|-----------|
| ubuntu | Ubuntu (proot-distro) | `ubuntu` |
| archlinux | Arch Linux (proot-distro) | `archlinux` |

### 테스트

```bash
bash tests/run_tests.sh              # 전체 (122개)
bash tests/run_tests.sh domain_termux
bash tests/run_tests.sh app_installer
```

| 스위트 | 수 | 내용 |
|--------|---|------|
| ports | 7 | 어댑터 계약 준수 |
| adapters | 12 | pkg_termux, ui_terminal |
| domain_termux | 25 | termux_env 로직 |
| domain_xfce | 19 | xfce_env 로직 |
| domain_proot | 25 | proot_env 로직 |
| app_installer | 34 | 설치 스크립트 검증 |
| **합계** | **122** | **실기기 전체 통과** |

### Signal 9 오류 해결

Termux 강제 종료 시 ADB로 phantom process 제한 해제:

```bash
adb shell "/system/bin/device_config put activity_manager max_phantom_processes 2147483647"
```

[LADB](https://github.com/hyperio546/ladb-builds/releases) 또는 Termux에서 직접 ADB 연결 후 실행.

---

## English

Bash script that automatically installs **XFCE desktop environment** on Termux for Android.  
Derived from [phoenixbyrd/Termux_XFCE](https://github.com/phoenixbyrd/Termux_XFCE).

**Tested devices**: Galaxy Fold6 (Adreno 750, SD 8 Gen3), Galaxy Tab S9 Ultra (Adreno 740, SD 8 Gen2)

### Features

- **Termux native first** — XFCE, Firefox, fcitx5-hangul, GPU acceleration all installed as Termux native
- **Optional proot** — Ubuntu / Arch Linux / none
- **Hexagonal Architecture** — distro abstraction keeps Ubuntu & Arch code unified
- **Idempotent** — already installed items are skipped automatically
- **GPU acceleration** — Zink + Turnip auto-activated for Adreno 6xx/7xx/8xx

### Installation

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

### Usage

```bash
startXFCE          # Start XFCE desktop
ubuntu             # Enter Ubuntu proot
archlinux          # Enter Arch Linux proot
prun code          # Run proot app from Termux terminal
cp2menu            # Copy proot .desktop files to XFCE menu
app-installer      # GUI for installing/removing extra apps
```

### GPU Acceleration

Hardware acceleration via **Zink (OpenGL→Vulkan) + Turnip driver** on Adreno GPUs (Snapdragon 6xx/7xx/8xx).  
Applied automatically to every terminal session after installation.

```bash
# Verify Zink is active
echo $MESA_LOADER_DRIVER_OVERRIDE   # → zink

# Show GPU model
gpu-info

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
| `GALLIUM_HUD` | `fps` | FPS overlay (`hud` alias) |

> **Note**: If the XFCE4 compositor (xfwm4) causes a black screen,  
> go to Settings → Window Manager Tweaks → Compositor → uncheck "Enable display compositing"

### What Gets Installed

#### Termux Native (always)

| Category | Packages |
|----------|----------|
| Base utils | wget, unzip, dbus, pulseaudio |
| XFCE | xfce4, xfce4-goodies, firefox, papirus-icon-theme, termux-x11-nightly |
| CLI | git, eza, bat, jq, neofetch |
| Korean IME | fcitx5, fcitx5-hangul, fcitx5-configtool |
| GPU (optional) | mesa-zink, osmesa-zink, mesa-vulkan-icd-freedreno, vulkan-loader-generic |

#### proot (optional)

| distro | base | entry command |
|--------|------|---------------|
| ubuntu | Ubuntu (proot-distro) | `ubuntu` |
| archlinux | Arch Linux (proot-distro) | `archlinux` |

### Tests

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

### Fix Signal 9 Crashes

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
