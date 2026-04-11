# CLAUDE.md — Termux XFCE 프로젝트 컨텍스트

## 프로젝트 개요

Android 기기(Termux)에서 XFCE 데스크탑 환경 + proot-distro(Ubuntu/Arch 선택)를 자동 설치하는 Bash 스크립트 모음.
**헥사고날 아키텍처(Ports & Adapters)** 적용 중.

## 실행 환경

- **타겟 환경**: Android 기기의 Termux (`/data/data/com.termux/...` 경로)
- **개발/편집 환경**: Linux PC (`/home/lideok/code/work/linux/Termux_XFCE/`)
- 스크립트 shebang: `#!/data/data/com.termux/files/usr/bin/bash` (일반 Linux에서 직접 실행 불가)
- 테스트: `adb push` 후 기기 Termux 앱에서 실행

## 설치 방법 (최종 사용자)

```bash
curl -sL https://raw.githubusercontent.com/yanghoeg/Termux_XFCE/main/install.sh | bash
# 또는
bash install.sh --distro archlinux --user lideok --gpu
# 또는 환경변수
DISTRO=ubuntu USERNAME=lideok bash install.sh
```

## 아키텍처: 헥사고날 (Ports & Adapters)

```
install.sh          → DI(어댑터 선택) → Domain 실행
ports/              → 계약 정의 (인터페이스)
adapters/input/     → CLI 인자 / 대화형 입력
adapters/output/    → pkg 매니저 구현체 / UI 구현체
domain/             → 비즈니스 로직 (HOW 모름, WHAT만 앎)
```

### 핵심 원칙
- **Termux native 우선**: XFCE, Firefox, fcitx5, GPU mesa 모두 Termux 네이티브
- **proot는 선택**: Ubuntu 또는 Arch Linux, 또는 없음
- **도메인은 pkg_install/ui_info만 호출** (어댑터 주입)
- **멱등성**: 모든 함수는 이미 설치된 경우 건너뜀

### 현재 파일 구조

```
Termux_XFCE/
├── install.sh                    ← 진입점 + DI 컨테이너
├── ports/
│   ├── pkg_manager.sh            ← 패키지 관리 계약 (완료)
│   └── ui.sh                     ← UI 계약 (완료)
├── adapters/
│   ├── input/
│   │   ├── cli.sh                ← CLI/env var 파싱 (완료)
│   │   └── interactive.sh        ← 대화형 입력 (완료)
│   └── output/
│       ├── pkg_termux.sh         ← Termux pkg 구현체 (완료)
│       ├── pkg_ubuntu.sh         ← Ubuntu apt 구현체 (완료)
│       ├── pkg_arch.sh           ← Arch pacman 구현체 (완료)
│       ├── ui_terminal.sh        ← echo 기반 UI (완료)
│       └── ui_zenity.sh          ← zenity GUI UI (완료)
├── domain/
│   ├── packages.sh               ← 패키지 정의 목록 (완료)
│   ├── termux_env.sh             ← Termux 환경 도메인 (완료)
│   ├── xfce_env.sh               ← XFCE 환경 도메인 (완료)
│   └── proot_env.sh              ← proot 환경 도메인 (완료)
└── CLAUDE.md
```

### 구 파일 (제거 예정)
- `etc.sh` → `domain/termux_env.sh`로 통합됨
- `xfce.sh` → `domain/xfce_env.sh`로 통합됨
- `proot.sh` + `ubuntu_etc.sh` → `domain/proot_env.sh`로 통합됨
- `utils.sh` → `domain/termux_env.sh`의 `_setup_prun`, `_setup_cp2menu`로 통합됨

## App-Installer 연동

- **결정**: 별도 Git repo 유지 + Git Submodule로 연결
- App-Installer는 독립적으로 업데이트 가능
- App-Installer `install.sh`도 동일 헥사고날 아키텍처 적용 예정
- `PROOT_DISTRO` env var로 distro-aware 동작

## 다음 세션에서 할 일

1. **Termux 쉘 환경 설정**:
   - bash → zsh 전환: `pkg install zsh` 후 `chsh -s zsh`
   - 프롬프트 테마: **Powerlevel10k** 권장 (zsh 네이티브, fancybash 대체)
     ```bash
     pkg install zsh git
     git clone --depth=1 https://github.com/romkatv/powerlevel10k.git ~/powerlevel10k
     echo 'source ~/powerlevel10k/powerlevel10k.zsh-theme' >> ~/.zshrc
     chsh -s zsh
     # 재시작 후 p10k 설정 마법사 자동 실행 (Nerd Font 없어도 동작)
     # 이후 재설정: p10k configure
     ```
   - p10k 특징: git branch/status, 실행시간, exit code, 배터리 표시 기본 제공, 매우 빠름
   - install.sh에 `_setup_zsh_p10k` 함수 추가 예정 (domain/termux_env.sh)
   - zsh 전환 후 `.zshrc`에 기존 `.bashrc` aliases/exports 이식 필요
   - (fancybash 계속 쓸 경우) `~/.fancybash.sh` line 326 `" user "` → `" yanghoeg "`, line 372 `user:` → `yanghoeg:`
2. **구 파일 제거**: `etc.sh`, `xfce.sh`, `proot.sh`, `ubuntu_etc.sh`, `utils.sh`
2. **App-Installer를 Git Submodule로 추가**:
   ```bash
   git submodule add https://github.com/yanghoeg/App-Installer.git app-installer
   ```
3. **App-Installer Termux native 우선 리팩토링**:
   - 각 앱마다 Termux native 패키지가 있으면 proot 대신 `pkg install`로 설치
   - 판단 기준: `pkg search <앱>` 결과가 있으면 native, 없으면 proot fallback
   - 예시: Thunderbird는 이미 native, VLC·LibreOffice는 proot 유지
   - `install.sh` GUI에 설치 위치(native/proot) 표시 추가 예정
4. **App-Installer 헥사고날 리팩토링**: `install.sh`의 `PKG_MAP`, distro 추상화
4. **실제 기기 테스트** 후 버그 수정
   - **테스트 방법**: Termux에 Claude Code 설치 후 직접 테스트
     ```bash
     pkg install nodejs git
     npm install -g @anthropic-ai/claude-code
     echo 'export ANTHROPIC_API_KEY="sk-ant-..."' >> ~/.bashrc
     git clone https://github.com/yanghoeg/Termux_XFCE.git ~/Termux_XFCE
     cd ~/Termux_XFCE && claude
     ```
   - 전체 install.sh 실행 대신 **단위 함수 테스트** 권장: `source domain/termux_env.sh && some_func`
   - PC에서 수정 → `git push` → Termux에서 `git pull` → Claude로 테스트
5. **README.md 업데이트**: 새 구조 설명, 설치 방법

## 주의사항

- `set -euo pipefail` 사용 중 — 오류 시 즉시 종료
- `local` 키워드: bash에서는 함수 내에서만 유효 (install.sh 맨 아래 `_install_termux_x11_apk`에 `local` 사용 — 함수 밖에서 쓰면 에러)
- Termux 패키지: `--force-confold` 옵션으로 설정 파일 충돌 방지
- fancybash line 번호(326, 327)는 원본 파일 기준 — 버전 바뀌면 재확인 필요
- `proot_exec`는 `PROOT_DISTRO`, `PROOT_USER` 환경변수 필요
- **Termux:X11 nightly APK**: X 서버를 APK 내부에서 직접 실행 — CLI `termux-x11 :1.0` 불필요/충돌
  - startXFCE에서 `am start`만 호출, `DISPLAY=:1.0`으로 바로 연결
  - 구버전(stable) APK는 CLI `termux-x11 :1.0` 필요 (현재 스크립트는 nightly 기준)
