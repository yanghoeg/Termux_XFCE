#!/data/data/com.termux/files/usr/bin/bash
# =============================================================================
# ADAPTER (공통): pkg_common_termux.sh
# -----------------------------------------------------------------------------
# Termux native 패키지 관리 — 모든 pkg_*.sh 어댑터가 source하는 공통 구현체
# pkg_manager.sh 포트의 Termux native 계약 구현
# =============================================================================

# Termux `pkg` 래퍼는 mirror가 선택돼 있지 않으면 매 호출마다 미러 자동 테스트를
# 강제한다. 느리거나 고지연인 네트워크에서는 이 테스트가 전부 타임아웃되어 "bad"로
# 처리되고, sources.list에 유효 미러가 있어도 설치가 "None of the mirrors are
# accessible"로 중단된다. sources.list의 기존(기본) 미러를 신뢰하고 자동 테스트를
# 건너뛴다 — sources.list에 미러가 없으면 `pkg`가 알아서 정상 선택 로직으로 fallback.
export TERMUX_PKG_NO_MIRROR_SELECT=1

pkg_update() {
    # 일부 미러 fetch 실패(exit 100)는 캐시된 인덱스로 계속 진행 가능 — 관대 처리.
    # Why: tur.kcubeterm.com 등 외부 미러 동기화 지연이 전체 설치를 중단시키는 일을 방지.
    local tmplog exit_code pipefail_was_enabled=false
    tmplog=$(mktemp)
    if shopt -qo pipefail; then
        pipefail_was_enabled=true
    fi
    set +o pipefail
    pkg update -y -o Dpkg::Options::="--force-confold" 2>&1 | tee "$tmplog"
    exit_code=${PIPESTATUS[0]}
    if [ "$pipefail_was_enabled" = true ]; then
        set -o pipefail
    fi
    if [ $exit_code -ne 0 ]; then
        if grep -q "Some index files failed to download" "$tmplog" && \
           ! grep -qE "Could not get lock|Unable to lock|dpkg was interrupted" "$tmplog"; then
            echo "[WARN] pkg_update: 일부 미러 동기화 실패 — 캐시된 인덱스로 계속 진행" >&2
            rm -f "$tmplog"
            return 0
        fi
    fi
    rm -f "$tmplog"
    return $exit_code
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
    dpkg -s "$1" 2>/dev/null | grep -q "^Status: install ok installed"
}

pkg_autoremove() {
    apt autoremove -y
    apt autoclean -y
}

# URL의 .deb를 native에 설치. dpkg가 의존성 부족으로 non-zero를 반환하면
# apt로 복구하되, 복구 실패 시 설치 성공으로 보고하지 않는다.
# $2(expected_sha256, 선택)가 주어지면 dpkg -i 전에 무결성을 검증하고,
# 불일치 시 dpkg를 실행하지 않고 return 1 (GitHub Releases .deb 위변조 방지).
pkg_install_deb_url() {
    local url="$1"
    local expected_sha256="${2:-}"
    local deb="${TMPDIR:-/tmp}/$(basename "$url")"

    wget -q "$url" -O "$deb" || { rm -f "$deb"; return 1; }

    if [ -n "$expected_sha256" ]; then
        local actual_sha256
        actual_sha256=$(sha256sum "$deb" | cut -d' ' -f1)
        if [ "$actual_sha256" != "$expected_sha256" ]; then
            echo "[ERROR] $(basename "$deb") sha256 불일치 (기대: ${expected_sha256}, 실제: ${actual_sha256}) — 설치 중단" >&2
            rm -f "$deb"
            return 1
        fi
    fi

    if ! dpkg -i --force-overwrite "$deb" 2>/dev/null; then
        if ! apt --fix-broken install -y 2>/dev/null; then
            rm -f "$deb"
            return 1
        fi
    fi
    rm -f "$deb"
}
