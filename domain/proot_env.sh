#!/data/data/com.termux/files/usr/bin/bash
# =============================================================================
# DOMAIN: proot_env.sh
# -----------------------------------------------------------------------------
# proot-distro 환경 구성 도메인 로직
# - Ubuntu / Arch Linux 공통 로직
# - distro별 차이는 어댑터(pkg_ubuntu.sh / pkg_arch.sh)가 흡수
# - 기존 proot.sh + ubuntu_etc.sh 통합
# 환경변수: PROOT_DISTRO, PROOT_USER 필요
# =============================================================================

readonly PROOT_ROOTFS="$PREFIX/var/lib/proot-distro/installed-rootfs"

# -----------------------------------------------------------------------------
# Public API
# -----------------------------------------------------------------------------

setup_proot_install() {
    ui_info "${PROOT_DISTRO} proot-distro 설치"
    # 이미 설치된 경우 건너뜀
    [ -d "${PROOT_ROOTFS}/${PROOT_DISTRO}" ] && {
        ui_warn "${PROOT_DISTRO}가 이미 설치되어 있습니다. 건너뜁니다."
        return 0
    }
    proot-distro install "$PROOT_DISTRO"
}

setup_proot_update() {
    ui_info "${PROOT_DISTRO} 패키지 업데이트"
    # 사용자 생성 전 단계이므로 root로 실행
    case "$PROOT_DISTRO" in
        ubuntu)
            proot_exec_root apt update
            proot_exec_root apt upgrade -y -o Dpkg::Options::="--force-confold"
            ;;
        archlinux)
            proot_exec_root pacman -Syu --noconfirm
            ;;
    esac
}

setup_proot_user() {
    local username="$PROOT_USER"
    ui_info "${PROOT_DISTRO} 사용자 생성: ${username}"

    local home_dir="${PROOT_ROOTFS}/${PROOT_DISTRO}/home/${username}"
    [ -d "$home_dir" ] && {
        ui_warn "사용자 ${username}이 이미 존재합니다. 건너뜁니다."
        return 0
    }

    # 사용자 생성 전이므로 root로 실행
    proot_exec_root groupadd storage  2>/dev/null || true
    proot_exec_root groupadd wheel    2>/dev/null || true
    proot_exec_root useradd -m -g users -G wheel,audio,video,storage -s /bin/bash "$username"

    _setup_proot_sudoers "$username"

    # Arch: sudo가 base에 없음 → 사용자 생성 직후 root로 설치
    # 이후 proot_exec sudo pacman ... 이 작동하려면 sudo 바이너리가 필요
    case "${PROOT_DISTRO}" in
        archlinux)
            proot_exec_root pacman -S --noconfirm --needed sudo 2>/dev/null || true
            ;;
    esac
}

setup_proot_base_packages() {
    ui_info "${PROOT_DISTRO} 기본 패키지 설치"

    case "$PROOT_DISTRO" in
        ubuntu)
            for p in "${PKGS_PROOT_UBUNTU_BASE[@]}" "${PKGS_PROOT_UBUNTU_DESKTOP[@]}"; do
                proot_pkg_is_installed "$p" || proot_pkg_install "$p"
            done
            ;;
        archlinux)
            # proot_pkg_install 이 "sudo pacman" 을 쓰므로 sudo 바이너리가 먼저 필요.
            # setup_proot_user 가 멱등성으로 건너뛴 경우도 있으므로 여기서 항상 보장.
            proot_exec_root pacman -S --noconfirm --needed sudo 2>/dev/null || true
            # sudo 설치 후 sudoers 재구성 (wheel NOPASSWD + 유저 직접 항목)
            _setup_proot_sudoers "$PROOT_USER"
            proot_pkg_update || true  # proot systemd hook 오류 무시
            for p in "${PKGS_PROOT_ARCH_BASE[@]}" "${PKGS_PROOT_ARCH_DESKTOP[@]}"; do
                # proot 내부 systemd/udev hook 실패(exit 1)는 패키지 설치 자체와 무관 → 무시
                proot_pkg_is_installed "$p" || proot_pkg_install "$p" || \
                    echo "[WARN] $p: pacman hook 오류 (패키지는 설치됨)" >&2
            done
            ;;
    esac
}

setup_proot_korean() {
    ui_info "${PROOT_DISTRO} 한글 환경 설정"

    case "$PROOT_DISTRO" in
        ubuntu)
            for p in "${PKGS_PROOT_UBUNTU_KOREAN[@]}"; do
                proot_pkg_is_installed "$p" || proot_pkg_install "$p"
            done
            _setup_ubuntu_korean_locale
            _setup_ubuntu_nimf
            ;;
        archlinux)
            for p in "${PKGS_PROOT_ARCH_KOREAN[@]}"; do
                proot_pkg_is_installed "$p" || proot_pkg_install "$p" || \
                    echo "[WARN] $p: 설치 오류 (계속 진행)" >&2
            done
            _setup_arch_korean_locale
            ;;
    esac
}

setup_proot_env() {
    ui_info "${PROOT_DISTRO} 환경변수 설정"
    local bashrc="${PROOT_ROOTFS}/${PROOT_DISTRO}/home/${PROOT_USER}/.bashrc"

    grep -q "# termux-xfce-proot-env" "$bashrc" 2>/dev/null && return 0

    # Termux Turnip(freedreno) Vulkan ICD 절대경로
    local _vk_icd="/data/data/com.termux/files/usr/share/vulkan/icd.d/freedreno_icd.aarch64.json"

    cat >> "$bashrc" << EOF

# termux-xfce-proot-env
export DISPLAY=\${DISPLAY:-:1.0}
export LD_PRELOAD=/system/lib64/libskcodec.so
export XDG_RUNTIME_DIR=/run/user/\$(id -u)
export MESA_NO_ERROR=1
export MESA_LOADER_DRIVER_OVERRIDE=zink    # proot는 Zink(OpenGL→Vulkan) 사용
export TU_DEBUG=noconform
export MESA_GL_VERSION_OVERRIDE=4.6COMPAT
export MESA_GLES_VERSION_OVERRIDE=3.2
export MESA_VK_WSI_PRESENT_MODE=immediate  # Vulkan 프레젠테이션 레이턴시 감소
export ZINK_DESCRIPTORS=lazy               # Zink 디스크립터 성능 최적화
export vblank_mode=0                       # vsync 비활성화 (FPS 측정용)
# Termux Turnip Vulkan ICD → proot Zink 백엔드 드라이버
export VK_ICD_FILENAMES=${_vk_icd}
export VK_DRIVER_FILES=${_vk_icd}          # Mesa 23+ 별칭

# aliases
alias hud='GALLIUM_HUD=fps '
alias ls='eza -lF --icons'
alias ll='ls -alhF'
alias shutdown='kill -9 -1'
alias cat='bat'
alias python='/usr/bin/python3'
alias pip='/usr/bin/pip'
alias start='echo "Termux에서 실행하세요."'
EOF
}

setup_proot_timezone() {
    ui_info "${PROOT_DISTRO} 시간대 설정"
    local tz
    tz=$(getprop persist.sys.timezone 2>/dev/null || echo "Asia/Seoul")

    proot_exec rm -f /etc/localtime
    proot_exec ln -sf "/usr/share/zoneinfo/${tz}" /etc/localtime
}

setup_proot_fancybash() {
    local username="$PROOT_USER"
    local distro_label="${PROOT_DISTRO}"
    ui_info "${PROOT_DISTRO} fancybash 설정"

    local src="$HOME/.fancybash.sh"
    local dst="${PROOT_ROOTFS}/${PROOT_DISTRO}/home/${username}/.fancybash.sh"

    [ -f "$src" ] || {
        ui_warn "Termux의 .fancybash.sh가 없습니다. setup_xfce_fancybash를 먼저 실행하세요."
        return 1
    }

    [ -f "$dst" ] && return 0  # 멱등성

    cp "$src" "$dst"
    # 호스트명을 distro명으로 변경
    sed -i "s/termux/${distro_label}/" "$dst"

    local bashrc="${PROOT_ROOTFS}/${PROOT_DISTRO}/home/${username}/.bashrc"
    grep -q "source.*\.fancybash\.sh" "$bashrc" 2>/dev/null || \
        echo "source ~/.fancybash.sh" >> "$bashrc"
}

setup_proot_hardware_accel() {
    ui_info "${PROOT_DISTRO} GPU 가속(mesa-vulkan-kgsl) 설치"

    case "$PROOT_DISTRO" in
        ubuntu)
            # Adreno 세대 확인: 8xx는 구형 deb 비호환 → Zink 사용
            local gpu_model
            gpu_model=$(cat /sys/class/kgsl/kgsl-3d0/gpu_model 2>/dev/null || echo "")
            if [[ "$gpu_model" =~ [Aa]dreno.*8[0-9]{2} ]]; then
                ui_warn "Adreno 8xx 감지 — 구형 kgsl deb 미지원. Zink(MESA_LOADER_DRIVER_OVERRIDE=zink) 사용."
                ui_warn "최신 드라이버: https://github.com/lfdevs/mesa-for-android-container"
                return 0
            fi

            local deb="mesa-vulkan-kgsl_24.1.0-devel-20240120_arm64.deb"
            local url="https://github.com/yanghoeg/Termux_XFCE/raw/main/${deb}"

            if proot_exec bash -c "
                wget -q '${url}' -O /tmp/${deb} &&
                apt install -y /tmp/${deb} &&
                rm -f /tmp/${deb}
            "; then
                ui_info "mesa-vulkan-kgsl 설치 완료 (Adreno 6xx/7xx KGSL 드라이버)"
            else
                ui_warn "kgsl deb 설치 실패 — Zink(소프트웨어) 폴백으로 계속 진행합니다."
            fi
            ;;
        archlinux)
            ui_info "Arch proot: Zink + Termux Turnip ICD 설정"
            # mesa-demos (glxinfo/glxgears) + vulkan-tools 설치
            # proot systemd hook 실패는 무시 (패키지 자체는 설치됨)
            proot_exec sudo pacman -S --noconfirm --needed \
                mesa vulkan-tools mesa-demos 2>/dev/null || true
            # VK_ICD_FILENAMES는 setup_proot_env()의 .bashrc에서 이미 설정됨
            ui_info "Arch proot GPU: Termux Turnip ICD → Zink 경로 활성화됨"
            ;;
    esac
}

setup_proot_cursor_theme() {
    ui_info "${PROOT_DISTRO} 커서 테마(dist-dark) 적용"
    local src="$PREFIX/share/icons/dist-dark"
    local dst="${PROOT_ROOTFS}/${PROOT_DISTRO}/usr/share/icons/dist-dark"

    [ -d "$dst" ] && return 0
    [ -d "$src" ] || {
        ui_warn "dist-dark 커서 테마가 없습니다. setup_xfce_theme를 먼저 실행하세요."
        return 1
    }

    cp -r "$src" "$dst"

    local xresources="${PROOT_ROOTFS}/${PROOT_DISTRO}/home/${PROOT_USER}/.Xresources"
    grep -q "Xcursor.theme" "$xresources" 2>/dev/null || \
        echo "Xcursor.theme: dist-dark" >> "$xresources"
}

setup_proot_conky() {
    ui_info "${PROOT_DISTRO} Conky 설정 복사"
    local username="$PROOT_USER"
    local config_dst="${PROOT_ROOTFS}/${PROOT_DISTRO}/home/${username}/.config"

    [ -d "${config_dst}/conky" ] && return 0  # 멱등성

    mkdir -p "$config_dst"

    local conky_src="${SCRIPT_DIR:-}/tar/conky/.config"
    if [ -d "$conky_src" ]; then
        # 로컬 repo에서 직접 복사
        cp -rn "$conky_src/." "$config_dst/"
    else
        # curl 파이프 실행 시 원격 다운로드
        local repo_base="https://github.com/yanghoeg/Termux_XFCE/raw/main"
        local tmp="${HOME}/.cache/termux-xfce-install"
        mkdir -p "$tmp"
        wget -q "${repo_base}/conky.tar.gz" -O "${tmp}/conky.tar.gz"
        local tmpextract
        tmpextract=$(mktemp -d "${tmp}/conky-XXXXXX")
        tar -xzf "${tmp}/conky.tar.gz" -C "$tmpextract"
        rm -f "${tmp}/conky.tar.gz"
        [ -d "${tmpextract}/.config/conky" ]    && cp -r "${tmpextract}/.config/conky"    "$config_dst/"
        [ -d "${tmpextract}/.config/neofetch" ] && cp -r "${tmpextract}/.config/neofetch" "$config_dst/"
        rm -rf "$tmpextract"
    fi

    # 이모지 폰트 복사
    local emoji_src="$HOME/.fonts/NotoColorEmoji-Regular.ttf"
    local emoji_dst="${PROOT_ROOTFS}/${PROOT_DISTRO}/home/${username}/.fonts/"
    mkdir -p "$emoji_dst"
    [ -f "$emoji_src" ] && cp "$emoji_src" "$emoji_dst"
}

# proot 제거 (테스트용 distro 정리)
# 사용법: PROOT_DISTRO=ubuntu PROOT_USER=yanghoeg bash -c 'source domain/proot_env.sh && teardown_proot'
teardown_proot() {
    local distro="${PROOT_DISTRO:?PROOT_DISTRO 필요}"
    local user="${PROOT_USER:-}"

    ui_info "${distro} proot 제거 중..."

    # rootfs 제거
    proot-distro remove "$distro" 2>/dev/null || true

    # bash.bashrc alias 제거
    local bashrc="$PREFIX/etc/bash.bashrc"
    sed -i "/alias ${distro}=/d" "$bashrc" 2>/dev/null || true

    # ~/.zshrc alias 제거
    if [ -f "$HOME/.zshrc" ]; then
        sed -i "/alias ${distro}=/d" "$HOME/.zshrc" 2>/dev/null || true
    fi

    # 설정 파일에서 distro 항목 제거
    local cfg="$HOME/.config/termux-xfce/config"
    if [ -f "$cfg" ] && grep -q "^PROOT_DISTRO=\"${distro}\"" "$cfg"; then
        sed -i "s/^PROOT_DISTRO=\"${distro}\"/PROOT_DISTRO=\"\"/" "$cfg"
        sed -i "s/^PROOT_USER=\"${user}\"/PROOT_USER=\"\"/" "$cfg"
    fi

    ui_info "${distro} 제거 완료."
}

# -----------------------------------------------------------------------------
# Private
# -----------------------------------------------------------------------------

_setup_proot_sudoers() {
    local username="$1"
    local sudoers="${PROOT_ROOTFS}/${PROOT_DISTRO}/etc/sudoers"
    local sudoers_d="${PROOT_ROOTFS}/${PROOT_DISTRO}/etc/sudoers.d"

    if [ ! -f "$sudoers" ]; then
        # sudo 미설치(Arch 기본): sudoers.d에 미리 작성 → sudo 설치 후 활성화
        mkdir -p "$sudoers_d"
        echo "${username} ALL=(ALL) NOPASSWD:ALL" > "${sudoers_d}/${username}"
        chmod 440 "${sudoers_d}/${username}"
        return 0
    fi

    # /etc/sudoers 존재: wheel 그룹 NOPASSWD 활성화 + 유저 직접 추가
    chmod u+rw "$sudoers"

    # Arch: "# %wheel ALL=(ALL:ALL) NOPASSWD: ALL" 주석 해제
    sed -i 's/^#[[:space:]]*%wheel[[:space:]]*ALL=(ALL:ALL)[[:space:]]*NOPASSWD:/%wheel ALL=(ALL:ALL) NOPASSWD:/' "$sudoers"
    # Ubuntu: "# %wheel ALL=(ALL) NOPASSWD:ALL"
    sed -i 's/^#[[:space:]]*%wheel[[:space:]]*ALL=(ALL)[[:space:]]*NOPASSWD:/%wheel ALL=(ALL) NOPASSWD:/' "$sudoers"

    # 유저 직접 항목 (wheel 그룹 설정 없을 때 폴백)
    grep -q "^${username}" "$sudoers" || \
        echo "${username} ALL=(ALL) NOPASSWD:ALL" >> "$sudoers"

    chmod 440 "$sudoers"
}

_setup_ubuntu_korean_locale() {
    local profile="${PROOT_ROOTFS}/${PROOT_DISTRO}/home/${PROOT_USER}/.profile"
    grep -q "# termux-xfce-korean" "$profile" 2>/dev/null && return 0

    cat >> "$profile" << 'EOF'

# termux-xfce-korean
LANG=ko_KR.UTF-8
LANGUAGE=ko_KR.UTF-8
LC_ALL=ko_KR.UTF-8
export GTK_IM_MODULE=nimf
export QT_IM_MODULE=nimf
export XMODIFIERS="@im=nimf"
nimf
EOF

    # /etc/default/locale
    cat > "${PROOT_ROOTFS}/${PROOT_DISTRO}/etc/default/locale" << 'EOF'
LANG=ko_KR.UTF-8
LANGUAGE=ko_KR.UTF-8
EOF
}

_setup_ubuntu_nimf() {
    # 하모니카 repo 추가 후 nimf 설치
    proot_exec bash -c "
        wget -qO- https://update.hamonikr.org/add-update-repo.apt | bash - 2>/dev/null || true
        apt install -y nimf nimf-libhangul 2>/dev/null || true
        im-config -n nimf 2>/dev/null || true
    "
}

_setup_arch_korean_locale() {
    local locale_gen="${PROOT_ROOTFS}/${PROOT_DISTRO}/etc/locale.gen"
    grep -q "ko_KR.UTF-8" "$locale_gen" 2>/dev/null || \
        echo "ko_KR.UTF-8 UTF-8" >> "$locale_gen"
    proot_exec locale-gen
}
