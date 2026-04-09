#!/data/data/com.termux/files/usr/bin/bash
# =============================================================================
# PORT: ui.sh
# -----------------------------------------------------------------------------
# Output Port — 사용자 인터페이스 인터페이스 (계약 정의)
# 어댑터(adapters/output/ui_*.sh)가 이 함수들을 반드시 구현해야 함.
# 도메인은 ui_info/ui_warn/ui_error/ui_select 만 호출함.
# =============================================================================

# ui_info <message>
#   설명: 일반 정보 메시지 출력
#   인자: $1 = 메시지
# ui_info() { ... }

# ui_warn <message>
#   설명: 경고 메시지 출력
#   인자: $1 = 메시지
# ui_warn() { ... }

# ui_error <message>
#   설명: 에러 메시지 출력 (stderr)
#   인자: $1 = 메시지
# ui_error() { ... }

# ui_select <title> <prompt> <option...>
#   설명: 사용자에게 선택지 제공
#   인자: $1=타이틀, $2=프롬프트, $3...=선택지
#   반환: 선택된 값을 stdout에 출력
#   예시: choice=$(ui_select "Distro 선택" "설치할 환경:" ubuntu archlinux)
# ui_select() { ... }

# ui_confirm <message>
#   설명: Y/N 확인 요청
#   인자: $1 = 질문 메시지
#   반환: 0=Yes, 1=No
# ui_confirm() { ... }

# ui_input <prompt> <default>
#   설명: 텍스트 입력 요청
#   인자: $1=프롬프트, $2=기본값
#   반환: 입력값을 stdout에 출력
# ui_input() { ... }
