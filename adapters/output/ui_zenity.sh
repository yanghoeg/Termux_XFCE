#!/data/data/com.termux/files/usr/bin/bash
# =============================================================================
# ADAPTER: ui_zenity.sh
# -----------------------------------------------------------------------------
# Output Adapter — Zenity GUI UI (XFCE 환경에서 사용)
# ui.sh 포트의 zenity 구현체
# DISPLAY=:1.0 환경에서만 동작
# =============================================================================

ui_info() {
    zenity --info \
        --title="Termux XFCE Installer" \
        --text="$1" \
        --width=400 2>/dev/null \
    || echo "[INFO] $1"  # zenity 실패 시 터미널 fallback
}

ui_warn() {
    zenity --warning \
        --title="경고" \
        --text="$1" \
        --width=400 2>/dev/null \
    || echo "[WARN] $1"
}

ui_error() {
    zenity --error \
        --title="오류" \
        --text="$1" \
        --width=400 2>/dev/null \
    || echo "[ERROR] $1" >&2
}

ui_select() {
    local title="$1"
    local prompt="$2"
    shift 2
    local options=("$@")

    local zenity_args=()
    local first=TRUE
    for opt in "${options[@]}"; do
        zenity_args+=("$first" "$opt")
        first=FALSE
    done

    local result
    result=$(zenity --list --radiolist \
        --title="$title" \
        --text="$prompt" \
        --column="선택" --column="항목" \
        "${zenity_args[@]}" \
        --width=500 --height=400 2>/dev/null) || return 1

    echo "$result"
}

ui_confirm() {
    local message="$1"
    zenity --question \
        --title="확인" \
        --text="$message" \
        --width=400 2>/dev/null
}

ui_input() {
    local prompt="$1"
    local default="${2:-}"

    zenity --entry \
        --title="입력" \
        --text="$prompt" \
        --entry-text="$default" \
        --width=400 2>/dev/null
}
