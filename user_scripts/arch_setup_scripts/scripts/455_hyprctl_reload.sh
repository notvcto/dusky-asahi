#!/usr/bin/env bash
# hyprctl reload to refresh hyprland
# Description: Safely reloads Hyprland configuration with timeout protection.

set -u

# 1. Safety Checks
if (( EUID == 0 )); then
    printf 'Error: This script must run as user, not root.\n' >&2
    exit 1
fi

# Exit silently if Hyprland socket is missing (e.g. TTY/SSH) or binary not found
if [[ -z "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]] || ! command -v hyprctl &>/dev/null; then
    exit 0
fi

# 2. Execution (5s timeout to prevent hanging the update process)
if timeout 5s hyprctl reload >/dev/null; then
    
    # Visual Feedback (Non-blocking)
    if command -v notify-send &>/dev/null; then
        notify-send "System Update" "Hyprland configuration reloaded" \
            -i system-software-update \
            -u low \
            -t 3000 \
            -a "Update Script" &>/dev/null || true
    fi

    printf '%s[OK   ]%s Hyprland reloaded.\n' $'\e[1;32m' $'\e[0m'

else
    # Soft fail: log warning but do not break the orchestrator
    printf '%s[WARN ]%s Hyprland reload timed out or failed.\n' $'\e[1;33m' $'\e[0m' >&2
    exit 0
fi
