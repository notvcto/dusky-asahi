#!/usr/bin/env bash
# power_saving_off/restore_performance.sh - RESTORE PERFORMANCE
# -----------------------------------------------------------------------------
set -euo pipefail

# --- Path Resolution ---
readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
readonly LIB_DIR="${SCRIPT_DIR}/lib"
readonly MODULES_DIR="${SCRIPT_DIR}/modules"

# --- Source Common Library ---
if [[ ! -f "${LIB_DIR}/common.sh" ]]; then
    printf '\033[1;31mFATAL: common.sh not found at %s\033[0m\n' "${LIB_DIR}/common.sh" >&2
    exit 1
fi
source "${LIB_DIR}/common.sh"

# --- Dependency Check ---
if ! has_cmd gum; then
    printf 'Error: gum is required for interactive prompts.\n' >&2
    exit 1
fi

# --- Module Runner ---
run_module() {
    local module="$1"
    local desc="${2:-Running ${module##*/}...}"
    
    if [[ -x "${module}" ]]; then
        spin_exec "${desc}" "${module}"
    elif [[ -f "${module}" ]]; then
        # Silent return if found but not executable
        return 0
    else
        # Silent return if file doesn't exist (optional module)
        return 0 
    fi
}

# --- Sudo Keepalive ---
start_sudo_keepalive() {
    ( while true; do sudo -n true; sleep 50; done ) &>/dev/null &
    SUDO_KEEPALIVE_PID=$!
    trap 'kill "${SUDO_KEEPALIVE_PID}" 2>/dev/null || true' EXIT
}

# =============================================================================
# INTERACTIVE PROMPTS
# =============================================================================
clear
# Generic Header for Public Use
gum style --border double --margin "1" --padding "1 2" \
    --border-foreground 46 --foreground 46 \
    "PERFORMANCE MODE: RESTORE"

# Theme prompt
export RESTORE_THEME="false"
gum style --foreground 245 --italic "Rationale: Return to standard Dark Mode."
if gum confirm "Switch to Dark Mode?" --affirmative "Yes" --negative "No"; then
    export RESTORE_THEME="true"
    log_step "Theme switch queued."
fi

# =============================================================================
# USER MODULES
# =============================================================================
run_module "${MODULES_DIR}/01_visuals.sh" "Module 01: Visuals..."
run_module "${MODULES_DIR}/02_hardware.sh" "Module 02: Hardware..."

# =============================================================================
# ROOT MODULES
# =============================================================================
printf '\n'
gum style --border normal --border-foreground 196 --foreground 196 \
    "PRIVILEGE ESCALATION"

if sudo -v; then
    start_sudo_keepalive
    run_module "${MODULES_DIR}/03_root_ops.sh" "Module 03: Root Operations..."
    run_module "${MODULES_DIR}/06_service_restorer.sh" "Module 06: Services..." || true
else
    log_error "Sudo authentication failed. Skipping root modules."
fi

# =============================================================================
# DEFERRED
# =============================================================================
run_module "${MODULES_DIR}/04_theme.sh" "Module 04: Theme..."

printf '\n'
gum style --foreground 46 --bold "✓ DONE: Performance Mode Active"
