#!/data/data/com.termux/files/usr/bin/bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/framework.sh"

describe 'force_gettext — safe lookups, mnemonics and GTK text semantics'
_run_force_gettext() {
    local mode="$1" sanitized="$2" sb compiler="${CC:-clang}"
    local -a flags=(-O2)
    if [ "$sanitized" = true ]; then
        flags=(-g -O1 -fsanitize=address,undefined -fno-omit-frame-pointer)
    fi
    command -v "$compiler" >/dev/null || compiler=cc
    sb=$(make_sandbox)
    # Make uninitialized stack reads reproducible when the compiler supports it.
    if [ "$mode" = overrides ] &&
       "$compiler" -ftrivial-auto-var-init=pattern -x c -c /dev/null -o "$sb/init-probe.o" >/dev/null 2>&1; then
        flags+=(-ftrivial-auto-var-init=pattern)
    fi
    "$compiler" "${flags[@]}" \
        "$SCRIPT_DIR/test_force_gettext.c" -o "$sb/hook-tests" -ldl -pthread || {
        cleanup_sandbox "$sb"; return 1;
    }
    local rc=0
    ASAN_OPTIONS=detect_leaks=0 UBSAN_OPTIONS=halt_on_error=1 \
        "$sb/hook-tests" "$mode" "$sb/catalog.mo" || rc=$?
    cleanup_sandbox "$sb"
    return "$rc"
}
_test_normalize_sanitized() { _run_force_gettext normalize true; }
_test_catalogs_sanitized() { _run_force_gettext mo true; }
_test_dialogs_sanitized() { _run_force_gettext gtk true; }
_test_dialogs_optimized() { _run_force_gettext gtk false; }
_test_overrides_sanitized() { _run_force_gettext overrides true; }
_test_overrides_optimized() { _run_force_gettext overrides false; }
it 'Unicode punctuation preserves adjacent bytes and never reads past NUL (ASan/UBSan)' _test_normalize_sanitized
it 'MO offsets, lengths, terminators and unaligned tables are safe in both byte orders (ASan/UBSan)' _test_catalogs_sanitized
it 'GTK NULL formats reach originals while ordinary formatting and translation remain intact (ASan/UBSan)' _test_dialogs_sanitized
it 'GTK constructors and secondary clearing accept NULL in an optimized build' _test_dialogs_optimized
it 'menu mnemonics and long context/message lookups remain intact (ASan/UBSan)' _test_overrides_sanitized
it 'menu mnemonics and long lookups retain their behavior in an optimized build' _test_overrides_optimized
print_results
