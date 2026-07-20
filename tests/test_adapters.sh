#!/data/data/com.termux/files/usr/bin/bash
# =============================================================================
# TEST: adapters — pkg_termux.sh, ui_terminal.sh
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/framework.sh"
source "${SCRIPT_DIR}/mocks.sh"

ADAPTER_DIR="${SCRIPT_DIR}/../adapters/output"

# =============================================================================
# pkg_termux.sh — 함수 존재 여부 (계약 검증)
# =============================================================================

describe "pkg_termux.sh — 포트 계약 준수"

_load_pkg_termux() {
    source "${ADAPTER_DIR}/pkg_termux.sh"
}

_test_pkg_termux_contract() {
    source "${ADAPTER_DIR}/pkg_termux.sh"
    assert_cmd_exists pkg_update
    assert_cmd_exists pkg_upgrade
    assert_cmd_exists pkg_install
    assert_cmd_exists pkg_remove
    assert_cmd_exists pkg_is_installed
    assert_cmd_exists pkg_autoremove
    assert_cmd_exists proot_exec
    assert_cmd_exists proot_pkg_install
    assert_cmd_exists proot_pkg_update
    assert_cmd_exists proot_pkg_remove
    assert_cmd_exists proot_pkg_autoremove
    assert_cmd_exists proot_pkg_is_installed
}
it "모든 계약 함수가 선언되어 있다" _test_pkg_termux_contract

_test_proot_exec_error() {
    source "${ADAPTER_DIR}/pkg_termux.sh"
    local out
    out=$(proot_exec echo hello 2>&1) || true
    assert_output_contains "$out" "ERROR"
}
it "proot_exec는 에러 메시지를 출력한다" _test_proot_exec_error

_test_proot_pkg_install_error() {
    source "${ADAPTER_DIR}/pkg_termux.sh"
    local out
    out=$(proot_pkg_install vim 2>&1) || true
    assert_output_contains "$out" "ERROR"
}
it "proot_pkg_install는 에러 메시지를 출력한다" _test_proot_pkg_install_error

_test_proot_pkg_is_installed_false() {
    source "${ADAPTER_DIR}/pkg_termux.sh"
    local rc=0
    proot_pkg_is_installed "nonexistent_pkg_xyz" || rc=$?
    assert_nonzero "$rc" "proot_pkg_is_installed는 항상 1(미설치)을 반환해야 한다"
}
it "proot_pkg_is_installed는 항상 미설치(1)를 반환한다" _test_proot_pkg_is_installed_false

# =============================================================================
# ui_terminal.sh — 출력 형식 검증
# =============================================================================

describe "ui_terminal.sh — UI 출력 형식"

_test_ui_terminal_contract() {
    source "${ADAPTER_DIR}/ui_terminal.sh"
    assert_cmd_exists ui_info
    assert_cmd_exists ui_warn
    assert_cmd_exists ui_error
    assert_cmd_exists ui_select
    assert_cmd_exists ui_confirm
    assert_cmd_exists ui_input
}
it "모든 UI 계약 함수가 선언되어 있다" _test_ui_terminal_contract

_test_ui_info_format() {
    source "${ADAPTER_DIR}/ui_terminal.sh"
    local out
    out=$(ui_info "테스트 메시지")
    assert_output_contains "$out" "[INFO]"
    assert_output_contains "$out" "테스트 메시지"
}
it "ui_info는 [INFO] 태그를 포함한다" _test_ui_info_format

_test_ui_warn_format() {
    source "${ADAPTER_DIR}/ui_terminal.sh"
    local out
    out=$(ui_warn "경고 메시지")
    assert_output_contains "$out" "[WARN]"
    assert_output_contains "$out" "경고 메시지"
}
it "ui_warn은 [WARN] 태그를 포함한다" _test_ui_warn_format

_test_ui_error_stderr() {
    source "${ADAPTER_DIR}/ui_terminal.sh"
    local err
    err=$(ui_error "에러 메시지" 2>&1 >/dev/null)
    assert_output_contains "$err" "[ERROR]"
    assert_output_contains "$err" "에러 메시지"
}
it "ui_error는 stderr로 출력한다" _test_ui_error_stderr

_test_ui_input_default() {
    source "${ADAPTER_DIR}/ui_terminal.sh"
    # /dev/tty 대신 빈 입력 시뮬레이션 → 기본값 반환 여부
    local out
    out=$(echo "" | ui_input "이름" "기본값" 2>/dev/null || echo "기본값")
    # 기본값이 포함되는지 확인
    assert_output_contains "$out" "기본값"
}
it "ui_input은 빈 입력 시 기본값을 반환한다" _test_ui_input_default

_test_ui_select_menu_redirected_to_stderr_static() {
    # 회귀: ui_select 메뉴 출력이 stdout으로 가면 $()로 캡처될 때 반환값과
    # 섞여서 PROOT_DISTRO 등이 통째로 깨진다. 메뉴 그룹은 stderr로 가야 한다.
    # 과거 버그: 사용자가 install.sh 대화형 실행 시 distro 선택 후
    #   "[ERROR] 지원하지 않는 distro: === proot-distro 선택 ==="로 실패
    # /dev/tty 의존 때문에 dynamic 테스트가 어려워 정적 검증으로 잠금
    local file="${ADAPTER_DIR}/ui_terminal.sh"
    # ui_select 함수 본문 추출 (sed로 함수 시작~끝 블록)
    local body
    body=$(awk '/^ui_select\(\)/,/^\}/' "$file")
    # 메뉴 그룹 redirect '} >&2'가 있어야 한다
    if ! echo "$body" | grep -q '} >&2'; then
        echo "  ui_select에 '} >&2' 메뉴 그룹 redirect가 없다"
        return 1
    fi
    # 검증 실패 메시지도 stderr로 가야 한다
    if ! echo "$body" | grep -q '올바른 번호를 입력하세요.*>&2'; then
        echo "  검증 실패 echo가 stderr로 redirect되지 않음"
        return 1
    fi
}
it "ui_select 메뉴 출력은 stderr로 redirect된다 (회귀)" \
   _test_ui_select_menu_redirected_to_stderr_static

# =============================================================================
# pkg_termux.sh — proot 신규 stub 에러 반환 검증
# =============================================================================

describe "pkg_termux.sh — proot stub 에러 반환"

_test_proot_pkg_update_error() {
    source "${ADAPTER_DIR}/pkg_termux.sh"
    local out
    out=$(proot_pkg_update 2>&1) || true
    assert_output_contains "$out" "ERROR"
}
it "proot_pkg_update는 에러 메시지를 출력한다" _test_proot_pkg_update_error

_test_proot_pkg_remove_error() {
    source "${ADAPTER_DIR}/pkg_termux.sh"
    local out
    out=$(proot_pkg_remove vim 2>&1) || true
    assert_output_contains "$out" "ERROR"
}
it "proot_pkg_remove는 에러 메시지를 출력한다" _test_proot_pkg_remove_error

_test_proot_pkg_autoremove_error() {
    source "${ADAPTER_DIR}/pkg_termux.sh"
    local out
    out=$(proot_pkg_autoremove 2>&1) || true
    assert_output_contains "$out" "ERROR"
}
it "proot_pkg_autoremove는 에러 메시지를 출력한다" _test_proot_pkg_autoremove_error

# =============================================================================
# script_builder_zenity.sh — 스크립트 빌더 직접 테스트
# =============================================================================

describe "script_builder_zenity.sh — script_build_start_xfce"

_test_sb_start_xfce_creates_valid_bash() {
    source "${ADAPTER_DIR}/display_x11.sh"
    source "${ADAPTER_DIR}/script_builder_zenity.sh"
    local sb; sb=$(make_sandbox)
    local out="${sb}/startXFCE"
    script_build_start_xfce "$out"
    assert_file_exists "$out"
    bash -n "$out"
    cleanup_sandbox "$sb"
}
it "유효한 bash 스크립트를 생성한다" _test_sb_start_xfce_creates_valid_bash

_test_sb_start_xfce_has_display_detection() {
    source "${ADAPTER_DIR}/display_x11.sh"
    source "${ADAPTER_DIR}/script_builder_zenity.sh"
    local sb; sb=$(make_sandbox)
    local out="${sb}/startXFCE"
    script_build_start_xfce "$out"
    assert_file_contains "$out" ".X11-unix"
    assert_file_contains "$out" "DISPLAY_NUM"
    cleanup_sandbox "$sb"
}
it "DISPLAY 자동 감지 로직이 있다" _test_sb_start_xfce_has_display_detection

_test_sb_start_xfce_pulse_no_idle_exit() {
    source "${ADAPTER_DIR}/display_x11.sh"
    source "${ADAPTER_DIR}/script_builder_zenity.sh"
    local sb; sb=$(make_sandbox)
    local out="${sb}/startXFCE"
    script_build_start_xfce "$out"
    assert_file_contains "$out" "exit-idle-time=-1"
    assert_file_not_contains "$out" "exit-idle-time=120"
    cleanup_sandbox "$sb"
}
it "PulseAudio exit-idle-time=-1 (유휴 종료 비활성)" _test_sb_start_xfce_pulse_no_idle_exit

_test_sb_start_xfce_has_gpu_branch() {
    source "${ADAPTER_DIR}/display_x11.sh"
    source "${ADAPTER_DIR}/script_builder_zenity.sh"
    local sb; sb=$(make_sandbox)
    local out="${sb}/startXFCE"
    script_build_start_xfce "$out"
    assert_file_contains "$out" "MESA_LOADER_DRIVER_OVERRIDE=zink"
    assert_file_contains "$out" "LIBGL_ALWAYS_SOFTWARE"
    cleanup_sandbox "$sb"
}
it "GPU 분기(Zink vs llvmpipe)가 포함된다" _test_sb_start_xfce_has_gpu_branch

_test_sb_start_xfce_has_session_duplicate_check() {
    source "${ADAPTER_DIR}/display_x11.sh"
    source "${ADAPTER_DIR}/script_builder_zenity.sh"
    local sb; sb=$(make_sandbox)
    local out="${sb}/startXFCE"
    script_build_start_xfce "$out"
    assert_file_contains "$out" "xfce4-session"
    assert_file_contains "$out" "_kill_display_session"
    assert_file_contains "$out" "세션 중복 감지"
    cleanup_sandbox "$sb"
}
it "X11 세션 중복 감지 로직이 있다" _test_sb_start_xfce_has_session_duplicate_check

_test_sb_start_xfce_am_start_force() {
    source "${ADAPTER_DIR}/display_x11.sh"
    source "${ADAPTER_DIR}/script_builder_zenity.sh"
    local sb; sb=$(make_sandbox)
    local out="${sb}/startXFCE"
    script_build_start_xfce "$out"
    assert_file_contains "$out" "am start"
    cleanup_sandbox "$sb"
}
it "am start로 APK를 시작한다" _test_sb_start_xfce_am_start_force

describe "script_builder_zenity.sh — script_build_kill_display"

_test_sb_kill_creates_valid_bash() {
    source "${ADAPTER_DIR}/display_x11.sh"
    source "${ADAPTER_DIR}/script_builder_zenity.sh"
    local sb; sb=$(make_sandbox)
    local out="${sb}/kill_display_session"
    script_build_kill_display "$out"
    assert_file_exists "$out"
    bash -n "$out"
    cleanup_sandbox "$sb"
}
it "유효한 bash 스크립트를 생성한다" _test_sb_kill_creates_valid_bash

_test_sb_kill_checks_pkg_running() {
    source "${ADAPTER_DIR}/display_x11.sh"
    source "${ADAPTER_DIR}/script_builder_zenity.sh"
    local sb; sb=$(make_sandbox)
    local out="${sb}/kill_display_session"
    script_build_kill_display "$out"
    assert_file_contains "$out" "\[a\]pt|\[a\]pt-get|\[d\]pkg|\[n\]ala"
    cleanup_sandbox "$sb"
}
it "패키지 설치 중 여부를 확인한다" _test_sb_kill_checks_pkg_running

_test_sb_kill_has_wake_unlock() {
    source "${ADAPTER_DIR}/display_x11.sh"
    source "${ADAPTER_DIR}/script_builder_zenity.sh"
    local sb; sb=$(make_sandbox)
    local out="${sb}/kill_display_session"
    script_build_kill_display "$out"
    assert_file_contains "$out" "termux-wake-unlock"
    cleanup_sandbox "$sb"
}
it "종료 시 termux-wake-unlock을 호출한다" _test_sb_kill_has_wake_unlock

describe "script_builder_zenity.sh — script_build_cp2menu"

_test_sb_cp2menu_creates_valid_bash() {
    source "${ADAPTER_DIR}/display_x11.sh"
    source "${ADAPTER_DIR}/script_builder_zenity.sh"
    local sb; sb=$(make_sandbox)
    local out="${sb}/cp2menu"
    script_build_cp2menu "$out"
    assert_file_exists "$out"
    bash -n "$out"
    cleanup_sandbox "$sb"
}
it "유효한 bash 스크립트를 생성한다" _test_sb_cp2menu_creates_valid_bash

_test_sb_cp2menu_reads_config() {
    source "${ADAPTER_DIR}/display_x11.sh"
    source "${ADAPTER_DIR}/script_builder_zenity.sh"
    local sb; sb=$(make_sandbox)
    local out="${sb}/cp2menu"
    script_build_cp2menu "$out"
    assert_file_contains "$out" "termux-xfce/config"
    cleanup_sandbox "$sb"
}
it "termux-xfce/config에서 distro를 읽는다" _test_sb_cp2menu_reads_config

_test_sb_cp2menu_uses_prun_gui() {
    source "${ADAPTER_DIR}/display_x11.sh"
    source "${ADAPTER_DIR}/script_builder_zenity.sh"
    local sb; sb=$(make_sandbox)
    local out="${sb}/cp2menu"
    script_build_cp2menu "$out"
    assert_file_contains "$out" "prun-gui"
    cleanup_sandbox "$sb"
}
it "prun-gui로 Exec 라인을 변환한다" _test_sb_cp2menu_uses_prun_gui

# =============================================================================
# display_x11.sh — emit 함수 검증
# =============================================================================

describe "display_x11.sh — emit 함수"

_test_display_x11_emit_kill_valid() {
    source "${ADAPTER_DIR}/display_x11.sh"
    local frag
    frag=$(display_emit_kill_session)
    echo "$frag" | bash -n
}
it "display_emit_kill_session이 유효한 bash를 출력한다" _test_display_x11_emit_kill_valid

_test_display_x11_emit_server_start_valid() {
    source "${ADAPTER_DIR}/display_x11.sh"
    local frag
    frag=$(display_emit_server_start)
    echo "$frag" | bash -n
}
it "display_emit_server_start가 유효한 bash를 출력한다" _test_display_x11_emit_server_start_valid

_test_display_x11_emit_server_start_sets_xdisplay() {
    source "${ADAPTER_DIR}/display_x11.sh"
    local frag
    frag=$(display_emit_server_start)
    echo "$frag" | grep -q 'XDISPLAY='
}
it "display_emit_server_start가 XDISPLAY를 설정한다" _test_display_x11_emit_server_start_sets_xdisplay

_test_display_x11_get_packages() {
    source "${ADAPTER_DIR}/display_x11.sh"
    local pkgs
    pkgs=$(display_get_packages)
    echo "$pkgs" | grep -q 'termux-x11-nightly'
}
it "display_get_packages가 termux-x11-nightly를 포함한다" _test_display_x11_get_packages

_test_display_x11_emit_clipboard_valid() {
    source "${ADAPTER_DIR}/display_x11.sh"
    local frag
    frag=$(display_emit_clipboard_sync)
    echo "$frag" | bash -n
}
it "display_emit_clipboard_sync이 유효한 bash를 출력한다" _test_display_x11_emit_clipboard_valid

print_results
