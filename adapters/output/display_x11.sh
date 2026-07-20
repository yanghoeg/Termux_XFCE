#!/data/data/com.termux/files/usr/bin/bash
# =============================================================================
# ADAPTER: display_x11.sh
# -----------------------------------------------------------------------------
# Output Adapter — Termux:X11 디스플레이 서버 구현체
# ports/display.sh 계약의 X11 구현
# =============================================================================

display_emit_kill_session() {
    cat << 'FRAG'
_kill_display_session() {
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
    rm -f "${TMPDIR}/.X11-unix/X"* "${TMPDIR}/.X"*"-lock" 2>/dev/null || true
}
FRAG
}

display_emit_session_detect() {
    cat << 'FRAG'
# ─── X11 세션 중복 감지: X 소켓 또는 세션 프로세스가 남아 있으면 다이얼로그 ───
_EXISTING_SOCK=$(ls "${TMPDIR}/.X11-unix/X"* 2>/dev/null | head -1)
_EXISTING_XFCE=$(pgrep -x xfce4-session 2>/dev/null | head -1 || echo "")
_EXISTING_TX11=$(pgrep -f "termux-x11 :" 2>/dev/null | head -1 || echo "")

if [ -n "$_EXISTING_SOCK" ] || [ -n "$_EXISTING_XFCE" ] || [ -n "$_EXISTING_TX11" ]; then
    if [ -z "$_EXISTING_TX11" ] || [ -z "$_EXISTING_XFCE" ]; then
        # stale/zombie 세션 — termux-x11 또는 xfce4-session 중 하나라도 없으면 자동 정리
        _kill_display_session
    else
        # live 세션 — APK를 포그라운드로 올린 뒤 다이얼로그 표시
        if [ -n "$_EXISTING_SOCK" ]; then
            _NUM=$(basename "$_EXISTING_SOCK" | sed 's/^X//')
            export DISPLAY=":${_NUM}"
        fi

        am start --user 0 -n com.termux.x11/com.termux.x11.MainActivity 2>/dev/null
        sleep 1

        XFCE_STATUS="실행 중 (PID: ${_EXISTING_XFCE})"
        TX11_STATUS="실행 중 (PID: ${_EXISTING_TX11})"
        DBUS_COUNT=$(pgrep dbus-daemon 2>/dev/null | wc -l | tr -d ' ')

        choice=$(zenity --list \
            --title="XFCE 세션 중복 감지" \
            --text="⚠ X11 세션이 이미 실행 중입니다\n\n현황\n  • XFCE4 세션 : ${XFCE_STATUS}\n  • Termux:X11 : ${TX11_STATUS}\n  • dbus 수     : ${DBUS_COUNT:-0}개" \
            --column="동작" --height=320 \
            "기존 세션으로 이동" \
            "세션 종료 후 재시작" \
            "세션 전체 종료" \
            2>/dev/null || true)

        case "$choice" in
            "기존 세션으로 이동")
                exit 0
                ;;
            "세션 종료 후 재시작")
                _kill_display_session
                ;;
            "세션 전체 종료")
                _kill_display_session
                termux-wake-unlock 2>/dev/null || true
                exit 0
                ;;
            *)
                # 취소(ESC/닫기) — 아무것도 안 함
                exit 0
                ;;
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

# X 서버 실행 — 사용 가능한 디스플레이 번호 자동 탐색 (:0~:3)
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
echo "Detected DISPLAY=${XDISPLAY}"
FRAG
}

display_emit_clipboard_sync() {
    cat << 'FRAG'
# Android ↔ X11 클립보드 동기화
if command -v termux-clipboard-get >/dev/null 2>&1 && command -v xclip >/dev/null 2>&1; then
    pkill -f termux-clipboard-sync 2>/dev/null || true
    DISPLAY="$XDISPLAY" termux-clipboard-sync &
fi
FRAG
}

display_get_packages() {
    echo "termux-x11-nightly xdotool xclip wmctrl"
}

display_setup_apk() {
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
