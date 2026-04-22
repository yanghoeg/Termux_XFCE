# Termux XFCE

<div align="center">

[English](README.md) &nbsp;|&nbsp; **[한국어](README.ko.md)**

[![Android](https://img.shields.io/badge/Android-Termux-3DDC84?logo=android)](https://termux.dev)
[![Arch](https://img.shields.io/badge/Arch-aarch64-0070C0)](https://github.com/yanghoeg/Termux_XFCE)
[![License](https://img.shields.io/badge/License-MIT-yellow)](LICENSE)

</div>

---

Android 기기의 Termux에서 **XFCE 데스크탑 환경**을 자동 설치하는 Bash 스크립트입니다.  
[phoenixbyrd/Termux_XFCE](https://github.com/phoenixbyrd/Termux_XFCE) 에서 파생되었습니다.

**테스트 기기**: Galaxy Fold6 (Adreno 750, SD 8 Gen3), Galaxy Tab S9 Ultra (Adreno 740, SD 8 Gen2)

## 특징

- **Termux native 우선** — XFCE, Firefox, fcitx5-hangul, GPU 가속 모두 Termux 네이티브 설치
- **proot 선택 가능** — Ubuntu / Arch Linux / 없음
- **헥사고날 아키텍처** — distro 추상화로 Ubuntu·Arch 공통 코드 유지
- **멱등성** — 이미 설치된 항목은 자동으로 건너뜀
- **GPU 가속** — Adreno 6xx/7xx/8xx에서 Zink + Turnip 자동 활성화
- **zsh + Powerlevel10k** — 기본 쉘로 설정, 자동완성·구문강조 포함

## 설치

```bash
# one-liner (자동 clone 후 실행)
curl -sL https://raw.githubusercontent.com/yanghoeg/Termux_XFCE/main/install.sh | bash
```

```bash
# 옵션 지정
bash install.sh --distro ubuntu --user <username> --gpu
bash install.sh --distro archlinux --user <username>
bash install.sh --no-proot          # Termux native만
bash install.sh --distro ubuntu --user <username> --gpu --gpu-dev
bash install.sh --distro archlinux --user <username> --proot-only  # 두 번째 distro 추가
```

```bash
# 환경변수로 지정
DISTRO=ubuntu USERNAME=<username> INSTALL_GPU=true bash install.sh
```

| 옵션 | 환경변수 | 설명 |
|------|----------|------|
| `--distro ubuntu\|archlinux` | `DISTRO=` | proot distro 선택 |
| `--user <이름>` | `USERNAME=` | proot 사용자 이름 |
| `--no-proot` | `SKIP_PROOT=true` | proot 없이 native만 |
| `--proot-only` | `PROOT_ONLY=true` | proot만 설치 (Termux native 설정 생략, 두 번째 distro 추가 시) |
| `--gpu` | `INSTALL_GPU=true` | GPU 가속 패키지 설치 |
| `--gpu-dev` | `INSTALL_GPU_DEV=true` | GPU 개발 도구 설치 |
| `--korean-locale` | `KOREAN_LOCALE=true` | 한글 로케일 옵트인 (아래 "한글 로케일" 참조) |
| `--locale-zip <path>` | `KOREAN_LOCALE_ZIP=` | .mo 카탈로그 zip 경로 (Release asset) |

## 사용법

```bash
startXFCE          # XFCE 데스크탑 시작
ubuntu             # Ubuntu proot 진입
archlinux          # Arch Linux proot 진입
prun libreoffice   # proot 앱을 Termux에서 직접 실행
cp2menu            # proot .desktop 파일을 XFCE 메뉴에 복사
app-installer      # 앱 추가 설치/제거 GUI
```

## GPU 가속

Adreno GPU(Snapdragon 6xx/7xx/8xx)에서 **Zink(OpenGL→Vulkan) + Turnip** 드라이버로 하드웨어 가속이 동작합니다.  
설치 후 모든 bash/zsh 세션에서 자동 적용됩니다.

> **glamor 단독으로는 안 되는 이유**  
> X11의 OpenGL 가속(`glamor_egl`)은 DRI3 지원이 필요하지만, Termux:X11의 Xwayland 브릿지는 Adreno DRI3를 노출하지 않습니다.  
> Zink는 OpenGL 호출을 Vulkan(Turnip)으로 우회해 `/dev/kgsl-3d0`을 통해 GPU에 접근합니다 — 현재 Adreno에서 하드웨어 가속을 쓸 수 있는 유일한 경로입니다.

> **GTK4 앱(zenity 등) 크래시 시**  
> Zink+Turnip이 Termux:X11 nightly APK에서 GLX 스왑체인 생성에 실패해 `GLXBadCurrentWindow` 크래시가 발생합니다.  
> `GSK_RENDERER=cairo`(GTK4 Cairo 렌더러 강제)로 해결됩니다. 설치 시 자동 설정됩니다.  
> `glmark2` (GLX) 대신 `glmark2-es2` (EGL)를 사용하세요.

```bash
# Zink 활성 여부 확인
echo $MESA_LOADER_DRIVER_OVERRIDE   # → zink

# GPU 모델 확인
gpu-info
# 또는 직접:
cat /sys/class/kgsl/kgsl-3d0/gpu_model

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
| `MESA_GL_VERSION_OVERRIDE` | `4.6COMPAT` | OpenGL 4.6 compat 광고 |
| `MESA_GLES_VERSION_OVERRIDE` | `3.2` | GLES 3.2 광고 |
| `MESA_VK_WSI_PRESENT_MODE` | `immediate` | Vulkan VSync 비활성 (지연 감소) |
| `GSK_RENDERER` | `cairo` | GTK4 Cairo 렌더러 (GLX 크래시 방지) |
| `GALLIUM_HUD` | `fps` | FPS 오버레이 (`hud` 별칭) |

> **주의**: XFCE4 컴포지터(xfwm4)가 검은 화면을 유발할 경우  
> 설정 → 창관리자(작업) → 컴포지터 → '화면 컴포지팅 활성화' 해제

## 한글 로케일 (옵션)

XFCE 메뉴/설정/앱 UI를 한글로 표시할 수 있습니다. Termux의 bionic libc가 `setlocale(LC_MESSAGES)`를 지원하지 않기 때문에 일반적인 "XFCE 언어 설정" 접근은 불가능하고, **LD_PRELOAD 기반 gettext 후킹**으로 우회합니다.

> 이 접근법은 **미코(미니기기 코리아) — 흡혈귀왕님**이 공유해 주신 방법을 바탕으로 구현되었습니다. 감사합니다. 🙏

### 사용법

```bash
# 1) 한글 로케일 옵션 활성화 + locale.zip 경로 지정 (Release asset에서 다운로드)
bash install.sh --distro archlinux --user <username> --korean-locale --locale-zip ~/Downloads/locale.zip

# 2) 한글 모드로 XFCE 기동
tx11start --xstartup "$HOME/bin/startxfce4-ko"
```

### 구성

| 파일 | 역할 |
|------|------|
| `assets/force_gettext.c` | gettext/dgettext/dcgettext + GTK 심볼 후킹 C 소스 (clang -shared 빌드) |
| `domain/locale_ko.sh` | `setup_korean_locale_native()` — .mo 카탈로그 배치 + `.so` 빌드 + `startxfce4-ko` 래퍼 생성 |
| `$PREFIX/lib/force_gettext.so` | 런타임 주입 shared object |
| `$HOME/bin/startxfce4-ko` | DBus autostart 포함 한글 모드 XFCE 기동 래퍼 |

`locale.zip`(~163MB, glibc용 .mo 카탈로그 모음)은 리포 용량상 포함하지 않고 **Release asset으로 별도 배포**합니다.

### 동작 확인된 앱

GIMP, Inkscape, Audacity, Thunderbird, VLC(proot), XFCE 설정 매니저 — 메뉴/대화상자/툴팁 한글 표시.

## 쉘 (zsh + Powerlevel10k)

설치 시 **zsh**가 기본 쉘로 설정되고 Powerlevel10k가 자동으로 구성됩니다.

```bash
# p10k 프롬프트 재설정
p10k configure

# 자동 설치되는 별칭
ll          # eza -alhgF
ls          # eza -lF --icons
cat         # bat
gpu-info    # Adreno GPU 모델 확인
zink        # Zink 강제 지정으로 앱 실행
hud         # FPS 오버레이로 앱 실행
zrunhud     # proot 앱 + FPS + GPU
shutdown    # kill -9 -1 (Termux 전체 프로세스 종료)
```

## 설치 구성

### Termux Native (항상 설치)

| 분류 | 패키지 |
|------|--------|
| 기본 유틸 | wget, unzip, dbus, pulseaudio, yad |
| XFCE | xfce4, xfce4-goodies, firefox, papirus-icon-theme, termux-x11-nightly |
| CLI | git, zsh, eza, bat, fzf, htop, jq, neofetch |
| 한글 입력 | fcitx5, fcitx5-hangul, fcitx5-configtool |
| GPU (옵션) | mesa, mesa-vulkan-icd-freedreno, vulkan-loader-generic, mesa-vulkan-icd-swrast |

### proot (선택)

| distro | 기반 | 한글 입력기 | 진입 명령 |
|--------|------|-------------|-----------|
| ubuntu | Ubuntu (proot-distro) | nimf (자동 설치) | `ubuntu` |
| archlinux | Arch Linux (proot-distro) | nimf (AUR) → fcitx5 폴백 | `archlinux` |

> **Arch Linux nimf 지원**
> 설치 시 nimf AUR 빌드를 자동 시도하며, 실패 시 fcitx5로 폴백합니다.
> 수동 재시도: `paru -S nimf nimf-libhangul`

## App Installer

GIMP, Inkscape, Audacity, VLC, LibreOffice, Thunderbird 등 추가 앱은 GUI로 설치 가능합니다:

```bash
app-installer
```

- **yad 기반 검색 UI** — 앱 이름/설명 타이핑으로 즉시 필터링 (yad 미설치 시 zenity 폴백)
- **카테고리 구분** — 그래픽/미디어/오피스/브라우저/개발/보안/유틸/소통
- **Termux native 우선** — GIMP, Inkscape, Audacity, Thunderbird는 Termux 네이티브 (한글 로케일 지원)
- **proot 자동 라우팅** — VLC, LibreOffice 등은 proot 내부 설치; VSCode(code-oss), Burp Suite는 Termux native

소스: [yanghoeg/App-Installer](https://github.com/yanghoeg/App-Installer) (Git Submodule)

## 테스트

```bash
bash tests/run_tests.sh              # 전체 (141개)
bash tests/run_tests.sh domain_termux
bash tests/run_tests.sh app_installer
```

| 스위트 | 수 | 내용 |
|--------|---|------|
| ports | 7 | 어댑터 계약 준수 |
| adapters | 12 | pkg_termux, ui_terminal |
| domain_termux | 25 | termux_env 로직 |
| domain_xfce | 18 | xfce_env 로직 |
| domain_proot | 25 | proot_env 로직 |
| app_installer | 39 | 설치 스크립트 검증 |
| prun_ld_preload | 15 | prun / LD_PRELOAD 회귀 |
| **합계** | **141** | **실기기 전체 통과** |

## Android 시스템 최적화

안정적이고 부드러운 데스크탑 환경을 위해 아래 시스템 설정을 적용하세요.

### 팬텀 프로세스 킬러 비활성화 (Android 12+)

Android 12부터 백그라운드 자식 프로세스를 강제 종료하는 정책이 도입되어 데스크탑 세션이 끊길 수 있습니다.  
[LADB](https://github.com/hyperio546/ladb-builds/releases) 또는 PC ADB 연결 후 실행:

```bash
adb shell "/system/bin/device_config put activity_manager max_phantom_processes 2147483647"
```

### 배터리 최적화 해제

**안드로이드 설정 → 앱 → Termux** (및 **Termux:X11**) → 배터리 → **제한 없음** 으로 설정.  
이 설정이 없으면 백그라운드 CPU 사용량이 제한되어 Zink 가속이 활성화되어도 프레임 드랍이 발생할 수 있습니다.

### Wakelock

`startXFCE` 실행 시 `termux-wake-lock`이 자동으로 호출됩니다. 장시간 작업 시 Termux 알림에서 **"Acquire wakelock"** 을 탭해 유지하세요.

---

## 파일 구조

```
Termux_XFCE/
├── install.sh                    ← 진입점 + DI 컨테이너
├── ports/
│   ├── pkg_manager.sh            ← 패키지 관리 계약
│   └── ui.sh                     ← UI 계약
├── adapters/
│   ├── input/
│   │   ├── cli.sh                ← CLI 인자 / 환경변수 파싱
│   │   └── interactive.sh        ← 대화형 입력
│   └── output/
│       ├── pkg_termux.sh         ← Termux pkg 어댑터
│       ├── pkg_ubuntu.sh         ← Ubuntu apt 어댑터
│       ├── pkg_arch.sh           ← Arch pacman 어댑터
│       ├── ui_terminal.sh        ← echo 기반 UI
│       ├── ui_yad.sh             ← yad 검색 GUI (zenity 상위호환)
│       └── ui_zenity.sh          ← zenity GUI UI (폴백)
├── domain/
│   ├── packages.sh               ← 패키지 목록 정의
│   ├── termux_env.sh             ← Termux 환경 로직
│   ├── xfce_env.sh               ← XFCE 설정 로직
│   ├── proot_env.sh              ← proot 로직 (Ubuntu/Arch 공통)
│   └── locale_ko.sh              ← 한글 로케일 옵트인 (LD_PRELOAD gettext 후킹)
├── assets/
│   └── force_gettext.c           ← gettext 후킹 C 소스 (→ force_gettext.so)
├── tests/                        ← 자동화 테스트 141개
└── app-installer/                ← 앱 추가 설치 GUI (Git Submodule)
```

## 브랜치 전략

| 브랜치 | 용도 |
|--------|------|
| `main` | 안정 — 실기기 테스트 완료, 최종 사용자용 |
| `dev` | 개발 중 — 테스트 통과 후 main에 머지 |

## 기여

버그 리포트·PR은 GitHub Issues / Pull Requests를 통해 환영합니다.
