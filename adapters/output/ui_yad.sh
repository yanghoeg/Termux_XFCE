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

    # yad --radiolist 는 첫 컬럼을 라디오 버튼으로 사용하므로 TRUE/FALSE 를 prepend
    # (zenity 어댑터와 동일 패턴). print-column=2 로 값 컬럼만 출력시켜 파싱 단순화.
    local rows=()
    local first=TRUE
    for opt in "${options[@]}"; do
        rows+=("$first" "$opt")
        first=FALSE
    done

    local result
    result=$(yad --list --radiolist \
        --title="$title" \
        --text="$prompt" \
        --column="선택:RD" --column="항목:TEXT" \
        --print-column=2 \
        --search-column=2 \
        "${rows[@]}" \
        --width=500 --height=400 --center 2>/dev/null) || return 1

    # yad 는 "값|" 형태로 반환 → trailing 구분자 제거
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
