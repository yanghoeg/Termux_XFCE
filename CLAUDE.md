# CLAUDE.md — Termux XFCE 프로젝트 컨텍스트

## 프로젝트 개요

Android 기기(Termux)에서 XFCE 데스크탑 환경 + proot-distro(Ubuntu/Arch 선택)를 자동 설치하는 Bash 스크립트 모음.
**헥사고날 아키텍처(Ports & Adapters)** 적용.

## 실행 환경

- **타겟 환경**: Android 기기의 Termux (`/data/data/com.termux/...` 경로)
- **개발/편집 환경**: Linux PC (`/home/yanghoeg/code/work/linux/Termux_XFCE/`) 및 기기 Termux 내 Claude Code
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
│   ├── proot_env.sh              ← proot 환경
│   └── locale_ko.sh              ← 한글 로케일 — LD_PRELOAD gettext 훅
├── tests/
│   ├── framework.sh, mocks.sh, run_tests.sh, autopilot.sh
│   ├── test_domain_{termux,xfce,proot,locale_ko}.sh
│   ├── test_{ports,adapters,adapters_deb,app_installer}.sh
│   ├── test_{e2e_install,input_interactive,install_matrix}.sh
│   ├── test_prun_ld_preload.sh
│   ├── batch_test_appinstaller.sh
│   └── INSTALL_MATRIX.md
└── app-installer/                ← submodule
```

## App-Installer 연동

- 별도 Git repo 유지 + Git Submodule로 연결 (독립 업데이트 가능) — 변경은 서브모듈에서 커밋한 뒤
  부모에서 포인터 커밋
- 동일 헥사고날 구조(ports/adapters/domain/installers) 적용 완료. distro별 패키지명 차이는
  `adapters/output/pkg_{termux,ubuntu,arch}.sh` 어댑터가 흡수하고, `PROOT_DISTRO` env var로 선택
- 앱은 Termux native 우선 — 레지스트리(`domain/apps.sh`) 설명에 설치 위치(native/proot) 표기
- **다운로드 무결성**: 외부 파일(.deb/tarball/zip/exe)은 버전 핀 + sha256 상수, `lib/fetch.sh`의
  `fetch_verified` 경유. `releases/latest`·GitHub API "최신" 조회 금지 (예외: `llama_cpp.sh`
  사용자 선택 모델). 버전 올릴 때 `sha256sum`으로 상수 함께 갱신
- proot 내부 한글 IME(로케일 + nimf/fcitx5)는 app-installer `korean_proot` 항목
  (2026-09-05 부모 `domain/`에서 이관)
- 테스트: `app-installer/tests/test_{domain_apps,adapters,ports,fetch,proot_path}.sh` 개별 실행
  (run_tests.sh 없음). `test_nimf_*_real.sh`는 실기기 전용
- Claude Code 핀 상향/롤백 이력: `app-installer/docs/claude-code-login-regression.md`

## 남은 TODO (실기기 검증 — PC에서는 mock/정적 검사만 가능)

1. `prun` GPU env(`/etc/profile.d/termux-xfce-env.sh`) 전파
2. zsh + Powerlevel10k 설정 순서
3. Termux native nimf `pgrep` 가드
4. Claude Code 2.1.261 `/login` (회귀 시 `app-installer/docs/claude-code-login-regression.md` 롤백 절차)
5. `korean_proot` 설치(Ubuntu nimf .deb / Arch AUR→fcitx5) + `.profile` `export` 로케일이 GUI 앱에 전파되는지

## 주의사항

- `set -euo pipefail` 사용 중 — 오류 시 즉시 종료
- `local` 키워드는 bash 함수 내에서만 유효 (함수 밖에서 쓰면 에러)
- Termux 패키지: `--force-confold` 옵션으로 설정 파일 충돌 방지
- **패키지 배치 규칙**: `PKGS_TERMUX_*`(항상 설치)에는 **termux-main + x11-repo** 패키지가
  들어갈 수 있다 — XFCE/firefox/yad 자체가 x11-repo 제공이기 때문이다. `domain/termux_env.sh`의
  `_setup_termux_repos()`는 설치 초입에 **x11-repo만** 켠다 — tur-repo/root-repo는 여기서
  켜지 않는다.
  단 **tur-repo/root-repo 패키지는 반드시 App Installer 선택 항목**으로만 넣는다 — TUR/root는
  커뮤니티 빌드·소규모 저장소라 base에 넣으면 저장소 장애가 설치 전체를 깨뜨린다.
  선택 항목 설치기 안에서는 `termux_pkg_enable_repo <repo>`로 저장소를 먼저 켠다.
- **새 패키지 추가 시 오라클 대조 필수** (패키지명 추측 금지):
  `curl -s https://packages.termux.dev/apt/termux-main/dists/stable/main/binary-aarch64/Packages | grep '^Package: '`
  (x11 = `termux-x11/dists/x11/main/binary-aarch64/Packages`,
   root = `termux-root/dists/root/stable/binary-aarch64/Packages`,
   tur = `https://tur.kcubeterm.com/dists/tur-packages/tur/binary-aarch64/Packages`)
- `proot_exec`는 `PROOT_DISTRO`, `PROOT_USER` 환경변수 필요
- **디스플레이 서버 추상화**: `ports/display.sh` 포트로 X11/Wayland 분리
  - X11 어댑터(`display_x11.sh`): Termux:X11 APK + `termux-x11` 프로세스
  - Wayland 어댑터(`display_wayland.sh`): labwc 기반 (구현됨)
  - `--display x11|wayland` CLI 옵션 / `DISPLAY_SERVER` 환경변수 / 미지정 시 대화형 선택
  - **설치 시 하나 고정**: 선택된 서버의 런처(`startXFCE`)만 생성 (기본: x11, wayland는 실험적)
  - X11: `termux-x11 :N` → 소켓 자동 감지 (`${TMPDIR}/.X11-unix/X*`)
- **기본 쉘은 zsh + Powerlevel10k**: `domain/termux_env.sh` `_setup_zsh_p10k()`가 설치 시 자동 구성
  - RC 파일 수정은 bash/zsh 양쪽 모두 반영해야 함 (`_rc_targets()` + `_append_to_rc()` 참조)
- **Wine 백엔드는 2종 공존**: `app-installer/lib/wine_backend.sh`가 선택 로직을 소유
  - `$PREFIX/bin/wine` = 디스패처, `wine-box64` / `wine-hangover` = 실제 래퍼
  - 활성 백엔드는 `$HOME/.config/termux-xfce/wine-backend` (config 파일은 install.sh가
    덮어쓰므로 별도 파일), 사용자 전환은 `wine-backend` CLI
  - WINEPREFIX가 백엔드별로 분리됨 — Wine 앱은 `wine_exec_shell`로 실행하고
    스니펫 안에서 `$WINEPREFIX`를 쓸 것 (`$HOME/.wine` 하드코딩 금지)
- **부팅 자동 기동**: `termux-services`(runit) + Termux:Boot APK,
  `~/.termux/boot/start-services`는 `_setup_termux_boot_script()`가 생성 (기존 파일 보존)
