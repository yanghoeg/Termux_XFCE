#!/data/data/com.termux/files/usr/bin/bash
# =============================================================================
# TEST: adapters/input/interactive.sh
# -----------------------------------------------------------------------------
# resolve_interactive_inputs 분기 커버리지:
#   - PROOT_USER 미설정 → ui_input 호출
#   - PROOT_USER 설정됨 → 건너뜀
#   - SKIP_PROOT=false + PROOT_DISTRO 미설정 → ui_select 호출
#   - distro_choice "없음 (Termux native만)" → SKIP_PROOT=true
#   - SKIP_PROOT=true → distro 질문 건너뜀
#   GPU/한글 입력기는 app-installer로 이관됨 (base install에서 제거)
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/framework.sh"
source "${SCRIPT_DIR}/mocks.sh"

ADAPTER="${SCRIPT_DIR}/../adapters/input/interactive.sh"

# UI 응답을 제어 가능한 mock — 각 함수가 호출되었는지 파일로 추적
# 주의: ui_input/ui_select는 $(...) 안에서 호출되어 서브셸에서 실행되므로
# 배열 수정은 부모로 전파되지 않는다. 파일 추가만 자식→부모 가시성 보장.
_setup_controllable_ui() {
    UI_INPUT_RESPONSE="${UI_INPUT_RESPONSE:-defaultuser}"
    UI_SELECT_RESPONSE="${UI_SELECT_RESPONSE:-ubuntu}"
    UI_CONFIRM_RESPONSE="${UI_CONFIRM_RESPONSE:-0}"
    UI_LOG_FILE=$(mktemp "$(_test_tmp_base)/ui_log_XXXXXX")
    : > "$UI_LOG_FILE"

    ui_info()    { :; }
    ui_warn()    { :; }
    ui_error()   { :; }
    ui_input()   {
        echo "input:$1" >> "$UI_LOG_FILE"
        echo "$UI_INPUT_RESPONSE"
    }
    ui_select()  {
        echo "select:$1" >> "$UI_LOG_FILE"
        echo "$UI_SELECT_RESPONSE"
    }
    ui_confirm() {
        echo "confirm:$1" >> "$UI_LOG_FILE"
        return "$UI_CONFIRM_RESPONSE"
    }
}

_assert_ui_called() {
    local pattern="$1"
    if ! grep -q -- "$pattern" "$UI_LOG_FILE" 2>/dev/null; then
        echo "[ASSERT] expected UI call '${pattern}' but log: $(cat "$UI_LOG_FILE" 2>/dev/null || echo '<none>')" >&2
        return 1
    fi
}

_assert_ui_not_called() {
    local pattern="$1"
    if grep -q -- "$pattern" "$UI_LOG_FILE" 2>/dev/null; then
        echo "[ASSERT] unexpected UI call matching '${pattern}' in: $(cat "$UI_LOG_FILE")" >&2
        return 1
    fi
}

_unset_inputs() {
    unset PROOT_USER PROOT_DISTRO SKIP_PROOT
}

# =============================================================================
describe "interactive — resolve_interactive_inputs PROOT_USER"

_test_user_prompted_when_unset() {
    _unset_inputs
    _setup_controllable_ui
    UI_INPUT_RESPONSE="alice"
    source "$ADAPTER"
    resolve_interactive_inputs
    assert_eq "alice" "$PROOT_USER"
    _assert_ui_called "input:사용자 이름"
}
it "PROOT_USER 미설정 시 ui_input 호출 후 export" _test_user_prompted_when_unset

_test_user_skipped_when_set() {
    _unset_inputs
    _setup_controllable_ui
    export PROOT_USER="preset"
    source "$ADAPTER"
    resolve_interactive_inputs
    assert_eq "preset" "$PROOT_USER"
    _assert_ui_not_called "input:사용자 이름"
}
it "PROOT_USER 설정 시 ui_input 건너뜀" _test_user_skipped_when_set

# =============================================================================
describe "interactive — resolve_interactive_inputs PROOT_DISTRO"

_test_distro_prompted_when_unset() {
    _unset_inputs
    _setup_controllable_ui
    UI_SELECT_RESPONSE="archlinux"
    export PROOT_USER="x"
    source "$ADAPTER"
    resolve_interactive_inputs
    assert_eq "archlinux" "$PROOT_DISTRO"
    _assert_ui_called "select:proot-distro"
}
it "SKIP_PROOT=false + PROOT_DISTRO 미설정 시 ui_select 호출" _test_distro_prompted_when_unset

_test_distro_none_choice_sets_skip_proot() {
    _unset_inputs
    _setup_controllable_ui
    UI_SELECT_RESPONSE="없음 (Termux native만)"
    export PROOT_USER="x"
    source "$ADAPTER"
    resolve_interactive_inputs
    assert_eq "true" "$SKIP_PROOT"
    assert_eq "" "$PROOT_DISTRO"
}
it "'없음' 선택 시 SKIP_PROOT=true, PROOT_DISTRO 빈값" _test_distro_none_choice_sets_skip_proot

_test_distro_skipped_when_skip_proot_true() {
    _unset_inputs
    _setup_controllable_ui
    export PROOT_USER="x" SKIP_PROOT=true
    source "$ADAPTER"
    resolve_interactive_inputs
    _assert_ui_not_called "select:proot-distro"
}
it "SKIP_PROOT=true 면 distro 질문 건너뜀" _test_distro_skipped_when_skip_proot_true

print_results
