#!/data/data/com.termux/files/usr/bin/bash
# =============================================================================
# DOMAIN: termux_env.sh
# -----------------------------------------------------------------------------
# Termux 기본 환경 구성 도메인 로직
# - pkg_install, ui_info 등은 어댑터에서 주입됨 (직접 호출 안 함)
# - 기존: etc.sh 의 termux_base_setup(), termux_gpu_accel_install() 통합
# =============================================================================

# -----------------------------------------------------------------------------
# Public API
# -----------------------------------------------------------------------------

setup_termux_base() {
    ui_info "Termux 기본 환경 설정 시작"

    _setup_termux_properties
    _setup_termux_repos
    pkg_update
    pkg_upgrade
    _install_base_packages
    # zsh+p10k 먼저 설정 (~/.zshrc 생성) → 이후 _setup_aliases 등이 zshrc에도 블록을 반영
    # (과거: _setup_aliases가 먼저 실행되어 clean install 시 zshrc에 alias 블록 누락)
    _setup_zsh_p10k
    _setup_aliases
    _setup_locale
    _setup_korean_env
    _setup_xdg_runtime
    _setup_gpu_env
}

setup_termux_shortcuts() {
    ui_info "Termux 단축키(startXFCE) 설정"
    _setup_start_xfce
    _setup_kill_display
    _setup_prun
    _setup_prun_gui
    _setup_cp2menu
    _setup_app_installer
    _setup_clipboard_sync
}

_download_and_open_apk() {
    local apk_url="$1" apk_filename="$2"
    local dl_dir="$HOME/storage/downloads"
    local apk_path="${dl_dir}/${apk_filename}"

    if [ ! -d "$dl_dir" ]; then
        dl_dir="$HOME"
        apk_path="${dl_dir}/${apk_filename}"
        ui_warn "storage/downloads 없음 — ${apk_path} 에 저장합니다."
    fi

    if [ -f "$apk_path" ]; then
        ui_warn "APK가 이미 다운로드되어 있습니다: ${apk_path}"
    else
        if ! wget -q "$apk_url" -O "$apk_path"; then
            rm -f "$apk_path"
            ui_warn "APK 다운로드 실패: ${apk_url}"
            return 0
        fi
    fi

    termux-open "$apk_path" 2>/dev/null || \
        ui_warn "APK 자동 열기 실패 — 수동으로 설치하세요: ${apk_path}"
}


# setup_termux_x11_apk: display_x11.sh:display_setup_apk()로 이동됨

setup_termux_api_apk() {
    _download_and_open_apk \
        'https://github.com/termux/termux-api/releases/download/v0.53.0/termux-api-app_v0.53.0+github.debug.apk' \
        'termux-api.apk'
}

setup_termux_float_apk() {
    _download_and_open_apk \
        'https://github.com/termux/termux-float/releases/download/v0.17.0/termux-float-app_v0.17.0+github.debug.apk' \
        'termux-float.apk'
}

setup_termux_widget() {
    local apk_url='https://github.com/termux/termux-widget/releases/download/v0.13.0/termux-widget_v0.13.0+github-debug.apk'
    ui_info "Termux-Widget 설치"

    [ -d "$HOME/.shortcuts" ] || mkdir -p "$HOME/.shortcuts"

    if ! ls "$HOME/.shortcuts/startXFCE" &>/dev/null; then
        ui_warn "startXFCE 단축키가 없습니다. setup_termux_shortcuts 를 먼저 실행하세요."
    fi

    _download_and_open_apk "$apk_url" 'termux-widget.apk'
}

# -----------------------------------------------------------------------------
# Private
# -----------------------------------------------------------------------------

# RC 파일 목록 반환: bash.bashrc + ~/.zshrc (zsh 설치/존재 시)
_rc_targets() {
    echo "$PREFIX/etc/bash.bashrc"
    if command -v zsh &>/dev/null && [ -f "$HOME/.zshrc" ]; then
        echo "$HOME/.zshrc"
    fi
}

# 마커가 없으면 내용을 RC 파일에 추가 (멱등성)
_append_to_rc() {
    local marker="$1"
    local content="$2"
    local file="$3"
    [ -f "$file" ] || return 0  # 파일 없으면 건너뜀 (silent failure 방지)
    grep -qF "$marker" "$file" 2>/dev/null || printf '%s\n' "$content" >> "$file"
}

_setup_termux_properties() {
    local props="$HOME/.termux/termux.properties"
    mkdir -p "$(dirname "$props")"
    [ -f "$props" ] || touch "$props"
    if ! grep -q "^allow-external-apps = true" "$props" 2>/dev/null; then
        sed -i 's/# allow-external-apps = true/allow-external-apps = true/g' "$props"
        # sed 대상 주석이 없었을 경우 직접 추가
        grep -q "^allow-external-apps = true" "$props" 2>/dev/null || \
            echo "allow-external-apps = true" >> "$props"
    fi

    if ! grep -q "^bell-character = ignore" "$props" 2>/dev/null; then
        sed -i 's/# bell-character = ignore/bell-character = ignore/g' "$props"
        grep -q "^bell-character = ignore" "$props" 2>/dev/null || \
            echo "bell-character = ignore" >> "$props"
    fi
}

_setup_termux_repos() {
    pkg_is_installed "x11-repo"  || pkg_install x11-repo
    pkg_is_installed "tur-repo"  || pkg_install tur-repo
    pkg_is_installed "root-repo" || pkg_install root-repo
    pkg_update
}

_install_base_packages() {
    local all_pkgs=(
        "${PKGS_TERMUX_BASE[@]}"
        "${PKGS_TERMUX_CLI[@]}"
        "${PKGS_TERMUX_PROOT[@]}"
    )

    # dbus 리셋: dbus 락/소켓 상태 초기화로 startXFCE의 dbus-launch와
    # proot-distro 내부 dbus-daemon 간 소켓 경합을 예방.
    # 단, XFCE가 이미 설치된 idempotent 재실행에서는 cascade 제거를 피함
    # — `pkg uninstall dbus` 는 dbus를 require하는 64개 (xfce4, fcitx5 전체) 까지 함께 제거.
    # XFCE가 깔려 있다는 건 이전 설치가 성공했다는 뜻 → dbus 리셋 불필요.
    if pkg_is_installed "dbus" && ! pkg_is_installed "xfce4-session"; then
        pkg_remove dbus
    fi

    local total=${#all_pkgs[@]} i=0
    for p in "${all_pkgs[@]}"; do
        ((++i))
        if pkg_is_installed "$p"; then
            ui_info "  (${i}/${total}) ${p} — 이미 설치됨"
        else
            ui_info "  (${i}/${total}) ${p} 설치 중..."
            pkg_install "$p"
        fi
    done
}

_setup_aliases() {
    local block
    block=$(cat << 'ALIASES'

# termux-xfce-aliases
alias ll='eza -alhgF'
alias ls='eza -lF --icons'
alias cat='bat'
# Zink(OpenGL→Vulkan) 드라이버로 앱 실행: zink glxgears
alias zink='MESA_LOADER_DRIVER_OVERRIDE=zink TU_DEBUG=noconform ZINK_DESCRIPTORS=lazy '
# FPS HUD 오버레이: hud glxgears
alias hud='GALLIUM_HUD=fps '
# proot 앱을 FPS HUD + GPU 가속으로 실행: zrunhud glxgears
alias zrunhud='GALLIUM_HUD=fps MESA_LOADER_DRIVER_OVERRIDE=zink TU_DEBUG=noconform ZINK_DESCRIPTORS=lazy prun '
# GPU 모델 확인
alias gpu-info='cat /sys/class/kgsl/kgsl-3d0/gpu_model 2>/dev/null || echo "KGSL 미감지 (비-Adreno?)"'
alias shutdown='kill -9 -1'
ALIASES
)

    while IFS= read -r rc; do
        _append_to_rc "# termux-xfce-aliases" "$block" "$rc"
    done < <(_rc_targets)
}

_setup_locale() {
    local block
    block=$(cat << 'LOCALE'

# termux-xfce-locale
export LANG=ko_KR.UTF-8
export LC_ALL=
export XDG_CONFIG_HOME="$HOME/.config"
# XDG_RUNTIME_DIR은 _setup_xdg_runtime 블록에서 관리 (mode 700 user-private)
export XMODIFIERS="@im=nimf"
export GTK_IM_MODULE=nimf
export QT_IM_MODULE=nimf
LOCALE
)

    while IFS= read -r rc; do
        _append_to_rc "# termux-xfce-locale" "$block" "$rc"
    done < <(_rc_targets)
}

setup_korean_rc() {
    local block
    block=$(cat << 'KOREAN'

# termux-xfce-korean — force_gettext.so 한글 UI 자동 적용
if [ -f "$PREFIX/lib/force_gettext.so" ]; then
    export LANG="ko_KR.UTF-8"
    export LANGUAGE="ko_KR:ko:en_US:en"
    export FORCE_TEXTDOMAINDIR="$PREFIX/share/locale"
    export FALLBACK_DOMAINS="__KOREAN_FALLBACK_DOMAINS__"
    export XDG_DATA_DIRS="$PREFIX/share${XDG_DATA_DIRS:+:$XDG_DATA_DIRS}"
    QT_TRANSLATIONS_PATH="$PREFIX/share/qt6/translations:$PREFIX/share/qt/translations${QT_TRANSLATIONS_PATH:+:$QT_TRANSLATIONS_PATH}"
    export QT_TRANSLATIONS_PATH
    export KDE_LANG=ko QT_LOCALE_OVERRIDE=ko_KR
    case ":${LD_PRELOAD-}:" in *:"$PREFIX/lib/force_gettext.so":*) ;; *)
        export LD_PRELOAD="$PREFIX/lib/force_gettext.so${LD_PRELOAD:+:$LD_PRELOAD}";; esac
fi
KOREAN
)
    block="${block/__KOREAN_FALLBACK_DOMAINS__/$_KOREAN_FALLBACK_DOMAINS}"

    while IFS= read -r rc; do
        _append_to_rc "# termux-xfce-korean" "$block" "$rc"
    done < <(_rc_targets)
}

# XDG runtime dir: mode 700 user-private ($PREFIX/var/run/user/$UID)
# Why: 구버전 _setup_locale가 XDG_RUNTIME_DIR=$TMPDIR(mode 1777, world-writable)을 심어
#      dbus가 "can be written by others" 경고를 띄우며 session bus를 반쯤 고장냄
#      → flameshot/xfdesktop의 DBus 경고도 여기서 파생됨
_setup_xdg_runtime() {
    # 구버전 라인 제거 (마이그레이션)
    while IFS= read -r rc; do
        [ -f "$rc" ] || continue
        sed -i '\#^export XDG_RUNTIME_DIR="${TMPDIR:-/data/data/com.termux/files/usr/tmp}"$#d' "$rc" 2>/dev/null || true
    done < <(_rc_targets)

    local block
    block=$(cat << 'XDGRT'

# termux-xfce-xdg-runtime
XDG_RUNTIME_DIR="${PREFIX:-/data/data/com.termux/files/usr}/var/run/user/$(id -u)"
if [ ! -d "$XDG_RUNTIME_DIR" ]; then
    mkdir -p "$XDG_RUNTIME_DIR" 2>/dev/null && chmod 700 "$XDG_RUNTIME_DIR" 2>/dev/null
fi
export XDG_RUNTIME_DIR
XDGRT
)

    while IFS= read -r rc; do
        _append_to_rc "# termux-xfce-xdg-runtime" "$block" "$rc"
    done < <(_rc_targets)
}

_setup_gpu_env() {
    local block
    block=$(cat << 'GPU'

# termux-xfce-gpu — Adreno 감지 시 Zink 상시 활성화
# Termux:X11 nightly APK: Zink+Turnip이 GLX 스왑체인 생성 실패
#   → glmark2(GLX) 크래시, GTK4 앱(zenity 등) GLXBadCurrentWindow 크래시
# 해결: GSK_RENDERER=cairo (GTK4 Cairo 렌더러), glmark2 → glmark2-es2 사용
# glmark2-es2 는 EGL 사용으로 정상 동작, glmark2(GLX)는 --off-screen 에서만 동작
if [ -f /sys/class/kgsl/kgsl-3d0/gpu_model ]; then
    export MESA_LOADER_DRIVER_OVERRIDE=zink
    export TU_DEBUG=noconform
    export ZINK_DESCRIPTORS=lazy
    export MESA_NO_ERROR=1
    export MESA_GL_VERSION_OVERRIDE=4.6COMPAT
    export MESA_GLES_VERSION_OVERRIDE=3.2
    export MESA_VK_WSI_PRESENT_MODE=fifo
    # GTK4 GLX 스왑체인 크래시 방지 — Cairo 소프트 렌더러 강제
    export GSK_RENDERER=cairo
fi
GPU
)

    while IFS= read -r rc; do
        _append_to_rc "# termux-xfce-gpu" "$block" "$rc"
    done < <(_rc_targets)
}

_setup_zsh_p10k() {
    command -v zsh &>/dev/null || return 0

    # zsh를 기본 쉘로 설정 — Termux의 chsh는 ~/.termux/shell 심볼릭 링크로 관리됨
    # (일반 Linux의 /etc/passwd 기반 getent는 Termux에선 빈값 반환 → 기존 getent 분기는 사실상 항상 실패)
    local zsh_path
    zsh_path=$(command -v zsh)
    local current_shell
    current_shell=$(readlink "$HOME/.termux/shell" 2>/dev/null || echo "")
    if [ "$current_shell" != "$zsh_path" ]; then
        chsh -s zsh 2>/dev/null || true
    fi

    # Powerlevel10k 설치
    local p10k_dir="$HOME/powerlevel10k"
    if [ ! -d "$p10k_dir" ]; then
        ui_info "Powerlevel10k 설치 중..."
        git clone --depth=1 https://github.com/romkatv/powerlevel10k.git "$p10k_dir"
    fi

    # zsh 플러그인 설치
    local plugin_dir="$HOME/.zsh/plugins"
    mkdir -p "$plugin_dir"
    if [ ! -d "$plugin_dir/zsh-autosuggestions" ]; then
        ui_info "zsh-autosuggestions 설치 중..."
        git clone --depth=1 https://github.com/zsh-users/zsh-autosuggestions \
            "$plugin_dir/zsh-autosuggestions"
    fi
    if [ ! -d "$plugin_dir/zsh-syntax-highlighting" ]; then
        ui_info "zsh-syntax-highlighting 설치 중..."
        git clone --depth=1 https://github.com/zsh-users/zsh-syntax-highlighting \
            "$plugin_dir/zsh-syntax-highlighting"
    fi

    # ~/.zshrc 생성 (없는 경우에만)
    local zshrc="$HOME/.zshrc"
    [ -f "$zshrc" ] && return 0

    ui_info "~/.zshrc 생성"
    cat > "$zshrc" << 'ZSHRC'
# Enable Powerlevel10k instant prompt. Should stay close to the top of ~/.zshrc.
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi

# =============================================================================
# 히스토리
# =============================================================================
HISTFILE=~/.zsh_history
HISTSIZE=100000
SAVEHIST=100000
setopt EXTENDED_HISTORY
setopt SHARE_HISTORY
setopt HIST_EXPIRE_DUPS_FIRST
setopt HIST_IGNORE_ALL_DUPS
setopt HIST_IGNORE_SPACE
setopt HIST_SAVE_NO_DUPS
setopt HIST_REDUCE_BLANKS

# =============================================================================
# 자동 완성
# =============================================================================
fpath=(~/.zsh/completions $fpath)
autoload -Uz compinit && compinit
autoload -U +X bashcompinit && bashcompinit

# =============================================================================
# 플러그인
# =============================================================================
[[ -f ~/.zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh ]] && \
    source ~/.zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh

# syntax-highlighting은 반드시 마지막에 로드
[[ -f ~/.zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh ]] && \
    source ~/.zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh

# =============================================================================
# Powerlevel10k
# =============================================================================
source ~/powerlevel10k/powerlevel10k.zsh-theme
[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh

# =============================================================================
# 환경변수
# =============================================================================
export EDITOR=nano
export VISUAL=nano
export PATH="$HOME/.local/bin:$PREFIX/bin:$PATH"
ZSHRC
}

_setup_korean_env() {
    _install_nimf_native || ui_warn "nimf 설치 실패 — autostart만 설정합니다"

    local autostart_dir="$HOME/.config/autostart"
    mkdir -p "$autostart_dir"

    local nimf_desktop="$autostart_dir/nimf.desktop"
    [ -f "$nimf_desktop" ] && return 0

    cat > "$nimf_desktop" << 'EOF'
[Desktop Entry]
Type=Application
Name=Nimf
Exec=nimf
Hidden=false
X-GNOME-Autostart-enabled=true
EOF

    # fcitx5 시스템 autostart가 있으면 사용자 오버라이드로 비활성화
    local fcitx_sys="${PREFIX}/etc/xdg/autostart/org.fcitx.Fcitx5.desktop"
    if [ -f "$fcitx_sys" ]; then
        cat > "$autostart_dir/org.fcitx.Fcitx5.desktop" << 'EOF'
[Desktop Entry]
Type=Application
Name=Fcitx5
Exec=fcitx5 -d
Hidden=true
X-GNOME-Autostart-enabled=false
EOF
    fi
}

_install_nimf_native() {
    command -v nimf &>/dev/null && return 0

    local url="https://github.com/yanghoeg/Termux_XFCE/releases/download/nimf-termux-v1.4.19/nimf_1.4.19_aarch64.deb"
    local deb="${TMPDIR:-/tmp}/nimf_1.4.19_aarch64.deb"

    ui_info "nimf 한글 입력기 설치 중..."
    wget -q "$url" -O "$deb" || { ui_warn "nimf deb 다운로드 실패"; return 1; }
    dpkg -i --force-overwrite "$deb" 2>/dev/null || true
    apt --fix-broken install -y 2>/dev/null || true
    rm -f "$deb"
    glib-compile-schemas "${PREFIX}/share/glib-2.0/schemas/" 2>/dev/null || true

    command -v nimf &>/dev/null || return 1
}

_setup_start_xfce() {
    local shortcut="$HOME/.shortcuts/startXFCE"
    mkdir -p "$HOME/.shortcuts"
    script_build_start_xfce "$shortcut"
    chmod +x "$shortcut"
    ln -sf "$shortcut" "$PREFIX/bin/startXFCE"
}

_setup_kill_display() {
    local bin="$PREFIX/bin/kill_display_session"

    mkdir -p "$PREFIX/share/applications"
    script_build_kill_display "$bin"
    chmod +x "$bin"

    cat > "$PREFIX/share/applications/kill_display_session.desktop" << 'EOF'
[Desktop Entry]
Version=1.0
Type=Application
Name=Kill Display Session
Exec=kill_display_session
Icon=system-shutdown
Categories=System;
StartupNotify=false
EOF
}

_setup_prun() {
    local bin="$PREFIX/bin/prun"

    # PROOT_DISTRO는 설치 시 결정된 값을 config에서 읽음
    cat > "$bin" << 'EOF'
#!/data/data/com.termux/files/usr/bin/bash
CONFIG="$HOME/.config/termux-xfce/config"
[ -f "$CONFIG" ] && source "$CONFIG"

DISTRO="${PROOT_DISTRO:-archlinux}"

# config에 PROOT_USER 있으면 사용, 없으면 home/ 디렉토리에서 탐색 (alarm 제외)
if [ -n "${PROOT_USER:-}" ]; then
    USER_NAME="$PROOT_USER"
else
    USER_NAME=$(ls "$PREFIX/var/lib/proot-distro/installed-rootfs/$DISTRO/home/" 2>/dev/null \
        | grep -v '^alarm$' | head -1)
    USER_NAME="${USER_NAME:-user}"
fi

# LD_PRELOAD 해제: Termux exec 훅이 proot-distro 실행 시 재주입하므로
# unset만으론 부족 → proot 내부 첫 명령을 env -u LD_PRELOAD로 감싼다
unset LD_PRELOAD

# 참고: 호스트 DBUS_SESSION_BUS_ADDRESS를 proot에 전파해도 작동하지 않음
# proot이 getuid()를 위조(예: 10381)하지만 커널 SCM_CREDENTIALS는 실제 UID(10380)를 보고
# → dbus EXTERNAL auth에서 UID 불일치 → 인증 실패
# dbus가 필요한 앱(flameshot 등)은 Termux native로 설치하여 해결

# DISPLAY: 실행 환경(XFCE 세션) 값 우선, 없으면 :0.0 폴백
# 인자 없으면 PROOT_SHELL(config) 기반 인터랙티브 로그인 셸 실행
if [ $# -eq 0 ]; then
    exec proot-distro login "$DISTRO" --user "$USER_NAME" --shared-tmp \
        -- env -u LD_PRELOAD DISPLAY="${DISPLAY:-:0.0}" "${PROOT_SHELL:-bash}" --login
else
    exec proot-distro login "$DISTRO" --user "$USER_NAME" --shared-tmp \
        -- env -u LD_PRELOAD DISPLAY="${DISPLAY:-:0.0}" "$@"
fi
EOF

    chmod +x "$bin"
}

# prun-gui: proot GUI 앱 실행 시 로딩 알림 표시
# proot-distro login은 콜드 스타트에 10–30초 걸려 사용자가 실행 여부를 알기 어려움
# → notify-send로 "로딩 중" 토스트를 먼저 띄우고 prun exec
_setup_prun_gui() {
    local bin="$PREFIX/bin/prun-gui"

    cat > "$bin" << 'EOF'
#!/data/data/com.termux/files/usr/bin/bash
# 사용: prun-gui "AppName" -- <proot 내부 명령...>
# "--" 는 선택. 없으면 $1 이후 전부 명령으로 간주.
NAME="${1:-App}"; shift
[ "${1:-}" = "--" ] && shift

if command -v notify-send >/dev/null 2>&1; then
    notify-send -t 30000 -i system-run \
        "$NAME" "로딩 중... (proot 컨테이너 기동, 최대 30초)" \
        >/dev/null 2>&1 &
fi

exec prun "$@"
EOF

    chmod +x "$bin"

    # 기존 .desktop 파일 중 prun을 쓰는 항목을 prun-gui로 마이그레이션
    _migrate_desktop_to_prun_gui
}

# 기존 설치된 .desktop 파일의 Exec=...prun ... → prun-gui 마이그레이션
# 신규 설치는 desktop_copy_from_proot / desktop_register가 처리하므로
# 이 함수는 업그레이드 시 기존 파일만 패치
_migrate_desktop_to_prun_gui() {
    local apps_dir="$PREFIX/share/applications"
    local f app_name line content repl
    for f in "$apps_dir"/*.desktop; do
        [ -f "$f" ] || continue
        # 이미 prun-gui 사용 중이면 건너뜀
        grep -q "prun-gui" "$f" 2>/dev/null && continue
        # prun을 사용하는 .desktop만 대상
        grep -q "prun " "$f" 2>/dev/null || continue
        app_name=$(grep -m1 '^Name=' "$f" | cut -d= -f2-)
        app_name="${app_name:-App}"
        # 홑따옴표 안에 리터럴 작은따옴표를 넣기 위한 셸 이스케이프: ' → '\''
        app_name="${app_name//\'/\'\\\'\'}"
        # sed 대신 순수 bash 문자열 치환 사용 (sed 치환 문자열의 백슬래시 소비 방지).
        # 치환 문자열을 사전 변수로 빌드 — ${line//..} 안에 ${app_name}를 직접 중첩하면
        # bash가 확장하지 못하고 리터럴로 남으므로 반드시 분리한다.
        repl="\"prun-gui '${app_name}' -- "
        content=""
        while IFS= read -r line || [ -n "$line" ]; do
            line="${line/\"prun /$repl}"
            content+="$line"$'\n'
        done < "$f"
        printf '%s' "$content" > "$f"
    done
}

_setup_app_installer() {
    local bin="$PREFIX/bin/app-installer"
    local desktop="$PREFIX/share/applications/app-installer.desktop"

    # SCRIPT_DIR은 install.sh 실행 시점 기준 — curl-pipe(~/.termux-xfce-installer),
    # 수동 clone(~/Termux_XFCE) 양쪽 모두 정확한 경로를 기록한다.
    # 항상 재생성하여 SCRIPT_DIR 변경을 반영한다.
    cat > "$bin" << EOF
#!/data/data/com.termux/files/usr/bin/bash
# GTK4 zenity: Zink+Turnip GLX 스왑체인 크래시 방지
export GSK_RENDERER=cairo
exec bash ${SCRIPT_DIR}/app-installer/install.sh "\$@"
EOF
    chmod +x "$bin"

    if [ ! -f "$desktop" ]; then
        mkdir -p "$PREFIX/share/applications"
        cat > "$desktop" << 'EOF'
[Desktop Entry]
Version=1.0
Type=Application
Name=App Installer
Exec=app-installer
Icon=appimagekit-pioneer_install_icon
Categories=System;
Terminal=false
StartupNotify=false
EOF
    fi

    # 데스크탑 바탕화면 아이콘 (phoenixbyrd 방식)
    local desktop_icon="$HOME/Desktop/App-Installer.desktop"
    if [ ! -f "$desktop_icon" ]; then
        mkdir -p "$HOME/Desktop"
        cat > "$desktop_icon" << 'EOF'
[Desktop Entry]
Version=1.0
Type=Application
Name=App Installer
Exec=app-installer
Icon=appimagekit-pioneer_install_icon
Categories=System;
Terminal=false
StartupNotify=false
EOF
        chmod +x "$desktop_icon"
        gio set "$desktop_icon" metadata::trusted true 2>/dev/null || true
    fi
}

_setup_cp2menu() {
    local bin="$PREFIX/bin/cp2menu"

    mkdir -p "$PREFIX/share/applications"
    script_build_cp2menu "$bin"
    chmod +x "$bin"

    cat > "$PREFIX/share/applications/cp2menu.desktop" << 'EOF'
[Desktop Entry]
Version=1.0
Type=Application
Name=cp2menu
Exec=cp2menu
Icon=edit-move
Categories=System;
Terminal=false
StartupNotify=false
EOF
}

_setup_clipboard_sync() {
    local bin="$PREFIX/bin/termux-clipboard-sync"
    mkdir -p "$(dirname "$bin")"

    cat > "$bin" << 'SYNCEOF'
#!/data/data/com.termux/files/usr/bin/bash
# Android ↔ X11 클립보드 양방향 동기화 데몬
PREV_ANDROID="" PREV_X11=""
while true; do
    sleep 2
    ANDROID=$(termux-clipboard-get 2>/dev/null) || continue
    X11=$(DISPLAY="${DISPLAY:-:0}" xclip -selection clipboard -o 2>/dev/null) || continue
    if [ "$ANDROID" != "$PREV_ANDROID" ] && [ "$ANDROID" != "$X11" ]; then
        printf '%s' "$ANDROID" | DISPLAY="${DISPLAY:-:0}" xclip -selection clipboard -i 2>/dev/null
    elif [ "$X11" != "$PREV_X11" ] && [ "$X11" != "$ANDROID" ]; then
        termux-clipboard-set "$X11" 2>/dev/null
    fi
    PREV_ANDROID="$ANDROID" PREV_X11="$X11"
done
SYNCEOF
    chmod +x "$bin"
}
