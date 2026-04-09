# Termux XFCE

Android 기기(Termux)에서 XFCE 데스크탑 환경을 자동 설치하는 스크립트입니다.
[phoenixbyrd/Termux_XFCE](https://github.com/phoenixbyrd/Termux_XFCE) 에서 파생되었습니다.

**테스트 기기**: Galaxy Fold6 (SD 8 Gen3), Galaxy Tab S9 Ultra (SD 8 Gen2)

---

## 특징

- **Termux native 우선**: XFCE, Firefox, fcitx5-hangul, GPU 가속 모두 Termux 네이티브로 설치
- **proot 선택 가능**: Ubuntu / Arch Linux / 없음
- **헥사고날 아키텍처(Ports & Adapters)**: distro 추상화로 Ubuntu·Arch 공통 코드 유지
- **멱등성**: 이미 설치된 항목은 자동으로 건너뜀

---

## 설치

### 기본 (curl one-liner)

```bash
curl -sL https://raw.githubusercontent.com/yanghoeg/Termux_XFCE/main/install.sh | bash
```

`domain/` 디렉토리가 없으면 자동으로 전체 저장소를 clone 후 실행합니다.

### 옵션 지정

```bash
# Ubuntu proot + GPU 가속
bash install.sh --distro ubuntu --user lideok --gpu

# Arch Linux proot
bash install.sh --distro archlinux --user lideok

# Termux native only (proot 없음)
bash install.sh --no-proot

# GPU 개발 도구 포함
bash install.sh --distro ubuntu --user lideok --gpu --gpu-dev
```

### 환경변수로 지정

```bash
DISTRO=ubuntu USERNAME=lideok INSTALL_GPU=true bash install.sh
```

### 전체 옵션

| 옵션 | 환경변수 | 설명 |
|------|----------|------|
| `--distro ubuntu\|archlinux` | `DISTRO=` | proot distro 선택 |
| `--user <이름>` | `USERNAME=` | proot 사용자 이름 |
| `--no-proot` | `SKIP_PROOT=true` | proot 없이 Termux native만 설치 |
| `--gpu` | `INSTALL_GPU=true` | GPU 가속 패키지 설치 |
| `--gpu-dev` | `INSTALL_GPU_DEV=true` | GPU 개발 도구 설치 |

---

## 사용법

```bash
# XFCE 데스크탑 시작
startXFCE

# proot 진입
ubuntu        # Ubuntu proot
archlinux     # Arch Linux proot

# proot 앱을 Termux 터미널에서 직접 실행
prun code
prun libreoffice

# proot .desktop 파일을 XFCE 메뉴에 복사
cp2menu

# 앱 추가 설치/제거 GUI
app-installer
```

---

## 설치 구성

### Termux Native (항상 설치)

| 분류 | 패키지 |
|------|--------|
| 기본 유틸 | wget, unzip, dbus, pulseaudio |
| XFCE | xfce4, xfce4-goodies, firefox, papirus-icon-theme, termux-x11-nightly |
| CLI | git, eza, bat, jq, neofetch |
| 한글 입력 | fcitx5, fcitx5-hangul, fcitx5-configtool |
| GPU (옵션) | mesa, mesa-dev, virglrenderer-android |

### proot (선택)

| distro | 기반 | 진입 명령 |
|--------|------|-----------|
| ubuntu | Ubuntu (proot-distro) | `ubuntu` |
| archlinux | Arch Linux (proot-distro) | `archlinux` |

설치 완료 후 설정은 `~/.config/termux-xfce/config`에 저장됩니다.

```
PROOT_DISTRO=ubuntu
PROOT_USER=lideok
INSTALL_ARCH=aarch64
```

`prun`, `cp2menu`, `app-installer` 는 이 파일을 읽어 동작합니다.

---

## GPU 가속

Termux native 가속 드라이버: [xMeM/termux-packages](https://github.com/xMeM/termux-packages)
→ Actions → 최신 run → `mesa-vulkan-icd-wrapper` + mesa 드라이버 다운로드 후 설치

> zenity가 실행되지 않으면 `pkg install mesa-zink` 후 zenity 실행, 이후 원래 mesa로 재설치

---

## 프로젝트 구조

```
Termux_XFCE/
├── install.sh                    ← 진입점 + DI 컨테이너
├── ports/
│   ├── pkg_manager.sh            ← 패키지 관리 계약 (인터페이스)
│   └── ui.sh                     ← UI 계약 (인터페이스)
├── adapters/
│   ├── input/
│   │   ├── cli.sh                ← CLI 인자 / 환경변수 파싱
│   │   └── interactive.sh        ← 대화형 입력 (distro, username)
│   └── output/
│       ├── pkg_termux.sh         ← Termux pkg 구현체
│       ├── pkg_ubuntu.sh         ← Ubuntu apt 구현체
│       ├── pkg_arch.sh           ← Arch pacman 구현체
│       ├── ui_terminal.sh        ← 터미널 echo UI
│       └── ui_zenity.sh          ← zenity GUI UI
├── domain/
│   ├── packages.sh               ← 패키지 정의 목록
│   ├── termux_env.sh             ← Termux 환경 설정 로직
│   ├── xfce_env.sh               ← XFCE 설치 로직
│   └── proot_env.sh              ← proot 환경 로직 (Ubuntu/Arch 공통)
└── app-installer/                ← 앱 추가 설치 GUI (Git Submodule)
```

**아키텍처 흐름:**
```
install.sh (DI)
  ├── ports/ 로드 (계약)
  ├── adapters/output/ 선택 (UI: terminal or zenity, pkg: termux/ubuntu/arch)
  ├── adapters/input/ 실행 (CLI 파싱 → 대화형 보완)
  └── domain/ 실행 (비즈니스 로직)
```

도메인 로직은 `pkg_install()`, `ui_info()` 등 포트 함수만 호출하며 어댑터 구현을 모릅니다.

---

## dev 브랜치 테스트

```bash
# dev 브랜치에서 설치 테스트
curl -sL https://raw.githubusercontent.com/yanghoeg/Termux_XFCE/dev/install.sh | INSTALL_BRANCH=dev bash

# 옵션 포함
curl -sL https://raw.githubusercontent.com/yanghoeg/Termux_XFCE/dev/install.sh | INSTALL_BRANCH=dev bash -s -- --distro ubuntu --user lideok --gpu
```

---

## Signal 9 오류 해결

Termux가 강제 종료되는 경우 ADB로 phantom process 제한 해제:

```bash
adb shell "/system/bin/device_config put activity_manager max_phantom_processes 2147483647"
```

[LADB](https://github.com/hyperio546/ladb-builds/releases) 또는 Termux에서 직접 ADB 연결 후 실행.  
참고 영상: https://www.youtube.com/watch?v=BHc7uvX34bM

---

## 기여

오류나 개선 아이디어는 Pull Request 또는 Issue로 남겨주세요.
