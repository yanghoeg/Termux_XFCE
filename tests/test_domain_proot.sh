#!/data/data/com.termux/files/usr/bin/bash
# =============================================================================
# TEST: domain/proot_env.sh
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/framework.sh"
source "${SCRIPT_DIR}/mocks.sh"

DOMAIN_DIR="${SCRIPT_DIR}/../domain"

_load_domain() {
    local sandbox="$1"
    local distro="${2:-ubuntu}"
    local user="${3:-testuser}"

    setup_fs_sandbox "$sandbox"
    export PROOT_DISTRO="$distro"
    export PROOT_USER="$user"

    mock_pkg_adapter
    mock_ui_adapter
    mock_wget

    # proot-distro 명령 mock
    proot-distro() { _record_call "proot-distro $*"; }

    source "${DOMAIN_DIR}/packages.sh"
    # PROOT_ROOTFS readonly 재선언 방지
    source "${DOMAIN_DIR}/proot_env.sh" 2>/dev/null || true
}

_make_proot_rootfs() {
    local sandbox="$1" distro="${2:-ubuntu}" user="${3:-testuser}"
    local rootfs="${sandbox}/usr/var/lib/proot-distro/installed-rootfs/${distro}"
    mkdir -p \
        "${rootfs}/home/${user}" \
        "${rootfs}/etc" \
        "${rootfs}/usr/share/icons"
    # sudoers stub
    touch "${rootfs}/etc/sudoers"
    # .bashrc stub
    touch "${rootfs}/home/${user}/.bashrc"
}

# =============================================================================
# setup_proot_install — 멱등성
# =============================================================================

describe "proot_env — setup_proot_install"

_test_proot_install_runs_if_missing() {
    local sb; sb=$(make_sandbox)
    _load_domain "$sb" "ubuntu"
    reset_mock_calls

    # rootfs 없음
    setup_proot_install 2>/dev/null || true
    assert_was_called "proot-distro install"
    cleanup_sandbox "$sb"
}
it "rootfs가 없으면 proot-distro install을 호출한다" _test_proot_install_runs_if_missing

_test_proot_install_skips_if_exists() {
    local sb; sb=$(make_sandbox)
    _load_domain "$sb" "ubuntu"
    # rootfs 미리 생성
    mkdir -p "${PREFIX}/var/lib/proot-distro/installed-rootfs/ubuntu"
    reset_mock_calls

    setup_proot_install 2>/dev/null || true
    assert_not_called "proot-distro install"
    cleanup_sandbox "$sb"
}
it "멱등성 — rootfs가 이미 있으면 install을 건너뛴다" _test_proot_install_skips_if_exists

# =============================================================================
# setup_proot_user — 멱등성
# =============================================================================

describe "proot_env — setup_proot_user"

_test_proot_user_created() {
    local sb; sb=$(make_sandbox)
    _load_domain "$sb" "ubuntu" "testuser"
    reset_mock_calls

    setup_proot_user 2>/dev/null || true
    assert_was_called "proot_exec"
    cleanup_sandbox "$sb"
}
it "사용자 홈 없을 시 useradd를 실행한다" _test_proot_user_created

_test_proot_user_skips_if_exists() {
    local sb; sb=$(make_sandbox)
    _load_domain "$sb" "ubuntu" "testuser"
    _make_proot_rootfs "$sb" "ubuntu" "testuser"
    reset_mock_calls

    setup_proot_user 2>/dev/null || true
    assert_not_called "proot_exec"
    cleanup_sandbox "$sb"
}
it "멱등성 — 사용자가 이미 있으면 건너뛴다" _test_proot_user_skips_if_exists

# =============================================================================
# _setup_proot_sudoers
# =============================================================================

describe "proot_env — _setup_proot_sudoers"

_test_sudoers_entry_added() {
    local sb; sb=$(make_sandbox)
    _load_domain "$sb" "ubuntu" "testuser"
    _make_proot_rootfs "$sb" "ubuntu" "testuser"

    _setup_proot_sudoers "testuser"

    assert_file_contains \
        "${PREFIX}/var/lib/proot-distro/installed-rootfs/ubuntu/etc/sudoers" \
        "testuser ALL=(ALL) NOPASSWD:ALL"
    cleanup_sandbox "$sb"
}
it "sudoers에 NOPASSWD 항목을 추가한다" _test_sudoers_entry_added

_test_sudoers_idempotent() {
    local sb; sb=$(make_sandbox)
    _load_domain "$sb" "ubuntu" "testuser"
    _make_proot_rootfs "$sb" "ubuntu" "testuser"

    _setup_proot_sudoers "testuser"
    _setup_proot_sudoers "testuser"  # 두 번

    local count
    count=$(grep -c "testuser ALL=(ALL)" \
        "${PREFIX}/var/lib/proot-distro/installed-rootfs/ubuntu/etc/sudoers")
    assert_eq "1" "$count" "멱등성: sudoers 항목이 1번만 있어야 한다"
    cleanup_sandbox "$sb"
}
it "멱등성 — sudoers 항목이 중복 추가되지 않는다" _test_sudoers_idempotent

# =============================================================================
# setup_proot_env — 환경변수
# =============================================================================

describe "proot_env — setup_proot_env"

_test_proot_env_written() {
    local sb; sb=$(make_sandbox)
    _load_domain "$sb" "ubuntu" "testuser"
    _make_proot_rootfs "$sb" "ubuntu" "testuser"

    setup_proot_env 2>/dev/null || true

    local bashrc="${PREFIX}/var/lib/proot-distro/installed-rootfs/ubuntu/home/testuser/.bashrc"
    assert_file_contains "$bashrc" "termux-xfce-proot-env"
    assert_file_contains "$bashrc" "DISPLAY=:1.0"
    assert_file_contains "$bashrc" "MESA_LOADER_DRIVER_OVERRIDE=zink"
    cleanup_sandbox "$sb"
}
it ".bashrc에 DISPLAY, MESA 등 환경변수를 추가한다" _test_proot_env_written

_test_proot_env_idempotent() {
    local sb; sb=$(make_sandbox)
    _load_domain "$sb" "ubuntu" "testuser"
    _make_proot_rootfs "$sb" "ubuntu" "testuser"

    setup_proot_env 2>/dev/null || true
    setup_proot_env 2>/dev/null || true

    local bashrc="${PREFIX}/var/lib/proot-distro/installed-rootfs/ubuntu/home/testuser/.bashrc"
    local count
    count=$(grep -c "termux-xfce-proot-env" "$bashrc")
    assert_eq "1" "$count" "멱등성: env 블록이 1번만 있어야 한다"
    cleanup_sandbox "$sb"
}
it "멱등성 — proot env 블록이 중복 추가되지 않는다" _test_proot_env_idempotent

# =============================================================================
# setup_proot_base_packages — distro 분기
# =============================================================================

describe "proot_env — setup_proot_base_packages"

_test_ubuntu_base_uses_ubuntu_pkgs() {
    local sb; sb=$(make_sandbox)
    _load_domain "$sb" "ubuntu"
    reset_mock_calls
    MOCK_INSTALLED_PKGS=""

    setup_proot_base_packages 2>/dev/null || true
    assert_was_called "proot_pkg_install"
    cleanup_sandbox "$sb"
}
it "Ubuntu: proot 패키지 설치를 호출한다" _test_ubuntu_base_uses_ubuntu_pkgs

_test_arch_base_uses_arch_pkgs() {
    local sb; sb=$(make_sandbox)
    _load_domain "$sb" "archlinux"
    reset_mock_calls
    MOCK_INSTALLED_PKGS=""

    setup_proot_base_packages 2>/dev/null || true
    assert_was_called "proot_pkg_install"
    cleanup_sandbox "$sb"
}
it "Arch: proot 패키지 설치를 호출한다" _test_arch_base_uses_arch_pkgs

# =============================================================================
# setup_proot_cursor_theme
# =============================================================================

describe "proot_env — setup_proot_cursor_theme"

_test_cursor_skips_if_dst_exists() {
    local sb; sb=$(make_sandbox)
    _load_domain "$sb" "ubuntu" "testuser"
    reset_mock_calls

    # 목적지 이미 존재
    mkdir -p "${PREFIX}/var/lib/proot-distro/installed-rootfs/ubuntu/usr/share/icons/dist-dark"

    setup_proot_cursor_theme 2>/dev/null || true
    assert_not_called "cp"
    cleanup_sandbox "$sb"
}
it "멱등성 — dist-dark가 이미 있으면 복사하지 않는다" _test_cursor_skips_if_dst_exists

_test_cursor_warns_if_src_missing() {
    local sb; sb=$(make_sandbox)
    _load_domain "$sb" "ubuntu" "testuser"
    reset_ui_output

    # src 없음 (${PREFIX}/share/icons/dist-dark 없음)
    setup_proot_cursor_theme 2>/dev/null || true
    assert_ui_contains "WARN"
    cleanup_sandbox "$sb"
}
it "dist-dark 소스가 없으면 경고를 출력한다" _test_cursor_warns_if_src_missing

_test_cursor_theme_copied() {
    local sb; sb=$(make_sandbox)
    _load_domain "$sb" "ubuntu" "testuser"
    _make_proot_rootfs "$sb" "ubuntu" "testuser"

    # src 생성
    mkdir -p "${PREFIX}/share/icons/dist-dark"
    touch "${PREFIX}/share/icons/dist-dark/cursor.theme"

    setup_proot_cursor_theme 2>/dev/null || true

    assert_dir_exists "${PREFIX}/var/lib/proot-distro/installed-rootfs/ubuntu/usr/share/icons/dist-dark"
    cleanup_sandbox "$sb"
}
it "dist-dark 커서 테마를 proot로 복사한다" _test_cursor_theme_copied

# =============================================================================
# setup_proot_fancybash
# =============================================================================

describe "proot_env — setup_proot_fancybash"

_test_fancybash_warns_if_src_missing() {
    local sb; sb=$(make_sandbox)
    _load_domain "$sb" "ubuntu" "testuser"
    reset_ui_output

    # Termux .fancybash.sh 없음
    setup_proot_fancybash 2>/dev/null || true
    assert_ui_contains "WARN"
    cleanup_sandbox "$sb"
}
it "Termux의 .fancybash.sh가 없으면 경고를 출력한다" _test_fancybash_warns_if_src_missing

_test_fancybash_copied_to_proot() {
    local sb; sb=$(make_sandbox)
    _load_domain "$sb" "ubuntu" "testuser"
    _make_proot_rootfs "$sb" "ubuntu" "testuser"

    echo 'PS1="testuser@termux"' > "${HOME}/.fancybash.sh"

    setup_proot_fancybash 2>/dev/null || true

    assert_file_exists \
        "${PREFIX}/var/lib/proot-distro/installed-rootfs/ubuntu/home/testuser/.fancybash.sh"
    cleanup_sandbox "$sb"
}
it ".fancybash.sh를 proot 홈으로 복사한다" _test_fancybash_copied_to_proot

_test_fancybash_idempotent() {
    local sb; sb=$(make_sandbox)
    _load_domain "$sb" "ubuntu" "testuser"
    _make_proot_rootfs "$sb" "ubuntu" "testuser"

    echo 'PS1="testuser@termux"' > "${HOME}/.fancybash.sh"

    setup_proot_fancybash 2>/dev/null || true
    local dst="${PREFIX}/var/lib/proot-distro/installed-rootfs/ubuntu/home/testuser/.fancybash.sh"
    local mtime1; mtime1=$(stat -c %Y "$dst")

    sleep 1
    setup_proot_fancybash 2>/dev/null || true
    local mtime2; mtime2=$(stat -c %Y "$dst")

    assert_eq "$mtime1" "$mtime2" "멱등성"
    cleanup_sandbox "$sb"
}
it "멱등성 — proot .fancybash.sh가 이미 있으면 덮어쓰지 않는다" _test_fancybash_idempotent

print_results
