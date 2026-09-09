#!/data/data/com.termux/files/usr/bin/bash
# Started by KWin with the compositor's actual display and D-Bus environment.
set -euo pipefail
: "${SESSION_STATE_DIR:?}" "${WAYLAND_DISPLAY:?}" "${DISPLAY:?}"
export XDG_SESSION_TYPE=wayland XDG_CURRENT_DESKTOP=XFCE XDG_SESSION_DESKTOP=xfce
export XFCE4_SESSION_COMPOSITOR=kwin_wayland
dbus-update-activation-environment --all
# Keep the marker only while xfce4-session is running; an exec/start failure must
# not be mistaken for a successful session by startXFCE.
_xfce_pid=""
_cleanup() {
    local rc=$?
    trap - EXIT INT TERM
    rm -f "$SESSION_STATE_DIR/anland-ready"
    if [ -n "$_xfce_pid" ]; then
        kill "$_xfce_pid" 2>/dev/null || true
        wait "$_xfce_pid" 2>/dev/null || true
    fi
    exit "$rc"
}
trap _cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
xfce4-session &
_xfce_pid=$!
sleep 1
kill -0 "$_xfce_pid"
printf '%s\n' "$DISPLAY" > "$SESSION_STATE_DIR/anland-ready"
wait "$_xfce_pid"
