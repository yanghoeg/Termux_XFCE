#!/data/data/com.termux/files/usr/bin/bash
# =============================================================================
# DOMAIN: locale_ko.sh
# -----------------------------------------------------------------------------
# Termux bionic libc는 setlocale(LC_MESSAGES,…)을 지원하지 않아
# "XFCE 설정 → 언어 선택"식 접근이 불가. 대신 다음 3-레이어로 강제 한글화:
#   (1) glibc용 .mo 카탈로그를 $PREFIX/share/locale에 배치
#   (2) force_gettext.so (LD_PRELOAD) — gettext/GTK 심볼 후킹
#   (3) startxfce4-ko 래퍼 — 환경변수 + LD_PRELOAD 주입 후 startxfce4 exec
# =============================================================================

# 옵트인: install.sh가 --korean-locale 플래그나 KOREAN_LOCALE=true 시에만 호출
setup_korean_locale_native() {
    local locale_zip="${KOREAN_LOCALE_ZIP:-}"

    if [ -z "$locale_zip" ] || [ ! -f "$locale_zip" ]; then
        ui_warn "한글 로케일을 건너뜁니다 — KOREAN_LOCALE_ZIP 경로가 유효하지 않습니다."
        ui_warn "사용법: KOREAN_LOCALE_ZIP=/path/to/locale.zip bash install.sh --korean-locale"
        return 0
    fi

    ui_info "한글 로케일 — glibc .mo 카탈로그 배치"
    _deploy_locale_catalogs "$locale_zip"

    ui_info "한글 로케일 — force_gettext.so 빌드"
    _build_force_gettext

    ui_info "한글 로케일 — startxfce4-ko 래퍼 생성"
    _install_startxfce4_ko_wrapper

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

    # 기존 locale 백업 (Termux 기본 locale은 비어있는 경우가 많지만 안전하게)
    if [ -d "$dest" ] && [ ! -d "$dest.bak" ]; then
        mv "$dest" "$dest.bak.$(date +%s)"
    fi

    mkdir -p "$dest"
    unzip -q "$zip" -d "$dest"
}

_build_force_gettext() {
    local src="${SCRIPT_DIR}/assets/force_gettext.c"
    local dst="$PREFIX/lib/force_gettext.so"

    [ -f "$dst" ] && return 0  # 멱등성

    if [ ! -f "$src" ]; then
        ui_warn "force_gettext.c 누락 — 한글 로케일 빌드를 건너뜁니다."
        return 0
    fi
    if ! command -v clang >/dev/null 2>&1; then
        pkg_install clang
    fi

    clang -shared -fPIC -O2 -o "$dst" "$src" -ldl
}

_install_startxfce4_ko_wrapper() {
    local wrapper="$HOME/bin/startxfce4-ko"
    [ -x "$wrapper" ] && return 0

    mkdir -p "$HOME/bin"
    cat > "$wrapper" << 'EOF'
#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

PREFIX="/data/data/com.termux/files/usr"

# 로케일 힌트 (QLocale/KDE 포함)
export LANG="ko_KR.UTF-8"
export LANGUAGE="ko_KR:ko:en_US:en"

# Qt 번역 경로 (누적)
QT_TRANSLATIONS_PATH="$PREFIX/share/qt6/translations:$PREFIX/share/qt/translations${QT_TRANSLATIONS_PATH:+:$QT_TRANSLATIONS_PATH}"
export QT_TRANSLATIONS_PATH
export KDE_FULL_SESSION=1
export KDE_LANG=ko
export KDE_USE_QT_TRANSLATIONS=1
export QT_LOCALE_OVERRIDE=ko_KR

# gettext(.mo) 루트
export FORCE_TEXTDOMAINDIR="$PREFIX/share/locale"

# 폴백 도메인 — XFCE/GTK/KDE FW6/그래픽 앱 카탈로그
export FALLBACK_DOMAINS="mousepad xfce4-terminal thunar ristretto \
gtk30 glib20 gdk-pixbuf libxfce4ui-2 libxfce4util exo garcon \
xfce4-session xfce4-settings xfce4-panel xfdesktop xfconf vte-2.91 \
gtksourceview-5 gtksourceview-4 gimp20 gimp30 gimp20-std-plugins \
gimp30-plugins gegl-0.4 babl inkscape \
vlc kdenlive kxmlgui6 kwidgetsaddons6 kconfigwidgets6 kcoreaddons6 \
kitemviews6 kiconthemes6 kio6 sonnet6 knewstuff6 ktextwidgets6 \
knotifications6 kservice6 solid6 kguiaddons6 kcolorscheme6"

export XDG_DATA_DIRS="$PREFIX/share${XDG_DATA_DIRS:+:$XDG_DATA_DIRS}"

# LD_PRELOAD — libtermux-exec 먼저, force_gettext 뒤 (둘 다 중복 방지)
case ":${LD_PRELOAD-}:" in *:"$PREFIX/lib/libtermux-exec.so":*) ;; *)
  export LD_PRELOAD="$PREFIX/lib/libtermux-exec.so${LD_PRELOAD:+:$LD_PRELOAD}";; esac
case ":${LD_PRELOAD-}:" in *:"$PREFIX/lib/force_gettext.so":*) ;; *)
  export LD_PRELOAD="$PREFIX/lib/force_gettext.so${LD_PRELOAD:+:$LD_PRELOAD}";; esac

# DBus 세션 (없을 때만)
if command -v dbus-launch >/dev/null 2>&1 && [[ -z "${DBUS_SESSION_BUS_ADDRESS-}" ]]; then
  eval "$(dbus-launch --sh-syntax)"
  export DBUS_SESSION_BUS_ADDRESS DBUS_SESSION_BUS_PID
fi

exec startxfce4
EOF
    chmod +x "$wrapper"
}

_install_dbus_propagate_autostart() {
    local dest="$HOME/.config/autostart/00-env-dbus-propagate.desktop"
    [ -f "$dest" ] && return 0

    mkdir -p "$HOME/.config/autostart"
    cat > "$dest" << 'EOF'
[Desktop Entry]
Type=Application
Name=Env & DBus propagate
Exec=/usr/bin/env bash -lc 'command -v dbus-update-activation-environment >/dev/null 2>&1 && dbus-update-activation-environment --all || true'
X-GNOME-Autostart-enabled=true
NoDisplay=true
EOF
}
