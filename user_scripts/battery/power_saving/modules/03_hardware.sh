#!/usr/bin/env bash
source "$(dirname -- "${BASH_SOURCE[0]}")/../lib/common.sh"

echo
log_step "Module 03: User Hardware Control"

# 1. Brightness
if has_cmd brightnessctl; then
    spin_exec "Lowering brightness to ${BRIGHTNESS_LEVEL}..." \
        brightnessctl set "${BRIGHTNESS_LEVEL}" -q
    log_step "Brightness set to ${BRIGHTNESS_LEVEL}."
else
    log_warn "brightnessctl not found."
fi

# 2. Vendor Specifics (ASUS)
# Only runs if 'asusctl' is installed on the system
if has_cmd asusctl; then
    # We use '|| true' to ensure a profile failure doesn't crash the script
    run_external_script "${ASUS_PROFILE_SCRIPT}" "Applying Quiet Profile..." || true
fi

# 3. Volume Cap
if has_cmd wpctl; then
    raw_output=$(wpctl get-volume @DEFAULT_AUDIO_SINK@ 2>/dev/null) || true
    if [[ -n "${raw_output}" ]]; then
        current_vol=$(awk '{printf "%.0f", $2 * 100}' <<< "${raw_output}")
        
        if is_numeric "${current_vol}" && ((current_vol > VOLUME_CAP)); then
            spin_exec "Volume ${current_vol}% → ${VOLUME_CAP}%..." \
                wpctl set-volume @DEFAULT_AUDIO_SINK@ "${VOLUME_CAP}%"
            log_step "Volume capped at ${VOLUME_CAP}%."
        else
            log_step "Volume at ${current_vol}% (within limit)."
        fi
    fi
else
    log_warn "wpctl not found."
fi
