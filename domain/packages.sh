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
)

# XFCE 데스크탑 환경
PKGS_TERMUX_XFCE=(
    xfce4
    xfce4-goodies
    firefox
    papirus-icon-theme
    termux-x11-nightly
    libuv
    wmctrl
    pavucontrol-qt
)

# CLI 강화 도구
PKGS_TERMUX_CLI=(
    git
    eza
    bat
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
# 패키지명: Termux 26.x 기준 (2025년 이후 최신 메인라인 Mesa 반영)
# DRI3 지원: Termux:X11 최신 + mesa-vulkan-icd-freedreno 24.1+ 조합으로 활성화
PKGS_TERMUX_GPU=(
    mesa-zink                      # OpenGL → Vulkan 레이어 (Zink 드라이버)
    mesa-dev
    mesa-demos
    osmesa-zink                    # osmosa → osmesa-zink 로 이름 변경
    mesa-vulkan-icd-freedreno      # Turnip Vulkan 드라이버 (DRI3 포함, -dri3 패키지 폐기됨)
    vulkan-loader-generic          # vulkan-loader-android → vulkan-loader-generic
    mesa-vulkan-icd-swrast         # 소프트웨어 Vulkan 폴백 (lavapipe → swrast)
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
    flameshot
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
    nimf
    nimf-libhangul
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
    flameshot
    conky
    zenity
    onboard
    xorg-xeyes   # x11-apps 대체
)

PKGS_PROOT_ARCH_KOREAN=(
    noto-fonts-cjk
    ttf-nanum
    fcitx5-hangul
    fcitx5-configtool
    libhangul
)

PKGS_PROOT_ARCH_DEV=(
    python
    python-pip
    github-cli
    meson
    ninja
)
