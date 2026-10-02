#!/data/data/com.termux/files/usr/bin/bash
# Failure recovery and exact-state regressions from the full function review.
REVIEW_ROOT="$(cd "${BASH_SOURCE[0]%/*}/.." && pwd)"
source "$REVIEW_ROOT/tests/framework.sh"
source "$REVIEW_ROOT/tests/mocks.sh"

_parent_sandbox() {
    REVIEW_PARENT_SB=$(make_sandbox)
    trap 'cleanup_sandbox "$REVIEW_PARENT_SB"' EXIT
    setup_fs_sandbox "$REVIEW_PARENT_SB"
    export REVIEW_PARENT_TRACE="$REVIEW_PARENT_SB/trace"
    : > "$REVIEW_PARENT_TRACE"
}

_bootstrap_fixture() {
    _parent_sandbox
    mkdir -p "$HOME/.termux-xfce-installer"
    printf 'old checkout\n' > "$HOME/.termux-xfce-installer/keep"
    # Execute only bootstrap code, so no installed-package/Android action can run.
    awk '/^# 1\. 종료 트랩/ { exit } { print }' "$REVIEW_ROOT/install.sh" > "$REVIEW_PARENT_SB/bootstrap.sh"
    git() {
        if [ "${1:-}" = clone ]; then
            local dest="${!#}"
            case "$dest" in
                */app-installer) [ "${REVIEW_BOOT_FAILURE:-}" != fallback ] || return 42 ;;
                *) [ "${REVIEW_BOOT_FAILURE:-}" != clone ] || return 42 ;;
            esac
            mkdir -p "$dest/domain"
            cat > "$dest/install.sh" <<'FIXTURE'
printf 'published:%s\n' "$*" >> "$REVIEW_PARENT_TRACE"
FIXTURE
        elif [ "${3:-}" = submodule ]; then
            [ "${REVIEW_BOOT_FAILURE:-}" != fallback ] || return 42
        elif [ "${3:-}" = config ]; then
            printf 'https://example.invalid/app-installer.git\n'
        fi
    }
    mv() {
        local -a args=("$@")
        local src="${args[${#args[@]}-2]}" dest="${args[${#args[@]}-1]}"
        if [[ "${REVIEW_BOOT_FAILURE:-}" = publish* ]] &&
           [[ "$src" == *.new.* ]] && [ "$dest" = "$HOME/.termux-xfce-installer" ]; then
            return 42
        fi
        command mv "$@"
    }
    export -f git mv
    rm() {
        if [ "${REVIEW_BOOT_FAILURE:-}" = publish-cleanup ] && [[ "${!#}" = *.new.* ]]; then
            return 73
        fi
        command rm "$@"
    }
    export -f rm
}

_test_bootstrap_failure_case() {
    _bootstrap_fixture
    export REVIEW_BOOT_FAILURE="$1"
    if bash "$REVIEW_PARENT_SB/bootstrap.sh" --no-proot > "$REVIEW_PARENT_SB/output" 2>&1; then
        return 1
    fi
    assert_eq 'old checkout' "$(cat "$HOME/.termux-xfce-installer/keep")"
    assert_eq '' "$(find "$HOME" -maxdepth 1 -name '.termux-xfce-installer.new.*' -print)"
    assert_eq '' "$(cat "$REVIEW_PARENT_TRACE")"
}
_test_bootstrap_clone_failure() { _test_bootstrap_failure_case clone; }
_test_bootstrap_submodule_failure() { _test_bootstrap_failure_case fallback; }
_test_bootstrap_publish_failure() { _test_bootstrap_failure_case publish; }
_test_bootstrap_cleanup_failure() {
    _bootstrap_fixture
    export REVIEW_BOOT_FAILURE=publish-cleanup
    local rc=0
    bash "$REVIEW_PARENT_SB/bootstrap.sh" > "$REVIEW_PARENT_SB/output" 2>&1 || rc=$?
    assert_eq 42 "$rc"
    assert_eq 'old checkout' "$(cat "$HOME/.termux-xfce-installer/keep")"
    assert_file_contains "$REVIEW_PARENT_SB/output" '임시 저장소를 정리하지 못했습니다'
}
_test_bootstrap_replacement() {
    _bootstrap_fixture
    unset REVIEW_BOOT_FAILURE
    bash "$REVIEW_PARENT_SB/bootstrap.sh" --no-proot
    [ ! -e "$HOME/.termux-xfce-installer/keep" ]
    assert_file_exists "$HOME/.termux-xfce-installer/install.sh"
    assert_eq 'published:--no-proot' "$(cat "$REVIEW_PARENT_TRACE")"
    assert_eq '' "$(find "$HOME" -maxdepth 1 -name '.termux-xfce-installer.old.*' -print)"
}

describe 'bootstrap preserves working checkout until replacement is ready'
it 'clone failure leaves the original checkout intact and removes staging' _test_bootstrap_clone_failure
it 'submodule fallback failure leaves the original checkout intact' _test_bootstrap_submodule_failure
it 'publishing failure restores the original checkout' _test_bootstrap_publish_failure
it 'staging cleanup failure still restores the checkout and preserves the original exit code' _test_bootstrap_cleanup_failure
it 'successful replacement publishes new checkout and forwards arguments' _test_bootstrap_replacement

_test_sudoers_exact_user() {
    _parent_sandbox
    export PROOT_DISTRO=ubuntu PROOT_USER=alice
    local rootfs="$PREFIX/var/lib/proot-distro/installed-rootfs/ubuntu"
    mkdir -p "$rootfs/etc"
    printf 'alice2 ALL=(ALL) NOPASSWD:ALL\n' > "$rootfs/etc/sudoers"
    source "$REVIEW_ROOT/domain/proot_env.sh"
    _setup_proot_sudoers alice
    _setup_proot_sudoers alice
    assert_eq 1 "$(grep -c '^alice ALL=' "$rootfs/etc/sudoers")"
    assert_eq 1 "$(grep -c '^alice2 ALL=' "$rootfs/etc/sudoers")"
}
describe 'sudoers matches complete user names'
it 'a prefix-sharing existing user neither blocks nor duplicates the new user' _test_sudoers_exact_user

_test_terminal_missing_tty() {
    python3 - "$REVIEW_ROOT/adapters/output/ui_terminal.sh" <<'PY'
import subprocess, sys
script = '''set -euo pipefail
source "$1"
if out=$(ui_input name user 2>/dev/null); then exit 41; fi
[ -z "$out" ]
if out=$(ui_select title prompt ubuntu 2>/dev/null); then exit 42; fi
[ -z "$out" ]
if ui_confirm proceed >/dev/null 2>&1; then exit 43; fi
'''
result = subprocess.run(['bash', '-c', script, '_', sys.argv[1]],
                        start_new_session=True, stdin=subprocess.DEVNULL,
                        capture_output=True, timeout=5)
assert result.returncode == 0, (result.returncode, result.stdout, result.stderr)
PY
}
describe 'terminal input failures reach cancellation handling'
it 'no controlling terminal returns failure without a default user or input loop' _test_terminal_missing_tty

_arch_fixture() {
    _parent_sandbox
    source "$REVIEW_ROOT/adapters/output/pkg_arch.sh"
    pacman() {
        printf '%s\n' "$*" >> "$REVIEW_PARENT_TRACE"
        case "$1" in
            -Qq) printf 'orphan-a\norphan-b\n' ;;
            -Qtdq)
                [ "${REVIEW_ORPHAN_CASE:-}" != empty ] || return 1
                printf 'orphan-a\norphan-b\n' ;;
            -Rns) [ "${REVIEW_ORPHAN_CASE:-}" != failure ] || return 42 ;;
            -Sc) return 0 ;;
            *) return 99 ;;
        esac
    }
    proot_exec() {
        [ "$1" = sudo ] || return 77
        shift
        "$@"
    }
    export -f pacman
}
_test_arch_removal() {
    _arch_fixture
    proot_pkg_autoremove
    assert_file_contains "$REVIEW_PARENT_TRACE" '^-Rns --noconfirm -- orphan-a orphan-b$'
    assert_file_contains "$REVIEW_PARENT_TRACE" '^-Sc --noconfirm$'
}
_test_arch_empty() {
    _arch_fixture
    export REVIEW_ORPHAN_CASE=empty
    proot_pkg_autoremove
    assert_file_not_contains "$REVIEW_PARENT_TRACE" '^-Rns'
    assert_file_contains "$REVIEW_PARENT_TRACE" '^-Sc'
}
_test_arch_failure() {
    _arch_fixture
    export REVIEW_ORPHAN_CASE=failure
    local rc=0
    proot_pkg_autoremove || rc=$?
    assert_eq 42 "$rc"
    assert_file_not_contains "$REVIEW_PARENT_TRACE" '^-Sc'
}
describe 'Arch orphan removal runs as root and propagates failures'
it 'orphan removal uses sudo and passes separate package arguments' _test_arch_removal
it 'an empty orphan set succeeds without attempting removal' _test_arch_empty
it 'removal failure prevents a misleading successful cache cleanup' _test_arch_failure

_test_autopilot_layout() {
    local layout="$1"
    _parent_sandbox
    export PROOT_USER=alice PROOT_DISTRO=ubuntu
    case "$layout" in
        new) mkdir -p "$PREFIX/var/lib/proot-distro/containers/ubuntu/rootfs" ;;
        legacy) mkdir -p "$PREFIX/var/lib/proot-distro/installed-rootfs/ubuntu" ;;
    esac
    proot-distro() { printf '%s\n' "$*" >> "$REVIEW_PARENT_TRACE"; }
    export -f proot-distro
    source <(sed -n '/^_teardown() {/,/^}/p' "$REVIEW_ROOT/tests/autopilot.sh")
    cd "$REVIEW_ROOT"
    _teardown ubuntu
    assert_file_contains "$REVIEW_PARENT_TRACE" '^remove ubuntu$'
}
_test_autopilot_new() { _test_autopilot_layout new; }
_test_autopilot_legacy() { _test_autopilot_layout legacy; }
describe 'autopilot detects both supported rootfs layouts'
it 'new containers are removed instead of being mistaken for missing' _test_autopilot_new
it 'legacy containers retain the existing cleanup behavior' _test_autopilot_legacy

print_results
