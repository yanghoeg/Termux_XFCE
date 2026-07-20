#!/data/data/com.termux/files/usr/bin/bash
# =============================================================================
# DOMAIN: xfce_env.sh
# -----------------------------------------------------------------------------
# XFCE 환경 구성 도메인 로직 (Termux native)
# - 기존 xfce.sh 통합 및 멱등성 확보
# - 테마, 폰트, 배경화면, fancybash
# =============================================================================

[[ -v REPO_BASE ]] || readonly REPO_BASE="https://github.com/yanghoeg/Termux_XFCE/raw/main"

# -----------------------------------------------------------------------------
# Public API
# -----------------------------------------------------------------------------

setup_xfce_packages() {
    ui_info "XFCE 패키지 설치"
    # 패키지 설치 전에 Desktop 생성 — desktop-file-utils trigger가
    # pkg install 중에 ~/Desktop에 .desktop 파일을 복사하려 시도하기 때문
    mkdir -p "$HOME/Desktop"

    local -a _pkgs=("${PKGS_TERMUX_XFCE[@]}")
    local total=${#_pkgs[@]} i=0
    for p in "${_pkgs[@]}"; do
        ((++i))
        if pkg_is_installed "$p"; then
            ui_info "  (${i}/${total}) ${p} — 이미 설치됨"
        else
            ui_info "  (${i}/${total}) ${p} 설치 중..."
            pkg_install "$p"
        fi
    done

    # 디스플레이 서버 패키지 설치
    local _dp
    local -a _dp_arr
    IFS=' ' read -ra _dp_arr <<< "$(display_get_packages)"
    for _dp in "${_dp_arr[@]}"; do
        if pkg_is_installed "$_dp"; then
            ui_info "  ${_dp} — 이미 설치됨 (display)"
        else
            ui_info "  ${_dp} 설치 중... (display)"
            pkg_install "$_dp"
        fi
    done

    # Firefox 데스크탑 아이콘
    local firefox_desktop="$HOME/Desktop/firefox.desktop"
    [ -f "$firefox_desktop" ] || \
        cp "$PREFIX/share/applications/firefox.desktop" "$firefox_desktop" 2>/dev/null || true
    if [ -f "$firefox_desktop" ]; then
        chmod +x "$firefox_desktop"
        gio set "$firefox_desktop" metadata::trusted true 2>/dev/null || true
    fi
}

setup_xfce_theme() {
    # 테마/커서는 선택적 — 다운로드 실패 시 경고만 출력하고 계속 진행
    ui_info "WhiteSur-Dark 테마 설치"
    _install_whitesur_theme || true
    ui_info "Fluent 커서 아이콘 설치"
    _install_fluent_cursor || true
}

setup_xfce_fonts() {
    # 폰트는 선택적 — 다운로드 실패 시 경고만 출력하고 계속 진행
    ui_info "폰트 설치 (CascadiaCode, Meslo Nerd, Noto Emoji)"
    mkdir -p "$HOME/.fonts"
    _install_cascadia_code || true
    _install_meslo_nerd    || true
    _install_noto_emoji    || true
    _install_termux_font   || true
    # fontconfig 캐시 갱신: MesloLGS NF 등 신규 폰트를 xfce4-terminal이 FontName으로 찾을 수 있게 함
    command -v fc-cache >/dev/null && fc-cache -f "$HOME/.fonts" 2>/dev/null || true
}

setup_xfce_wallpaper() {
    # 배경화면은 선택적 — 다운로드 실패 시 경고만 출력하고 계속 진행
    ui_info "배경화면 다운로드"
    local bg_dir="$PREFIX/share/backgrounds/xfce"
    mkdir -p "$bg_dir"

    [ -f "$bg_dir/dark_waves.png" ] || \
        wget -q "${REPO_BASE}/dark_waves.png" -O "$bg_dir/dark_waves.png" \
        || { ui_warn "dark_waves.png 다운로드 실패"; rm -f "$bg_dir/dark_waves.png"; }
    [ -f "$bg_dir/TheSolarSystem.jpg" ] || \
        wget -q "${REPO_BASE}/TheSolarSystem.jpg" -O "$bg_dir/TheSolarSystem.jpg" \
        || { ui_warn "TheSolarSystem.jpg 다운로드 실패"; rm -f "$bg_dir/TheSolarSystem.jpg"; }
}

setup_xfce_fancybash() {
    local username="$1"
    ui_info "fancybash 설치 (Termux)"
    _install_fancybash "$username" "termux"
}

setup_xfce_autostart() {
    ui_info "자동시작 설정 (Conky, Flameshot)"
    _setup_autostart_config
    _migrate_fix_x11_input
    _migrate_flameshot_native
    _migrate_terminal_font
    _migrate_borderless_maximize
    _migrate_disable_compositing
    _migrate_remove_actions_plugin
    _migrate_dbus_propagate_path
    _migrate_conky_exec_ampersand
}

# -----------------------------------------------------------------------------
# Private
# -----------------------------------------------------------------------------

# 주의: 아래 _install_* 함수들은 네트워크(wget)에 의존하므로 단위 테스트 불가.
# 테스트는 tests/test_domain_xfce.sh의 멱등성 케이스(파일 존재 시 건너뜀)만 커버.
# 실제 다운로드 경로 검증은 e2e(autopilot) 환경에서만 가능.

_install_whitesur_theme() {
    local theme_dir="$PREFIX/share/themes/WhiteSur-Dark"
    [ -d "$theme_dir" ] && return 0  # 멱등성

    local tmpdir
    tmpdir=$(mktemp -d)
    trap "rm -rf '$tmpdir'" RETURN

    local zip="2024-11-18.zip"
    wget -q "https://github.com/vinceliuice/WhiteSur-gtk-theme/archive/refs/tags/${zip}" -O "$tmpdir/$zip" \
        || { ui_warn "WhiteSur 테마 다운로드 실패"; return 1; }
    unzip -o -q "$tmpdir/$zip" -d "$tmpdir" \
        || { ui_warn "WhiteSur 테마 압축 해제 실패"; return 1; }
    tar -xf "$tmpdir/WhiteSur-gtk-theme-2024-11-18/release/WhiteSur-Dark.tar.xz" -C "$tmpdir" \
        || { ui_warn "WhiteSur 테마 tar 해제 실패"; return 1; }
    mv "$tmpdir/WhiteSur-Dark/" "$PREFIX/share/themes/"
}

_install_fluent_cursor() {
    local cursor_dir="$PREFIX/share/icons/dist-dark"
    [ -d "$cursor_dir" ] && return 0  # 멱등성

    local tmpdir
    tmpdir=$(mktemp -d)
    trap "rm -rf '$tmpdir'" RETURN

    local zip="2024-02-25.zip"
    wget -q "https://github.com/vinceliuice/Fluent-icon-theme/archive/refs/tags/${zip}" -O "$tmpdir/$zip" \
        || { ui_warn "Fluent 커서 다운로드 실패"; return 1; }
    unzip -o -q "$tmpdir/$zip" -d "$tmpdir" \
        || { ui_warn "Fluent 커서 압축 해제 실패"; return 1; }
    rm -rf "$PREFIX/share/icons/dist" "$PREFIX/share/icons/dist-dark"
    mv "$tmpdir/Fluent-icon-theme-2024-02-25/cursors/dist"      "$PREFIX/share/icons/"
    mv "$tmpdir/Fluent-icon-theme-2024-02-25/cursors/dist-dark" "$PREFIX/share/icons/"
}

_install_cascadia_code() {
    [ -f "$HOME/.fonts/CascadiaCode.otf" ] && return 0

    local tmpdir
    tmpdir=$(mktemp -d)
    trap "rm -rf '$tmpdir'" RETURN

    local zip="CascadiaCode-2111.01.zip"
    wget -q "https://github.com/microsoft/cascadia-code/releases/download/v2111.01/${zip}" -O "$tmpdir/$zip" \
        || { ui_warn "CascadiaCode 폰트 다운로드 실패"; return 1; }
    unzip -q "$tmpdir/$zip" -d "$tmpdir" \
        || { ui_warn "CascadiaCode 폰트 압축 해제 실패"; return 1; }
    mv "$tmpdir/otf/static/"*.otf "$HOME/.fonts/" 2>/dev/null || true
    mv "$tmpdir/ttf/"*.ttf       "$HOME/.fonts/" 2>/dev/null || true
}

_install_meslo_nerd() {
    # ryanoasis/nerd-fonts v3.2.1 Meslo.zip은 "MesloLGSNerdFont-Regular.ttf" 형태로 압축
    # (family: "MesloLGS Nerd Font" / "MesloLGS Nerd Font Mono")
    [ -f "$HOME/.fonts/MesloLGSNerdFont-Regular.ttf" ] && return 0

    local tmpdir
    tmpdir=$(mktemp -d)
    trap "rm -rf '$tmpdir'" RETURN

    wget -q "https://github.com/ryanoasis/nerd-fonts/releases/download/v3.2.1/Meslo.zip" -O "$tmpdir/Meslo.zip" \
        || { ui_warn "Meslo Nerd Font 다운로드 실패"; return 1; }
    unzip -q "$tmpdir/Meslo.zip" -d "$tmpdir/meslo_tmp" \
        || { ui_warn "Meslo Nerd Font 압축 해제 실패"; return 1; }
    mv "$tmpdir/meslo_tmp/"*.ttf "$HOME/.fonts/" 2>/dev/null || true
}

_install_noto_emoji() {
    [ -f "$HOME/.fonts/NotoColorEmoji-Regular.ttf" ] && return 0
    wget -q "${REPO_BASE}/NotoColorEmoji-Regular.ttf" -O "$HOME/.fonts/NotoColorEmoji-Regular.ttf" \
        || { ui_warn "Noto Emoji 폰트 다운로드 실패"; rm -f "$HOME/.fonts/NotoColorEmoji-Regular.ttf"; return 1; }
}

_install_termux_font() {
    [ -f "$HOME/.termux/font.ttf" ] && return 0
    wget -q "${REPO_BASE}/font.ttf" -O "$HOME/.termux/font.ttf" \
        || { ui_warn "Termux 폰트 다운로드 실패"; rm -f "$HOME/.termux/font.ttf"; return 1; }
}

_install_fancybash() {
    local username="$1"
    local hostname="${2:-termux}"
    local target="$HOME/.fancybash.sh"

    [ -f "$target" ] && return 0

    wget -q "${REPO_BASE}/fancybash.sh" -O "$target" \
        || { ui_warn "fancybash.sh 다운로드 실패"; rm -f "$target"; return 1; }

    # 사용자명/호스트명 치환 (line 326, 327은 원본 기준)
    # PROMT_USER/PROMT_HOST 정의 라인으로 한정 — 라인 미지정 시 TRIANGLE 구분자 등
    # 무관한 유니코드 이스케이프의 첫 \u,\h 까지 손상됨
    sed -i "/local PROMT_USER=/s/\\\\u/${username}/" "$target"
    sed -i "/local PROMT_HOST=/s/\\\\h/${hostname}/" "$target"

    local bashrc="$PREFIX/etc/bash.bashrc"
    grep -q "source.*\.fancybash\.sh" "$bashrc" 2>/dev/null || \
        echo "source \$HOME/.fancybash.sh" >> "$bashrc"
}

# 자동시작 + XFCE 프리셋(.config 하위 전체) 1회성 배포
# 가드가 conky.desktop 하나만 체크하는 이유:
#   - tar/config/.config/ 하위엔 Thunar/, Mousepad/, xfce4/, mimeapps.list 등이 함께 들어있음
#   - 사용자가 재설치/재실행 시 자신의 XFCE 커스터마이즈(패널 배치, 단축키 변경 등)를
#     덮어쓰지 않기 위해 의도적으로 광범위 가드 사용 — "첫 설치 프리셋"으로만 작동
#   - tar/config/ 내용이 업데이트되어 기존 사용자에게 반영이 필요하면
#     _migrate_terminal_font()처럼 "구 값 감지 → 선택적 치환" 패턴의 마이그레이션 함수를 별도로 추가할 것
_setup_autostart_config() {
    local autostart_dir="$HOME/.config/autostart"
    [ -d "$autostart_dir" ] && \
        [ -f "$autostart_dir/conky.desktop" ] && return 0  # 멱등성 (위 주석 참조)

    mkdir -p "$autostart_dir"

    # install.sh:28-35이 curl-pipe 실행을 git clone으로 재시작하므로 SCRIPT_DIR은 항상 존재
    # (과거엔 config.tar.gz wget 폴백이 있었으나 해당 아티팩트 미발행 → 제거)
    cp -rn "${SCRIPT_DIR}/tar/config/.config/." "$HOME/.config/"

    chmod +x "$autostart_dir/conky.desktop" 2>/dev/null || true
    chmod +x "$autostart_dir/org.flameshot.Flameshot.desktop" 2>/dev/null || true
}

# 기존 설치본의 xfce4-terminal 폰트를 Nerd Font로 갱신 (p10k 아이콘 렌더링용)
# Why: _setup_autostart_config가 cp -rn로 보호되어 재설치 시 신규 terminalrc가 적용되지 않음
# Note: "MesloLGS NF"는 romkatv/p10k-media 전용 이름이며 ryanoasis Meslo.zip의 family는
#       "MesloLGS Nerd Font Mono" — fc-match로 확인함 (fallback 방지)
# Note: xfce4-terminal ≥ 1.1은 terminalrc → xfconf xml로 이관됨 → 양쪽 모두 갱신
# Termux:X11 포커스 복귀 시 입력 오류 수정용 autostart 추가
# Why: 다른 앱 전환 후 X11로 돌아오면 터치→우클릭 오작동, 방향키 불가 현상 발생
#      _setup_autostart_config의 cp -rn + 멱등 가드로 기존 설치본에는 반영 안 됨
_migrate_fix_x11_input() {
    local src="${SCRIPT_DIR}/tar/config/.config/autostart/fix-x11-input.desktop"
    local dst="$HOME/.config/autostart/fix-x11-input.desktop"
    [ -f "$src" ] || return 0  # 소스 없으면 건너뜀
    # 항상 덮어씀 — xdotool alt 고착 해제 등 내용이 업데이트될 수 있음
    cp "$src" "$dst"
}

# 기존 설치본의 flameshot autostart를 prun → native로 전환
# Why: 6cb9166에서 flameshot을 Termux native로 이동했으나
#      _setup_autostart_config의 cp -rn + 멱등 가드로 기존 파일이 업데이트되지 않음
# Issue: #2 — proot dbus EXTERNAL auth UID 불일치로 flameshot DBus 연결 실패
_migrate_flameshot_native() {
    local desktop="$HOME/.config/autostart/org.flameshot.Flameshot.desktop"
    [ -f "$desktop" ] || return 0
    grep -q "Exec=prun " "$desktop" 2>/dev/null || return 0
    sed -i 's#Exec=prun flameshot#Exec=flameshot#g' "$desktop"
}

_migrate_terminal_font() {
    local target="MesloLGS Nerd Font Mono 12"
    local old='Cascadia Mono PL|MesloLGS NF'

    # 1) terminalrc (xfce4-terminal < 1.1)
    local rc="$HOME/.config/xfce4/terminal/terminalrc"
    if [ -f "$rc" ] && grep -qE "^FontName=($old)" "$rc" 2>/dev/null; then
        sed -i -E "s#^FontName=($old).*#FontName=${target}#" "$rc"
    fi

    # 2) xfconf xml (xfce4-terminal ≥ 1.1 — 최초 실행 시 terminalrc를 xfconf로 이관,
    #   이후 terminalrc는 무시됨. 설치 후 재로그인에서 이관이 일어나도 cover하도록 xml도 수정)
    local xml="$HOME/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-terminal.xml"
    if [ -f "$xml" ] && grep -qE "name=\"font-name\"[^/]*value=\"($old)" "$xml" 2>/dev/null; then
        sed -i -E "s#(name=\"font-name\"[^/]*value=)\"($old)[^\"]*\"#\\1\"${target}\"#" "$xml"
    fi
}

# 기존 설치본의 borderless_maximize 끄기 — 최대화 시 타이틀바(닫기 버튼) 숨김 방지
# Why: borderless_maximize=true면 최대화된 창의 닫기/최소화 버튼이 사라져
#      모바일 환경에서 창을 닫을 방법이 없어짐
_migrate_borderless_maximize() {
    local xml="$HOME/.config/xfce4/xfconf/xfce-perchannel-xml/xfwm4.xml"
    [ -f "$xml" ] || return 0
    grep -q 'name="borderless_maximize"[^/]*value="true"' "$xml" 2>/dev/null || return 0
    sed -i 's#name="borderless_maximize" type="bool" value="true"#name="borderless_maximize" type="bool" value="false"#' "$xml"
}

# 기존 설치본의 컴포지터 끄기 — Zink(GPU) + 컴포지터 조합이 검은 화면 유발
# Why: Adreno GPU에서 MESA_LOADER_DRIVER_OVERRIDE=zink + use_compositing=true면
#      Termux:X11 화면이 검은색으로만 표시되어 데스크탑을 사용할 수 없음
_migrate_disable_compositing() {
    local xml="$HOME/.config/xfce4/xfconf/xfce-perchannel-xml/xfwm4.xml"
    [ -f "$xml" ] || return 0
    grep -q 'name="use_compositing"[^/]*value="true"' "$xml" 2>/dev/null || return 0
    sed -i 's#name="use_compositing" type="bool" value="true"#name="use_compositing" type="bool" value="false"#' "$xml"
}

# 패널에서 XFCE actions 플러그인 제거 — Termux에 systemd/logind 없어서
# shutdown/reboot 비활성화, logout도 정상 종료 불가 → Kill Termux X11 버튼만 유지
_migrate_remove_actions_plugin() {
    local xml="$HOME/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-panel.xml"
    [ -f "$xml" ] || return 0
    grep -q 'value="actions"' "$xml" 2>/dev/null || return 0
    # plugin-ids에서 plugin-20 제거
    sed -i '/<value type="int" value="20"\/>/d' "$xml"
    # actions 플러그인 정의 블록 제거 — depth 추적 awk 사용
    # (line-range sed는 중첩 <property>(예: items 배열)가 있으면 그 첫 </property>에서
    #  멈춰 plugin-20 자신의 종료 태그가 남는 XML 손상을 유발함)
    local tmp="${xml}.tmp"
    awk '
        skip == 0 && /<property name="plugin-20"[^>]*value="actions"/ { skip = 1 }
        skip == 1 {
            line = $0
            opens = gsub(/<property[^>]*>/, "&", line)
            selfclose = gsub(/<property[^>]*\/>/, "&", line)
            closes = gsub(/<\/property>/, "&", line)
            depth += (opens - selfclose) - closes
            if (depth <= 0) { skip = 0 }
            next
        }
        { print }
    ' "$xml" > "$tmp" && mv "$tmp" "$xml"
}

# 기존 설치본의 dbus-propagate autostart에서 /usr/bin/env → bash 직접 호출로 전환
# Why: Termux에는 /usr/bin/env가 없어 XFCE autostart 실행 시 절대경로 해석 실패
#      → dbus activation 환경 전파가 완전히 무동작 상태
_migrate_dbus_propagate_path() {
    local desktop="$HOME/.config/autostart/00-env-dbus-propagate.desktop"
    [ -f "$desktop" ] || return 0
    grep -q '/usr/bin/env' "$desktop" 2>/dev/null || return 0
    sed -i 's|Exec=/usr/bin/env bash|Exec=bash|' "$desktop"
}

# 기존 설치본의 conky autostart Exec 끝 '&' 제거
# Why: desktop entry 스펙에서 Exec 값은 셸 해석 없이 직접 실행되므로
#      '&'가 conky 인자로 전달되어 실행 실패 가능
_migrate_conky_exec_ampersand() {
    local desktop="$HOME/.config/autostart/conky.desktop"
    [ -f "$desktop" ] || return 0
    grep -q 'Exec=.*&$' "$desktop" 2>/dev/null || return 0
    sed -i 's| &$||' "$desktop"
}
