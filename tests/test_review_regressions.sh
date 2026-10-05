#!/data/data/com.termux/files/usr/bin/bash
# Regression coverage for the parent installer findings.
_REVIEW_ROOT="$(cd "${BASH_SOURCE[0]%/*}/.." && pwd)"
source "$_REVIEW_ROOT/tests/framework.sh"
source "$_REVIEW_ROOT/tests/mocks.sh"

_review_setup() {
    setup_fs_sandbox "$1"
    mock_ui_adapter
    mock_pkg_adapter
    export SCRIPT_DIR="$_REVIEW_ROOT"
    source "$_REVIEW_ROOT/domain/termux_env.sh"
    source "$_REVIEW_ROOT/domain/locale_ko.sh"
    source "$_REVIEW_ROOT/domain/xfce_env.sh"
    source "$_REVIEW_ROOT/domain/proot_env.sh"
    source "$_REVIEW_ROOT/adapters/output/script_builder_zenity.sh"
}

_review_compiler() {
    clang() {
        _record_call "clang"
        while [ "$#" -gt 0 ]; do
            if [ "$1" = -o ]; then printf 'new library\n' > "$2"; return; fi
            shift
        done
        return 1
    }
}

_test_locale_hash_migration() {
    local sb; sb=$(make_sandbox); _review_setup "$sb"; _review_compiler
    export SCRIPT_DIR="$sb/repo"
    mkdir -p "$SCRIPT_DIR/assets"
    echo 'source v1' > "$SCRIPT_DIR/assets/force_gettext.c"
    echo 'old library' > "$PREFIX/lib/force_gettext.so"
    _build_force_gettext
    assert_eq 'new library' "$(cat "$PREFIX/lib/force_gettext.so")"
    assert_was_called clang
    reset_mock_calls
    _build_force_gettext
    assert_not_called clang
    echo 'source v2' > "$SCRIPT_DIR/assets/force_gettext.c"
    _build_force_gettext
    assert_was_called clang
    cleanup_sandbox "$sb"
}
it 'gettext source changes reach existing installs and unchanged source skips compilation (#5)' _test_locale_hash_migration

_test_locale_build_failure_preserves_old() {
    local sb; sb=$(make_sandbox); _review_setup "$sb"
    printf 'old library\n' > "$PREFIX/lib/force_gettext.so"
    printf 'old hash\n' > "$PREFIX/lib/force_gettext.so.sha256"
    clang() { return 1; }
    if _build_force_gettext; then return 1; fi
    assert_eq 'old library' "$(cat "$PREFIX/lib/force_gettext.so")"
    assert_eq 'old hash' "$(cat "$PREFIX/lib/force_gettext.so.sha256")"
    cleanup_sandbox "$sb"
}
it 'gettext rebuild failure preserves the active library and its source stamp (#5)' _test_locale_build_failure_preserves_old

_test_base_updates_existing_locale() {
    local sb; sb=$(make_sandbox); _review_setup "$sb"; _review_compiler
    _setup_locale
    assert_not_called clang
    echo 'legacy library' > "$PREFIX/lib/force_gettext.so"
    _setup_locale
    assert_was_called clang
    assert_file_contains "$PREFIX/etc/bash.bashrc" RUNNING_IN_GLIBC_RUNNER
    cleanup_sandbox "$sb"
}
it 'base reruns rebuild an existing Korean hook while keeping first installation optional (#5)' _test_base_updates_existing_locale

_test_korean_rc_glibc_guard() {
    local sb; sb=$(make_sandbox); _review_setup "$sb"
    # The block as the first installer version (2026-05-08) wrote it.
    cat > "$PREFIX/etc/bash.bashrc" <<'RC'
# termux-xfce-korean — force_gettext.so 한글 UI 자동 적용
if [ -f "$PREFIX/lib/force_gettext.so" ]; then
    export LANGUAGE="ko_KR:ko:en_US:en"
    export FORCE_TEXTDOMAINDIR="$PREFIX/share/locale"
    export FALLBACK_DOMAINS="mousepad xfce4-terminal thunar ristretto \
gtk30 glib20 gdk-pixbuf libxfce4ui-2 libxfce4util exo garcon \
knotifications6 kservice6 solid6 kguiaddons6 kcolorscheme6"
    export XDG_DATA_DIRS="$PREFIX/share${XDG_DATA_DIRS:+:$XDG_DATA_DIRS}"
    QT_TRANSLATIONS_PATH="$PREFIX/share/qt6/translations:$PREFIX/share/qt/translations${QT_TRANSLATIONS_PATH:+:$QT_TRANSLATIONS_PATH}"
    export QT_TRANSLATIONS_PATH
    export KDE_LANG=ko QT_LOCALE_OVERRIDE=ko_KR
    case ":${LD_PRELOAD-}:" in *:"$PREFIX/lib/force_gettext.so":*) ;; *)
        export LD_PRELOAD="$PREFIX/lib/force_gettext.so${LD_PRELOAD:+:$LD_PRELOAD}";; esac
fi
export KEEP_USER_SETTING=yes
RC
    setup_korean_rc
    setup_korean_rc
    assert_eq 1 "$(grep -c '^# termux-xfce-korean' "$PREFIX/etc/bash.bashrc")"
    assert_file_contains "$PREFIX/etc/bash.bashrc" KEEP_USER_SETTING
    # The block is replaced where it was, so the user line still follows it.
    assert_eq 'export KEEP_USER_SETTING=yes' "$(tail -n 1 "$PREFIX/etc/bash.bashrc")"
    echo 'library fixture' > "$PREFIX/lib/force_gettext.so"
    unset LD_PRELOAD
    RUNNING_IN_GLIBC_RUNNER=true
    source "$PREFIX/etc/bash.bashrc"
    assert_eq unset "${LD_PRELOAD-unset}"
    RUNNING_IN_GLIBC_RUNNER=false
    source "$PREFIX/etc/bash.bashrc"
    assert_eq "$PREFIX/lib/force_gettext.so" "$LD_PRELOAD"
    unset LD_PRELOAD
    cleanup_sandbox "$sb"
}
it 'Korean RC migration preserves user lines and avoids Bionic preload in glibc shells (#4)' _test_korean_rc_glibc_guard

_test_korean_rc_broken_boundary_is_preserved() {
    local sb; sb=$(make_sandbox); _review_setup "$sb"
    printf '# termux-xfce-korean — malformed\nexport USER_SETTING=yes\n' > "$PREFIX/etc/bash.bashrc"
    local original; original=$(cat "$PREFIX/etc/bash.bashrc")
    # Base reruns must not stop on a block the installer cannot recognize.
    setup_korean_rc
    setup_korean_rc
    assert_eq "$original" "$(cat "$PREFIX/etc/bash.bashrc")"
    assert_ui_contains '직접 수정된 한글 RC 블록'
    cleanup_sandbox "$sb"
}
it 'a malformed Korean RC block is left unchanged with a warning on every run (#4)' _test_korean_rc_broken_boundary_is_preserved

_test_locale_upgrade_without_catalog_zip() {
    local sb; sb=$(make_sandbox); _review_setup "$sb"; _review_compiler
    source "$_REVIEW_ROOT/app-installer/domain/installers/korean_locale.sh"
    unset KOREAN_LOCALE_ZIP
    echo 'legacy library' > "$PREFIX/lib/force_gettext.so"
    app_upgrade_korean_locale
    assert_eq 'new library' "$(cat "$PREFIX/lib/force_gettext.so")"
    assert_file_exists "$PREFIX/lib/force_gettext.so.sha256"
    assert_file_contains "$PREFIX/etc/bash.bashrc" RUNNING_IN_GLIBC_RUNNER
    cleanup_sandbox "$sb"
}
it 'Korean locale upgrade refreshes an existing hook without requesting its catalog ZIP (#5)' _test_locale_upgrade_without_catalog_zip

_test_start_cleans_glibc_environment() {
    local sb; sb=$(make_sandbox); _review_setup "$sb"
    display_emit_kill_session() { :; }
    display_emit_session_detect() { :; }
    display_emit_server_start() { :; }
    display_emit_clipboard_sync() { :; }
    display_emit_session_launch() { :; }
    script_build_start_xfce "$sb/start"
    # Run only the generated initialization, so the test never starts a session.
    awk '/^# XDG runtime dir/ { exit } { print }' "$sb/start" > "$sb/header"
    cat >> "$sb/header" <<'CHECK'
case ":$PATH:" in *:"$PREFIX/glibc/bin":*|*:"$PREFIX/glibc/bin/":*) exit 1;; esac
[ "${RUNNING_IN_GLIBC_RUNNER-unset}" = unset ]
[ "${APP_PREFIX-unset}" = unset ]
[ "${GLIBC_PREFIX-unset}" = unset ]
CHECK
    RUNNING_IN_GLIBC_RUNNER=true APP_PREFIX=old GLIBC_PREFIX=old \
        PATH="$PREFIX/glibc/bin:$PATH:$PREFIX/glibc/bin/" bash "$sb/header"
    cleanup_sandbox "$sb"
}
it 'session initialization removes inherited glibc flags and glibc PATH entries (#4)' _test_start_cleans_glibc_environment

_test_cascadia_real_filename() {
    local sb; sb=$(make_sandbox); _review_setup "$sb"
    local download_log="$sb/downloads"
    _download_verified_asset() { printf 'download\n' >> "$download_log"; }
    unzip() {
        local dest=''
        while [ "$#" -gt 0 ]; do
            if [ "$1" = -d ]; then dest="$2"; break; fi
            shift
        done
        mkdir -p "$dest/otf/static" "$dest/ttf"
        echo font > "$dest/otf/static/CascadiaCode-Regular.otf"
        echo font > "$dest/ttf/CascadiaCode.ttf"
    }
    _install_cascadia_code
    _install_cascadia_code
    assert_eq 1 "$(grep -c '^download$' "$download_log")"
    assert_file_exists "$HOME/.fonts/CascadiaCode-Regular.otf"
    cleanup_sandbox "$sb"
}
it 'Cascadia extraction creates the file used by the no-download guard (#6)' _test_cascadia_real_filename

_test_missing_submodule_is_early_error() {
    local sb; sb=$(make_sandbox)
    mkdir -p "$sb/checkout/domain" "$sb/home" "$sb/usr"
    cp "$_REVIEW_ROOT/install.sh" "$sb/checkout/install.sh"
    cp -R "$_REVIEW_ROOT/ports" "$_REVIEW_ROOT/adapters" "$sb/checkout/"
    if HOME="$sb/home" PREFIX="$sb/usr" bash "$sb/checkout/install.sh" --no-proot > "$sb/error" 2>&1; then return 1; fi
    assert_file_contains "$sb/error" 'git submodule update --init'
    [ ! -e "$sb/home/.config/termux-xfce/config" ]
    [ ! -e "$sb/home/.zshrc" ]
    HOME="$sb/home" PREFIX="$sb/usr" bash "$sb/checkout/install.sh" --help > "$sb/help" 2>&1
    assert_file_contains "$sb/help" '사용법:'
    HOME="$sb/home" PREFIX="$sb/usr" bash "$sb/checkout/install.sh" -h > "$sb/help" 2>&1
    cleanup_sandbox "$sb"
}
it 'a missing App Installer fails before changes while CLI help remains available (#16)' _test_missing_submodule_is_early_error

_test_old_kill_command_forwards() {
    local sb; sb=$(make_sandbox); _review_setup "$sb"
    script_build_kill_display() { printf '#!/bin/sh\nprintf "%%s\\n" "$@"\n' > "$1"; }
    printf 'Name=Kill Termux X11\nExec=kill_termux_x11\n' > "$PREFIX/share/applications/kill_termux_x11.desktop"
    cp "$PREFIX/share/applications/kill_termux_x11.desktop" "$HOME/Desktop/kill_termux_x11.desktop"
    _setup_kill_display
    [ ! -e "$PREFIX/share/applications/kill_termux_x11.desktop" ]
    assert_file_exists "$PREFIX/share/applications/kill_display_session.desktop"
    # A desktop icon is not a duplicate menu entry; it keeps working.
    assert_file_contains "$HOME/Desktop/kill_termux_x11.desktop" '^Exec=kill_display_session$'
    assert_file_contains "$HOME/Desktop/kill_termux_x11.desktop" '^Name=Kill Display Session$'
    PATH="$PREFIX/bin:$PATH" assert_eq 'argument with spaces' \
        "$(PATH="$PREFIX/bin:$PATH" bash "$PREFIX/bin/kill_termux_x11" 'argument with spaces')"
    cleanup_sandbox "$sb"
}
it 'the old kill command forwards arguments, removes its duplicate menu entry and migrates desktop icons (#17)' _test_old_kill_command_forwards

_test_conky_keeps_user_arguments() {
    local sb; sb=$(make_sandbox); _review_setup "$sb"
    mkdir -p "$PREFIX/var/lib/proot-distro/installed-rootfs/ubuntu" "$HOME/.config/termux-xfce" "$HOME/.config/autostart"
    echo 'PROOT_DISTRO=ubuntu' > "$HOME/.config/termux-xfce/config"
    echo 'Exec=prun conky -c .config/conky/MyTheme/mine.conf -d' > "$HOME/.config/autostart/conky.desktop"
    _setup_conky_autostart
    assert_file_contains "$HOME/.config/autostart/conky.desktop" '^Exec=termux-xfce-conky -c .config/conky/MyTheme/mine.conf -d$'
    cat > "$PREFIX/bin/prun" <<'STUB'
#!/data/data/com.termux/files/usr/bin/bash
printf '%s\n' "$@"
STUB
    chmod +x "$PREFIX/bin/prun"
    export PATH="$PREFIX/bin:$PATH"
    assert_eq $'conky\n-c\nmy theme.conf\n-d' "$(bash "$PREFIX/bin/termux-xfce-conky" -c 'my theme.conf' -d)"
    assert_eq $'conky\n-c\n.config/conky/Alterf/Alterf.conf' "$(bash "$PREFIX/bin/termux-xfce-conky")"
    cleanup_sandbox "$sb"
}
it 'Conky migration and its forwarding wrapper preserve custom arguments (#18)' _test_conky_keeps_user_arguments

_test_old_proot_rc_preserves_user_content() {
    local sb; sb=$(make_sandbox); _review_setup "$sb"
    export PROOT_DISTRO=ubuntu PROOT_USER=testuser
    local rootfs; rootfs=$(_proot_rootfs)
    mkdir -p "$rootfs/home/testuser"
    cat > "$rootfs/home/testuser/.bashrc" <<'RC'
export BEFORE=yes
# termux-xfce-proot-env
export DISPLAY=:1.0
export LD_PRELOAD=/system/lib64/libskcodec.so
export MESA_LOADER_DRIVER_OVERRIDE=zink
# aliases
alias hud='GALLIUM_HUD=fps '
alias start='echo "Termux에서 실행하세요."'
source ~/.fancybash.sh
# >>> conda initialize >>>
export USER_CONDA_SETTING=yes
# <<< conda initialize <<<
RC
    setup_proot_env
    setup_proot_env
    local rc="$rootfs/home/testuser/.bashrc"
    assert_file_contains "$rc" 'source ~/.fancybash.sh'
    assert_file_contains "$rc" USER_CONDA_SETTING
    assert_file_contains "$rc" BEFORE
    assert_file_not_contains "$rc" 'export MESA_LOADER_DRIVER_OVERRIDE'
    assert_eq 1 "$(grep -c '^# termux-xfce-proot-env$' "$rc")"
    assert_eq 1 "$(grep -c '^code()' "$rc")"
    assert_eq 1 "$(grep -c '^# termux-xfce-proot-env-end$' "$rc")"
    cleanup_sandbox "$sb"
}
it 'proot RC migration preserves fancybash and conda when the old block has no code() (#19)' _test_old_proot_rc_preserves_user_content

_test_prun_gui_shows_configuration_errors() {
    local sb; sb=$(make_sandbox); _review_setup "$sb"
    _migrate_desktop_to_prun_gui() { :; }
    _setup_prun
    _setup_prun_gui
    zenity() { printf '%s\n' "$*" > "$TEST_DIALOG"; }
    notify-send() { :; }
    export -f zenity notify-send
    export TEST_DIALOG="$sb/dialog" PATH="$PREFIX/bin:$PATH"
    mkdir -p "$HOME/.config/termux-xfce"
    printf 'PROOT_DISTRO=""\nPROOT_USER=""\n' > "$HOME/.config/termux-xfce/config"
    if bash "$PREFIX/bin/prun-gui" Test -- true; then return 1; fi
    assert_file_contains "$TEST_DIALOG" 'proot 환경이 설정되지'
    echo 'PROOT_DISTRO=ubuntu' > "$HOME/.config/termux-xfce/config"
    if bash "$PREFIX/bin/prun-gui" Test -- true; then return 1; fi
    assert_file_contains "$TEST_DIALOG" 'proot rootfs를 찾을 수 없습니다'
    cleanup_sandbox "$sb"
}
it 'prun GUI errors remain visible for native-only or missing containers (#23)' _test_prun_gui_shows_configuration_errors

print_results
