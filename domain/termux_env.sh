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
    local bashrc="$PREFIX/etc/bash.bashrc"
    # 멱등성: alias 블록이 이미 있으면 건너뜀
    grep -q "# termux-xfce-aliases" "$bashrc" 2>/dev/null && return 0

    cat >> "$bashrc" << 'ALIASES'

# termux-xfce-aliases
alias ll='ls -alhF'
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
}

_setup_locale() {
    local bashrc="$PREFIX/etc/bash.bashrc"
    grep -q "# termux-xfce-locale" "$bashrc" 2>/dev/null && return 0

    cat >> "$bashrc" << 'LOCALE'

# termux-xfce-locale
export LANG=ko_KR.UTF-8
export LC_ALL=
export XDG_CONFIG_HOME="$HOME/.config"
export XMODIFIERS=@im=fcitx5
export GTK_IM_MODULE=fcitx5
export QT_IM_MODULE=fcitx5
LOCALE
}

_setup_gpu_env() {
    local bashrc="$PREFIX/etc/bash.bashrc"
    grep -q "# termux-xfce-gpu" "$bashrc" 2>/dev/null && return 0

    cat >> "$bashrc" << 'GPU'

# termux-xfce-gpu — Adreno 감지 시 Zink 상시 활성화
if [ -f /sys/class/kgsl/kgsl-3d0/gpu_model ]; then
    export MESA_LOADER_DRIVER_OVERRIDE=zink
    export TU_DEBUG=noconform
    export ZINK_DESCRIPTORS=lazy
    export MESA_NO_ERROR=1
    export MESA_GL_VERSION_OVERRIDE=4.6COMPAT
    export MESA_GLES_VERSION_OVERRIDE=3.2
fi
GPU
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
    [ -f "$shortcut" ] && return 0

    cat > "$shortcut" << 'EOF'
#!/data/data/com.termux/files/usr/bin/bash
killall -9 termux-x11 Xwayland pulseaudio 2>/dev/null || true

termux-wake-lock
XDG_RUNTIME_DIR="${TMPDIR}" termux-x11 :1.0 &
sleep 1

am start --user 0 -n com.termux.x11/com.termux.x11.MainActivity
sleep 1

LD_PRELOAD=/system/lib64/libskcodec.so pulseaudio --start \
    --load="module-native-protocol-tcp auth-ip-acl=127.0.0.1 auth-anonymous=1" \
    --exit-idle-time=-1

LD_PRELOAD=/system/lib64/libskcodec.so pacmd load-module \
    module-native-protocol-tcp auth-ip-acl=127.0.0.1 auth-anonymous=1

# GPU 자동 감지 (런타임)
# - /dev/kgsl-3d0: 루팅 없이 접근 가능 (Adreno KGSL 커널 드라이버)
# - Termux:X11 최신 버전 + mesa-vulkan-icd-freedreno 24.1+ → DRI3 지원
# - DRI3 활성화 시 Zink+Turnip이 X11 창에 직접 GPU 렌더링 가능
GPU_MODEL=$(cat /sys/class/kgsl/kgsl-3d0/gpu_model 2>/dev/null || echo "")

if [ -n "$GPU_MODEL" ]; then
    # Zink + Turnip 하드웨어 가속 (Adreno 6xx/7xx/8xx)
    # 주의: XFCE4 컴포지터(xfwm4)가 검은 화면을 유발할 경우
    #       설정 → 창관리자(작업) → 컴포지터 → '화면 컴포지팅 활성화' 해제
    MESA_DRIVER=zink
    env DISPLAY=:1.0 \
        PULSE_SERVER=tcp:127.0.0.1:4713 \
        MESA_NO_ERROR=1 \
        MESA_GL_VERSION_OVERRIDE=4.6COMPAT \
        MESA_GLES_VERSION_OVERRIDE=3.2 \
        MESA_LOADER_DRIVER_OVERRIDE=zink \
        TU_DEBUG=noconform \
        ZINK_DESCRIPTORS=lazy \
        dbus-launch --exit-with-session xfce4-session &
else
    # llvmpipe 소프트웨어 폴백 (KGSL 미감지)
    MESA_DRIVER=llvmpipe
    env DISPLAY=:1.0 \
        PULSE_SERVER=tcp:127.0.0.1:4713 \
        MESA_NO_ERROR=1 \
        MESA_GL_VERSION_OVERRIDE=4.6COMPAT \
        MESA_GLES_VERSION_OVERRIDE=3.2 \
        LIBGL_ALWAYS_SOFTWARE=1 \
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
        ui_warn "KGSL GPU 미감지 — virglrenderer-android(소프트 렌더) 폴백 사용"
        return 0
    fi

    ui_info "감지된 GPU: ${gpu_model}"

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

DISTRO="${PROOT_DISTRO:-ubuntu}"
USER_NAME=$(basename "$PREFIX/var/lib/proot-distro/installed-rootfs/$DISTRO/home/"* 2>/dev/null || echo "user")

proot-distro login "$DISTRO" --user "$USER_NAME" --shared-tmp -- env DISPLAY=:1.0 "$@"
EOF

    chmod +x "$bin"
}

_setup_app_installer() {
    local bin="$PREFIX/bin/app-installer"
    local desktop="$PREFIX/share/applications/app-installer.desktop"

    if [ ! -f "$bin" ]; then
        cat > "$bin" << 'EOF'
#!/data/data/com.termux/files/usr/bin/bash
SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
exec bash /data/data/com.termux/files/home/Termux_XFCE/app-installer/install.sh "$@"
EOF
        chmod +x "$bin"
    fi

    [ -f "$desktop" ] && return 0

    mkdir -p "$PREFIX/share/applications"
    cat > "$desktop" << 'EOF'
[Desktop Entry]
Version=1.0
Type=Application
Name=App Installer
Exec=app-installer
Icon=system-software-install
Categories=System;
Terminal=false
StartupNotify=false
EOF
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
    sed -i "s|^Exec=\(.*\)$|Exec=proot-distro login $DISTRO --user $USERNAME --shared-tmp -- env DISPLAY=:1.0 \1|" \
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
