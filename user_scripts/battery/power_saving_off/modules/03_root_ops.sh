#!/usr/bin/env bash
set -euo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/../lib/common.sh"

if ! sudo -n true 2>/dev/null; then
    log_error "Root privileges required. Skipping."
    exit 1
fi

printf '\n'
log_step "Module 04: Root Operations"

# 1. Unblock Radios (Consolidated)
if has_cmd rfkill; then
    spin_exec "Unblocking Bluetooth & Wi-Fi..." \
        bash -c "sudo rfkill unblock bluetooth && sudo rfkill unblock wifi"
    log_step "Wireless devices unblocked."
fi

# 2. TLP - AC Mode
if has_cmd tlp; then
    spin_exec "Activating TLP AC mode..." sudo tlp ac
    log_step "TLP AC mode activated."
fi
