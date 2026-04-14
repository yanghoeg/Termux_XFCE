#!/data/data/com.termux/files/usr/bin/bash
# =============================================================================
# 자율주행 파이프라인: Ubuntu 설치 → 양쪽 app-installer 테스트 → Ubuntu 제거
# =============================================================================
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$SCRIPT_DIR"

LOG="$SCRIPT_DIR/tests/autopilot.log"
PROOT_USER="yanghoeg"
exec > >(tee -a "$LOG") 2>&1

echo "=============================="
echo " 자율주행 시작: $(date)"
echo "=============================="

# ── 단계 1: Ubuntu proot-only 설치 ──────────────────────────────
echo ""
echo "▶ [1] Ubuntu proot-only 설치"
if [ -d "$PREFIX/var/lib/proot-distro/installed-rootfs/ubuntu" ]; then
    echo "  Ubuntu 이미 설치됨, 건너뜀"
else
    bash install.sh --distro ubuntu --user "$PROOT_USER" --proot-only
    echo "  Ubuntu 설치 완료"
fi

# ── 단계 2: Arch app-installer 테스트 ───────────────────────────
echo ""
echo "▶ [2] Arch Linux app-installer 테스트"
bash tests/batch_test_appinstaller.sh archlinux "$PROOT_USER"

# ── 단계 3: Ubuntu app-installer 테스트 ─────────────────────────
echo ""
echo "▶ [3] Ubuntu app-installer 테스트"
bash tests/batch_test_appinstaller.sh ubuntu "$PROOT_USER"

# ── 단계 4: Ubuntu 제거 ─────────────────────────────────────────
echo ""
echo "▶ [4] Ubuntu proot 제거"
source ports/ui.sh
source adapters/output/ui_terminal.sh
source adapters/output/pkg_ubuntu.sh   # proot_exec_root 포함
source domain/proot_env.sh
PROOT_DISTRO=ubuntu PROOT_USER="$PROOT_USER" teardown_proot

echo ""
echo "=============================="
echo " 자율주행 완료: $(date)"
echo " 결과 로그: tests/result_archlinux.log"
echo "            tests/result_ubuntu.log"
echo "=============================="
