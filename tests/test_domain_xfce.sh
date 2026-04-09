#!/data/data/com.termux/files/usr/bin/bash
# =============================================================================
# TEST: domain/xfce_env.sh
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/framework.sh"
source "${SCRIPT_DIR}/mocks.sh"

DOMAIN_DIR="${SCRIPT_DIR}/../domain"

_load_domain() {
    local sandbox="$1"
    setup_fs_sandbox "$sandbox"
    mock_pkg_adapter
    mock_ui_adapter
    mock_wget
    source "${DOMAIN_DIR}/packages.sh"
    # xfce_env는 REPO_BASE readonly 재선언 방지를 위해 subshell에서 로드
    source "${DOMAIN_DIR}/xfce_env.sh" 2>/dev/null || \
        source "${DOMAIN_DIR}/xfce_env.sh"
}

# =============================================================================
# setup_xfce_packages — 멱등성
# =============================================================================

describe "xfce_env — setup_xfce_packages"

_test_xfce_pkgs_installs_missing() {
    local sb; sb=$(make_sandbox)
    _load_domain "$sb"
    reset_mock_calls
    MOCK_INSTALLED_PKGS=""

    # firefox.desktop stub (cp 대상)
    mkdir -p "${PREFIX}/share/applications"
    touch "${PREFIX}/share/applications/firefox.desktop"

    setup_xfce_packages 2>/dev/null || true
    assert_was_called "pkg_install"
    cleanup_sandbox "$sb"
}
it "미설치 패키지에 대해 pkg_install을 호출한다" _test_xfce_pkgs_installs_missing

_test_xfce_pkgs_skips_installed() {
    local sb; sb=$(make_sandbox)
    _load_domain "$sb"
    reset_mock_calls
    MOCK_INSTALLED_PKGS="${PKGS_TERMUX_XFCE[*]} ${PKGS_TERMUX_CLI[*]}"

    mkdir -p "${PREFIX}/share/applications"
    touch "${PREFIX}/share/applications/firefox.desktop"

    setup_xfce_packages 2>/dev/null || true
    assert_not_called "pkg_install"
    cleanup_sandbox "$sb"
}
it "멱등성 — 설치된 패키지는 pkg_install을 호출하지 않는다" _test_xfce_pkgs_skips_installed

_test_xfce_firefox_desktop_copied() {
    local sb; sb=$(make_sandbox)
    _load_domain "$sb"
    MOCK_INSTALLED_PKGS="${PKGS_TERMUX_XFCE[*]} ${PKGS_TERMUX_CLI[*]}"

    mkdir -p "${PREFIX}/share/applications"
    echo "[Desktop Entry]" > "${PREFIX}/share/applications/firefox.desktop"

    setup_xfce_packages 2>/dev/null || true
    assert_file_exists "${HOME}/Desktop/firefox.desktop"
    cleanup_sandbox "$sb"
}
it "firefox.desktop을 Desktop에 복사한다" _test_xfce_firefox_desktop_copied

# =============================================================================
# setup_xfce_wallpaper — 멱등성
# =============================================================================

describe "xfce_env — setup_xfce_wallpaper"

_test_wallpaper_downloads_files() {
    local sb; sb=$(make_sandbox)
    _load_domain "$sb"
    reset_mock_calls

    setup_xfce_wallpaper 2>/dev/null || true
    assert_was_called "wget"
    cleanup_sandbox "$sb"
}
it "배경화면 파일을 다운로드한다" _test_wallpaper_downloads_files

_test_wallpaper_idempotent() {
    local sb; sb=$(make_sandbox)
    _load_domain "$sb"

    local bg_dir="${PREFIX}/share/backgrounds/xfce"
    # 이미 파일이 있는 경우
    touch "${bg_dir}/dark_waves.png"
    touch "${bg_dir}/TheSolarSystem.jpg"
    reset_mock_calls

    setup_xfce_wallpaper 2>/dev/null || true
    assert_not_called "wget"
    cleanup_sandbox "$sb"
}
it "멱등성 — 배경화면이 이미 있으면 재다운로드하지 않는다" _test_wallpaper_idempotent

# =============================================================================
# _install_whitesur_theme — 멱등성
# =============================================================================

describe "xfce_env — _install_whitesur_theme"

_test_theme_skips_if_exists() {
    local sb; sb=$(make_sandbox)
    _load_domain "$sb"
    reset_mock_calls

    # 테마 디렉토리가 이미 있는 경우
    mkdir -p "${PREFIX}/share/themes/WhiteSur-Dark"

    _install_whitesur_theme 2>/dev/null || true
    assert_not_called "wget"
    cleanup_sandbox "$sb"
}
it "멱등성 — 테마가 이미 있으면 다운로드하지 않는다" _test_theme_skips_if_exists

_test_theme_downloads_if_missing() {
    local sb; sb=$(make_sandbox)
    _load_domain "$sb"
    reset_mock_calls

    # unzip/tar 등 mock
    unzip() { _record_call "unzip $*"; mkdir -p WhiteSur-gtk-theme-2024-11-18/release; touch WhiteSur-gtk-theme-2024-11-18/release/WhiteSur-Dark.tar.xz; }
    tar()   { _record_call "tar $*"; mkdir -p WhiteSur-Dark; }
    mv()    { _record_call "mv $*"; mkdir -p "${PREFIX}/share/themes/WhiteSur-Dark" 2>/dev/null || true; }
    rm()    { _record_call "rm $*"; }

    _install_whitesur_theme 2>/dev/null || true
    assert_was_called "wget"
    cleanup_sandbox "$sb"
}
it "테마가 없으면 다운로드를 시도한다" _test_theme_downloads_if_missing

# =============================================================================
# _install_fancybash — 사용자명/호스트명 치환
# =============================================================================

describe "xfce_env — _install_fancybash"

_test_fancybash_created() {
    local sb; sb=$(make_sandbox)
    _load_domain "$sb"

    # wget mock: fancybash.sh 내용 생성
    wget() {
        local out_path=""
        local args=("$@")
        for (( i=0; i<${#args[@]}; i++ )); do
            [[ "${args[$i]}" == "-O" ]] && out_path="${args[$((i+1))]}" && break
        done
        # \u 와 \h 포함한 stub 생성
        echo 'PS1="\u@\h \$ "' > "$out_path"
    }

    _install_fancybash "testuser" "termux"

    assert_file_exists "${HOME}/.fancybash.sh"
    # \u → testuser 로 치환됐는지
    assert_file_contains "${HOME}/.fancybash.sh" "testuser"
    cleanup_sandbox "$sb"
}
it "fancybash.sh를 생성하고 사용자명을 치환한다" _test_fancybash_created

_test_fancybash_bashrc_sourced() {
    local sb; sb=$(make_sandbox)
    _load_domain "$sb"

    wget() {
        local args=("$@"); local out_path=""
        for (( i=0; i<${#args[@]}; i++ )); do
            [[ "${args[$i]}" == "-O" ]] && out_path="${args[$((i+1))]}" && break
        done
        echo 'PS1="\u@\h"' > "$out_path"
    }

    _install_fancybash "testuser" "termux"
    assert_file_contains "${PREFIX}/etc/bash.bashrc" "fancybash"
    cleanup_sandbox "$sb"
}
it "bash.bashrc에 fancybash source 줄을 추가한다" _test_fancybash_bashrc_sourced

_test_fancybash_idempotent() {
    local sb; sb=$(make_sandbox)
    _load_domain "$sb"

    # 이미 생성된 경우
    echo 'PS1="testuser@termux"' > "${HOME}/.fancybash.sh"
    reset_mock_calls

    _install_fancybash "testuser" "termux" 2>/dev/null || true
    assert_not_called "wget"
    cleanup_sandbox "$sb"
}
it "멱등성 — .fancybash.sh가 이미 있으면 재다운로드하지 않는다" _test_fancybash_idempotent

# =============================================================================
# setup_xfce_fonts — 멱등성
# =============================================================================

describe "xfce_env — setup_xfce_fonts"

_test_fonts_dir_created() {
    local sb; sb=$(make_sandbox)
    _load_domain "$sb"

    setup_xfce_fonts 2>/dev/null || true
    assert_dir_exists "${HOME}/.fonts"
    cleanup_sandbox "$sb"
}
it ".fonts 디렉토리를 생성한다" _test_fonts_dir_created

_test_noto_emoji_skipped_if_exists() {
    local sb; sb=$(make_sandbox)
    _load_domain "$sb"
    reset_mock_calls

    touch "${HOME}/.fonts/NotoColorEmoji-Regular.ttf"

    _install_noto_emoji 2>/dev/null || true
    assert_not_called "wget"
    cleanup_sandbox "$sb"
}
it "멱등성 — NotoColorEmoji가 이미 있으면 재다운로드하지 않는다" _test_noto_emoji_skipped_if_exists

print_results
