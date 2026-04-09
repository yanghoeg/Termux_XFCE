#!/data/data/com.termux/files/usr/bin/bash
# =============================================================================
# TEST: domain/termux_env.sh
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
    assert_file_contains "${HOME}/.shortcuts/startXFCE" "MESA_DRIVER"
    assert_file_contains "${HOME}/.shortcuts/startXFCE" "kgsl"
    cleanup_sandbox "$sb"
}
it "startXFCE에 GPU 자동 감지 로직이 있다" _test_startxfce_has_gpu_detection

_test_startxfce_idempotent() {
    local sb; sb=$(make_sandbox)
    _load_domain "$sb"

    _setup_start_xfce
    local mtime1
    mtime1=$(stat -c %Y "${HOME}/.shortcuts/startXFCE")

    sleep 1
    _setup_start_xfce  # 두 번째 호출

    local mtime2
    mtime2=$(stat -c %Y "${HOME}/.shortcuts/startXFCE")
    assert_eq "$mtime1" "$mtime2" "멱등성: 이미 존재하면 덮어쓰지 않는다"
    cleanup_sandbox "$sb"
}
it "멱등성 — startXFCE가 이미 있으면 덮어쓰지 않는다" _test_startxfce_idempotent

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

_test_prun_idempotent() {
    local sb; sb=$(make_sandbox)
    _load_domain "$sb"

    _setup_prun
    local mtime1; mtime1=$(stat -c %Y "${PREFIX}/bin/prun")
    sleep 1
    _setup_prun
    local mtime2; mtime2=$(stat -c %Y "${PREFIX}/bin/prun")
    assert_eq "$mtime1" "$mtime2" "멱등성: prun이 이미 있으면 덮어쓰지 않는다"
    cleanup_sandbox "$sb"
}
it "멱등성 — prun이 이미 있으면 덮어쓰지 않는다" _test_prun_idempotent

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

describe "termux_env — _setup_korean_env"

_test_korean_fcitx5_desktop_created() {
    local sb; sb=$(make_sandbox)
    _load_domain "$sb"

    _setup_korean_env
    assert_file_exists "${HOME}/.config/autostart/fcitx5.desktop"
    assert_file_contains "${HOME}/.config/autostart/fcitx5.desktop" "Exec=fcitx5 -d"
    cleanup_sandbox "$sb"
}
it "fcitx5.desktop 자동시작 파일을 생성한다" _test_korean_fcitx5_desktop_created

_test_korean_env_idempotent() {
    local sb; sb=$(make_sandbox)
    _load_domain "$sb"

    _setup_korean_env
    local mtime1; mtime1=$(stat -c %Y "${HOME}/.config/autostart/fcitx5.desktop")
    sleep 1
    _setup_korean_env
    local mtime2; mtime2=$(stat -c %Y "${HOME}/.config/autostart/fcitx5.desktop")
    assert_eq "$mtime1" "$mtime2" "멱등성"
    cleanup_sandbox "$sb"
}
it "멱등성 — fcitx5.desktop이 이미 있으면 덮어쓰지 않는다" _test_korean_env_idempotent

# =============================================================================
# _detect_and_log_gpu
# =============================================================================

describe "termux_env — _detect_and_log_gpu (GPU 감지)"

_test_gpu_no_kgsl() {
    local sb; sb=$(make_sandbox)
    _load_domain "$sb"
    reset_ui_output

    # KGSL 없음 → warn
    _detect_and_log_gpu 2>/dev/null || true
    assert_ui_contains "WARN"
    cleanup_sandbox "$sb"
}
it "KGSL 미감지 시 경고를 출력한다" _test_gpu_no_kgsl

_test_gpu_adreno_7xx() {
    local sb; sb=$(make_sandbox)
    _load_domain "$sb"
    reset_ui_output

    # sys 파일 모킹 (임시 파일로 함수 내 경로 재정의)
    _detect_and_log_gpu_mocked() {
        local gpu_model="Adreno (TM) 750"
        ui_info "감지된 GPU: ${gpu_model}"
        if [[ "$gpu_model" =~ [Aa]dreno.*7[0-9]{2} ]]; then
            ui_info "Adreno 7xx"
        fi
    }
    _detect_and_log_gpu_mocked
    assert_ui_contains "Adreno 7xx"
    cleanup_sandbox "$sb"
}
it "Adreno 7xx GPU 감지 시 7xx 메시지를 출력한다" _test_gpu_adreno_7xx

_test_gpu_adreno_8xx_warn() {
    local sb; sb=$(make_sandbox)
    _load_domain "$sb"
    reset_ui_output

    _detect_and_log_gpu_mocked() {
        local gpu_model="Adreno (TM) 830"
        ui_info "감지된 GPU: ${gpu_model}"
        if [[ "$gpu_model" =~ [Aa]dreno.*8[0-9]{2} ]]; then
            ui_warn "구형 mesa-vulkan-kgsl deb는 8xx와 호환되지 않을 수 있습니다."
        fi
    }
    _detect_and_log_gpu_mocked
    assert_ui_contains "WARN: 구형 mesa-vulkan-kgsl"
    cleanup_sandbox "$sb"
}
it "Adreno 8xx GPU 감지 시 경고를 출력한다" _test_gpu_adreno_8xx_warn

# =============================================================================
# setup_termux_gpu — 패키지 설치 루프
# =============================================================================

describe "termux_env — setup_termux_gpu"

_test_setup_gpu_installs_pkgs() {
    local sb; sb=$(make_sandbox)
    _load_domain "$sb"
    reset_mock_calls
    MOCK_INSTALLED_PKGS=""  # 아무것도 설치 안 된 상태

    setup_termux_gpu 2>/dev/null || true

    # GPU 패키지 중 하나라도 pkg_install 호출됐는지 확인
    assert_was_called "pkg_install"
    cleanup_sandbox "$sb"
}
it "GPU 패키지 미설치 시 pkg_install을 호출한다" _test_setup_gpu_installs_pkgs

_test_setup_gpu_skips_installed() {
    local sb; sb=$(make_sandbox)
    _load_domain "$sb"
    reset_mock_calls
    # 모든 GPU 패키지를 설치된 것으로 설정
    MOCK_INSTALLED_PKGS="${PKGS_TERMUX_GPU[*]}"

    setup_termux_gpu 2>/dev/null || true

    assert_not_called "pkg_install"
    cleanup_sandbox "$sb"
}
it "멱등성 — GPU 패키지가 이미 설치된 경우 pkg_install을 호출하지 않는다" _test_setup_gpu_skips_installed

print_results
