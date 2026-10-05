#!/data/data/com.termux/files/usr/bin/bash
# Regressions for the follow-up review of the parent installer changes.
_FOLLOWUP_ROOT="$(cd "${BASH_SOURCE[0]%/*}/.." && pwd)"
source "$_FOLLOWUP_ROOT/tests/framework.sh"
source "$_FOLLOWUP_ROOT/tests/mocks.sh"

_followup_setup() {
    _FOLLOWUP_SB=$(make_sandbox) || return 1
    trap 'cleanup_sandbox "$_FOLLOWUP_SB"' EXIT
    setup_fs_sandbox "$_FOLLOWUP_SB"
    mock_ui_adapter
    mock_pkg_adapter
    export SCRIPT_DIR="$_FOLLOWUP_ROOT"
    source "$_FOLLOWUP_ROOT/domain/termux_env.sh"
    source "$_FOLLOWUP_ROOT/domain/locale_ko.sh"
    source "$_FOLLOWUP_ROOT/domain/proot_env.sh"
}

# =============================================================================
# proot .bashrc — blocks written by earlier installers
# =============================================================================

describe 'proot env — legacy blocks are removed completely'

# Blocks exactly as earlier installers wrote them (setup_proot_env never
# rewrote an existing block, so each shape can still be on a device).
_legacy_proot_block() {
    local icd=/data/data/com.termux/files/usr/share/vulkan/icd.d/freedreno_icd.aarch64.json
    case "$1" in
        2026-04-09)
            printf '%s\n' '# termux-xfce-proot-env' 'export DISPLAY=:1.0' \
                'export LD_PRELOAD=/system/lib64/libskcodec.so' \
                'export XDG_RUNTIME_DIR=/run/user/$(id -u)' 'export MESA_NO_ERROR=1' \
                'export MESA_LOADER_DRIVER_OVERRIDE=zink' 'export TU_DEBUG=noconform' \
                'export MESA_GL_VERSION_OVERRIDE=4.6COMPAT' 'export MESA_GLES_VERSION_OVERRIDE=3.2'
            ;;
        2026-04-12)
            printf '%s\n' '# termux-xfce-proot-env' 'export DISPLAY=${DISPLAY:-:0.0}' \
                'export LD_PRELOAD=/system/lib64/libskcodec.so' \
                'export XDG_RUNTIME_DIR=/run/user/$(id -u)' 'export MESA_NO_ERROR=1' \
                'export MESA_LOADER_DRIVER_OVERRIDE=zink    # proot는 Zink(OpenGL→Vulkan) 사용' \
                'export vblank_mode=0                       # vsync 비활성화 (FPS 측정용)' \
                '# Termux Turnip Vulkan ICD → proot Zink 백엔드 드라이버' \
                "export VK_ICD_FILENAMES=$icd" "export VK_DRIVER_FILES=$icd          # Mesa 23+ 별칭"
            ;;
        2026-04-14|2026-06-15)
            local quote=''
            [ "$1" = 2026-04-14 ] || quote='"'
            printf '%s\n' '# termux-xfce-proot-env' 'export DISPLAY=${DISPLAY:-:0.0}' \
                'export XDG_RUNTIME_DIR=/run/user/$(id -u)' \
                'mkdir -p "$XDG_RUNTIME_DIR" 2>/dev/null' 'export MESA_NO_ERROR=1' \
                'export MESA_LOADER_DRIVER_OVERRIDE=zink    # proot는 Zink(OpenGL→Vulkan) 사용' \
                'export TU_DEBUG=noconform' 'export MESA_GL_VERSION_OVERRIDE=4.6COMPAT' \
                'export MESA_GLES_VERSION_OVERRIDE=3.2' \
                'export MESA_VK_WSI_PRESENT_MODE=immediate  # Vulkan 프레젠테이션 레이턴시 감소' \
                'export ZINK_DESCRIPTORS=lazy               # Zink 디스크립터 성능 최적화' \
                'export vblank_mode=0                       # vsync 비활성화 (FPS 측정용)' \
                '# Termux Turnip Vulkan ICD → proot Zink 백엔드 드라이버' \
                "export VK_ICD_FILENAMES=$quote$icd$quote" \
                "export VK_DRIVER_FILES=$quote$icd$quote        # Mesa 23+ 별칭"
            ;;
        2026-09-05)
            printf '%s\n' '# termux-xfce-proot-env' \
                '[ -f /etc/profile.d/termux-xfce-env.sh ] && . /etc/profile.d/termux-xfce-env.sh' \
                '# aliases' "alias hud='GALLIUM_HUD=fps '" \
                "command -v eza >/dev/null 2>&1 && alias ls='eza -lF --icons'" \
                "alias ll='ls -alhF'" "alias shutdown='kill -9 -1'" \
                "command -v bat >/dev/null 2>&1 && alias cat='bat'" \
                "alias start='echo \"Termux에서 실행하세요.\"'" \
                'code() { nohup dbus-run-session /usr/bin/code --no-sandbox "$@" >/dev/null 2>&1 & disown; }'
            return 0
            ;;
    esac
    printf '%s\n' '' '# aliases' "alias hud='GALLIUM_HUD=fps '" "alias ls='eza -lF --icons'" \
        "alias ll='ls -alhF'" "alias shutdown='kill -9 -1'" "alias cat='bat'" \
        "alias python='/usr/bin/python3'" "alias pip='/usr/bin/pip'" \
        "alias start='echo \"Termux에서 실행하세요.\"'"
    case "$1" in 2026-04-14|2026-06-15)
        printf '%s\n' 'code() { nohup dbus-run-session /usr/bin/code --no-sandbox "$@" >/dev/null 2>&1 & disown; }' ;;
    esac
}

_test_proot_legacy_blocks_removed() {
    _followup_setup
    export PROOT_DISTRO=ubuntu PROOT_USER=testuser
    local rootfs rc shape
    rootfs=$(_proot_rootfs)
    rc="$rootfs/home/testuser/.bashrc"
    mkdir -p "${rc%/*}"
    for shape in 2026-04-09 2026-04-12 2026-04-14 2026-06-15 2026-09-05; do
        { printf 'export BEFORE=yes\n\n'; _legacy_proot_block "$shape"
          printf 'source ~/.fancybash.sh\nexport AFTER=yes\n'; } > "$rc"
        setup_proot_env
        setup_proot_env
        bash -n "$rc"
        assert_eq 1 "$(grep -c '^# termux-xfce-proot-env$' "$rc")" "$shape"
        assert_eq 1 "$(grep -c '^code()' "$rc")" "$shape"
        assert_eq 1 "$(grep -c '^# termux-xfce-proot-env-end$' "$rc")" "$shape"
        if grep -Eq 'MESA_|VK_ICD|VK_DRIVER|LD_PRELOAD|vblank_mode|XDG_RUNTIME_DIR|^alias (ls|cat|python|pip)=' "$rc"; then
            echo "[ASSERT] $shape left part of the old block:" >&2
            cat "$rc" >&2
            return 1
        fi
        assert_file_contains "$rc" '^export BEFORE=yes$'
        assert_file_contains "$rc" '^source ~/.fancybash.sh$'
        assert_file_contains "$rc" '^export AFTER=yes$'
    done
}
it 'every block shape written since 2026-04-09 is removed without touching user lines' _test_proot_legacy_blocks_removed

_test_proot_env_keeps_linked_bashrc() {
    _followup_setup
    export PROOT_DISTRO=ubuntu PROOT_USER=testuser
    local rootfs rc dotfile
    rootfs=$(_proot_rootfs)
    rc="$rootfs/home/testuser/.bashrc"
    dotfile="$rootfs/home/testuser/dotfiles/bashrc"
    mkdir -p "${dotfile%/*}"
    { printf 'export BEFORE=yes\n'; _legacy_proot_block 2026-06-15; } > "$dotfile"
    chmod 640 "$dotfile"
    ln -s dotfiles/bashrc "$rc"
    setup_proot_env
    [ -L "$rc" ]
    assert_eq 640 "$(stat -c %a "$dotfile")"
    assert_file_contains "$dotfile" '^# termux-xfce-proot-env-end$'
    assert_file_not_contains "$dotfile" 'MESA_LOADER_DRIVER_OVERRIDE'
}
it 'a symlinked .bashrc stays a link and its target keeps its mode' _test_proot_env_keeps_linked_bashrc

_test_proot_env_failed_replace_keeps_original() {
    _followup_setup
    export PROOT_DISTRO=ubuntu PROOT_USER=testuser
    local rootfs rc before
    rootfs=$(_proot_rootfs)
    rc="$rootfs/home/testuser/.bashrc"
    mkdir -p "${rc%/*}"
    { printf 'export BEFORE=yes\n'; _legacy_proot_block 2026-06-15; } > "$rc"
    before=$(cat "$rc")
    mv() { return 1; }
    if setup_proot_env; then return 1; fi
    unset -f mv
    assert_eq "$before" "$(cat "$rc")"
    [ -z "$(find "${rc%/*}" -name '.bashrc.*' -print)" ]
}
it 'a failed replacement leaves the original .bashrc whole and no staged copy' _test_proot_env_failed_replace_keeps_original

# =============================================================================
# proot aliases — installer shapes, user guards and one-line definitions
# =============================================================================

describe 'proot alias — earlier shapes refresh, user definitions stay'

_test_proot_alias_refreshes_legacy_shapes() {
    _followup_setup
    export PROOT_DISTRO=archlinux PROOT_USER=yanghoeg
    local legacy rc
    for legacy in \
        "alias archlinux='proot-distro login archlinux --user lideok --shared-tmp'" \
        "alias archlinux='proot-distro login archlinux --user lideok --shared-tmp -- env -u LD_PRELOAD \${PROOT_SHELL:-bash} --login'"; do
        printf 'export BEFORE=yes\n%s\nexport AFTER=yes\n' "$legacy" > "$PREFIX/etc/bash.bashrc"
        printf '%s\n' "$legacy" > "$HOME/.zshrc"
        setup_proot_alias
        for rc in "$PREFIX/etc/bash.bashrc" "$HOME/.zshrc"; do
            assert_eq 1 "$(grep -c 'alias archlinux=' "$rc")"
            assert_file_contains "$rc" 'login archlinux --user yanghoeg'
            assert_file_contains "$rc" 'PROOT_SHELL:-bash}")" --login'"'"'$'
            assert_file_not_contains "$rc" 'lideok'
        done
        # The refreshed alias keeps its position between the user lines.
        assert_eq 'export AFTER=yes' "$(tail -n 1 "$PREFIX/etc/bash.bashrc")"
    done
}
it 'aliases from earlier installers are refreshed in place for the configured user' _test_proot_alias_refreshes_legacy_shapes

_test_proot_alias_keeps_guarded_definition() {
    _followup_setup
    export PROOT_DISTRO=ubuntu PROOT_USER=bob
    local managed
    setup_proot_alias
    managed=$(grep '^alias ubuntu=' "$PREFIX/etc/bash.bashrc")
    printf 'if command -v proot-distro >/dev/null; then\n    %s\nfi\n' "$managed" > "$PREFIX/etc/bash.bashrc"
    cp "$PREFIX/etc/bash.bashrc" "$_FOLLOWUP_SB/guarded"
    setup_proot_alias
    bash -n "$PREFIX/etc/bash.bashrc"
    assert_eq "$(cat "$_FOLLOWUP_SB/guarded")" "$(cat "$PREFIX/etc/bash.bashrc")"
}
it 'an alias indented inside a user guard is left in place and nothing is appended' _test_proot_alias_keeps_guarded_definition

_test_proot_alias_keeps_one_line_definition() {
    _followup_setup
    export PROOT_DISTRO=ubuntu PROOT_USER=bob
    local custom="[ -x \"\$PREFIX/bin/proot-distro\" ] && alias ubuntu='proot-distro login ubuntu --user me'"
    printf '%s\n' "$custom" > "$PREFIX/etc/bash.bashrc"
    setup_proot_alias
    assert_eq "$custom" "$(cat "$PREFIX/etc/bash.bashrc")"
    # A commented-out alias is not a definition.
    printf "# alias ubuntu='old'\n" > "$PREFIX/etc/bash.bashrc"
    setup_proot_alias
    assert_file_contains "$PREFIX/etc/bash.bashrc" '^alias ubuntu=.*--user bob'
}
it 'a one-line conditional alias suppresses the managed alias; a comment does not' _test_proot_alias_keeps_one_line_definition

_test_proot_alias_unchanged_file_not_rewritten() {
    _followup_setup
    export PROOT_DISTRO=ubuntu PROOT_USER=bob
    setup_proot_alias
    local inode; inode=$(stat -c %i "$PREFIX/etc/bash.bashrc")
    setup_proot_alias
    assert_eq "$inode" "$(stat -c %i "$PREFIX/etc/bash.bashrc")"
}
it 'a current alias leaves the shell config untouched' _test_proot_alias_unchanged_file_not_rewritten

# =============================================================================
# install.sh — a stale App Installer checkout
# =============================================================================

describe 'install.sh — App Installer compatibility check'

_test_stale_submodule_is_early_error() {
    _FOLLOWUP_SB=$(make_sandbox) || return 1
    trap 'cleanup_sandbox "$_FOLLOWUP_SB"' EXIT
    local sb="$_FOLLOWUP_SB"
    mkdir -p "$sb/checkout/domain" "$sb/checkout/app-installer/lib" \
        "$sb/checkout/app-installer/domain" "$sb/home" "$sb/usr"
    cp "$_FOLLOWUP_ROOT/install.sh" "$sb/checkout/install.sh"
    cp -R "$_FOLLOWUP_ROOT/ports" "$_FOLLOWUP_ROOT/adapters" "$sb/checkout/"
    # Like the commit main pinned: both helpers exist, the launcher import does not.
    cp "$_FOLLOWUP_ROOT/app-installer/lib/input_method.sh" "$sb/checkout/app-installer/lib/"
    printf 'desktop_rewrite_for_proot() { :; }\ndesktop_register() { :; }\n' \
        > "$sb/checkout/app-installer/domain/desktop.sh"
    if HOME="$sb/home" PREFIX="$sb/usr" bash "$sb/checkout/install.sh" --no-proot > "$sb/error" 2>&1; then
        return 1
    fi
    assert_file_contains "$sb/error" 'git submodule update --init'
    [ ! -e "$sb/home/.config/termux-xfce/config" ]
}
it 'a readable but stale App Installer stops before any change' _test_stale_submodule_is_early_error

# =============================================================================
# Korean UI — base reruns refresh the hook without blocking the installer
# =============================================================================

describe 'Korean UI — base reruns and the RC block'

_hide_clang() {
    command() {
        if [ "${1:-}" = -v ] && [ "${2:-}" = clang ]; then return 1; fi
        builtin command "$@"
    }
}

# Put back the case line installers wrote before 2026-10-01.
_use_old_case_line() {
    OLD_CASE='    case ":${LD_PRELOAD-}:" in *:"$PREFIX/lib/force_gettext.so":*) ;; *)' \
        awk '/^    case .*RUNNING_IN_GLIBC_RUNNER/ { print ENVIRON["OLD_CASE"]; next } { print }' \
        "$1" > "$1.old" && cat "$1.old" > "$1" && rm -f "$1.old"
    grep -q '^    case ":\${LD_PRELOAD-}:" in' "$1"
}

_test_locale_rerun_without_clang() {
    _followup_setup
    _hide_clang
    printf 'old library\n' > "$PREFIX/lib/force_gettext.so"
    _setup_locale
    assert_not_called 'pkg_install clang'
    assert_eq 'old library' "$(cat "$PREFIX/lib/force_gettext.so")"
    assert_ui_contains '기존 force_gettext.so를 유지합니다'
    # The RC block is still refreshed for the existing hook.
    assert_file_contains "$PREFIX/etc/bash.bashrc" RUNNING_IN_GLIBC_RUNNER
    assert_file_contains "$PREFIX/etc/bash.bashrc" '# termux-xfce-locale'
}
it 'a base rerun without clang keeps the old hook and does not download a compiler' _test_locale_rerun_without_clang

_test_locale_rerun_build_failure() {
    _followup_setup
    clang() { return 1; }
    printf 'old library\n' > "$PREFIX/lib/force_gettext.so"
    _setup_locale
    assert_eq 'old library' "$(cat "$PREFIX/lib/force_gettext.so")"
    [ ! -e "$PREFIX/lib/force_gettext.so.sha256" ]
    assert_ui_contains '기존 force_gettext.so를 유지합니다'
}
it 'a failed hook rebuild warns and the base install continues' _test_locale_rerun_build_failure

_test_korean_rc_commented_block_untouched() {
    _followup_setup
    cat > "$PREFIX/etc/bash.bashrc" <<'RC'
# termux-xfce-korean — force_gettext.so 한글 UI 자동 적용
#if [ -f "$PREFIX/lib/force_gettext.so" ]; then
#    export LANG="ko_KR.UTF-8"
#fi

# termux-xfce-xdg-runtime
XDG_RUNTIME_DIR="${PREFIX:-/data/data/com.termux/files/usr}/var/run/user/$(id -u)"
if [ ! -d "$XDG_RUNTIME_DIR" ]; then
    mkdir -p "$XDG_RUNTIME_DIR" 2>/dev/null && chmod 700 "$XDG_RUNTIME_DIR" 2>/dev/null
fi
export XDG_RUNTIME_DIR
if [ -d ~/bin ]; then
    PATH=~/bin:$PATH
fi
RC
    cp "$PREFIX/etc/bash.bashrc" "$_FOLLOWUP_SB/before"
    setup_korean_rc
    assert_eq "$(cat "$_FOLLOWUP_SB/before")" "$(cat "$PREFIX/etc/bash.bashrc")"
    assert_ui_contains '직접 수정된 한글 RC 블록'
    # Without a closing fi the block is equally left alone.
    head -n 4 "$_FOLLOWUP_SB/before" > "$PREFIX/etc/bash.bashrc"
    cp "$PREFIX/etc/bash.bashrc" "$_FOLLOWUP_SB/before"
    setup_korean_rc
    assert_eq "$(cat "$_FOLLOWUP_SB/before")" "$(cat "$PREFIX/etc/bash.bashrc")"
}
it 'a commented-out block keeps the following if/fi blocks and adds no active block' _test_korean_rc_commented_block_untouched

_test_korean_rc_user_lines_inside_block() {
    _followup_setup
    setup_korean_rc
    sed -i 's|^    export KDE_LANG=ko QT_LOCALE_OVERRIDE=ko_KR$|&\n    export MY_SETTING=yes|' "$PREFIX/etc/bash.bashrc"
    assert_file_contains "$PREFIX/etc/bash.bashrc" MY_SETTING
    cp "$PREFIX/etc/bash.bashrc" "$_FOLLOWUP_SB/before"
    setup_korean_rc
    assert_eq "$(cat "$_FOLLOWUP_SB/before")" "$(cat "$PREFIX/etc/bash.bashrc")"
}
it 'a block with a line the user added is not replaced' _test_korean_rc_user_lines_inside_block

_test_korean_rc_guarded_block_stays_inside_guard() {
    _followup_setup
    setup_korean_rc
    # The guarded block holds the pre-2026-10-01 case line, which is refreshed.
    _use_old_case_line "$PREFIX/etc/bash.bashrc"
    { printf 'if [ -z "${NO_KOREAN:-}" ]; then\n'
      sed '/^$/d' "$PREFIX/etc/bash.bashrc"
      printf 'fi\nexport AFTER=yes\n'; } > "$_FOLLOWUP_SB/guarded"
    cp "$_FOLLOWUP_SB/guarded" "$PREFIX/etc/bash.bashrc"
    setup_korean_rc
    bash -n "$PREFIX/etc/bash.bashrc"
    assert_eq 'if [ -z "${NO_KOREAN:-}" ]; then' "$(head -n 1 "$PREFIX/etc/bash.bashrc")"
    assert_eq 'export AFTER=yes' "$(tail -n 1 "$PREFIX/etc/bash.bashrc")"
    assert_file_contains "$PREFIX/etc/bash.bashrc" RUNNING_IN_GLIBC_RUNNER
    assert_eq 1 "$(grep -c '^# termux-xfce-korean' "$PREFIX/etc/bash.bashrc")"
}
it 'a block inside a user guard is refreshed where it is and the file still parses' _test_korean_rc_guarded_block_stays_inside_guard

_test_korean_rc_keeps_position_and_is_idempotent() {
    _followup_setup
    setup_korean_rc
    printf 'export LANG=en_US.UTF-8\nunset LD_PRELOAD\n' >> "$PREFIX/etc/bash.bashrc"
    cp "$PREFIX/etc/bash.bashrc" "$_FOLLOWUP_SB/before"
    local inode; inode=$(stat -c %i "$PREFIX/etc/bash.bashrc")
    setup_korean_rc
    setup_korean_rc
    assert_eq "$(cat "$_FOLLOWUP_SB/before")" "$(cat "$PREFIX/etc/bash.bashrc")"
    assert_eq "$inode" "$(stat -c %i "$PREFIX/etc/bash.bashrc")"
    assert_eq 'unset LD_PRELOAD' "$(tail -n 1 "$PREFIX/etc/bash.bashrc")"
}
it 'reruns leave a current block, its position and the following user lines alone' _test_korean_rc_keeps_position_and_is_idempotent

_test_korean_rc_linked_zshrc() {
    _followup_setup
    command() {
        if [ "${1:-}" = -v ] && [ "${2:-}" = zsh ]; then echo zsh; return 0; fi
        builtin command "$@"
    }
    mkdir -p "$HOME/dotfiles"
    printf 'export ZSH_USER=yes\n' > "$HOME/dotfiles/zshrc"
    chmod 640 "$HOME/dotfiles/zshrc"
    ln -s dotfiles/zshrc "$HOME/.zshrc"
    setup_korean_rc
    _use_old_case_line "$HOME/dotfiles/zshrc"
    setup_korean_rc
    [ -L "$HOME/.zshrc" ]
    assert_eq 640 "$(stat -c %a "$HOME/dotfiles/zshrc")"
    assert_file_contains "$HOME/dotfiles/zshrc" RUNNING_IN_GLIBC_RUNNER
    assert_file_contains "$HOME/dotfiles/zshrc" '^export ZSH_USER=yes$'
}
it 'a symlinked .zshrc keeps its link while the block is refreshed' _test_korean_rc_linked_zshrc

_test_korean_rc_failed_replace_keeps_original() {
    _followup_setup
    setup_korean_rc
    _use_old_case_line "$PREFIX/etc/bash.bashrc"
    cp "$PREFIX/etc/bash.bashrc" "$_FOLLOWUP_SB/before"
    mv() { return 1; }
    if setup_korean_rc; then return 1; fi
    unset -f mv
    assert_eq "$(cat "$_FOLLOWUP_SB/before")" "$(cat "$PREFIX/etc/bash.bashrc")"
    [ -z "$(find "$PREFIX/etc" -name 'bash.bashrc.*' -print)" ]
}
it 'a failed replacement keeps the whole RC file and removes the staged copy' _test_korean_rc_failed_replace_keeps_original

_test_locale_catalogs_behind_symlink() {
    _followup_setup
    unzip() {
        local dest=''
        while [ "$#" -gt 0 ]; do
            if [ "$1" = -d ]; then dest="$2"; break; fi
            shift
        done
        mkdir -p "$dest/ko/LC_MESSAGES"
        printf 'catalog\n' > "$dest/ko/LC_MESSAGES/gtk30.mo"
    }
    mkdir -p "$_FOLLOWUP_SB/locale-store/en/LC_MESSAGES"
    printf 'english\n' > "$_FOLLOWUP_SB/locale-store/en/LC_MESSAGES/existing.mo"
    mkdir -p "$PREFIX/share"
    ln -s "$_FOLLOWUP_SB/locale-store" "$PREFIX/share/locale"
    : > "$_FOLLOWUP_SB/locale.zip"
    _deploy_locale_catalogs "$_FOLLOWUP_SB/locale.zip"
    [ -L "$PREFIX/share/locale" ]
    assert_file_exists "$PREFIX/share/locale/ko/LC_MESSAGES/gtk30.mo"
    assert_eq english "$(cat "$PREFIX/share/locale/en/LC_MESSAGES/existing.mo")"
}
it 'catalogs reached through a symlinked locale directory are deployed behind the link' _test_locale_catalogs_behind_symlink

print_results
