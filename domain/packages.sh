#!/data/data/com.termux/files/usr/bin/bash
# =============================================================================
# DOMAIN: packages.sh
# -----------------------------------------------------------------------------
# 패키지 정의 레이어 — "무엇"을 설치할지만 정의
# 어떤 패키지 매니저로 설치할지는 어댑터가 결정
# =============================================================================

# -----------------------------------------------------------------------------
# Termux Native 패키지 (항상 설치)
# -----------------------------------------------------------------------------

# 기본 유틸리티
PKGS_TERMUX_BASE=(
    wget
    unzip
    which
    ncurses-utils
    dbus
    pulseaudio
    yad            # app-installer 검색 가능 GUI (zenity 대체)
)

# XFCE 데스크탑 환경
PKGS_TERMUX_XFCE=(
    xfce4
    xfce4-goodies
    firefox
    flameshot          # 스크린샷 — native 필수 (proot에선 dbus EXTERNAL auth UID 불일치로 작동 불가)
    papirus-icon-theme
    termux-x11-nightly
    libuv
    wmctrl
    pavucontrol-qt
    fontconfig-utils   # fc-cache/fc-match: Nerd Font 폰트 캐시 갱신용 (xfce 의존성에 미포함)
    libsimdutf         # libvte(xfce4-terminal) 런타임 의존성 (Termux 26.x+에서 자동 pull 안 됨)
)

# CLI 강화 도구
PKGS_TERMUX_CLI=(
    git
    zsh
    eza
    bat
    fzf
    ripgrep
    fd
    zoxide
    lazygit
    starship
    atuin
    htop
    jq
    netcat-openbsd
    neofetch
)

# 한글 입력기
PKGS_TERMUX_KOREAN=(
    fcitx5
    fcitx5-hangul
    fcitx5-configtool
    libhangul
    libhangul-static
)

# GPU 가속 (Adreno/Turnip + Zink)
# mesa 26.x (메인 저장소)에 zink_dri.so 내장 — TUR의 mesa-zink/osmesa-zink 불필요
# mesa-zink(TUR)는 mesa와 Conflicts/Replaces 관계라 설치 시 xfce4 의존성 체인이 깨짐
PKGS_TERMUX_GPU=(
    mesa                           # OpenGL (zink_dri.so 내장) — 메인 저장소 26.x
    mesa-dev
    mesa-demos
    mesa-vulkan-icd-freedreno      # Turnip Vulkan 드라이버 (Adreno Zink 백엔드)
    vulkan-loader-generic          # Vulkan 로더
    mesa-vulkan-icd-swrast         # 소프트웨어 Vulkan 폴백
)

# GPU 개발 도구 (선택적)
PKGS_TERMUX_GPU_DEV=(
    clvk
    clinfo
    gtkmm4
    libsigc++-3.0
    libcairomm-1.16
    libglibmm-2.68
    libpangomm-2.48
    swig
    libpeas
)

# proot-distro 설치에 필요한 Termux 패키지
PKGS_TERMUX_PROOT=(
    proot-distro
    x11-repo
    tur-repo
)

# -----------------------------------------------------------------------------
# proot Ubuntu 패키지 (Ubuntu 선택 시)
# -----------------------------------------------------------------------------

PKGS_PROOT_UBUNTU_BASE=(
    sudo
    wget
    jq
    curl
    vim
    nano
    htop
    psmisc
    apt-utils
    dialog
    aptitude
)

PKGS_PROOT_UBUNTU_DESKTOP=(
    # flameshot: Termux native로 이동 (proot dbus EXTERNAL auth UID 불일치)
    conky-all
    zenity
    onboard
    x11-apps
    glmark2
)

PKGS_PROOT_UBUNTU_KOREAN=(
    language-pack-ko
    language-pack-gnome-ko-base
    locales
    fonts-nanum-extra
    fonts-noto-cjk
    fonts-roboto
    im-config
    # nimf: Ubuntu 공식 repo 미제공 → _install_ubuntu_nimf_deb()으로 직접 설치
)

# nimf GitHub Releases ARM64 .deb (Ubuntu 24.04 빌드 — 25.10에서도 호환)
NIMF_DEB_BASE_URL="https://github.com/hamonikr/nimf/releases/download/v1.4.17"
NIMF_DEBS=(
    "nimf_1.4.17_arm64-ubuntu.2404.arm64.deb"
    "nimf-i18n_1.4.17_arm64-ubuntu.2404.arm64.deb"
)

PKGS_PROOT_UBUNTU_DEV=(
    python3
    python3-pip
    gh
    meson
    ninja-build
    build-essential
)

# -----------------------------------------------------------------------------
# proot Arch Linux 패키지 (Arch 선택 시)
# -----------------------------------------------------------------------------

PKGS_PROOT_ARCH_BASE=(
    sudo
    wget
    jq
    curl
    vim
    nano
    htop
    base-devel
)

PKGS_PROOT_ARCH_DESKTOP=(
    # flameshot: Termux native로 이동 (proot dbus EXTERNAL auth UID 불일치)
    conky
    zenity
    onboard
    xorg-xeyes   # x11-apps 대체
    mesa-demos   # glxinfo/glxgears — GPU 가속 테스트
    vulkan-tools # vulkaninfo — Vulkan 가속 확인
)

PKGS_PROOT_ARCH_KOREAN=(
    noto-fonts-cjk   # 한국어 폰트 (공식 repo)
    # ttf-nanum: AUR 전용 → noto-fonts-cjk로 대체
    libhangul
)

# Arch nimf: AUR 빌드 (yay) → 실패 시 fcitx5 폴백
PKGS_PROOT_ARCH_KOREAN_NIMF=(
    nimf
    nimf-libhangul
)

PKGS_PROOT_ARCH_KOREAN_FCITX5=(
    fcitx5-hangul
    fcitx5-configtool
)

PKGS_PROOT_ARCH_DEV=(
    python
    python-pip
    github-cli
    meson
    ninja
)
