#!/data/data/com.termux/files/usr/bin/bash
# =============================================================================
# 자율주행 파이프라인 — install.sh 매트릭스 실제 실행
# -----------------------------------------------------------------------------
# 사이클 1: Ubuntu     — teardown → install --proot-only → app-installer 배치
# 사이클 2: Arch Linux — teardown → install --proot-only → app-installer 배치
# 종료: 양쪽 teardown으로 깔끔하게 정리
#
# 사용법:
#   PROOT_USER=yanghoeg bash tests/autopilot.sh
#   PROOT_USER=yanghoeg SKIP_APPS=1 bash tests/autopilot.sh   # install만, 앱 배치 생략
#   PROOT_USER=yanghoeg DISTROS=ubuntu bash tests/autopilot.sh # 한 distro만
# =============================================================================
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$SCRIPT_DIR"

LOG="$SCRIPT_DIR/tests/autopilot.log"
PROOT_USER="${PROOT_USER:-tester}"
SKIP_APPS="${SKIP_APPS:-0}"
DISTROS="${DISTROS:-ubuntu archlinux}"
exec > >(tee -a "$LOG") 2>&1

# proot 제거 헬퍼 — 미설치도 안전 (no-op)
_teardown() {
    local distro="$1"
    PROOT_DISTRO="$distro" PROOT_USER="$PROOT_USER" \
    bash -c '
        set -uo pipefail
        source ports/ui.sh
        source adapters/output/ui_terminal.sh
        case "$PROOT_DISTRO" in
            ubuntu)    source adapters/output/pkg_ubuntu.sh ;;
            archlinux) source adapters/output/pkg_arch.sh   ;;
        esac
        source domain/proot_env.sh
        if [ ! -d "$(_proot_rootfs)" ]; then
            echo "  [teardown] ${PROOT_DISTRO} 미설치 — skip"
            exit 0
        fi
        teardown_proot
    '
}

echo "=============================="
echo " 자율주행 시작: $(date)"
echo " PROOT_USER : $PROOT_USER"
echo " DISTROS    : $DISTROS"
echo " SKIP_APPS  : $SKIP_APPS"
echo "=============================="

OVERALL_RC=0

for distro in $DISTROS; do
    echo ""
    echo "▶▶▶ [사이클: $distro] 시작 ─────────────────────────────────"

    # ── 단계 A: 사전 teardown ────────────────────────────────────
    echo ""
    echo "▶ [A] 사전 teardown ($distro)"
    _teardown "$distro" || true

    # ── 단계 B: install.sh --proot-only ──────────────────────────
    echo ""
    echo "▶ [B] install.sh --proot-only --distro $distro --user $PROOT_USER"
    if bash install.sh --proot-only --distro "$distro" --user "$PROOT_USER"; then
        echo "  ✓ install.sh OK"
    else
        rc=$?
        echo "  ✗ install.sh FAIL (rc=$rc)"
        OVERALL_RC=1
        # 실패 시 다음 distro로 (앱 배치는 의미 없음)
        echo "  → 다음 사이클로 진행"
        continue
    fi

    # ── 단계 C: app-installer 배치 테스트 ─────────────────────────
    if [ "$SKIP_APPS" != "1" ]; then
        echo ""
        echo "▶ [C] app-installer 배치 테스트 ($distro)"
        bash tests/batch_test_appinstaller.sh "$distro" "$PROOT_USER" || true
    else
        echo ""
        echo "▶ [C] app-installer 배치 — SKIP_APPS=1 → 생략"
    fi

    # ── 단계 D: 사이클 종료 teardown ─────────────────────────────
    echo ""
    echo "▶ [D] 사이클 종료 teardown ($distro)"
    _teardown "$distro" || true

    echo ""
    echo "◀◀◀ [사이클: $distro] 종료 ─────────────────────────────────"
done

echo ""
echo "=============================="
echo " 자율주행 완료: $(date)"
echo " 결과 로그   : tests/autopilot.log"
[ "$SKIP_APPS" != "1" ] && echo " 앱 로그     : tests/result_<distro>.log"
echo " 전체 결과   : $([ "$OVERALL_RC" -eq 0 ] && echo "PASS" || echo "FAIL")"
echo "=============================="

exit "$OVERALL_RC"
