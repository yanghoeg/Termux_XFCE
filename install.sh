#!/data/data/com.termux/files/usr/bin/bash
# =============================================================================
# Termux XFCE Desktop Installer
# Hexagonal Architecture: Ports & Adapters
#
# 사용법:
#   curl -sL https://raw.githubusercontent.com/yanghoeg/Termux_XFCE/main/install.sh | bash
#   또는
#   bash install.sh [--distro ubuntu|archlinux] [--user <name>] [--gpu]
#
# 아키텍처:
#   install.sh  → DI(어댑터 선택) → Domain 실행
#   ports/      → 계약 정의 (pkg_manager, ui)
#   adapters/   → 구현체 (pkg_termux, pkg_ubuntu, pkg_arch, ui_terminal, ui_zenity)
#   domain/     → 비즈니스 로직 (termux_env, xfce_env, proot_env, packages)
# =============================================================================

set -euo pipefail
IFS=$'\n\t'

# -----------------------------------------------------------------------------
# 0. 경로 설정
# -----------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
ARCH=$(uname -m)

# curl로 직접 실행 시 (파일이 없는 경우) 임시 디렉토리에 클론
if [ ! -d "$SCRIPT_DIR/domain" ]; then
    echo "[INFO] 저장소를 클론합니다..."
    local_dir="$HOME/.termux-xfce-installer"
    rm -rf "$local_dir"
    git clone --depth=1 -b "${INSTALL_BRANCH:-main}" --recurse-submodules \
        https://github.com/yanghoeg/Termux_XFCE.git "$local_dir"
    exec bash "$local_dir/install.sh" "$@"
fi

# -----------------------------------------------------------------------------
# 1. 종료 트랩
# -----------------------------------------------------------------------------
_on_exit() {
    local code=$?
    if [ "$code" -ne 0 ] && [ "$code" -ne 130 ]; then
        echo ""
        echo "[ERROR] 설치 실패 (exit: ${code}). 위 오류 메시지를 확인하세요." >&2
    fi
}
trap _on_exit EXIT

# -----------------------------------------------------------------------------
# 2. Ports 로드 (계약 정의)
# -----------------------------------------------------------------------------
source "$SCRIPT_DIR/ports/pkg_manager.sh"
source "$SCRIPT_DIR/ports/ui.sh"

# -----------------------------------------------------------------------------
# 3. Output Adapter 선택 — UI
# (DISPLAY, zenity 가용 여부로 자동 선택)
# -----------------------------------------------------------------------------
if [ -n "${DISPLAY:-}" ] && command -v zenity &>/dev/null; then
    source "$SCRIPT_DIR/adapters/output/ui_zenity.sh"
else
    source "$SCRIPT_DIR/adapters/output/ui_terminal.sh"
fi

# -----------------------------------------------------------------------------
# 4. Input Adapter — CLI 인자 파싱
# -----------------------------------------------------------------------------
source "$SCRIPT_DIR/adapters/input/cli.sh"
parse_cli_args "$@"

# -----------------------------------------------------------------------------
# 5. Input Adapter — 빠진 값 대화형으로 채우기
# -----------------------------------------------------------------------------
source "$SCRIPT_DIR/adapters/input/interactive.sh"
resolve_interactive_inputs

# -----------------------------------------------------------------------------
# 6. Output Adapter 선택 — Package Manager
# Termux native는 항상 pkg_termux.sh,
# proot 어댑터는 distro에 따라 추가 로드
# -----------------------------------------------------------------------------
source "$SCRIPT_DIR/adapters/output/pkg_termux.sh"

case "${PROOT_DISTRO:-}" in
    ubuntu)
        source "$SCRIPT_DIR/adapters/output/pkg_ubuntu.sh"
        ;;
    archlinux)
        source "$SCRIPT_DIR/adapters/output/pkg_arch.sh"
        ;;
    "")
        # native only — proot_exec 함수는 pkg_termux.sh의 stub 사용
        ;;
    *)
        echo "[ERROR] 지원하지 않는 distro: ${PROOT_DISTRO}" >&2
        exit 1
        ;;
esac

# -----------------------------------------------------------------------------
# 7. Domain 로드
# -----------------------------------------------------------------------------
source "$SCRIPT_DIR/domain/packages.sh"
source "$SCRIPT_DIR/domain/termux_env.sh"
source "$SCRIPT_DIR/domain/xfce_env.sh"
source "$SCRIPT_DIR/domain/proot_env.sh"

# -----------------------------------------------------------------------------
# 8. 아키텍처 확인
# -----------------------------------------------------------------------------
if [[ "$ARCH" != "aarch64" ]]; then
    ui_warn "이 스크립트는 aarch64(arm64) 기기에 최적화되어 있습니다. 현재: $ARCH"
fi

# -----------------------------------------------------------------------------
# 9. 설치 설정 저장 (prun, cp2menu가 읽음)
# -----------------------------------------------------------------------------
mkdir -p "$HOME/.config/termux-xfce"
cat > "$HOME/.config/termux-xfce/config" << EOF
# Termux XFCE 설치 설정 — 자동 생성 ($(date '+%Y-%m-%d'))
PROOT_DISTRO="${PROOT_DISTRO:-}"
PROOT_USER="${PROOT_USER:-}"
INSTALL_ARCH="$ARCH"
# proot 인터랙티브 셸: bash(기본) 또는 zsh (proot에 zsh 설치 후 변경 가능)
PROOT_SHELL="${PROOT_SHELL:-bash}"
EOF

# -----------------------------------------------------------------------------
# 10. Storage 권한
# -----------------------------------------------------------------------------
if [ "${PROOT_ONLY:-false}" != "true" ] && [ ! -d "$HOME/storage" ]; then
    ui_info "저장소 접근 권한을 요청합니다..."
    termux-setup-storage
    sleep 2
fi

# -----------------------------------------------------------------------------
# 11. 실행 — Termux Native
# --proot-only 플래그 사용 시 생략 (추가 distro 설치 시 중복 방지)
# -----------------------------------------------------------------------------
if [ "${PROOT_ONLY:-false}" != "true" ]; then
    ui_info "=== [1/4] Termux 기본 환경 설정 ==="
    setup_termux_base

    ui_info "=== [2/4] XFCE 패키지 및 테마 설치 ==="
    setup_xfce_packages
    setup_xfce_theme
    setup_xfce_fonts
    setup_xfce_wallpaper
    # zsh가 기본 쉘이면 fancybash 건너뜀 (p10k가 대체)
    # Termux의 login shell은 ~/.termux/shell 심볼릭 링크로 관리됨
    # ($SHELL은 현재 스크립트 세션 값이라 chsh 직후 갱신되지 않고, /etc/passwd는 Termux에 없음)
    _login_shell=$(readlink "$HOME/.termux/shell" 2>/dev/null || echo "")
    if [[ "$_login_shell" != */zsh ]]; then
        setup_xfce_fancybash "$PROOT_USER"
    fi
    unset _login_shell
    setup_xfce_autostart

    ui_info "=== [3/4] 한글 입력기 설치 ==="
    setup_termux_korean

    ui_info "=== [4/4] 유틸리티 설정 (shortcuts, prun, cp2menu) ==="
    setup_termux_shortcuts

    # GPU 가속 (선택)
    if [ "${INSTALL_GPU:-false}" = "true" ]; then
        setup_termux_gpu
    fi
    if [ "${INSTALL_GPU_DEV:-false}" = "true" ]; then
        setup_termux_gpu_dev
    fi
else
    ui_info "[--proot-only] Termux native 설정 생략 — proot 환경만 구성합니다."
fi

# -----------------------------------------------------------------------------
# 12. 실행 — proot (선택)
# -----------------------------------------------------------------------------
if [ "${SKIP_PROOT:-false}" != "true" ] && [ -n "${PROOT_DISTRO:-}" ]; then
    ui_info "=== [proot] ${PROOT_DISTRO} 환경 구성 ==="

    setup_proot_install
    setup_proot_update
    setup_proot_user
    setup_proot_base_packages
    setup_proot_korean
    setup_proot_env
    setup_proot_timezone
    setup_proot_fancybash
    setup_proot_hardware_accel
    setup_proot_cursor_theme
    setup_proot_conky

    # proot alias (bash.bashrc + ~/.zshrc)
    # PROOT_SHELL: config에서 읽어 인터랙티브 셸 결정 (bash|zsh, 기본 bash)
    _proot_alias="alias ${PROOT_DISTRO}='proot-distro login ${PROOT_DISTRO} --user ${PROOT_USER} --shared-tmp -- env -u LD_PRELOAD \${PROOT_SHELL:-bash} --login'"
    _bashrc="$PREFIX/etc/bash.bashrc"
    grep -q "alias ${PROOT_DISTRO}=" "$_bashrc" 2>/dev/null || echo "$_proot_alias" >> "$_bashrc"
    if command -v zsh &>/dev/null && [ -f "$HOME/.zshrc" ]; then
        grep -q "alias ${PROOT_DISTRO}=" "$HOME/.zshrc" 2>/dev/null || echo "$_proot_alias" >> "$HOME/.zshrc"
    fi
fi

# -----------------------------------------------------------------------------
# 내부 함수 — 호출 전에 정의
# -----------------------------------------------------------------------------
_install_termux_x11_apk() {
    local apk_name

    case "$ARCH" in
        aarch64) apk_name="app-arm64-v8a-debug.apk" ;;
        x86_64)  apk_name="app-x86_64-debug.apk" ;;
        *)
            ui_warn "아키텍처 ${ARCH}용 Termux-X11 APK를 지원하지 않습니다. 수동 설치하세요."
            return 0
            ;;
    esac

    local apk_url="https://github.com/termux/termux-x11/releases/download/nightly/${apk_name}"
    local dl_dir="$HOME/storage/downloads"
    local apk_path="${dl_dir}/${apk_name}"

    # storage/downloads가 없으면 HOME에 저장 (termux-setup-storage 미실행 환경)
    if [ ! -d "$dl_dir" ]; then
        dl_dir="$HOME"
        apk_path="${dl_dir}/${apk_name}"
        ui_warn "storage/downloads 없음 — ${apk_path} 에 저장합니다."
    fi

    if [ -f "$apk_path" ]; then
        ui_warn "APK가 이미 다운로드되어 있습니다: ${apk_path}"
    else
        wget -q "$apk_url" -O "$apk_path"
    fi

    termux-open "$apk_path" 2>/dev/null || \
        ui_warn "APK 자동 열기 실패 — 수동으로 설치하세요: ${apk_path}"
}

# -----------------------------------------------------------------------------
# 13. Termux-X11 APK 설치 (proot-only 시 생략)
# -----------------------------------------------------------------------------
if [ "${PROOT_ONLY:-false}" != "true" ]; then
    ui_info "=== Termux-X11 APK 설치 ==="
    _install_termux_x11_apk
fi

# -----------------------------------------------------------------------------
# 14. 완료
# -----------------------------------------------------------------------------
ui_info "=================================================="
ui_info "설치가 완료되었습니다!"
ui_info ""
ui_info "시작하려면: startXFCE"
if [ -n "${PROOT_DISTRO:-}" ]; then
    ui_info "proot 진입: ${PROOT_DISTRO} (또는 prun <명령>)"
fi
ui_info "앱 설치: app-installer"
ui_info "=================================================="

termux-reload-settings
