#!/data/data/com.termux/files/usr/bin/bash
# =============================================================================
# 비대화형 app-installer 배치 테스트
# 사용법: bash tests/batch_test_appinstaller.sh archlinux <username>
#         bash tests/batch_test_appinstaller.sh ubuntu    <username>
# =============================================================================
set -uo pipefail

DISTRO="${1:?distro 필요}"
USER="${2:?user 필요}"
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
AI_DIR="${SCRIPT_DIR}/app-installer"
LOG="${SCRIPT_DIR}/tests/result_${DISTRO}.log"

# proot 앱 desktop 파일은 termux 호스트($PREFIX/share/applications)에 공유되므로,
# 한 호스트에서 distro별로 batch를 돌리면 다른 distro의 흔적 때문에 SKIP 처리됨.
# PROOT_FRESH=1로 시작 시 proot 앱 desktop 흔적을 제거 → 현 distro에서 진짜 재설치 검증.
PROOT_FRESH="${PROOT_FRESH:-0}"
# INCLUDE_HEAVY=1: HEAVY_APPS(teams/thorium/sasm)까지 포함.
# 기본 0 — 무거워서(각 5-15분) 별도 옵션으로 분리.
INCLUDE_HEAVY="${INCLUDE_HEAVY:-0}"

export PROOT_DISTRO="$DISTRO"
export PROOT_USER="$USER"

# DI 로드
source "${AI_DIR}/ports/pkg_manager.sh"
source "${AI_DIR}/adapters/output/pkg_termux.sh"
case "$DISTRO" in
    ubuntu)    source "${AI_DIR}/adapters/output/pkg_ubuntu.sh" ;;
    archlinux) source "${AI_DIR}/adapters/output/pkg_arch.sh"   ;;
esac
source "${AI_DIR}/domain/desktop.sh"
source "${AI_DIR}/domain/apps.sh"
for f in "${AI_DIR}/domain/installers/"*.sh; do source "$f"; done

# Mesa/Zink 충돌 변수 제거 (zenity/GTK 렌더링 버그 방지)
unset MESA_LOADER_DRIVER_OVERRIDE TU_DEBUG ZINK_DESCRIPTORS \
      MESA_NO_ERROR MESA_GL_VERSION_OVERRIDE MESA_GLES_VERSION_OVERRIDE 2>/dev/null || true

PASS=0; FAIL=0; SKIP=0
declare -A RESULTS

run_test() {
    local id="$1"
    local result
    printf "  [%-15s] " "$id"
    if ! app_can_install "$id"; then
        result="SKIP (installer retired)"
        (( SKIP++ )) || true
    elif app_is_installed "$id"; then
        result="SKIP (already installed)"
        (( SKIP++ )) || true
    elif app_install "$id" >> "$LOG" 2>&1; then
        result="PASS"
        (( PASS++ )) || true
    else
        result="FAIL"
        (( FAIL++ )) || true
    fi
    # 터미널 출력 + 로그 파일 기록 (서브쉘 없이)
    echo "$result" | tee -a "$LOG"
}

{
echo "=============================="
echo " app-installer 배치 테스트"
echo " DISTRO : $DISTRO"
echo " USER   : $USER"
echo " DATE   : $(date)"
echo "=============================="
} | tee -a "$LOG"

echo "" | tee -a "$LOG"
echo "--- 설치 테스트 ---" | tee -a "$LOG"

PROOT_APPS=(libreoffice miniforge nautilus dbeaver vscode burpsuite)
HEAVY_APPS=(teams thorium sasm)
NATIVE_APPS=(thunderbird vlc notion)

# PROOT_FRESH=1: 현 distro에서 진짜 재설치 검증 위해 호스트 공유 desktop 흔적 제거
if [ "$PROOT_FRESH" = "1" ]; then
    echo "▶ PROOT_FRESH=1: proot 앱 desktop 흔적 정리 (호스트 공유 정리)" | tee -a "$LOG"
    _fresh_targets=("${PROOT_APPS[@]}")
    [ "$INCLUDE_HEAVY" = "1" ] && _fresh_targets+=("${HEAVY_APPS[@]}")
    for id in "${_fresh_targets[@]}"; do
        desktop_remove_prefix "$id"
        echo "  - $id 흔적 제거" | tee -a "$LOG"
    done
    unset _fresh_targets
fi

echo "▶ Native (Termux) 앱" | tee -a "$LOG"
for id in "${NATIVE_APPS[@]}"; do run_test "$id"; done

echo "▶ proot 경량 앱" | tee -a "$LOG"
for id in "${PROOT_APPS[@]}"; do run_test "$id"; done

if [ "$INCLUDE_HEAVY" = "1" ]; then
    echo "▶ proot 무거운 앱 (HEAVY_APPS)" | tee -a "$LOG"
    for id in "${HEAVY_APPS[@]}"; do run_test "$id"; done
fi

echo "" | tee -a "$LOG"
echo "--- GPU 가속 확인 ---" | tee -a "$LOG"
GPU_RESULT=$(proot-distro login "$DISTRO" --user "$USER" --shared-tmp -- \
    env DISPLAY="${DISPLAY:-:0.0}" \
        MESA_LOADER_DRIVER_OVERRIDE=zink \
        VK_ICD_FILENAMES=/data/data/com.termux/files/usr/share/vulkan/icd.d/freedreno_icd.aarch64.json \
    glxinfo 2>/dev/null | grep -E "OpenGL renderer|OpenGL version" || echo "glxinfo 없음/실패")
echo "  glxinfo: $GPU_RESULT" | tee -a "$LOG"

VK_RESULT=$(proot-distro login "$DISTRO" --user "$USER" --shared-tmp -- \
    env VK_ICD_FILENAMES=/data/data/com.termux/files/usr/share/vulkan/icd.d/freedreno_icd.aarch64.json \
    vulkaninfo --summary 2>/dev/null | grep -E "GPU|driverName|apiVersion" | head -5 || echo "vulkaninfo 없음/실패")
echo "  vulkaninfo: $VK_RESULT" | tee -a "$LOG"

echo "" | tee -a "$LOG"
echo "=============================="
echo " 결과: PASS=$PASS  FAIL=$FAIL  SKIP=$SKIP"
echo "=============================="
echo " 결과: PASS=$PASS  FAIL=$FAIL  SKIP=$SKIP" >> "$LOG"

# FAIL 있어도 0 반환 (로그 확인용)
exit 0
