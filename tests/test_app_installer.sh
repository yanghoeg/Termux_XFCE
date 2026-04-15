#!/data/data/com.termux/files/usr/bin/bash
# =============================================================================
# TEST: app-installer/
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/framework.sh"
source "${SCRIPT_DIR}/mocks.sh"

APP_DIR="${SCRIPT_DIR}/../app-installer"

# =============================================================================
# 정적 분석 — 스크립트 구조 검증
# =============================================================================

describe "app-installer — shebang 유효성"

_test_vlc_shebang() {
    local first
    first=$(head -1 "${APP_DIR}/install_vlc.sh")
    # #! 로 시작해야 함 (## 아님)
    if [[ "$first" == "##"* ]]; then
        echo "[ASSERT] install_vlc.sh shebang 이중 # 오류: $first" >&2
        return 1
    fi
    [[ "$first" == "#!/"* ]]
}
it "install_vlc.sh — shebang이 올바르다 (# 하나)" _test_vlc_shebang

_test_all_shebangs() {
    local failed=0
    for f in "${APP_DIR}"/install_*.sh; do
        local first; first=$(head -1 "$f")
        if [[ "$first" == "##"* ]]; then
            echo "[ASSERT] $(basename "$f") shebang 이중 #: $first" >&2
            failed=1
        fi
    done
    return "$failed"
}
it "모든 install_*.sh — shebang 단일 #" _test_all_shebangs

# =============================================================================
# 정적 분석 — 명백한 타이포
# =============================================================================

describe "app-installer — 명백한 타이포"

_test_no_wget_wget() {
    if grep -r "wget wget" "${APP_DIR}"/ 2>/dev/null | grep -q .; then
        grep -r "wget wget" "${APP_DIR}"/ >&2
        echo "[ASSERT] 'wget wget' 이중 명령 발견" >&2
        return 1
    fi
}
it "install_miniforge.sh — 'wget wget' 이중 명령 없음" _test_no_wget_wget

_test_no_home_dotdot() {
    if grep -r 'HOME/../usr' "${APP_DIR}"/ 2>/dev/null | grep -q .; then
        grep -r 'HOME/../usr' "${APP_DIR}"/ >&2
        echo "[ASSERT] '\$HOME/../usr/' 경로 발견 — \$PREFIX 사용 필요" >&2
        return 1
    fi
}
it "모든 스크립트 — '\$HOME/../usr/' 경로 없음 (\$PREFIX 사용)" _test_no_home_dotdot

_test_no_hardcoded_ubuntu() {
    # install.sh(메인), install_wine.sh(명시적 분기) 는 제외
    local offenders=()
    for f in "${APP_DIR}"/install_*.sh; do
        [[ "$(basename "$f")" == "install_wine.sh" ]] && continue
        if grep -q "proot-distro login ubuntu" "$f" 2>/dev/null; then
            offenders+=("$(basename "$f")")
        fi
    done
    if [ "${#offenders[@]}" -gt 0 ]; then
        echo "[ASSERT] hardcoded 'ubuntu' proot login: ${offenders[*]}" >&2
        return 1
    fi
}
it "install_*.sh — proot-distro login에 distro 하드코딩 없음" _test_no_hardcoded_ubuntu

# =============================================================================
# install.sh — 설정 로드 + check 함수
# =============================================================================

describe "app-installer/install.sh — 설정 로드"

_load_installer() {
    local sandbox="$1"
    export HOME="${sandbox}/home"
    export PREFIX="${sandbox}/usr"
    mkdir -p "${HOME}/.config/termux-xfce" \
             "${PREFIX}/share/applications" \
             "${PREFIX}/var/lib/proot-distro/installed-rootfs/ubuntu/home/testuser"

    cat > "${HOME}/.config/termux-xfce/config" << 'EOF'
PROOT_DISTRO="ubuntu"
PROOT_USER="testuser"
EOF

    # zenity, proot-distro mock
    zenity()        { echo "ZENITY: $*"; }
    proot-distro()  { echo "PROOT: $*"; }

    # install.sh의 메인 루프는 실행 안 함 — 함수 정의만 source
    # 메인 루프(while true) 전까지만 로드
    local tmp="${TMPDIR}/install_partial_$$.sh"
    awk '/^while true/{ exit } { print }' "${APP_DIR}/install.sh" > "$tmp"
    source "$tmp"
    rm -f "$tmp"
}

_test_config_loaded() {
    local sb; sb=$(make_sandbox)
    _load_installer "$sb"

    assert_eq "ubuntu"   "${PROOT_DISTRO:-}" "PROOT_DISTRO"
    assert_eq "testuser" "${PROOT_USER:-}"   "PROOT_USER"
    cleanup_sandbox "$sb"
}
it "config 파일에서 PROOT_DISTRO, PROOT_USER를 로드한다" _test_config_loaded

_test_config_fallback() {
    local sb; sb=$(make_sandbox)
    export HOME="${sb}/home"
    export PREFIX="${sb}/usr"
    mkdir -p "${HOME}/.config/termux-xfce" \
             "${PREFIX}/var/lib/proot-distro/installed-rootfs/ubuntu/home"

    # config 없음 → fallback
    zenity()       { echo "ZENITY: $*"; }
    proot-distro() { echo "PROOT: $*"; }
    local tmp="${TMPDIR}/install_partial_$$.sh"
    awk '/^while true/{ exit } { print }' "${APP_DIR}/install.sh" > "$tmp"
    source "$tmp"
    rm -f "$tmp"

    assert_eq "ubuntu" "${PROOT_DISTRO:-}" "fallback PROOT_DISTRO"
    cleanup_sandbox "$sb"
}
it "config 없을 때 PROOT_DISTRO=ubuntu로 fallback한다" _test_config_fallback

# =============================================================================
# install.sh — check_*_installed 함수
# =============================================================================

describe "app-installer/install.sh — check_installed 함수"

_setup_check_env() {
    local sb="$1"
    _load_installer "$sb"
}

_test_check_not_installed() {
    local sb; sb=$(make_sandbox)
    _setup_check_env "$sb"

    assert_eq "Not Installed" "$(check_vlc_installed)"        "vlc: 미설치"
    assert_eq "Not Installed" "$(check_code_installed)"       "vscode: 미설치"
    assert_eq "Not Installed" "$(check_wine_installed)"       "wine: 미설치"
    assert_eq "Not Installed" "$(check_thunderbird_installed)" "thunderbird: 미설치"
    cleanup_sandbox "$sb"
}
it "desktop 파일 없으면 'Not Installed' 반환" _test_check_not_installed

_test_check_installed_after_desktop_created() {
    local sb; sb=$(make_sandbox)
    _setup_check_env "$sb"

    # desktop 파일 생성
    touch "${PREFIX}/share/applications/vlc.desktop"
    touch "${PREFIX}/share/applications/code.desktop"
    touch "${PREFIX}/share/applications/wine64.desktop"

    assert_eq "Installed" "$(check_vlc_installed)"  "vlc: 설치됨"
    assert_eq "Installed" "$(check_code_installed)"  "vscode: 설치됨"
    assert_eq "Installed" "$(check_wine_installed)"  "wine: 설치됨"
    cleanup_sandbox "$sb"
}
it "desktop 파일 있으면 'Installed' 반환" _test_check_installed_after_desktop_created

_test_check_miniforge_uses_dir() {
    local sb; sb=$(make_sandbox)
    _setup_check_env "$sb"

    # miniforge는 디렉토리 존재 여부로 판단
    assert_eq "Not Installed" "$(check_miniforge_installed)"
    mkdir -p "${PREFIX}/var/lib/proot-distro/installed-rootfs/ubuntu/home/testuser/miniforge3"
    assert_eq "Installed" "$(check_miniforge_installed)"
    cleanup_sandbox "$sb"
}
it "miniforge — 홈 디렉토리 존재 여부로 판단" _test_check_miniforge_uses_dir

# =============================================================================
# install.sh — _action + _row 행 생성 로직
# =============================================================================

describe "app-installer/install.sh — UI 행 생성"

_test_action_not_installed_shows_install() {
    local sb; sb=$(make_sandbox)
    _setup_check_env "$sb"

    local row; row=$(_action "VLC" "Not Installed" "Media player")
    assert_output_contains "$row" "Install VLC"
    assert_output_contains "$row" "Not Installed"
    cleanup_sandbox "$sb"
}
it "미설치 앱은 'Install' 액션을 표시한다" _test_action_not_installed_shows_install

_test_action_installed_shows_remove() {
    local sb; sb=$(make_sandbox)
    _setup_check_env "$sb"

    local row; row=$(_action "VLC" "Installed" "Media player")
    assert_output_contains "$row" "Remove VLC"
    assert_output_contains "$row" "Installed"
    cleanup_sandbox "$sb"
}
it "설치된 앱은 'Remove' 액션을 표시한다" _test_action_installed_shows_remove

# =============================================================================
# install_vlc.sh — 실제 실행 (Termux native, proot 불필요)
# =============================================================================

describe "install_vlc.sh — 실제 설치 테스트"

_test_vlc_installs() {
    # vlc가 pkg에 있는지 확인
    pkg show vlc 2>/dev/null | grep -q "Package: vlc"
}
it "pkg에 vlc 패키지가 존재한다" _test_vlc_installs

_test_vlc_script_syntax() {
    bash -n "${APP_DIR}/install_vlc.sh" 2>/dev/null
}
it "install_vlc.sh — bash 문법 오류 없음" _test_vlc_script_syntax

# =============================================================================
# install_thunderbird.sh — 구조 검증
# =============================================================================

# 헥사고날 리팩토링 이후 installer 파일은 ${APP_DIR}/domain/installers/ 하위에 있음
describe "thunderbird.sh — 구조 검증"

_test_thunderbird_script_syntax() {
    bash -n "${APP_DIR}/domain/installers/thunderbird.sh" 2>/dev/null
}
it "thunderbird.sh — bash 문법 오류 없음" _test_thunderbird_script_syntax

_test_thunderbird_has_desktop_register() {
    # desktop_register 헬퍼 호출 확인 (share/applications 직접 접근은 desktop.sh가 담당)
    grep -q "desktop_register" "${APP_DIR}/domain/installers/thunderbird.sh"
}
it "thunderbird.sh — desktop_register 헬퍼 사용" _test_thunderbird_has_desktop_register

# =============================================================================
# wine.sh — 로직 구조 검증
# =============================================================================

describe "wine.sh — 구조 검증"

_test_wine_script_syntax() {
    bash -n "${APP_DIR}/domain/installers/wine.sh" 2>/dev/null
}
it "wine.sh — bash 문법 오류 없음" _test_wine_script_syntax

_test_wine_has_proot_distro_check() {
    grep -q 'PROOT_DISTRO' "${APP_DIR}/domain/installers/wine.sh"
}
it "wine.sh — PROOT_DISTRO 분기 처리" _test_wine_has_proot_distro_check

_test_wine_has_native_fallback() {
    grep -q '_install_wine_native\|which wine' "${APP_DIR}/domain/installers/wine.sh"
}
it "wine.sh — no-proot native 설치 경로 있음" _test_wine_has_native_fallback

_test_wine_creates_desktop() {
    grep -q 'WINE_DESKTOP' "${APP_DIR}/domain/installers/wine.sh" && \
    grep -q '\[Desktop Entry\]' "${APP_DIR}/domain/installers/wine.sh"
}
it "wine.sh — .desktop 파일 생성 로직 있음" _test_wine_creates_desktop

_test_wine_idempotent_check() {
    grep -q 'which wine' "${APP_DIR}/domain/installers/wine.sh"
}
it "wine.sh — 이미 설치된 경우 건너뛰는 멱등성 체크 있음" _test_wine_idempotent_check

# =============================================================================
# 모든 스크립트 문법 검사
# =============================================================================

describe "모든 install_*.sh — bash 문법"

for _script in "${APP_DIR}"/install_*.sh; do
    _name=$(basename "$_script")
    _test_syntax() {
        bash -n "${APP_DIR}/${_name}" 2>/dev/null
    }
    it "${_name} — 문법 오류 없음" _test_syntax
done

print_results
