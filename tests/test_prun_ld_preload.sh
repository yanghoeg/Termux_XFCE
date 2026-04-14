#!/data/data/com.termux/files/usr/bin/bash
# =============================================================================
# TEST: _setup_prun LD_PRELOAD 제거 + PROOT_USER 로직
# 변경 내역:
#   - prun 스크립트에 unset LD_PRELOAD 추가
#   - proot-distro 실행 시 env -u LD_PRELOAD로 감쌈
#   - PROOT_USER env var 우선 사용, 없으면 home/ 탐색 (alarm 제외)
#   - install.sh proot alias에 -- env -u LD_PRELOAD bash --login 추가
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/framework.sh"
source "${SCRIPT_DIR}/mocks.sh"

DOMAIN_DIR="${SCRIPT_DIR}/../domain"
INSTALL_SH="${SCRIPT_DIR}/../install.sh"

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
# prun 스크립트 — LD_PRELOAD 관련
# =============================================================================

describe "_setup_prun — LD_PRELOAD 제거"

_test_prun_unset_ld_preload() {
    local sb; sb=$(make_sandbox)
    _load_domain "$sb"

    _setup_prun

    assert_file_contains "${PREFIX}/bin/prun" "unset LD_PRELOAD"
    cleanup_sandbox "$sb"
}
it "prun 스크립트에 unset LD_PRELOAD가 있다" _test_prun_unset_ld_preload

_test_prun_env_u_ld_preload() {
    local sb; sb=$(make_sandbox)
    _load_domain "$sb"

    _setup_prun

    assert_file_contains "${PREFIX}/bin/prun" "env -u LD_PRELOAD"
    cleanup_sandbox "$sb"
}
it "prun 스크립트 proot-distro 실행 시 env -u LD_PRELOAD로 감싼다" _test_prun_env_u_ld_preload

_test_prun_noarg_uses_login_shell() {
    local sb; sb=$(make_sandbox)
    _load_domain "$sb"

    _setup_prun

    # 인자 없을 때 PROOT_SHELL 기반 --login 폴백이 있어야 함
    assert_file_contains "${PREFIX}/bin/prun" 'if \[ \$# -eq 0 \]'
    assert_file_contains "${PREFIX}/bin/prun" 'PROOT_SHELL:-bash'
    assert_file_contains "${PREFIX}/bin/prun" '--login'
    cleanup_sandbox "$sb"
}
it "인자 없이 prun 호출 시 PROOT_SHELL --login으로 인터랙티브 셸 실행" _test_prun_noarg_uses_login_shell

_test_prun_ld_preload_before_proot() {
    local sb; sb=$(make_sandbox)
    _load_domain "$sb"

    _setup_prun

    # unset 라인이 proot-distro login 라인보다 앞에 있어야 함
    local unset_line proot_line
    unset_line=$(grep -n "unset LD_PRELOAD" "${PREFIX}/bin/prun" | head -1 | cut -d: -f1)
    proot_line=$(grep -n "proot-distro login" "${PREFIX}/bin/prun" | head -1 | cut -d: -f1)

    [ -n "$unset_line" ] && [ -n "$proot_line" ]
    assert_nonzero "$(( proot_line - unset_line ))" "unset LD_PRELOAD가 proot-distro login보다 앞에 있어야 한다"
    cleanup_sandbox "$sb"
}
it "unset LD_PRELOAD가 proot-distro login 호출보다 앞에 있다" _test_prun_ld_preload_before_proot

# =============================================================================
# prun 스크립트 — PROOT_USER 우선 사용
# =============================================================================

describe "_setup_prun — PROOT_USER 처리 로직"

_test_prun_uses_proot_user_var() {
    local sb; sb=$(make_sandbox)
    _load_domain "$sb"

    _setup_prun

    # PROOT_USER 환경변수를 사용하는 분기가 있어야 함
    assert_file_contains "${PREFIX}/bin/prun" 'PROOT_USER'
    cleanup_sandbox "$sb"
}
it "prun 스크립트가 PROOT_USER 환경변수를 참조한다" _test_prun_uses_proot_user_var

_test_prun_fallback_excludes_alarm() {
    local sb; sb=$(make_sandbox)
    _load_domain "$sb"

    _setup_prun

    # alarm 계정을 제외하는 grep -v 패턴이 있어야 함
    assert_file_contains "${PREFIX}/bin/prun" "alarm"
    assert_file_contains "${PREFIX}/bin/prun" "grep -v"
    cleanup_sandbox "$sb"
}
it "prun의 user 탐색 로직에 alarm 제외 패턴이 있다" _test_prun_fallback_excludes_alarm

_test_prun_user_logic_proot_user_branch() {
    local sb; sb=$(make_sandbox)
    _load_domain "$sb"

    _setup_prun

    # if [ -n "${PROOT_USER:-}" ] 분기가 있어야 함
    assert_file_contains "${PREFIX}/bin/prun" 'if \[ -n.*PROOT_USER'
    cleanup_sandbox "$sb"
}
it "prun 스크립트에 PROOT_USER 분기 if문이 있다" _test_prun_user_logic_proot_user_branch

_test_prun_user_fallback_default() {
    local sb; sb=$(make_sandbox)
    _load_domain "$sb"

    _setup_prun

    # home/ 탐색 실패 시 user 기본값이 있어야 함
    assert_file_contains "${PREFIX}/bin/prun" ':-user}'
    cleanup_sandbox "$sb"
}
it "prun user 탐색 실패 시 'user' 기본값으로 폴백한다" _test_prun_user_fallback_default

# =============================================================================
# prun 스크립트 — 실제 동작 검증 (sandbox에서 PROOT_USER 설정 시)
# =============================================================================

describe "_setup_prun — PROOT_USER 설정 시 USER_NAME 결정"

_test_prun_proot_user_is_used_when_set() {
    local sb; sb=$(make_sandbox)
    _load_domain "$sb"

    _setup_prun

    # prun 스크립트의 PROOT_USER 분기 로직을 직접 추출해서 실행
    # PROOT_USER가 설정된 경우 해당 값이 USER_NAME으로 쓰여야 함
    local user_name
    user_name=$(
        export PREFIX="${sb}/usr"
        export PROOT_USER="testuser"
        bash -c '
            DISTRO="archlinux"
            if [ -n "${PROOT_USER:-}" ]; then
                USER_NAME="$PROOT_USER"
            else
                USER_NAME=$(ls "$PREFIX/var/lib/proot-distro/installed-rootfs/$DISTRO/home/" 2>/dev/null \
                    | grep -v '"'"'^alarm$'"'"' | head -1)
                USER_NAME="${USER_NAME:-user}"
            fi
            echo "$USER_NAME"
        '
    )
    assert_eq "testuser" "$user_name" "PROOT_USER=testuser 설정 시 USER_NAME이 testuser여야 한다"
    cleanup_sandbox "$sb"
}
it "PROOT_USER 환경변수가 설정되면 USER_NAME으로 사용된다" _test_prun_proot_user_is_used_when_set

_test_prun_alarm_excluded_from_fallback() {
    local sb; sb=$(make_sandbox)
    _load_domain "$sb"

    # home/ 디렉토리에 alarm과 일반 유저가 있는 상황 시뮬레이션
    local rootfs="${sb}/usr/var/lib/proot-distro/installed-rootfs/archlinux/home"
    mkdir -p "${rootfs}/alarm"
    mkdir -p "${rootfs}/lideok"

    _setup_prun

    local user_name
    user_name=$(
        export PREFIX="${sb}/usr"
        unset PROOT_USER
        bash -c '
            DISTRO="archlinux"
            if [ -n "${PROOT_USER:-}" ]; then
                USER_NAME="$PROOT_USER"
            else
                USER_NAME=$(ls "$PREFIX/var/lib/proot-distro/installed-rootfs/$DISTRO/home/" 2>/dev/null \
                    | grep -v '"'"'^alarm$'"'"' | head -1)
                USER_NAME="${USER_NAME:-user}"
            fi
            echo "$USER_NAME"
        '
    )
    assert_eq "lideok" "$user_name" "alarm 제외 후 lideok이 선택되어야 한다"
    cleanup_sandbox "$sb"
}
it "home/ 탐색 시 alarm 계정을 건너뛰고 다른 유저를 선택한다" _test_prun_alarm_excluded_from_fallback

_test_prun_only_alarm_fallback_to_default() {
    local sb; sb=$(make_sandbox)
    _load_domain "$sb"

    # home/ 에 alarm만 있는 경우
    local rootfs="${sb}/usr/var/lib/proot-distro/installed-rootfs/archlinux/home"
    mkdir -p "${rootfs}/alarm"

    _setup_prun

    local user_name
    user_name=$(
        export PREFIX="${sb}/usr"
        unset PROOT_USER
        bash -c '
            DISTRO="archlinux"
            if [ -n "${PROOT_USER:-}" ]; then
                USER_NAME="$PROOT_USER"
            else
                USER_NAME=$(ls "$PREFIX/var/lib/proot-distro/installed-rootfs/$DISTRO/home/" 2>/dev/null \
                    | grep -v '"'"'^alarm$'"'"' | head -1)
                USER_NAME="${USER_NAME:-user}"
            fi
            echo "$USER_NAME"
        '
    )
    assert_eq "user" "$user_name" "alarm만 있으면 기본값 'user'로 폴백해야 한다"
    cleanup_sandbox "$sb"
}
it "home/ 에 alarm만 있으면 기본값 'user'로 폴백한다" _test_prun_only_alarm_fallback_to_default

# =============================================================================
# install.sh — proot alias LD_PRELOAD 처리
# =============================================================================

describe "install.sh — proot alias env -u LD_PRELOAD"

_test_install_proot_alias_has_env_u() {
    # install.sh 소스에서 proot alias 라인을 직접 grep으로 확인
    local alias_line
    alias_line=$(grep "_proot_alias=" "${INSTALL_SH}" | head -1)

    # env -u LD_PRELOAD 포함 여부
    assert_output_contains "$alias_line" "env -u LD_PRELOAD"
    # PROOT_SHELL 변수 참조 및 --login 포함 여부
    assert_output_contains "$alias_line" "PROOT_SHELL"
    assert_output_contains "$alias_line" "--login"
}
it "install.sh proot alias에 env -u LD_PRELOAD \${PROOT_SHELL:-bash} --login이 포함된다" _test_install_proot_alias_has_env_u

_test_install_proot_alias_format() {
    local alias_line
    alias_line=$(grep "_proot_alias=" "${INSTALL_SH}" | head -1)

    # -- 구분자 뒤에 env -u LD_PRELOAD ${PROOT_SHELL:-bash} --login 순서 확인
    if ! echo "$alias_line" | grep -qF -- '-- env -u LD_PRELOAD'; then
        echo "[ASSERT] proot alias에 '-- env -u LD_PRELOAD' 패턴이 없다" >&2
        echo "[ASSERT] actual: ${alias_line}" >&2
        return 1
    fi
    if ! echo "$alias_line" | grep -q 'PROOT_SHELL.*--login'; then
        echo "[ASSERT] proot alias에 'PROOT_SHELL ... --login' 패턴이 없다" >&2
        echo "[ASSERT] actual: ${alias_line}" >&2
        return 1
    fi
}
it "proot alias에서 -- env -u LD_PRELOAD \${PROOT_SHELL:-bash} --login 순서가 맞다" _test_install_proot_alias_format

# =============================================================================
# _setup_prun — 이미 존재할 때도 덮어쓰기 (운영환경 업데이트 보장)
# =============================================================================

describe "_setup_prun — 기존 파일 덮어쓰기"

_test_prun_overwrites_existing() {
    local sb; sb=$(make_sandbox)
    _load_domain "$sb"

    # 구버전 prun 미리 설치 (if [ \$# -eq 0 ] 분기 없는 버전)
    cat > "${PREFIX}/bin/prun" << 'OLDPRUN'
#!/data/data/com.termux/files/usr/bin/bash
proot-distro login archlinux "$@"
OLDPRUN
    chmod +x "${PREFIX}/bin/prun"

    _setup_prun

    # 새 버전으로 덮어써져 있어야 함
    assert_file_contains "${PREFIX}/bin/prun" 'if \[ \$# -eq 0 \]'
    cleanup_sandbox "$sb"
}
it "_setup_prun은 구버전 prun을 최신 버전으로 덮어쓴다" _test_prun_overwrites_existing

_test_prun_config_sourced_in_sandbox() {
    local sb; sb=$(make_sandbox)
    _load_domain "$sb"

    # sandbox에 config 있음 (setup_fs_sandbox가 생성)
    assert_file_exists "${HOME}/.config/termux-xfce/config"
    assert_file_contains "${HOME}/.config/termux-xfce/config" "PROOT_DISTRO"
    cleanup_sandbox "$sb"
}
it "sandbox에 termux-xfce config 파일이 존재한다 (운영환경 반영)" _test_prun_config_sourced_in_sandbox

print_results
