#!/usr/bin/env bash
source "$(dirname -- "${BASH_SOURCE[0]}")/../lib/common.sh"

# Verify sudo privileges
if ! sudo -n true 2>/dev/null; then
    log_error "Root privileges required. Skipping root module."
    exit 1
fi

echo
log_step "Module 04: Root Operations (Privileged)"

# 1. Bluetooth
if has_cmd rfkill; then
    spin_exec "Blocking Bluetooth..." sudo rfkill block bluetooth
    log_step "Bluetooth blocked."
fi

# 2. Wi-Fi (Conditional)
if [[ "${POWER_SAVER_WIFI:-false}" == "true" ]]; then
    if has_cmd rfkill; then
        spin_exec "Blocking Wi-Fi (Hardware)..." sudo rfkill block wifi
        log_step "Wi-Fi blocked."
    fi
else
    log_step "Skipping Wi-Fi block (user request)."
fi

# 3. TLP - Force battery mode
if has_cmd tlp; then
    spin_exec "Activating TLP battery mode..." sudo tlp bat
    log_step "TLP battery mode activated."
fi
