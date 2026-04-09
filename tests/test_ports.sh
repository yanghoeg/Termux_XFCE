#!/data/data/com.termux/files/usr/bin/bash
# =============================================================================
# TEST: ports — 계약(포트) 검증
# 모든 어댑터가 포트에서 요구하는 함수를 구현하는지 확인
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/framework.sh"

ADAPTER_DIR="${SCRIPT_DIR}/../adapters/output"

# pkg_manager 포트가 요구하는 함수 목록
PKG_MANAGER_CONTRACTS=(
    pkg_update
    pkg_upgrade
    pkg_install
    pkg_remove
    pkg_is_installed
    pkg_autoremove
    proot_exec
    proot_pkg_install
    proot_pkg_is_installed
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
# _pkg_manager_check — 어댑터 미로드 시 에러
# =============================================================================

describe "포트 계약 — _pkg_manager_check"

_test_pkg_check_fails_without_adapter() {
    (
        unset -f pkg_install 2>/dev/null || true
        source "${SCRIPT_DIR}/../ports/pkg_manager.sh"
        _pkg_manager_check
    )
    # 위 서브셸은 exit 1로 종료해야 함
    assert_nonzero $? "_pkg_manager_check는 어댑터 없으면 1을 반환해야 한다"
}
it "어댑터 없으면 _pkg_manager_check가 실패한다" _test_pkg_check_fails_without_adapter

_test_pkg_check_passes_with_adapter() {
    (
        pkg_install() { :; }
        source "${SCRIPT_DIR}/../ports/pkg_manager.sh"
        _pkg_manager_check
    )
    assert_zero $? "_pkg_manager_check는 어댑터 있으면 0을 반환해야 한다"
}
it "어댑터 있으면 _pkg_manager_check가 성공한다" _test_pkg_check_passes_with_adapter

print_results
