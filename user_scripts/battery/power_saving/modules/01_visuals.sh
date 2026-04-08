#!/usr/bin/env bash
source "$(dirname -- "${BASH_SOURCE[0]}")/../lib/common.sh"

echo
log_step "Module 01: Visual Effects"

if ! has_cmd uwsm-app; then
    log_warn "uwsm-app not found. Skipping visual effects."
    exit 0
fi

# Disable blur/opacity/shadow
run_external_script "${BLUR_SCRIPT}" "Disabling blur/opacity/shadow..." off

# Disable Hyprshade
if has_cmd hyprshade; then
    spin_exec "Disabling Hyprshade..." uwsm-app -- hyprshade off
fi

log_step "Visual effects configuration complete."
