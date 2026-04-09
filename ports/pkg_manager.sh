#!/data/data/com.termux/files/usr/bin/bash
# =============================================================================
# PORT: pkg_manager.sh
# -----------------------------------------------------------------------------
# Output Port — 패키지 관리 인터페이스 (계약 정의)
# 어댑터(adapters/output/pkg_*.sh)가 이 함수들을 반드시 구현해야 함.
# 도메인 코드는 이 함수만 호출하고, 어떤 패키지 매니저인지 알지 못함.
# =============================================================================

# 사용 전 어댑터가 로드됐는지 확인
_pkg_manager_check() {
    if ! declare -f pkg_install > /dev/null 2>&1; then
        echo "[FATAL] pkg_manager 어댑터가 로드되지 않았습니다." >&2
        echo "[FATAL] adapters/output/pkg_*.sh 중 하나를 먼저 source 하세요." >&2
        exit 1
    fi
}

# -----------------------------------------------------------------------------
# 계약 (Contract) — 어댑터가 구현해야 할 함수 목록
# -----------------------------------------------------------------------------

# pkg_update
#   설명: 패키지 목록 업데이트
#   인자: 없음
#   반환: 0=성공, 1=실패
# pkg_update() { ... }

# pkg_upgrade
#   설명: 설치된 패키지 전체 업그레이드
#   인자: 없음
#   반환: 0=성공, 1=실패
# pkg_upgrade() { ... }

# pkg_install <package...>
#   설명: 패키지 설치 (여러 개 동시 가능)
#   인자: $@ = 패키지 이름 목록
#   반환: 0=성공, 1=실패
# pkg_install() { ... }

# pkg_remove <package...>
#   설명: 패키지 제거
#   인자: $@ = 패키지 이름 목록
#   반환: 0=성공, 1=실패
# pkg_remove() { ... }

# pkg_is_installed <package>
#   설명: 패키지 설치 여부 확인 (멱등성 체크에 사용)
#   인자: $1 = 패키지 이름
#   반환: 0=설치됨, 1=미설치
# pkg_is_installed() { ... }

# pkg_autoremove
#   설명: 불필요한 의존성 패키지 제거
#   인자: 없음
# pkg_autoremove() { ... }

# proot_exec <cmd...>
#   설명: 선택된 proot distro 내에서 명령 실행
#   인자: $@ = 실행할 명령
#   환경변수: PROOT_DISTRO, PROOT_USER 필요
#   반환: 명령의 exit code
# proot_exec() { ... }

# proot_pkg_install <package...>
#   설명: proot 내부에 패키지 설치
#   인자: $@ = 패키지 이름 목록
# proot_pkg_install() { ... }

# proot_pkg_is_installed <package>
#   설명: proot 내부 패키지 설치 여부 확인
#   인자: $1 = 패키지 이름
#   반환: 0=설치됨, 1=미설치
# proot_pkg_is_installed() { ... }
