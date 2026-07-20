#!/data/data/com.termux/files/usr/bin/bash
# =============================================================================
# TEST: domain/termux_env.sh
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/framework.sh"
source "${SCRIPT_DIR}/mocks.sh"

DOMAIN_DIR="${SCRIPT_DIR}/../domain"
_REAL_PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

_load_domain() {
    local sandbox="$1"
    setup_fs_sandbox "$sandbox"
    mock_pkg_adapter
    mock_ui_adapter
    mock_wget
    source "${DOMAIN_DIR}/packages.sh"
    # script_builder는 순수 파일 생성기(외부 의존 없음) → 실제 어댑터 로드
    source "${DOMAIN_DIR}/../adapters/output/display_x11.sh"
    source "${DOMAIN_DIR}/../adapters/output/script_builder_zenity.sh"
    source "${DOMAIN_DIR}/termux_env.sh"
}

# =============================================================================
# _setup_termux_properties
# =============================================================================

describe "termux_env — _setup_termux_properties"

_test_props_uncomments_allow_external() {
    local sb; sb=$(make_sandbox)
    _load_domain "$sb"

    _setup_termux_properties
    assert_file_contains "${HOME}/.termux/termux.properties" "^allow-external-apps = true"
    cleanup_sandbox "$sb"
}
it "allow-external-apps 주석을 해제한다" _test_props_uncomments_allow_external

_test_props_idempotent() {
    local sb; sb=$(make_sandbox)
    _load_domain "$sb"

    # 이미 설정된 상태
    echo "allow-external-apps = true" >> "${HOME}/.termux/termux.properties"
    echo "bell-character = ignore" >> "${HOME}/.termux/termux.properties"

    _setup_termux_properties

    # 중복 없이 1번만 존재해야 함
    local count
    count=$(grep -c "^allow-external-apps = true" "${HOME}/.termux/termux.properties")
    assert_eq "1" "$count" "멱등성: allow-external-apps가 1번만 있어야 한다"
    cleanup_sandbox "$sb"
}
it "멱등성 — 이미 설정된 경우 중복 추가하지 않는다" _test_props_idempotent

_test_props_appends_when_no_comment() {
    local sb; sb=$(make_sandbox)
    _load_domain "$sb"

    # 주석 라인 없이 빈 properties 파일
    echo "# 임의 설정" > "${HOME}/.termux/termux.properties"

    _setup_termux_properties
    assert_file_contains "${HOME}/.termux/termux.properties" "^allow-external-apps = true"
    assert_file_contains "${HOME}/.termux/termux.properties" "^bell-character = ignore"
    cleanup_sandbox "$sb"
}
it "주석 라인 없으면 직접 추가한다 (폴백)" _test_props_appends_when_no_comment

# =============================================================================
# _setup_aliases
# =============================================================================

describe "termux_env — _setup_aliases"

_test_aliases_written() {
    local sb; sb=$(make_sandbox)
    _load_domain "$sb"

    _setup_aliases
    assert_file_contains "${PREFIX}/etc/bash.bashrc" "termux-xfce-aliases"
    assert_file_contains "${PREFIX}/etc/bash.bashrc" "alias ll="
    assert_file_contains "${PREFIX}/etc/bash.bashrc" "alias shutdown="
    cleanup_sandbox "$sb"
}
it "bash.bashrc에 alias 블록을 추가한다" _test_aliases_written

_test_aliases_idempotent() {
    local sb; sb=$(make_sandbox)
    _load_domain "$sb"

    _setup_aliases
    _setup_aliases  # 두 번 호출

    local count
    count=$(grep -c "termux-xfce-aliases" "${PREFIX}/etc/bash.bashrc")
    assert_eq "1" "$count" "멱등성: alias 블록이 1번만 있어야 한다"
    cleanup_sandbox "$sb"
}
it "멱등성 — alias 블록이 중복 추가되지 않는다" _test_aliases_idempotent

# =============================================================================
# _setup_locale
# =============================================================================

describe "termux_env — _setup_locale"

_test_locale_written() {
    local sb; sb=$(make_sandbox)
    _load_domain "$sb"

    _setup_locale
    assert_file_contains "${PREFIX}/etc/bash.bashrc" "termux-xfce-locale"
    assert_file_contains "${PREFIX}/etc/bash.bashrc" "LANG=ko_KR.UTF-8"
    assert_file_contains "${PREFIX}/etc/bash.bashrc" "XDG_CONFIG_HOME"
    cleanup_sandbox "$sb"
}
it "bash.bashrc에 locale 환경변수를 추가한다" _test_locale_written

_test_locale_idempotent() {
    local sb; sb=$(make_sandbox)
    _load_domain "$sb"

    _setup_locale
    _setup_locale

    local count
    count=$(grep -c "termux-xfce-locale" "${PREFIX}/etc/bash.bashrc")
    assert_eq "1" "$count" "멱등성: locale 블록이 1번만 있어야 한다"
    cleanup_sandbox "$sb"
}
it "멱등성 — locale 블록이 중복 추가되지 않는다" _test_locale_idempotent

# =============================================================================
# _setup_start_xfce
# =============================================================================

describe "termux_env — _setup_start_xfce"

_test_startxfce_created() {
    local sb; sb=$(make_sandbox)
    _load_domain "$sb"

    _setup_start_xfce
    assert_file_exists "${HOME}/.shortcuts/startXFCE"
    # 실행 권한 확인
    [ -x "${HOME}/.shortcuts/startXFCE" ]
    cleanup_sandbox "$sb"
}
it "startXFCE 스크립트를 생성한다" _test_startxfce_created

_test_startxfce_has_gpu_detection() {
    local sb; sb=$(make_sandbox)
    _load_domain "$sb"

    _setup_start_xfce
    assert_file_contains "${HOME}/.shortcuts/startXFCE" "GPU_MODEL"
    assert_file_contains "${HOME}/.shortcuts/startXFCE" "MESA_LOADER_DRIVER_OVERRIDE"
    assert_file_contains "${HOME}/.shortcuts/startXFCE" "kgsl"
    cleanup_sandbox "$sb"
}
it "startXFCE에 GPU 자동 감지 로직이 있다" _test_startxfce_has_gpu_detection

_test_startxfce_overwrites_on_update() {
    local sb; sb=$(make_sandbox)
    _load_domain "$sb"

    # 구버전 startXFCE
    echo "old_version" > "${HOME}/.shortcuts/startXFCE"

    _setup_start_xfce

    # 새 내용으로 덮어씀 (가드 없음 — 업데이트 보장)
    assert_file_contains "${HOME}/.shortcuts/startXFCE" "_kill_display_session"
    cleanup_sandbox "$sb"
}
it "startXFCE를 항상 최신 버전으로 재생성한다" _test_startxfce_overwrites_on_update

# =============================================================================
# _setup_prun
# =============================================================================

describe "termux_env — _setup_prun"

_test_prun_created() {
    local sb; sb=$(make_sandbox)
    _load_domain "$sb"

    _setup_prun
    assert_file_exists "${PREFIX}/bin/prun"
    [ -x "${PREFIX}/bin/prun" ]
    cleanup_sandbox "$sb"
}
it "prun 스크립트를 생성한다" _test_prun_created

_test_prun_has_config_source() {
    local sb; sb=$(make_sandbox)
    _load_domain "$sb"

    _setup_prun
    assert_file_contains "${PREFIX}/bin/prun" "CONFIG"
    assert_file_contains "${PREFIX}/bin/prun" "proot-distro login"
    cleanup_sandbox "$sb"
}
it "prun은 config에서 DISTRO를 읽는다" _test_prun_has_config_source

_test_prun_overwrites_old_version() {
    local sb; sb=$(make_sandbox)
    _load_domain "$sb"

    echo "old_version" > "${PREFIX}/bin/prun"
    _setup_prun

    # 최신 내용으로 갱신됨 (가드 없음 — test_prun_ld_preload.sh와 일관)
    assert_file_contains "${PREFIX}/bin/prun" "proot-distro login"
    cleanup_sandbox "$sb"
}
it "prun을 항상 최신 버전으로 재생성한다" _test_prun_overwrites_old_version

# =============================================================================
# _setup_cp2menu
# =============================================================================

describe "termux_env — _setup_cp2menu"

_test_cp2menu_created() {
    local sb; sb=$(make_sandbox)
    _load_domain "$sb"

    _setup_cp2menu
    assert_file_exists "${PREFIX}/bin/cp2menu"
    assert_file_exists "${PREFIX}/share/applications/cp2menu.desktop"
    cleanup_sandbox "$sb"
}
it "cp2menu 스크립트와 desktop 파일을 생성한다" _test_cp2menu_created

_test_cp2menu_desktop_valid() {
    local sb; sb=$(make_sandbox)
    _load_domain "$sb"

    _setup_cp2menu
    assert_file_contains "${PREFIX}/share/applications/cp2menu.desktop" "[Desktop Entry]"
    assert_file_contains "${PREFIX}/share/applications/cp2menu.desktop" "Exec=cp2menu"
    cleanup_sandbox "$sb"
}
it "cp2menu.desktop에 필수 필드가 있다" _test_cp2menu_desktop_valid

# =============================================================================
# _setup_korean_env
# =============================================================================

describe "termux_env — _setup_korean_env (nimf)"

_test_korean_nimf_desktop_created() {
    local sb; sb=$(make_sandbox)
    _load_domain "$sb"

    _setup_korean_env
    assert_file_exists "${HOME}/.config/autostart/nimf.desktop"
    assert_file_contains "${HOME}/.config/autostart/nimf.desktop" "Exec=nimf"
    cleanup_sandbox "$sb"
}
it "nimf.desktop 자동시작 파일을 생성한다" _test_korean_nimf_desktop_created

_test_korean_env_idempotent() {
    local sb; sb=$(make_sandbox)
    _load_domain "$sb"

    _setup_korean_env
    local mtime1; mtime1=$(stat -c %Y "${HOME}/.config/autostart/nimf.desktop")
    sleep 1
    _setup_korean_env
    local mtime2; mtime2=$(stat -c %Y "${HOME}/.config/autostart/nimf.desktop")
    assert_eq "$mtime1" "$mtime2" "멱등성"
    cleanup_sandbox "$sb"
}
it "멱등성 — nimf.desktop이 이미 있으면 덮어쓰지 않는다" _test_korean_env_idempotent

# (_detect_and_log_gpu, _setup_tur_multilib: 삭제된 함수 — 테스트 제거)

# =============================================================================
# _setup_kill_display — bin 생성 및 desktop entry
# =============================================================================

describe "termux_env — _setup_kill_display"

_test_kill_display_created() {
    local sb; sb=$(make_sandbox)
    _load_domain "$sb"

    _setup_kill_display 2>/dev/null || true

    assert_file_exists "${PREFIX}/bin/kill_display_session"
    assert_file_exists "${PREFIX}/share/applications/kill_display_session.desktop"
    cleanup_sandbox "$sb"
}
it "kill_display_session 스크립트와 desktop 파일을 생성한다" _test_kill_display_created

_test_kill_display_always_regenerated() {
    local sb; sb=$(make_sandbox)
    _load_domain "$sb"

    _setup_kill_display 2>/dev/null || true
    local mtime1; mtime1=$(stat -c %Y "${PREFIX}/bin/kill_display_session")
    sleep 1
    _setup_kill_display 2>/dev/null || true
    local mtime2; mtime2=$(stat -c %Y "${PREFIX}/bin/kill_display_session")

    assert_ne "$mtime1" "$mtime2" "항상 재생성되어야 한다"
    cleanup_sandbox "$sb"
}
it "kill_display_session을 항상 최신 버전으로 재생성한다" _test_kill_display_always_regenerated

# =============================================================================
# _migrate_desktop_to_prun_gui — 기존 prun → prun-gui 마이그레이션
# =============================================================================

describe "termux_env — _migrate_desktop_to_prun_gui"

_test_migrate_prun_to_prun_gui() {
    local sb; sb=$(make_sandbox)
    _load_domain "$sb"

    # prun 사용하는 .desktop 파일 생성
    cat > "${PREFIX}/share/applications/testapp.desktop" << 'EOF'
[Desktop Entry]
Name=TestApp
Exec=bash -c "prun testapp --flag </dev/null >/dev/null 2>&1 &"
EOF

    _migrate_desktop_to_prun_gui

    assert_file_contains "${PREFIX}/share/applications/testapp.desktop" "prun-gui 'TestApp' --"
    cleanup_sandbox "$sb"
}
it "prun 사용 .desktop 파일을 prun-gui로 변환한다" _test_migrate_prun_to_prun_gui

_test_migrate_skips_already_prun_gui() {
    local sb; sb=$(make_sandbox)
    _load_domain "$sb"

    # 이미 prun-gui 사용 중인 .desktop
    cat > "${PREFIX}/share/applications/already.desktop" << 'EOF'
[Desktop Entry]
Name=Already
Exec=bash -c "prun-gui Already -- someapp </dev/null >/dev/null 2>&1 &"
EOF

    _migrate_desktop_to_prun_gui

    local count
    count=$(grep -c "prun-gui" "${PREFIX}/share/applications/already.desktop")
    assert_eq "1" "$count" "멱등성: prun-gui가 1번만 있어야 한다"
    cleanup_sandbox "$sb"
}
it "멱등성 — 이미 prun-gui인 파일은 건너뛴다" _test_migrate_skips_already_prun_gui

_test_migrate_skips_non_proot() {
    local sb; sb=$(make_sandbox)
    _load_domain "$sb"

    # prun을 사용하지 않는 native .desktop
    cat > "${PREFIX}/share/applications/native.desktop" << 'EOF'
[Desktop Entry]
Name=NativeApp
Exec=firefox
EOF

    _migrate_desktop_to_prun_gui

    assert_file_contains "${PREFIX}/share/applications/native.desktop" "^Exec=firefox"
    cleanup_sandbox "$sb"
}
it "prun 미사용 .desktop 파일은 건드리지 않는다" _test_migrate_skips_non_proot

_test_migrate_uses_name_field() {
    local sb; sb=$(make_sandbox)
    _load_domain "$sb"

    cat > "${PREFIX}/share/applications/named.desktop" << 'EOF'
[Desktop Entry]
Name=LibreOffice Writer
Exec=bash -c "prun libreoffice --writer </dev/null >/dev/null 2>&1 &"
EOF

    _migrate_desktop_to_prun_gui

    assert_file_contains "${PREFIX}/share/applications/named.desktop" "prun-gui 'LibreOffice Writer' --"
    cleanup_sandbox "$sb"
}
it "Name= 필드를 prun-gui 앱 이름으로 사용한다" _test_migrate_uses_name_field

# =============================================================================
# _append_to_rc — RC 파일 멱등 추가 유틸
# =============================================================================

describe "termux_env — _append_to_rc"

_test_append_to_rc_adds_content() {
    local sb; sb=$(make_sandbox)
    _load_domain "$sb"

    _append_to_rc "# test-marker" "# test-marker\nexport FOO=bar" "${PREFIX}/etc/bash.bashrc"
    assert_file_contains "${PREFIX}/etc/bash.bashrc" "test-marker"
    cleanup_sandbox "$sb"
}
it "마커가 없으면 내용을 추가한다" _test_append_to_rc_adds_content

_test_append_to_rc_idempotent() {
    local sb; sb=$(make_sandbox)
    _load_domain "$sb"

    _append_to_rc "# test-marker" "# test-marker\nexport FOO=bar" "${PREFIX}/etc/bash.bashrc"
    _append_to_rc "# test-marker" "# test-marker\nexport FOO=bar" "${PREFIX}/etc/bash.bashrc"

    local count
    count=$(grep -c "test-marker" "${PREFIX}/etc/bash.bashrc")
    assert_eq "1" "$count"
    cleanup_sandbox "$sb"
}
it "멱등성 — 마커가 이미 있으면 중복 추가하지 않는다" _test_append_to_rc_idempotent

_test_append_to_rc_returns_zero_when_file_absent() {
    local sb; sb=$(make_sandbox)
    _load_domain "$sb"
    local missing="${sb}/does_not_exist.rc"

    # 존재하지 않는 파일 — silent return 0 (set -e 트립 안됨)
    set -e
    _append_to_rc "# m" "# m\nexport X=1" "$missing"
    local rc=$?
    set +e

    assert_eq "0" "$rc"
    [ ! -f "$missing" ]  # 파일이 새로 생성되어서도 안됨
    cleanup_sandbox "$sb"
}
it "파일이 없으면 0 반환 + 새로 생성하지 않는다" _test_append_to_rc_returns_zero_when_file_absent

# =============================================================================
# _rc_targets — zsh 존재 여부에 따른 RC 파일 목록
# =============================================================================

describe "termux_env — _rc_targets"

_test_rc_targets_returns_bashrc_only_when_no_zshrc() {
    local sb; sb=$(make_sandbox)
    _load_domain "$sb"
    rm -f "$HOME/.zshrc"

    local out; out=$(_rc_targets)
    [[ "$out" == *"bash.bashrc"* ]]
    [[ "$out" != *".zshrc"* ]]
    cleanup_sandbox "$sb"
}
it ".zshrc가 없으면 bash.bashrc만 반환" _test_rc_targets_returns_bashrc_only_when_no_zshrc

_test_rc_targets_includes_zshrc_when_zsh_present() {
    local sb; sb=$(make_sandbox)
    _load_domain "$sb"
    touch "$HOME/.zshrc"
    # zsh가 PATH에 있는 것처럼 mock
    command() {
        if [ "$1" = "-v" ] && [ "$2" = "zsh" ]; then return 0; fi
        builtin command "$@"
    }

    local out; out=$(_rc_targets)
    [[ "$out" == *"bash.bashrc"* ]]
    [[ "$out" == *".zshrc"* ]]
    cleanup_sandbox "$sb"
}
it "zsh + .zshrc 둘 다 있으면 양쪽 모두 반환" _test_rc_targets_includes_zshrc_when_zsh_present

# =============================================================================
# _setup_xdg_runtime — XDG_RUNTIME_DIR mode 700
# =============================================================================

describe "termux_env — _setup_xdg_runtime"

_test_xdg_runtime_written() {
    local sb; sb=$(make_sandbox)
    _load_domain "$sb"

    _setup_xdg_runtime
    assert_file_contains "${PREFIX}/etc/bash.bashrc" "termux-xfce-xdg-runtime"
    assert_file_contains "${PREFIX}/etc/bash.bashrc" "XDG_RUNTIME_DIR"
    assert_file_contains "${PREFIX}/etc/bash.bashrc" "chmod 700"
    cleanup_sandbox "$sb"
}
it "bash.bashrc에 XDG_RUNTIME_DIR 블록을 추가한다" _test_xdg_runtime_written

_test_xdg_runtime_idempotent() {
    local sb; sb=$(make_sandbox)
    _load_domain "$sb"

    _setup_xdg_runtime
    _setup_xdg_runtime

    local count
    count=$(grep -c "termux-xfce-xdg-runtime" "${PREFIX}/etc/bash.bashrc")
    assert_eq "1" "$count"
    cleanup_sandbox "$sb"
}
it "멱등성 — XDG_RUNTIME_DIR 블록이 중복 추가되지 않는다" _test_xdg_runtime_idempotent

_test_xdg_runtime_removes_old_tmpdir_line() {
    local sb; sb=$(make_sandbox)
    _load_domain "$sb"

    # 구버전 라인 삽입 (마이그레이션 대상)
    echo 'export XDG_RUNTIME_DIR="${TMPDIR:-/data/data/com.termux/files/usr/tmp}"' >> "${PREFIX}/etc/bash.bashrc"

    _setup_xdg_runtime

    assert_file_not_contains "${PREFIX}/etc/bash.bashrc" 'XDG_RUNTIME_DIR="${TMPDIR'
    assert_file_contains "${PREFIX}/etc/bash.bashrc" "termux-xfce-xdg-runtime"
    cleanup_sandbox "$sb"
}
it "구버전 TMPDIR 기반 XDG_RUNTIME_DIR 라인을 제거한다" _test_xdg_runtime_removes_old_tmpdir_line

# =============================================================================
# _setup_gpu_env — GPU 환경변수 RC 추가
# =============================================================================

describe "termux_env — _setup_gpu_env"

_test_gpu_env_written() {
    local sb; sb=$(make_sandbox)
    _load_domain "$sb"

    _setup_gpu_env
    assert_file_contains "${PREFIX}/etc/bash.bashrc" "termux-xfce-gpu"
    assert_file_contains "${PREFIX}/etc/bash.bashrc" "MESA_LOADER_DRIVER_OVERRIDE"
    assert_file_contains "${PREFIX}/etc/bash.bashrc" "GSK_RENDERER=cairo"
    cleanup_sandbox "$sb"
}
it "bash.bashrc에 GPU 환경변수 블록을 추가한다" _test_gpu_env_written

_test_gpu_env_idempotent() {
    local sb; sb=$(make_sandbox)
    _load_domain "$sb"

    _setup_gpu_env
    _setup_gpu_env

    local count
    count=$(grep -c "termux-xfce-gpu" "${PREFIX}/etc/bash.bashrc")
    assert_eq "1" "$count"
    cleanup_sandbox "$sb"
}
it "멱등성 — GPU 블록이 중복 추가되지 않는다" _test_gpu_env_idempotent

# =============================================================================
# _setup_prun_gui — prun-gui 스크립트 생성
# =============================================================================

describe "termux_env — _setup_prun_gui"

_test_prun_gui_created() {
    local sb; sb=$(make_sandbox)
    _load_domain "$sb"

    _setup_prun_gui
    assert_file_exists "${PREFIX}/bin/prun-gui"
    [ -x "${PREFIX}/bin/prun-gui" ]
    assert_file_contains "${PREFIX}/bin/prun-gui" "notify-send"
    assert_file_contains "${PREFIX}/bin/prun-gui" "exec prun"
    cleanup_sandbox "$sb"
}
it "prun-gui 스크립트를 생성한다" _test_prun_gui_created

_test_prun_gui_syntax_valid() {
    local sb; sb=$(make_sandbox)
    _load_domain "$sb"

    _setup_prun_gui
    bash -n "${PREFIX}/bin/prun-gui"
    cleanup_sandbox "$sb"
}
it "prun-gui 스크립트의 bash 문법 오류가 없다" _test_prun_gui_syntax_valid

# =============================================================================
# _setup_app_installer — bin + desktop + 바탕화면 아이콘
# =============================================================================

describe "termux_env — _setup_app_installer"

_test_app_installer_created() {
    local sb; sb=$(make_sandbox)
    _load_domain "$sb"
    export SCRIPT_DIR="${_REAL_PROJECT_DIR}"

    _setup_app_installer
    assert_file_exists "${PREFIX}/bin/app-installer"
    assert_file_exists "${PREFIX}/share/applications/app-installer.desktop"
    assert_file_exists "${HOME}/Desktop/App-Installer.desktop"
    [ -x "${PREFIX}/bin/app-installer" ]
    cleanup_sandbox "$sb"
}
it "app-installer bin, desktop, 바탕화면 아이콘을 생성한다" _test_app_installer_created

_test_app_installer_always_regenerated() {
    local sb; sb=$(make_sandbox)
    _load_domain "$sb"
    export SCRIPT_DIR="${_REAL_PROJECT_DIR}"

    _setup_app_installer
    local mtime1; mtime1=$(stat -c %Y "${PREFIX}/bin/app-installer")
    sleep 1
    _setup_app_installer
    local mtime2; mtime2=$(stat -c %Y "${PREFIX}/bin/app-installer")

    assert_ne "$mtime1" "$mtime2" "bin은 항상 재생성되어야 한다 (SCRIPT_DIR 변경 반영)"
    cleanup_sandbox "$sb"
}
it "app-installer bin을 항상 최신 버전으로 재생성한다" _test_app_installer_always_regenerated

# =============================================================================
# _install_base_packages — 패키지 설치 루프
# =============================================================================

describe "termux_env — _install_base_packages"

_test_base_pkgs_installs_missing() {
    local sb; sb=$(make_sandbox)
    _load_domain "$sb"
    reset_mock_calls
    MOCK_INSTALLED_PKGS=""

    _install_base_packages 2>/dev/null || true
    assert_was_called "pkg_install"
    cleanup_sandbox "$sb"
}
it "미설치 패키지에 대해 pkg_install을 호출한다" _test_base_pkgs_installs_missing

_test_base_pkgs_skips_installed() {
    local sb; sb=$(make_sandbox)
    _load_domain "$sb"
    reset_mock_calls
    # XFCE도 이미 설치된 상태 (Stage 6→Stage 7 같은 idempotent 재실행 시뮬레이션)
    MOCK_INSTALLED_PKGS="${PKGS_TERMUX_BASE[*]} ${PKGS_TERMUX_CLI[*]} ${PKGS_TERMUX_PROOT[*]} dbus xfce4-session"

    _install_base_packages 2>/dev/null || true
    # XFCE 존재 시 dbus 제거 안 함 → cascade 제거 차단 → 모든 pkg가 skip
    local install_count=0
    for call in "${MOCK_CALLS[@]:-}"; do
        [[ "$call" == pkg_install* ]] && ((install_count++))
    done
    [ "$install_count" -eq 0 ]
    cleanup_sandbox "$sb"
}
it "멱등성 — 이미 설치된 패키지는 건너뛴다 (XFCE 있으면 dbus도 보존)" _test_base_pkgs_skips_installed

_test_base_pkgs_dbus_removed_on_clean_install() {
    # 클린 설치 (XFCE 없음): dbus 리셋 의도대로 작동
    local sb; sb=$(make_sandbox)
    _load_domain "$sb"
    reset_mock_calls
    MOCK_INSTALLED_PKGS="dbus"   # dbus만 잔존 (xfce4-session 없음)

    _install_base_packages 2>/dev/null || true
    assert_was_called "pkg_remove dbus"
    cleanup_sandbox "$sb"
}
it "클린 설치 (XFCE 없음) — dbus 리셋을 위해 제거된다" _test_base_pkgs_dbus_removed_on_clean_install

_test_base_pkgs_dbus_preserved_when_xfce_installed() {
    # 회귀: Stage 7 같은 멱등 재실행에서 dbus 제거 → 64개 cascade 제거 방지
    local sb; sb=$(make_sandbox)
    _load_domain "$sb"
    reset_mock_calls
    MOCK_INSTALLED_PKGS="dbus xfce4-session fcitx5"

    _install_base_packages 2>/dev/null || true
    assert_not_called "pkg_remove dbus"
    cleanup_sandbox "$sb"
}
it "XFCE 설치된 idempotent 재실행에서는 dbus를 보존한다 (cascade 제거 차단)" _test_base_pkgs_dbus_preserved_when_xfce_installed

# =============================================================================
# setup_termux_shortcuts — composition 함수 검증
# =============================================================================

describe "termux_env — setup_termux_shortcuts (composition)"

_test_shortcuts_creates_all() {
    local sb; sb=$(make_sandbox)
    _load_domain "$sb"
    export SCRIPT_DIR="${_REAL_PROJECT_DIR}"

    setup_termux_shortcuts 2>/dev/null || true

    assert_file_exists "${HOME}/.shortcuts/startXFCE"
    assert_file_exists "${PREFIX}/bin/prun"
    assert_file_exists "${PREFIX}/bin/prun-gui"
    assert_file_exists "${PREFIX}/bin/cp2menu"
    assert_file_exists "${PREFIX}/bin/kill_display_session"
    assert_file_exists "${PREFIX}/bin/app-installer"
    cleanup_sandbox "$sb"
}
it "모든 유틸리티 스크립트를 생성한다" _test_shortcuts_creates_all

# =============================================================================
# 회귀: set -e + ((i++)) 폭탄 (i=0 시작 카운터)
# i++는 *증가 전* 값을 종료코드로 반환하므로 i=0이면 exit 1 → set -e가 첫
# 반복에서 스크립트를 즉시 죽인다. 기존 테스트들은 모두 `|| true`로 가려져
# 있어 이 버그를 잡지 못했음. 새 테스트는 `|| true` 없이 호출하여 함수가
# 끝까지 실행되는지를 직접 검증한다.
# =============================================================================

describe "termux_env — set -e safe counter (regression)"

_test_install_base_packages_completes_under_set_e() {
    local sb; sb=$(make_sandbox)
    _load_domain "$sb"
    reset_mock_calls
    MOCK_INSTALLED_PKGS=""

    # || true 없이 직접 호출 — set -e 하에서 첫 반복부터 끝까지 가야 함
    _install_base_packages

    # 모든 패키지에 대해 pkg_install이 호출되었는지 (루프가 끝까지 돌았다는 증거)
    local total=$((${#PKGS_TERMUX_BASE[@]} + ${#PKGS_TERMUX_CLI[@]} + ${#PKGS_TERMUX_PROOT[@]}))
    local install_count=0
    for call in "${MOCK_CALLS[@]:-}"; do
        [[ "$call" == pkg_install* ]] && install_count=$((install_count + 1))
    done
    # dbus 재설치(remove → install) 1건 포함해 최소 total건은 호출되어야 함
    [ "$install_count" -ge "$total" ]
    cleanup_sandbox "$sb"
}
it "_install_base_packages가 set -e 하에서 끝까지 실행된다" _test_install_base_packages_completes_under_set_e

# =============================================================================
# display_setup_apk — 아키텍처 분기 + 멱등성 + 폴백
# =============================================================================

describe "display_x11 — display_setup_apk"

# uname -m 결과를 지정값으로 고정한 채 함수 실행
_run_with_arch() {
    local _MOCK_ARCH="$1"; shift
    uname() {
        if [ "$1" = "-m" ]; then echo "$_MOCK_ARCH"; else command uname "$@"; fi
    }
    "$@"
}

_test_x11_apk_aarch64_path() {
    local sb; sb=$(make_sandbox)
    _load_domain "$sb"
    mkdir -p "$HOME/storage/downloads"
    termux-open() { _record_call "termux-open $*"; }
    reset_mock_calls

    _run_with_arch "aarch64" display_setup_apk

    assert_was_called "wget"
    assert_was_called "app-arm64-v8a-debug.apk"
    cleanup_sandbox "$sb"
}
it "aarch64는 arm64-v8a APK를 다운로드한다" _test_x11_apk_aarch64_path

_test_x11_apk_x86_64_path() {
    local sb; sb=$(make_sandbox)
    _load_domain "$sb"
    mkdir -p "$HOME/storage/downloads"
    termux-open() { :; }
    reset_mock_calls

    _run_with_arch "x86_64" display_setup_apk

    assert_was_called "app-x86_64-debug.apk"
    cleanup_sandbox "$sb"
}
it "x86_64는 x86_64 APK를 다운로드한다" _test_x11_apk_x86_64_path

_test_x11_apk_unsupported_arch_warns_and_returns() {
    local sb; sb=$(make_sandbox)
    _load_domain "$sb"
    mkdir -p "$HOME/storage/downloads"
    termux-open() { _record_call "termux-open $*"; }
    reset_mock_calls

    _run_with_arch "armv7l" display_setup_apk

    # wget/termux-open 둘 다 호출되지 않아야 함
    assert_not_called "wget"
    assert_not_called "termux-open"
    cleanup_sandbox "$sb"
}
it "지원되지 않는 아키텍처는 wget 없이 경고 후 종료" _test_x11_apk_unsupported_arch_warns_and_returns

_test_x11_apk_idempotent_when_present() {
    local sb; sb=$(make_sandbox)
    _load_domain "$sb"
    mkdir -p "$HOME/storage/downloads"
    # 이미 다운로드된 상태
    touch "$HOME/storage/downloads/app-arm64-v8a-debug.apk"
    termux-open() { _record_call "termux-open $*"; }
    reset_mock_calls

    _run_with_arch "aarch64" display_setup_apk

    assert_not_called "wget"
    assert_was_called "termux-open"
    cleanup_sandbox "$sb"
}
it "APK가 이미 있으면 wget 건너뛰고 termux-open만 호출" _test_x11_apk_idempotent_when_present

_test_x11_apk_falls_back_to_home_when_no_storage() {
    local sb; sb=$(make_sandbox)
    _load_domain "$sb"
    # storage/downloads 없음 → HOME으로 폴백
    [ ! -d "$HOME/storage/downloads" ]
    termux-open() { _record_call "termux-open $*"; }
    reset_mock_calls

    _run_with_arch "aarch64" display_setup_apk

    # HOME에 APK가 생성되어야 함 (mock_wget이 -O 경로에 touch)
    assert_file_exists "$HOME/app-arm64-v8a-debug.apk"
    cleanup_sandbox "$sb"
}
it "storage/downloads 없을 때 HOME으로 폴백" _test_x11_apk_falls_back_to_home_when_no_storage

# =============================================================================
# setup_termux_widget — 사전 조건 + 디렉터리 생성
# =============================================================================

describe "termux_env — setup_termux_widget"

_test_widget_creates_shortcuts_dir() {
    local sb; sb=$(make_sandbox)
    _load_domain "$sb"
    mkdir -p "$HOME/storage/downloads"
    rm -rf "$HOME/.shortcuts"
    termux-open() { :; }

    setup_termux_widget

    assert_dir_exists "$HOME/.shortcuts"
    cleanup_sandbox "$sb"
}
it ".shortcuts 디렉터리가 없으면 생성한다" _test_widget_creates_shortcuts_dir

_test_widget_warns_when_startxfce_missing() {
    local sb; sb=$(make_sandbox)
    _load_domain "$sb"
    mkdir -p "$HOME/storage/downloads" "$HOME/.shortcuts"
    # startXFCE 단축키 부재
    termux-open() { :; }
    reset_ui_output

    setup_termux_widget

    assert_ui_contains "startXFCE 단축키가 없습니다"
    cleanup_sandbox "$sb"
}
it "startXFCE 단축키 누락 시 경고 출력" _test_widget_warns_when_startxfce_missing

_test_widget_no_warn_when_startxfce_present() {
    local sb; sb=$(make_sandbox)
    _load_domain "$sb"
    mkdir -p "$HOME/storage/downloads" "$HOME/.shortcuts"
    touch "$HOME/.shortcuts/startXFCE"
    termux-open() { :; }
    reset_ui_output

    setup_termux_widget

    # startXFCE 경고가 없어야 함
    for msg in "${UI_OUTPUT[@]:-}"; do
        if [[ "$msg" == *"startXFCE 단축키가 없습니다"* ]]; then
            echo "[ASSERT] unexpected startXFCE warning: $msg" >&2
            return 1
        fi
    done
    cleanup_sandbox "$sb"
}
it "startXFCE 단축키 존재 시 경고 안나옴" _test_widget_no_warn_when_startxfce_present

# =============================================================================
# setup_termux_api_apk — APK 다운로드 + 멱등성
# =============================================================================

describe "termux_env — setup_termux_api_apk"

_test_api_apk_downloads() {
    local sb; sb=$(make_sandbox)
    _load_domain "$sb"
    mkdir -p "$HOME/storage/downloads"
    termux-open() { _record_call "termux-open $*"; }
    reset_mock_calls

    setup_termux_api_apk

    assert_was_called "wget"
    assert_was_called "termux-api.apk"
    cleanup_sandbox "$sb"
}
it "Termux:API APK를 다운로드한다" _test_api_apk_downloads

_test_api_apk_idempotent() {
    local sb; sb=$(make_sandbox)
    _load_domain "$sb"
    mkdir -p "$HOME/storage/downloads"
    touch "$HOME/storage/downloads/termux-api.apk"
    termux-open() { _record_call "termux-open $*"; }
    reset_mock_calls

    setup_termux_api_apk

    assert_not_called "wget"
    assert_was_called "termux-open"
    cleanup_sandbox "$sb"
}
it "API APK가 이미 있으면 wget 건너뛰고 termux-open만 호출" _test_api_apk_idempotent

# =============================================================================
# setup_termux_float_apk — APK 다운로드 + 멱등성
# =============================================================================

describe "termux_env — setup_termux_float_apk"

_test_float_apk_downloads() {
    local sb; sb=$(make_sandbox)
    _load_domain "$sb"
    mkdir -p "$HOME/storage/downloads"
    termux-open() { _record_call "termux-open $*"; }
    reset_mock_calls

    setup_termux_float_apk

    assert_was_called "wget"
    assert_was_called "termux-float.apk"
    cleanup_sandbox "$sb"
}
it "Termux:Float APK를 다운로드한다" _test_float_apk_downloads

_test_float_apk_idempotent() {
    local sb; sb=$(make_sandbox)
    _load_domain "$sb"
    mkdir -p "$HOME/storage/downloads"
    touch "$HOME/storage/downloads/termux-float.apk"
    termux-open() { _record_call "termux-open $*"; }
    reset_mock_calls

    setup_termux_float_apk

    assert_not_called "wget"
    assert_was_called "termux-open"
    cleanup_sandbox "$sb"
}
it "Float APK가 이미 있으면 wget 건너뛰고 termux-open만 호출" _test_float_apk_idempotent

# =============================================================================
# _setup_clipboard_sync — 동기화 스크립트 생성
# =============================================================================

describe "termux_env — _setup_clipboard_sync"

_test_clipboard_sync_creates_script() {
    local sb; sb=$(make_sandbox)
    _load_domain "$sb"

    _setup_clipboard_sync

    assert_file_exists "$PREFIX/bin/termux-clipboard-sync"
    [ -x "$PREFIX/bin/termux-clipboard-sync" ]
    cleanup_sandbox "$sb"
}
it "termux-clipboard-sync 스크립트를 생성하고 실행 권한을 부여한다" _test_clipboard_sync_creates_script

_test_clipboard_sync_contains_sync_logic() {
    local sb; sb=$(make_sandbox)
    _load_domain "$sb"

    _setup_clipboard_sync

    local bin="$PREFIX/bin/termux-clipboard-sync"
    grep -q 'termux-clipboard-get' "$bin"
    grep -q 'xclip -selection clipboard' "$bin"
    grep -q 'termux-clipboard-set' "$bin"
    cleanup_sandbox "$sb"
}
it "동기화 스크립트에 양방향 클립보드 로직이 포함된다" _test_clipboard_sync_contains_sync_logic

# =============================================================================
# _setup_termux_repos — 3개 repo + pkg_update
# =============================================================================

describe "termux_env — _setup_termux_repos"

_test_termux_repos_installs_three_when_absent() {
    local sb; sb=$(make_sandbox)
    _load_domain "$sb"
    MOCK_INSTALLED_PKGS=""
    reset_mock_calls

    _setup_termux_repos

    assert_was_called "pkg_install x11-repo"
    assert_was_called "pkg_install tur-repo"
    assert_was_called "pkg_install root-repo"
    assert_was_called "pkg_update"
    cleanup_sandbox "$sb"
}
it "x11/tur/root-repo 미설치 시 모두 설치 + pkg_update 호출" _test_termux_repos_installs_three_when_absent

_test_termux_repos_skips_already_installed() {
    local sb; sb=$(make_sandbox)
    _load_domain "$sb"
    MOCK_INSTALLED_PKGS="x11-repo tur-repo root-repo"
    reset_mock_calls

    _setup_termux_repos

    assert_not_called "pkg_install x11-repo"
    assert_not_called "pkg_install tur-repo"
    assert_not_called "pkg_install root-repo"
    # pkg_update는 항상 호출
    assert_was_called "pkg_update"
    cleanup_sandbox "$sb"
}
it "이미 설치된 repo는 건너뛰지만 pkg_update는 호출" _test_termux_repos_skips_already_installed

# (_cleanup_duplicate_fcitx_autostart: 삭제된 함수 — 테스트 제거)

print_results
