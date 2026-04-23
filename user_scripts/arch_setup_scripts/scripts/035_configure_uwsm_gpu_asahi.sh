#!/usr/bin/env bash
# Configure UWSM GPU environment for Apple Silicon (Asahi Linux)
# -----------------------------------------------------------------------------
# Replaces 035_configure_uwsm_gpu.sh for Asahi Linux.
# The Apple AGX GPU does not appear as a PCI device, so the standard
# sysfs vendor-ID detection path does not apply. This script finds the
# non-PCI DRM node exposed by the AGX kernel driver and writes the
# appropriate UWSM env.d/gpu file.
# -----------------------------------------------------------------------------

set -euo pipefail
shopt -s nullglob

readonly UWSM_CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/uwsm"
readonly ENV_DIR="$UWSM_CONFIG_DIR/env.d"
readonly OUTPUT_FILE="$ENV_DIR/gpu"

if [[ -t 2 ]]; then
    readonly BOLD=$'\033[1m'
    readonly BLUE=$'\033[34m'
    readonly GREEN=$'\033[32m'
    readonly YELLOW=$'\033[33m'
    readonly RED=$'\033[31m'
    readonly RESET=$'\033[0m'
else
    readonly BOLD='' BLUE='' GREEN='' YELLOW='' RED='' RESET=''
fi

# All log functions write to stderr so stdout stays clean for data capture.
log_info() { printf '%s[INFO]%s %s\n' "${BLUE}${BOLD}" "${RESET}" "$*" >&2; }
log_ok()   { printf '%s[OK]%s   %s\n' "${GREEN}${BOLD}" "${RESET}" "$*" >&2; }
log_warn() { printf '%s[WARN]%s %s\n' "${YELLOW}${BOLD}" "${RESET}" "$*" >&2; }
log_err()  { printf '%s[ERROR]%s %s\n' "${RED}${BOLD}" "${RESET}" "$*" >&2; }

TEMP_OUTPUT=''
cleanup() { if [[ -n "${TEMP_OUTPUT:-}" ]]; then rm -f -- "$TEMP_OUTPUT"; fi; }
trap cleanup EXIT

# Confirm we are on Apple Silicon via device tree model string.
detect_apple_silicon() {
    local model=''
    if [[ -r /proc/device-tree/model ]]; then
        model=$(tr -d '\0' </proc/device-tree/model 2>/dev/null || true)
        if [[ "$model" == *Apple* ]]; then
            log_info "Confirmed Apple Silicon: $model"
            return 0
        fi
    fi
    log_warn "Could not confirm Apple Silicon via device tree — proceeding anyway."
}

# Find the Apple Silicon KMS display controller node for AQ_DRM_DEVICES.
#
# Apple Silicon exposes two separate DRM devices:
#   card1  — AGX GPU (406xxxxxxx.gpu): render/compute only, NOT a KMS device.
#             Aquamarine skips this because libseat reports it has no KMS.
#   card2  — DCP display controller (soc:display-subsystem): the actual KMS
#             device that drives the screen. This is what AQ_DRM_DEVICES needs.
#   renderD128 — AGX render node; Aquamarine finds this automatically from card2.
#
# Strategy: prefer the device whose sysfs path contains "display-subsystem"
# (the DCP/KMS controller). Fall back to any card with connector subdirs
# (another KMS indicator), then to the first non-PCI card.
find_apple_gpu_node() {
    local card_path dev_node vendor_id real_dev
    local kms_node='' fallback_node=''

    for card_path in /sys/class/drm/card[0-9]*; do
        dev_node="/dev/dri/${card_path##*/}"
        [[ -e "$dev_node" ]] || continue

        if [[ -r "$card_path/device/vendor" ]]; then
            vendor_id=$(<"$card_path/device/vendor")
            case "${vendor_id,,}" in
                0x8086|0x1002|0x10de)
                    log_warn "Skipping PCI GPU node $dev_node (vendor: $vendor_id)"
                    continue
                    ;;
            esac
        fi

        real_dev=$(readlink -f "$card_path/device" 2>/dev/null || true)

        # Prefer the DCP display controller (KMS, drives the screen)
        if [[ "$real_dev" == *"display-subsystem"* ]]; then
            kms_node="$dev_node"
            log_info "Found Apple DCP display controller (KMS): $dev_node"
            break
        fi

        # Alternative KMS indicator: card has connector subdirectories
        local connectors=("$card_path"/card*-*/)
        if [[ ${#connectors[@]} -gt 0 && -e "${connectors[0]}" ]]; then
            kms_node="$dev_node"
            log_info "Found KMS device with connectors: $dev_node"
            break
        fi

        # Record first non-PCI card as last-resort fallback
        [[ -z "$fallback_node" ]] && fallback_node="$dev_node"
    done

    local found_node="${kms_node:-$fallback_node}"

    # Final fallback: first card in the system
    if [[ -z "$found_node" ]]; then
        local fallback_cards=(/sys/class/drm/card[0-9]*)
        if (( ${#fallback_cards[@]} > 0 )); then
            found_node="/dev/dri/${fallback_cards[0]##*/}"
            log_warn "No KMS node found — falling back to $found_node"
        fi
    fi

    printf '%s' "$found_node"
}

main() {
    log_info "Configuring UWSM GPU environment for Apple Silicon (Asahi Linux)..."
    detect_apple_silicon

    local gpu_node
    gpu_node=$(find_apple_gpu_node)

    if [[ -z "$gpu_node" ]]; then
        log_err "No DRM card nodes found under /sys/class/drm. Is the Asahi kernel booted?"
        exit 1
    fi

    log_info "Selected KMS display node: $gpu_node"
    mkdir -p -- "$ENV_DIR"

    TEMP_OUTPUT=$(mktemp "$ENV_DIR/.gpu.XXXXXX")

    {
        printf '# -----------------------------------------------------------------\n'
        printf '# UWSM GPU Config | Asahi Linux / Apple Silicon\n'
        printf '# GPU Node: %s\n' "$gpu_node"
        printf '# Generated by 035_configure_uwsm_gpu_asahi.sh\n'
        printf '# -----------------------------------------------------------------\n'
        printf 'export ELECTRON_OZONE_PLATFORM_HINT=auto\n'
        printf 'export MOZ_ENABLE_WAYLAND=1\n'
        printf '\n'
        printf '# Apple DCP display controller (KMS) — required by Hyprland / Aquamarine\n'
        printf '# card1 (AGX GPU) is render-only; AQ_DRM_DEVICES must point to the KMS device.\n'
        printf 'export AQ_DRM_DEVICES="%s"\n' "$gpu_node"
        printf '\n'
        printf '# AGX cursor plane not yet fully supported; disable hardware cursors.\n'
        printf '# Remove this line once your Hyprland cursor renders correctly.\n'
        printf 'export WLR_NO_HARDWARE_CURSORS=1\n'
        printf '\n'
        printf '# VA-API: mesa (from asahi-alarm repo) handles autodetection — do not force LIBVA_DRIVER_NAME.\n'
    } >"$TEMP_OUTPUT"

    chmod 0644 -- "$TEMP_OUTPUT"

    if [[ -f "$OUTPUT_FILE" ]] && cmp -s -- "$TEMP_OUTPUT" "$OUTPUT_FILE"; then
        rm -f -- "$TEMP_OUTPUT"
        TEMP_OUTPUT=''
        log_ok "Config already up to date: $OUTPUT_FILE"
    else
        mv -f -- "$TEMP_OUTPUT" "$OUTPUT_FILE"
        TEMP_OUTPUT=''
        log_ok "Config written to: $OUTPUT_FILE"
    fi

    log_info "Active config:"
    printf '%s\n' '-------------------------------------' >&2
    cat "$OUTPUT_FILE" >&2
    printf '%s\n' '-------------------------------------' >&2
    log_ok "Done. Restart your UWSM session to apply."
}

main "$@"
