#!/data/data/com.termux/files/usr/bin/bash
# =============================================================================
# ADAPTER: adapters/input/interactive.sh
# -----------------------------------------------------------------------------
# Input Adapter — 대화형 입력 (터미널 select)
# PROOT_DISTRO, PROOT_USER 등이 비어있을 때 사용자에게 물어봄
# =============================================================================

resolve_interactive_inputs() {
    # 사용자 이름
    if [ -z "${PROOT_USER:-}" ]; then
        PROOT_USER=$(ui_input "사용자 이름(id)을 입력하세요" "user")
        export PROOT_USER
    fi

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

    # 디스플레이 서버 — CLI/환경변수 미지정 시 대화형 선택, 기본 wayland
    # (stdout이 터미널일 때만 프롬프트 → curl|bash·터미널에선 묻고, 테스트/파이프에선 기본값)
    if [ -z "${DISPLAY_SERVER:-}" ]; then
        if [ -t 1 ]; then
            local display_choice
            display_choice=$(ui_select \
                "디스플레이 서버 선택" \
                "XFCE를 실행할 디스플레이 서버를 선택하세요:" \
                "wayland (labwc — 기본 권장)" \
                "x11 (termux-x11)")

            case "$display_choice" in
                x11*) DISPLAY_SERVER="x11" ;;
                *)    DISPLAY_SERVER="wayland" ;;
            esac
        fi
        DISPLAY_SERVER="${DISPLAY_SERVER:-wayland}"
        export DISPLAY_SERVER
    fi
}
