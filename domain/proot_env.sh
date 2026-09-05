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

# -----------------------------------------------------------------------------
# proot-distro rootfs 경로 해석 (호출 시점 lazy — 레이아웃 자동 판별)
#   신규:   $PREFIX/var/lib/proot-distro/containers/<distro>/rootfs   (Python proot-distro)
#   레거시: $PREFIX/var/lib/proot-distro/installed-rootfs/<distro>    (구 bash proot-distro)
# 이미 설치된 경우 실제 존재하는 경로를 우선하고, 미설치(신규 설치 직전)에는
# proot-distro 구현으로 판별한다: Python 모듈이 있으면 신규, 없으면 레거시.
# 테스트/특수 환경은 PROOT_ROOTFS_BASE로 베이스 디렉토리를 override할 수 있다.
# -----------------------------------------------------------------------------
_proot_rootfs() {
    local base="${PROOT_ROOTFS_BASE:-$PREFIX/var/lib/proot-distro}"
    local new="${base}/containers/${PROOT_DISTRO}/rootfs"
    local legacy="${base}/installed-rootfs/${PROOT_DISTRO}"

    if [ -d "$new" ]; then
        printf '%s' "$new"
    elif [ -d "$legacy" ]; then
        printf '%s' "$legacy"
    elif command -v python3 >/dev/null 2>&1 && python3 -c 'import proot_distro' 2>/dev/null; then
        printf '%s' "$new"
    else
        printf '%s' "$legacy"
    fi
}

# -----------------------------------------------------------------------------
# Public API
# -----------------------------------------------------------------------------

setup_proot_install() {
    ui_info "${PROOT_DISTRO} proot-distro 설치"

    # 의존성 보강: --proot-only 모드는 setup_termux_base를 건너뛰므로
    # proot-distro 패키지가 없을 수 있다. 도메인이 자기 런타임 의존성을 보장.
    if ! command -v proot-distro >/dev/null 2>&1; then
        ui_info "proot-distro 패키지가 없어 먼저 설치합니다 (PKGS_TERMUX_PROOT)"
        pkg_update
        for _p in "${PKGS_TERMUX_PROOT[@]}"; do
            if pkg_is_installed "$_p"; then
                ui_info "  ${_p} — 이미 설치됨"
            else
                ui_info "  ${_p} 설치 중..."
                pkg_install "$_p"
            fi
        done
        unset _p
    fi

    # 이미 설치된 경우 건너뜀
    [ -d "$(_proot_rootfs)" ] && {
        ui_warn "${PROOT_DISTRO}가 이미 설치되어 있습니다. 건너뜁니다."
        return 0
    }
    proot_install "$PROOT_DISTRO"
}

setup_proot_update() {
    ui_info "${PROOT_DISTRO} 패키지 업데이트"
    # 사용자 생성 전 단계이므로 root로 실행
    proot_pkg_update_root
}

setup_proot_user() {
    local username="$PROOT_USER"
    ui_info "${PROOT_DISTRO} 사용자 생성: ${username}"

    local home_dir="$(_proot_rootfs)/home/${username}"
    [ -d "$home_dir" ] && {
        ui_warn "사용자 ${username}이 이미 존재합니다. 건너뜁니다."
        return 0
    }

    # 사용자 생성 전이므로 root로 실행
    proot_exec_root groupadd storage  2>/dev/null || true
    proot_exec_root groupadd wheel    2>/dev/null || true
    proot_exec_root useradd -m -g users -G wheel,audio,video,storage -s /bin/bash "$username"

    _setup_proot_sudoers "$username"

    # sudo가 base에 없을 수 있음 → 사용자 생성 직후 root로 설치
    # 이후 proot_exec sudo ... 이 작동하려면 sudo 바이너리가 필요
    proot_pkg_install_root sudo 2>/dev/null || true
}

setup_proot_base_packages() {
    ui_info "${PROOT_DISTRO} 기본 패키지 설치"

    # sudo가 base에 없으면 proot_pkg_install(sudo 기반) 자체가 실패
    # → root로 먼저 설치 후 sudoers ���구성
    proot_pkg_install_root sudo 2>/dev/null || true
    _setup_proot_sudoers "$PROOT_USER"

    # setup_proot_user가 멱등성으로 건너뛴 경우도 있으므로 여기서 항상 보장
    proot_pkg_update || true  # proot systemd hook 오류 무시

    # 패키지 목록 선택은 도메인 지식 (distro별 패키지명이 다름)
    case "$PROOT_DISTRO" in
        ubuntu)
            local -a _pkgs=("${PKGS_PROOT_UBUNTU_BASE[@]}" "${PKGS_PROOT_UBUNTU_DESKTOP[@]}")
            local _total=${#_pkgs[@]} _i=0
            for p in "${_pkgs[@]}"; do
                ((++_i))
                if proot_pkg_is_installed "$p"; then
                    ui_info "  (${_i}/${_total}) ${p} — 이미 설치됨"
                else
                    ui_info "  (${_i}/${_total}) ${p} 설치 중..."
                    # 개별 패키지의 apt 설치 실패로 나머지 base 패키지 설치가
                    # 전부 중단되지 않도록 경고 후 계속 진행 (archlinux 분기와 동일 패턴)
                    proot_pkg_install "$p" || \
                        echo "[WARN] $p: apt 설치 오류 (계속 진행)" >&2
                fi
            done
            ;;
        archlinux)
            local -a _pkgs=("${PKGS_PROOT_ARCH_BASE[@]}" "${PKGS_PROOT_ARCH_DESKTOP[@]}")
            local _total=${#_pkgs[@]} _i=0
            for p in "${_pkgs[@]}"; do
                ((++_i))
                if proot_pkg_is_installed "$p"; then
                    ui_info "  (${_i}/${_total}) ${p} — 이미 설치됨"
                else
                    ui_info "  (${_i}/${_total}) ${p} 설치 중..."
                    # proot 내부 systemd/udev hook 실패(exit 1)는 패키지 설치 자체와 무관 → 무시
                    proot_pkg_install "$p" || \
                        echo "[WARN] $p: pacman hook 오류 (패키지는 설치됨)" >&2
                fi
            done
            ;;
    esac
}

setup_proot_korean() {
    ui_info "${PROOT_DISTRO} 한글 환경 설정"

    case "$PROOT_DISTRO" in
        ubuntu)
            local _total=${#PKGS_PROOT_UBUNTU_KOREAN[@]} _i=0
            for p in "${PKGS_PROOT_UBUNTU_KOREAN[@]}"; do
                ((++_i))
                if proot_pkg_is_installed "$p"; then
                    ui_info "  (${_i}/${_total}) ${p} — 이미 설치됨"
                else
                    ui_info "  (${_i}/${_total}) ${p} 설치 중..."
                    proot_pkg_install "$p" || \
                        echo "[WARN] $p: apt 설치 오류 (계속 진행)" >&2
                fi
            done
            _install_ubuntu_nimf_deb
            _setup_ubuntu_korean_locale
            _setup_ubuntu_nimf
            ;;
        archlinux)
            local _total=${#PKGS_PROOT_ARCH_KOREAN[@]} _i=0
            for p in "${PKGS_PROOT_ARCH_KOREAN[@]}"; do
                ((++_i))
                if proot_pkg_is_installed "$p"; then
                    ui_info "  (${_i}/${_total}) ${p} — 이미 설치됨"
                else
                    ui_info "  (${_i}/${_total}) ${p} 설치 중..."
                    proot_pkg_install "$p" || \
                        echo "[WARN] $p: 설치 오류 (계속 진행)" >&2
                fi
            done
            _setup_arch_nimf_or_fcitx5
            _setup_arch_korean_locale
            ;;
    esac
}

setup_proot_env() {
    ui_info "${PROOT_DISTRO} 환경변수 설정"
    local rootfs; rootfs="$(_proot_rootfs)"
    local bashrc="${rootfs}/home/${PROOT_USER}/.bashrc"
    local profile_d="${rootfs}/etc/profile.d"
    local envfile="${profile_d}/termux-xfce-env.sh"

    # Termux Turnip(freedreno) Vulkan ICD 절대경로
    local _vk_icd="/data/data/com.termux/files/usr/share/vulkan/icd.d/freedreno_icd.aarch64.json"

    # 1) export 블록 → /etc/profile.d/
    #    prun <cmd>(= .desktop → prun-gui → prun)는 비대화형이라 .bashrc를 읽지 않는다
    #    (Ubuntu 기본 .bashrc도 비대화형이면 즉시 return). 로그인 셸이 읽는 /etc/profile은
    #    Ubuntu·Arch 모두 /etc/profile.d/*.sh를 source하고, 두 distro의 /etc/zsh/zprofile도
    #    `emulate sh -c 'source /etc/profile'` 하므로 bash/zsh 로그인 셸 모두 적용된다.
    #    전체가 생성 파일이므로 항상 덮어쓴다.
    mkdir -p "$profile_d"
    cat > "$envfile" << EOF
# Termux XFCE proot 환경변수 — Auto-generated by Termux XFCE installer (수동 수정 금지)
export DISPLAY=\${DISPLAY:-:0.0}
export XDG_RUNTIME_DIR=/run/user/\$(id -u)
mkdir -p "\$XDG_RUNTIME_DIR" 2>/dev/null
export MESA_NO_ERROR=1
export MESA_LOADER_DRIVER_OVERRIDE=zink    # proot는 Zink(OpenGL→Vulkan) 사용
export TU_DEBUG=noconform
export MESA_GL_VERSION_OVERRIDE=4.6COMPAT
export MESA_GLES_VERSION_OVERRIDE=3.2
export MESA_VK_WSI_PRESENT_MODE=immediate  # Vulkan 프레젠테이션 레이턴시 감소
export ZINK_DESCRIPTORS=lazy               # Zink 디스크립터 성능 최적화
export vblank_mode=0                       # vsync 비활성화 (FPS 측정용)
# Termux Turnip Vulkan ICD → proot Zink 백엔드 드라이버
export VK_ICD_FILENAMES="${_vk_icd}"
export VK_DRIVER_FILES="${_vk_icd}"        # Mesa 23+ 별칭
EOF

    # 2) .bashrc: 기존 생성 블록(마커 ~ code() 줄)을 먼저 제거 →
    #    멱등성 + 구버전(export/무가드 alias 포함) 설치본 마이그레이션. 사용자 라인은 보존된다.
    if [ -f "$bashrc" ] && grep -q '^# termux-xfce-proot-env$' "$bashrc"; then
        sed -i '/^# termux-xfce-proot-env$/,/^code() {/d' "$bashrc"
    fi

    cat >> "$bashrc" << 'EOF'

# termux-xfce-proot-env
[ -f /etc/profile.d/termux-xfce-env.sh ] && . /etc/profile.d/termux-xfce-env.sh
# aliases
alias hud='GALLIUM_HUD=fps '
command -v eza >/dev/null 2>&1 && alias ls='eza -lF --icons'
alias ll='ls -alhF'
alias shutdown='kill -9 -1'
command -v bat >/dev/null 2>&1 && alias cat='bat'
alias start='echo "Termux에서 실행하세요."'
code() { nohup dbus-run-session /usr/bin/code --no-sandbox "$@" >/dev/null 2>&1 & disown; }
EOF
}

setup_proot_timezone() {
    ui_info "${PROOT_DISTRO} 시간대 설정"
    local tz
    tz=$(getprop persist.sys.timezone 2>/dev/null || echo "Asia/Seoul")
    tz="${tz:-Asia/Seoul}"

    # /etc/localtime는 root 소유 → proot_exec_root 사용
    proot_exec_root rm -f /etc/localtime
    proot_exec_root ln -sf "/usr/share/zoneinfo/${tz}" /etc/localtime
}

setup_proot_fancybash() {
    local username="$PROOT_USER"
    ui_info "${PROOT_DISTRO} 프롬프트 설정"

    local dst="$(_proot_rootfs)/home/${username}/.fancybash.sh"
    [ -f "$dst" ] && return 0  # 멱등성

    _generate_proot_fancybash "$dst"

    local bashrc="$(_proot_rootfs)/home/${username}/.bashrc"
    grep -q "source.*\.fancybash\.sh" "$bashrc" 2>/dev/null || \
        echo "source ~/.fancybash.sh" >> "$bashrc"
}

setup_proot_hardware_accel() {
    # Termux 호스트의 mesa-vulkan-icd-freedreno를 VK_ICD_FILENAMES로 공유 (setup_proot_env 참조).
    # proot 내에는 확인용 유틸(glxinfo / vulkaninfo)만 설치.
    ui_info "${PROOT_DISTRO} GPU: Termux Turnip ICD 재사용 + 확인 유틸 설치"

    # 패키지 목록 선택은 도메인 지식 (distro별 패키지명이 다름)
    case "$PROOT_DISTRO" in
        ubuntu)
            proot_pkg_install mesa-utils vulkan-tools 2>/dev/null || \
                ui_warn "Ubuntu proot: mesa-utils/vulkan-tools 설치 실패 — 확인 유틸 없이 진행"
            ;;
        archlinux)
            # proot systemd hook 실패는 무시 (패키지 자체는 설치됨)
            proot_pkg_install mesa vulkan-tools mesa-demos 2>/dev/null || true
            ;;
    esac
    ui_info "${PROOT_DISTRO} proot GPU: Termux Turnip ICD → Zink 경로 활성화됨"
}

setup_proot_cursor_theme() {
    ui_info "${PROOT_DISTRO} 커서 테마(dist-dark) 적용"
    local src="$PREFIX/share/icons/dist-dark"
    local dst="$(_proot_rootfs)/usr/share/icons/dist-dark"

    [ -d "$dst" ] && return 0

    # 의존성 보강: --proot-only 모드는 setup_xfce_theme를 건너뛰므로 dist-dark가 없을 수 있다.
    # _install_fluent_cursor가 로드돼 있으면 자동 다운로드 (xfce_env.sh와 함께 source된 경우).
    if [ ! -d "$src" ] && declare -F _install_fluent_cursor >/dev/null 2>&1; then
        ui_info "  dist-dark 미존재 → _install_fluent_cursor 자동 호출"
        _install_fluent_cursor || true
    fi

    # 여전히 없으면 cosmetic 실패이므로 경고 후 skip (set -e에서 distro 전체 중단 방지)
    [ -d "$src" ] || {
        ui_warn "dist-dark 커서 테마를 준비하지 못했습니다 — 커서 테마 적용을 건너뜁니다."
        return 0
    }

    cp -r "$src" "$dst"

    local xresources="$(_proot_rootfs)/home/${PROOT_USER}/.Xresources"
    grep -q "Xcursor.theme" "$xresources" 2>/dev/null || \
        echo "Xcursor.theme: dist-dark" >> "$xresources"
}

setup_proot_conky() {
    ui_info "${PROOT_DISTRO} Conky 설정 복사"
    local username="$PROOT_USER"
    local config_dst="$(_proot_rootfs)/home/${username}/.config"

    if [ ! -d "${config_dst}/conky" ]; then
        mkdir -p "$config_dst"

        # install.sh:28-35이 curl-pipe 실행을 git clone으로 재시작하므로 SCRIPT_DIR은 항상 존재
        # (과거엔 conky.tar.gz wget 폴백이 있었으나 해당 아티팩트 미발행 → 제거)
        local conky_src="${SCRIPT_DIR}/tar/conky/.config"
        if [ -d "$conky_src" ]; then
            cp -rn "$conky_src/." "$config_dst/"
        else
            ui_warn "conky 소스 디렉토리를 찾을 수 없습니다: ${conky_src}"
        fi

        # 이모지 폰트 복사
        local emoji_src="$HOME/.fonts/NotoColorEmoji-Regular.ttf"
        local emoji_dst="$(_proot_rootfs)/home/${username}/.fonts/"
        mkdir -p "$emoji_dst"
        [ -f "$emoji_src" ] && cp "$emoji_src" "$emoji_dst"
    fi

    # *.sh 실행권한 보정 (항상 실행 — git index가 100755로 반영되기 전 구버전 설치본 커버)
    find "${config_dst}/conky" -type f -name "*.sh" -exec chmod +x {} + 2>/dev/null || true

    # 구버전 Alterf.conf의 `backend = "glx";` 제거 (conky가 인식 못해 경고 유발)
    local alterf="${config_dst}/conky/Alterf/Alterf.conf"
    if [ -f "$alterf" ] && grep -q '^\s*backend\s*=' "$alterf" 2>/dev/null; then
        sed -i '/^\s*backend\s*=/d' "$alterf"
    fi
}

# proot 제거 (테스트용 distro 정리)
# 사용법: PROOT_DISTRO=ubuntu PROOT_USER=<username> bash -c 'source domain/proot_env.sh && teardown_proot'
teardown_proot() {
    local distro="${PROOT_DISTRO:?PROOT_DISTRO 필요}"
    local user="${PROOT_USER:-}"

    ui_info "${distro} proot 제거 중..."

    # rootfs 제거
    proot_remove "$distro"

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

setup_proot_alias() {
    local distro="$PROOT_DISTRO"
    local user="$PROOT_USER"
    [ -z "$distro" ] && return 0

    # PROOT_SHELL: alias 사용 시점에 서브셸에서 config를 읽어 인터랙티브 셸 결정
    # (bash|zsh, 기본 bash). 설치 후 사용자가 config의 PROOT_SHELL을 바꾸면 즉시 반영되고,
    # 서브셸이라 config의 다른 변수는 사용자 셸로 새지 않는다.
    local _proot_alias="alias ${distro}='proot-distro login ${distro} --user ${user} --shared-tmp -- env -u LD_PRELOAD \"\$(. \"\$HOME/.config/termux-xfce/config\" 2>/dev/null; echo \"\${PROOT_SHELL:-bash}\")\" --login'"

    local bashrc="$PREFIX/etc/bash.bashrc"
    grep -q "alias ${distro}=" "$bashrc" 2>/dev/null || echo "$_proot_alias" >> "$bashrc"

    if [ -f "$HOME/.zshrc" ]; then
        grep -q "alias ${distro}=" "$HOME/.zshrc" 2>/dev/null || echo "$_proot_alias" >> "$HOME/.zshrc"
    fi
}

# -----------------------------------------------------------------------------
# Private
# -----------------------------------------------------------------------------

_generate_proot_fancybash() {
    local dst="$1"
    local icon_hex color
    case "$PROOT_DISTRO" in
        archlinux) icon_hex='\uf303'; color='75'  ;;   #  Arch blue
        ubuntu)    icon_hex='\uf31b'; color='208' ;;   #  Ubuntu orange
        *)         icon_hex='\uf17c'; color='34'  ;;   #  Linux tux
    esac

    local icon_char git_icon
    printf -v icon_char "$icon_hex"
    printf -v git_icon '\ue0a0'

    cat > "$dst" << FANCYBASH
# fancybash — proot prompt (${PROOT_DISTRO})
# Auto-generated by Termux XFCE installer

__git_branch() {
    local b
    b=\$(git symbolic-ref --short HEAD 2>/dev/null || git rev-parse --short HEAD 2>/dev/null)
    [ -n "\$b" ] && printf ' \001\033[38;5;203m\002${git_icon} %s\001\033[0m\002' "\$b"
}

PROMPT_COMMAND='__proot_ps1'
__proot_ps1() {
    local ec=\$?
    local R='\[\e[0m\]'
    local B='\[\e[1m\]'
    local C='\[\e[38;5;${color}m\]'
    local G='\[\e[38;5;114m\]'
    local D='\[\e[38;5;244m\]'
    local A='\[\e[38;5;75m\]'
    local E='\[\e[38;5;203m\]'

    local p="\${C}❯\${R}"
    [ \$ec -ne 0 ] && p="\${E}❯\${R}"

    PS1="\${B}\${C}${icon_char} \${R}\${G}\u\${D}@\${C}${PROOT_DISTRO}\${R} \${B}\${A}\w\${R}\$(__git_branch) \${p} "
}
FANCYBASH
}

_setup_proot_sudoers() {
    local username="$1"
    local sudoers="$(_proot_rootfs)/etc/sudoers"
    local sudoers_d="$(_proot_rootfs)/etc/sudoers.d"

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
    local profile="$(_proot_rootfs)/home/${PROOT_USER}/.profile"
    grep -q "# termux-xfce-korean" "$profile" 2>/dev/null && return 0

    cat >> "$profile" << 'EOF'

# termux-xfce-korean
LANG=ko_KR.UTF-8
LANGUAGE=ko_KR.UTF-8
LC_ALL=ko_KR.UTF-8
export GTK_IM_MODULE=nimf
export QT_IM_MODULE=nimf
export XMODIFIERS="@im=nimf"
command -v nimf >/dev/null 2>&1 && ! pgrep -x nimf >/dev/null 2>&1 && { nimf & disown; } 2>/dev/null
EOF

    # /etc/default/locale
    cat > "$(_proot_rootfs)/etc/default/locale" << 'EOF'
LANG=ko_KR.UTF-8
LANGUAGE=ko_KR.UTF-8
EOF
}

_install_ubuntu_nimf_deb() {
    # nimf이 Ubuntu 공식 repo에 없으므로 GitHub Releases .deb 직접 설치
    proot_exec bash -c "command -v nimf &>/dev/null" && return 0

    # nimf 런타임 의존성 (Ubuntu 패키지명 — 어떤 패키지가 필요한지는 도메인 지식)
    proot_pkg_install libglib2.0-0 libgtk-3-0 libdbus-1-3 2>/dev/null || true

    local deb
    local -a urls=()
    for deb in "${NIMF_DEBS[@]}"; do
        urls+=("${NIMF_DEB_BASE_URL}/${deb}|${NIMF_DEB_SHA256[$deb]:-}")
    done
    proot_pkg_install_deb_url "${urls[@]}"

    proot_exec bash -c "command -v nimf &>/dev/null" || \
        ui_warn "nimf 설치 실패 — 한글 입력기가 동작하지 않을 수 있습니다"
}

_setup_ubuntu_nimf() {
    # im-config로 nimf을 기본 입력기로 설정
    proot_exec bash -c "im-config -n nimf 2>/dev/null || true"
}

_setup_arch_nimf_or_fcitx5() {
    # nimf AUR 빌드 시도 → 실패 시 fcitx5 폴백
    local use_nimf=false

    ui_info "Arch: nimf AUR 빌드 시도 (실패 시 fcitx5 폴백)"
    if proot_ensure_aur_helper; then
        local nimf_ok=true
        for p in "${PKGS_PROOT_ARCH_KOREAN_NIMF[@]}"; do
            proot_pkg_is_installed "$p" && continue
            proot_aur_install "$p" 2>/dev/null || { nimf_ok=false; break; }
        done
        $nimf_ok && use_nimf=true
    fi

    if ! $use_nimf; then
        ui_warn "nimf AUR 빌드 실패 → fcitx5로 폴백"
        local _total=${#PKGS_PROOT_ARCH_KOREAN_FCITX5[@]} _i=0
        for p in "${PKGS_PROOT_ARCH_KOREAN_FCITX5[@]}"; do
            ((++_i))
            if proot_pkg_is_installed "$p"; then
                ui_info "  (${_i}/${_total}) ${p} — 이미 설치됨"
            else
                ui_info "  (${_i}/${_total}) ${p} 설치 중..."
                proot_pkg_install "$p" || \
                    echo "[WARN] $p: 설치 오류 (계속 진행)" >&2
            fi
        done
    fi

    _write_arch_im_env "$use_nimf"
}

_write_arch_im_env() {
    local use_nimf="$1"
    local profile="$(_proot_rootfs)/home/${PROOT_USER}/.profile"
    grep -q "# termux-xfce-korean" "$profile" 2>/dev/null && return 0

    if $use_nimf; then
        cat >> "$profile" << 'EOF'

# termux-xfce-korean
LANG=ko_KR.UTF-8
LANGUAGE=ko_KR.UTF-8
LC_ALL=ko_KR.UTF-8
export GTK_IM_MODULE=nimf
export QT_IM_MODULE=nimf
export XMODIFIERS="@im=nimf"
command -v nimf >/dev/null 2>&1 && ! pgrep -x nimf >/dev/null 2>&1 && { nimf & disown; } 2>/dev/null
EOF
    else
        cat >> "$profile" << 'EOF'

# termux-xfce-korean
LANG=ko_KR.UTF-8
LANGUAGE=ko_KR.UTF-8
LC_ALL=ko_KR.UTF-8
export GTK_IM_MODULE=fcitx5
export QT_IM_MODULE=fcitx5
export XMODIFIERS="@im=fcitx5"
{ fcitx5 -d --replace 2>/dev/null & disown; } 2>/dev/null
EOF
    fi
}

_setup_arch_korean_locale() {
    local locale_gen="$(_proot_rootfs)/etc/locale.gen"
    grep -q "ko_KR.UTF-8" "$locale_gen" 2>/dev/null || \
        echo "ko_KR.UTF-8 UTF-8" >> "$locale_gen"
    proot_exec_root locale-gen
}
