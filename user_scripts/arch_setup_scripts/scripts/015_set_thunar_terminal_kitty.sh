#!/usr/bin/env bash
# Sets up "right click to open in terminal" for thunar
# Environment: Arch Linux / Hyprland / UWSM
# Author: Elite DevOps Engineer
#
# Principles:
# 1. No root privileges (modifies User Home).
# 2. Idempotent (safe to run multiple times).
# 3. No artifacts (clean cleanup via traps).
# 4. Atomic operations (verify before overwrite).

set -euo pipefail

# --- Configuration ---
readonly THUNAR_DIR="${HOME}/.config/Thunar"
readonly UCA_FILE="${THUNAR_DIR}/uca.xml"
readonly TARGET_CMD="kitty %f"
readonly ACTION_NAME="Open Terminal Here"

# --- Styling (Terminal Detection) ---
# Only use colors if stdout is a terminal (tty)
if [[ -t 1 ]]; then
    readonly GREEN=$'\e[32m'
    readonly BLUE=$'\e[34m'
    readonly RED=$'\e[31m'
    readonly RESET=$'\e[0m'
else
    readonly GREEN="" BLUE="" RED="" RESET=""
fi

# --- State Tracking ---
CURRENT_TEMP_FILE=""

# --- Logging Functions ---
log_info()    { printf "%s[INFO]%s %s\n" "${BLUE}" "${RESET}" "$1"; }
log_success() { printf "%s[OK]%s %s\n" "${GREEN}" "${RESET}" "$1"; }
log_err()     { printf "%s[ERROR]%s %s\n" "${RED}" "${RESET}" "$1" >&2; }

# --- Cleanup Trap ---
cleanup() {
    if [[ -n "${CURRENT_TEMP_FILE}" && -f "${CURRENT_TEMP_FILE}" ]]; then
        rm -f -- "${CURRENT_TEMP_FILE}"
    fi
}
trap cleanup EXIT

# --- Privilege Check ---
if (( EUID == 0 )); then
    log_err "This script manages user dotfiles. Do not run as root/sudo."
    exit 1
fi

# --- Helper Functions ---
generate_uid() {
    # Generates a pseudo-unique ID based on nanoseconds
    printf '%s-1' "$(date +%s%N | cut -c1-16)"
}

# --- Main Logic ---
main() {
    # Ensure Thunar config directory exists (mkdir -p is idempotent)
    mkdir -p -- "${THUNAR_DIR}"

    # 1. Handle Missing File: Create fresh XML
    if [[ ! -f "${UCA_FILE}" ]]; then
        log_info "Configuration file not found. Creating new uca.xml..."
        
        local uid
        uid="$(generate_uid)"

        cat > "${UCA_FILE}" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<actions>
<action>
    <icon>utilities-terminal</icon>
    <name>${ACTION_NAME}</name>
    <submenu></submenu>
    <unique-id>${uid}</unique-id>
    <command>${TARGET_CMD}</command>
    <description>Open kitty in current folder</description>
    <range></range>
    <patterns>*</patterns>
    <startup-notify/>
    <directories/>
</action>
</actions>
EOF
        log_success "Created ${UCA_FILE} with Kitty configured."
        return 0
    fi

    # 2. Handle Existing File: Update or Inject
    log_info "Found existing uca.xml. Validating..."

    # Check if action exists
    if grep -q -- "<name>${ACTION_NAME}</name>" "${UCA_FILE}"; then
        log_info "Action '${ACTION_NAME}' exists. Updating command..."
        
        # Update using sed
        sed -i "/<name>${ACTION_NAME}<\/name>/,/<\/action>/ s|<command>.*</command>|<command>${TARGET_CMD}</command>|" "${UCA_FILE}"
        
        # Verify the update actually happened
        if grep -q -- "<command>${TARGET_CMD}</command>" "${UCA_FILE}"; then
            log_success "Updated existing action to use Kitty."
        else
            log_err "Failed to update command. Manual intervention required."
            exit 1
        fi
    else
        log_info "Action '${ACTION_NAME}' missing. Injecting..."
        
        # Sanity check for closing tag
        if ! grep -q -- "</actions>" "${UCA_FILE}"; then
            log_err "File is malformed (missing </actions>). Manual intervention required."
            exit 1
        fi

        local uid
        uid="$(generate_uid)"

        local block="<action>
    <icon>utilities-terminal</icon>
    <name>${ACTION_NAME}</name>
    <submenu></submenu>
    <unique-id>${uid}</unique-id>
    <command>${TARGET_CMD}</command>
    <description>Open kitty in current folder</description>
    <range></range>
    <patterns>*</patterns>
    <startup-notify/>
    <directories/>
</action>"

        CURRENT_TEMP_FILE=$(mktemp)
             
        # Inject the block
        awk -v block="$block" '
            /<\/actions>/ { print block }
            { print }
        ' "${UCA_FILE}" > "${CURRENT_TEMP_FILE}" 
        
        # SAFETY CHECK: Ensure awk didn't produce an empty file
        if [[ ! -s "${CURRENT_TEMP_FILE}" ]]; then
            log_err "Processing produced empty output. Aborting to prevent data loss."
            exit 1
        fi

        # Move temp file over original
        mv -- "${CURRENT_TEMP_FILE}" "${UCA_FILE}"
        CURRENT_TEMP_FILE=""
        
        log_success "Injected Kitty action into existing configuration."
    fi
}

main
