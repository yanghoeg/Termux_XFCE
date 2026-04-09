#!/data/data/com.termux/files/usr/bin/bash
# =============================================================================
# ADAPTER: ui_terminal.sh
# -----------------------------------------------------------------------------
# Output Adapter — 터미널 텍스트 UI
# ui.sh 포트의 터미널(echo) 구현체
# =============================================================================

_C_GREEN='\033[0;32m'
_C_YELLOW='\033[1;33m'
_C_RED='\033[0;31m'
_C_CYAN='\033[0;36m'
_C_NC='\033[0m'

ui_info() {
    echo -e "${_C_GREEN}[INFO]${_C_NC} $1"
}

ui_warn() {
    echo -e "${_C_YELLOW}[WARN]${_C_NC} $1"
}

ui_error() {
    echo -e "${_C_RED}[ERROR]${_C_NC} $1" >&2
}

ui_select() {
    local title="$1"
    local prompt="$2"
    shift 2
    local options=("$@")

    echo -e "${_C_CYAN}=== ${title} ===${_C_NC}"
    echo "$prompt"
    echo ""

    local i=1
    for opt in "${options[@]}"; do
        echo "  $i) $opt"
        ((i++))
    done
    echo ""

    local choice
    while true; do
        read -r -p "선택 (1-${#options[@]}): " choice </dev/tty
        if [[ "$choice" =~ ^[0-9]+$ ]] && \
           [ "$choice" -ge 1 ] && \
           [ "$choice" -le "${#options[@]}" ]; then
            echo "${options[$((choice-1))]}"
            return 0
        fi
        echo "올바른 번호를 입력하세요."
    done
}

ui_confirm() {
    local message="$1"
    local answer

    while true; do
        read -r -p "${message} (y/n): " answer </dev/tty
        case "$answer" in
            [Yy]) return 0 ;;
            [Nn]) return 1 ;;
            *) echo "y 또는 n을 입력하세요." ;;
        esac
    done
}

ui_input() {
    local prompt="$1"
    local default="${2:-}"
    local value

    if [ -n "$default" ]; then
        read -r -p "${prompt} [기본값: ${default}]: " value </dev/tty
        echo "${value:-$default}"
    else
        read -r -p "${prompt}: " value </dev/tty
        echo "$value"
    fi
}
