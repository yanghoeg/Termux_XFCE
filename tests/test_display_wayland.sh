#!/data/data/com.termux/files/usr/bin/bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/framework.sh"
source "$SCRIPT_DIR/mocks.sh"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$PROJECT_DIR/adapters/output/display_wayland.sh"

describe 'Anland — APK selection and hardware preflight'
_test_variants() {
    unset ANLAND_APK_VARIANT TERMUX_APP__APK_RELEASE
    assert_eq compatible "$(_anland_apk_variant)"
    assert_eq standard "$(TERMUX_APP__APK_RELEASE=GITHUB _anland_apk_variant)"
    assert_eq compatible "$(TERMUX_APP__APK_RELEASE=F_DROID _anland_apk_variant)"
    assert_eq compatible "$(ANLAND_APK_VARIANT=compatible TERMUX_APP__APK_RELEASE=GITHUB _anland_apk_variant)"
    ui_error() { :; }
    if ANLAND_APK_VARIANT=typo _anland_apk_variant; then return 1; fi
}
it 'APK signing transport follows Termux source, with validated override' _test_variants

_test_preflight() {
    ui_error() { :; }
    uname() { echo x86_64; }
    _anland_has_kgsl() { return 0; }
    if display_preflight; then return 1; fi
    uname() { echo aarch64; }
    _anland_has_kgsl() { return 1; }
    if display_preflight; then return 1; fi
    _anland_has_kgsl() { return 0; }
    display_preflight
}
it 'unsupported architecture/GPU fails before installation' _test_preflight

describe 'Anland — verified package installation'
_test_deb_failure() {
    local sb; sb=$(make_sandbox)
    mock_ui_adapter
    fetch_verified() { printf package > "$2"; }
    dpkg-query() { return 1; }
    apt() { return 42; }
    apt-mark() { echo unexpected > "$sb/held"; }
    local rc=0
    _anland_deb anland 5.13.3 https://example.invalid/anland.deb unused "$sb/anland.deb" || rc=$?
    assert_eq 1 "$rc"
    [ ! -e "$sb/held" ]
    cleanup_sandbox "$sb"
}
it 'apt failure aborts without marking the package installed/held' _test_deb_failure

_test_deb_wrong_version() {
    local sb; sb=$(make_sandbox)
    mock_ui_adapter
    fetch_verified() { printf package > "$2"; }
    dpkg-query() { echo 'install ok installed 5.12'; }
    apt() { :; }
    apt-mark() { echo unexpected > "$sb/held"; }
    if _anland_deb anland 5.13.3 https://example.invalid/anland.deb unused "$sb/anland.deb"; then return 1; fi
    [ ! -e "$sb/held" ]
    cleanup_sandbox "$sb"
}
it 'successful apt exit alone cannot pass an incorrect package version' _test_deb_wrong_version

_test_deb_reuse() {
    local sb; sb=$(make_sandbox)
    dpkg-query() { echo 'install ok installed 5.13.3'; }
    fetch_verified() { return 99; }
    apt() { return 99; }
    apt-mark() { printf '%s\n' "$*" > "$sb/held"; }
    _anland_deb anland 5.13.3 unused unused "$sb/anland.deb"
    assert_eq 'hold anland' "$(cat "$sb/held")"
    cleanup_sandbox "$sb"
}
it 'the exact installed version is reused and protected from replacement' _test_deb_reuse

_test_hash_failure() {
    local sb; sb=$(make_sandbox)
    _anland_load_fetch
    wget() { printf corrupt > "$3"; }
    apt() { touch "$sb/apt-called"; }
    dpkg-query() { return 1; }
    if _anland_deb anland 5.13.3 unused 62cc21942692377aff64f4e7d6d8cd110c4ed1b49e524c95584c98c7c222d493 "$sb/a.deb"; then return 1; fi
    [ ! -e "$sb/apt-called" ]
    [ ! -e "$sb/a.deb" ]
    cleanup_sandbox "$sb"
}
it 'a corrupt download never reaches apt' _test_hash_failure

_test_apk_error() {
    local sb; sb=$(make_sandbox)
    setup_fs_sandbox "$sb"
    _anland_load_fetch() { :; }
    fetch_verified() { return 1; }
    termux-open() { touch "$sb/opened"; }
    if anland_install_apk; then return 1; fi
    [ ! -e "$sb/opened" ]
    cleanup_sandbox "$sb"
}
it 'APK download failure is surfaced instead of reporting success' _test_apk_error

describe 'Anland — generated launcher and supervised runtime'
_test_launcher() {
    local sb; sb=$(make_sandbox)
    source "$PROJECT_DIR/adapters/output/script_builder_zenity.sh"
    script_build_start_xfce "$sb/startXFCE"
    bash -n "$sb/startXFCE"
    assert_file_contains "$sb/startXFCE" 'com.anland.termux/.MainActivity'
    assert_file_contains "$sb/startXFCE" 'termux-xfce-anland-session'
    assert_file_contains "$sb/startXFCE" 'anland-ready'
    assert_file_not_contains "$sb/startXFCE" 'termux-x11 :'
    assert_file_not_contains "$sb/startXFCE" 'WLR_BACKENDS=x11'
    assert_file_not_contains "$sb/startXFCE" 'termux-clipboard-sync &'
    cleanup_sandbox "$sb"
}
it 'Wayland launcher uses Anland and waits for XFCE readiness' _test_launcher

_test_supervisor() {
    local sb; sb=$(make_sandbox)
    setup_fs_sandbox "$sb"
    python3 "$SCRIPT_DIR/probe_anland_runtime.py" "$PROJECT_DIR"
    cleanup_sandbox "$sb"
}
it 'runtime forwards actual displays and cleans children on exit/failure (mock processes)' _test_supervisor
print_results
