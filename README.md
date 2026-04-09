# Termux XFCE

Android 기기(Termux)에서 XFCE 데스크탑 환경을 자동 설치하는 스크립트입니다.  
[phoenixbyrd/Termux_XFCE](https://github.com/phoenixbyrd/Termux_XFCE) 에서 파생되었습니다.

**테스트 기기**: Galaxy Fold6 (Adreno 750, SD 8 Gen3), Galaxy Tab S9 Ultra (Adreno 740, SD 8 Gen2)

---

## 특징

- **Termux native 우선**: XFCE, Firefox, fcitx5-hangul, GPU 가속 모두 Termux 네이티브로 설치
- **proot 선택 가능**: Ubuntu / Arch Linux / 없음
- **헥사고날 아키텍처(Ports & Adapters)**: distro 추상화로 Ubuntu·Arch 공통 코드 유지
- **멱등성**: 이미 설치된 항목은 자동으로 건너뜀
- **실기기 검증**: 실제 Termux 환경에서 단계별 설치 + 122개 자동화 테스트로 검증

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
bash install.sh --distro ubuntu --user yanghoeg --gpu

# Arch Linux proot
bash install.sh --distro archlinux --user yanghoeg

# Termux native only (proot 없음)
bash install.sh --no-proot

# GPU 개발 도구 포함
bash install.sh --distro ubuntu --user yanghoeg --gpu --gpu-dev
```

### 환경변수로 지정

```bash
DISTRO=ubuntu USERNAME=yanghoeg INSTALL_GPU=true bash install.sh
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

### Wine (Windows 앱 실행)

app-installer에서 Wine을 설치하면 Box64 + Wine-Staging이 구성됩니다.

```bash
# Windows 앱 실행
wine kakao.exe
wine hancom.exe

# Wine 환경 설정
wine winecfg

# DLL·런타임 설치 (vcrun, dotnet 등)
winetricks vcrun2019
winetricks dotnet48

# FPS HUD와 함께 실행
GALLIUM_HUD=fps wine game.exe
```

| 상황 | 구성 |
|------|------|
| proot Ubuntu/Arch | Box64(ARM64) + Wine-Staging x86_64 tarball |
| proot 없음 | glibc-runner + box64-glibc + Wine-Staging tarball |

> **한계**: 안티치트 게임, 커널 드라이버 의존 앱, 최신 .NET 복잡 앱은 동작하지 않습니다.

### GPU 관련 별칭

```bash
# Zink(OpenGL→Vulkan) 드라이버로 앱 실행
zink glxgears

# FPS HUD 오버레이
hud glxgears

# proot 앱을 GPU 가속 + FPS HUD로 실행
zrunhud glxgears

# 감지된 GPU 모델 확인
gpu-info
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
| GPU (옵션) | mesa-zink, osmesa-zink, mesa-vulkan-icd-freedreno, vulkan-loader-generic, mesa-vulkan-icd-swrast |

> GPU 패키지명은 Termux tur-repo 2024년 이후 구조 기준입니다. (mesa → mesa-zink, osmesa → osmesa-zink 등)

### proot (선택)

| distro | 기반 | 진입 명령 |
|--------|------|-----------|
| ubuntu | Ubuntu (proot-distro) | `ubuntu` |
| archlinux | Arch Linux (proot-distro) | `archlinux` |

설치 완료 후 설정은 `~/.config/termux-xfce/config`에 저장됩니다.

```
PROOT_DISTRO=ubuntu
PROOT_USER=yanghoeg
INSTALL_ARCH=aarch64
```

`prun`, `cp2menu`, `app-installer` 는 이 파일을 읽어 동작합니다.

---

## GPU 가속

### 현재 상태 (Termux X11 환경 제약)

Termux X11에서 Adreno GPU 하드웨어 가속은 현재 작동하지 않습니다. **llvmpipe (소프트웨어 렌더링)** 으로 동작합니다.

**근본 원인 3가지**:

| 항목 | 상태 | 설명 |
|------|------|------|
| `/dev/dri/renderD128` | Permission denied | root 없이 DRM 렌더 노드 접근 불가 |
| Termux X11 | DRI3 미지원 | Zink/Turnip이 X11 창에 GPU 직접 렌더링 불가 |
| `virgl_test_server` | 초기화 실패 | 호스트 OpenGL 없어 `failed to initialise renderer` |

**조사 결과** (Galaxy Fold6, Adreno 750):
- `/dev/kgsl-3d0` 접근 가능 (666) — 하지만 `libvulkan_freedreno.so` 26.0.4는 DRM 경유
- `mesa-zink-vulkan-icd-freedreno` 22.0.5는 kgsl 직접 접근 지원하나, DRI3 없이 Zink EGL 초기화 불가
- `virgl_test_server_android --angle-vulkan` 실행해도 vtest 프로토콜 버전 불일치로 스택 충돌

**GPU 가속 활성화 조건** (미래):
- root 권한으로 `chmod 666 /dev/dri/renderD128` → freedreno kgsl ICD(22.0.5) 사용 가능
- 또는 Termux X11이 DRI3 지원 추가 시 → Zink + Turnip 경로 가능

### 환경변수 (startXFCE)

```bash
MESA_NO_ERROR=1                    # GL 에러 체크 비활성 (성능)
MESA_GL_VERSION_OVERRIDE=4.6COMPAT
MESA_GLES_VERSION_OVERRIDE=3.2
```

### 참고 자료

- [xMeM/termux-packages](https://github.com/xMeM/termux-packages) — Termux용 GPU 패키지 빌드
- [Mesa 환경변수 문서](https://docs.mesa3d.org/envvars.html)

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
├── tests/                        ← 자동화 테스트 (122개)
│   ├── run_tests.sh              ← 전체 실행 진입점
│   ├── framework.sh              ← 테스트 러너 (describe/it/assert)
│   ├── mocks.sh                  ← Mock 어댑터 + 파일시스템 샌드박스
│   ├── test_ports.sh             ← 포트 계약 검증
│   ├── test_adapters.sh          ← 어댑터 유닛 테스트
│   ├── test_domain_termux.sh     ← termux_env 도메인 테스트
│   ├── test_domain_xfce.sh       ← xfce_env 도메인 테스트
│   ├── test_domain_proot.sh      ← proot_env 도메인 테스트
│   └── test_app_installer.sh     ← app-installer 테스트
└── app-installer/                ← 앱 추가 설치 GUI (Git Submodule)
    ├── install.sh                ← zenity GUI 메인
    ├── install_vlc.sh
    ├── install_thunderbird.sh
    ├── install_wine.sh           ← Box64 + Wine-Staging (proot/native 분기)
    └── ...                       ← 총 13개 앱 설치 스크립트
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

## 테스트

```bash
# 전체 테스트 실행
bash tests/run_tests.sh

# 특정 스위트만
bash tests/run_tests.sh domain_termux
bash tests/run_tests.sh app_installer
```

| 스위트 | 테스트 수 | 내용 |
|--------|----------|------|
| ports | 7 | 어댑터 계약 준수 검증 |
| adapters | 12 | pkg_termux stub 에러 반환, ui_terminal 유닛 테스트 |
| domain_termux | 25 | termux_env 도메인 로직 + tur_multilib sed + kill_x11 |
| domain_xfce | 19 | xfce_env 도메인 로직 + autostart cp + 폰트·커서 멱등성 |
| domain_proot | 25 | proot_env 도메인 로직 + conky cp + korean locale 경로 검증 |
| app_installer | 34 | shebang, 타이포, 경로, 설치 상태 |
| **합계** | **122** | **Adreno750v2 실기기에서 전체 통과** |

---

## 브랜치 전략

| 브랜치 | 용도 |
|--------|------|
| `main` | 안정 버전 — 실기기 테스트 완료, 최종 사용자용 |
| `dev` | 개발 중 — 기능 추가·버그 수정 후 테스트 통과 시 main에 머지 |

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
