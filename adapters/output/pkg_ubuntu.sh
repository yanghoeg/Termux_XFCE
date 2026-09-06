#!/data/data/com.termux/files/usr/bin/bash
# =============================================================================
# ADAPTER: pkg_ubuntu.sh
# -----------------------------------------------------------------------------
# Output Adapter — Ubuntu proot-distro 패키지 매니저 (apt)
# pkg_manager.sh 포트의 Ubuntu 구현체
# 환경변수: PROOT_DISTRO=ubuntu, PROOT_USER=<username> 필요
# =============================================================================

# Termux native + proot 공통 (라이프사이클, 실행 함수)
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/pkg_common_proot.sh"

# -----------------------------------------------------------------------------
# proot (Ubuntu 내부) 패키지 관리
# -----------------------------------------------------------------------------

proot_pkg_install() {
    proot_exec sudo apt install -y -o Dpkg::Options::="--force-confold" "$@"
}

proot_pkg_install_root() {
    proot_exec_root apt install -y -o Dpkg::Options::="--force-confold" "$@"
}

proot_pkg_update() {
    proot_exec sudo apt update
    proot_exec sudo apt upgrade -y -o Dpkg::Options::="--force-confold"
}

proot_pkg_update_root() {
    proot_exec_root apt update
    proot_exec_root apt upgrade -y -o Dpkg::Options::="--force-confold"
}

proot_pkg_remove() {
    proot_exec sudo apt remove -y "$@"
    proot_exec sudo apt autoremove -y
}

proot_pkg_is_installed() {
    proot_exec dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q "^install ok installed"
}

proot_pkg_autoremove() {
    proot_exec sudo apt autoremove -y
    proot_exec sudo apt autoclean -y
}

