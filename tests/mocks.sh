#!/data/data/com.termux/files/usr/bin/bash
# =============================================================================
# MOCKS — 어댑터 의존성을 테스트용 스텁으로 교체
# =============================================================================

# 호출 기록 (스파이 패턴)
MOCK_CALLS=()

_record_call() {
    MOCK_CALLS+=("$*")
}

reset_mock_calls() {
    MOCK_CALLS=()
}

assert_was_called() {
    local expected="$1"
    for call in "${MOCK_CALLS[@]:-}"; do
        if [[ "$call" == *"$expected"* ]]; then
            return 0
        fi
    done
    echo "[ASSERT] expected call containing '${expected}' but not found in: ${MOCK_CALLS[*]:-<none>}" >&2
    return 1
}

assert_not_called() {
    local unexpected="$1"
    for call in "${MOCK_CALLS[@]:-}"; do
        if [[ "$call" == *"$unexpected"* ]]; then
            echo "[ASSERT] unexpected call found: ${call}" >&2
            return 1
        fi
    done
    return 0
}

# =============================================================================
# Mock: pkg_manager 어댑터
# =============================================================================

# 설치된 것으로 취급할 패키지 목록 (공백 구분)
MOCK_INSTALLED_PKGS=""

mock_pkg_adapter() {
    pkg_update()          { _record_call "pkg_update"; }
    pkg_upgrade()         { _record_call "pkg_upgrade"; }
    pkg_install()         { _record_call "pkg_install $*"; }
    pkg_remove()          { _record_call "pkg_remove $*"; }
    pkg_autoremove()      { _record_call "pkg_autoremove"; }
    pkg_is_installed() {
        local pkg="$1"
        echo "$MOCK_INSTALLED_PKGS" | grep -qw "$pkg"
    }
    # NOTE: 옛 구현(`shift; bash -c "$*"`)은 첫 인자(보통 "bash")를 떨어뜨린 뒤
    # 잔여 `-c "..."` 를 다시 `bash -c "..."` 로 감싸 invalid option 에러로 침묵 종료했다.
    # 글로벌 mock은 호출 기록만 남기고 inner 명령은 실행하지 않는다.
    # inner 명령의 side-effect 검증이 필요한 테스트는 자체 proot_exec 재정의 사용.
    proot_exec()          { _record_call "proot_exec $*"; return 0; }
    proot_exec_root()     { _record_call "proot_exec_root $*"; return 0; }
    proot_install()       { _record_call "proot-distro install $*"; }
    proot_remove()        { _record_call "proot_remove $*"; }
    proot_pkg_install()   { _record_call "proot_pkg_install $*"; }
    proot_pkg_install_root() { _record_call "proot_pkg_install_root $*"; }
    proot_pkg_update()    { _record_call "proot_pkg_update"; }
    proot_pkg_update_root() { _record_call "proot_pkg_update_root"; }
    proot_pkg_remove()    { _record_call "proot_pkg_remove $*"; }
    proot_pkg_autoremove() { _record_call "proot_pkg_autoremove"; }
    proot_pkg_is_installed() { return 1; }  # 기본: 미설치
    # 비표준 설치 포트 (URL .deb / AUR) — 도메인은 HOW를 모르고 이 포트만 호출
    proot_pkg_install_deb_url() { _record_call "proot_pkg_install_deb_url $*"; }
    proot_aur_install()   { _record_call "proot_aur_install $*"; }
    proot_ensure_aur_helper() { _record_call "proot_ensure_aur_helper"; return 0; }  # 기본: yay 사용 가능
    pkg_install_deb_url() { _record_call "pkg_install_deb_url $*"; return 0; }
}

# =============================================================================
# Mock: ui 어댑터 (출력 캡처용)
# =============================================================================

UI_OUTPUT=()

mock_ui_adapter() {
    ui_info()    { UI_OUTPUT+=("INFO: $*"); }
    ui_warn()    { UI_OUTPUT+=("WARN: $*"); }
    ui_error()   { UI_OUTPUT+=("ERROR: $*"); >&2 echo "ERROR: $*"; }
    ui_select()  { echo "${@: -1}"; }   # 마지막 옵션 반환
    ui_confirm() { return 0; }          # 항상 Yes
    ui_input()   {
        local prompt="$1" default="${2:-}"
        echo "${default}"
    }
}

reset_ui_output() {
    UI_OUTPUT=()
}

assert_ui_contains() {
    local pattern="$1"
    for msg in "${UI_OUTPUT[@]:-}"; do
        if [[ "$msg" == *"$pattern"* ]]; then
            return 0
        fi
    done
    echo "[ASSERT] ui output does not contain '${pattern}'" >&2
    echo "[ASSERT] actual ui output: ${UI_OUTPUT[*]:-<none>}" >&2
    return 1
}

# =============================================================================
# Mock: wget (네트워크 없이 빈 파일 생성)
# =============================================================================

mock_wget() {
    wget() {
        _record_call "wget $*"
        # -O <path> 에서 경로 추출해 빈 파일 생성
        local out_path=""
        local args=("$@")
        for (( i=0; i<${#args[@]}; i++ )); do
            if [[ "${args[$i]}" == "-O" ]]; then
                out_path="${args[$((i+1))]}"
                break
            fi
        done
        [ -n "$out_path" ] && printf 'PKmock\n' > "$out_path"
        return 0
    }
}

# =============================================================================
# Filesystem 샌드박스 — HOME, PREFIX 등을 임시 디렉토리로 교체
# =============================================================================

setup_fs_sandbox() {
    local sandbox="$1"
    export HOME="${sandbox}/home"
    export PREFIX="${sandbox}/usr"
    mkdir -p \
        "${HOME}/.termux" \
        "${HOME}/.config/termux-xfce" \
        "${HOME}/.config/autostart" \
        "${HOME}/.shortcuts" \
        "${HOME}/.fonts" \
        "${HOME}/Desktop" \
        "${PREFIX}/etc/apt/sources.list.d" \
        "${PREFIX}/bin" \
        "${PREFIX}/lib" \
        "${PREFIX}/share/applications" \
        "${PREFIX}/share/themes" \
        "${PREFIX}/share/icons" \
        "${PREFIX}/share/backgrounds/xfce" \
        "${PREFIX}/var/lib/proot-distro/installed-rootfs"

    # termux.properties stub
    cat > "${HOME}/.termux/termux.properties" << 'EOF'
# allow-external-apps = true
# bell-character = ignore
EOF

    # termux-xfce config stub (실제 운영 환경과 동일한 구조)
    cat > "${HOME}/.config/termux-xfce/config" << 'EOF'
PROOT_DISTRO="archlinux"
PROOT_USER="testuser"
INSTALL_ARCH="aarch64"
EOF

    # bash.bashrc stub
    touch "${PREFIX}/etc/bash.bashrc"

    # tur.list stub — production에선 tur-repo 설치 시 생성됨 (mock_pkg_adapter는 미생성)
    cat > "${PREFIX}/etc/apt/sources.list.d/tur.list" << 'EOF'
deb https://termux.dev/tur stable main
EOF
}
