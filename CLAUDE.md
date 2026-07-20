# CLAUDE.md — Termux XFCE 프로젝트 컨텍스트

## 프로젝트 개요

Android 기기(Termux)에서 XFCE 데스크탑 환경 + proot-distro(Ubuntu/Arch 선택)를 자동 설치하는 Bash 스크립트 모음.
**헥사고날 아키텍처(Ports & Adapters)** 적용.

## 실행 환경

- **타겟 환경**: Android 기기의 Termux (`/data/data/com.termux/...` 경로)
- **개발/편집 환경**: Linux PC (`/home/lideok/code/work/linux/Termux_XFCE/`) 및 기기 Termux 내 Claude Code
- 스크립트 shebang: `#!/data/data/com.termux/files/usr/bin/bash` (일반 Linux에서 직접 실행 불가)
- 테스트: PC 수정 → `git push` → 기기에서 `git pull` → `tests/` 단위 테스트 또는 `source domain/*.sh && <func>`

## 설치 방법 (최종 사용자)

```bash
curl -sL https://raw.githubusercontent.com/yanghoeg/Termux_XFCE/main/install.sh | bash
# 또는
bash install.sh --distro archlinux --user lideok
# 또는 환경변수
DISTRO=ubuntu USERNAME=lideok bash install.sh
# 디스플레이 서버 선택 (기본: x11)
bash install.sh --distro ubuntu --user lideok --display wayland
```

## 아키텍처: 헥사고날 (Ports & Adapters)

```
install.sh          → DI(어댑터 선택) → Domain 실행
ports/              → 계약 정의 (pkg_manager, ui, display, script_builder)
adapters/input/     → CLI 인자 / 대화형 입력
adapters/output/    → pkg 매니저 / UI / 디스플레이 서버 / 스크립트 빌더 구현체
domain/             → 비즈니스 로직 (HOW 모름, WHAT만 앎)
tests/              → 단위/통합 테스트, mocks, autopilot
app-installer/      → Git Submodule (독립 repo)
```

### 핵심 원칙
- **Termux native 우선**: XFCE, Firefox, fcitx5, GPU mesa 모두 Termux 네이티브
- **proot는 선택**: Ubuntu 또는 Arch Linux, 또는 없음
- **도메인은 pkg_install/ui_info/display_get_packages만 호출** (어댑터 주입)
- **멱등성**: 모든 함수는 이미 설치된 경우 건너뜀

### 파일 구조

```
Termux_XFCE/
├── install.sh                    ← 진입점 + DI 컨테이너
├── ports/
│   ├── pkg_manager.sh            ← 패키지 관리 계약
│   ├── ui.sh                     ← UI 계약
│   ├── display.sh                ← 디스플레이 서버 계약 (X11/Wayland)
│   └── script_builder.sh         ← 런타임 스크립트 생성 계약
├── adapters/
│   ├── input/{cli,interactive}.sh
│   └── output/{pkg_*,ui_*,display_x11,display_wayland,script_builder_zenity}.sh
├── domain/
│   ├── packages.sh               ← 패키지 정의 목록
│   ├── termux_env.sh             ← Termux 환경 (zsh+p10k 포함)
│   ├── xfce_env.sh               ← XFCE 환경
│   └── proot_env.sh              ← proot 환경
├── tests/
│   ├── framework.sh, mocks.sh, run_tests.sh, autopilot.sh
│   ├── test_domain_{termux,xfce,proot}.sh
│   ├── test_{ports,adapters,app_installer}.sh
│   └── test_prun_ld_preload.sh
└── app-installer/                ← submodule
```

## App-Installer 연동

- 별도 Git repo 유지 + Git Submodule로 연결 (독립 업데이트 가능)
- `PROOT_DISTRO` env var로 distro-aware 동작
- 동일 헥사고날 아키텍처 적용 예정 (아래 TODO 참조)

## 남은 TODO

1. **App-Installer Termux native 우선 리팩토링**
   - 각 앱마다 `pkg search <앱>` 결과 있으면 `pkg install`로 전환, 없으면 proot fallback
   - 예: Thunderbird는 native, VLC·LibreOffice는 proot 유지
   - `install.sh` GUI에 설치 위치(native/proot) 표시 추가
2. **App-Installer 헥사고날 리팩토링**: `PKG_MAP`, distro 추상화
3. **README.md / README.ko.md 최신성 확인**: 구조 설명, 설치 방법, zsh 기본 쉘 반영 여부

## 주의사항

- `set -euo pipefail` 사용 중 — 오류 시 즉시 종료
- `local` 키워드는 bash 함수 내에서만 유효 (함수 밖에서 쓰면 에러)
- Termux 패키지: `--force-confold` 옵션으로 설정 파일 충돌 방지
- `proot_exec`는 `PROOT_DISTRO`, `PROOT_USER` 환경변수 필요
- **디스플레이 서버 추상화**: `ports/display.sh` 포트로 X11/Wayland 분리
  - X11 어댑터(`display_x11.sh`): Termux:X11 APK + `termux-x11` 프로세스
  - Wayland 어댑터(`display_wayland.sh`): labwc 기반 (스텁 — 구현 예정)
  - `--display x11|wayland` CLI 옵션 또는 `DISPLAY_SERVER` 환경변수로 선택
  - X11 기본: `termux-x11 :N` → 소켓 자동 감지 (`${TMPDIR}/.X11-unix/X*`)
- **기본 쉘은 zsh + Powerlevel10k**: `domain/termux_env.sh` `_setup_zsh_p10k()`가 설치 시 자동 구성
  - RC 파일 수정은 bash/zsh 양쪽 모두 반영해야 함 (`_get_rc_files()` 참조)
