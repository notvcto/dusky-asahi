#!/usr/bin/env bash
# Configure SDDM to use its native Wayland compositor on Asahi Linux
# -----------------------------------------------------------------------------
# On Asahi / Apple Silicon, Xorg is not available. SDDM must run in Wayland
# mode (its built-in Qt Wayland compositor) rather than defaulting to X11.
#
# Without this config SDDM fails silently at the display-server launch step
# and the machine sits at a black screen after the boot splash.
#
# This drop-in is numbered 466 so it runs immediately after 465_sddm_setup.sh
# and is additive (does not overwrite the theme config written by 465).
#
# Privilege: S (root)
# -----------------------------------------------------------------------------

set -euo pipefail

readonly C_RESET=$'\033[0m'
readonly C_INFO=$'\033[1;34m'
readonly C_SUCCESS=$'\033[1;32m'
readonly C_WARN=$'\033[1;33m'

log_info()    { printf '%s[INFO]%s %s\n'    "${C_INFO}"    "${C_RESET}" "$*"; }
log_success() { printf '%s[OK]%s   %s\n'    "${C_SUCCESS}" "${C_RESET}" "$*"; }
log_warn()    { printf '%s[WARN]%s %s\n'    "${C_WARN}"    "${C_RESET}" "$*" >&2; }

if [[ $EUID -ne 0 ]]; then
    log_info "Root privileges required. Elevating..."
    exec sudo bash "$(realpath "$0")" "$@"
fi

readonly CONF_FILE="/etc/sddm.conf.d/20-asahi-wayland.conf"

if [[ -f "$CONF_FILE" ]]; then
    log_info "${CONF_FILE} already exists — skipping."
    exit 0
fi

mkdir -p /etc/sddm.conf.d

cat > "$CONF_FILE" <<'EOF'
# Asahi Linux / Apple Silicon — SDDM Wayland backend
#
# Xorg is not available on Apple Silicon. SDDM must use its native Qt Wayland
# compositor (KWin-free, DRM/KMS direct). Without this setting, SDDM cannot
# launch a display server and the login screen never appears.
[General]
DisplayServer=wayland
EOF

log_success "SDDM Wayland config written: ${CONF_FILE}"
log_info "SDDM will use the Qt Wayland compositor (direct DRM/KMS via AGX)."
