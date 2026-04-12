#!/data/data/com.termux/files/usr/bin/bash
# =============================================================================
# DOMAIN: xfce_env.sh
# -----------------------------------------------------------------------------
# XFCE 환경 구성 도메인 로직 (Termux native)
# - 기존 xfce.sh 통합 및 멱등성 확보
# - 테마, 폰트, 배경화면, fancybash
# =============================================================================

readonly REPO_BASE="https://github.com/yanghoeg/Termux_XFCE/raw/main"

# -----------------------------------------------------------------------------
# Public API
# -----------------------------------------------------------------------------

setup_xfce_packages() {
    ui_info "XFCE 패키지 설치"
    for p in "${PKGS_TERMUX_XFCE[@]}" "${PKGS_TERMUX_CLI[@]}"; do
        pkg_is_installed "$p" || pkg_install "$p"
    done

    # Firefox 데스크탑 아이콘
    mkdir -p "$HOME/Desktop"
    local firefox_desktop="$HOME/Desktop/firefox.desktop"
    [ -f "$firefox_desktop" ] || \
        cp "$PREFIX/share/applications/firefox.desktop" "$firefox_desktop" 2>/dev/null || true
    [ -f "$firefox_desktop" ] && chmod +x "$firefox_desktop"
}

setup_xfce_theme() {
    ui_info "WhiteSur-Dark 테마 설치"
    _install_whitesur_theme
    ui_info "Fluent 커서 아이콘 설치"
    _install_fluent_cursor
}

setup_xfce_fonts() {
    ui_info "폰트 설치 (CascadiaCode, Meslo Nerd, Noto Emoji)"
    mkdir -p "$HOME/.fonts"
    _install_cascadia_code
    _install_meslo_nerd
    _install_noto_emoji
    _install_termux_font
}

setup_xfce_wallpaper() {
    ui_info "배경화면 다운로드"
    local bg_dir="$PREFIX/share/backgrounds/xfce"
    mkdir -p "$bg_dir"

    [ -f "$bg_dir/dark_waves.png" ] || \
        wget -q "${REPO_BASE}/dark_waves.png" -O "$bg_dir/dark_waves.png"
    [ -f "$bg_dir/TheSolarSystem.jpg" ] || \
        wget -q "${REPO_BASE}/TheSolarSystem.jpg" -O "$bg_dir/TheSolarSystem.jpg"
}

setup_xfce_fancybash() {
    local username="$1"
    ui_info "fancybash 설치 (Termux)"
    _install_fancybash "$username" "termux"
}

setup_xfce_autostart() {
    ui_info "자동시작 설정 (Conky, Flameshot)"
    _setup_autostart_config
}

# -----------------------------------------------------------------------------
# Private
# -----------------------------------------------------------------------------

_install_whitesur_theme() {
    local theme_dir="$PREFIX/share/themes/WhiteSur-Dark"
    [ -d "$theme_dir" ] && return 0  # 멱등성

    local zip="2024-11-18.zip"
    # 잔류 파일 정리 후 다운로드
    rm -rf "WhiteSur-gtk-theme-2024-11-18" "WhiteSur-Dark" "$zip"
    wget -q "https://github.com/vinceliuice/WhiteSur-gtk-theme/archive/refs/tags/${zip}" -O "$zip"
    unzip -o -q "$zip"   # -o: 기존 파일 덮어쓰기 (프롬프트 없음)
    tar -xf "WhiteSur-gtk-theme-2024-11-18/release/WhiteSur-Dark.tar.xz"
    mv WhiteSur-Dark/ "$PREFIX/share/themes/"
    rm -rf "WhiteSur-gtk-theme-2024-11-18" "$zip"
}

_install_fluent_cursor() {
    local cursor_dir="$PREFIX/share/icons/dist-dark"
    [ -d "$cursor_dir" ] && return 0  # 멱등성

    local zip="2024-02-25.zip"
    rm -rf "Fluent-icon-theme-2024-02-25" "$zip"
    wget -q "https://github.com/vinceliuice/Fluent-icon-theme/archive/refs/tags/${zip}" -O "$zip"
    unzip -o -q "$zip"   # -o: 덮어쓰기
    mv "Fluent-icon-theme-2024-02-25/cursors/dist"      "$PREFIX/share/icons/"
    mv "Fluent-icon-theme-2024-02-25/cursors/dist-dark" "$PREFIX/share/icons/"
    rm -rf "Fluent-icon-theme-2024-02-25" "$zip"
}

_install_cascadia_code() {
    [ -f "$HOME/.fonts/CascadiaCode.otf" ] && return 0

    local zip="CascadiaCode-2111.01.zip"
    wget -q "https://github.com/microsoft/cascadia-code/releases/download/v2111.01/${zip}" -O "$zip"
    unzip -q "$zip"
    mv otf/static/*.otf "$HOME/.fonts/" 2>/dev/null || true
    mv ttf/*.ttf       "$HOME/.fonts/" 2>/dev/null || true
    rm -rf otf/ ttf/ woff2/ "$zip"
}

_install_meslo_nerd() {
    [ -f "$HOME/.fonts/MesloLGS NF Regular.ttf" ] && return 0

    wget -q "https://github.com/ryanoasis/nerd-fonts/releases/download/v3.2.1/Meslo.zip" -O Meslo.zip
    unzip -q Meslo.zip -d meslo_tmp
    mv meslo_tmp/*.ttf "$HOME/.fonts/" 2>/dev/null || true
    rm -rf meslo_tmp/ Meslo.zip LICENSE.txt readme.md 2>/dev/null || true
}

_install_noto_emoji() {
    [ -f "$HOME/.fonts/NotoColorEmoji-Regular.ttf" ] && return 0
    wget -q "${REPO_BASE}/NotoColorEmoji-Regular.ttf" -O "$HOME/.fonts/NotoColorEmoji-Regular.ttf"
}

_install_termux_font() {
    [ -f "$HOME/.termux/font.ttf" ] && return 0
    wget -q "${REPO_BASE}/font.ttf" -O "$HOME/.termux/font.ttf"
}

_install_fancybash() {
    local username="$1"
    local hostname="${2:-termux}"
    local target="$HOME/.fancybash.sh"

    [ -f "$target" ] && return 0

    wget -q "${REPO_BASE}/fancybash.sh" -O "$target"

    # 사용자명/호스트명 치환 (line 326, 327은 원본 기준)
    sed -i "s/\\\\u/${username}/" "$target"
    sed -i "s/\\\\h/${hostname}/" "$target"

    local bashrc="$PREFIX/etc/bash.bashrc"
    grep -q "source.*\.fancybash\.sh" "$bashrc" 2>/dev/null || \
        echo "source \$HOME/.fancybash.sh" >> "$bashrc"
}

_setup_autostart_config() {
    local autostart_dir="$HOME/.config/autostart"
    [ -d "$autostart_dir" ] && \
        [ -f "$autostart_dir/conky.desktop" ] && return 0  # 멱등성

    mkdir -p "$autostart_dir"

    local config_src="${SCRIPT_DIR:-}/tar/config/.config"
    if [ -d "$config_src" ]; then
        # 로컬 repo에서 직접 복사 (외부 다운로드 불필요)
        cp -rn "$config_src/." "$HOME/.config/"
    else
        # curl 파이프 실행 시 원격 다운로드
        local tmp="${HOME}/.cache/termux-xfce-install"
        mkdir -p "$tmp"
        wget -q "${REPO_BASE}/config.tar.gz" -O "${tmp}/config.tar.gz"
        tar -xzf "${tmp}/config.tar.gz" -C "$HOME"
        rm -f "${tmp}/config.tar.gz"
    fi

    chmod +x "$autostart_dir/conky.desktop" 2>/dev/null || true
    chmod +x "$autostart_dir/org.flameshot.Flameshot.desktop" 2>/dev/null || true
}
