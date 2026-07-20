#!/data/data/com.termux/files/usr/bin/bash
# =============================================================================
# ADAPTER: adapters/input/cli.sh
# -----------------------------------------------------------------------------
# Input Adapter — CLI/환경변수 기반 비대화형 실행
# 사용법:
#   DISTRO=archlinux USERNAME=<username> bash install.sh
#   또는
#   bash install.sh --distro archlinux --user <username>
# =============================================================================

parse_cli_args() {
    # 환경변수 우선, 그 다음 CLI 인자
    export PROOT_DISTRO="${DISTRO:-}"
    export PROOT_USER="${USERNAME:-}"
    export SKIP_PROOT="${SKIP_PROOT:-false}"
    export PROOT_ONLY="${PROOT_ONLY:-false}"
    export DISPLAY_SERVER="${DISPLAY_SERVER:-x11}"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --distro|-d)
                [[ $# -ge 2 ]] || { echo "[ERROR] $1 옵션에 값이 필요합니다" >&2; exit 1; }
                PROOT_DISTRO="$2"; shift 2 ;;
            --user|-u)
                [[ $# -ge 2 ]] || { echo "[ERROR] $1 옵션에 값이 필요합니다" >&2; exit 1; }
                PROOT_USER="$2"; shift 2 ;;
            --display)
                [[ $# -ge 2 ]] || { echo "[ERROR] $1 옵션에 값이 필요합니다" >&2; exit 1; }
                DISPLAY_SERVER="$2"; shift 2 ;;
            --no-proot)
                SKIP_PROOT=true; shift ;;
            --proot-only)
                PROOT_ONLY=true; shift ;;
            --help|-h)
                _cli_usage; exit 0 ;;
            *)
                echo "[ERROR] 알 수 없는 인자: $1" >&2
                _cli_usage; exit 1 ;;
        esac
    done
}

_cli_usage() {
    cat << 'EOF'
사용법: bash install.sh [옵션]

옵션:
  -u, --user <이름>       proot 사용자 이름 (기본: 대화형 입력)
  -d, --distro <distro>   proot distro: ubuntu | archlinux (기본: 대화형 선택)
      --display <server>  디스플레이 서버: x11 | wayland (기본: x11)
      --no-proot          Termux native만 설치 (proot 생략)
      --proot-only        proot만 설치 (Termux native 설정 생략, 추가 distro용)
  -h, --help              이 도움말 출력

환경변수:
  DISTRO=archlinux        --distro 와 동일
  USERNAME=<username>     --user 와 동일
  DISPLAY_SERVER=x11      --display 와 동일
  SKIP_PROOT=true         --no-proot 와 동일
  PROOT_ONLY=true         --proot-only 와 동일

참고: GPU 가속, 한글 입력기 등 선택적 구성요소는 설치 후 App Installer에서 관리합니다.

예시:
  bash install.sh --user <username> --distro archlinux
  bash install.sh --user <username> --distro ubuntu --display wayland
  bash install.sh --user <username> --distro ubuntu --proot-only
  DISTRO=ubuntu USERNAME=<username> bash install.sh
EOF
}
