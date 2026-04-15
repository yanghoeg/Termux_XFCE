#!/data/data/com.termux/files/usr/bin/bash
# =============================================================================
# ADAPTER: ui_yad.sh
# -----------------------------------------------------------------------------
# Output Adapter — Yet Another Dialog (zenity 상위호환)
# ui.sh 포트의 yad 구현체. zenity와 달리 --list에 검색 입력창이 있어
# 앱 레지스트리가 늘어나도 빠르게 필터링 가능 (app-installer에서 사용).
# DISPLAY 필요.
# =============================================================================

ui_info() {
    yad --info \
        --title="Termux XFCE Installer" \
        --text="$1" \
        --width=400 --button=OK:0 --center 2>/dev/null \
    || echo "[INFO] $1"
}

ui_warn() {
    yad --warning \
        --title="경고" \
        --text="$1" \
        --width=400 --button=OK:0 --center 2>/dev/null \
    || echo "[WARN] $1"
}

ui_error() {
    yad --error \
        --title="오류" \
        --text="$1" \
        --width=400 --button=OK:0 --center 2>/dev/null \
    || echo "[ERROR] $1" >&2
}

ui_select() {
    local title="$1"
    local prompt="$2"
    shift 2
    local options=("$@")

    local rows=()
    for opt in "${options[@]}"; do
        rows+=("$opt")
    done

    local result
    result=$(yad --list --radiolist \
        --title="$title" \
        --text="$prompt" \
        --column="항목" \
        --search-column=1 \
        "${rows[@]}" \
        --width=500 --height=400 --center 2>/dev/null) || return 1

    # yad는 "항목|" 형태로 반환 → 구분자 제거
    echo "${result%|}"
}

ui_confirm() {
    local message="$1"
    yad --question \
        --title="확인" \
        --text="$message" \
        --width=400 --center 2>/dev/null
}

ui_input() {
    local prompt="$1"
    local default="${2:-}"

    yad --entry \
        --title="입력" \
        --text="$prompt" \
        --entry-text="$default" \
        --width=400 --center 2>/dev/null
}
