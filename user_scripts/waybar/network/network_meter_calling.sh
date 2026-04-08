#!/usr/bin/env bash
# waybar-net: Minimal JSON output for Waybar (Zero-Fork Edition)

# 1. OPTIMIZATION: Use ${UID} (Bash variable) instead of $(id -u) (Process fork)
STATE_DIR="${XDG_RUNTIME_DIR:-/run/user/${UID}}/waybar-net"
STATE_FILE="$STATE_DIR/state"
HEARTBEAT_FILE="$STATE_DIR/heartbeat"
PID_FILE="$STATE_DIR/daemon.pid"

# Defaults
UNIT="-" UP="-" DOWN="-" CLASS="network-disconnected"

# Read state (fast: tmpfs)
# Added "|| true" to prevent exit on read failure if file is being rotated
[[ -r "$STATE_FILE" ]] && read -r UNIT UP DOWN CLASS < "$STATE_FILE" || true

# Signal daemon via heartbeat
mkdir -p "$STATE_DIR"
touch "$HEARTBEAT_FILE"

# OPTIMIZATION: Only kill if PID file exists and process is actually running
if [[ -r "$PID_FILE" ]]; then
    read -r DAEMON_PID < "$PID_FILE"
    # 0 signal checks if process exists without killing it
    if [[ -n "$DAEMON_PID" ]] && kill -0 "$DAEMON_PID" 2>/dev/null; then
        kill -USR1 "$DAEMON_PID" 2>/dev/null || true
    fi
fi

# Fixed-width formatter (3 chars) - Keeps UI stable
fmt() {
    local s="${1:--}" len=${#1}
    if (( len == 1 )); then printf ' %s ' "$s"
    elif (( len == 2 )); then printf ' %s' "$s"
    else printf '%.3s' "$s"
    fi
}

D_UNIT=$(fmt "$UNIT")
D_UP=$(fmt "$UP")
D_DOWN=$(fmt "$DOWN")

# Tooltip
if [[ "$CLASS" == "network-disconnected" ]]; then
    TT="Disconnected"
else
    TT="Upload: ${UP} ${UNIT}/s\\nDownload: ${DOWN} ${UNIT}/s"
fi

# Output
case "${1:-}" in
    --vertical|vertical)     TEXT="${D_UP}\\n${D_UNIT}\\n${D_DOWN}" ;;
    --horizontal|horizontal) TEXT="${D_UP} ${D_UNIT} ${D_DOWN}" ;;
    unit)                    TEXT="$D_UNIT" ;;
    up|upload)               TEXT="$D_UP" ;;
    down|download)           TEXT="$D_DOWN" ;;
    *)                       printf '{}\n'; exit 0 ;;
esac

printf '{"text":"%s","class":"%s","tooltip":"%s"}\n' "$TEXT" "$CLASS" "$TT"
