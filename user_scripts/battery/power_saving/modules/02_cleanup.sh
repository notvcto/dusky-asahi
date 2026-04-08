#!/usr/bin/env bash
source "$(dirname -- "${BASH_SOURCE[0]}")/../lib/common.sh"

echo
log_step "Module 02: Cleanup Processes"

# Kill resource monitors
spin_exec "Cleaning up resource monitors..." pkill -x 'btop|nvtop' || true

# Pause media
if has_cmd playerctl; then
    run_quiet playerctl -a pause
fi
log_step "Resource monitors killed & media paused."

# Warp VPN
if has_cmd warp-cli; then
    spin_exec "Disconnecting Warp..." warp-cli disconnect || true
    log_step "Warp disconnected."
fi
