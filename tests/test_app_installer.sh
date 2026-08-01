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
    local tmp
    tmp=$(mktemp "$(_test_tmp_base)/install_partial_XXXXXX.sh")
    # install.sh의 `SCRIPT_DIR=$(...)` 라인은 source 시점 $0이 테스트라 잘못 잡히므로 제거 후 외부에서 주입
    awk '
        /^while true/{ exit }
        /^SCRIPT_DIR=/{ next }
        { print }
    ' "${APP_DIR}/install.sh" > "$tmp"
    SCRIPT_DIR="$APP_DIR" source "$tmp"
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
    local tmp
    tmp=$(mktemp "$(_test_tmp_base)/install_partial_XXXXXX.sh")
    # install.sh의 `SCRIPT_DIR=$(...)` 라인은 source 시점 $0이 테스트라 잘못 잡히므로 제거 후 외부에서 주입
    awk '
        /^while true/{ exit }
        /^SCRIPT_DIR=/{ next }
        { print }
    ' "${APP_DIR}/install.sh" > "$tmp"
    SCRIPT_DIR="$APP_DIR" source "$tmp"
    rm -f "$tmp"

    assert_eq "ubuntu" "${PROOT_DISTRO:-}" "fallback PROOT_DISTRO"
    cleanup_sandbox "$sb"
}
it "config 없을 때 PROOT_DISTRO=ubuntu로 fallback한다" _test_config_fallback

# =============================================================================
# install.sh — _detect_proot_user (P1-3 회귀: glob 미매치 시 literal "*" 폭탄)
# =============================================================================

describe "app-installer/install.sh — _detect_proot_user"

# install.sh의 _detect_proot_user만 추출해서 source (다른 부분 부작용 회피)
_load_detect_only() {
    # _detect_proot_user는 _proot_rootfs에 의존 → 리졸버 먼저 로드
    source "${APP_DIR}/lib/proot_path.sh"
    local tmp
    tmp=$(mktemp "$(_test_tmp_base)/detect_only_XXXXXX.sh")
    awk '
        /^_detect_proot_user\(\) \{/{ in_fn=1 }
        in_fn{ print }
        in_fn && /^\}/{ exit }
    ' "${APP_DIR}/install.sh" > "$tmp"
    source "$tmp"
    rm -f "$tmp"
}

_test_detect_proot_user_picks_first_home() {
    local sb; sb=$(make_sandbox)
    export PREFIX="${sb}/usr"
    export PROOT_DISTRO="ubuntu"
    mkdir -p "${PREFIX}/var/lib/proot-distro/installed-rootfs/ubuntu/home/alice"
    _load_detect_only
    local got; got=$(_detect_proot_user)
    assert_eq "alice" "$got" "single home dir"
    cleanup_sandbox "$sb"
}
it "home에 사용자 1명 → 그 이름 반환" _test_detect_proot_user_picks_first_home

_test_detect_proot_user_no_home_returns_user() {
    local sb; sb=$(make_sandbox)
    export PREFIX="${sb}/usr"
    export PROOT_DISTRO="ubuntu"
    # home 디렉토리는 만들지만 사용자 dir 없음 → glob 미매치
    mkdir -p "${PREFIX}/var/lib/proot-distro/installed-rootfs/ubuntu/home"
    _load_detect_only
    local got; got=$(_detect_proot_user)
    assert_eq "user" "$got" "empty home → fallback (P1-3 핵심: literal '*' 반환 차단)"
    cleanup_sandbox "$sb"
}
it "home이 비어있을 때 'user' 폴백 (glob '*' 폭탄 차단)" _test_detect_proot_user_no_home_returns_user

_test_detect_proot_user_no_proot_returns_user() {
    local sb; sb=$(make_sandbox)
    export PREFIX="${sb}/usr"
    export PROOT_DISTRO="ubuntu"
    # proot-distro 자체 미설치 → installed-rootfs 디렉토리 없음
    _load_detect_only
    local got; got=$(_detect_proot_user)
    assert_eq "user" "$got" "proot 미설치 → fallback"
    cleanup_sandbox "$sb"
}
it "proot 미설치 시 'user' 폴백" _test_detect_proot_user_no_proot_returns_user

_test_detect_proot_user_distro_unset_returns_user() {
    local sb; sb=$(make_sandbox)
    export PREFIX="${sb}/usr"
    unset PROOT_DISTRO
    _load_detect_only
    local got; got=$(_detect_proot_user)
    assert_eq "user" "$got" "PROOT_DISTRO 미설정 → fallback"
    cleanup_sandbox "$sb"
}
it "PROOT_DISTRO 미설정 시 set -u에서 트립하지 않고 'user' 반환" _test_detect_proot_user_distro_unset_returns_user

# =============================================================================
# 구 API(check_*_installed, _action)는 헥사고날 리팩토링으로 제거됨
# 새 API: app_is_installed_<id> / app_install_<id> / app_remove_<id> (domain/installers/*.sh)
# 새 API용 테스트는 별도 추가 필요 (TODO)
# =============================================================================

# =============================================================================
# vlc.sh — proot 설치 (VLC는 Qt GUI 의존성으로 proot 내부에 설치)
# =============================================================================

describe "vlc.sh — 구조 검증"

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

_test_wine_no_desktop_shell() {
    ! grep -q '/desktop=shell' "${APP_DIR}/domain/installers/wine.sh"
}
it "wine.sh — explorer /desktop=shell 미사용 (Box64 호환)" _test_wine_no_desktop_shell

_test_wine_has_dpi_sync() {
    grep -q 'WINE_DPI' "${APP_DIR}/domain/installers/wine.sh" && \
    grep -q 'LogPixels' "${APP_DIR}/domain/installers/wine.sh"
}
it "wine.sh — WINE_DPI 레지스트리 동기화 로직 있음" _test_wine_has_dpi_sync

_test_wine_dpi_in_both_wrappers() {
    # proot wrapper와 native wrapper 모두 DPI 지원해야 함
    local proot_dpi native_dpi
    proot_dpi=$(grep -c 'WINE_DPI' "${APP_DIR}/domain/installers/wine.sh")
    [ "$proot_dpi" -ge 4 ]  # proot wrapper + native wrapper 각각 2회 이상
}
it "wine.sh — proot/native 양쪽 wrapper 모두 DPI 지원" _test_wine_dpi_in_both_wrappers

# =============================================================================
# Wine 앱 — 구조 검증
# =============================================================================

describe "Wine 앱 installer — 구조 검증"

_test_wine_apps_have_wine_check() {
    local failed=0
    for id in notepadpp sevenzip sumatrapdf winmerge; do
        local f="${INSTALLERS_DIR}/${id}.sh"
        if [ ! -f "$f" ]; then
            echo "[ASSERT] ${id}.sh 파일 없음" >&2; failed=1; continue
        fi
        if ! command grep -q "app_is_installed_wine" "$f"; then
            echo "[ASSERT] ${id}.sh에 Wine 설치 확인 없음" >&2; failed=1
        fi
    done
    return "$failed"
}
it "모든 Wine 앱 — Wine 설치 여부 체크 있음" _test_wine_apps_have_wine_check

_test_wine_apps_have_desktop_logic() {
    local failed=0
    for id in notepadpp sevenzip sumatrapdf winmerge; do
        local f="${INSTALLERS_DIR}/${id}.sh"
        [ -f "$f" ] || continue
        if ! command grep -q "desktop\|\.desktop" "$f"; then
            echo "[ASSERT] ${id}.sh에 desktop 파일 생성 로직 없음" >&2; failed=1
        fi
    done
    return "$failed"
}
it "모든 Wine 앱 — .desktop 파일 생성 로직 있음" _test_wine_apps_have_desktop_logic

_test_wine_apps_use_wine_in_exec() {
    local failed=0
    for id in notepadpp sevenzip sumatrapdf winmerge; do
        local f="${INSTALLERS_DIR}/${id}.sh"
        [ -f "$f" ] || continue
        if ! command grep -q "wine" "$f"; then
            echo "[ASSERT] ${id}.sh에 wine 명령 없음" >&2; failed=1
        fi
    done
    return "$failed"
}
it "모든 Wine 앱 — desktop Exec에 wine 명령 사용" _test_wine_apps_use_wine_in_exec

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
