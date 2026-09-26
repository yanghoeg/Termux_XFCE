#!/usr/bin/env bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/framework.sh"

describe 'force_gettext — string boundaries'
_test_normalize_sanitized() {
    local sb compiler="${CC:-clang}"
    command -v "$compiler" >/dev/null || compiler=cc
    sb=$(make_sandbox)
    "$compiler" -g -O1 -fsanitize=address,undefined -fno-omit-frame-pointer \
        "$SCRIPT_DIR/test_force_gettext.c" -o "$sb/normalize" -ldl -pthread || {
        cleanup_sandbox "$sb"; return 1;
    }
    local rc=0
    ASAN_OPTIONS=detect_leaks=0 UBSAN_OPTIONS=halt_on_error=1 "$sb/normalize" || rc=$?
    cleanup_sandbox "$sb"
    return "$rc"
}
it 'Unicode punctuation preserves adjacent bytes and never reads past NUL (ASan/UBSan)' _test_normalize_sanitized
print_results
