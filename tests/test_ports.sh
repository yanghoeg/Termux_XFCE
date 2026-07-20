#!/data/data/com.termux/files/usr/bin/bash
# =============================================================================
# TEST: ports — 계약(포트) 검증
# 모든 어댑터가 포트에서 요구하는 함수를 구현하는지 확인
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/framework.sh"

ADAPTER_DIR="${SCRIPT_DIR}/../adapters/output"

# pkg_manager 포트가 요구하는 함수 목록 — ports/pkg_manager.sh와 1:1 일치 필요
PKG_MANAGER_CONTRACTS=(
    pkg_update
    pkg_upgrade
    pkg_install
    pkg_remove
    pkg_is_installed
    pkg_autoremove
    proot_exec
    proot_exec_root
    proot_install
    proot_remove
    proot_pkg_install
    proot_pkg_install_root
    proot_pkg_is_installed
    proot_pkg_update
    proot_pkg_update_root
    proot_pkg_remove
    proot_pkg_autoremove
)

# ui 포트가 요구하는 함수 목록
UI_CONTRACTS=(
    ui_info
    ui_warn
    ui_error
    ui_select
    ui_confirm
    ui_input
)

# script_builder 포트가 요구하는 함수 목록
SCRIPT_BUILDER_CONTRACTS=(
    script_build_start_xfce
    script_build_kill_display
    script_build_cp2menu
)

# display 포트가 요구하는 함수 목록
DISPLAY_CONTRACTS=(
    display_emit_kill_session
    display_emit_session_detect
    display_emit_server_start
    display_emit_clipboard_sync
    display_get_packages
    display_setup_apk
)

_check_adapter_contracts() {
    local adapter_file="$1"
    shift
    local contracts=("$@")

    source "$adapter_file"
    for fn in "${contracts[@]}"; do
        if ! declare -f "$fn" > /dev/null 2>&1; then
            echo "[ASSERT] '${fn}' not implemented in $(basename "$adapter_file")" >&2
            return 1
        fi
    done
}

# =============================================================================
# pkg_manager 계약 — 모든 pkg_*.sh 어댑터
# =============================================================================

describe "포트 계약 — pkg_termux.sh"

_test_pkg_termux_contracts() {
    ( _check_adapter_contracts "${ADAPTER_DIR}/pkg_termux.sh" "${PKG_MANAGER_CONTRACTS[@]}" )
}
it "pkg_termux.sh가 모든 pkg_manager 계약을 구현한다" _test_pkg_termux_contracts

describe "포트 계약 — pkg_ubuntu.sh"

_test_pkg_ubuntu_contracts() {
    if [ ! -f "${ADAPTER_DIR}/pkg_ubuntu.sh" ]; then
        return 0  # 파일 없으면 skip
    fi
    ( _check_adapter_contracts "${ADAPTER_DIR}/pkg_ubuntu.sh" "${PKG_MANAGER_CONTRACTS[@]}" )
}
it "pkg_ubuntu.sh가 모든 pkg_manager 계약을 구현한다" _test_pkg_ubuntu_contracts

describe "포트 계약 — pkg_arch.sh"

_test_pkg_arch_contracts() {
    if [ ! -f "${ADAPTER_DIR}/pkg_arch.sh" ]; then
        return 0
    fi
    ( _check_adapter_contracts "${ADAPTER_DIR}/pkg_arch.sh" "${PKG_MANAGER_CONTRACTS[@]}" )
}
it "pkg_arch.sh가 모든 pkg_manager 계약을 구현한다" _test_pkg_arch_contracts

# =============================================================================
# ui 계약 — 모든 ui_*.sh 어댑터
# =============================================================================

describe "포트 계약 — ui_terminal.sh"

_test_ui_terminal_contracts() {
    ( _check_adapter_contracts "${ADAPTER_DIR}/ui_terminal.sh" "${UI_CONTRACTS[@]}" )
}
it "ui_terminal.sh가 모든 ui 계약을 구현한다" _test_ui_terminal_contracts

describe "포트 계약 — ui_zenity.sh"

_test_ui_zenity_contracts() {
    if [ ! -f "${ADAPTER_DIR}/ui_zenity.sh" ]; then
        return 0
    fi
    ( _check_adapter_contracts "${ADAPTER_DIR}/ui_zenity.sh" "${UI_CONTRACTS[@]}" )
}
it "ui_zenity.sh가 모든 ui 계약을 구현한다" _test_ui_zenity_contracts

# =============================================================================
# script_builder 계약 — 모든 script_builder_*.sh 어댑터
# =============================================================================

describe "포트 계약 — script_builder_zenity.sh"

_test_script_builder_zenity_contracts() {
    if [ ! -f "${ADAPTER_DIR}/script_builder_zenity.sh" ]; then
        return 0
    fi
    ( _check_adapter_contracts "${ADAPTER_DIR}/script_builder_zenity.sh" "${SCRIPT_BUILDER_CONTRACTS[@]}" )
}
it "script_builder_zenity.sh가 모든 script_builder 계약을 구현한다" _test_script_builder_zenity_contracts

# =============================================================================
# display 계약 — 모든 display_*.sh 어댑터
# =============================================================================

describe "포트 계약 — display_x11.sh"

_test_display_x11_contracts() {
    (
        # display_x11.sh의 display_setup_apk가 ui_warn, _download_and_open_apk 호출
        ui_warn() { :; }
        _download_and_open_apk() { :; }
        _check_adapter_contracts "${ADAPTER_DIR}/display_x11.sh" "${DISPLAY_CONTRACTS[@]}"
    )
}
it "display_x11.sh가 모든 display 계약을 구현한다" _test_display_x11_contracts

describe "포트 계약 — display_wayland.sh"

_test_display_wayland_contracts() {
    (
        ui_info() { :; }
        _check_adapter_contracts "${ADAPTER_DIR}/display_wayland.sh" "${DISPLAY_CONTRACTS[@]}"
    )
}
it "display_wayland.sh가 모든 display 계약을 구현한다" _test_display_wayland_contracts

# =============================================================================
# _pkg_manager_check — 어댑터 미로드 시 에러
# =============================================================================

describe "포트 계약 — _pkg_manager_check"

_test_pkg_check_fails_without_adapter() {
    local rc=0
    (
        unset -f pkg_install 2>/dev/null || true
        source "${SCRIPT_DIR}/../ports/pkg_manager.sh"
        _pkg_manager_check
    ) 2>/dev/null || rc=$?
    # 위 서브셸은 exit 1로 종료해야 함
    assert_nonzero "$rc" "_pkg_manager_check는 어댑터 없으면 1을 반환해야 한다"
}
it "어댑터 없으면 _pkg_manager_check가 실패한다" _test_pkg_check_fails_without_adapter

_test_pkg_check_passes_with_adapter() {
    local rc=0
    (
        pkg_install() { :; }
        source "${SCRIPT_DIR}/../ports/pkg_manager.sh"
        _pkg_manager_check
    ) || rc=$?
    assert_zero "$rc" "_pkg_manager_check는 어댑터 있으면 0을 반환해야 한다"
}
it "어댑터 있으면 _pkg_manager_check가 성공한다" _test_pkg_check_passes_with_adapter

# =============================================================================
# _display_check — 어댑터 미로드 시 에러
# =============================================================================

describe "포트 계약 — _display_check"

_test_display_check_fails_without_adapter() {
    local rc=0
    (
        unset -f display_emit_server_start 2>/dev/null || true
        source "${SCRIPT_DIR}/../ports/display.sh"
        _display_check
    ) 2>/dev/null || rc=$?
    assert_nonzero "$rc" "_display_check는 어댑터 없으면 1을 반환해야 한다"
}
it "어댑터 없으면 _display_check가 실패한다" _test_display_check_fails_without_adapter

_test_display_check_passes_with_adapter() {
    local rc=0
    (
        display_emit_server_start() { :; }
        source "${SCRIPT_DIR}/../ports/display.sh"
        _display_check
    ) || rc=$?
    assert_zero "$rc" "_display_check는 어댑터 있으면 0을 반환해야 한다"
}
it "어댑터 있으면 _display_check가 성공한다" _test_display_check_passes_with_adapter

print_results
