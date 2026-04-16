#!/data/data/com.termux/files/usr/bin/bash
# =============================================================================
# ADAPTER: adapters/input/cli.sh
# -----------------------------------------------------------------------------
# Input Adapter — CLI/환경변수 기반 비대화형 실행
# 사용법:
#   DISTRO=archlinux USERNAME=<username> bash install.sh
#   또는
#   bash install.sh --distro archlinux --user <username> --no-gpu
# =============================================================================

parse_cli_args() {
    # 환경변수 우선, 그 다음 CLI 인자
    export PROOT_DISTRO="${DISTRO:-}"
    export PROOT_USER="${USERNAME:-}"
    export INSTALL_GPU="${INSTALL_GPU:-}"
    export INSTALL_GPU_DEV="${INSTALL_GPU_DEV:-}"
    export SKIP_PROOT="${SKIP_PROOT:-false}"
    export PROOT_ONLY="${PROOT_ONLY:-false}"
    export KOREAN_LOCALE="${KOREAN_LOCALE:-false}"
    export KOREAN_LOCALE_ZIP="${KOREAN_LOCALE_ZIP:-}"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --distro|-d)
                PROOT_DISTRO="$2"; shift 2 ;;
            --user|-u)
                PROOT_USER="$2"; shift 2 ;;
            --no-proot)
                SKIP_PROOT=true; shift ;;
            --proot-only)
                PROOT_ONLY=true; shift ;;
            --gpu)
                INSTALL_GPU=true; shift ;;
            --gpu-dev)
                INSTALL_GPU_DEV=true; shift ;;
            --korean-locale)
                KOREAN_LOCALE=true; shift ;;
            --locale-zip)
                KOREAN_LOCALE_ZIP="$2"; KOREAN_LOCALE=true; shift 2 ;;
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
      --no-proot          Termux native만 설치 (proot 생략)
      --proot-only        proot만 설치 (Termux native 설정 생략, 추가 distro용)
      --gpu               GPU 가속 설치
      --gpu-dev           GPU 개발 도구 설치
      --korean-locale         XFCE 한글 로케일 강제 적용 (LD_PRELOAD 기반)
      --locale-zip <path>     한글 로케일 .mo 카탈로그 zip 경로 (--korean-locale 자동 활성화)
  -h, --help              이 도움말 출력

환경변수:
  DISTRO=archlinux        --distro 와 동일
  USERNAME=<username>     --user 와 동일
  INSTALL_GPU=true        --gpu 와 동일
  SKIP_PROOT=true         --no-proot 와 동일
  PROOT_ONLY=true         --proot-only 와 동일
  KOREAN_LOCALE=true      --korean-locale 와 동일
  KOREAN_LOCALE_ZIP=path  --locale-zip 과 동일

예시:
  bash install.sh --user <username> --distro archlinux --gpu
  bash install.sh --user <username> --distro ubuntu --proot-only
  bash install.sh --korean-locale --locale-zip ~/Downloads/locale.zip
  DISTRO=ubuntu USERNAME=<username> bash install.sh
EOF
}
