#!/usr/bin/env bash
set -euo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/../lib/common.sh"

printf '\n'
log_step "Module 02: Hardware Control"

# 1. Brightness
if has_cmd brightnessctl; then
    spin_exec "Restoring brightness to ${RESTORE_BRIGHTNESS}..." \
        brightnessctl set "${RESTORE_BRIGHTNESS}" -q
    log_step "Brightness set to ${RESTORE_BRIGHTNESS}."
fi

# 2. Vendor Specifics (ASUS)
# We only run the external script if 'asusctl' is present on this machine.
if has_cmd asusctl; then
    # We use '|| true' to ensure a profile failure doesn't crash the restoration
    run_external_script "${ASUS_PROFILE_SCRIPT}" "Applying System Profile..." || true
fi

# 3. Volume Cap (Reset to 100%)
if has_cmd wpctl; then
    spin_exec "Resetting volume limit..." wpctl set-volume @DEFAULT_AUDIO_SINK@ 1.0
    log_step "Volume limit reset to 100%."
fi
