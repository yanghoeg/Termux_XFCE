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

