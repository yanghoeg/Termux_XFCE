#!/data/data/com.termux/files/usr/bin/bash
# =============================================================================
# ADAPTER: display_wayland.sh
# -----------------------------------------------------------------------------
# Output Adapter — Wayland(labwc) 디스플레이 서버 구현체 (실험적)
# ports/display.sh 계약의 Wayland 구현
#
# 표시면(display surface)은 여전히 Termux:X11 APK를 사용한다. 그 X11 화면
# 안에서 labwc 컴포지터를 X11 백엔드(WLR_BACKENDS=x11)로 nested 실행하고,
# XFCE를 `startxfce4 --wayland` 세션으로 붙인다. (XFCE 4.20+, labwc 필요)
#
# 참고: Android에는 네이티브 Wayland 소켓을 제공하는 안정적 APK가 없어
# Termux:X11을 표시면으로 재사용하는 것이 2025~2026 기준 가장 현실적이다.
# 물리 키보드 입력 등 일부 기능은 실험적이며 불안정할 수 있다.
# =============================================================================

display_emit_kill_session() {
    cat << 'FRAG'
_kill_display_session() {
    pkill -9 -x labwc 2>/dev/null || true
    pkill -9 -f "termux-x11" 2>/dev/null || true
    killall -9 Xwayland xfce4-session xfwm4 xfdesktop xfce4-panel \
        xfsettingsd xfconfd xfce4-power-manager xfce4-notifyd \
        xfce4-screensaver nimf pulseaudio dbus-daemon dbus-launch 2>/dev/null || true
    pkill -9 -f conky 2>/dev/null || true
    am force-stop com.termux.x11 2>/dev/null || true
    pkill -f termux-clipboard-sync 2>/dev/null || true
    local _w; for _w in 1 2 3; do
        pgrep -f "termux-x11" >/dev/null 2>&1 || break
        sleep 1
    done
    rm -f "${XDG_RUNTIME_DIR}/wayland-"* 2>/dev/null || true
    rm -f "${TMPDIR}/.X11-unix/X"* "${TMPDIR}/.X"*"-lock" 2>/dev/null || true
}
FRAG
}

display_emit_session_detect() {
    cat << 'FRAG'
# ─── Wayland 세션 중복 감지: labwc / xfce / termux-x11 중 하나라도 남아 있으면 ───
_EXISTING_LABWC=$(pgrep -x labwc 2>/dev/null | head -1 || echo "")
_EXISTING_XFCE=$(pgrep -x xfce4-session 2>/dev/null | head -1 || echo "")
_EXISTING_TX11=$(pgrep -f "termux-x11 :" 2>/dev/null | head -1 || echo "")

if [ -n "$_EXISTING_LABWC" ] || [ -n "$_EXISTING_XFCE" ] || [ -n "$_EXISTING_TX11" ]; then
    if [ -z "$_EXISTING_LABWC" ] || [ -z "$_EXISTING_XFCE" ]; then
        # stale/zombie 세션 — labwc 또는 xfce4-session 중 하나라도 없으면 자동 정리
        _kill_display_session
    else
        am start --user 0 -n com.termux.x11/com.termux.x11.MainActivity 2>/dev/null
        sleep 1

        choice=$(zenity --list \
            --title="XFCE 세션 중복 감지" \
            --text="⚠ Wayland 세션이 이미 실행 중입니다\n\n현황\n  • labwc      : 실행 중 (PID: ${_EXISTING_LABWC})\n  • XFCE4 세션 : 실행 중 (PID: ${_EXISTING_XFCE})\n  • Termux:X11 : 실행 중 (PID: ${_EXISTING_TX11:-없음})" \
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
# ─────────────────────────────────────────────────────────────────
FRAG
}

display_emit_server_start() {
    cat << 'FRAG'
_kill_display_session

termux-wake-lock

if ! command -v labwc >/dev/null 2>&1; then
    echo "ERROR: labwc가 설치되어 있지 않습니다. 'pkg install labwc' 후 다시 시도하세요." >&2
    exit 1
fi

# 표시면: Termux:X11 — 사용 가능한 디스플레이 번호 자동 탐색 (:0~:3)
TX11_PID=""
for _DTRY in 0 1 2 3; do
    termux-x11 :${_DTRY} 2>/dev/null &
    TX11_PID=$!
    sleep 2
    if [ -e "${TMPDIR}/.X11-unix/X${_DTRY}" ]; then
        break
    fi
    kill $TX11_PID 2>/dev/null || true
    TX11_PID=""
done

# Termux:X11 APK 열기
am start --user 0 -n com.termux.x11/com.termux.x11.MainActivity

# X 소켓이 생길 때까지 최대 10초 추가 대기
DISPLAY_NUM=""
for i in $(seq 1 10); do
    SOCK=$(ls "${TMPDIR}/.X11-unix/X"* 2>/dev/null | head -1)
    if [ -n "$SOCK" ]; then
        DISPLAY_NUM=$(basename "$SOCK" | sed 's/^X//')
        break
    fi
    sleep 1
done

if [ -z "$DISPLAY_NUM" ]; then
    echo "ERROR: Termux:X11 X 소켓을 찾을 수 없습니다. Termux:X11 앱을 먼저 열어주세요." >&2
    exit 1
fi

XDISPLAY=":${DISPLAY_NUM}"
echo "Detected DISPLAY=${XDISPLAY} (Wayland/labwc nested)"
FRAG
}

display_emit_session_launch() {
    cat << 'FRAG'

# Wayland: xfce4-session(--wayland)이 컴포지터로 labwc를 직접 기동한다.
# Termux:X11을 표시면으로 재사용하므로 labwc는 X11 백엔드(WLR_BACKENDS=x11)로
# nested 실행된다. GPU 환경변수(zink/llvmpipe 등)는 상위 블록에서 export됨.
env DISPLAY="$XDISPLAY" \
    XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR" \
    XDG_SESSION_TYPE=wayland \
    WLR_BACKENDS=x11 \
    WLR_LIBINPUT_NO_DEVICES=1 \
    WLR_NO_HARDWARE_CURSORS=1 \
    GDK_BACKEND="wayland,x11" \
    QT_QPA_PLATFORM="wayland;xcb" \
    MOZ_ENABLE_WAYLAND=1 \
    dbus-launch --exit-with-session startxfce4 --wayland labwc &
FRAG
}

display_emit_clipboard_sync() {
    cat << 'FRAG'
# Android ↔ Wayland 클립보드 동기화 (X11 소켓을 통한 termux-clipboard-sync)
# labwc가 Xwayland를 통해 X11 클립보드를 노출하므로 xclip 경로를 재사용한다.
if command -v termux-clipboard-get >/dev/null 2>&1 && command -v xclip >/dev/null 2>&1; then
    pkill -f termux-clipboard-sync 2>/dev/null || true
    DISPLAY="$XDISPLAY" termux-clipboard-sync &
fi
FRAG
}

display_get_packages() {
    # 표시면은 Termux:X11 재사용 + labwc/xwayland/wl-clipboard 추가
    echo "termux-x11-nightly labwc xwayland wl-clipboard xdotool xclip wmctrl"
}

display_setup_apk() {
    # Wayland 경로도 표시면으로 Termux:X11 APK가 필요하다.
    local arch
    arch=$(uname -m)
    local apk_name

    case "$arch" in
        aarch64) apk_name="app-arm64-v8a-debug.apk" ;;
        x86_64)  apk_name="app-x86_64-debug.apk" ;;
        *)
            ui_warn "아키텍처 ${arch}용 Termux-X11 APK를 지원하지 않습니다. 수동 설치하세요."
            return 0
            ;;
    esac

    _download_and_open_apk \
        "https://github.com/termux/termux-x11/releases/download/nightly/${apk_name}" \
        "$apk_name"
}
