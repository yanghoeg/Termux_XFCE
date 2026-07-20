#!/data/data/com.termux/files/usr/bin/bash
# =============================================================================
# ADAPTER: script_builder_zenity.sh
# -----------------------------------------------------------------------------
# Output Adapter — zenity 기반 런타임 스크립트 빌더
# script_builder.sh 포트의 zenity 구현체
# 생성되는 스크립트: startXFCE, kill_display_session, cp2menu
#
# display_emit_* 함수(display 포트)를 조립하여 런타임 스크립트 생성.
# 공유 로직(GPU/PulseAudio/로케일)은 이 파일에 인라인으로 유지.
# =============================================================================

script_build_start_xfce() {
    local output="$1"

    {
        # ── 1. Shebang + 환경 초기화 (공유) ──
        cat << 'HEADER'
#!/data/data/com.termux/files/usr/bin/bash
# shortcut 실행 시 TMPDIR 미상속 방지
TMPDIR="${TMPDIR:-/data/data/com.termux/files/usr/tmp}"

# XDG runtime dir (dbus 요구: mode 700 user-private) — shortcut은 rc를 source하지 않음
XDG_RUNTIME_DIR="${PREFIX:-/data/data/com.termux/files/usr}/var/run/user/$(id -u)"
mkdir -p "$XDG_RUNTIME_DIR" 2>/dev/null
chmod 700 "$XDG_RUNTIME_DIR" 2>/dev/null
export XDG_RUNTIME_DIR

HEADER

        # ── 2. 세션 종료 함수 (display 어댑터) ──
        display_emit_kill_session

        # ── 3. 세션 중복 감지 (display 어댑터) ──
        display_emit_session_detect

        # ── 4. 디스플레이 서버 시작 (display 어댑터) ──
        # _kill_display_session + wake-lock + 서버 시작 + XDISPLAY 설정
        display_emit_server_start

        # ── 5. PulseAudio 시작 (공유) ──
        cat << 'PULSE'

_PA_PRELOAD=""
[ -f /system/lib64/libskcodec.so ] && _PA_PRELOAD="/system/lib64/libskcodec.so"

LD_PRELOAD="$_PA_PRELOAD" pulseaudio --start \
    --load="module-native-protocol-tcp auth-ip-acl=127.0.0.1 auth-anonymous=1" \
    --exit-idle-time=-1

LD_PRELOAD="$_PA_PRELOAD" pacmd load-module \
    module-native-protocol-tcp auth-ip-acl=127.0.0.1 auth-anonymous=1 2>/dev/null || true

PULSE

        # ── 6. 한글 로케일 (공유) ──
        cat << 'LOCALE'
# 한글 로케일 — force_gettext.so가 설치되어 있으면 자동 적용
_PREFIX="/data/data/com.termux/files/usr"
if [ -f "$_PREFIX/lib/force_gettext.so" ]; then
    export LANG="ko_KR.UTF-8"
    export LANGUAGE="ko_KR:ko:en_US:en"
    export FORCE_TEXTDOMAINDIR="$_PREFIX/share/locale"
    export FALLBACK_DOMAINS="__KOREAN_FALLBACK_DOMAINS__"
    export XDG_DATA_DIRS="$_PREFIX/share${XDG_DATA_DIRS:+:$XDG_DATA_DIRS}"
    QT_TRANSLATIONS_PATH="$_PREFIX/share/qt6/translations:$_PREFIX/share/qt/translations${QT_TRANSLATIONS_PATH:+:$QT_TRANSLATIONS_PATH}"
    export QT_TRANSLATIONS_PATH
    export KDE_LANG=ko QT_LOCALE_OVERRIDE=ko_KR
    case ":${LD_PRELOAD-}:" in *:"$_PREFIX/lib/force_gettext.so":*) ;; *)
      export LD_PRELOAD="$_PREFIX/lib/force_gettext.so${LD_PRELOAD:+:$LD_PRELOAD}";; esac
fi

LOCALE

        # ── 7. nimf 한글 입력기 (공유) ──
        cat << 'NIMF'
# nimf 입력기 — 설치되어 있으면 세션 전체에 적용
if command -v nimf >/dev/null 2>&1; then
    export XMODIFIERS="@im=nimf"
    export GTK_IM_MODULE=nimf
    export QT_IM_MODULE=nimf
fi

NIMF

        # ── 8. 클립보드 동기화 (display 어댑터) ──
        display_emit_clipboard_sync

        # ── 9. GPU 감지 + XFCE 세션 시작 (공유) ──
        cat << 'GPU_SESSION'

GPU_MODEL=$(cat /sys/class/kgsl/kgsl-3d0/gpu_model 2>/dev/null || echo "")

if [ -n "$GPU_MODEL" ]; then
    # Adreno GPU 감지 → Zink(OpenGL→Vulkan) + Turnip
    # xfwm4 컴포지터가 검은 화면 유발 시:
    #   설정 → 창관리자(작업) → 컴포지터 → '화면 컴포지팅 활성화' 해제
    env DISPLAY="$XDISPLAY" \
        PULSE_SERVER=tcp:127.0.0.1:4713 \
        MESA_LOADER_DRIVER_OVERRIDE=zink \
        TU_DEBUG=noconform \
        ZINK_DESCRIPTORS=lazy \
        MESA_NO_ERROR=1 \
        MESA_GL_VERSION_OVERRIDE=4.6COMPAT \
        MESA_GLES_VERSION_OVERRIDE=3.2 \
        MESA_VK_WSI_PRESENT_MODE=fifo \
        GSK_RENDERER=cairo \
        dbus-launch --exit-with-session xfce4-session &
else
    # llvmpipe 소프트웨어 폴백 (KGSL 미감지)
    env DISPLAY="$XDISPLAY" \
        PULSE_SERVER=tcp:127.0.0.1:4713 \
        MESA_NO_ERROR=1 \
        MESA_GL_VERSION_OVERRIDE=4.6COMPAT \
        MESA_GLES_VERSION_OVERRIDE=3.2 \
        LIBGL_ALWAYS_SOFTWARE=1 \
        GSK_RENDERER=cairo \
        dbus-launch --exit-with-session xfce4-session &
fi
GPU_SESSION
    } > "$output"

    sed -i "s|__KOREAN_FALLBACK_DOMAINS__|${_KOREAN_FALLBACK_DOMAINS:-}|" "$output"
}

script_build_kill_display() {
    local output="$1"

    {
        cat << 'HEADER'
#!/data/data/com.termux/files/usr/bin/bash
TMPDIR="${TMPDIR:-/data/data/com.termux/files/usr/tmp}"

HEADER

        display_emit_kill_session

        cat << 'BODY'

if pgrep -f '[a]pt|[a]pt-get|[d]pkg|[n]ala' > /dev/null; then
    zenity --info --text="패키지 설치 중입니다. 완료 후 시도하세요."
    exit 1
fi

# 디스플레이 세션 종료 전 존재 여부 확인
XFCE_PID=$(pgrep -x xfce4-session 2>/dev/null | head -1)
DISPLAY_PID=$(pgrep -f "termux-x11\|labwc" 2>/dev/null | head -1)

if [ -z "$XFCE_PID" ] && [ -z "$DISPLAY_PID" ]; then
    zenity --info --text="실행 중인 세션을 찾을 수 없습니다."
    exit 0
fi

_kill_display_session
termux-wake-unlock 2>/dev/null || true
BODY
    } > "$output"
}

# 하위 호환 별칭
script_build_kill_x11() { script_build_kill_display "$@"; }

script_build_cp2menu() {
    local output="$1"

    cat > "$output" << 'EOF'
#!/data/data/com.termux/files/usr/bin/bash
CONFIG="$HOME/.config/termux-xfce/config"
[ -f "$CONFIG" ] && source "$CONFIG"

DISTRO="${PROOT_DISTRO:-ubuntu}"
ROOTFS="$PREFIX/var/lib/proot-distro/installed-rootfs/$DISTRO"
USERNAME=$(ls "$ROOTFS/home/" 2>/dev/null | head -1)
USERNAME="${USERNAME:-user}"

action=$(zenity --list --title="cp2menu" --text="작업 선택:" \
    --radiolist --column="" --column="Action" \
    TRUE "Copy .desktop file" FALSE "Remove .desktop file")

[ -z "$action" ] && exit 0

if [[ "$action" == "Copy .desktop file" ]]; then
    selected=$(zenity --file-selection --title=".desktop 파일 선택" \
        --file-filter="*.desktop" \
        --filename="$ROOTFS/usr/share/applications")
    [ -z "$selected" ] && exit 0

    filename=$(basename "$selected")
    cp "$selected" "$PREFIX/share/applications/"
    app_name=$(grep -m1 '^Name=' "$PREFIX/share/applications/$filename" | cut -d= -f2-)
    app_name="${app_name:-App}"
    # sed 구분자(|)와 작은따옴표 충돌 방지
    app_name="${app_name//\\/\\\\}"
    app_name="${app_name//\'/\'\\\'\'}"
    app_name="${app_name//&/\\&}"
    app_name="${app_name//|/\\|}"
    sed -i "s|^Exec=\(.*\)$|Exec=bash -c \"prun-gui '${app_name}' -- \1 </dev/null >/dev/null 2>\&1 \&\"|" \
        "$PREFIX/share/applications/$filename"
    zenity --info --text="복사 완료: $filename"

elif [[ "$action" == "Remove .desktop file" ]]; then
    selected=$(zenity --file-selection --title="제거할 .desktop 선택" \
        --file-filter="*.desktop" \
        --filename="$PREFIX/share/applications")
    [ -z "$selected" ] && exit 0

    rm "$selected"
    zenity --info --text="제거 완료: $(basename "$selected")"
fi
EOF
}
