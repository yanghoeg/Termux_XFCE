#!/data/data/com.termux/files/usr/bin/bash
# =============================================================================
# DOMAIN: locale_ko.sh
# -----------------------------------------------------------------------------
# Termux bionic libc는 setlocale(LC_MESSAGES,…)을 지원하지 않아
# "XFCE 설정 → 언어 선택"식 접근이 불가. 대신 다음 3-레이어로 강제 한글화:
#   (1) glibc용 .mo 카탈로그를 $PREFIX/share/locale에 배치
#   (2) force_gettext.so (LD_PRELOAD) — gettext/GTK 심볼 후킹
#   (3) startXFCE 및 로그인 셸 — 같은 로케일 환경으로 세션 시작
# =============================================================================

# FALLBACK_DOMAINS — force_gettext.so가 후킹할 gettext 도메인 목록
# setup_korean_rc (termux_env.sh), script_builder_zenity.sh에서도 참조
if [[ ! -v _KOREAN_FALLBACK_DOMAINS ]]; then
readonly _KOREAN_FALLBACK_DOMAINS="\
mousepad xfce4-terminal thunar ristretto \
gtk30 glib20 gdk-pixbuf libxfce4ui-2 libxfce4util exo garcon \
xfce4-session xfce4-settings xfce4-panel xfdesktop xfconf vte-2.91 \
gtksourceview-5 gtksourceview-4 gimp20 gimp30 gimp20-std-plugins \
gimp30-plugins gegl-0.4 babl inkscape \
vlc kdenlive kxmlgui6 kwidgetsaddons6 kconfigwidgets6 kcoreaddons6 \
kitemviews6 kiconthemes6 kio6 sonnet6 knewstuff6 ktextwidgets6 \
knotifications6 kservice6 solid6 kguiaddons6 kcolorscheme6"
fi

# 옵트인: app-installer 또는 KOREAN_LOCALE_ZIP 환경변수로 호출
setup_korean_locale_native() {
    local locale_zip="${KOREAN_LOCALE_ZIP:-}"

    if [ -z "$locale_zip" ] || [ ! -f "$locale_zip" ]; then
        ui_error "KOREAN_LOCALE_ZIP에 한글 번역 카탈로그 ZIP 경로를 지정하세요."
        return 1
    fi

    ui_info "한글 로케일 — glibc .mo 카탈로그 배치"
    _deploy_locale_catalogs "$locale_zip" || return 1

    ui_info "한글 로케일 — force_gettext.so 빌드"
    _build_force_gettext || return 1

    ui_info "한글 로케일 — startxfce4-ko 래퍼 생성"
    _install_startxfce4_ko_wrapper || return 1

    ui_info "한글 로케일 — RC 파일에 환경변수 영구 등록"
    setup_korean_rc || return 1

    ui_info "한글 로케일 — DBus 환경 전파 autostart 등록"
    _install_dbus_propagate_autostart
}

# -----------------------------------------------------------------------------
# Private
# -----------------------------------------------------------------------------

_deploy_locale_catalogs() {
    local zip="$1"
    local dest="$PREFIX/share/locale"

    # 멱등성: ko 카탈로그가 이미 배치돼 있으면 스킵 (100개 이상이면 성공 설치로 간주)
    if [ -d "$dest/ko/LC_MESSAGES" ] && \
       [ "$(find "$dest/ko/LC_MESSAGES" -maxdepth 1 -type f | wc -l)" -gt 100 ]; then
        return 0
    fi

    # 압축 해제를 임시 디렉토리에서 먼저 시도 — 실패 시 기존 locale을 건드리지 않는다
    local tmp; tmp=$(mktemp -d "${TMPDIR:-/tmp}/locale_ko.XXXXXX") || return 1
    if ! unzip -q "$zip" -d "$tmp"; then
        rm -rf "$tmp"
        ui_error "한글 로케일 카탈로그 압축 해제 실패"
        return 1
    fi
    if ! find "$tmp/ko/LC_MESSAGES" -maxdepth 1 -type f -name '*.mo' -print -quit 2>/dev/null | grep -q .; then
        rm -rf "$tmp"
        ui_error "ZIP에 ko/LC_MESSAGES/*.mo 한글 카탈로그가 없습니다."
        return 1
    fi

    # 기존 locale 백업 (Termux 기본 locale은 비어있는 경우가 많지만 안전하게)
    if [ -d "$dest" ] && ! compgen -G "${dest}.bak."* > /dev/null 2>&1; then
        mv "$dest" "${dest}.bak.$(date +%s)" || { rm -rf "$tmp"; return 1; }
    fi

    # 병합 복사 (dest가 남아있는 재실행 — .bak이 이미 있어 백업을 건너뛴 경우 — 에서
    # mv는 tmp를 dest 하위로 중첩시키므로 사용하지 않는다)
    mkdir -p "$dest" || { rm -rf "$tmp"; return 1; }
    if ! cp -a "$tmp"/. "$dest"/; then
        rm -rf "$tmp"
        ui_error "한글 로케일 카탈로그 배치 실패"
        return 1
    fi
    rm -rf "$tmp"
}

_build_force_gettext() {
    local src="${SCRIPT_DIR}/assets/force_gettext.c"
    local dst="$PREFIX/lib/force_gettext.so"
    local source_hash

    if [ ! -f "$src" ]; then
        ui_error "force_gettext.c를 찾을 수 없습니다: $src"
        return 1
    fi
    source_hash=$(sha256sum "$src") || return 1
    source_hash=${source_hash%% *}
    if [ -s "$dst" ] && [ -r "${dst}.sha256" ] && \
       [ "$(cat "${dst}.sha256")" = "$source_hash" ]; then
        return 0
    fi
    if ! command -v clang >/dev/null 2>&1; then
        pkg_install clang || return 1
    fi

    local built
    built=$(mktemp "${dst}.XXXXXX") || return 1
    clang -shared -fPIC -O2 -o "$built" "$src" -ldl || {
        rm -f "$built"
        ui_error "force_gettext.so 빌드 실패"
        return 1
    }
    [ -s "$built" ] || { rm -f "$built"; return 1; }
    chmod 755 "$built" && mv -f "$built" "$dst" || { rm -f "$built"; return 1; }
    printf '%s\n' "$source_hash" > "${dst}.sha256"
}

# Keep the old command as a forwarding entry point; session setup has one owner.
_install_startxfce4_ko_wrapper() {
    local wrapper="$HOME/bin/startxfce4-ko"
    mkdir -p "${wrapper%/*}" || return 1
    cat > "$wrapper" << 'EOF' || return 1
#!/data/data/com.termux/files/usr/bin/bash
exec startXFCE "$@"
EOF
    chmod +x "$wrapper"
}

_install_dbus_propagate_autostart() {
    local dest="$HOME/.config/autostart/00-env-dbus-propagate.desktop"
    [ -f "$dest" ] && return 0

    mkdir -p "$HOME/.config/autostart" || return 1
    cat > "$dest" << 'EOF'
[Desktop Entry]
Type=Application
Name=Env & DBus propagate
Exec=bash -lc 'command -v dbus-update-activation-environment >/dev/null 2>&1 && dbus-update-activation-environment --all || true'
X-GNOME-Autostart-enabled=true
NoDisplay=true
EOF
}
