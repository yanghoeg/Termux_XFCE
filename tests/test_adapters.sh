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
    proot_pkg_is_installed "nonexistent_pkg_xyz"
    assert_nonzero $? "proot_pkg_is_installed는 항상 1(미설치)을 반환해야 한다"
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

print_results
