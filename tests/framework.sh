#!/data/data/com.termux/files/usr/bin/bash
# =============================================================================
# TEST FRAMEWORK — 경량 Bash 테스트 러너
# =============================================================================

_PASS=0
_FAIL=0
_SKIP=0
_CURRENT_SUITE=""

# 색상
_RED='\033[0;31m'
_GREEN='\033[0;32m'
_YELLOW='\033[1;33m'
_CYAN='\033[0;36m'
_NC='\033[0m'

# 테스트 스위트 시작
describe() {
    _CURRENT_SUITE="$1"
    echo -e "\n${_CYAN}▶ ${1}${_NC}"
}

# 테스트 케이스 실행 (서브셸 격리)
it() {
    local name="$1"
    local test_fn="$2"

    # 서브셸에서 실행 → set -euo pipefail 에러도 잡힘
    local _tmpfile="${TMPDIR:-/data/data/com.termux/files/usr/tmp}/test_stderr_$$"
    if (set -euo pipefail; "$test_fn") 2>"$_tmpfile"; then
        echo -e "  ${_GREEN}✓${_NC} ${name}"
        (( _PASS++ )) || true
    else
        local exit_code=$?
        echo -e "  ${_RED}✗${_NC} ${name}"
        if [ -s "$_tmpfile" ]; then
            sed 's/^/    /' "$_tmpfile"
        fi
        (( _FAIL++ )) || true
    fi
    rm -f "$_tmpfile"
}

# 스킵
skip() {
    local name="$1"
    echo -e "  ${_YELLOW}-${_NC} ${name} (skipped)"
    (( _SKIP++ )) || true
}

# Assert 함수들
assert_eq() {
    local expected="$1" actual="$2" msg="${3:-}"
    if [ "$expected" != "$actual" ]; then
        echo "[ASSERT] expected='${expected}' actual='${actual}' ${msg}" >&2
        return 1
    fi
}

assert_ne() {
    local unexpected="$1" actual="$2" msg="${3:-}"
    if [ "$unexpected" = "$actual" ]; then
        echo "[ASSERT] unexpected='${unexpected}' but got same value ${msg}" >&2
        return 1
    fi
}

assert_zero() {
    local val="$1" msg="${2:-}"
    if [ "$val" -ne 0 ]; then
        echo "[ASSERT] expected 0, got ${val} ${msg}" >&2
        return 1
    fi
}

assert_nonzero() {
    local val="$1" msg="${2:-}"
    if [ "$val" -eq 0 ]; then
        echo "[ASSERT] expected non-zero, got 0 ${msg}" >&2
        return 1
    fi
}

assert_file_exists() {
    local path="$1"
    if [ ! -f "$path" ]; then
        echo "[ASSERT] file not found: ${path}" >&2
        return 1
    fi
}

assert_dir_exists() {
    local path="$1"
    if [ ! -d "$path" ]; then
        echo "[ASSERT] directory not found: ${path}" >&2
        return 1
    fi
}

assert_file_contains() {
    local path="$1" pattern="$2"
    if ! grep -q "$pattern" "$path" 2>/dev/null; then
        echo "[ASSERT] file '${path}' does not contain pattern '${pattern}'" >&2
        return 1
    fi
}

assert_cmd_exists() {
    local cmd="$1"
    if ! declare -f "$cmd" > /dev/null 2>&1; then
        echo "[ASSERT] function not declared: ${cmd}" >&2
        return 1
    fi
}

assert_output_contains() {
    local cmd_output="$1" pattern="$2"
    if ! echo "$cmd_output" | grep -q -- "$pattern"; then
        echo "[ASSERT] output does not contain '${pattern}'" >&2
        echo "[ASSERT] actual output: ${cmd_output}" >&2
        return 1
    fi
}

# 최종 결과 출력
print_results() {
    echo ""
    echo "════════════════════════════════"
    echo -e " 결과: ${_GREEN}${_PASS} passed${_NC} | ${_RED}${_FAIL} failed${_NC} | ${_YELLOW}${_SKIP} skipped${_NC}"
    echo "════════════════════════════════"
    [ "$_FAIL" -eq 0 ]
}

# 임시 디렉토리 기반 샌드박스 생성
make_sandbox() {
    local dir
    dir=$(mktemp -d "${TMPDIR:-/data/data/com.termux/files/usr/tmp}/termux_test_XXXXXX")
    echo "$dir"
}

cleanup_sandbox() {
    local dir="$1"
    rm -rf "$dir"
}
