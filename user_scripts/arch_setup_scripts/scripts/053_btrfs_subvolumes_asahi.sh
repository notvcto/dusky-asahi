#!/usr/bin/env bash
# Creates @log (/var/log) and @pkg (/var/cache/pacman/pkg) BTRFS subvolumes.
# ALARM only ships with @ and @home; this script adds the missing subvolumes
# so logs and package cache are excluded from root snapshots.
# Run as root (S) via ORCHESTRA_ASAHI.sh, before snapper setup.

set -euo pipefail

readonly C_RESET='\e[0m'
readonly C_INFO='\e[1;34m'
readonly C_SUCCESS='\e[1;32m'
readonly C_ERROR='\e[1;31m'
readonly C_WARN='\e[1;33m'

log_info()    { echo -e "${C_INFO}[INFO]${C_RESET}    $*"; }
log_success() { echo -e "${C_SUCCESS}[SUCCESS]${C_RESET} $*"; }
log_error()   { echo -e "${C_ERROR}[ERROR]${C_RESET}   $*" >&2; }
log_warn()    { echo -e "${C_WARN}[WARN]${C_RESET}    $*"; }

TEMP_MNT=""

cleanup() {
    if [[ -n "$TEMP_MNT" ]] && mountpoint -q "$TEMP_MNT" 2>/dev/null; then
        umount "$TEMP_MNT" 2>/dev/null || true
    fi
    [[ -n "$TEMP_MNT" ]] && rmdir "$TEMP_MNT" 2>/dev/null || true
}
trap cleanup EXIT

# ---------------------------------------------------------------------------
# Pre-flight
# ---------------------------------------------------------------------------

if [[ $EUID -ne 0 ]]; then
    log_error "This script must run as root (use S | in ORCHESTRA_ASAHI)."
    exit 1
fi

if [[ "$(stat -f -c %T /)" != "btrfs" ]]; then
    log_warn "Root filesystem is not BTRFS — nothing to do."
    exit 0
fi

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

is_btrfs_subvolume() {
    btrfs subvolume show "$1" >/dev/null 2>&1
}

get_root_device() {
    findmnt -n -o SOURCE --target / | sed 's/\[.*//'
}

get_root_uuid() {
    blkid -s UUID -o value "$(get_root_device)"
}

get_root_mount_opts() {
    # Return existing fstab opts for /, stripping subvol= and subvolid= tokens
    local opts
    opts="$(findmnt -s -n -o OPTIONS --target / 2>/dev/null || findmnt -n -o OPTIONS --target /)"
    # Strip subvol/subvolid so we can supply our own
    echo "$opts" | tr ',' '\n' | grep -Ev '^subvol(id)?=' | tr '\n' ',' | sed 's/,$//'
}

mount_top_level() {
    local device
    device="$(get_root_device)"
    TEMP_MNT="$(mktemp -d)"
    mount -o subvolid=5 "$device" "$TEMP_MNT"
    log_info "Mounted BTRFS top-level at $TEMP_MNT"
}

# ---------------------------------------------------------------------------
# Core: ensure one subvolume exists and is mounted at its target path
# ---------------------------------------------------------------------------
# Args: <subvol_name>  <mount_point>
# Example: ensure_subvolume @log /var/log
# ---------------------------------------------------------------------------

ensure_subvolume() {
    local subvol="$1"
    local target="$2"

    log_info "Checking $subvol → $target"

    # Already a subvolume and mounted — fully done
    if is_btrfs_subvolume "$target" 2>/dev/null; then
        log_success "$target is already a BTRFS subvolume. Skipping."
        return 0
    fi

    # Idempotency: check if fstab already has a subvol= entry for this target
    if grep -qsE "^\s*UUID=\S+\s+${target}\s+btrfs" /etc/fstab; then
        log_warn "fstab already has an entry for $target but it is not mounted as a subvolume. Attempting mount."
        mount "$target" 2>/dev/null || true
        if is_btrfs_subvolume "$target"; then
            log_success "$target now mounted correctly."
            return 0
        fi
    fi

    [[ -n "$TEMP_MNT" ]] || mount_top_level

    # Create the subvolume at the top level if it doesn't exist
    if [[ ! -e "${TEMP_MNT}/${subvol}" ]]; then
        btrfs subvolume create "${TEMP_MNT}/${subvol}" >/dev/null
        log_success "Created BTRFS subvolume: $subvol"
    else
        log_info "Top-level subvolume $subvol already exists."
    fi

    # Migrate existing data into the new subvolume
    local staging="${TEMP_MNT}/${subvol}"
    if [[ -d "$target" ]] && [[ -n "$(ls -A "$target" 2>/dev/null)" ]]; then
        log_info "Migrating existing data from $target into $subvol..."
        cp -a "${target}/." "${staging}/"
        log_success "Data migrated."
    fi

    # Swap: rename old dir to backup, mount subvolume in its place
    local backup="${target}.old_$$"
    mv "$target" "$backup"
    mkdir -p "$target"

    local uuid base_opts mount_opts
    uuid="$(get_root_uuid)"
    base_opts="$(get_root_mount_opts)"
    [[ -n "$base_opts" ]] && mount_opts="${base_opts},subvol=/${subvol}" || mount_opts="subvol=/${subvol}"

    # Mount now so we can verify before writing fstab
    mount -o "$mount_opts" "$(get_root_device)" "$target"

    if ! is_btrfs_subvolume "$target"; then
        # Roll back
        umount "$target"
        rmdir "$target"
        mv "$backup" "$target"
        log_error "Mount succeeded but $target is still not a BTRFS subvolume. Rolled back."
        exit 1
    fi

    # Remove the backup dir (data is now in the subvolume)
    rm -rf "$backup"

    # Write fstab entry
    local fstab_line="UUID=${uuid} ${target} btrfs ${mount_opts} 0 0"
    if ! grep -qsE "^\s*UUID=\S+\s+${target}\s+btrfs" /etc/fstab; then
        echo "$fstab_line" >> /etc/fstab
        log_success "Added fstab entry for $target"
    else
        log_info "fstab entry for $target already present."
    fi

    log_success "$subvol mounted at $target"
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

log_info "BTRFS subvolume setup for ALARM (Asahi)"

ensure_subvolume "@log" "/var/log"
ensure_subvolume "@pkg" "/var/cache/pacman/pkg"

systemctl daemon-reload
log_success "Done. @log and @pkg subvolumes are in place."
