#!/data/data/com.termux/files/usr/bin/bash
# Installed as termux-xfce-anland-session. Owns only the children started here.
set -euo pipefail
if [ "${1:-}" != --dbus ]; then
    exec dbus-run-session -- bash "$0" --dbus
fi

: "${PREFIX:?}" "${TMPDIR:?}" "${XDG_RUNTIME_DIR:?}" "${SESSION_STATE_DIR:?}"
printf '%s\t%s\n' "$$" termux-xfce-anland-session > "$SESSION_STATE_DIR/anland-worker.pid"
_children=()
_owned_files=()
_daemon_started=false
_cleanup() {
    local rc=$? pid i running file
    trap - EXIT INT TERM
    for pid in "${_children[@]}"; do kill "$pid" 2>/dev/null || true; done
    for ((i=0; i<20; i++)); do
        running=false
        for pid in "${_children[@]}"; do kill -0 "$pid" 2>/dev/null && running=true; done
        [ "$running" = false ] && break
        sleep 0.1
    done
    for pid in "${_children[@]}"; do
        kill -0 "$pid" 2>/dev/null && kill -9 "$pid" 2>/dev/null || true
        wait "$pid" 2>/dev/null || true
    done
    for file in "${_owned_files[@]}"; do rm -f "$SESSION_STATE_DIR/$file"; done
    rm -f "$SESSION_STATE_DIR/anland-ready" "$SESSION_STATE_DIR/anland-worker.pid"
    if [ "$_daemon_started" = true ]; then
        rm -f "$ANLAND_SOCKET"
        am force-stop com.anland.termux 2>/dev/null || true
    fi
    termux-wake-unlock 2>/dev/null || true
    exit "$rc"
}
trap _cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

_spawn() {
    local file="$1" expected="$2"; shift 2
    "$@" &
    _last_pid=$!
    _children+=("$_last_pid")
    _owned_files+=("$file")
    printf '%s\t%s\n' "$_last_pid" "$expected" > "$SESSION_STATE_DIR/$file"
}
_wait_socket() {
    local socket="$1" pid="$2" i
    for ((i=0; i<40; i++)); do
        kill -0 "$pid" 2>/dev/null || return 1
        [ -S "$socket" ] && return 0
        sleep 0.1
    done
    echo "ERROR: 소켓 생성 실패: $socket" >&2
    return 1
}

# Discard nested-X11 and Zink settings inherited from an older startXFCE or rc.
unset DISPLAY WAYLAND_DISPLAY WLR_BACKENDS GDK_BACKEND QT_QPA_PLATFORM
unset MESA_LOADER_DRIVER_OVERRIDE GALLIUM_DRIVER LIBGL_ALWAYS_SOFTWARE
unset MESA_VK_WSI_PRESENT_MODE MESA_GL_VERSION_OVERRIDE MESA_GLES_VERSION_OVERRIDE
unset TU_DEBUG ZINK_DESCRIPTORS GTK_IM_MODULE QT_IM_MODULE XMODIFIERS
export ANLAND=1 ANLAND_NO_DRM_DEVICE=1 EGL_PLATFORM=surfaceless
export ANLAND_SOCKET="$TMPDIR/anland/display_daemon.sock"
export MESA_LOADER_DRIVER_OVERRIDE=kgsl TURNIP_KMD=kgsl GALLIUM_DRIVER=freedreno
export FD_FORCE_KGSL=1 XWAYLAND_FORCE_KGSL_SURFACELESS=1
export XDG_SESSION_TYPE=wayland XDG_CURRENT_DESKTOP=XFCE XDG_SESSION_DESKTOP=xfce
export GDK_BACKEND=wayland,x11 QT_QPA_PLATFORM=wayland MOZ_ENABLE_WAYLAND=1
export GSK_RENDERER=cairo
export PULSE_SERVER=tcp:127.0.0.1:4713

_variant=compatible
if [ -r "$HOME/.config/termux-xfce/anland-variant" ]; then
    read -r _variant < "$HOME/.config/termux-xfce/anland-variant"
fi
case "$_variant" in standard|compatible) ;; *) echo 'ERROR: 잘못된 Anland APK 종류' >&2; exit 1 ;; esac
_spawn display.pid anland anland --socket "$ANLAND_SOCKET"
_daemon_pid=$_last_pid
_daemon_started=true
_wait_socket "$ANLAND_SOCKET" "$_daemon_pid"
if [ "$_variant" = compatible ]; then
    _spawn bridge.pid anland-compatible anland-compatible "$ANLAND_SOCKET"
fi
am start -n com.anland.termux/.MainActivity

# Anland's microphone/camera streams use PipeWire. Desktop audio retains the
# existing Termux PulseAudio endpoint, including the endpoint used by proot.
export PIPEWIRE_RUNTIME_DIR="$XDG_RUNTIME_DIR/termux-xfce-audio"
mkdir -p "$PIPEWIRE_RUNTIME_DIR"
chmod 700 "$PIPEWIRE_RUNTIME_DIR"
_spawn pipewire.pid pipewire pipewire
_wait_socket "$PIPEWIRE_RUNTIME_DIR/pipewire-0" "$_last_pid"
_spawn wireplumber.pid wireplumber wireplumber

# KWin starts this child after creating Wayland and Xwayland and passes their
# actual DISPLAY/WAYLAND_DISPLAY/XAUTHORITY. It exits when the XFCE child exits.
_spawn compositor.pid kwin_wayland kwin_wayland --anland --xwayland \
    --socket wayland-termux-xfce \
    --exit-with-session "$PREFIX/bin/termux-xfce-anland-xfce"
_compositor_pid=$_last_pid
_wait_socket "$XDG_RUNTIME_DIR/wayland-termux-xfce" "$_compositor_pid"

# Failure of the daemon/bridge/audio/compositor must tear down the whole session.
# bash wait -n returns the first child's status; it does not mean the desktop
# rendered successfully. The launcher separately waits for the XFCE ready marker.
wait -n "${_children[@]}"
