#!/data/data/com.termux/files/usr/bin/bash
# =============================================================================
# ADAPTER SUPPORT: display_common.sh
# -----------------------------------------------------------------------------
# display_x11.sh / display_wayland.sh 공유 로직
#
# 두 어댑터는 세션 종료(kill) 로직(_kill_pidfile / _kill_orphans /
# _kill_display_session)이 거의 동일하며, 유일한 차이는 _kill_display_session이
# _kill_orphans에 추가로 넘기는 컴포지터 프로세스명(x11=없음, wayland=labwc)과
# 그를 설명하는 주석 한 줄뿐이다.
#
# display_emit_kill_session()은 install.sh가 아니라 script_builder가 호출해
# 그 stdout(FRAG 텍스트)을 그대로 생성 스크립트(startXFCE 등)에 이어 붙인다.
# 여기서도 최종적으로 "완성된 셸 코드 텍스트"를 stdout에 내야 하므로, 원본과
# 동일한 quoted heredoc으로 텍스트를 만들고 컴포지터 차이만 플레이스홀더
# 치환으로 반영한다(함수를 실제로 정의하거나 eval하지 않는다).
# =============================================================================

# display_common_emit_kill_session <extra_orphan_names>
#   _kill_pidfile/_kill_orphans/_kill_display_session 함수 정의 텍스트를 출력한다.
#   $1: _kill_orphans에 추가로 넘길 프로세스명(공백 구분, 없으면 "")
display_common_emit_kill_session() {
    local extra="${1:-}"
    local frag
    frag=$(cat << 'FRAG'
_kill_pidfile() {
    local file="$1" pid expected cmdline
    [ -r "$file" ] || return 0
    read -r pid expected < "$file" || true
    case "$pid" in ""|*[!0-9]*) rm -f "$file"; return 0 ;; esac
    if [ -n "$expected" ]; then
        [ -r "/proc/$pid/cmdline" ] || { rm -f "$file"; return 0; }
        cmdline=$(tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null || true)
        case "$cmdline" in *"$expected"*) ;; *) rm -f "$file"; return 0 ;; esac
    fi
    kill "$pid" 2>/dev/null || true
    local _w
    for _w in 1 2 3; do
        kill -0 "$pid" 2>/dev/null || break
        sleep 1
    done
    kill -9 "$pid" 2>/dev/null || true
    rm -f "$file"
}

# 세션 리더가 비정상 종료돼 남은 XFCE 컴포넌트 고아를 정리한다.
# 과거 방식의 "확실한 정리"와 현재 PID 방식의 "graceful 종료"를 결합:
# 정확한 프로세스명(-x)만 골라 SIGTERM 후 잔존분만 SIGKILL 한다.
# (-f 부분일치를 쓰지 않으므로 이름이 다른 무관 프로세스는 건드리지 않는다.)
_kill_orphans() {
    local names="Xwayland xfwm4 xfdesktop xfce4-panel xfsettingsd xfconfd xfce4-power-manager xfce4-notifyd xfce4-screensaver nimf pulseaudio conky dbus-daemon dbus-launch $*"
    local _n
    for _n in $names; do pkill -TERM -x "$_n" 2>/dev/null || true; done
    sleep 1
    for _n in $names; do pkill -KILL -x "$_n" 2>/dev/null || true; done
}

_kill_display_session() {
    _kill_pidfile "$SESSION_STATE_DIR/clipboard.pid"
    _kill_pidfile "$SESSION_STATE_DIR/session.pid"
    _kill_pidfile "$SESSION_STATE_DIR/display.pid"

    # 구버전 런처로 시작해 PID 파일이 없는 세션만 제한적으로 정리한다.
    pkill -x xfce4-session 2>/dev/null || true
    pkill -f '(^|/)termux-x11( |$)' 2>/dev/null || true
    am force-stop com.termux.x11 2>/dev/null || true

    # 세션 리더 사망 후 남을 수 있는 컴포넌트 고아를 정리 (graceful → SIGKILL)
__DISPLAY_COMMON_EXTRA_COMMENT_LINE__
    _kill_orphans __DISPLAY_COMMON_EXTRA_ORPHANS__

    local display_num=""
    [ -r "$SESSION_STATE_DIR/display-num" ] && read -r display_num < "$SESSION_STATE_DIR/display-num"
    case "$display_num" in
        ""|*[!0-9]*) ;;
        *) rm -f "${TMPDIR}/.X11-unix/X${display_num}" \
              "${TMPDIR}/.X${display_num}-lock" 2>/dev/null || true ;;
    esac
    rm -f "$SESSION_STATE_DIR/display-num"
    termux-wake-unlock 2>/dev/null || true
}
FRAG
)
    if [ -n "$extra" ]; then
        # wayland처럼 추가 프로세스명이 있으면 그 이유를 설명하는 주석 한 줄을 남긴다
        # (원본 display_wayland.sh의 "# labwc(컴포지터)도 고아 목록에 포함한다." 재현)
        frag="${frag/__DISPLAY_COMMON_EXTRA_COMMENT_LINE__/    # ${extra}(컴포지터)도 고아 목록에 포함한다.}"
    else
        # x11처럼 추가분이 없으면 마커 줄 자체(와 개행)를 통째로 제거한다
        frag="${frag/$'__DISPLAY_COMMON_EXTRA_COMMENT_LINE__\n'/}"
    fi
    printf '%s\n' "${frag/ __DISPLAY_COMMON_EXTRA_ORPHANS__/${extra:+ $extra}}"
}
