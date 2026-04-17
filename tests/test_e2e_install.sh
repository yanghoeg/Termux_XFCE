#!/data/data/com.termux/files/usr/bin/bash
# =============================================================================
# TEST: E2E 설치 시나리오 — composition 및 최종 상태 검증
# -----------------------------------------------------------------------------
# 개별 함수 테스트가 통과해도 composition/순서 버그나 외부 도구와의 상호작용
# 버그는 잡히지 않는다. 이 스위트는 사용자 보고 regression을 최종 상태 기준으로
# 검증한다.
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/framework.sh"
source "${SCRIPT_DIR}/mocks.sh"

DOMAIN_DIR="${SCRIPT_DIR}/../domain"
REPO_ROOT="${SCRIPT_DIR}/.."

# setup_termux_base가 호출하는 외부 도구를 stub으로 대체
_stub_external_tools() {
    # zsh 존재하는 것처럼 위장
    touch "${PREFIX}/bin/zsh"
    chmod +x "${PREFIX}/bin/zsh"

    # command -v zsh → 우리가 만든 stub 경로 반환
    # (bash builtin command를 override)
    command() {
        if [ "${1:-}" = "-v" ] && [ "${2:-}" = "zsh" ]; then
            echo "${PREFIX}/bin/zsh"
            return 0
        fi
        builtin command "$@"
    }
    export -f command

    # git clone 실제 네트워크 안 타게 stub
    git() {
        if [ "${1:-}" = "clone" ]; then
            local target="${!#}"   # 마지막 인자
            mkdir -p "$target"
            return 0
        fi
        return 0
    }
    export -f git

    # chsh / termux-wake-lock stub
    chsh() { return 0; }
    export -f chsh
}

_load_domain() {
    local sandbox="$1"
    setup_fs_sandbox "$sandbox"
    mock_pkg_adapter
    mock_ui_adapter
    mock_wget
    _stub_external_tools
    source "${DOMAIN_DIR}/packages.sh"
    source "${DOMAIN_DIR}/termux_env.sh"
}

# =============================================================================
# Regression #1: alias 순서 버그
# -----------------------------------------------------------------------------
# Issue #2 — Clean install 시 ~/.zshrc에 zink/hud alias 누락
# 원인: _setup_aliases가 _setup_zsh_p10k보다 먼저 호출되던 경우
#      _rc_targets()가 .zshrc 미존재로 bash.bashrc만 선택
# =============================================================================

describe "e2e — setup_termux_base 후 .zshrc 상태 (issue #2 regression)"

_test_zshrc_has_alias_block_after_composition() {
    local sb; sb=$(make_sandbox)
    _load_domain "$sb"

    # 개별 함수가 아닌 setup_termux_base 전체를 실행
    setup_termux_base

    assert_file_exists "${HOME}/.zshrc"
    assert_file_contains "${HOME}/.zshrc" "termux-xfce-aliases"
    assert_file_contains "${HOME}/.zshrc" "alias zink="
    assert_file_contains "${HOME}/.zshrc" "alias hud="
    assert_file_contains "${HOME}/.zshrc" "alias zrunhud="

    cleanup_sandbox "$sb"
}
it "clean install composition — .zshrc에 zink/hud alias가 존재한다" _test_zshrc_has_alias_block_after_composition

_test_zshrc_has_locale_block_after_composition() {
    local sb; sb=$(make_sandbox)
    _load_domain "$sb"

    setup_termux_base

    assert_file_contains "${HOME}/.zshrc" "termux-xfce-locale"
    assert_file_contains "${HOME}/.zshrc" "XMODIFIERS=@im=fcitx5"

    cleanup_sandbox "$sb"
}
it "clean install composition — .zshrc에 locale 블록이 존재한다" _test_zshrc_has_locale_block_after_composition

_test_zshrc_has_xdg_runtime_block_after_composition() {
    local sb; sb=$(make_sandbox)
    _load_domain "$sb"

    setup_termux_base

    assert_file_contains "${HOME}/.zshrc" "termux-xfce-xdg-runtime"
    assert_file_contains "${HOME}/.zshrc" "XDG_RUNTIME_DIR"

    cleanup_sandbox "$sb"
}
it "clean install composition — .zshrc에 XDG_RUNTIME_DIR 블록이 존재한다" _test_zshrc_has_xdg_runtime_block_after_composition

_test_zshrc_has_gpu_block_after_composition() {
    local sb; sb=$(make_sandbox)
    _load_domain "$sb"

    setup_termux_base

    assert_file_contains "${HOME}/.zshrc" "termux-xfce-gpu"

    cleanup_sandbox "$sb"
}
it "clean install composition — .zshrc에 GPU 블록이 존재한다" _test_zshrc_has_gpu_block_after_composition

_test_bashrc_still_has_aliases() {
    # 양쪽 RC 모두 반영되어야 함 (기본 쉘이 zsh가 아닐 때를 대비)
    local sb; sb=$(make_sandbox)
    _load_domain "$sb"

    setup_termux_base

    assert_file_contains "${PREFIX}/etc/bash.bashrc" "termux-xfce-aliases"
    assert_file_contains "${PREFIX}/etc/bash.bashrc" "alias zink="

    cleanup_sandbox "$sb"
}
it "clean install composition — bash.bashrc에도 alias가 존재한다" _test_bashrc_still_has_aliases

# =============================================================================
# Regression #2: startXFCE pgrep -c integer expected
# -----------------------------------------------------------------------------
# Issue #2 — `[: 0 0: integer expected`
# 원인: pgrep -c는 매치 없을 때 "0\n" 출력 + exit 1
#      "|| echo 0" 체이닝이 뒤에 "0"을 또 찍어 "0\n0" (두 줄) 생성
# =============================================================================

describe "e2e — startXFCE DBUS_COUNT 산술 안전성 (issue #2 regression)"

_test_startxfce_no_pgrep_c_or_echo_pattern() {
    # 정적 검사: 과거 버그 패턴이 재도입되지 않았는지
    local sb; sb=$(make_sandbox)
    _load_domain "$sb"

    _setup_start_xfce
    local script="${HOME}/.shortcuts/startXFCE"
    assert_file_exists "$script"

    # 버그 패턴: pgrep -c 의 exit 1을 || echo 0으로 흡수 → 출력 두 줄
    if grep -E 'pgrep -c [^|]*\|\| *echo 0' "$script" >/dev/null; then
        echo "[ASSERT] startXFCE에 금지된 'pgrep -c ... || echo 0' 패턴 재도입됨" >&2
        grep -n "pgrep -c" "$script" >&2
        return 1
    fi

    cleanup_sandbox "$sb"
}
it "startXFCE에 'pgrep -c ... || echo 0' 버그 패턴이 없다" _test_startxfce_no_pgrep_c_or_echo_pattern

_test_startxfce_dbus_count_is_integer_safe() {
    # 기능 검사: DBUS_COUNT 계산 라인을 실제로 실행하고
    # -gt 비교가 integer expected 오류를 내지 않는지 확인
    local sb; sb=$(make_sandbox)
    _load_domain "$sb"

    _setup_start_xfce
    local script="${HOME}/.shortcuts/startXFCE"

    # DBUS_COUNT 계산 + [ -gt ] 분기를 추출해서 실행
    # pgrep dbus-daemon → 존재하지 않는 프로세스명으로 치환 (매치 0건 재현)
    local tmp="${sb}/dbus_count_test.sh"
    {
        echo 'set -uo pipefail'
        grep "DBUS_COUNT=" "$script" | head -1 | sed 's/pgrep dbus-daemon/pgrep __definitely_not_a_process__/'
        echo 'if [ "${DBUS_COUNT:-0}" -gt 1 ]; then echo branch_gt; else echo branch_ok; fi'
    } > "$tmp"

    local result
    result=$(bash "$tmp" 2>&1)
    assert_output_contains "$result" "branch_ok"

    if echo "$result" | grep -q "integer expected"; then
        echo "[ASSERT] DBUS_COUNT이 'integer expected' 오류 유발" >&2
        echo "[ASSERT] 실제 출력: $result" >&2
        return 1
    fi

    cleanup_sandbox "$sb"
}
it "DBUS_COUNT 계산이 매치 0건에서도 integer 비교 안전하다" _test_startxfce_dbus_count_is_integer_safe

_test_startxfce_bash_syntax_valid() {
    local sb; sb=$(make_sandbox)
    _load_domain "$sb"

    _setup_start_xfce
    local script="${HOME}/.shortcuts/startXFCE"

    bash -n "$script"

    cleanup_sandbox "$sb"
}
it "startXFCE 스크립트의 bash 문법 오류가 없다" _test_startxfce_bash_syntax_valid

# =============================================================================
# Regression #3: xfce4-terminal.xml 프리셋
# -----------------------------------------------------------------------------
# Issue #2 — "Your Terminal settings have been migrated to Xfconf..." 메시지
# 원인: xfconf 채널이 비어 있으면 xfce4-terminal이 terminalrc를 xfconf로
#      이관하며 메시지 출력. 프리셋 xml로 이관 자체를 우회
# =============================================================================

describe "e2e — xfce4-terminal.xml 프리셋 (issue #2 regression)"

_test_xfce4_terminal_xml_preset_present() {
    local xml="${REPO_ROOT}/tar/config/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-terminal.xml"
    assert_file_exists "$xml"
}
it "tar/config에 xfce4-terminal.xml 프리셋이 존재한다" _test_xfce4_terminal_xml_preset_present

_test_xfce4_terminal_xml_has_channel_header() {
    local xml="${REPO_ROOT}/tar/config/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-terminal.xml"
    assert_file_contains "$xml" '<channel name="xfce4-terminal"'
}
it "xml 최상위 channel 이름이 xfce4-terminal이다" _test_xfce4_terminal_xml_has_channel_header

_test_xfce4_terminal_xml_has_font_name() {
    # font-name이 MesloLGS Nerd Font Mono로 설정되어 있어야 p10k 아이콘 렌더링
    local xml="${REPO_ROOT}/tar/config/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-terminal.xml"
    assert_file_contains "$xml" 'name="font-name"'
    assert_file_contains "$xml" 'MesloLGS Nerd Font Mono'
}
it "xml에 MesloLGS Nerd Font Mono 폰트가 설정되어 있다" _test_xfce4_terminal_xml_has_font_name

_test_xfce4_terminal_xml_has_enough_properties() {
    # 최소 1개 property만 있어도 마이그레이션 트리거를 우회 가능.
    # 하지만 terminalrc의 설정을 모두 계승해야 동등성 유지.
    # → 최소 30개 이상 (현재 35개)
    local xml="${REPO_ROOT}/tar/config/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-terminal.xml"
    local count
    count=$(grep -c '<property ' "$xml")
    if [ "$count" -lt 30 ]; then
        echo "[ASSERT] xml에 property가 ${count}개뿐 — 최소 30개 기대 (terminalrc 동등성)" >&2
        return 1
    fi
}
it "xml에 terminalrc 동등 설정이 모두 포함되어 있다 (≥30 property)" _test_xfce4_terminal_xml_has_enough_properties

_test_xfce4_terminal_xml_is_valid_xml() {
    local xml="${REPO_ROOT}/tar/config/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-terminal.xml"
    # xmllint가 있으면 사용, 없으면 간단한 태그 매칭 검사
    if command -v xmllint >/dev/null 2>&1; then
        xmllint --noout "$xml"
    else
        # 최소한: <channel>과 </channel> 매칭
        grep -q '<channel ' "$xml" && grep -q '</channel>' "$xml"
    fi
}
it "xml이 well-formed XML이다" _test_xfce4_terminal_xml_is_valid_xml

# =============================================================================
# 구조 regression: setup_termux_base 호출 순서
# -----------------------------------------------------------------------------
# _rc_targets()가 .zshrc 존재 여부로 분기하므로,
# _setup_zsh_p10k는 .zshrc를 쓰는 다른 함수보다 먼저 호출되어야 한다.
# =============================================================================

describe "e2e — setup_termux_base 구조 검증"

_test_zsh_p10k_precedes_aliases() {
    # setup_termux_base() 함수 본문을 추출하여 _setup_zsh_p10k가
    # _setup_aliases 앞에 오는지 확인 (주석 라인 제외)
    local src="${DOMAIN_DIR}/termux_env.sh"
    local body
    body=$(awk '/^setup_termux_base\(\) \{/,/^}/' "$src" | grep -v '^\s*#')

    local zsh_line alias_line
    zsh_line=$(echo "$body" | grep -n "_setup_zsh_p10k" | head -1 | cut -d: -f1)
    alias_line=$(echo "$body" | grep -n "_setup_aliases" | head -1 | cut -d: -f1)

    if [ -z "$zsh_line" ] || [ -z "$alias_line" ]; then
        echo "[ASSERT] setup_termux_base() 본문에서 두 함수 중 하나를 찾지 못함" >&2
        echo "  zsh_line='$zsh_line' alias_line='$alias_line'" >&2
        return 1
    fi

    if [ "$zsh_line" -ge "$alias_line" ]; then
        echo "[ASSERT] _setup_zsh_p10k (line $zsh_line in function)는 _setup_aliases (line $alias_line) 앞에 와야 함" >&2
        return 1
    fi
}
it "setup_termux_base()에서 _setup_zsh_p10k가 _setup_aliases보다 먼저 호출된다" _test_zsh_p10k_precedes_aliases

# =============================================================================
# Regression #4: fcitx5 중복 autostart
# -----------------------------------------------------------------------------
# Issue #2 — "Failed to create addon: dbus Unable to request dbus name.
#            Is there another fcitx already running?"
# 원인: _setup_korean_env가 ~/.config/autostart/fcitx5.desktop을 항상 생성
#      fcitx5 패키지가 제공하는 시스템 autostart와 중복 → 두 인스턴스 실행
# =============================================================================

describe "e2e — fcitx5 autostart 중복 방지 (issue #2 regression)"

_test_skips_user_autostart_when_system_exists() {
    local sb; sb=$(make_sandbox)
    _load_domain "$sb"

    # 시스템 autostart 존재 시뮬레이션 (fcitx5 패키지가 제공하는 파일)
    mkdir -p "${PREFIX}/etc/xdg/autostart"
    cat > "${PREFIX}/etc/xdg/autostart/org.fcitx.Fcitx5.desktop" << 'EOF'
[Desktop Entry]
Name=Fcitx 5
Exec=fcitx5
EOF

    _setup_korean_env

    # 사용자 autostart는 생성되지 않아야 함
    local user_autostart="$HOME/.config/autostart/fcitx5.desktop"
    if [ -f "$user_autostart" ]; then
        echo "[ASSERT] 시스템 autostart 있음에도 사용자 autostart가 생성됨" >&2
        return 1
    fi

    cleanup_sandbox "$sb"
}
it "시스템 autostart 존재 시 사용자 autostart를 생성하지 않는다" _test_skips_user_autostart_when_system_exists

_test_creates_user_autostart_when_system_missing() {
    # 시스템 autostart가 없는 구버전 Termux 대응 폴백
    local sb; sb=$(make_sandbox)
    _load_domain "$sb"

    # 시스템 autostart 없음 (sandbox 초기 상태 그대로)

    _setup_korean_env

    local user_autostart="$HOME/.config/autostart/fcitx5.desktop"
    assert_file_exists "$user_autostart"
    assert_file_contains "$user_autostart" "Exec=fcitx5"

    cleanup_sandbox "$sb"
}
it "시스템 autostart 없으면 사용자 autostart를 폴백 생성한다" _test_creates_user_autostart_when_system_missing

_test_cleanup_removes_duplicate_user_autostart() {
    # 기존 설치본 마이그레이션 — 이미 잘못 생성된 사용자 autostart 제거
    local sb; sb=$(make_sandbox)
    _load_domain "$sb"

    # 시스템 autostart + 기존 사용자 autostart 둘 다 존재하는 상태
    mkdir -p "${PREFIX}/etc/xdg/autostart"
    echo "[Desktop Entry]" > "${PREFIX}/etc/xdg/autostart/org.fcitx.Fcitx5.desktop"
    mkdir -p "$HOME/.config/autostart"
    echo "[Desktop Entry]" > "$HOME/.config/autostart/fcitx5.desktop"

    _cleanup_duplicate_fcitx_autostart

    if [ -f "$HOME/.config/autostart/fcitx5.desktop" ]; then
        echo "[ASSERT] 중복 사용자 autostart가 제거되지 않음" >&2
        return 1
    fi

    cleanup_sandbox "$sb"
}
it "기존 설치본의 중복 사용자 autostart를 제거한다 (마이그레이션)" _test_cleanup_removes_duplicate_user_autostart

_test_cleanup_preserves_user_autostart_if_no_system() {
    # 시스템 autostart 없는 구버전에서 사용자 autostart는 남겨둬야 함
    local sb; sb=$(make_sandbox)
    _load_domain "$sb"

    # 시스템 autostart 없음, 사용자 autostart만 존재
    mkdir -p "$HOME/.config/autostart"
    echo "[Desktop Entry]" > "$HOME/.config/autostart/fcitx5.desktop"

    _cleanup_duplicate_fcitx_autostart

    assert_file_exists "$HOME/.config/autostart/fcitx5.desktop"

    cleanup_sandbox "$sb"
}
it "시스템 autostart 없으면 사용자 autostart를 제거하지 않는다" _test_cleanup_preserves_user_autostart_if_no_system

# =============================================================================
# Regression #5: conky backend 설정
# -----------------------------------------------------------------------------
# Issue #2 — "conky: Unknown setting 'backend'"
# 원인: Alterf.conf의 `backend = "glx";`를 현재 conky가 인식 못함
# =============================================================================

describe "e2e — conky Alterf.conf 유효성 (issue #2 regression)"

_test_alterf_conf_has_no_backend_setting() {
    local conf="${REPO_ROOT}/tar/conky/.config/conky/Alterf/Alterf.conf"
    assert_file_exists "$conf"

    # backend 라인이 있으면 실패
    if grep -q '^\s*backend\s*=' "$conf"; then
        echo "[ASSERT] Alterf.conf에 conky가 인식 못하는 'backend =' 설정 재도입됨" >&2
        grep -n '^\s*backend\s*=' "$conf" >&2
        return 1
    fi
}
it "Alterf.conf에 'backend =' 설정이 없다" _test_alterf_conf_has_no_backend_setting

_test_alterf_conf_still_has_core_settings() {
    # backend 제거하다가 다른 설정까지 날리지 않았는지 sanity check
    local conf="${REPO_ROOT}/tar/conky/.config/conky/Alterf/Alterf.conf"
    assert_file_contains "$conf" 'alignment'
    assert_file_contains "$conf" 'maximum_width'
    assert_file_contains "$conf" 'use_xft'
}
it "Alterf.conf의 핵심 설정은 유지된다" _test_alterf_conf_still_has_core_settings

# =============================================================================
# Regression #6: prun DBus session bus 전파
# -----------------------------------------------------------------------------
# Issue #2 — "flameshot: error: Unable to connect via DBus"
# 근본 원인: proot이 getuid()를 위조(예: 10381)하지만 커널 SCM_CREDENTIALS는 실제 UID(10380)
#           → dbus EXTERNAL auth UID 불일치 → 인증 실패 → proot에서 호스트 dbus 접근 불가
# 해결: flameshot을 Termux native로 이동 (네이티브 프로세스는 UID 일치 → dbus 정상)
# =============================================================================

# --- flameshot: Termux native 실행 검증 ---
# proot dbus EXTERNAL auth는 UID 불일치(proot getuid()≠커널 SCM_CREDENTIALS)로 작동 불가
# → flameshot을 Termux native로 이동, autostart에서 prun 제거

describe "e2e — flameshot Termux native 실행 검증 (issue #2 regression)"

_test_flameshot_autostart_runs_native() {
    # flameshot autostart가 native로 실행되어야 함 (prun 없이)
    local desktop="${REPO_ROOT}/tar/config/.config/autostart/org.flameshot.Flameshot.desktop"
    assert_file_exists "$desktop"

    local exec_line
    exec_line=$(grep '^Exec=' "$desktop" | head -1)
    # prun이 없어야 함 — native 실행
    if echo "$exec_line" | grep -q "prun"; then
        echo "[ASSERT] flameshot autostart가 여전히 prun을 사용: ${exec_line}" >&2
        return 1
    fi
    assert_output_contains "$exec_line" "flameshot"
}
it "flameshot autostart가 native로 실행된다 (prun 없음)" _test_flameshot_autostart_runs_native

_test_flameshot_in_native_packages() {
    # flameshot이 Termux native 패키지 목록에 포함되어야 함
    local pkg_file="${REPO_ROOT}/domain/packages.sh"
    source "$pkg_file"
    local found=0
    for pkg in "${PKGS_TERMUX_XFCE[@]}"; do
        [ "$pkg" = "flameshot" ] && found=1 && break
    done
    [ "$found" -eq 1 ] || { echo "[ASSERT] flameshot이 PKGS_TERMUX_XFCE에 없다" >&2; return 1; }
}
it "flameshot이 Termux native XFCE 패키지에 포함된다" _test_flameshot_in_native_packages

_test_prun_no_dbus_propagation() {
    # prun에 DBUS 전파 코드가 없어야 함 (작동 불가 — UID 불일치)
    local sb; sb=$(make_sandbox)
    _load_domain "$sb"
    _setup_prun

    local prun="${PREFIX}/bin/prun"
    assert_file_exists "$prun"
    # DBUS_ENV 변수 사용이 없어야 함
    if grep -v '^\s*#' "$prun" | grep -q 'DBUS_ENV'; then
        echo "[ASSERT] prun에 작동 불가능한 DBUS_ENV 전파 코드가 남아있다" >&2
        cleanup_sandbox "$sb"
        return 1
    fi

    cleanup_sandbox "$sb"
}
it "prun에 작동 불가능한 DBUS 전파 코드가 없다" _test_prun_no_dbus_propagation

# =============================================================================
# 결과 출력
# =============================================================================
print_results
