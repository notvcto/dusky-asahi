#!/usr/bin/env bash
# Enables systemd system services for Asahi Linux / Apple Silicon
# ==============================================================================
# Asahi-adapted version of 290_system_services.sh
#
# Changes from x86 version:
#   - Removed: tlp.service, thermald.service  (Intel power management daemons,
#               not applicable on Apple Silicon)
#   - Removed: reflector.timer  (x86 Arch mirrorlist only; ALARM uses its own)
#   - Added:   power-profiles-daemon.service  (Apple Silicon power management
#               via upower/ppd; coordinates with the Asahi platform driver)
# ==============================================================================

set -euo pipefail
IFS=$'\n\t'

trap 'exit_code=$?; [[ $exit_code -ne 0 ]] && printf "\n[!] Script failed with code %d\n" "$exit_code"' EXIT

readonly TARGET_SERVICES=(
    "NetworkManager.service"
    "power-profiles-daemon.service"   # Apple Silicon power management (replaces TLP)
    "udisks2.service"
    "bluetooth.service"
    "ufw.service"
    "fstrim.timer"
    "systemd-timesyncd.service"
    # acpid.service removed: x86 ACPI event daemon, not applicable on Apple Silicon
    "iio-sensor-proxy.service"  # ambient light sensor / auto-brightness (MacBook)
    "vsftpd.service"
    # swayosd removed (switched to mako OSD)
    "systemd-resolved.service"
)

if [[ $EUID -ne 0 ]]; then
   printf "[\033[0;33mINFO\033[0m] Escalating permissions to root...\n"
   exec sudo "$0" "$@"
fi

log_info()    { printf "[\033[0;34mINFO\033[0m] %s\n" "$1"; }
log_success() { printf "[\033[0;32m OK \033[0m] %s\n" "$1"; }
log_warn()    { printf "[\033[0;33mWARN\033[0m] %s\n" "$1"; }
log_err()     { printf "[\033[0;31mERR \033[0m] %s\n" "$1"; }

enable_service() {
    local service="$1"

    if systemctl list-unit-files "$service" &>/dev/null; then
        if systemctl is-enabled --quiet "$service"; then
            log_info "$service is already enabled."
        else
            if systemctl enable --now "$service" &>/dev/null; then
                log_success "Enabled & Started: $service"
            else
                log_err "Failed to enable: $service (Check logs)"
            fi
        fi
    else
        log_warn "Skipping: $service (Package not installed / Unit not found)"
    fi
}

main() {
    printf "\n--- Asahi System Service Setup ---\n"

    for service in "${TARGET_SERVICES[@]}"; do
        enable_service "$service"
    done

    # ── Keyboard backlight permissions ────────────────────────────────────────
    # On Asahi, /sys/class/leds/kbd_backlight/brightness is root-only by default.
    # brightnessctl (used by osd_router.sh) needs write access for the video group.
    local udev_rule="/etc/udev/rules.d/90-asahi-kbd-backlight.rules"
    if [[ ! -f "$udev_rule" ]]; then
        log_info "Writing keyboard backlight udev rule..."
        cat >"$udev_rule" <<'EOF'
# Allow video group to control Apple Silicon keyboard backlight
ACTION=="add", SUBSYSTEM=="leds", KERNEL=="kbd_backlight", \
  RUN+="/bin/chgrp video /sys/class/leds/%k/brightness", \
  RUN+="/bin/chmod g+w /sys/class/leds/%k/brightness"
EOF
        udevadm control --reload-rules
        # Apply immediately without reboot
        if [[ -w /sys/class/leds/kbd_backlight/brightness ]]; then
            : # already writable
        else
            chgrp video /sys/class/leds/kbd_backlight/brightness 2>/dev/null || true
            chmod g+w  /sys/class/leds/kbd_backlight/brightness 2>/dev/null || true
        fi
        log_success "Keyboard backlight udev rule installed."
    else
        log_info "Keyboard backlight udev rule already present — skipping."
    fi

    printf "\n--- Operation Complete ---\n"
}

main
