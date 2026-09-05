#!/data/data/com.termux/files/usr/bin/bash
# =============================================================================
# TEST: domain/locale_ko.sh
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

    # locale_ko.sh는 clang, unzip 등 호출 → mock
    clang()  { _record_call "clang $*"; }
    unzip()  { _record_call "unzip $*"; mkdir -p "$PREFIX/share/locale/ko/LC_MESSAGES" 2>/dev/null; }
    chmod()  { command chmod "$@"; }

    export SCRIPT_DIR="${SCRIPT_DIR}/.."
    source "${DOMAIN_DIR}/packages.sh" 2>/dev/null || true
    source "${DOMAIN_DIR}/termux_env.sh" 2>/dev/null || true
    source "${DOMAIN_DIR}/locale_ko.sh" 2>/dev/null || true
}

# =============================================================================
# setup_korean_locale_native — 오케스트레이션
# =============================================================================

describe "locale_ko — setup_korean_locale_native"

_test_locale_native_skips_without_zip() {
    local sb; sb=$(make_sandbox)
    _load_domain "$sb"
    export KOREAN_LOCALE_ZIP=""
    reset_ui_output

    setup_korean_locale_native 2>/dev/null || true
    assert_ui_contains "WARN"
    cleanup_sandbox "$sb"
}
it "KOREAN_LOCALE_ZIP 미설정 시 경고 후 건너뛴다" _test_locale_native_skips_without_zip

_test_locale_native_skips_invalid_path() {
    local sb; sb=$(make_sandbox)
    _load_domain "$sb"
    export KOREAN_LOCALE_ZIP="/nonexistent/locale.zip"
    reset_ui_output

    setup_korean_locale_native 2>/dev/null || true
    assert_ui_contains "WARN"
    cleanup_sandbox "$sb"
}
it "KOREAN_LOCALE_ZIP 파일 미존재 시 경고 후 건너뛴다" _test_locale_native_skips_invalid_path

_test_locale_native_runs_all_steps() {
    local sb; sb=$(make_sandbox)
    _load_domain "$sb"

    # 유효한 zip 파일 stub 생성
    local zip_path="${sb}/locale.zip"
    touch "$zip_path"
    export KOREAN_LOCALE_ZIP="$zip_path"
    reset_mock_calls
    reset_ui_output

    setup_korean_locale_native 2>/dev/null || true

    assert_ui_contains "glibc .mo 카탈로그"
    assert_ui_contains "force_gettext.so"
    assert_ui_contains "startxfce4-ko"
    assert_ui_contains "RC 파일에 환경변수 영구 등록"
    assert_ui_contains "DBus 환경 전파"
    cleanup_sandbox "$sb"
}
it "유효한 zip 경로 시 5단계를 모두 실행한다" _test_locale_native_runs_all_steps

# =============================================================================
# _deploy_locale_catalogs — .mo 카탈로그 배치
# =============================================================================

describe "locale_ko — _deploy_locale_catalogs"

_test_deploy_catalogs_calls_unzip() {
    local sb; sb=$(make_sandbox)
    _load_domain "$sb"
    reset_mock_calls

    local zip_path="${sb}/locale.zip"
    touch "$zip_path"

    _deploy_locale_catalogs "$zip_path" 2>/dev/null || true
    assert_was_called "unzip"
    cleanup_sandbox "$sb"
}
it "unzip으로 카탈로그를 배치한다" _test_deploy_catalogs_calls_unzip

_test_deploy_catalogs_idempotent() {
    local sb; sb=$(make_sandbox)
    _load_domain "$sb"

    # 이미 100개 이상의 .mo 파일이 있는 것처럼 설정
    local mo_dir="${PREFIX}/share/locale/ko/LC_MESSAGES"
    mkdir -p "$mo_dir"
    for i in $(seq 1 110); do
        touch "${mo_dir}/fake_${i}.mo"
    done
    reset_mock_calls

    _deploy_locale_catalogs "/dummy.zip" 2>/dev/null || true
    assert_not_called "unzip"
    cleanup_sandbox "$sb"
}
it "멱등성 — ko LC_MESSAGES에 100개 이상 .mo 있으면 건너뛴다" _test_deploy_catalogs_idempotent

_test_deploy_catalogs_unzip_failure_preserves_original() {
    local sb; sb=$(make_sandbox)
    _load_domain "$sb"

    # unzip 실패하도록 오버라이드 (기존 mock은 성공)
    unzip() { _record_call "unzip $*"; return 1; }

    # 기존 locale 디렉토리에 마커 파일 배치
    local dest="${PREFIX}/share/locale"
    mkdir -p "$dest"
    touch "${dest}/marker.txt"

    local zip_path="${sb}/locale.zip"
    touch "$zip_path"
    reset_ui_output

    local rc=0
    _deploy_locale_catalogs "$zip_path" 2>/dev/null || rc=$?

    assert_zero "$rc" "unzip 실패해도 set -e 트립 없이 rc 0"
    assert_file_exists "${dest}/marker.txt"
    ! compgen -G "${dest}.bak."* > /dev/null 2>&1
    cleanup_sandbox "$sb"
}
it "unzip 실패 시 기존 locale 보존 + .bak 생성 안 함" _test_deploy_catalogs_unzip_failure_preserves_original

_test_deploy_catalogs_merges_when_bak_exists() {
    local sb; sb=$(make_sandbox)
    _load_domain "$sb"

    # unzip 성공 스텁: -d 대상 안에 ko 카탈로그 1개 생성
    unzip() {
        local d=""
        while [ $# -gt 0 ]; do [ "$1" = "-d" ] && d="$2"; shift; done
        mkdir -p "${d}/ko/LC_MESSAGES" && touch "${d}/ko/LC_MESSAGES/x.mo"
    }

    # 재실행 상황: dest 존재 + .bak 이미 존재 (백업 mv 건너뜀)
    local dest="${PREFIX}/share/locale"
    mkdir -p "$dest" "${dest}.bak.1"
    touch "${dest}/old.txt"

    local zip_path="${sb}/locale.zip"
    touch "$zip_path"

    _deploy_locale_catalogs "$zip_path" 2>/dev/null

    assert_file_exists "${dest}/ko/LC_MESSAGES/x.mo"
    assert_file_exists "${dest}/old.txt"
    ! compgen -G "${dest}/locale_ko.*" > /dev/null 2>&1
    cleanup_sandbox "$sb"
}
it ".bak 존재 재실행 시 tmp가 dest 하위로 중첩되지 않고 병합된다" _test_deploy_catalogs_merges_when_bak_exists

# =============================================================================
# _build_force_gettext — clang 빌드
# =============================================================================

describe "locale_ko — _build_force_gettext"

_test_force_gettext_builds_so() {
    local sb; sb=$(make_sandbox)
    _load_domain "$sb"
    reset_mock_calls

    # 테스트 저장소 내부가 아닌 샌드박스에 force_gettext.c stub을 둔다.
    export SCRIPT_DIR="${sb}/repo"
    local src_dir="${SCRIPT_DIR}/assets"
    mkdir -p "$src_dir"
    touch "${src_dir}/force_gettext.c"

    _build_force_gettext 2>/dev/null || true
    assert_was_called "clang -shared"
    cleanup_sandbox "$sb"
}
it "clang -shared로 force_gettext.so를 빌드한다" _test_force_gettext_builds_so

_test_force_gettext_idempotent() {
    local sb; sb=$(make_sandbox)
    _load_domain "$sb"
    reset_mock_calls

    # 이미 빌드된 .so가 있음
    touch "${PREFIX}/lib/force_gettext.so"

    _build_force_gettext 2>/dev/null || true
    assert_not_called "clang"
    cleanup_sandbox "$sb"
}
it "멱등성 — force_gettext.so 이미 존재 시 빌드하지 않는다" _test_force_gettext_idempotent

_test_force_gettext_warns_if_src_missing() {
    local sb; sb=$(make_sandbox)
    _load_domain "$sb"
    reset_ui_output

    # force_gettext.c 없음 + .so도 없음
    # SCRIPT_DIR을 샌드박스로 덮어 assets/force_gettext.c가 없는 상태로 만든다
    export SCRIPT_DIR="$sb"
    rm -f "${PREFIX}/lib/force_gettext.so"

    _build_force_gettext 2>/dev/null || true
    assert_ui_contains "WARN"
    cleanup_sandbox "$sb"
}
it "force_gettext.c 누락 시 경고를 출력한다" _test_force_gettext_warns_if_src_missing

_test_force_gettext_warns_if_clang_fails() {
    local sb; sb=$(make_sandbox)
    _load_domain "$sb"
    reset_ui_output

    export SCRIPT_DIR="${sb}/repo"
    local src_dir="${SCRIPT_DIR}/assets"
    mkdir -p "$src_dir"
    touch "${src_dir}/force_gettext.c"
    rm -f "${PREFIX}/lib/force_gettext.so"

    # clang이 컴파일 실패를 시뮬레이션
    clang() { _record_call "clang $*"; return 1; }
    command() {
        if [ "${1:-}" = "-v" ] && [ "${2:-}" = "clang" ]; then
            return 0
        fi
        builtin command "$@"
    }

    local rc=0
    _build_force_gettext 2>/dev/null || rc=$?

    assert_zero "$rc" "clang 실패해도 set -e 트립 없이 rc 0"
    assert_ui_contains "WARN"

    unset -f command
    cleanup_sandbox "$sb"
}
it "clang 빌드 실패 시 경고 후 건너뛴다 (set -e 트립 방지)" _test_force_gettext_warns_if_clang_fails

# =============================================================================
# _install_startxfce4_ko_wrapper — 래퍼 스크립트 생성
# =============================================================================

describe "locale_ko — _install_startxfce4_ko_wrapper"

_test_ko_wrapper_created() {
    local sb; sb=$(make_sandbox)
    _load_domain "$sb"

    _install_startxfce4_ko_wrapper 2>/dev/null || true

    local wrapper="${HOME}/bin/startxfce4-ko"
    assert_file_exists "$wrapper"
    [ -x "$wrapper" ]
    cleanup_sandbox "$sb"
}
it "startxfce4-ko 래퍼를 생성하고 실행 권한을 부여한다" _test_ko_wrapper_created

_test_ko_wrapper_sets_lang() {
    local sb; sb=$(make_sandbox)
    _load_domain "$sb"

    _install_startxfce4_ko_wrapper 2>/dev/null || true

    local wrapper="${HOME}/bin/startxfce4-ko"
    assert_file_contains "$wrapper" 'LANG="ko_KR.UTF-8"'
    assert_file_contains "$wrapper" 'LANGUAGE="ko_KR:ko:en_US:en"'
    cleanup_sandbox "$sb"
}
it "LANG/LANGUAGE를 한국어로 설정한다" _test_ko_wrapper_sets_lang

_test_ko_wrapper_has_ld_preload() {
    local sb; sb=$(make_sandbox)
    _load_domain "$sb"

    _install_startxfce4_ko_wrapper 2>/dev/null || true

    local wrapper="${HOME}/bin/startxfce4-ko"
    assert_file_contains "$wrapper" "force_gettext.so"
    assert_file_contains "$wrapper" "LD_PRELOAD"
    cleanup_sandbox "$sb"
}
it "LD_PRELOAD에 force_gettext.so를 포함한다" _test_ko_wrapper_has_ld_preload

_test_ko_wrapper_execs_startxfce4() {
    local sb; sb=$(make_sandbox)
    _load_domain "$sb"

    _install_startxfce4_ko_wrapper 2>/dev/null || true

    local wrapper="${HOME}/bin/startxfce4-ko"
    assert_file_contains "$wrapper" "exec startxfce4"
    cleanup_sandbox "$sb"
}
it "exec startxfce4로 XFCE를 실행한다" _test_ko_wrapper_execs_startxfce4

_test_ko_wrapper_idempotent() {
    local sb; sb=$(make_sandbox)
    _load_domain "$sb"

    _install_startxfce4_ko_wrapper 2>/dev/null || true
    local mtime1; mtime1=$(stat -c %Y "${HOME}/bin/startxfce4-ko")
    sleep 1
    _install_startxfce4_ko_wrapper 2>/dev/null || true
    local mtime2; mtime2=$(stat -c %Y "${HOME}/bin/startxfce4-ko")

    assert_eq "$mtime1" "$mtime2" "멱등성: 이미 있으면 덮어쓰지 않는다"
    cleanup_sandbox "$sb"
}
it "멱등성 — startxfce4-ko가 이미 있으면 덮어쓰지 않는다" _test_ko_wrapper_idempotent

_test_ko_wrapper_has_fallback_domains() {
    local sb; sb=$(make_sandbox)
    _load_domain "$sb"

    _install_startxfce4_ko_wrapper 2>/dev/null || true

    local wrapper="${HOME}/bin/startxfce4-ko"
    assert_file_contains "$wrapper" "FALLBACK_DOMAINS"
    assert_file_contains "$wrapper" "mousepad"
    assert_file_contains "$wrapper" "thunar"
    cleanup_sandbox "$sb"
}
it "FALLBACK_DOMAINS에 XFCE/GTK 앱 도메인 목록이 있다" _test_ko_wrapper_has_fallback_domains

_test_ko_wrapper_syntax_valid() {
    local sb; sb=$(make_sandbox)
    _load_domain "$sb"

    _install_startxfce4_ko_wrapper 2>/dev/null || true
    bash -n "${HOME}/bin/startxfce4-ko"
    cleanup_sandbox "$sb"
}
it "startxfce4-ko의 bash 문법 오류가 없다" _test_ko_wrapper_syntax_valid

# =============================================================================
# setup_korean_rc — RC 파일에 한글 환경변수 영구 등록
# =============================================================================

describe "locale_ko — setup_korean_rc"

_test_korean_rc_writes_to_bashrc() {
    local sb; sb=$(make_sandbox)
    _load_domain "$sb"

    setup_korean_rc 2>/dev/null || true

    assert_file_contains "${PREFIX}/etc/bash.bashrc" "termux-xfce-korean"
    assert_file_contains "${PREFIX}/etc/bash.bashrc" "FALLBACK_DOMAINS"
    cleanup_sandbox "$sb"
}
it "bash.bashrc에 한글 환경변수 블록을 추가한다" _test_korean_rc_writes_to_bashrc

_test_korean_rc_has_lang() {
    local sb; sb=$(make_sandbox)
    _load_domain "$sb"

    setup_korean_rc 2>/dev/null || true

    assert_file_contains "${PREFIX}/etc/bash.bashrc" 'LANG="ko_KR.UTF-8"'
    cleanup_sandbox "$sb"
}
it "LANG=ko_KR.UTF-8을 설정한다" _test_korean_rc_has_lang

_test_korean_rc_has_ld_preload_guard() {
    local sb; sb=$(make_sandbox)
    _load_domain "$sb"

    setup_korean_rc 2>/dev/null || true

    assert_file_contains "${PREFIX}/etc/bash.bashrc" "force_gettext.so"
    assert_file_contains "${PREFIX}/etc/bash.bashrc" "LD_PRELOAD"
    cleanup_sandbox "$sb"
}
it "LD_PRELOAD에 force_gettext.so 중복 방지 guard가 있다" _test_korean_rc_has_ld_preload_guard

_test_korean_rc_uses_shared_constant() {
    local sb; sb=$(make_sandbox)
    _load_domain "$sb"

    setup_korean_rc 2>/dev/null || true

    assert_file_contains "${PREFIX}/etc/bash.bashrc" "mousepad"
    assert_file_contains "${PREFIX}/etc/bash.bashrc" "thunar"
    assert_file_contains "${PREFIX}/etc/bash.bashrc" "kcolorscheme6"
    cleanup_sandbox "$sb"
}
it "FALLBACK_DOMAINS에 공유 상수의 도메인 목록이 포함된다" _test_korean_rc_uses_shared_constant

_test_korean_rc_idempotent() {
    local sb; sb=$(make_sandbox)
    _load_domain "$sb"

    setup_korean_rc 2>/dev/null || true
    setup_korean_rc 2>/dev/null || true

    local count
    count=$(grep -c "termux-xfce-korean" "${PREFIX}/etc/bash.bashrc")
    assert_eq "1" "$count" "멱등성: 마커가 1번만 있어야 한다"
    cleanup_sandbox "$sb"
}
it "멱등성 — 두 번 호출해도 블록이 중복되지 않는다" _test_korean_rc_idempotent

_test_korean_rc_conditional_on_so() {
    local sb; sb=$(make_sandbox)
    _load_domain "$sb"

    setup_korean_rc 2>/dev/null || true

    assert_file_contains "${PREFIX}/etc/bash.bashrc" 'if \[ -f "\$PREFIX/lib/force_gettext.so" \]'
    cleanup_sandbox "$sb"
}
it "force_gettext.so 존재 여부를 조건으로 감싼다" _test_korean_rc_conditional_on_so

# =============================================================================
# _install_dbus_propagate_autostart — desktop 파일 생성
# =============================================================================

describe "locale_ko — _install_dbus_propagate_autostart"

_test_dbus_propagate_created() {
    local sb; sb=$(make_sandbox)
    _load_domain "$sb"

    _install_dbus_propagate_autostart 2>/dev/null || true

    local dest="${HOME}/.config/autostart/00-env-dbus-propagate.desktop"
    assert_file_exists "$dest"
    assert_file_contains "$dest" "[Desktop Entry]"
    assert_file_contains "$dest" "dbus-update-activation-environment"
    cleanup_sandbox "$sb"
}
it "dbus propagate autostart desktop 파일을 생성한다" _test_dbus_propagate_created

_test_dbus_propagate_no_usr_bin_env() {
    local sb; sb=$(make_sandbox)
    _load_domain "$sb"

    _install_dbus_propagate_autostart 2>/dev/null || true

    local dest="${HOME}/.config/autostart/00-env-dbus-propagate.desktop"
    assert_file_not_contains "$dest" "/usr/bin/env"
    cleanup_sandbox "$sb"
}
it "Exec에 /usr/bin/env 경로가 없다 (Termux 호환)" _test_dbus_propagate_no_usr_bin_env

_test_dbus_propagate_idempotent() {
    local sb; sb=$(make_sandbox)
    _load_domain "$sb"

    _install_dbus_propagate_autostart 2>/dev/null || true
    local mtime1; mtime1=$(stat -c %Y "${HOME}/.config/autostart/00-env-dbus-propagate.desktop")
    sleep 1
    _install_dbus_propagate_autostart 2>/dev/null || true
    local mtime2; mtime2=$(stat -c %Y "${HOME}/.config/autostart/00-env-dbus-propagate.desktop")

    assert_eq "$mtime1" "$mtime2" "멱등성"
    cleanup_sandbox "$sb"
}
it "멱등성 — desktop 파일이 이미 있으면 덮어쓰지 않는다" _test_dbus_propagate_idempotent

print_results
