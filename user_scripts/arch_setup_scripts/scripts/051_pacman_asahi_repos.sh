#!/usr/bin/env bash
# Add the Asahi Alarm pacman overlay repository and install asahi-alarm-keyring
# -----------------------------------------------------------------------------
# The [asahi-alarm] overlay repo (github.com/asahi-alarm/asahi-alarm) provides:
#   - asahi-alarm-keyring  : Signing keys for the repo
#   - mesa (patched)       : Mesa with upstream AGX GPU driver (replaces ALARM mesa)
#   - linux-asahi          : Asahi kernel (already installed; kept up to date)
#   - alsa-ucm-conf-asahi  : ALSA UCM profiles for Apple Silicon audio
#   + other Apple Silicon platform packages
#
# The repo is distributed via GitHub Releases at:
#   https://github.com/asahi-alarm/asahi-alarm/releases/download/$arch
#
# Run order: after 040_pacman_config.sh, before 060_package_installation_asahi.sh
# Privilege: S (root)
# -----------------------------------------------------------------------------

set -euo pipefail

readonly C_RESET=$'\033[0m'
readonly C_INFO=$'\033[1;34m'
readonly C_SUCCESS=$'\033[1;32m'
readonly C_ERROR=$'\033[1;31m'
readonly C_WARN=$'\033[1;33m'

log_info()    { printf '%s[INFO]%s %s\n'    "${C_INFO}"    "${C_RESET}" "$*"; }
log_success() { printf '%s[OK]%s   %s\n'    "${C_SUCCESS}" "${C_RESET}" "$*"; }
log_warn()    { printf '%s[WARN]%s %s\n'    "${C_WARN}"    "${C_RESET}" "$*" >&2; }
log_error()   { printf '%s[ERROR]%s %s\n'   "${C_ERROR}"   "${C_RESET}" "$*" >&2; exit 1; }

# Self-elevate if not root
if [[ $EUID -ne 0 ]]; then
    log_info "Root privileges required. Elevating..."
    exec sudo bash "$(realpath "$0")" "$@"
fi

readonly PACMAN_CONF="/etc/pacman.conf"
readonly MIRRORLIST="/etc/pacman.d/mirrorlist.asahi-alarm"
readonly ASAHI_REPO_HEADER="[asahi-alarm]"
readonly ASAHI_REPO_BLOCK_BOOTSTRAP="[asahi-alarm]
Include = /etc/pacman.d/mirrorlist.asahi-alarm
SigLevel = Never"
readonly ASAHI_REPO_BLOCK_SIGNED="[asahi-alarm]
Include = /etc/pacman.d/mirrorlist.asahi-alarm
SigLevel = Required DatabaseOptional"

# ── Step 1: Write the mirrorlist file ────────────────────────────────────────

if [[ ! -f "${MIRRORLIST}" ]]; then
    log_info "Writing ${MIRRORLIST}..."
    cat >"${MIRRORLIST}" <<'EOF'
#
# Asahi Alarm repository mirrorlist
#
Server = https://github.com/asahi-alarm/asahi-alarm/releases/download/$arch
EOF
    log_success "Mirrorlist written."
else
    log_info "${MIRRORLIST} already exists — skipping."
fi

# ── Step 1a: Ensure sudo is installed ────────────────────────────────────────
# ALARM base does not include sudo. Required by paru, makepkg, and user scripts.

if ! command -v sudo &>/dev/null; then
    log_info "sudo not found — installing..."
    pacman -S --needed --noconfirm sudo
    log_success "sudo installed."
fi

# ── Step 1b: Ensure /etc/sudoers.d is included ───────────────────────────────
# ALARM ships a minimal /etc/sudoers with no #includedir directive.
# Without it, sudoers.d drop-ins (including the NOPASSWD rule written by
# 485_sudoers_nopassword.sh) are silently ignored — breaking paru and AUR builds.

if [[ ! -f /etc/sudoers ]]; then
    log_info "Creating /etc/sudoers (missing on minimal ALARM install)..."
    printf '%%wheel ALL=(ALL:ALL) ALL\n#includedir /etc/sudoers.d\n' > /etc/sudoers
    chmod 440 /etc/sudoers
    log_success "/etc/sudoers created."
elif ! grep -qF '#includedir /etc/sudoers.d' /etc/sudoers; then
    log_info "Adding '#includedir /etc/sudoers.d' to /etc/sudoers (ALARM default is missing it)..."
    printf '\n#includedir /etc/sudoers.d\n' >> /etc/sudoers
    log_success "/etc/sudoers.d drop-ins enabled."
fi

# ── Step 2: Add [asahi-alarm] repo to pacman.conf if not already present ────

# ── Step 2a: Remove stale [asahi] block if present (old pkg.asahi.dev URL) ───

if grep -qF '[asahi]' "$PACMAN_CONF"; then
    log_warn "Removing stale [asahi] repo block (pkg.asahi.dev) from $PACMAN_CONF..."
    sed -i '/^\[asahi\]$/,/^$/d' "$PACMAN_CONF"
    log_success "Stale [asahi] block removed."
fi

# ── Step 2b: Add [asahi-alarm] repo block ────────────────────────────────────

if grep -qF "$ASAHI_REPO_HEADER" "$PACMAN_CONF"; then
    log_info "[asahi-alarm] repo already present in $PACMAN_CONF — skipping addition."
else
    log_info "Adding [asahi-alarm] repo to $PACMAN_CONF (SigLevel=Never for bootstrap)..."

    # Insert before [core] or append at end of file
    if grep -qF '[core]' "$PACMAN_CONF"; then
        local_tmp=$(mktemp)
        chmod 644 "$local_tmp"
        awk -v block="$ASAHI_REPO_BLOCK_BOOTSTRAP" '
            /^\[core\]/ && !inserted { print block; print ""; inserted=1 }
            { print }
        ' "$PACMAN_CONF" >"$local_tmp"
        mv -f "$local_tmp" "$PACMAN_CONF"
    else
        printf '\n%s\n' "$ASAHI_REPO_BLOCK_BOOTSTRAP" >>"$PACMAN_CONF"
    fi

    log_success "[asahi-alarm] repo block added to $PACMAN_CONF (SigLevel=Never)."
fi

# ── Step 3: Sync the new repo and install asahi-alarm-keyring ────────────────
# SigLevel=Never lets pacman sync the asahi-alarm DB and install the keyring
# without yet having the keys trusted. The keyring package itself adds the keys.

if grep -qF 'SigLevel = Never' "$PACMAN_CONF"; then
    log_info "Syncing pacman databases (bootstrap mode, SigLevel=Never)..."
else
    log_info "Syncing pacman databases..."
fi
pacman -Sy --noconfirm

log_info "Installing asahi-alarm-keyring..."
if pacman -S --needed --noconfirm asahi-alarm-keyring; then
    log_success "asahi-alarm-keyring installed."
else
    log_warn "asahi-alarm-keyring install failed. Continuing — you may need to run this step manually."
fi

# ── Step 4: Populate keyring and upgrade SigLevel to Required ────────────────

log_info "Populating asahi-alarm keyring..."
pacman-key --populate asahi-alarm 2>/dev/null || \
    log_warn "pacman-key --populate asahi-alarm failed (keyring may auto-populate on next pacman run)"

if grep -qF 'SigLevel = Never' "$PACMAN_CONF"; then
    log_info "Upgrading [asahi-alarm] SigLevel to Required DatabaseOptional..."
    # Replace the full bootstrap block with the signed block
    local_tmp=$(mktemp)
    chmod 644 "$local_tmp"
    awk -v bootstrap="$ASAHI_REPO_BLOCK_BOOTSTRAP" -v signed="$ASAHI_REPO_BLOCK_SIGNED" '
        BEGIN { n=split(bootstrap,blines,"\n") }
        {
            if ($0 == blines[1]) {
                in_block=1; buf=$0"\n"; bi=1; next
            }
            if (in_block) {
                bi++; buf=buf $0"\n"
                if (bi == n) {
                    print signed; in_block=0; buf=""
                }
                next
            }
            print
        }
    ' "$PACMAN_CONF" >"$local_tmp"
    mv -f "$local_tmp" "$PACMAN_CONF"
    log_success "SigLevel upgraded to Required DatabaseOptional."
fi

# ── Step 5: Final sync with signatures required ───────────────────────────────

log_info "Final pacman database sync (signed mode)..."
pacman -Sy --noconfirm
log_success "Asahi Alarm overlay repo setup complete."
log_info "Note: patched mesa (AGX GPU driver) will be pulled in by 060_package_installation_asahi.sh"
