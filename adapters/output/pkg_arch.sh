#!/data/data/com.termux/files/usr/bin/bash
# =============================================================================
# ADAPTER: pkg_arch.sh
# -----------------------------------------------------------------------------
# Output Adapter — Arch Linux proot-distro 패키지 매니저 (pacman)
# pkg_manager.sh 포트의 Arch Linux 구현체
# 환경변수: PROOT_DISTRO=archlinux, PROOT_USER=<username> 필요
# =============================================================================

# Termux native + proot 공통 (라이프사이클, 실행 함수)
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/pkg_common_proot.sh"

# -----------------------------------------------------------------------------
# proot (Arch Linux 내부) 패키지 관리
# -----------------------------------------------------------------------------

proot_pkg_install() {
    proot_exec sudo pacman -S --noconfirm --needed "$@"
}

proot_pkg_install_root() {
    proot_exec_root pacman -S --noconfirm --needed "$@"
}

proot_pkg_update() {
    proot_exec sudo pacman -Syu --noconfirm
}

proot_pkg_update_root() {
    proot_exec_root pacman -Syu --noconfirm
}

proot_pkg_remove() {
    proot_exec sudo pacman -Rs --noconfirm "$@"
}

proot_pkg_is_installed() {
    proot_exec pacman -Q "$1" > /dev/null 2>&1
}

proot_pkg_autoremove() {
    # Arch: 고아 패키지 제거
    proot_exec bash -c 'pacman -Qtdq | pacman -Rns --noconfirm - 2>/dev/null || true'
    # 캐시 정리
    proot_exec sudo pacman -Sc --noconfirm
}

# AUR 헬퍼(yay)로 패키지 설치 (공식 repo 밖 패키지, nimf 등)
proot_aur_install() {
    proot_exec yay -S --noconfirm --needed "$@"
}

# yay가 없으면 yay-bin을 AUR에서 빌드/설치 (멱등성)
proot_ensure_aur_helper() {
    proot_exec bash -c "
        set -e
        command -v yay &>/dev/null && exit 0
        sudo pacman -S --noconfirm --needed git base-devel
        git clone https://aur.archlinux.org/yay-bin.git /tmp/yay-bin
        cd /tmp/yay-bin && makepkg -si --noconfirm
        rm -rf /tmp/yay-bin
    "
    proot_exec bash -c "command -v yay &>/dev/null"
}
