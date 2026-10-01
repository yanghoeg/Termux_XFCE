#!/data/data/com.termux/files/usr/bin/bash
# Behavioral regressions for bootstrap, clipboard and proot alias fixes.
_FIXES_ROOT="$(cd "${BASH_SOURCE[0]%/*}/.." && pwd)"
source "$_FIXES_ROOT/tests/framework.sh"
source "$_FIXES_ROOT/tests/mocks.sh"

_fixes_sandbox() {
    _FIXES_SB=$(make_sandbox)
    trap 'cleanup_sandbox "$_FIXES_SB"' EXIT
    setup_fs_sandbox "$_FIXES_SB"
    source "$_FIXES_ROOT/domain/termux_env.sh"
    source "$_FIXES_ROOT/domain/proot_env.sh"
}

_bootstrap_mocks() {
    export REVIEW_BOOT_TRACE="$_FIXES_SB/bootstrap.trace"
    export REVIEW_BOOT_INSTALLED="$_FIXES_SB/git-installed"
    command() {
        if [ "${1:-}" = -v ] && [ "${2:-}" = git ] &&
           [ ! -f "$REVIEW_BOOT_INSTALLED" ]; then
            return 1
        fi
        builtin command "$@"
    }
    pkg() {
        { printf 'pkg'; printf ' %s' "$@"; printf '\n'; } >> "$REVIEW_BOOT_TRACE"
        [ "${REVIEW_BOOT_FAIL:-false}" != true ] || return 42
        touch "$REVIEW_BOOT_INSTALLED"
    }
    git() {
        { printf 'git'; printf ' %s' "$@"; printf '\n'; } >> "$REVIEW_BOOT_TRACE"
        if [ "${1:-}" = clone ]; then
            local dest="${!#}"
            mkdir -p "$dest/domain"
            cat > "$dest/install.sh" <<'CLONE'
#!/data/data/com.termux/files/usr/bin/bash
printf 'installer args: %s\n' "$*" >> "$REVIEW_BOOT_TRACE"
CLONE
        fi
    }
    export -f command pkg git
    # Even a current directory called "domain" must not be treated as the
    # downloaded script's checkout when bash reads the installer from stdin.
    mkdir -p "$_FIXES_SB/domain"
    cd "$_FIXES_SB"
}

_test_bootstrap_installs_git_first() {
    _fixes_sandbox
    _bootstrap_mocks
    PREFIX=/data/data/com.termux/files/usr bash -s -- --no-proot < "$_FIXES_ROOT/install.sh"
    assert_eq 'pkg install -y -o Dpkg::Options::=--force-confold git' "$(head -1 "$REVIEW_BOOT_TRACE")"
    assert_file_contains "$REVIEW_BOOT_TRACE" '^git clone '
    assert_file_contains "$REVIEW_BOOT_TRACE" '^installer args: --no-proot$'
}
it 'stdin bootstrap prepares missing Git before cloning and forwards arguments' _test_bootstrap_installs_git_first

_test_bootstrap_preserves_checkout_on_git_failure() {
    _fixes_sandbox
    _bootstrap_mocks
    mkdir -p "$HOME/.termux-xfce-installer"
    printf 'existing checkout\n' > "$HOME/.termux-xfce-installer/keep"
    export REVIEW_BOOT_FAIL=true
    if PREFIX=/data/data/com.termux/files/usr bash -s -- --no-proot < "$_FIXES_ROOT/install.sh"; then return 1; fi
    assert_eq 'existing checkout' "$(cat "$HOME/.termux-xfce-installer/keep")"
    if grep -q '^git ' "$REVIEW_BOOT_TRACE"; then return 1; fi
}
it 'Git preparation failure stops before deleting an existing checkout' _test_bootstrap_preserves_checkout_on_git_failure

_test_bootstrap_reuses_git() {
    _fixes_sandbox
    _bootstrap_mocks
    touch "$REVIEW_BOOT_INSTALLED"
    PREFIX=/data/data/com.termux/files/usr bash -s -- --no-proot < "$_FIXES_ROOT/install.sh"
    if grep -q '^pkg ' "$REVIEW_BOOT_TRACE"; then return 1; fi
    assert_file_contains "$REVIEW_BOOT_TRACE" '^git clone '
}
it 'an available Git does not trigger package installation during bootstrap' _test_bootstrap_reuses_git

_clipboard_mocks() {
    _setup_clipboard_sync
    export REVIEW_CLIP_STATE="$_FIXES_SB/clipboard"
    mkdir -p "$REVIEW_CLIP_STATE"
    printf 'Android copy' > "$REVIEW_CLIP_STATE/android"
    sleep() {
        REVIEW_CLIP_ITER=$(( ${REVIEW_CLIP_ITER:-0} + 1 ))
        [ "$REVIEW_CLIP_ITER" -le 3 ] || exit 0
        if [ "$REVIEW_CLIP_ITER" -eq 2 ]; then
            case "${REVIEW_CLIP_CHANGE:-}" in
                x11) printf 'Desktop copy' > "$REVIEW_CLIP_STATE/x11" ;;
                android) printf 'Second Android copy' > "$REVIEW_CLIP_STATE/android" ;;
                drop) rm -f "$REVIEW_CLIP_STATE/x11" ;;
            esac
        fi
    }
    termux-clipboard-get() { cat "$REVIEW_CLIP_STATE/android"; }
    termux-clipboard-set() {
        printf 'set Android\n' >> "$REVIEW_CLIP_STATE/trace"
        printf '%s' "$1" > "$REVIEW_CLIP_STATE/android"
    }
    xclip() {
        case "${!#}" in
            -o) [ -f "$REVIEW_CLIP_STATE/x11" ] || return 1; cat "$REVIEW_CLIP_STATE/x11" ;;
            -i)
                printf 'write X11\n' >> "$REVIEW_CLIP_STATE/trace"
                if [ "${REVIEW_CLIP_FAIL_ONCE:-false}" = true ] &&
                   [ ! -f "$REVIEW_CLIP_STATE/failed" ]; then
                    touch "$REVIEW_CLIP_STATE/failed"
                    cat >/dev/null
                    return 1
                fi
                cat > "$REVIEW_CLIP_STATE/x11" ;;
            *) return 2 ;;
        esac
    }
    export -f sleep termux-clipboard-get termux-clipboard-set xclip
}

_test_clipboard_missing_owner() {
    _fixes_sandbox
    _clipboard_mocks
    bash "$PREFIX/bin/termux-clipboard-sync"
    assert_eq 'Android copy' "$(cat "$REVIEW_CLIP_STATE/x11")"
    assert_eq 1 "$(grep -c '^write X11$' "$REVIEW_CLIP_STATE/trace")"
}
it 'a missing X11 owner is seeded from Android without duplicate writes' _test_clipboard_missing_owner

_test_clipboard_retries_failed_seed() {
    _fixes_sandbox
    _clipboard_mocks
    export REVIEW_CLIP_FAIL_ONCE=true
    bash "$PREFIX/bin/termux-clipboard-sync"
    assert_eq 'Android copy' "$(cat "$REVIEW_CLIP_STATE/x11")"
    assert_eq 2 "$(grep -c '^write X11$' "$REVIEW_CLIP_STATE/trace")"
}
it 'failed clipboard writes retry rather than consuming the Android change' _test_clipboard_retries_failed_seed

_test_clipboard_both_directions() {
    _fixes_sandbox
    _clipboard_mocks
    export REVIEW_CLIP_CHANGE=x11
    bash "$PREFIX/bin/termux-clipboard-sync"
    assert_eq 'Desktop copy' "$(cat "$REVIEW_CLIP_STATE/android")"
    assert_eq 1 "$(grep -c '^set Android$' "$REVIEW_CLIP_STATE/trace")"
    export REVIEW_CLIP_CHANGE=android
    bash "$PREFIX/bin/termux-clipboard-sync"
    assert_eq 'Second Android copy' "$(cat "$REVIEW_CLIP_STATE/x11")"
}
it 'clipboard updates still propagate in both directions' _test_clipboard_both_directions

_test_clipboard_owner_loss_preserves_android() {
    _fixes_sandbox
    _clipboard_mocks
    export REVIEW_CLIP_CHANGE=drop
    bash "$PREFIX/bin/termux-clipboard-sync"
    assert_eq 'Android copy' "$(cat "$REVIEW_CLIP_STATE/android")"
    assert_eq 'Android copy' "$(cat "$REVIEW_CLIP_STATE/x11")"
    if grep -q '^set Android$' "$REVIEW_CLIP_STATE/trace"; then return 1; fi
}
it 'losing the X11 owner does not clear the Android clipboard' _test_clipboard_owner_loss_preserves_android

_test_alias_changes_user() {
    _fixes_sandbox
    touch "$HOME/.zshrc"
    export PROOT_DISTRO=ubuntu PROOT_USER=alice
    setup_proot_alias
    PROOT_USER=bob
    setup_proot_alias
    setup_proot_alias
    local rc
    for rc in "$PREFIX/etc/bash.bashrc" "$HOME/.zshrc"; do
        assert_eq 1 "$(grep -c '^alias ubuntu=' "$rc")"
        assert_file_contains "$rc" 'login ubuntu --user bob'
        if grep -q 'login ubuntu --user alice' "$rc"; then return 1; fi
    done
}
it 'reinstalling with a new proot user refreshes both shell aliases once' _test_alias_changes_user

_test_alias_preserves_custom_commands() {
    _fixes_sandbox
    export PROOT_DISTRO=ubuntu PROOT_USER=bob
    printf "alias ubuntu='ssh my-linux-host'\nexport KEEP_SETTING=yes\n" > "$PREFIX/etc/bash.bashrc"
    setup_proot_alias
    assert_eq 1 "$(grep -c '^alias ubuntu=' "$PREFIX/etc/bash.bashrc")"
    assert_file_contains "$PREFIX/etc/bash.bashrc" "alias ubuntu='ssh my-linux-host'"
    assert_file_contains "$PREFIX/etc/bash.bashrc" '^export KEEP_SETTING=yes$'
}
it 'custom distro aliases and unrelated user settings are preserved' _test_alias_preserves_custom_commands

_test_alias_preserves_custom_proot_options() {
    _fixes_sandbox
    export PROOT_DISTRO=ubuntu PROOT_USER=bob
    local custom="alias ubuntu='proot-distro login ubuntu --user alice --shared-tmp --bind /sdcard:/mnt/sdcard -- bash --login'"
    printf '%s\n' "$custom" > "$PREFIX/etc/bash.bashrc"
    setup_proot_alias
    assert_eq "$custom" "$(cat "$PREFIX/etc/bash.bashrc")"
}
it 'custom proot aliases retain bind mounts and extra login options' _test_alias_preserves_custom_proot_options

_test_alias_initial_bash_config() {
    _fixes_sandbox
    export PROOT_DISTRO=ubuntu PROOT_USER=bob
    rm -f "$PREFIX/etc/bash.bashrc" "$HOME/.zshrc"
    setup_proot_alias
    assert_file_contains "$PREFIX/etc/bash.bashrc" 'login ubuntu --user bob'
    [ ! -e "$HOME/.zshrc" ]
}
it 'initial setup creates a missing Bash config without adding a Zsh config' _test_alias_initial_bash_config

print_results
