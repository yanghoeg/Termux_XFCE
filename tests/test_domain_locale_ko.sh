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
    clang() {
        _record_call "clang $*"
        while [ "$#" -gt 0 ]; do
            if [ "$1" = -o ]; then printf 'shared library\n' > "$2"; return; fi
            shift
        done
        return 1
    }
    unzip() {
        _record_call "unzip $*"
        local dest=""
        while [ "$#" -gt 0 ]; do
            if [ "$1" = -d ]; then dest="$2"; break; fi
            shift
        done
        mkdir -p "$dest/ko/LC_MESSAGES"
        printf 'catalog\n' > "$dest/ko/LC_MESSAGES/gtk30.mo"
    }
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

    local rc=0
    setup_korean_locale_native 2>/dev/null || rc=$?
    assert_nonzero "$rc"
    assert_ui_contains "ERROR"
    cleanup_sandbox "$sb"
}
it "KOREAN_LOCALE_ZIP 미설정 시 실패를 반환한다" _test_locale_native_skips_without_zip

_test_locale_native_skips_invalid_path() {
    local sb; sb=$(make_sandbox)
    _load_domain "$sb"
    export KOREAN_LOCALE_ZIP="/nonexistent/locale.zip"
    reset_ui_output

    local rc=0
    setup_korean_locale_native 2>/dev/null || rc=$?
    assert_nonzero "$rc"
    assert_ui_contains "ERROR"
    cleanup_sandbox "$sb"
}
it "KOREAN_LOCALE_ZIP 파일 미존재 시 실패를 반환한다" _test_locale_native_skips_invalid_path

_test_locale_native_runs_all_steps() {
    local sb; sb=$(make_sandbox)
    _load_domain "$sb"

    # 유효한 zip 파일 stub 생성
    local zip_path="${sb}/locale.zip"
    touch "$zip_path"
    export KOREAN_LOCALE_ZIP="$zip_path"
    reset_mock_calls
    reset_ui_output

    setup_korean_locale_native

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

    assert_nonzero "$rc" "unzip 실패를 호출자에 전파"
    assert_file_exists "${dest}/marker.txt"
    ! compgen -G "${dest}.bak."* > /dev/null 2>&1
    cleanup_sandbox "$sb"
}
it "unzip 실패 시 기존 locale 보존 + .bak 생성 안 함" _test_deploy_catalogs_unzip_failure_preserves_original

_test_deploy_catalogs_missing_catalog_preserves_original() {
    local sb; sb=$(make_sandbox); _load_domain "$sb"
    unzip() { return 0; }
    mkdir -p "$PREFIX/share/locale"
    touch "$PREFIX/share/locale/marker.txt"
    if _deploy_locale_catalogs "$sb/unrelated.zip"; then return 1; fi
    assert_file_exists "$PREFIX/share/locale/marker.txt"
    cleanup_sandbox "$sb"
}
it "한글 카탈로그가 없는 ZIP은 거부하고 기존 locale을 보존한다" _test_deploy_catalogs_missing_catalog_preserves_original

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


_locale_original_fixture() {
    mkdir -p "$PREFIX/share/locale/en/LC_MESSAGES"
    printf 'original English catalog\n' > "$PREFIX/share/locale/en/LC_MESSAGES/existing.mo"
    printf 'original marker\n' > "$PREFIX/share/locale/marker.txt"
}
_assert_locale_transaction_clean() {
    [ -z "$(find "$PREFIX/share" -maxdepth 1 \( -name 'locale.stage.*' -o -name 'locale.previous.*' \) -print)" ]
}
_test_deploy_catalogs_preserves_existing_catalogs() {
    local sb; sb=$(make_sandbox); _load_domain "$sb"
    _locale_original_fixture
    chmod 750 "$PREFIX/share/locale"
    _deploy_locale_catalogs "$sb/locale.zip"
    assert_eq 'original English catalog' "$(cat "$PREFIX/share/locale/en/LC_MESSAGES/existing.mo")"
    assert_file_exists "$PREFIX/share/locale/ko/LC_MESSAGES/gtk30.mo"
    assert_eq 750 "$(stat -c %a "$PREFIX/share/locale")"
    compgen -G "$PREFIX/share/locale.bak.*/marker.txt" >/dev/null
    _assert_locale_transaction_clean
    cleanup_sandbox "$sb"
}
it "첫 한글 배치는 기존 언어와 권한을 보존하고 원본 백업을 남긴다" _test_deploy_catalogs_preserves_existing_catalogs

_test_deploy_catalogs_copy_failure_preserves_original() {
    local sb; sb=$(make_sandbox); _load_domain "$sb"
    _locale_original_fixture
    cp() {
        case "$2" in
            */locale_ko.*/*)
                command cp "$@" || return 1
                return 1 ;;
        esac
        command cp "$@"
    }
    if _deploy_locale_catalogs "$sb/locale.zip"; then return 1; fi
    assert_eq 'original English catalog' "$(cat "$PREFIX/share/locale/en/LC_MESSAGES/existing.mo")"
    assert_eq 'original marker' "$(cat "$PREFIX/share/locale/marker.txt")"
    [ ! -e "$PREFIX/share/locale/ko/LC_MESSAGES/gtk30.mo" ]
    ! compgen -G "$PREFIX/share/locale.bak.*" >/dev/null
    _assert_locale_transaction_clean
    cleanup_sandbox "$sb"
}
it "부분 복사 실패는 활성 카탈로그를 바꾸거나 백업으로 옮기지 않는다" _test_deploy_catalogs_copy_failure_preserves_original

_locale_commit_failure_case() {
    local existing_backup="$1" sb
    sb=$(make_sandbox); _load_domain "$sb"
    _locale_original_fixture
    if [ "$existing_backup" = true ]; then
        mkdir -p "$PREFIX/share/locale.bak.saved"
        printf 'saved backup\n' > "$PREFIX/share/locale.bak.saved/marker.txt"
    fi
    mv() {
        case "$2" in *.stage.*) return 1 ;; esac
        command mv "$@"
    }
    if _deploy_locale_catalogs "$sb/locale.zip"; then return 1; fi
    assert_eq 'original English catalog' "$(cat "$PREFIX/share/locale/en/LC_MESSAGES/existing.mo")"
    assert_eq 'original marker' "$(cat "$PREFIX/share/locale/marker.txt")"
    [ ! -e "$PREFIX/share/locale/ko/LC_MESSAGES/gtk30.mo" ]
    if [ "$existing_backup" = true ]; then
        assert_eq 'saved backup' "$(cat "$PREFIX/share/locale.bak.saved/marker.txt")"
        assert_eq 1 "$(find "$PREFIX/share" -maxdepth 1 -name 'locale.bak.*' | wc -l | tr -d ' ')"
    else
        ! compgen -G "$PREFIX/share/locale.bak.*" >/dev/null
    fi
    _assert_locale_transaction_clean
    cleanup_sandbox "$sb"
}
_test_deploy_catalogs_commit_failure_restores_original() { _locale_commit_failure_case false; }
_test_deploy_catalogs_commit_failure_keeps_backup() { _locale_commit_failure_case true; }
it "최종 rename 실패는 기존 카탈로그를 원래 위치로 복원한다" _test_deploy_catalogs_commit_failure_restores_original
it "재배치 rename 실패는 활성 카탈로그와 이전 영구 백업을 모두 보존한다" _test_deploy_catalogs_commit_failure_keeps_backup

_test_deploy_catalogs_backup_move_failure_preserves_original() {
    local sb; sb=$(make_sandbox); _load_domain "$sb"
    _locale_original_fixture
    mv() { return 1; }
    if _deploy_locale_catalogs "$sb/locale.zip"; then return 1; fi
    assert_eq 'original English catalog' "$(cat "$PREFIX/share/locale/en/LC_MESSAGES/existing.mo")"
    assert_eq 'original marker' "$(cat "$PREFIX/share/locale/marker.txt")"
    ! compgen -G "$PREFIX/share/locale.bak.*" >/dev/null
    _assert_locale_transaction_clean
    cleanup_sandbox "$sb"
}
it "기존 카탈로그 rename 실패는 원본과 활성 경로를 그대로 보존한다" _test_deploy_catalogs_backup_move_failure_preserves_original

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

    _build_force_gettext
    assert_was_called "clang -shared"
    [ -s "${PREFIX}/lib/force_gettext.so" ]
    cleanup_sandbox "$sb"
}
it "clang -shared로 force_gettext.so를 빌드한다" _test_force_gettext_builds_so

_test_force_gettext_idempotent() {
    local sb; sb=$(make_sandbox)
    _load_domain "$sb"
    _build_force_gettext
    reset_mock_calls
    _build_force_gettext
    assert_not_called "clang"
    cleanup_sandbox "$sb"
}
it "멱등성 — 같은 소스로 빌드된 force_gettext.so는 재빌드하지 않는다" _test_force_gettext_idempotent

_test_force_gettext_warns_if_src_missing() {
    local sb; sb=$(make_sandbox)
    _load_domain "$sb"
    reset_ui_output

    # force_gettext.c 없음 + .so도 없음
    # SCRIPT_DIR을 샌드박스로 덮어 assets/force_gettext.c가 없는 상태로 만든다
    export SCRIPT_DIR="$sb"
    rm -f "${PREFIX}/lib/force_gettext.so"

    local rc=0
    _build_force_gettext 2>/dev/null || rc=$?
    assert_nonzero "$rc"
    assert_ui_contains "ERROR"
    cleanup_sandbox "$sb"
}
it "force_gettext.c 누락 시 오류를 반환한다" _test_force_gettext_warns_if_src_missing

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

    assert_nonzero "$rc" "clang 실패를 호출자에 전파"
    assert_ui_contains "ERROR"
    [ ! -e "${PREFIX}/lib/force_gettext.so" ]

    unset -f command
    cleanup_sandbox "$sb"
}
it "clang 빌드 실패 시 오류를 반환하고 불완전한 .so를 남기지 않는다" _test_force_gettext_warns_if_clang_fails

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

_test_ko_wrapper_forwards_session() {
    local sb; sb=$(make_sandbox)
    _load_domain "$sb"
    mkdir -p "$HOME/bin"
    printf 'exec startxfce4\n' > "$HOME/bin/startxfce4-ko"
    _install_startxfce4_ko_wrapper
    printf '#!/bin/sh\nprintf "%%s\\n" "$@"\n' > "$PREFIX/bin/startXFCE"
    chmod +x "$PREFIX/bin/startXFCE"
    export PATH="$PREFIX/bin:$PATH"
    local output
    output=$(bash "$HOME/bin/startxfce4-ko" 'argument with spaces')
    assert_eq 'argument with spaces' "$output"
    assert_file_not_contains "$HOME/bin/startxfce4-ko" LD_PRELOAD
    bash -n "$HOME/bin/startxfce4-ko"
    cleanup_sandbox "$sb"
}
it "the old locale command forwards arguments to the managed session launcher" _test_ko_wrapper_forwards_session

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
