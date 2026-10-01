#!/data/data/com.termux/files/usr/bin/bash
# Desktop review regressions use temporary rootfs trees and GUI stubs only.
_DESKTOP_REVIEW_ROOT="$(cd "${BASH_SOURCE[0]%/*}/.." && pwd)"
source "$_DESKTOP_REVIEW_ROOT/tests/framework.sh"

_desktop_review_setup() {
    local sb="$1"
    _DESKTOP_REVIEW_SB="$sb"
    export HOME="$sb/home" PREFIX="$sb/prefix"
    export PROOT_DISTRO=archlinux PROOT_ROOTFS_BASE="$sb/rootfs-base"
    export TEST_ROOTFS="$PROOT_ROOTFS_BASE/containers/archlinux/rootfs"
    mkdir -p "$HOME/.config/termux-xfce" "$HOME/Desktop" "$PREFIX/bin" \
        "$PREFIX/share/applications" "$TEST_ROOTFS/usr/share/applications" \
        "$TEST_ROOTFS/usr/lib/libreoffice/share/xdg"
    printf 'PROOT_DISTRO=archlinux\n' > "$HOME/.config/termux-xfce/config"
    source "$_DESKTOP_REVIEW_ROOT/app-installer/domain/desktop.sh"
    source "$_DESKTOP_REVIEW_ROOT/adapters/output/script_builder_zenity.sh"
    _proot_rootfs() { printf '%s' "$TEST_ROOTFS"; }
}

_desktop_review_fixture() {
    printf '[Desktop Entry]\nName=Writer 100%%\nExec=libreoffice --writer %%U\nTryExec=/usr/bin/libreoffice\nPath=/opt/libreoffice\nDBusActivatable=true\n' > "$1"
}

_desktop_review_gui() {
    export TEST_DIALOG_LOG="$HOME/dialogs" TEST_SELECTED="${1:-}"
    export TEST_ACTION="${2:-Copy .desktop file}"
    zenity() {
        case "$1" in
            --list) printf '%s\n' "$TEST_ACTION" ;;
            --file-selection) printf '%s\n' "$TEST_SELECTED" ;;
            --error|--info) printf '%s\n' "$*" >> "$TEST_DIALOG_LOG" ;;
            *) return 1 ;;
        esac
    }
    export -f zenity
}

_test_desktop_absolute_and_relative_links() {
    local sb; sb=$(make_sandbox); trap 'cleanup_sandbox "$_DESKTOP_REVIEW_SB"' EXIT
    _desktop_review_setup "$sb"
    _desktop_review_fixture "$TEST_ROOTFS/usr/lib/libreoffice/share/xdg/base.desktop"
    ln -s /usr/lib/libreoffice/share/xdg/base.desktop "$TEST_ROOTFS/usr/share/applications/libreoffice-writer.desktop"
    ln -s ../../lib/libreoffice/share/xdg/base.desktop "$TEST_ROOTFS/usr/share/applications/libreoffice-base.desktop"
    desktop_copy_from_proot libreoffice
    for name in writer base; do
        rg -q '^Exec=prun-gui "Writer 100%%" -- libreoffice --writer %U$' "$PREFIX/share/applications/libreoffice-$name.desktop"
    done
    [ -L "$TEST_ROOTFS/usr/share/applications/libreoffice-writer.desktop" ]
    ln -s /usr/lib/libreoffice "$TEST_ROOTFS/usr/share/linked-directory"
    assert_eq "$TEST_ROOTFS/usr/lib/libreoffice/share/xdg/base.desktop" \
        "$(desktop_resolve_proot_source "$TEST_ROOTFS/usr/share/linked-directory/share/xdg/base.desktop" "$TEST_ROOTFS")"
}
it 'Arch absolute links, relative links and symlinked directories resolve inside the rootfs' _test_desktop_absolute_and_relative_links

_test_desktop_bad_link_preserves_menu() {
    local sb; sb=$(make_sandbox); trap 'cleanup_sandbox "$_DESKTOP_REVIEW_SB"' EXIT
    _desktop_review_setup "$sb"
    printf 'existing menu\n' > "$PREFIX/share/applications/libreoffice-bad.desktop"
    ln -s /missing.desktop "$TEST_ROOTFS/usr/share/applications/libreoffice-bad.desktop"
    if desktop_copy_from_proot libreoffice; then return 1; fi
    assert_eq 'existing menu' "$(cat "$PREFIX/share/applications/libreoffice-bad.desktop")"
    ln -s loop.desktop "$TEST_ROOTFS/usr/share/applications/loop.desktop"
    if desktop_resolve_proot_source "$TEST_ROOTFS/usr/share/applications/loop.desktop" "$TEST_ROOTFS"; then return 1; fi
    if desktop_copy_from_proot nonexistent; then return 1; fi
    _proot_rootfs() { return 1; }
    if desktop_copy_from_proot libreoffice; then return 1; fi
}
it 'missing files and cyclic links fail without replacing an existing menu entry' _test_desktop_bad_link_preserves_menu

_test_desktop_unreadable_rewrite() {
    local sb before; sb=$(make_sandbox); trap 'cleanup_sandbox "$_DESKTOP_REVIEW_SB"' EXIT
    _desktop_review_setup "$sb"
    if desktop_rewrite_for_proot "$sb/missing.desktop"; then return 1; fi
    [ ! -e "$sb/missing.desktop" ]
    _desktop_review_fixture "$sb/write-only.desktop"
    before=$(cat "$sb/write-only.desktop")
    chmod 200 "$sb/write-only.desktop"
    if desktop_rewrite_for_proot "$sb/write-only.desktop"; then return 1; fi
    chmod 600 "$sb/write-only.desktop"
    assert_eq "$before" "$(cat "$sb/write-only.desktop")"
}
it 'missing and write-only sources fail before rewrite and retain their contents' _test_desktop_unreadable_rewrite

_test_desktop_failed_import_preserves_menu() {
    local sb destination; sb=$(make_sandbox); trap 'cleanup_sandbox "$_DESKTOP_REVIEW_SB"' EXIT
    _desktop_review_setup "$sb"
    _desktop_review_fixture "$sb/source.desktop"
    destination="$PREFIX/share/applications/source.desktop"
    printf 'original\n' > "$destination"
    cp() { return 1; }
    if desktop_import_proot "$sb/source.desktop" "$TEST_ROOTFS" "$destination"; then return 1; fi
    assert_eq original "$(cat "$destination")"
    unset -f cp
    mv() { return 1; }
    if desktop_import_proot "$sb/source.desktop" "$TEST_ROOTFS" "$destination"; then return 1; fi
    assert_eq original "$(cat "$destination")"
    [ -z "$(find "$PREFIX/share/applications" -name '.desktop-import.*' -print)" ]
}
it 'copy and final rename failures preserve the destination and clean staged files' _test_desktop_failed_import_preserves_menu

_test_desktop_rewrite_idempotent() {
    local sb before; sb=$(make_sandbox); trap 'cleanup_sandbox "$_DESKTOP_REVIEW_SB"' EXIT
    _desktop_review_setup "$sb"
    _desktop_review_fixture "$sb/source.desktop"
    printf '[Desktop Action Edit]\nExec=libreoffice --draw %%F' >> "$sb/source.desktop"
    desktop_rewrite_for_proot "$sb/source.desktop"
    before=$(cat "$sb/source.desktop")
    desktop_rewrite_for_proot "$sb/source.desktop"
    assert_eq "$before" "$(cat "$sb/source.desktop")"
    rg -q '^Exec=prun-gui "Writer 100%%" -- libreoffice --draw %F$' "$sb/source.desktop"
    rg -q '^DBusActivatable=false$' "$sb/source.desktop"
    if rg -q '^(TryExec|Path)=' "$sb/source.desktop"; then return 1; fi
    desktop_import_proot "$sb/source.desktop" "$TEST_ROOTFS" "$sb/source.desktop"
    assert_eq "$before" "$(cat "$sb/source.desktop")"
}
it 'repeated rewrites and same-file imports keep one wrapper and all action arguments' _test_desktop_rewrite_idempotent

_test_desktop_legacy_migration() {
    local sb before; sb=$(make_sandbox); trap 'cleanup_sandbox "$_DESKTOP_REVIEW_SB"' EXIT
    _desktop_review_setup "$sb"
    _desktop_review_fixture "$sb/legacy.desktop"
    sed -i 's|^Exec=.*|Exec=bash -c "prun libreoffice --writer %U </dev/null >/dev/null 2>\&1 \&"|' "$sb/legacy.desktop"
    desktop_migrate_proot_launcher "$sb/legacy.desktop"
    rg -q '^Exec=prun-gui "Writer 100%%" -- libreoffice --writer %U$' "$sb/legacy.desktop"
    if rg -q '^(TryExec|Path)=' "$sb/legacy.desktop"; then return 1; fi
    printf '[Desktop Entry]\nName=Legacy GUI\nExec=bash -c "prun-gui '\''Legacy GUI'\'' -- libreoffice %%U &"\n' > "$sb/legacy-gui.desktop"
    desktop_migrate_proot_launcher "$sb/legacy-gui.desktop"
    rg -q '^Exec=prun-gui "Legacy GUI" -- libreoffice %U$' "$sb/legacy-gui.desktop"
    _desktop_review_fixture "$sb/native.desktop"
    before=$(cat "$sb/native.desktop")
    desktop_migrate_proot_launcher "$sb/native.desktop"
    assert_eq "$before" "$(cat "$sb/native.desktop")"
    printf 'Name=Complex\nExec=bash -c "prun foo; touch /tmp/should-never-exist &"\n' > "$sb/complex.desktop"
    before=$(cat "$sb/complex.desktop")
    if desktop_migrate_proot_launcher "$sb/complex.desktop"; then return 1; fi
    assert_eq "$before" "$(cat "$sb/complex.desktop")"
}
it 'migration unwraps known legacy forms and preserves native or complex launchers' _test_desktop_legacy_migration

_test_desktop_parent_migration() {
    local sb before; sb=$(make_sandbox); trap 'cleanup_sandbox "$_DESKTOP_REVIEW_SB"' EXIT
    _desktop_review_setup "$sb"
    source "$_DESKTOP_REVIEW_ROOT/domain/termux_env.sh"
    ui_warn() { :; }
    printf 'Name=Legacy\nExec=prun libreoffice %%U\nTryExec=/usr/bin/libreoffice\nPath=/opt/libreoffice\nDBusActivatable=true\n' > "$HOME/Desktop/legacy.desktop"
    _desktop_review_fixture "$PREFIX/share/applications/native.desktop"
    before=$(cat "$PREFIX/share/applications/native.desktop")
    _migrate_desktop_to_prun_gui
    rg -q '^Exec=prun-gui "Legacy" -- libreoffice %U$' "$HOME/Desktop/legacy.desktop"
    rg -q '^DBusActivatable=false$' "$HOME/Desktop/legacy.desktop"
    assert_eq "$before" "$(cat "$PREFIX/share/applications/native.desktop")"
}
it 'parent upgrade migration uses the common helper and preserves native menu entries' _test_desktop_parent_migration

_test_cp2menu_gui_preflight_errors() {
    local sb; sb=$(make_sandbox); trap 'cleanup_sandbox "$_DESKTOP_REVIEW_SB"' EXIT
    _desktop_review_setup "$sb"
    _desktop_review_gui
    script_build_cp2menu "$PREFIX/bin/cp2menu"
    printf 'PROOT_DISTRO=""\n' > "$HOME/.config/termux-xfce/config"
    if bash "$PREFIX/bin/cp2menu" > "$sb/errors" 2>&1; then return 1; fi
    rg -q -- '--error.*proot 환경이 설정되지' "$TEST_DIALOG_LOG"
    printf 'PROOT_DISTRO=missing\n' > "$HOME/.config/termux-xfce/config"
    if bash "$PREFIX/bin/cp2menu" >> "$sb/errors" 2>&1; then return 1; fi
    rg -q -- '--error.*rootfs를 찾을 수' "$TEST_DIALOG_LOG"
    printf 'PROOT_DISTRO=archlinux\n' > "$HOME/.config/termux-xfce/config"
    script_build_cp2menu "$PREFIX/bin/cp2menu" "$sb/missing-helper.sh"
    if bash "$PREFIX/bin/cp2menu" >> "$sb/errors" 2>&1; then return 1; fi
    rg -q -- '--error.*데스크톱 관리 스크립트를 읽을 수' "$TEST_DIALOG_LOG"
    if rg -q -- '--info' "$TEST_DIALOG_LOG"; then return 1; fi
}
it 'cp2menu shows GUI errors for missing configuration, rootfs and runtime helper' _test_cp2menu_gui_preflight_errors

_test_cp2menu_import_and_failed_copy() {
    local sb selected destination before; sb=$(make_sandbox); trap 'cleanup_sandbox "$_DESKTOP_REVIEW_SB"' EXIT
    _desktop_review_setup "$sb"
    _desktop_review_fixture "$TEST_ROOTFS/usr/lib/libreoffice/share/xdg/base.desktop"
    selected="$TEST_ROOTFS/usr/share/applications/libreoffice-writer.desktop"
    ln -s /usr/lib/libreoffice/share/xdg/base.desktop "$selected"
    _desktop_review_gui "$selected"
    script_build_cp2menu "$PREFIX/bin/cp2menu"
    bash "$PREFIX/bin/cp2menu"
    destination="$PREFIX/share/applications/libreoffice-writer.desktop"
    rg -q '^Exec=prun-gui "Writer 100%%" -- libreoffice --writer %U$' "$destination"
    before=$(cat "$destination")
    TEST_SELECTED="$destination" bash "$PREFIX/bin/cp2menu"
    assert_eq "$before" "$(cat "$destination")"
    : > "$TEST_DIALOG_LOG"
    TEST_SELECTED="$TEST_ROOTFS/missing/libreoffice-writer.desktop"
    export TEST_SELECTED
    if bash "$PREFIX/bin/cp2menu" > "$sb/errors" 2>&1; then return 1; fi
    assert_eq "$before" "$(cat "$destination")"
    rg -q -- '--error.*복사 실패' "$TEST_DIALOG_LOG"
    if rg -q -- '--info' "$TEST_DIALOG_LOG"; then return 1; fi
}
it 'generated cp2menu imports absolute links and keeps existing launchers after a failed copy' _test_cp2menu_import_and_failed_copy

_test_cp2menu_live_helper() {
    local sb helper; sb=$(make_sandbox); trap 'cleanup_sandbox "$_DESKTOP_REVIEW_SB"' EXIT
    _desktop_review_setup "$sb"
    helper="$sb/checkout with spaces\$literal/desktop.sh"
    mkdir -p "${helper%/*}"
    cp "$_DESKTOP_REVIEW_ROOT/app-installer/domain/desktop.sh" "$helper"
    _desktop_review_gui "$TEST_ROOTFS/usr/share/applications/live.desktop"
    script_build_cp2menu "$PREFIX/bin/cp2menu" "$helper"
    # Updating the checkout after generation must affect the next cp2menu run.
    cat >> "$helper" <<'UPDATED'
desktop_import_proot() {
    printf '[Desktop Entry]\nName=Live update\nExec=updated-command\n' > "$3"
}
UPDATED
    bash "$PREFIX/bin/cp2menu"
    rg -q '^Exec=updated-command$' "$PREFIX/share/applications/live.desktop"
    rg -q -- '--info.*복사 완료' "$TEST_DIALOG_LOG"
}
it 'cp2menu sources its live checkout path safely after the helper is updated' _test_cp2menu_live_helper

_test_cp2menu_remove_failure() {
    local sb; sb=$(make_sandbox); trap 'cleanup_sandbox "$_DESKTOP_REVIEW_SB"' EXIT
    _desktop_review_setup "$sb"
    _desktop_review_gui "$PREFIX/share/applications/missing.desktop" 'Remove .desktop file'
    script_build_cp2menu "$PREFIX/bin/cp2menu"
    if bash "$PREFIX/bin/cp2menu" > "$sb/errors" 2>&1; then return 1; fi
    rg -q -- '--error.*제거 실패' "$TEST_DIALOG_LOG"
    if rg -q -- '--info' "$TEST_DIALOG_LOG"; then return 1; fi
}
it 'cp2menu reports failed removals through its GUI without a completion message' _test_cp2menu_remove_failure

print_results
