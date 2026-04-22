#!/data/data/com.termux/files/usr/bin/bash
# =============================================================================
# 실테스트: Ubuntu proot에 nimf 설치 + 한글 동작 검증
# 실제 Ubuntu proot에 접속해 nimf를 설치하고 기본 동작을 확인합니다.
# 사전 조건: proot-distro ubuntu 설치됨
# 사용법: bash tests/test_nimf_ubuntu_real.sh
# =============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/framework.sh"

PROOT_LOGIN="proot-distro login ubuntu --"

_proot() { $PROOT_LOGIN bash -c "$*" 2>/dev/null; }
_proot_root() { proot-distro login ubuntu --user root -- bash -c "$*" 2>/dev/null; }

pass=0; fail=0

_ok() { echo "  [32m✓[0m $1"; (( pass++ )); }
_fail() { echo "  [31m✗[0m $1"; (( fail++ )); }
_info() { echo "  → $1"; }

# =============================================================================

echo ""
echo "[36m▶ 사전 조건 확인[0m"

if [ ! -d "$PREFIX/var/lib/proot-distro/installed-rootfs/ubuntu" ]; then
    echo "[31m✗ Ubuntu proot가 설치되지 않았습니다.[0m"
    echo "  먼저 실행: bash install.sh --distro ubuntu --user \$USER --proot-only"
    exit 1
fi
_ok "Ubuntu proot rootfs 존재"

# =============================================================================

echo ""
echo "[36m▶ nimf .deb 설치[0m"

NIMF_DEB_BASE="https://github.com/hamonikr/nimf/releases/download/v1.4.17"
NIMF_MAIN_DEB="nimf_1.4.17_arm64-ubuntu.2404.arm64.deb"
NIMF_I18N_DEB="nimf-i18n_1.4.17_arm64-ubuntu.2404.arm64.deb"

if _proot "command -v nimf" &>/dev/null; then
    _ok "nimf 이미 설치됨 — 건너뜀"
else
    _info "의존성 패키지 설치 중..."
    _proot_root "apt-get install -y --no-install-recommends libglib2.0-0 libgtk-3-0 libdbus-1-3 im-config libhangul1 2>/dev/null" || true

    _info "nimf .deb 다운로드 + 설치 중..."
    for deb in "$NIMF_MAIN_DEB" "$NIMF_I18N_DEB"; do
        if proot-distro login ubuntu --user root -- bash -c "
            wget -q -O /tmp/${deb} ${NIMF_DEB_BASE}/${deb} &&
            dpkg -i /tmp/${deb} 2>&1 | tail -3 &&
            rm -f /tmp/${deb}
        " 2>/dev/null; then
            _ok "${deb} 설치 완료"
        else
            _fail "${deb} 설치 실패"
        fi
    done

    _proot_root "apt-get install -f -y 2>/dev/null" || true
fi

# =============================================================================

echo ""
echo "[36m▶ nimf 설치 검증[0m"

if _proot "command -v nimf"; then
    _ok "nimf 바이너리 존재: $(_proot 'which nimf')"
else
    _fail "nimf 바이너리 없음"
fi

if _proot "nimf --version 2>&1" | grep -q "1\.4"; then
    _ok "nimf 버전: $(_proot 'nimf --version 2>&1')"
else
    _fail "nimf --version 실패"
fi

NIMF_PLUGIN=$(_proot "find /usr/lib -name 'libnimf-libhangul.so' 2>/dev/null | head -1")
if [ -n "$NIMF_PLUGIN" ]; then
    _ok "nimf-libhangul 플러그인: $NIMF_PLUGIN"
else
    _fail "nimf-libhangul 플러그인 없음 (libnimf-libhangul.so)"
fi

# =============================================================================

echo ""
echo "[36m▶ 한글 폰트 확인[0m"

if _proot "fc-list :lang=ko 2>/dev/null | head -3" | grep -q "\."; then
    _ok "한글 폰트 설치됨:"
    _proot "fc-list :lang=ko 2>/dev/null | head -3" | while read -r l; do _info "$l"; done
else
    _info "한글 폰트 미설치 — fonts-nanum 설치 시도"
    _proot_root "apt-get install -y fonts-nanum 2>/dev/null" || true
    if _proot "fc-list :lang=ko 2>/dev/null | head -1" | grep -q "\."; then
        _ok "fonts-nanum 설치 후 한글 폰트 확인됨"
    else
        _fail "한글 폰트 없음"
    fi
fi

# =============================================================================

echo ""
echo "[36m▶ 한글 텍스트 출력 테스트[0m"

KOREAN_TEXT="안녕하세요 한글 테스트"
result=$(_proot "echo '${KOREAN_TEXT}'" 2>/dev/null)
if [ "$result" = "$KOREAN_TEXT" ]; then
    _ok "한글 echo 출력: $result"
else
    _fail "한글 echo 출력 실패: '$result'"
fi

LOCALE_RESULT=$(_proot "LANG=ko_KR.UTF-8 LC_ALL=ko_KR.UTF-8 echo '가나다라마바사'" 2>/dev/null)
if [ "$LOCALE_RESULT" = "가나다라마바사" ]; then
    _ok "ko_KR 로케일 한글 출력: $LOCALE_RESULT"
else
    _fail "ko_KR 로케일 한글 출력 실패"
fi

# =============================================================================

echo ""
echo "[36m▶ im-config 설정[0m"

if _proot_root "im-config -n nimf 2>/dev/null"; then
    _ok "im-config -n nimf 성공"
else
    _fail "im-config -n nimf 실패"
fi

if _proot "cat /etc/X11/xinit/xinput.d/nimf 2>/dev/null || cat ~/.xinputrc 2>/dev/null" | grep -qi "nimf"; then
    _ok "im-config nimf 설정 파일 존재"
else
    _info "im-config 설정 파일 확인 불가 (X11 없는 환경 — 정상)"
fi

# =============================================================================

echo ""
echo "════════════════════════════════"
if (( fail == 0 )); then
    echo " 결과: [32m${pass} passed[0m | [31m${fail} failed[0m"
    echo " [32mnimf 설치 및 한글 동작 확인 완료[0m"
else
    echo " 결과: [32m${pass} passed[0m | [31m${fail} failed[0m"
fi
echo "════════════════════════════════"
echo ""

(( fail == 0 ))
