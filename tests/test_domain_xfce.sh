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
        # 실제 fancybash.sh 구조 모사: 프롬프트 user/host 정의 라인 +
        # 무관한  유니코드 이스케이프(TRIANGLE 구분자)
        cat > "$out_path" << 'FB'
local PROMT_USER=$"$TEXT_FORMAT_1 \u "
local PROMT_HOST=$"$TEXT_FORMAT_2 \h "
local TRIANGLE=$'\uE0B0'
FB
    }

    _install_fancybash "testuser" "termux"

    assert_file_exists "${HOME}/.fancybash.sh"
    # PROMT_USER 의 \u → testuser 로 치환됐는지
    assert_file_contains "${HOME}/.fancybash.sh" "testuser"
    # 무관한 (TRIANGLE 구분자)는 손상되지 않아야 함 (finding #14 회귀 가드)
    assert_file_contains "${HOME}/.fancybash.sh" 'uE0B0'
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

# =============================================================================
# _install_fluent_cursor / _install_cascadia_code / _install_meslo_nerd /
# _install_termux_font — 멱등성
# =============================================================================

describe "xfce_env — 폰트·커서 멱등성"

_test_fluent_cursor_skipped_if_exists() {
    local sb; sb=$(make_sandbox)
    _load_domain "$sb"
    reset_mock_calls
    mkdir -p "${PREFIX}/share/icons/dist-dark"
    _install_fluent_cursor 2>/dev/null || true
    assert_not_called "wget"
    cleanup_sandbox "$sb"
}
it "멱등성 — dist-dark 커서가 이미 있으면 재다운로드하지 않는다" _test_fluent_cursor_skipped_if_exists

_test_cascadia_skipped_if_exists() {
    local sb; sb=$(make_sandbox)
    _load_domain "$sb"
    reset_mock_calls
    touch "${HOME}/.fonts/CascadiaCode.otf"
    _install_cascadia_code 2>/dev/null || true
    assert_not_called "wget"
    cleanup_sandbox "$sb"
}
it "멱등성 — CascadiaCode가 이미 있으면 재다운로드하지 않는다" _test_cascadia_skipped_if_exists

_test_meslo_skipped_if_exists() {
    local sb; sb=$(make_sandbox)
    _load_domain "$sb"
    reset_mock_calls
    # ryanoasis/nerd-fonts Meslo.zip이 제공하는 실제 파일명 (family: "MesloLGS Nerd Font Mono")
    touch "${HOME}/.fonts/MesloLGSNerdFont-Regular.ttf"
    _install_meslo_nerd 2>/dev/null || true
    assert_not_called "wget"
    cleanup_sandbox "$sb"
}
it "멱등성 — MesloLGSNerdFont-Regular.ttf가 이미 있으면 재다운로드하지 않는다" _test_meslo_skipped_if_exists

_test_termux_font_skipped_if_exists() {
    local sb; sb=$(make_sandbox)
    _load_domain "$sb"
    reset_mock_calls
    touch "${HOME}/.termux/font.ttf"
    _install_termux_font 2>/dev/null || true
    assert_not_called "wget"
    cleanup_sandbox "$sb"
}
it "멱등성 — termux font.ttf가 이미 있으면 재다운로드하지 않는다" _test_termux_font_skipped_if_exists

# =============================================================================
# _setup_autostart_config — SCRIPT_DIR cp / wget 폴백 / 멱등성
# =============================================================================

describe "xfce_env — _setup_autostart_config"

# 실제 프로젝트 루트 (tar/config/ 포함)
_REAL_PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

_test_autostart_copies_from_repo() {
    local sb; sb=$(make_sandbox)
    _load_domain "$sb"
    export SCRIPT_DIR="${_REAL_PROJECT_DIR}"

    _setup_autostart_config 2>/dev/null || true

    assert_file_exists "${HOME}/.config/autostart/conky.desktop"
    assert_file_exists "${HOME}/.config/autostart/org.flameshot.Flameshot.desktop"
    assert_file_exists "${HOME}/.config/xfce4/xfconf/xfce-perchannel-xml/xsettings.xml"
    assert_file_exists "${HOME}/.config/xfce4/xfconf/xfce-perchannel-xml/xfwm4.xml"
    cleanup_sandbox "$sb"
}
it "SCRIPT_DIR 있으면 tar/config에서 직접 복사한다" _test_autostart_copies_from_repo

_test_autostart_idempotent() {
    local sb; sb=$(make_sandbox)
    _load_domain "$sb"
    export SCRIPT_DIR="${_REAL_PROJECT_DIR}"

    _setup_autostart_config 2>/dev/null || true
    local mtime1; mtime1=$(stat -c %Y "${HOME}/.config/autostart/conky.desktop")
    sleep 1
    _setup_autostart_config 2>/dev/null || true
    local mtime2; mtime2=$(stat -c %Y "${HOME}/.config/autostart/conky.desktop")

    assert_eq "$mtime1" "$mtime2" "멱등성: conky.desktop이 덮어쓰이면 안 된다"
    cleanup_sandbox "$sb"
}
it "멱등성 — conky.desktop이 이미 있으면 재복사하지 않는다" _test_autostart_idempotent

# =============================================================================
# _migrate_dbus_propagate_path — /usr/bin/env → bash
# =============================================================================

describe "xfce_env — _migrate_dbus_propagate_path"

_test_dbus_propagate_fixes_path() {
    local sb; sb=$(make_sandbox)
    _load_domain "$sb"
    mkdir -p "${HOME}/.config/autostart"
    cat > "${HOME}/.config/autostart/00-env-dbus-propagate.desktop" << 'EOF'
[Desktop Entry]
Exec=/usr/bin/env bash -lc 'dbus-update-activation-environment --all'
EOF

    _migrate_dbus_propagate_path

    assert_file_contains "${HOME}/.config/autostart/00-env-dbus-propagate.desktop" "Exec=bash"
    assert_file_not_contains "${HOME}/.config/autostart/00-env-dbus-propagate.desktop" "/usr/bin/env"
    cleanup_sandbox "$sb"
}
it "/usr/bin/env를 bash 직접 호출로 변환한다" _test_dbus_propagate_fixes_path

_test_dbus_propagate_idempotent() {
    local sb; sb=$(make_sandbox)
    _load_domain "$sb"
    mkdir -p "${HOME}/.config/autostart"
    cat > "${HOME}/.config/autostart/00-env-dbus-propagate.desktop" << 'EOF'
[Desktop Entry]
Exec=bash -lc 'dbus-update-activation-environment --all'
EOF

    _migrate_dbus_propagate_path

    assert_file_contains "${HOME}/.config/autostart/00-env-dbus-propagate.desktop" "Exec=bash"
    cleanup_sandbox "$sb"
}
it "멱등성 — 이미 수정된 경우 건너뛴다" _test_dbus_propagate_idempotent

# =============================================================================
# _migrate_conky_exec_ampersand — Exec 끝 & 제거
# =============================================================================

describe "xfce_env — _migrate_conky_exec_ampersand"

_test_conky_removes_ampersand() {
    local sb; sb=$(make_sandbox)
    _load_domain "$sb"
    mkdir -p "${HOME}/.config/autostart"
    cat > "${HOME}/.config/autostart/conky.desktop" << 'EOF'
[Desktop Entry]
Exec=prun conky -c .config/conky/Alterf/Alterf.conf &
EOF

    _migrate_conky_exec_ampersand

    assert_file_contains "${HOME}/.config/autostart/conky.desktop" "Exec=prun conky"
    assert_file_not_contains "${HOME}/.config/autostart/conky.desktop" " &"
    cleanup_sandbox "$sb"
}
it "Exec 끝의 &를 제거한다" _test_conky_removes_ampersand

_test_conky_ampersand_idempotent() {
    local sb; sb=$(make_sandbox)
    _load_domain "$sb"
    mkdir -p "${HOME}/.config/autostart"
    cat > "${HOME}/.config/autostart/conky.desktop" << 'EOF'
[Desktop Entry]
Exec=prun conky -c .config/conky/Alterf/Alterf.conf
EOF

    _migrate_conky_exec_ampersand

    assert_file_contains "${HOME}/.config/autostart/conky.desktop" "Exec=prun conky"
    cleanup_sandbox "$sb"
}
it "멱등성 — &가 없으면 건너뛴다" _test_conky_ampersand_idempotent

# =============================================================================
# _migrate_fix_x11_input — fix-x11-input.desktop 항상 덮어쓰기
# =============================================================================

describe "xfce_env — _migrate_fix_x11_input"

_test_fix_x11_input_copies() {
    local sb; sb=$(make_sandbox)
    _load_domain "$sb"
    export SCRIPT_DIR="${_REAL_PROJECT_DIR}"
    mkdir -p "${HOME}/.config/autostart"

    _migrate_fix_x11_input

    assert_file_exists "${HOME}/.config/autostart/fix-x11-input.desktop"
    assert_file_contains "${HOME}/.config/autostart/fix-x11-input.desktop" "xdotool"
    cleanup_sandbox "$sb"
}
it "fix-x11-input.desktop을 복사한다" _test_fix_x11_input_copies

_test_fix_x11_input_overwrites() {
    local sb; sb=$(make_sandbox)
    _load_domain "$sb"
    export SCRIPT_DIR="${_REAL_PROJECT_DIR}"
    mkdir -p "${HOME}/.config/autostart"
    echo "old content" > "${HOME}/.config/autostart/fix-x11-input.desktop"

    _migrate_fix_x11_input

    assert_file_contains "${HOME}/.config/autostart/fix-x11-input.desktop" "xdotool"
    assert_file_not_contains "${HOME}/.config/autostart/fix-x11-input.desktop" "old content"
    cleanup_sandbox "$sb"
}
it "기존 파일을 항상 최신 버전으로 덮어쓴다" _test_fix_x11_input_overwrites

_test_fix_x11_input_no_source_skips() {
    local sb; sb=$(make_sandbox)
    _load_domain "$sb"
    export SCRIPT_DIR="${sb}/nonexistent"

    _migrate_fix_x11_input

    [ ! -f "${HOME}/.config/autostart/fix-x11-input.desktop" ]
    cleanup_sandbox "$sb"
}
it "소스 파일 없으면 건너뛴다" _test_fix_x11_input_no_source_skips

# =============================================================================
# _migrate_terminal_font — terminalrc + xfconf xml 폰트 패치
# =============================================================================

describe "xfce_env — _migrate_terminal_font"

_test_terminal_font_patches_terminalrc() {
    local sb; sb=$(make_sandbox)
    _load_domain "$sb"
    mkdir -p "${HOME}/.config/xfce4/terminal"
    echo 'FontName=Cascadia Mono PL 12' > "${HOME}/.config/xfce4/terminal/terminalrc"

    _migrate_terminal_font

    assert_file_contains "${HOME}/.config/xfce4/terminal/terminalrc" "MesloLGS Nerd Font Mono 12"
    cleanup_sandbox "$sb"
}
it "terminalrc의 구 폰트를 MesloLGS Nerd Font Mono로 패치한다" _test_terminal_font_patches_terminalrc

_test_terminal_font_patches_xml() {
    local sb; sb=$(make_sandbox)
    _load_domain "$sb"
    mkdir -p "${HOME}/.config/xfce4/xfconf/xfce-perchannel-xml"
    cat > "${HOME}/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-terminal.xml" << 'EOF'
<channel name="xfce4-terminal">
  <property name="font-name" type="string" value="MesloLGS NF 12"/>
</channel>
EOF

    _migrate_terminal_font

    assert_file_contains "${HOME}/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-terminal.xml" 'value="MesloLGS Nerd Font Mono 12"'
    cleanup_sandbox "$sb"
}
it "xfconf xml의 구 폰트를 MesloLGS Nerd Font Mono로 패치한다" _test_terminal_font_patches_xml

_test_terminal_font_idempotent() {
    local sb; sb=$(make_sandbox)
    _load_domain "$sb"
    mkdir -p "${HOME}/.config/xfce4/terminal"
    echo 'FontName=MesloLGS Nerd Font Mono 12' > "${HOME}/.config/xfce4/terminal/terminalrc"

    _migrate_terminal_font

    assert_file_contains "${HOME}/.config/xfce4/terminal/terminalrc" "MesloLGS Nerd Font Mono 12"
    cleanup_sandbox "$sb"
}
it "멱등성 — 이미 올바른 폰트면 변경하지 않는다" _test_terminal_font_idempotent

# =============================================================================
# _migrate_borderless_maximize — xfwm4 true→false
# =============================================================================

describe "xfce_env — _migrate_borderless_maximize"

_test_borderless_maximize_patches() {
    local sb; sb=$(make_sandbox)
    _load_domain "$sb"
    mkdir -p "${HOME}/.config/xfce4/xfconf/xfce-perchannel-xml"
    cat > "${HOME}/.config/xfce4/xfconf/xfce-perchannel-xml/xfwm4.xml" << 'EOF'
<channel name="xfwm4">
  <property name="borderless_maximize" type="bool" value="true"/>
</channel>
EOF

    _migrate_borderless_maximize

    assert_file_contains "${HOME}/.config/xfce4/xfconf/xfce-perchannel-xml/xfwm4.xml" 'value="false"'
    cleanup_sandbox "$sb"
}
it "borderless_maximize를 true→false로 패치한다" _test_borderless_maximize_patches

_test_borderless_maximize_idempotent() {
    local sb; sb=$(make_sandbox)
    _load_domain "$sb"
    mkdir -p "${HOME}/.config/xfce4/xfconf/xfce-perchannel-xml"
    cat > "${HOME}/.config/xfce4/xfconf/xfce-perchannel-xml/xfwm4.xml" << 'EOF'
<channel name="xfwm4">
  <property name="borderless_maximize" type="bool" value="false"/>
</channel>
EOF

    _migrate_borderless_maximize

    local count
    count=$(grep -c 'value="false"' "${HOME}/.config/xfce4/xfconf/xfce-perchannel-xml/xfwm4.xml")
    assert_eq "1" "$count"
    cleanup_sandbox "$sb"
}
it "멱등성 — 이미 false면 변경하지 않는다" _test_borderless_maximize_idempotent

# =============================================================================
# _migrate_disable_compositing — xfwm4 컴포지터 off
# =============================================================================

describe "xfce_env — _migrate_disable_compositing"

_test_disable_compositing_patches() {
    local sb; sb=$(make_sandbox)
    _load_domain "$sb"
    mkdir -p "${HOME}/.config/xfce4/xfconf/xfce-perchannel-xml"
    cat > "${HOME}/.config/xfce4/xfconf/xfce-perchannel-xml/xfwm4.xml" << 'EOF'
<channel name="xfwm4">
  <property name="use_compositing" type="bool" value="true"/>
</channel>
EOF

    _migrate_disable_compositing

    assert_file_contains "${HOME}/.config/xfce4/xfconf/xfce-perchannel-xml/xfwm4.xml" 'use_compositing" type="bool" value="false"'
    cleanup_sandbox "$sb"
}
it "use_compositing을 true→false로 패치한다" _test_disable_compositing_patches

_test_disable_compositing_idempotent() {
    local sb; sb=$(make_sandbox)
    _load_domain "$sb"
    mkdir -p "${HOME}/.config/xfce4/xfconf/xfce-perchannel-xml"
    cat > "${HOME}/.config/xfce4/xfconf/xfce-perchannel-xml/xfwm4.xml" << 'EOF'
<channel name="xfwm4">
  <property name="use_compositing" type="bool" value="false"/>
</channel>
EOF

    _migrate_disable_compositing

    assert_file_contains "${HOME}/.config/xfce4/xfconf/xfce-perchannel-xml/xfwm4.xml" 'value="false"'
    cleanup_sandbox "$sb"
}
it "멱등성 — 이미 false면 변경하지 않는다" _test_disable_compositing_idempotent

# =============================================================================
# _migrate_remove_actions_plugin — 패널 actions 플러그인 제거
# =============================================================================

describe "xfce_env — _migrate_remove_actions_plugin"

_test_remove_actions_plugin() {
    local sb; sb=$(make_sandbox)
    _load_domain "$sb"
    mkdir -p "${HOME}/.config/xfce4/xfconf/xfce-perchannel-xml"
    cat > "${HOME}/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-panel.xml" << 'EOF'
<channel name="xfce4-panel">
  <property name="plugin-ids" type="array">
    <value type="int" value="1"/>
    <value type="int" value="20"/>
  </property>
  <property name="plugin-20" type="string" value="actions">
    <property name="items" type="array"/>
  </property>
</channel>
EOF

    _migrate_remove_actions_plugin

    assert_file_not_contains "${HOME}/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-panel.xml" 'value="20"'
    assert_file_not_contains "${HOME}/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-panel.xml" 'value="actions"'
    cleanup_sandbox "$sb"
}
it "패널에서 actions 플러그인(plugin-20)을 제거한다" _test_remove_actions_plugin

_test_remove_actions_plugin_idempotent() {
    local sb; sb=$(make_sandbox)
    _load_domain "$sb"
    mkdir -p "${HOME}/.config/xfce4/xfconf/xfce-perchannel-xml"
    cat > "${HOME}/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-panel.xml" << 'EOF'
<channel name="xfce4-panel">
  <property name="plugin-ids" type="array">
    <value type="int" value="1"/>
  </property>
</channel>
EOF

    _migrate_remove_actions_plugin

    assert_file_contains "${HOME}/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-panel.xml" 'value="1"'
    cleanup_sandbox "$sb"
}
it "멱등성 — actions가 없으면 변경하지 않는다" _test_remove_actions_plugin_idempotent

# =============================================================================
# 회귀: set -e + ((i++)) 폭탄 — || true 없이 끝까지 실행 검증
# =============================================================================

describe "xfce_env — set -e safe counter (regression)"

_test_setup_xfce_packages_completes_under_set_e() {
    local sb; sb=$(make_sandbox)
    _load_domain "$sb"
    reset_mock_calls
    MOCK_INSTALLED_PKGS=""

    # || true 없이 호출 — i=0에서 시작하는 카운터 루프가 set -e로 죽지 않음을 보증
    setup_xfce_packages

    local install_count=0
    for call in "${MOCK_CALLS[@]:-}"; do
        [[ "$call" == pkg_install* ]] && install_count=$((install_count + 1))
    done
    [ "$install_count" -eq "${#PKGS_TERMUX_XFCE[@]}" ]
    cleanup_sandbox "$sb"
}
it "setup_xfce_packages가 set -e 하에서 끝까지 실행된다" _test_setup_xfce_packages_completes_under_set_e

# =============================================================================
# setup_xfce_theme — 다운로드 실패 시에도 || true 로 계속 진행
# =============================================================================

describe "xfce_env — setup_xfce_theme (error tolerance)"

_test_xfce_theme_calls_both_installers() {
    local sb; sb=$(make_sandbox)
    _load_domain "$sb"
    THEME_CALLS=""
    _install_whitesur_theme() { THEME_CALLS+="whitesur:"; return 0; }
    _install_fluent_cursor()  { THEME_CALLS+="fluent:";  return 0; }

    setup_xfce_theme

    [[ "$THEME_CALLS" == *whitesur:* ]] && [[ "$THEME_CALLS" == *fluent:* ]]
    cleanup_sandbox "$sb"
}
it "_install_whitesur_theme + _install_fluent_cursor 둘 다 호출" _test_xfce_theme_calls_both_installers

_test_xfce_theme_continues_on_whitesur_failure() {
    local sb; sb=$(make_sandbox)
    _load_domain "$sb"
    _install_whitesur_theme() { return 1; }
    FLUENT_CALLED=0
    _install_fluent_cursor()  { FLUENT_CALLED=1; return 0; }

    # set -e 활성 환경에서도 || true 로 계속 진행되어야 함
    set -e
    setup_xfce_theme
    set +e

    [ "$FLUENT_CALLED" -eq 1 ]
    cleanup_sandbox "$sb"
}
it "whitesur 실패해도 fluent 커서 설치 계속 (|| true)" _test_xfce_theme_continues_on_whitesur_failure

_test_xfce_theme_continues_on_fluent_failure() {
    local sb; sb=$(make_sandbox)
    _load_domain "$sb"
    _install_whitesur_theme() { return 0; }
    _install_fluent_cursor()  { return 1; }

    set -e
    setup_xfce_theme
    local rc=$?
    set +e

    [ "$rc" -eq 0 ]
    cleanup_sandbox "$sb"
}
it "fluent 실패해도 setup_xfce_theme 자체는 0 반환" _test_xfce_theme_continues_on_fluent_failure

# =============================================================================
# setup_xfce_autostart — 마이그레이션 호출 순서
# =============================================================================

describe "xfce_env — setup_xfce_autostart (composition order)"

_test_xfce_autostart_calls_in_order() {
    local sb; sb=$(make_sandbox)
    _load_domain "$sb"

    AUTOSTART_LOG=$(mktemp "${TMPDIR:-/data/data/com.termux/files/usr/tmp}/autostart_log_XXXXXX")
    : > "$AUTOSTART_LOG"
    _setup_autostart_config()        { echo "config"   >> "$AUTOSTART_LOG"; }
    _migrate_fix_x11_input()         { echo "x11"      >> "$AUTOSTART_LOG"; }
    _migrate_flameshot_native()      { echo "flame"    >> "$AUTOSTART_LOG"; }
    _migrate_terminal_font()         { echo "termfont" >> "$AUTOSTART_LOG"; }
    _migrate_borderless_maximize()   { echo "border"   >> "$AUTOSTART_LOG"; }
    _migrate_disable_compositing()   { echo "comp"     >> "$AUTOSTART_LOG"; }
    _migrate_remove_actions_plugin() { echo "actions"  >> "$AUTOSTART_LOG"; }
    _migrate_dbus_propagate_path()   { echo "dbus"     >> "$AUTOSTART_LOG"; }
    _migrate_conky_exec_ampersand()  { echo "conky"    >> "$AUTOSTART_LOG"; }

    setup_xfce_autostart

    local expected="config
x11
flame
termfont
border
comp
actions
dbus
conky"
    local actual; actual=$(cat "$AUTOSTART_LOG")
    rm -f "$AUTOSTART_LOG"

    assert_eq "$expected" "$actual" "마이그레이션 호출 순서가 소스 코드와 일치해야 함"
    cleanup_sandbox "$sb"
}
it "_setup_autostart_config → 마이그레이션 8건 순서대로 호출" _test_xfce_autostart_calls_in_order

print_results
