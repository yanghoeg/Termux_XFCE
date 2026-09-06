#!/data/data/com.termux/files/usr/bin/bash
# =============================================================================
# ADAPTER: pkg_termux.sh
# -----------------------------------------------------------------------------
# Output Adapter — Termux native 전용 (proot 미사용)
# pkg_manager.sh 포트의 Termux 구현체
# =============================================================================

# Termux native 패키지 관리 (공통)
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/pkg_common_termux.sh"

# -----------------------------------------------------------------------------
# proot 미지원 stub — native-only 모드에서 호출 시 에러
# -----------------------------------------------------------------------------

proot_exec() {
    echo "[ERROR] pkg_termux: proot_exec는 proot 어댑터에서만 사용 가능합니다." >&2
    return 1
}

proot_exec_root() {
    echo "[ERROR] pkg_termux: proot_exec_root는 proot 어댑터에서만 사용 가능합니다." >&2
    return 1
}

proot_install() {
    echo "[ERROR] pkg_termux: proot_install은 proot 어댑터에서만 사용 가능합니다." >&2
    return 1
}

proot_remove() {
    echo "[ERROR] pkg_termux: proot_remove는 proot 어댑터에서만 사용 가능합니다." >&2
    return 1
}

proot_pkg_install() {
    echo "[ERROR] pkg_termux: proot_pkg_install는 proot 어댑터에서만 사용 가능합니다." >&2
    return 1
}

proot_pkg_install_root() {
    echo "[ERROR] pkg_termux: proot_pkg_install_root는 proot 어댑터에서만 사용 가능합니다." >&2
    return 1
}

proot_pkg_is_installed() {
    return 1
}

proot_pkg_update() {
    echo "[ERROR] pkg_termux: proot_pkg_update는 proot 어댑터에서만 사용 가능합니다." >&2
    return 1
}

proot_pkg_update_root() {
    echo "[ERROR] pkg_termux: proot_pkg_update_root는 proot 어댑터에서만 사용 가능합니다." >&2
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
