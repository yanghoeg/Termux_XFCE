#!/data/data/com.termux/files/usr/bin/bash
# =============================================================================
# ADAPTER: pkg_arch.sh
# -----------------------------------------------------------------------------
# Output Adapter — Arch Linux proot-distro 패키지 매니저 (pacman)
# pkg_manager.sh 포트의 Arch Linux 구현체
# 환경변수: PROOT_DISTRO=archlinux, PROOT_USER=<username> 필요
# =============================================================================

# Termux native 패키지 관리 (Ubuntu 어댑터와 동일 — Termux는 항상 pkg)
pkg_update() {
    pkg update -y -o Dpkg::Options::="--force-confold"
}

pkg_upgrade() {
    pkg upgrade -y -o Dpkg::Options::="--force-confold"
}

pkg_install() {
    pkg install -y -o Dpkg::Options::="--force-confold" "$@"
}

pkg_remove() {
    pkg uninstall -y "$@"
}

pkg_is_installed() {
    pkg list-installed 2>/dev/null | grep -q "^${1}/"
}

pkg_autoremove() {
    apt autoremove -y
    apt autoclean -y
}

# -----------------------------------------------------------------------------
# proot (Arch Linux 내부) 패키지 관리
# -----------------------------------------------------------------------------

proot_exec() {
    : "${PROOT_DISTRO:?PROOT_DISTRO 환경변수가 설정되지 않았습니다}"
    : "${PROOT_USER:?PROOT_USER 환경변수가 설정되지 않았습니다}"
    proot-distro login "$PROOT_DISTRO" \
        --user "$PROOT_USER" \
        --shared-tmp \
        -- env DISPLAY=:1.0 "$@"
}

proot_pkg_install() {
    proot_exec sudo pacman -S --noconfirm --needed "$@"
}

proot_pkg_update() {
    proot_exec sudo pacman -Syu --noconfirm
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
