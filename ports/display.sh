#!/data/data/com.termux/files/usr/bin/bash
# =============================================================================
# PORT: display.sh
# -----------------------------------------------------------------------------
# Output Port — 디스플레이 서버 인터페이스 (계약 정의)
# 어댑터(adapters/output/display_*.sh)가 이 함수들을 반드시 구현해야 함.
# 도메인은 X11/Wayland 등 구체적 디스플레이 서버를 알지 못함.
# =============================================================================

# 사용 전 어댑터가 로드됐는지 확인
_display_check() {
    if ! declare -f display_emit_server_start > /dev/null 2>&1; then
        echo "[FATAL] display 어댑터가 로드되지 않았습니다." >&2
        echo "[FATAL] adapters/output/display_*.sh 중 하나를 먼저 source 하세요." >&2
        exit 1
    fi
}

# -----------------------------------------------------------------------------
# 계약 (Contract) — 어댑터가 구현해야 할 함수 목록
# -----------------------------------------------------------------------------
# emit 패턴: display_emit_* 함수는 install 시점에 호출되어 stdout으로
# bash 코드 조각을 출력. script_builder가 이 조각을 조립하여 런타임 스크립트 생성.

# display_emit_kill_session
#   설명: 디스플레이 세션 종료 셸 코드 조각 출력
#         _kill_display_session() 함수 정의를 stdout에 출력
#   인자: 없음
#   출력: stdout — bash 코드 조각
# display_emit_kill_session() { ... }

# display_emit_session_detect
#   설명: 기존 세션 감지 + 충돌 다이얼로그 셸 코드 출력
#         소켓/프로세스 체크, stale 세션 정리, 사용자 선택 다이얼로그 포함
#   인자: 없음
#   출력: stdout — bash 코드 조각
# display_emit_session_detect() { ... }

# display_emit_server_start
#   설명: 디스플레이 서버 시작 + XDISPLAY 변수 설정 코드 출력
#         서버 프로세스 시작, 소켓 감지, XDISPLAY=":N" 설정 필수
#   인자: 없음
#   출력: stdout — bash 코드 조각 (XDISPLAY 변수를 반드시 설정)
# display_emit_server_start() { ... }

# display_emit_clipboard_sync
#   설명: 클립보드 동기화 시작 코드 출력
#         Android ↔ 데스크탑 클립보드 양방향 동기화
#   인자: 없음
#   출력: stdout — bash 코드 조각
# display_emit_clipboard_sync() { ... }

# display_get_packages
#   설명: 디스플레이 서버에 필요한 패키지 목록 반환
#   인자: 없음
#   출력: stdout — 공백 구분 패키지 이름
# display_get_packages() { ... }

# display_setup_apk
#   설명: 컴패니언 APK 다운로드 및 설치 (런타임 함수, emit 아님)
#   인자: 없음
#   반환: 0=성공
# display_setup_apk() { ... }
