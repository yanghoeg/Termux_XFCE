#!/data/data/com.termux/files/usr/bin/bash
# =============================================================================
# ADAPTER: display_wayland.sh
# -----------------------------------------------------------------------------
# Output Adapter — Wayland (labwc) 디스플레이 서버 구현체 (스텁)
# ports/display.sh 계약의 Wayland 구현 — 아직 미구현
# =============================================================================

display_emit_kill_session() {
    cat << 'FRAG'
_kill_display_session() {
    pkill -9 labwc 2>/dev/null || true
    killall -9 Xwayland xfce4-session xfwm4 xfdesktop xfce4-panel \
        xfsettingsd xfconfd xfce4-power-manager xfce4-notifyd \
        xfce4-screensaver nimf pulseaudio dbus-daemon dbus-launch 2>/dev/null || true
    pkill -9 -f conky 2>/dev/null || true
    pkill -f termux-clipboard-sync 2>/dev/null || true
    rm -f "${XDG_RUNTIME_DIR}/wayland-"* 2>/dev/null || true
}
FRAG
}

display_emit_session_detect() {
    cat << 'FRAG'
# Wayland 세션 중복 감지 — TODO
_EXISTING_LABWC=$(pgrep -x labwc 2>/dev/null | head -1 || echo "")
_EXISTING_XFCE=$(pgrep -x xfce4-session 2>/dev/null | head -1 || echo "")

if [ -n "$_EXISTING_LABWC" ] || [ -n "$_EXISTING_XFCE" ]; then
    if [ -z "$_EXISTING_LABWC" ] || [ -z "$_EXISTING_XFCE" ]; then
        _kill_display_session
    else
        choice=$(zenity --list \
            --title="XFCE 세션 중복 감지" \
            --text="⚠ Wayland 세션이 이미 실행 중입니다" \
            --column="동작" --height=320 \
            "기존 세션으로 이동" \
            "세션 종료 후 재시작" \
            "세션 전체 종료" \
            2>/dev/null || true)

        case "$choice" in
            "기존 세션으로 이동") exit 0 ;;
            "세션 종료 후 재시작") _kill_display_session ;;
            "세션 전체 종료")
                _kill_display_session
                termux-wake-unlock 2>/dev/null || true
                exit 0
                ;;
            *) exit 0 ;;
        esac
    fi
fi
FRAG
}

display_emit_server_start() {
    cat << 'FRAG'
_kill_display_session

termux-wake-lock

# Wayland/labwc — TODO: 구현 예정
echo "[ERROR] Wayland 디스플레이 서버는 아직 구현되지 않았습니다." >&2
echo "[ERROR] --display x11 을 사용하세요." >&2
exit 1

XDISPLAY=":0"
FRAG
}

display_emit_clipboard_sync() {
    cat << 'FRAG'
# Wayland 클립보드 동기화 — TODO
if command -v termux-clipboard-get >/dev/null 2>&1 && command -v wl-copy >/dev/null 2>&1; then
    pkill -f termux-clipboard-sync 2>/dev/null || true
    # TODO: wl-clipboard 기반 동기화 구현
fi
FRAG
}

display_get_packages() {
    echo "labwc wl-clipboard"
}

display_setup_apk() {
    ui_info "Wayland 백엔드 — 별도 APK 불필요"
}
