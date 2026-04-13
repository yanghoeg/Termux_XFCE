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
    _setup_aliases
    _setup_locale
    _setup_gpu_env
    _setup_zsh_p10k
}

setup_termux_gpu() {
    ui_info "GPU 가속(mesa, Adreno) 설치"
    for p in "${PKGS_TERMUX_GPU[@]}"; do
        pkg_is_installed "$p" || pkg_install "$p"
    done
    _detect_and_log_gpu
}

setup_termux_gpu_dev() {
    ui_info "GPU 개발 도구(clvk 등) 설치"
    for p in "${PKGS_TERMUX_GPU_DEV[@]}"; do
        pkg_is_installed "$p" || pkg_install "$p"
    done
}

setup_termux_korean() {
    ui_info "한글 입력기(fcitx5-hangul) 설치"
    pkg_is_installed "tur-repo" || pkg_install tur-repo
    _setup_tur_multilib

    for p in "${PKGS_TERMUX_KOREAN[@]}"; do
        pkg_is_installed "$p" || pkg_install "$p"
    done
    _setup_korean_env
}

setup_termux_shortcuts() {
    ui_info "Termux 단축키(startXFCE) 설정"
    _setup_start_xfce
    _setup_kill_termux_x11
    _setup_prun
    _setup_cp2menu
    _setup_app_installer
}

setup_termux_widget() {
    local apk_url='https://github.com/termux/termux-widget/releases/download/v0.13.0/termux-widget_v0.13.0+github-debug.apk'
    ui_info "Termux-Widget 설치"

    [ -d "$HOME/.shortcuts" ] || mkdir -p "$HOME/.shortcuts"

    if ! ls "$HOME/.shortcuts/startXFCE" &>/dev/null; then
        ui_warn "startXFCE 단축키가 없습니다. setup_termux_shortcuts 를 먼저 실행하세요."
    fi

    local apk_path="$HOME/storage/downloads/termux-widget.apk"
    wget -q "$apk_url" -O "$apk_path"
    termux-open "$apk_path"
    rm -f "$apk_path"
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
    grep -q "$marker" "$file" 2>/dev/null || printf '%s\n' "$content" >> "$file"
}

_setup_termux_properties() {
    local props="$HOME/.termux/termux.properties"
    # 멱등성: 이미 설정된 경우 건너뜀
    grep -q "^allow-external-apps = true" "$props" 2>/dev/null || \
        sed -i 's/# allow-external-apps = true/allow-external-apps = true/g' "$props"

    grep -q "^bell-character = ignore" "$props" 2>/dev/null || \
        sed -i 's/# bell-character = ignore/bell-character = ignore/g' "$props"
}

_setup_termux_repos() {
    pkg_is_installed "x11-repo"  || pkg_install x11-repo
    pkg_is_installed "tur-repo"  || pkg_install tur-repo
    pkg_is_installed "root-repo" || pkg_install root-repo
    pkg_update
}

_setup_tur_multilib() {
    local tur_list="$PREFIX/etc/apt/sources.list.d/tur.list"
    grep -q "tur-multilib" "$tur_list" 2>/dev/null || \
        sed -i '/^deb /s/$/ tur-multilib tur-hacking/' "$tur_list"
    pkg_update
}

_install_base_packages() {
    local all_pkgs=(
        "${PKGS_TERMUX_BASE[@]}"
        "${PKGS_TERMUX_CLI[@]}"
        "${PKGS_TERMUX_PROOT[@]}"
    )

    # dbus 충돌 방지 (멱등성)
    pkg_is_installed "dbus" && pkg_remove dbus

    for p in "${all_pkgs[@]}"; do
        pkg_is_installed "$p" || pkg_install "$p"
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
export XDG_RUNTIME_DIR="${TMPDIR:-/data/data/com.termux/files/usr/tmp}"
export XMODIFIERS=@im=fcitx5
export GTK_IM_MODULE=fcitx5
export QT_IM_MODULE=fcitx5
LOCALE
)

    while IFS= read -r rc; do
        _append_to_rc "# termux-xfce-locale" "$block" "$rc"
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
    export MESA_VK_WSI_PRESENT_MODE=immediate
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

    # zsh를 기본 쉘로 설정 (chsh 가능한 경우)
    local zsh_path
    zsh_path=$(command -v zsh)
    local current_shell
    current_shell=$(getent passwd "${USER:-$(id -un)}" 2>/dev/null | cut -d: -f7 || echo "")
    if [ -n "$current_shell" ] && [ "$current_shell" != "$zsh_path" ]; then
        chsh -s "$zsh_path" 2>/dev/null || true
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
    # fcitx5 자동시작 설정
    local autostart_dir="$HOME/.config/autostart"
    mkdir -p "$autostart_dir"

    local fcitx_desktop="$autostart_dir/fcitx5.desktop"
    [ -f "$fcitx_desktop" ] && return 0

    cat > "$fcitx_desktop" << 'EOF'
[Desktop Entry]
Type=Application
Name=Fcitx5
Exec=fcitx5 -d
Hidden=false
X-GNOME-Autostart-enabled=true
EOF
}

_setup_start_xfce() {
    local shortcut="$HOME/.shortcuts/startXFCE"
    mkdir -p "$HOME/.shortcuts"

    cat > "$shortcut" << 'EOF'
#!/data/data/com.termux/files/usr/bin/bash
# shortcut 실행 시 TMPDIR 미상속 방지
TMPDIR="${TMPDIR:-/data/data/com.termux/files/usr/tmp}"

# ─── dbus 중복 감지: 1 초과이면 현황 다이얼로그 표시 ──────────
DBUS_COUNT=$(pgrep -c dbus-daemon 2>/dev/null || echo 0)
if [ "$DBUS_COUNT" -gt 1 ]; then
    # 기존 X 소켓으로 DISPLAY 자동 감지
    _SOCK=$(ls "${TMPDIR}/.X11-unix/X"* 2>/dev/null | head -1)
    if [ -n "$_SOCK" ]; then
        _NUM=$(basename "$_SOCK" | sed 's/^X//')
        export DISPLAY=":${_NUM}"
    fi

    XFCE_PID=$(pgrep -x xfce4-session 2>/dev/null | head -1 || echo "")
    TX11_PID=$(pgrep -f termux-x11 2>/dev/null | head -1 || echo "")
    XFCE_STATUS=$([ -n "$XFCE_PID" ] && echo "실행 중 (PID: ${XFCE_PID})" || echo "미실행")
    TX11_STATUS=$([ -n "$TX11_PID" ] && echo "실행 중 (PID: ${TX11_PID})" || echo "미실행")

    choice=$(zenity --list \
        --title="XFCE 세션 중복 감지" \
        --text="⚠ dbus 인스턴스 ${DBUS_COUNT}개 감지됨\n\n현황\n  • XFCE4 세션 : ${XFCE_STATUS}\n  • Termux:X11 : ${TX11_STATUS}\n  • dbus 수     : ${DBUS_COUNT}개" \
        --column="동작" --height=280 \
        "기존 세션으로 이동" \
        "세션 전체 종료" \
        2>/dev/null || true)

    case "$choice" in
        "기존 세션으로 이동")
            am start --user 0 -n com.termux.x11/com.termux.x11.MainActivity
            ;;
        "세션 전체 종료")
            killall -9 termux-x11 Xwayland xfce4-session pulseaudio dbus-daemon 2>/dev/null || true
            ;;
    esac
    exit 0
fi
# ────────────────────────────────────────────────────────────────

killall -9 termux-x11 Xwayland xfce4-session pulseaudio 2>/dev/null || true
sleep 1

# 잔류 X 소켓/락 파일 전체 삭제
rm -f "${TMPDIR}/.X11-unix/X"* "${TMPDIR}/.X"*"-lock" 2>/dev/null || true

termux-wake-lock

# X 서버 실행 (소켓 생성) — :1은 nightly APK 내부 점유, :0 사용
termux-x11 :0 &
TX11_PID=$!

# Termux:X11 APK 열기 (화면 표시)
sleep 2
am start --user 0 -n com.termux.x11/com.termux.x11.MainActivity

# X 소켓이 생길 때까지 최대 20초 대기 후 DISPLAY 자동 감지
DISPLAY_NUM=""
for i in $(seq 1 20); do
    sleep 1
    SOCK=$(ls "${TMPDIR}/.X11-unix/X"* 2>/dev/null | head -1)
    if [ -n "$SOCK" ]; then
        DISPLAY_NUM=$(basename "$SOCK" | sed 's/^X//')
        break
    fi
done

if [ -z "$DISPLAY_NUM" ]; then
    echo "ERROR: Termux:X11 X 소켓을 찾을 수 없습니다. Termux:X11 앱을 먼저 열어주세요." >&2
    exit 1
fi

XDISPLAY=":${DISPLAY_NUM}"
echo "Detected DISPLAY=${XDISPLAY}"

LD_PRELOAD=/system/lib64/libskcodec.so pulseaudio --start \
    --load="module-native-protocol-tcp auth-ip-acl=127.0.0.1 auth-anonymous=1" \
    --exit-idle-time=-1

LD_PRELOAD=/system/lib64/libskcodec.so pacmd load-module \
    module-native-protocol-tcp auth-ip-acl=127.0.0.1 auth-anonymous=1 2>/dev/null || true

GPU_MODEL=$(cat /sys/class/kgsl/kgsl-3d0/gpu_model 2>/dev/null || echo "")

if [ -n "$GPU_MODEL" ]; then
    # Adreno GPU 감지 → Zink(OpenGL→Vulkan) + Turnip
    # 주의: XFCE4 컴포지터(xfwm4)가 검은 화면을 유발할 경우
    #       설정 → 창관리자(작업) → 컴포지터 → '화면 컴포지팅 활성화' 해제
    env DISPLAY="$XDISPLAY" \
        XDG_RUNTIME_DIR="${TMPDIR:-/data/data/com.termux/files/usr/tmp}" \
        PULSE_SERVER=tcp:127.0.0.1:4713 \
        MESA_LOADER_DRIVER_OVERRIDE=zink \
        TU_DEBUG=noconform \
        ZINK_DESCRIPTORS=lazy \
        MESA_NO_ERROR=1 \
        MESA_GL_VERSION_OVERRIDE=4.6COMPAT \
        MESA_GLES_VERSION_OVERRIDE=3.2 \
        MESA_VK_WSI_PRESENT_MODE=immediate \
        GSK_RENDERER=cairo \
        dbus-launch --exit-with-session xfce4-session &
else
    # llvmpipe 소프트웨어 폴백 (KGSL 미감지)
    env DISPLAY="$XDISPLAY" \
        XDG_RUNTIME_DIR="${TMPDIR:-/data/data/com.termux/files/usr/tmp}" \
        PULSE_SERVER=tcp:127.0.0.1:4713 \
        MESA_NO_ERROR=1 \
        MESA_GL_VERSION_OVERRIDE=4.6COMPAT \
        MESA_GLES_VERSION_OVERRIDE=3.2 \
        LIBGL_ALWAYS_SOFTWARE=1 \
        GSK_RENDERER=cairo \
        dbus-launch --exit-with-session xfce4-session &
fi
EOF

    chmod +x "$shortcut"
    ln -sf "$shortcut" "$PREFIX/bin/startXFCE"
}

# GPU 모델 감지 및 로그 출력
_detect_and_log_gpu() {
    local gpu_model
    gpu_model=$(cat /sys/class/kgsl/kgsl-3d0/gpu_model 2>/dev/null || echo "")

    if [ -z "$gpu_model" ]; then
        ui_warn "KGSL GPU 미감지 (비-Adreno 기기이거나 /dev/kgsl-3d0 접근 불가)"
        # Mali 등 비-Adreno GPU 안내
        if [ -d /sys/class/misc/mali0 ] || [ -c /dev/mali0 ]; then
            ui_warn "Mali GPU 감지 — mesa-zink + GALLIUM_DRIVER=zink 시도 가능"
            ui_warn "단, Mali용 Vulkan ICD가 없으면 llvmpipe로 폴백됩니다."
            ui_warn "시도: pkg install mesa && GALLIUM_DRIVER=zink glxinfo | grep renderer"
        else
            ui_warn "→ llvmpipe 소프트웨어 렌더링으로 실행됩니다."
        fi
        return 0
    fi

    ui_info "감지된 GPU: ${gpu_model}"

    # DRI3 접근 가능 여부 — Termux:X11 nightly APK DRI3 지원 필요
    if [ -r /dev/dri/renderD128 ]; then
        ui_info "DRI3 활성 — Zink+Turnip X11 직접 렌더링 가능"
    else
        ui_warn "DRI3 비활성 (/dev/dri/renderD128 접근 불가)"
        ui_warn "→ Termux:X11 nightly APK를 최신 버전으로 업데이트하세요"
        ui_warn "  미업데이트 시: glmark2 크래시, glmark2-es2 검정화면"
    fi

    # Adreno 세대별 안내
    if [[ "$gpu_model" =~ [Aa]dreno.*8[0-9]{2} ]]; then
        ui_info "Adreno 8xx (Snapdragon 8 Elite) 감지 — Mesa 26+ KGSL 드라이버 권장"
        ui_warn "구형 mesa-vulkan-kgsl deb는 8xx와 호환되지 않을 수 있습니다."
    elif [[ "$gpu_model" =~ [Aa]dreno.*7[0-9]{2} ]]; then
        ui_info "Adreno 7xx (Snapdragon 8 Gen1~3) 감지 — KGSL 드라이버 최적 지원"
    elif [[ "$gpu_model" =~ [Aa]dreno.*6[0-9]{2} ]]; then
        ui_info "Adreno 6xx 감지 — KGSL 드라이버 지원"
    else
        ui_warn "미확인 GPU 모델: ${gpu_model} — Zink 폴백 권장"
    fi
}

_setup_kill_termux_x11() {
    local bin="$PREFIX/bin/kill_termux_x11"
    [ -f "$bin" ] && return 0

    mkdir -p "$PREFIX/share/applications"

    cat > "$bin" << 'EOF'
#!/data/data/com.termux/files/usr/bin/bash
if pgrep -f 'apt|apt-get|dpkg|nala' > /dev/null; then
    zenity --info --text="패키지 설치 중입니다. 완료 후 시도하세요."
    exit 1
fi

termux_x11_pid=$(pgrep -f /system/bin/app_process.*com.termux.x11.Loader)
xfce_pid=$(pgrep -f "xfce4-session")

if [ -n "$termux_x11_pid" ] && [ -n "$xfce_pid" ]; then
    kill -9 "$termux_x11_pid" "$xfce_pid"
    zenity --info --text="Termux-X11 및 XFCE 세션이 종료되었습니다."
else
    zenity --info --text="실행 중인 세션을 찾을 수 없습니다."
fi

pid=$(termux-info | grep -o 'TERMUX_APP_PID=[0-9]\+' | cut -d= -f2)
[ -n "$pid" ] && kill "$pid"
EOF

    chmod +x "$bin"

    # Desktop entry
    cat > "$PREFIX/share/applications/kill_termux_x11.desktop" << 'EOF'
[Desktop Entry]
Version=1.0
Type=Application
Name=Kill Termux X11
Exec=kill_termux_x11
Icon=system-shutdown
Categories=System;
StartupNotify=false
EOF
}

_setup_prun() {
    local bin="$PREFIX/bin/prun"
    [ -f "$bin" ] && return 0

    # PROOT_DISTRO는 설치 시 결정된 값을 config에서 읽음
    cat > "$bin" << 'EOF'
#!/data/data/com.termux/files/usr/bin/bash
CONFIG="$HOME/.config/termux-xfce/config"
[ -f "$CONFIG" ] && source "$CONFIG"

DISTRO="${PROOT_DISTRO:-archlinux}"
USER_NAME=$(basename "$PREFIX/var/lib/proot-distro/installed-rootfs/$DISTRO/home/"* 2>/dev/null || echo "user")

# DISPLAY: 실행 환경(XFCE 세션) 값 우선, 없으면 :0.0 폴백
proot-distro login "$DISTRO" --user "$USER_NAME" --shared-tmp -- env DISPLAY="${DISPLAY:-:0.0}" "$@"
EOF

    chmod +x "$bin"
}

_setup_app_installer() {
    local bin="$PREFIX/bin/app-installer"
    local desktop="$PREFIX/share/applications/app-installer.desktop"

    if [ ! -f "$bin" ]; then
        cat > "$bin" << 'EOF'
#!/data/data/com.termux/files/usr/bin/bash
# GTK4 zenity: Zink+Turnip GLX 스왑체인 크래시 방지
export GSK_RENDERER=cairo
exec bash /data/data/com.termux/files/home/Termux_XFCE/app-installer/install.sh "$@"
EOF
        chmod +x "$bin"
    fi

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
    [ -f "$bin" ] && return 0

    mkdir -p "$PREFIX/share/applications"

    cat > "$bin" << 'EOF'
#!/data/data/com.termux/files/usr/bin/bash
CONFIG="$HOME/.config/termux-xfce/config"
[ -f "$CONFIG" ] && source "$CONFIG"

DISTRO="${PROOT_DISTRO:-ubuntu}"
ROOTFS="$PREFIX/var/lib/proot-distro/installed-rootfs/$DISTRO"
USERNAME=$(basename "$ROOTFS/home/"* 2>/dev/null || echo "user")

action=$(zenity --list --title="cp2menu" --text="작업 선택:" \
    --radiolist --column="" --column="Action" \
    TRUE "Copy .desktop file" FALSE "Remove .desktop file")

[ -z "$action" ] && exit 0

if [[ "$action" == "Copy .desktop file" ]]; then
    selected=$(zenity --file-selection --title=".desktop 파일 선택" \
        --file-filter="*.desktop" \
        --filename="$ROOTFS/usr/share/applications")
    [ -z "$selected" ] && exit 0

    filename=$(basename "$selected")
    cp "$selected" "$PREFIX/share/applications/"
    sed -i "s|^Exec=\(.*\)$|Exec=prun \1|" \
        "$PREFIX/share/applications/$filename"
    zenity --info --text="복사 완료: $filename"

elif [[ "$action" == "Remove .desktop file" ]]; then
    selected=$(zenity --file-selection --title="제거할 .desktop 선택" \
        --file-filter="*.desktop" \
        --filename="$PREFIX/share/applications")
    [ -z "$selected" ] && exit 0

    rm "$selected"
    zenity --info --text="제거 완료: $(basename "$selected")"
fi
EOF

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
