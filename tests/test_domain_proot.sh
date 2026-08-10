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
        "${rootfs}/etc/default" \
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

# --proot-only 모드 회귀: proot-distro 명령이 없는 상태에서 setup_proot_install이
# PKGS_TERMUX_PROOT를 먼저 설치해야 한다. (이전 버그: rc=127 command not found)
_test_proot_install_installs_termux_proot_pkgs_when_missing() {
    local sb; sb=$(make_sandbox)
    _load_domain "$sb" "ubuntu"

    # 호스트에 proot-distro가 실제로 설치돼 있을 수 있으므로 command -v를 강제로 false
    unset -f proot-distro
    command() {
        if [ "${1:-}" = "-v" ] && [ "${2:-}" = "proot-distro" ]; then
            return 1
        fi
        builtin command "$@"
    }
    reset_mock_calls

    setup_proot_install 2>/dev/null || true

    # PKGS_TERMUX_PROOT 의 각 패키지가 pkg_install로 호출돼야 함
    assert_was_called "pkg_install proot-distro"
    assert_was_called "pkg_install x11-repo"
    assert_was_called "pkg_install tur-repo"
    assert_was_called "pkg_update"
    # 의존성 설치 후 최종 proot_install도 호출
    assert_was_called "proot-distro install"

    unset -f command
    cleanup_sandbox "$sb"
}
it "--proot-only 회귀: proot-distro 미설치 시 PKGS_TERMUX_PROOT를 먼저 설치한다" \
    _test_proot_install_installs_termux_proot_pkgs_when_missing

_test_proot_install_skips_dep_install_when_proot_distro_present() {
    local sb; sb=$(make_sandbox)
    _load_domain "$sb" "ubuntu"
    # proot-distro 함수가 정의된 상태(_load_domain 기본 mock) → 의존성 설치 건너뛰어야 함
    reset_mock_calls

    setup_proot_install 2>/dev/null || true

    # PKGS_TERMUX_PROOT 패키지가 pkg_install로 호출되지 않아야 함 (이미 있다고 간주)
    assert_not_called "pkg_install proot-distro"
    assert_not_called "pkg_install x11-repo"
    # 그러나 distro 자체는 설치
    assert_was_called "proot-distro install"
    cleanup_sandbox "$sb"
}
it "proot-distro 이미 존재 시 의존성 설치 분기는 건너뛴다" \
    _test_proot_install_skips_dep_install_when_proot_distro_present

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
    assert_file_contains "$bashrc" 'DISPLAY=${DISPLAY:-:0.0}'
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

# --proot-only 회귀: src 미존재여도 return 0(set -e 안전), 그리고
# _install_fluent_cursor 헬퍼가 로드돼 있으면 자동 호출
_test_cursor_returns_zero_when_src_missing() {
    local sb; sb=$(make_sandbox)
    _load_domain "$sb" "ubuntu" "testuser"

    # src 없음, 헬퍼도 정의 안 함 — 그래도 return 0 (cosmetic skip)
    local rc=0
    setup_proot_cursor_theme >/dev/null 2>&1 || rc=$?
    if [ "$rc" -ne 0 ]; then
        echo "[ASSERT] expected rc=0 (cosmetic skip), got rc=$rc" >&2
        cleanup_sandbox "$sb"
        return 1
    fi
    cleanup_sandbox "$sb"
}
it "--proot-only 회귀: src 미존재 시 return 0 (set -e 트립 방지)" \
    _test_cursor_returns_zero_when_src_missing

_test_cursor_invokes_fluent_helper_if_loaded() {
    local sb; sb=$(make_sandbox)
    _load_domain "$sb" "ubuntu" "testuser"

    # _install_fluent_cursor stub: 호출되면 src 디렉토리를 생성하도록
    _install_fluent_cursor() {
        _record_call "_install_fluent_cursor"
        mkdir -p "${PREFIX}/share/icons/dist-dark"
        touch "${PREFIX}/share/icons/dist-dark/cursor.theme"
    }
    _make_proot_rootfs "$sb" "ubuntu" "testuser"
    reset_mock_calls

    setup_proot_cursor_theme 2>/dev/null || true

    assert_was_called "_install_fluent_cursor"
    # 자동 보강 후 실제 복사까지 완료
    assert_dir_exists "${PREFIX}/var/lib/proot-distro/installed-rootfs/ubuntu/usr/share/icons/dist-dark"

    unset -f _install_fluent_cursor
    cleanup_sandbox "$sb"
}
it "src 없을 때 _install_fluent_cursor가 로드돼 있으면 자동 호출한다" \
    _test_cursor_invokes_fluent_helper_if_loaded

# =============================================================================
# setup_proot_fancybash
# =============================================================================

describe "proot_env — setup_proot_fancybash"

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

# =============================================================================
# setup_proot_update — proot_pkg_update 호출 확인
# =============================================================================

describe "proot_env — setup_proot_update"

_test_proot_update_calls_pkg_update() {
    local sb; sb=$(make_sandbox)
    _load_domain "$sb" "ubuntu"
    reset_mock_calls

    setup_proot_update 2>/dev/null || true
    assert_was_called "proot_pkg_update"
    cleanup_sandbox "$sb"
}
it "setup_proot_update는 proot_pkg_update를 호출한다" _test_proot_update_calls_pkg_update

# =============================================================================
# setup_proot_korean — distro 분기 확인
# =============================================================================

describe "proot_env — setup_proot_korean"

_test_korean_ubuntu_installs_pkgs() {
    local sb; sb=$(make_sandbox)
    _load_domain "$sb" "ubuntu"
    _make_proot_rootfs "$sb" "ubuntu" "testuser"
    reset_mock_calls
    MOCK_INSTALLED_PKGS=""

    setup_proot_korean 2>/dev/null || true
    assert_was_called "proot_pkg_install"
    cleanup_sandbox "$sb"
}
it "Ubuntu: proot 한글 패키지 설치를 호출한다" _test_korean_ubuntu_installs_pkgs

_test_korean_arch_installs_pkgs() {
    local sb; sb=$(make_sandbox)
    _load_domain "$sb" "archlinux"
    _make_proot_rootfs "$sb" "archlinux" "testuser"
    reset_mock_calls
    MOCK_INSTALLED_PKGS=""

    setup_proot_korean 2>/dev/null || true
    assert_was_called "proot_pkg_install"
    cleanup_sandbox "$sb"
}
it "Arch: proot 한글 패키지 설치를 호출한다" _test_korean_arch_installs_pkgs

# =============================================================================
# _setup_ubuntu_korean_locale — PROOT_DISTRO 변수 사용 (하드코딩 수정 검증)
# =============================================================================

describe "proot_env — _setup_ubuntu_korean_locale 경로 검증"

_test_ubuntu_korean_locale_uses_distro_var() {
    local sb; sb=$(make_sandbox)
    _load_domain "$sb" "ubuntu" "testuser"
    _make_proot_rootfs "$sb" "ubuntu" "testuser"

    _setup_ubuntu_korean_locale 2>/dev/null || true

    local profile="${PREFIX}/var/lib/proot-distro/installed-rootfs/ubuntu/home/testuser/.profile"
    local locale_file="${PREFIX}/var/lib/proot-distro/installed-rootfs/ubuntu/etc/default/locale"
    assert_file_exists "$profile"
    assert_file_contains "$profile" "termux-xfce-korean"
    assert_file_exists "$locale_file"
    assert_file_contains "$locale_file" "ko_KR.UTF-8"
    cleanup_sandbox "$sb"
}
it "ubuntu: .profile과 /etc/default/locale을 올바른 경로에 작성한다" _test_ubuntu_korean_locale_uses_distro_var

_test_ubuntu_korean_locale_idempotent() {
    local sb; sb=$(make_sandbox)
    _load_domain "$sb" "ubuntu" "testuser"
    _make_proot_rootfs "$sb" "ubuntu" "testuser"

    _setup_ubuntu_korean_locale 2>/dev/null || true
    _setup_ubuntu_korean_locale 2>/dev/null || true

    local count
    count=$(grep -c "termux-xfce-korean" \
        "${PREFIX}/var/lib/proot-distro/installed-rootfs/ubuntu/home/testuser/.profile")
    assert_eq "1" "$count" "멱등성: korean 블록이 1번만 있어야 한다"
    cleanup_sandbox "$sb"
}
it "멱등성 — korean locale 블록이 중복 추가되지 않는다" _test_ubuntu_korean_locale_idempotent

# =============================================================================
# _setup_arch_korean_locale — PROOT_DISTRO 변수 사용 (하드코딩 수정 검증)
# =============================================================================

describe "proot_env — _setup_arch_korean_locale 경로 검증"

_test_arch_korean_locale_uses_distro_var() {
    local sb; sb=$(make_sandbox)
    _load_domain "$sb" "archlinux" "testuser"
    _make_proot_rootfs "$sb" "archlinux" "testuser"

    local locale_gen="${PREFIX}/var/lib/proot-distro/installed-rootfs/archlinux/etc/locale.gen"
    touch "$locale_gen"

    _setup_arch_korean_locale 2>/dev/null || true

    assert_file_contains "$locale_gen" "ko_KR.UTF-8"
    cleanup_sandbox "$sb"
}
it "archlinux: locale.gen을 올바른 경로에 작성한다" _test_arch_korean_locale_uses_distro_var

# =============================================================================
# _setup_arch_nimf_or_fcitx5 — nimf 성공/실패 분기
# =============================================================================

describe "proot_env — _setup_arch_nimf_or_fcitx5"

_test_arch_nimf_success_writes_nimf_env() {
    local sb; sb=$(make_sandbox)
    _load_domain "$sb" "archlinux" "testuser"
    _make_proot_rootfs "$sb" "archlinux" "testuser"

    # yay 사용 가능 + AUR nimf 설치 성공 mock (proot_aur_install 스파이는 기본 성공)
    proot_ensure_aur_helper() { return 0; }

    _setup_arch_nimf_or_fcitx5 2>/dev/null || true

    local profile="${PREFIX}/var/lib/proot-distro/installed-rootfs/archlinux/home/testuser/.profile"
    assert_file_exists "$profile"
    assert_file_contains "$profile" "GTK_IM_MODULE=nimf"
    cleanup_sandbox "$sb"
}
it "nimf AUR 빌드 성공 시 nimf 환경변수를 .profile에 쓴다" _test_arch_nimf_success_writes_nimf_env

_test_arch_nimf_failure_falls_back_to_fcitx5() {
    local sb; sb=$(make_sandbox)
    _load_domain "$sb" "archlinux" "testuser"
    _make_proot_rootfs "$sb" "archlinux" "testuser"

    # paru 설치 실패 mock → fcitx5 폴백 경로
    proot_ensure_aur_helper() { return 1; }

    _setup_arch_nimf_or_fcitx5 2>/dev/null || true

    local profile="${PREFIX}/var/lib/proot-distro/installed-rootfs/archlinux/home/testuser/.profile"
    assert_file_exists "$profile"
    assert_file_contains "$profile" "GTK_IM_MODULE=fcitx5"
    cleanup_sandbox "$sb"
}
it "nimf AUR 빌드 실패 시 fcitx5로 폴백하고 .profile에 fcitx5 환경변수를 쓴다" _test_arch_nimf_failure_falls_back_to_fcitx5

_test_arch_nimf_fcitx5_idempotent() {
    local sb; sb=$(make_sandbox)
    _load_domain "$sb" "archlinux" "testuser"
    _make_proot_rootfs "$sb" "archlinux" "testuser"

    proot_ensure_aur_helper() { return 1; }

    _setup_arch_nimf_or_fcitx5 2>/dev/null || true
    _setup_arch_nimf_or_fcitx5 2>/dev/null || true

    local count
    count=$(grep -c "termux-xfce-korean" \
        "${PREFIX}/var/lib/proot-distro/installed-rootfs/archlinux/home/testuser/.profile")
    assert_eq "1" "$count" "멱등성: korean 블록이 1번만 있어야 한다"
    cleanup_sandbox "$sb"
}
it "멱등성 — _setup_arch_nimf_or_fcitx5가 중복 호출돼도 .profile 블록은 1개" _test_arch_nimf_fcitx5_idempotent

_test_arch_nimf_fallback_installs_fcitx5_pkgs() {
    local sb; sb=$(make_sandbox)
    _load_domain "$sb" "archlinux" "testuser"
    _make_proot_rootfs "$sb" "archlinux" "testuser"
    reset_mock_calls

    proot_ensure_aur_helper() { return 1; }

    _setup_arch_nimf_or_fcitx5 2>/dev/null || true
    assert_was_called "proot_pkg_install"
    cleanup_sandbox "$sb"
}
it "nimf 폴백 시 fcitx5 패키지 설치를 호출한다" _test_arch_nimf_fallback_installs_fcitx5_pkgs

# =============================================================================
# setup_proot_conky — SCRIPT_DIR cp / 멱등성 / emoji 폰트 복사
# =============================================================================

describe "proot_env — setup_proot_conky"

_REAL_PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

_test_conky_copies_from_repo() {
    local sb; sb=$(make_sandbox)
    _load_domain "$sb" "ubuntu" "testuser"
    _make_proot_rootfs "$sb" "ubuntu" "testuser"
    export SCRIPT_DIR="${_REAL_PROJECT_DIR}"

    setup_proot_conky 2>/dev/null || true

    assert_dir_exists \
        "${PREFIX}/var/lib/proot-distro/installed-rootfs/ubuntu/home/testuser/.config/conky"
    cleanup_sandbox "$sb"
}
it "SCRIPT_DIR 있으면 tar/conky에서 직접 복사한다" _test_conky_copies_from_repo

_test_conky_idempotent() {
    local sb; sb=$(make_sandbox)
    _load_domain "$sb" "ubuntu" "testuser"
    _make_proot_rootfs "$sb" "ubuntu" "testuser"
    export SCRIPT_DIR="${_REAL_PROJECT_DIR}"

    setup_proot_conky 2>/dev/null || true
    local conky_dir="${PREFIX}/var/lib/proot-distro/installed-rootfs/ubuntu/home/testuser/.config/conky"
    local mtime1; mtime1=$(stat -c %Y "$conky_dir")
    sleep 1
    setup_proot_conky 2>/dev/null || true
    local mtime2; mtime2=$(stat -c %Y "$conky_dir")

    assert_eq "$mtime1" "$mtime2" "멱등성: conky 디렉토리가 재복사되면 안 된다"
    cleanup_sandbox "$sb"
}
it "멱등성 — conky가 이미 있으면 재복사하지 않는다" _test_conky_idempotent

_test_conky_copies_emoji_font() {
    local sb; sb=$(make_sandbox)
    _load_domain "$sb" "ubuntu" "testuser"
    _make_proot_rootfs "$sb" "ubuntu" "testuser"
    export SCRIPT_DIR="${_REAL_PROJECT_DIR}"

    # NotoColorEmoji 준비
    mkdir -p "${HOME}/.fonts"
    touch "${HOME}/.fonts/NotoColorEmoji-Regular.ttf"

    setup_proot_conky 2>/dev/null || true

    assert_file_exists \
        "${PREFIX}/var/lib/proot-distro/installed-rootfs/ubuntu/home/testuser/.fonts/NotoColorEmoji-Regular.ttf"
    cleanup_sandbox "$sb"
}
it "NotoColorEmoji를 proot 홈 .fonts에 복사한다" _test_conky_copies_emoji_font

# =============================================================================
# _install_ubuntu_nimf_deb — deb 다운로드/설치, 멱등성
# =============================================================================

describe "proot_env — _install_ubuntu_nimf_deb"

_test_nimf_deb_skips_when_installed() {
    local sb; sb=$(make_sandbox)
    _load_domain "$sb" "ubuntu" "testuser"
    reset_mock_calls

    # nimf 이미 설치됨 mock
    proot_exec() {
        _record_call "proot_exec $*"
        if [[ "$*" == *"command -v nimf"* ]]; then return 0; fi
        return 0
    }

    _install_ubuntu_nimf_deb 2>/dev/null || true
    # nimf 존재 확인 후 return → deb 설치 포트 호출 없어야 함
    assert_not_called "proot_pkg_install_deb_url"
    cleanup_sandbox "$sb"
}
it "nimf 이미 설치 시 건너뛴다" _test_nimf_deb_skips_when_installed

_test_nimf_deb_downloads_all_debs() {
    local sb; sb=$(make_sandbox)
    _load_domain "$sb" "ubuntu" "testuser"
    reset_mock_calls

    # nimf 미설치 mock
    proot_exec() {
        _record_call "proot_exec $*"
        if [[ "$*" == *"command -v nimf"* ]]; then return 1; fi
        return 0
    }

    _install_ubuntu_nimf_deb 2>/dev/null || true
    assert_was_called "nimf_1.4.17_arm64-ubuntu.2404.arm64.deb"
    assert_was_called "nimf-i18n_1.4.17_arm64-ubuntu.2404.arm64.deb"
    cleanup_sandbox "$sb"
}
it "nimf 미설치 시 모든 .deb를 다운로드한다" _test_nimf_deb_downloads_all_debs

# 헥사고날: 도메인은 apt/dpkg를 모른다. .deb URL 설치는 포트로 위임하고
# 런타임 의존성 패키지명(도메인 지식)은 proot_pkg_install 포트로 요청한다.
# (apt-get/dpkg raw 명령 검증은 tests/test_adapters.sh의 pkg_ubuntu 어댑터 테스트)
_test_nimf_deb_delegates_to_port() {
    local sb; sb=$(make_sandbox)
    _load_domain "$sb" "ubuntu" "testuser"
    reset_mock_calls

    proot_exec() {
        _record_call "proot_exec $*"
        if [[ "$*" == *"command -v nimf"* ]]; then return 1; fi
        return 0
    }

    _install_ubuntu_nimf_deb 2>/dev/null || true
    # 런타임 의존성은 포트로 설치
    assert_was_called "proot_pkg_install libglib2.0-0 libgtk-3-0 libdbus-1-3"
    # .deb 설치는 URL 포트로 위임 (도메인은 dpkg/apt를 모름)
    assert_was_called "proot_pkg_install_deb_url"
    cleanup_sandbox "$sb"
}
it "deb 설치를 포트(proot_pkg_install_deb_url)로 위임한다" _test_nimf_deb_delegates_to_port

# =============================================================================
# _setup_ubuntu_korean_locale — nimf & 가드
# =============================================================================

describe "proot_env — _setup_ubuntu_korean_locale nimf 가드"

_test_ubuntu_profile_guards_nimf_exec() {
    local sb; sb=$(make_sandbox)
    _load_domain "$sb" "ubuntu" "testuser"
    _make_proot_rootfs "$sb" "ubuntu" "testuser"

    _setup_ubuntu_korean_locale 2>/dev/null || true

    local profile="${PREFIX}/var/lib/proot-distro/installed-rootfs/ubuntu/home/testuser/.profile"
    # "nimf &" 가 단독으로 있으면 안 됨 — command -v 가드 필요
    # grep -c는 0 매치 시 "0" 출력 후 exit 1 → `|| echo 0`은 "0\n0" 생성하므로 사용 금지
    local bare_nimf
    bare_nimf=$(grep -c '^nimf &$' "$profile" 2>/dev/null) || bare_nimf=0
    assert_eq "0" "$bare_nimf" ".profile에 가드 없는 'nimf &'가 없어야 한다"
    assert_file_contains "$profile" "command -v nimf"
    cleanup_sandbox "$sb"
}
it ".profile에서 nimf 실행을 command -v로 가드한다" _test_ubuntu_profile_guards_nimf_exec

_test_ubuntu_profile_nimf_uses_disown() {
    local sb; sb=$(make_sandbox)
    _load_domain "$sb" "ubuntu" "testuser"
    _make_proot_rootfs "$sb" "ubuntu" "testuser"

    _setup_ubuntu_korean_locale 2>/dev/null || true

    local profile="${PREFIX}/var/lib/proot-distro/installed-rootfs/ubuntu/home/testuser/.profile"
    assert_file_contains "$profile" "disown" \
        ".profile의 nimf 백그라운드 실행에 disown이 있어야 한다"
    cleanup_sandbox "$sb"
}
it ".profile의 nimf 백그라운드 실행에 disown을 포함한다 (job 완료 메시지 억제)" _test_ubuntu_profile_nimf_uses_disown

_test_arch_nimf_profile_guards_nimf_exec() {
    local sb; sb=$(make_sandbox)
    _load_domain "$sb" "archlinux" "testuser"
    _make_proot_rootfs "$sb" "archlinux" "testuser"

    proot_ensure_aur_helper() { return 0; }

    _setup_arch_nimf_or_fcitx5 2>/dev/null || true

    local profile="${PREFIX}/var/lib/proot-distro/installed-rootfs/archlinux/home/testuser/.profile"
    local bare_nimf
    bare_nimf=$(grep -c '^nimf &$' "$profile" 2>/dev/null) || bare_nimf=0
    assert_eq "0" "$bare_nimf" ".profile에 가드 없는 'nimf &'가 없어야 한다"
    assert_file_contains "$profile" "command -v nimf"
    cleanup_sandbox "$sb"
}
it "Arch nimf 성공 시에도 .profile nimf 실행을 가드한다" _test_arch_nimf_profile_guards_nimf_exec

_test_arch_nimf_profile_uses_disown() {
    local sb; sb=$(make_sandbox)
    _load_domain "$sb" "archlinux" "testuser"
    _make_proot_rootfs "$sb" "archlinux" "testuser"

    proot_ensure_aur_helper() { return 0; }

    _setup_arch_nimf_or_fcitx5 2>/dev/null || true

    local profile="${PREFIX}/var/lib/proot-distro/installed-rootfs/archlinux/home/testuser/.profile"
    assert_file_contains "$profile" "disown" \
        ".profile의 nimf 백그라운드 실행에 disown이 있어야 한다"
    cleanup_sandbox "$sb"
}
it "Arch nimf 성공 시 .profile nimf 백그라운드 실행에 disown을 포함한다" _test_arch_nimf_profile_uses_disown

_test_arch_fcitx5_profile_uses_disown() {
    local sb; sb=$(make_sandbox)
    _load_domain "$sb" "archlinux" "testuser"
    _make_proot_rootfs "$sb" "archlinux" "testuser"

    proot_ensure_aur_helper() { return 1; }  # nimf 빌드 실패 → fcitx5 폴백

    _setup_arch_nimf_or_fcitx5 2>/dev/null || true

    local profile="${PREFIX}/var/lib/proot-distro/installed-rootfs/archlinux/home/testuser/.profile"
    assert_file_contains "$profile" "disown" \
        ".profile의 fcitx5 백그라운드 실행에 disown이 있어야 한다"
    cleanup_sandbox "$sb"
}
it "Arch fcitx5 폴백 시 .profile fcitx5 백그라운드 실행에 disown을 포함한다" _test_arch_fcitx5_profile_uses_disown

# =============================================================================
# setup_proot_timezone — getprop + proot_exec_root
# =============================================================================

describe "proot_env — setup_proot_timezone"

_test_timezone_calls_exec_root() {
    local sb; sb=$(make_sandbox)
    _load_domain "$sb" "ubuntu" "testuser"
    reset_mock_calls
    getprop() { echo "Asia/Seoul"; }
    proot_exec_root() { _record_call "proot_exec_root $*"; }

    setup_proot_timezone 2>/dev/null || true
    assert_was_called "proot_exec_root ln -sf"
    cleanup_sandbox "$sb"
}
it "proot_exec_root로 /etc/localtime 심볼릭 링크를 생성한다" _test_timezone_calls_exec_root

_test_timezone_uses_getprop_value() {
    local sb; sb=$(make_sandbox)
    _load_domain "$sb" "ubuntu" "testuser"
    reset_mock_calls
    getprop() { echo "America/New_York"; }
    local _tz_arg=""
    proot_exec_root() {
        _record_call "proot_exec_root $*"
        [[ "$*" == *"America/New_York"* ]] && _tz_arg="ok"
    }

    setup_proot_timezone 2>/dev/null || true
    assert_was_called "America/New_York"
    cleanup_sandbox "$sb"
}
it "getprop 결과를 시간대로 사용한다" _test_timezone_uses_getprop_value

# =============================================================================
# setup_proot_hardware_accel — distro 분기 GPU 유틸 설치
# =============================================================================

describe "proot_env — setup_proot_hardware_accel"

_test_hw_accel_ubuntu_pkgs() {
    local sb; sb=$(make_sandbox)
    _load_domain "$sb" "ubuntu" "testuser"
    reset_mock_calls

    setup_proot_hardware_accel 2>/dev/null || true
    assert_was_called "proot_pkg_install mesa-utils vulkan-tools"
    cleanup_sandbox "$sb"
}
it "Ubuntu: mesa-utils, vulkan-tools를 설치한다" _test_hw_accel_ubuntu_pkgs

_test_hw_accel_arch_pkgs() {
    local sb; sb=$(make_sandbox)
    _load_domain "$sb" "archlinux" "testuser"
    reset_mock_calls

    setup_proot_hardware_accel 2>/dev/null || true
    assert_was_called "proot_pkg_install mesa vulkan-tools mesa-demos"
    cleanup_sandbox "$sb"
}
it "Arch: mesa, vulkan-tools, mesa-demos를 설치한다" _test_hw_accel_arch_pkgs

# =============================================================================
# teardown_proot — 제거 흐름
# =============================================================================

describe "proot_env — teardown_proot"

_test_teardown_calls_proot_remove() {
    local sb; sb=$(make_sandbox)
    _load_domain "$sb" "ubuntu" "testuser"
    reset_mock_calls
    proot_remove() { _record_call "proot_remove $*"; }

    # alias를 bashrc에 미리 추가
    echo "alias ubuntu='proot-distro login ubuntu'" >> "${PREFIX}/etc/bash.bashrc"

    teardown_proot 2>/dev/null || true
    assert_was_called "proot_remove ubuntu"
    cleanup_sandbox "$sb"
}
it "proot_remove를 호출하여 rootfs를 제거한다" _test_teardown_calls_proot_remove

_test_teardown_removes_alias_from_bashrc() {
    local sb; sb=$(make_sandbox)
    _load_domain "$sb" "ubuntu" "testuser"
    proot_remove() { _record_call "proot_remove $*"; }

    echo "alias ubuntu='proot-distro login ubuntu'" >> "${PREFIX}/etc/bash.bashrc"

    teardown_proot 2>/dev/null || true
    assert_file_not_contains "${PREFIX}/etc/bash.bashrc" "alias ubuntu="
    cleanup_sandbox "$sb"
}
it "bash.bashrc에서 distro alias를 제거한다" _test_teardown_removes_alias_from_bashrc

_test_teardown_removes_alias_from_zshrc() {
    local sb; sb=$(make_sandbox)
    _load_domain "$sb" "ubuntu" "testuser"
    proot_remove() { _record_call "proot_remove $*"; }

    touch "${HOME}/.zshrc"
    echo "alias ubuntu='proot-distro login ubuntu'" >> "${HOME}/.zshrc"

    teardown_proot 2>/dev/null || true
    assert_file_not_contains "${HOME}/.zshrc" "alias ubuntu="
    cleanup_sandbox "$sb"
}
it ".zshrc에서 distro alias를 제거한다" _test_teardown_removes_alias_from_zshrc

_test_teardown_clears_config() {
    local sb; sb=$(make_sandbox)
    _load_domain "$sb" "ubuntu" "testuser"
    proot_remove() { _record_call "proot_remove $*"; }

    # config에 PROOT_DISTRO 설정
    cat > "${HOME}/.config/termux-xfce/config" << 'EOF'
PROOT_DISTRO="ubuntu"
PROOT_USER="testuser"
EOF

    teardown_proot 2>/dev/null || true
    assert_file_contains "${HOME}/.config/termux-xfce/config" 'PROOT_DISTRO=""'
    cleanup_sandbox "$sb"
}
it "config 파일에서 PROOT_DISTRO를 비운다" _test_teardown_clears_config

# =============================================================================
# setup_proot_alias — bashrc/zshrc alias 추가
# =============================================================================

describe "proot_env — setup_proot_alias"

_test_proot_alias_added_to_bashrc() {
    local sb; sb=$(make_sandbox)
    _load_domain "$sb" "ubuntu" "testuser"

    setup_proot_alias 2>/dev/null || true
    assert_file_contains "${PREFIX}/etc/bash.bashrc" "alias ubuntu="
    cleanup_sandbox "$sb"
}
it "bash.bashrc에 distro alias를 추가한다" _test_proot_alias_added_to_bashrc

_test_proot_alias_added_to_zshrc() {
    local sb; sb=$(make_sandbox)
    _load_domain "$sb" "ubuntu" "testuser"
    touch "${HOME}/.zshrc"

    setup_proot_alias 2>/dev/null || true
    assert_file_contains "${HOME}/.zshrc" "alias ubuntu="
    cleanup_sandbox "$sb"
}
it ".zshrc에 distro alias를 추가한다" _test_proot_alias_added_to_zshrc

_test_proot_alias_idempotent() {
    local sb; sb=$(make_sandbox)
    _load_domain "$sb" "ubuntu" "testuser"

    setup_proot_alias 2>/dev/null || true
    setup_proot_alias 2>/dev/null || true
    local count
    count=$(grep -c "alias ubuntu=" "${PREFIX}/etc/bash.bashrc")
    assert_eq "1" "$count" "멱등성: alias가 1번만 있어야 한다"
    cleanup_sandbox "$sb"
}
it "멱등성 — alias가 중복 추가되지 않는다" _test_proot_alias_idempotent

_test_proot_alias_contains_env_u_ld_preload() {
    local sb; sb=$(make_sandbox)
    _load_domain "$sb" "ubuntu" "testuser"

    setup_proot_alias 2>/dev/null || true
    assert_file_contains "${PREFIX}/etc/bash.bashrc" "env -u LD_PRELOAD"
    cleanup_sandbox "$sb"
}
it "alias에 env -u LD_PRELOAD가 포함된다" _test_proot_alias_contains_env_u_ld_preload

# =============================================================================
# _generate_proot_fancybash — distro별 프롬프트 생성
# =============================================================================

describe "proot_env — _generate_proot_fancybash"

_test_fancybash_generates_file() {
    local sb; sb=$(make_sandbox)
    _load_domain "$sb" "ubuntu" "testuser"
    _make_proot_rootfs "$sb" "ubuntu" "testuser"

    local dst="${PREFIX}/var/lib/proot-distro/installed-rootfs/ubuntu/home/testuser/.fancybash.sh"
    _generate_proot_fancybash "$dst" 2>/dev/null || true
    assert_file_exists "$dst"
    cleanup_sandbox "$sb"
}
it "fancybash 파일을 생성한다" _test_fancybash_generates_file

_test_fancybash_ubuntu_has_orange_color() {
    local sb; sb=$(make_sandbox)
    _load_domain "$sb" "ubuntu" "testuser"
    _make_proot_rootfs "$sb" "ubuntu" "testuser"

    local dst="${PREFIX}/var/lib/proot-distro/installed-rootfs/ubuntu/home/testuser/.fancybash.sh"
    _generate_proot_fancybash "$dst" 2>/dev/null || true
    assert_file_contains "$dst" "208"   # Ubuntu orange color code
    assert_file_contains "$dst" "ubuntu"
    cleanup_sandbox "$sb"
}
it "Ubuntu: 오렌지 컬러(208)와 distro명을 포함한다" _test_fancybash_ubuntu_has_orange_color

_test_fancybash_arch_has_blue_color() {
    local sb; sb=$(make_sandbox)
    _load_domain "$sb" "archlinux" "testuser"
    _make_proot_rootfs "$sb" "archlinux" "testuser"

    local dst="${PREFIX}/var/lib/proot-distro/installed-rootfs/archlinux/home/testuser/.fancybash.sh"
    _generate_proot_fancybash "$dst" 2>/dev/null || true
    assert_file_contains "$dst" "75"    # Arch blue color code
    assert_file_contains "$dst" "archlinux"
    cleanup_sandbox "$sb"
}
it "Arch: 블루 컬러(75)와 distro명을 포함한다" _test_fancybash_arch_has_blue_color

_test_fancybash_contains_git_branch() {
    local sb; sb=$(make_sandbox)
    _load_domain "$sb" "ubuntu" "testuser"
    _make_proot_rootfs "$sb" "ubuntu" "testuser"

    local dst="${PREFIX}/var/lib/proot-distro/installed-rootfs/ubuntu/home/testuser/.fancybash.sh"
    _generate_proot_fancybash "$dst" 2>/dev/null || true
    assert_file_contains "$dst" "__git_branch"
    cleanup_sandbox "$sb"
}
it "git branch 표시 함수가 포함된다" _test_fancybash_contains_git_branch

# =============================================================================
# _setup_ubuntu_nimf — im-config 호출
# =============================================================================

describe "proot_env — _setup_ubuntu_nimf"

_test_ubuntu_nimf_calls_im_config() {
    local sb; sb=$(make_sandbox)
    _load_domain "$sb" "ubuntu" "testuser"
    reset_mock_calls

    _setup_ubuntu_nimf 2>/dev/null || true
    assert_was_called "im-config -n nimf"
    cleanup_sandbox "$sb"
}
it "proot_exec로 im-config -n nimf를 호출한다" _test_ubuntu_nimf_calls_im_config

# =============================================================================
# _write_arch_im_env — nimf/fcitx5 분기 직접 검증
# =============================================================================

describe "proot_env — _write_arch_im_env"

_test_write_arch_im_env_nimf() {
    local sb; sb=$(make_sandbox)
    _load_domain "$sb" "archlinux" "testuser"
    _make_proot_rootfs "$sb" "archlinux" "testuser"
    touch "${PREFIX}/var/lib/proot-distro/installed-rootfs/archlinux/home/testuser/.profile"

    _write_arch_im_env true 2>/dev/null || true

    local profile="${PREFIX}/var/lib/proot-distro/installed-rootfs/archlinux/home/testuser/.profile"
    assert_file_contains "$profile" "GTK_IM_MODULE=nimf"
    cleanup_sandbox "$sb"
}
it "use_nimf=true 시 nimf 환경변수를 쓴다" _test_write_arch_im_env_nimf

_test_write_arch_im_env_fcitx5() {
    local sb; sb=$(make_sandbox)
    _load_domain "$sb" "archlinux" "testuser"
    _make_proot_rootfs "$sb" "archlinux" "testuser"
    touch "${PREFIX}/var/lib/proot-distro/installed-rootfs/archlinux/home/testuser/.profile"

    _write_arch_im_env false 2>/dev/null || true

    local profile="${PREFIX}/var/lib/proot-distro/installed-rootfs/archlinux/home/testuser/.profile"
    assert_file_contains "$profile" "GTK_IM_MODULE=fcitx5"
    cleanup_sandbox "$sb"
}
it "use_nimf=false 시 fcitx5 환경변수를 쓴다" _test_write_arch_im_env_fcitx5

# =============================================================================
# (yay 빌드 raw 명령 검증은 tests/test_adapters.sh의 pkg_arch 어댑터 테스트로 이동.
#  헥사고날: 도메인은 AUR 헬퍼를 proot_ensure_aur_helper 포트로만 호출한다.)
# =============================================================================
# 회귀: set -e + ((_i++)) 폭탄 — proot_env.sh의 카운터 루프 5곳
# -----------------------------------------------------------------------------
# Stage 4 실제 설치(--proot-only --distro ubuntu)에서 setup_proot_base_packages가
# `((_i++))` 첫 호출 시 0 반환 → set -e 트립 → 패키지 1개도 못 깐 채 종료.
# `((++_i))` 로 변경 (pre-increment, 항상 새 값 반환).
# =============================================================================

describe "proot_env — set -e safe counter (regression)"

_test_setup_proot_base_packages_ubuntu_completes_under_set_e() {
    local sb; sb=$(make_sandbox)
    _load_domain "$sb" "ubuntu" "testuser"
    _make_proot_rootfs "$sb" "ubuntu" "testuser"
    reset_mock_calls
    MOCK_INSTALLED_PKGS=""

    # || true 없이 호출 — set -e 하에서 모든 패키지를 끝까지 시도해야 함
    setup_proot_base_packages

    local install_count=0
    for call in "${MOCK_CALLS[@]:-}"; do
        [[ "$call" == "proot_pkg_install "* ]] && install_count=$((install_count + 1))
    done
    local expected=$(( ${#PKGS_PROOT_UBUNTU_BASE[@]} + ${#PKGS_PROOT_UBUNTU_DESKTOP[@]} ))
    assert_eq "$expected" "$install_count" "Ubuntu base+desktop 패키지 모두 시도되어야 함"
    cleanup_sandbox "$sb"
}
it "setup_proot_base_packages(ubuntu)가 set -e 하에서 끝까지 실행된다" _test_setup_proot_base_packages_ubuntu_completes_under_set_e

_test_setup_proot_base_packages_arch_completes_under_set_e() {
    local sb; sb=$(make_sandbox)
    _load_domain "$sb" "archlinux" "testuser"
    _make_proot_rootfs "$sb" "archlinux" "testuser"
    reset_mock_calls
    MOCK_INSTALLED_PKGS=""

    setup_proot_base_packages

    local install_count=0
    for call in "${MOCK_CALLS[@]:-}"; do
        [[ "$call" == "proot_pkg_install "* ]] && install_count=$((install_count + 1))
    done
    local expected=$(( ${#PKGS_PROOT_ARCH_BASE[@]} + ${#PKGS_PROOT_ARCH_DESKTOP[@]} ))
    assert_eq "$expected" "$install_count" "Arch base+desktop 패키지 모두 시도되어야 함"
    cleanup_sandbox "$sb"
}
it "setup_proot_base_packages(arch)가 set -e 하에서 끝까지 실행된다" _test_setup_proot_base_packages_arch_completes_under_set_e

_test_no_post_increment_in_proot_env() {
    # 정적 검사: 향후 ((_i++)) 패턴이 재도입되지 않도록 grep으로 가드
    if grep -E '\(\(_*i\+\+\)\)' "${DOMAIN_DIR}/proot_env.sh" >/dev/null; then
        echo "[ASSERT] proot_env.sh에 금지된 '((i++))' 패턴 재도입됨 — '((++i))' 사용 필요" >&2
        grep -nE '\(\(_*i\+\+\)\)' "${DOMAIN_DIR}/proot_env.sh" >&2
        return 1
    fi
}
it "proot_env.sh에 ((i++)) post-increment 패턴이 없다" _test_no_post_increment_in_proot_env

# =============================================================================
# _proot_rootfs — 레이아웃 자동 판별 (신규 containers/<distro>/rootfs vs 레거시)
# =============================================================================

describe "proot_env — _proot_rootfs 경로 해석"

_test_proot_rootfs_prefers_new_layout() {
    local sb; sb=$(make_sandbox)
    _load_domain "$sb" "ubuntu"
    local base="${PREFIX}/var/lib/proot-distro"
    mkdir -p "${base}/containers/ubuntu/rootfs"

    assert_eq "${base}/containers/ubuntu/rootfs" "$(_proot_rootfs)" \
        "신규 레이아웃이 있으면 containers/<distro>/rootfs를 반환해야 함"
    cleanup_sandbox "$sb"
}
it "신규 레이아웃이 있으면 containers/<distro>/rootfs를 반환한다" _test_proot_rootfs_prefers_new_layout

_test_proot_rootfs_falls_back_to_legacy() {
    local sb; sb=$(make_sandbox)
    _load_domain "$sb" "ubuntu"
    local base="${PREFIX}/var/lib/proot-distro"
    mkdir -p "${base}/installed-rootfs/ubuntu"   # 레거시만 존재

    assert_eq "${base}/installed-rootfs/ubuntu" "$(_proot_rootfs)" \
        "레거시 레이아웃만 있으면 installed-rootfs/<distro>로 폴백해야 함"
    cleanup_sandbox "$sb"
}
it "레거시 레이아웃만 있으면 installed-rootfs/<distro>로 폴백한다" _test_proot_rootfs_falls_back_to_legacy

_test_proot_rootfs_new_wins_when_both_exist() {
    local sb; sb=$(make_sandbox)
    _load_domain "$sb" "ubuntu"
    local base="${PREFIX}/var/lib/proot-distro"
    mkdir -p "${base}/containers/ubuntu/rootfs" "${base}/installed-rootfs/ubuntu"

    assert_eq "${base}/containers/ubuntu/rootfs" "$(_proot_rootfs)" \
        "두 레이아웃이 공존하면 신규를 우선해야 함"
    cleanup_sandbox "$sb"
}
it "두 레이아웃이 공존하면 신규를 우선한다" _test_proot_rootfs_new_wins_when_both_exist

print_results
