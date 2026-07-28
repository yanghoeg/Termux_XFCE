#!/data/data/com.termux/files/usr/bin/bash
# =============================================================================
# ADAPTER: adapters/input/interactive.sh
# -----------------------------------------------------------------------------
# Input Adapter — 대화형 입력 (터미널 select)
# PROOT_DISTRO, PROOT_USER 등이 비어있을 때 사용자에게 물어봄
# =============================================================================

resolve_interactive_inputs() {
    # proot 설치 여부
    if [ "${SKIP_PROOT:-false}" = "false" ] && [ -z "${PROOT_DISTRO:-}" ]; then
        local distro_choice
        distro_choice=$(ui_select \
            "proot-distro 선택" \
            "설치할 Linux 환경을 선택하세요 (Termux native XFCE는 항상 설치됩니다):" \
            "ubuntu" \
            "archlinux" \
            "없음 (Termux native만)")

        case "$distro_choice" in
            "없음 (Termux native만)")
                SKIP_PROOT=true
                PROOT_DISTRO=""
                ;;
            *)
                PROOT_DISTRO="$distro_choice"
                ;;
        esac
        export PROOT_DISTRO SKIP_PROOT
    fi

    # proot를 실제로 설치할 때만 사용자 이름을 묻는다.
    if [ "${SKIP_PROOT:-false}" != "true" ] && [ -z "${PROOT_USER:-}" ]; then
        PROOT_USER=$(ui_input "사용자 이름(id)을 입력하세요" "user")
        export PROOT_USER
    fi

    # 디스플레이 서버 — CLI/환경변수 미지정 시 대화형 선택, 기본 x11
    # (stdout이 터미널일 때만 프롬프트 → curl|bash·터미널에선 묻고, 테스트/파이프에선 기본값)
    # wayland(labwc)는 실험적 — 한글 입력·스크린샷 등 다수 이슈가 있어 x11을 기본으로 둔다.
    if [ -z "${DISPLAY_SERVER:-}" ]; then
        if [ "${INSTALL_NONINTERACTIVE:-false}" != true ] && [ -t 1 ]; then
            local display_choice
            display_choice=$(ui_select \
                "디스플레이 서버 선택" \
                "XFCE를 실행할 디스플레이 서버를 선택하세요:" \
                "x11 (termux-x11 — 기본 권장)" \
                "wayland (labwc — 실험적, 이슈 많음)")

            case "$display_choice" in
                wayland*) DISPLAY_SERVER="wayland" ;;
                *)        DISPLAY_SERVER="x11" ;;
            esac
        fi
        DISPLAY_SERVER="${DISPLAY_SERVER:-x11}"
        export DISPLAY_SERVER
    fi

    if declare -F validate_install_inputs >/dev/null 2>&1; then
        validate_install_inputs true
    fi
}
