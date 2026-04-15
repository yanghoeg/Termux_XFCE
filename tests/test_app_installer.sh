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

# 헥사고날 리팩토링 이후 installer 스크립트는 domain/installers/*.sh 위치
INSTALLERS_DIR="${APP_DIR}/domain/installers"

_test_vlc_shebang() {
    local first
    first=$(head -1 "${INSTALLERS_DIR}/vlc.sh")
    # #! 로 시작해야 함 (## 아님)
    if [[ "$first" == "##"* ]]; then
        echo "[ASSERT] vlc.sh shebang 이중 # 오류: $first" >&2
        return 1
    fi
    [[ "$first" == "#!/"* ]]
}
it "vlc.sh — shebang이 올바르다 (# 하나)" _test_vlc_shebang

_test_all_shebangs() {
    local failed=0
    shopt -s nullglob
    local files=("${INSTALLERS_DIR}"/*.sh)
    shopt -u nullglob
    if [ "${#files[@]}" -eq 0 ]; then
        echo "[ASSERT] installer 스크립트를 찾을 수 없음: ${INSTALLERS_DIR}" >&2
        return 1
    fi
    for f in "${files[@]}"; do
        local first; first=$(head -1 "$f")
        if [[ "$first" == "##"* ]]; then
            echo "[ASSERT] $(basename "$f") shebang 이중 #: $first" >&2
            failed=1
        fi
    done
    return "$failed"
}
it "모든 installer 스크립트 — shebang 단일 #" _test_all_shebangs

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
it "miniforge.sh — 'wget wget' 이중 명령 없음" _test_no_wget_wget

_test_no_home_dotdot() {
    if grep -r 'HOME/../usr' "${APP_DIR}"/ 2>/dev/null | grep -q .; then
        grep -r 'HOME/../usr' "${APP_DIR}"/ >&2
        echo "[ASSERT] '\$HOME/../usr/' 경로 발견 — \$PREFIX 사용 필요" >&2
        return 1
    fi
}
it "모든 스크립트 — '\$HOME/../usr/' 경로 없음 (\$PREFIX 사용)" _test_no_home_dotdot

_test_no_hardcoded_ubuntu() {
    # wine.sh 는 명시적 distro 분기라 제외
    local offenders=()
    shopt -s nullglob
    for f in "${INSTALLERS_DIR}"/*.sh; do
        [[ "$(basename "$f")" == "wine.sh" ]] && continue
        if grep -q "proot-distro login ubuntu" "$f" 2>/dev/null; then
            offenders+=("$(basename "$f")")
        fi
    done
    shopt -u nullglob
    if [ "${#offenders[@]}" -gt 0 ]; then
        echo "[ASSERT] hardcoded 'ubuntu' proot login: ${offenders[*]}" >&2
        return 1
    fi
}
it "installer 스크립트 — proot-distro login에 distro 하드코딩 없음" _test_no_hardcoded_ubuntu

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
# vlc.sh — proot 설치 (VLC는 Qt GUI 의존성으로 proot 내부에 설치)
# =============================================================================

describe "vlc.sh — 구조 검증"

_test_vlc_installs() {
    # vlc가 pkg에 있는지 확인 (Termux native fallback용)
    pkg show vlc 2>/dev/null | grep -q "Package: vlc"
}
it "pkg에 vlc 패키지가 존재한다" _test_vlc_installs

_test_vlc_script_syntax() {
    bash -n "${INSTALLERS_DIR}/vlc.sh" 2>/dev/null
}
it "vlc.sh — bash 문법 오류 없음" _test_vlc_script_syntax

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
# 모든 installer 스크립트 문법 검사
# =============================================================================

describe "모든 installer 스크립트 — bash 문법"

shopt -s nullglob
_INSTALLER_FILES=("${INSTALLERS_DIR}"/*.sh)
shopt -u nullglob

if [ "${#_INSTALLER_FILES[@]}" -eq 0 ]; then
    _test_installers_exist() {
        echo "[ASSERT] installer 스크립트를 찾을 수 없음: ${INSTALLERS_DIR}" >&2
        return 1
    }
    it "installer 스크립트 디렉토리 존재" _test_installers_exist
else
    # 루프 변수를 각 테스트 함수에 캡처하기 위해 클로저로 감쌈
    for _script in "${_INSTALLER_FILES[@]}"; do
        _name=$(basename "$_script")
        _make_syntax_test() {
            local path="$1"
            eval "_test_syntax_${_name//./_}() { bash -n '${path}' 2>/dev/null; }"
            it "${_name} — 문법 오류 없음" "_test_syntax_${_name//./_}"
        }
        _make_syntax_test "$_script"
    done
fi

# app-installer/install.sh(메인 런처)도 문법 검사
_test_main_installer_syntax() {
    bash -n "${APP_DIR}/install.sh" 2>/dev/null
}
it "app-installer/install.sh — 문법 오류 없음" _test_main_installer_syntax

print_results
