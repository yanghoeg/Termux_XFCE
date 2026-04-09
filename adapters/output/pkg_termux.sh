#!/data/data/com.termux/files/usr/bin/bash
# =============================================================================
# ADAPTER: pkg_termux.sh
# -----------------------------------------------------------------------------
# Output Adapter — Termux native 패키지 매니저 (pkg/apt)
# pkg_manager.sh 포트의 Termux 구현체
# =============================================================================

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

# Termux native는 proot_exec 미지원
proot_exec() {
    echo "[ERROR] pkg_termux: proot_exec는 proot 어댑터에서만 사용 가능합니다." >&2
    return 1
}

proot_pkg_install() {
    echo "[ERROR] pkg_termux: proot_pkg_install는 proot 어댑터에서만 사용 가능합니다." >&2
    return 1
}

proot_pkg_is_installed() {
    return 1
}

proot_pkg_update() {
    echo "[ERROR] pkg_termux: proot_pkg_update는 proot 어댑터에서만 사용 가능합니다." >&2
    return 1
}

proot_pkg_remove() {
    echo "[ERROR] pkg_termux: proot_pkg_remove는 proot 어댑터에서만 사용 가능합니다." >&2
    return 1
}

proot_pkg_autoremove() {
    echo "[ERROR] pkg_termux: proot_pkg_autoremove는 proot 어댑터에서만 사용 가능합니다." >&2
    return 1
}
