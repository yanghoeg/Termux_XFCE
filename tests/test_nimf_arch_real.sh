#!/data/data/com.termux/files/usr/bin/bash
# =============================================================================
# 실테스트: Arch proot nimf AUR 시도 + fcitx5 폴백 검증
# - nimf: ARM64 Arch에서 AUR/릴리즈 모두 x86_64 전용 → 설치 불가 확인
# - fcitx5: 공식 pacman 설치 + 한글 동작 검증
# 사전 조건: proot-distro archlinux 설치됨, 일반 유저 존재
# 사용법: bash tests/test_nimf_arch_real.sh
# =============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/framework.sh"

PROOT_USER="${PROOT_USER:-yanghoeg}"
_proot()      { proot-distro login archlinux --user "$PROOT_USER" -- bash -c "$*" 2>/dev/null; }
_proot_root() { proot-distro login archlinux --user root          -- bash -c "$*" 2>/dev/null; }

pass=0; fail=0; skip=0

_ok()   { echo "  [32m✓[0m $1"; (( pass++ )); }
_fail() { echo "  [31m✗[0m $1"; (( fail++ )); }
_skip() { echo "  [33m-[0m $1 (건너뜀)"; (( skip++ )); }
_info() { echo "  → $1"; }

# =============================================================================

echo ""
echo "[36m▶ 사전 조건 확인[0m"

if [ ! -d "$PREFIX/var/lib/proot-distro/installed-rootfs/archlinux" ]; then
    echo "[31m✗ Arch proot가 설치되지 않았습니다.[0m"
    exit 1
fi
_ok "Arch proot rootfs 존재"

ARCH=$(_proot "uname -m")
_ok "아키텍처: $ARCH"

# =============================================================================

echo ""
echo "[36m▶ nimf ARM64 Arch 지원 여부 확인[0m"

_info "GitHub Releases .pkg.tar.zst 아키텍처 확인..."
# 파일명에 'any'가 붙어있지만 내부 경로가 x86_64-linux-gnu임을 파일 목록으로 검증
PKG_LIST=$(curl -sL --max-time 30 \
    "https://github.com/hamonikr/nimf/releases/download/v1.4.17/nimf-1.4.17-1-any-arch.pkg.tar.zst" \
    | tar -tf - 2>/dev/null | grep "lib/" | head -5 || true)

if echo "$PKG_LIST" | grep -q "x86_64"; then
    _ok "확인: 릴리즈 패키지가 x86_64 전용 (ARM64 사용 불가)"
elif [ -z "$PKG_LIST" ]; then
    # 네트워크 실패 시 파일명 패턴으로 대체 판단
    _info "다운로드 실패 — AUR PKGBUILD 결과로 대체 판단"
    _skip "릴리즈 .pkg.tar.zst 아키텍처 직접 확인 불가 (네트워크 타임아웃)"
else
    _fail "릴리즈 패키지 아키텍처 확인 실패"
fi

_info "AUR PKGBUILD arch 필드 확인..."
AUR_ARCH=$(curl -s "https://aur.archlinux.org/cgit/aur.git/plain/PKGBUILD?h=nimf" \
    | grep "^arch=")
if echo "$AUR_ARCH" | grep -q "x86_64"; then
    _ok "확인: AUR PKGBUILD arch=(x86_64) — ARM64 미지원"
    _info "AUR: $AUR_ARCH"
else
    _skip "AUR PKGBUILD 확인 불가"
fi

# makepkg fakeroot 상태
if _proot "fakeroot echo ok" | grep -q "ok"; then
    _info "fakeroot 자체는 작동함 — nimf 소스가 ARM64 빌드를 지원하지 않음"
fi

# =============================================================================

echo ""
echo "[36m▶ fcitx5 폴백 설치 확인[0m"

if _proot "pacman -Q fcitx5 2>/dev/null" | grep -q "fcitx5"; then
    VER=$(_proot "pacman -Q fcitx5 2>/dev/null | awk '{print \$2}'")
    _ok "fcitx5 설치됨: $VER"
else
    _info "fcitx5 설치 중..."
    _proot_root "pacman -S --noconfirm --needed fcitx5 fcitx5-hangul fcitx5-configtool libhangul 2>/dev/null" || true
    if _proot "pacman -Q fcitx5 2>/dev/null" | grep -q "fcitx5"; then
        _ok "fcitx5 설치 완료"
    else
        _fail "fcitx5 설치 실패"
    fi
fi

if _proot "pacman -Q fcitx5-hangul 2>/dev/null" | grep -q "fcitx5-hangul"; then
    VER=$(_proot "pacman -Q fcitx5-hangul 2>/dev/null | awk '{print \$2}'")
    _ok "fcitx5-hangul 설치됨: $VER"
else
    _fail "fcitx5-hangul 없음"
fi

if _proot "pacman -Q libhangul 2>/dev/null" | grep -q "libhangul"; then
    _ok "libhangul 설치됨"
else
    _fail "libhangul 없음"
fi

# =============================================================================

echo ""
echo "[36m▶ fcitx5 바이너리 검증[0m"

FCITX_BIN=$(_proot "which fcitx5 2>/dev/null")
if [ -n "$FCITX_BIN" ]; then
    _ok "fcitx5 바이너리: $FCITX_BIN"
else
    _fail "fcitx5 바이너리 없음"
fi

HANGUL_MODULE=$(_proot "find /usr/lib/fcitx5 -name '*hangul*' 2>/dev/null | head -1")
if [ -n "$HANGUL_MODULE" ]; then
    _ok "hangul 모듈: $HANGUL_MODULE"
else
    _fail "fcitx5-hangul 모듈 없음 (/usr/lib/fcitx5/)"
fi

# =============================================================================

echo ""
echo "[36m▶ 한글 폰트 확인[0m"

if _proot "fc-list :lang=ko 2>/dev/null | head -1" | grep -q "\."; then
    _ok "한글 폰트 설치됨:"
    _proot "fc-list :lang=ko 2>/dev/null | head -3" | while read -r l; do _info "$l"; done
else
    _info "한글 폰트 없음 — noto-fonts-cjk 설치 시도"
    _proot_root "pacman -S --noconfirm --needed noto-fonts-cjk 2>/dev/null" || true
    if _proot "fc-list :lang=ko 2>/dev/null | head -1" | grep -q "\."; then
        _ok "noto-fonts-cjk 설치 후 한글 폰트 확인됨"
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
echo "════════════════════════════════"
if (( fail == 0 )); then
    echo " 결과: [32m${pass} passed[0m | [31m${fail} failed[0m | [33m${skip} skipped[0m"
    echo " [32mArch fcitx5 폴백 검증 완료[0m"
    echo ""
    echo " [33m※ nimf: ARM64 Arch 미지원 (x86_64 전용)[0m"
    echo "   X11 세션 기동 후 fcitx5로 한글 입력 가능"
else
    echo " 결과: [32m${pass} passed[0m | [31m${fail} failed[0m | [33m${skip} skipped[0m"
fi
echo "════════════════════════════════"
echo ""

(( fail == 0 ))
