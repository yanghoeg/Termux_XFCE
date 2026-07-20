# Termux XFCE

<div align="center">

**[한국어](README.md)** &nbsp;|&nbsp; [English](README.en.md)

[![Android](https://img.shields.io/badge/Android-Termux-3DDC84?logo=android)](https://termux.dev)
[![Arch](https://img.shields.io/badge/Arch-aarch64-0070C0)](https://github.com/yanghoeg/Termux_XFCE)
[![License](https://img.shields.io/badge/License-MIT-yellow)](LICENSE)

</div>

---

Android 기기의 Termux에서 **XFCE 데스크탑 환경**을 자동 설치하는 Bash 스크립트입니다.  
[phoenixbyrd/Termux_XFCE](https://github.com/phoenixbyrd/Termux_XFCE) 에서 파생되었습니다.

**테스트 기기**: Galaxy Fold6 (Adreno 750, SD 8 Gen3), Galaxy Tab S9 Ultra (Adreno 740, SD 8 Gen2)

## 특징

- **Termux native 우선** — XFCE, Firefox, GPU 가속 모두 Termux 네이티브 설치
- **proot 선택 가능** — Ubuntu / Arch Linux / 없음
- **헥사고날 아키텍처** — distro 추상화로 Ubuntu·Arch 공통 코드 유지
- **멱등성** — 이미 설치된 항목은 자동으로 건너뜀
- **GPU 가속** — Adreno 6xx/7xx/8xx에서 Zink + Turnip 자동 활성화
- **Termux API 연동** — Android 클립보드 동기화, 배터리 모니터, 밝기/볼륨 조절
- **zsh + Powerlevel10k** — 기본 쉘로 설정, 자동완성·구문강조 포함

## 설치

> **그냥 `install.sh`만 실행하면 됩니다 — 모든 옵션은 대화형으로 물어봅니다.**  
> 플래그/환경변수는 비대화형(스크립트) 설치용입니다.

```bash
# one-liner (자동 clone 후 실행 — 대화형)
curl -sL https://raw.githubusercontent.com/yanghoeg/Termux_XFCE/main/install.sh | bash
```

```bash
# 비대화형: 옵션 지정
bash install.sh --distro ubuntu --user <username>
bash install.sh --distro archlinux --user <username>
bash install.sh --no-proot          # Termux native만
bash install.sh --distro archlinux --user <username> --proot-only  # 두 번째 distro 추가
```

```bash
# 비대화형: 환경변수로 지정
DISTRO=ubuntu USERNAME=<username> bash install.sh
```

| 옵션 | 환경변수 | 설명 |
|------|----------|------|
| `--distro ubuntu\|archlinux` | `DISTRO=` | proot distro 선택 |
| `--user <이름>` | `USERNAME=` | proot 사용자 이름 |
| `--no-proot` | `SKIP_PROOT=true` | proot 없이 native만 |
| `--proot-only` | `PROOT_ONLY=true` | proot만 설치 (두 번째 distro 추가 시) |

> GPU 가속, 한글 입력기 등 선택적 구성요소는 설치 후 `app-installer`에서 관리합니다.

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
> X11의 OpenGL 가속(`glamor_egl`)은 DRI3 지원이 필요하지만, Termux:X11의 Xwayland는 Adreno DRI3를 노출하지 않습니다.  
> Zink는 OpenGL 호출을 Vulkan(Turnip)으로 우회해 `/dev/kgsl-3d0`을 통해 GPU에 접근합니다.

> **GTK4 앱(zenity 등) 크래시 시**  
> `GSK_RENDERER=cairo`(GTK4 Cairo 렌더러 강제)로 해결됩니다. 설치 시 자동 설정됩니다.

```bash
echo $MESA_LOADER_DRIVER_OVERRIDE   # → zink
gpu-info                             # GPU 모델 확인
hud glxgears                         # FPS HUD 오버레이
```

| 변수 | 값 | 역할 |
|------|----|------|
| `MESA_LOADER_DRIVER_OVERRIDE` | `zink` | OpenGL → Vulkan(Zink) 강제 |
| `TU_DEBUG` | `noconform` | Turnip conformance 체크 비활성 |
| `ZINK_DESCRIPTORS` | `lazy` | 디스크립터 업데이트 최적화 |
| `MESA_NO_ERROR` | `1` | GL 에러 체크 비활성 |
| `MESA_GL_VERSION_OVERRIDE` | `4.6COMPAT` | OpenGL 4.6 compat 광고 |
| `MESA_GLES_VERSION_OVERRIDE` | `3.2` | GLES 3.2 광고 |
| `MESA_VK_WSI_PRESENT_MODE` | `immediate` | Vulkan VSync 비활성 |
| `GSK_RENDERER` | `cairo` | GTK4 Cairo 렌더러 (GLX 크래시 방지) |

> **주의**: XFCE4 컴포지터(xfwm4)가 검은 화면을 유발할 경우  
> 설정 → 창관리자(작업) → 컴포지터 → '화면 컴포지팅 활성화' 해제

## Termux API 연동

설치 시 **Termux:API** 패키지와 APK가 자동으로 설치됩니다.

### 자동 활성화

- **클립보드 동기화** — XFCE 시작 시 Android↔X11 클립보드 양방향 동기화 데몬이 자동 실행

### App Installer에서 추가 설치

| 도구 | 설명 |
|------|------|
| Conky 배터리 | Conky 위젯에 배터리 잔량·온도 표시 |
| 밝기 조절 | XFCE 패널용 화면 밝기 조절 스크립트 |
| 볼륨 조절 | XFCE 패널용 볼륨 조절 스크립트 |
| 알림 도구 | 스크립트에서 Android 알림바 전송 |
| TTS 음성 | 텍스트를 음성으로 변환 (Android TTS) |
| 음성인식 | 음성을 텍스트로 변환 (Android STT) |
| 배경화면 동기화 | XFCE 배경화면을 Android에 적용 |

## 한글 로케일 (옵션)

XFCE 메뉴/설정/앱 UI를 한글로 표시합니다. Termux의 bionic libc가 `setlocale(LC_MESSAGES)`를 지원하지 않기 때문에 **LD_PRELOAD 기반 gettext 후킹**으로 우회합니다.

> 이 접근법은 **미코(미니기기 코리아) — 흡혈귀왕님**이 공유해 주신 방법을 바탕으로 구현되었습니다. 🙏

한글 입력기(fcitx5), 한글 로케일은 `app-installer`에서 설치할 수 있습니다.

| 파일 | 역할 |
|------|------|
| `assets/force_gettext.c` | gettext 후킹 C 소스 (clang -shared 빌드) |
| `domain/locale_ko.sh` | .mo 카탈로그 배치 + `.so` 빌드 |
| `$PREFIX/lib/force_gettext.so` | 런타임 주입 shared object |

## 쉘 (zsh + Powerlevel10k)

설치 시 **zsh**가 기본 쉘로 설정되고 Powerlevel10k가 자동으로 구성됩니다.

```bash
p10k configure        # p10k 프롬프트 재설정

# 자동 설치되는 별칭
ll          # eza -alhgF
ls          # eza -lF --icons
cat         # bat
gpu-info    # Adreno GPU 모델 확인
zink        # Zink 강제 지정으로 앱 실행
hud         # FPS 오버레이로 앱 실행
```

## 설치 구성

### Termux Native (항상 설치)

| 분류 | 패키지 |
|------|--------|
| 기본 유틸 | wget, unzip, dbus, pulseaudio, yad, termux-api, xclip |
| XFCE | xfce4, xfce4-goodies, firefox, papirus-icon-theme, termux-x11-nightly |
| CLI | git, zsh, eza, bat, fzf, ripgrep, fd, zoxide, lazygit, git-delta, starship, atuin, zellij, htop, btop, procs, dust, duf, ncdu, yazi, glow, tealdeer, xh, onefetch, jq, neofetch |
| APK | Termux:X11, Termux:API, Termux:Float |

### proot (선택)

| distro | 기반 | 진입 명령 |
|--------|------|-----------|
| ubuntu | Ubuntu (proot-distro) | `ubuntu` |
| archlinux | Arch Linux (proot-distro) | `archlinux` |

## App Installer

추가 앱·시스템 도구·Termux API 도구를 탭 기반 GUI로 설치/제거합니다:

```bash
app-installer          # 전체 (탭: 앱 | 시스템 | Termux API | Wine)
app-installer wine     # Wine 앱만
```

- **탭 기반 UI** — 앱 / 시스템 / Termux API / Wine 탭으로 분류
- **검색** — 이름/설명 타이핑으로 즉시 필터링 (yad notebook, zenity 폴백)
- **Termux native 우선** — GIMP, Inkscape, Thunderbird 등은 네이티브 설치
- **proot 자동 라우팅** — VLC, LibreOffice 등은 proot 내부 설치

소스: [yanghoeg/App-Installer](https://github.com/yanghoeg/App-Installer) (Git Submodule)

## 테스트

```bash
bash tests/run_tests.sh              # 전체 343개
bash tests/run_tests.sh domain_termux
bash tests/run_tests.sh e2e_install
```

| 스위트 | 수 | 내용 |
|--------|---|------|
| ports | 8 | 어댑터 계약 준수 |
| adapters | 25 | pkg_termux, ui_terminal, script_builder_zenity |
| domain_termux | 67 | termux_env 로직 (API APK, 클립보드 동기화 포함) |
| domain_xfce | 39 | xfce_env + 마이그레이션 |
| domain_proot | 62 | proot_env (Ubuntu/Arch) |
| domain_locale_ko | 24 | 한글 로케일 |
| input_interactive | 5 | 대화형 입력 |
| install_matrix | 12 | 설치 조합 매트릭스 |
| app_installer | 56 | app-installer 검증 |
| prun_ld_preload | 17 | prun / LD_PRELOAD 회귀 |
| e2e_install | 28 | E2E 통합 & 회귀 |
| **합계** | **343+** | **실기기 전체 통과** |

## Android 시스템 최적화

### 팬텀 프로세스 킬러 비활성화 (Android 12+)

[LADB](https://github.com/hyperio546/ladb-builds/releases) 또는 PC ADB 연결 후:

```bash
adb shell "/system/bin/device_config put activity_manager max_phantom_processes 2147483647"
```

### 배터리 최적화 해제

**안드로이드 설정 → 앱 → Termux** (및 Termux:X11) → 배터리 → **제한 없음**.

### Wakelock

`startXFCE` 실행 시 `termux-wake-lock`이 자동 호출됩니다.

---

## 알려진 문제

### Termux:X11 — 앱 전환 후 우클릭 오작동 / 방향키 불가

Android가 앱 포커스 해제 시 키 릴리스 이벤트를 중단하여 Alt 키가 고착됩니다. ([#781](https://github.com/termux/termux-x11/issues/781))

**우회**: Alt 키를 한 번 더 누르거나, Super+I로 입력 리셋, 또는 제스처로 앱 전환.

> Samsung DeX: Termux:X11 → Preferences → Keyboard → "Intercept system shortcuts" 활성화.

---

## 파일 구조

```
Termux_XFCE/
├── install.sh                    ← 진입점 + DI 컨테이너
├── ports/                        ← 계약 정의 (인터페이스)
├── adapters/
│   ├── input/                    ← CLI 인자 / 대화형 입력
│   └── output/                   ← pkg 어댑터, UI, 스크립트 빌더
├── domain/
│   ├── packages.sh               ← 패키지 목록
│   ├── termux_env.sh             ← Termux 환경 (API APK, 클립보드 동기화 포함)
│   ├── xfce_env.sh               ← XFCE 설정
│   ├── proot_env.sh              ← proot (Ubuntu/Arch 공통)
│   └── locale_ko.sh              ← 한글 로케일 (LD_PRELOAD)
├── tests/                        ← 자동화 테스트 330개
└── app-installer/                ← 앱 설치 GUI (Git Submodule)
    ├── install.sh                ← yad notebook 탭 GUI
    └── domain/installers/        ← 앱별 설치 스크립트 (31개)
```

## 브랜치 전략

| 브랜치 | 용도 |
|--------|------|
| `main` | 안정 — 실기기 테스트 완료, 최종 사용자용 |
| `dev` | 개발 중 — 테스트 통과 후 main에 머지 |

## 기여

버그 리포트·PR은 GitHub Issues / Pull Requests를 통해 환영합니다.
