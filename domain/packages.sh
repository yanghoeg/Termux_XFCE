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
    termux-api     # Android API 브리지 (클립보드, 알림, 배터리 등)
    termux-services # runit 서비스 관리 (sv-enable/sv — Termux:Boot 자동 기동용)
    # xclip: display 어댑터(display_get_packages)로 이동
)

# XFCE 데스크탑 환경
PKGS_TERMUX_XFCE=(
    xfce4
    xfce4-goodies
    firefox
    flameshot          # 스크린샷 — native 필수 (proot에선 dbus EXTERNAL auth UID 불일치로 작동 불가)
    papirus-icon-theme
    # termux-x11-nightly, wmctrl: display 어댑터(display_get_packages)로 이동
    libuv
    pavucontrol-qt
    fontconfig-utils   # fc-cache/fc-match: Nerd Font 폰트 캐시 갱신용 (xfce 의존성에 미포함)
    libsimdutf         # libvte(xfce4-terminal) 런타임 의존성 (Termux 26.x+에서 자동 pull 안 됨)
    # xdotool: display 어댑터(display_get_packages)로 이동
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
    fastfetch   # 시스템 정보 (neofetch 후속 — neofetch는 2024년 upstream 아카이브됨)
    git-delta   # git diff 구문 강조 (lazygit 연동)
    zellij      # tmux 대안 — 세션 멀티플렉서
    dust        # du 시각화 — 스토리지 확인
    duf         # df 현대적 대체
    yazi        # Rust 비동기 터미널 파일매니저 (이미지 프리뷰)
    procs       # ps 현대적 대체 — 컬러/트리 뷰
    ncdu        # 디스크 사용량 드릴다운 TUI (duf/dust 보완)
    glow        # 터미널 마크다운 렌더러 (README·AI 출력 읽기)
    tealdeer    # tldr — 명령어 치트시트 (man 빠른 조회)
    xh          # HTTPie 호환 HTTP 클라이언트 (curl 대체)
    onefetch    # git 저장소 요약 (fastfetch의 repo판)
    uv          # Python 패키지/가상환경 관리 (pip·venv·pyenv 대체)
    sd          # sed 대체 — 직관적 문자열 치환
    difftastic  # 구문 인식 diff (git difftool 연동)
    gitui       # git TUI (lazygit 대안 — Rust, 저메모리)
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
# 태그(v1.4.17)에 고정 — releases/latest 사용 금지(무결성 검증 불가능해짐).
NIMF_DEB_BASE_URL="https://github.com/hamonikr/nimf/releases/download/v1.4.17"
NIMF_DEBS=(
    "nimf_1.4.17_arm64-ubuntu.2404.arm64.deb"
    "nimf-i18n_1.4.17_arm64-ubuntu.2404.arm64.deb"
)

# 각 .deb의 sha256 (dpkg -i 전 무결성 검증용 — proot_pkg_install_deb_url이 소비)
# -g 필수: 이 파일이 함수(_load_domain 등) 안에서 source될 수 있어 -g 없으면
# declare가 그 함수 로컬 스코프로 묶여 함수 반환 시 배열이 통째로 사라진다.
declare -gA NIMF_DEB_SHA256=(
    ["nimf_1.4.17_arm64-ubuntu.2404.arm64.deb"]="0530909cf696828bdcd54c122ad465af8bbdf83b1e7eb2fe7a6d6da388334c58"
    ["nimf-i18n_1.4.17_arm64-ubuntu.2404.arm64.deb"]="7a1f9c3b3893439fa14a4d369e6eac722f40128a595bd98e032e14857e0201b4"
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
