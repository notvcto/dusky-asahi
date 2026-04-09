#!/usr/bin/env bash
# AUR package installation for Asahi Linux / Arch Linux ARM
# -----------------------------------------------------------------------------
# ARM64-adapted version of 100_paru_packages.sh.
#
# Changes from the x86 version:
#   - Removed: limine-mkinitcpio-hook, limine-snapper-sync
#              (Limine is x86/EFI only; Asahi uses its own boot chain)
#   - Removed: wifitui-bin
#              (prebuilt x86_64 binary — replace with wifitui if/when an
#               ARM64 build is published to the AUR)
# -----------------------------------------------------------------------------
set -uo pipefail

declare -gi CAN_PROMPT=0
declare -gi TTY_FD=-1

if [[ -t 2 ]]; then
  declare -gr C_RESET=$'\e[0m'
  declare -gr C_BOLD=$'\e[1m'
  declare -gr C_GREEN=$'\e[1;32m'
  declare -gr C_BLUE=$'\e[1;34m'
  declare -gr C_YELLOW=$'\e[1;33m'
  declare -gr C_RED=$'\e[1;31m'
  declare -gr C_CYAN=$'\e[1;36m'
else
  declare -gr C_RESET='' C_BOLD='' C_GREEN='' C_BLUE='' C_YELLOW='' C_RED='' C_CYAN=''
fi

log_info()    { printf '%s[INFO]%s %s\n'    "${C_BLUE}"   "${C_RESET}" "$*" >&2; }
log_success() { printf '%s[SUCCESS]%s %s\n' "${C_GREEN}"  "${C_RESET}" "$*" >&2; }
log_warn()    { printf '%s[WARN]%s %s\n'    "${C_YELLOW}" "${C_RESET}" "$*" >&2; }
log_err()     { printf '%s[ERROR]%s %s\n'   "${C_RED}"    "${C_RESET}" "$*" >&2; }
log_task()    { printf '\n%s%s:: %s%s\n'    "${C_BOLD}"   "${C_CYAN}"  "$*" "${C_RESET}" >&2; }

disable_prompt_capability() {
  if (( TTY_FD >= 0 )); then
    exec {TTY_FD}>&- 2>/dev/null || :
    TTY_FD=-1
  fi
  CAN_PROMPT=0
}

cleanup() {
  disable_prompt_capability
  [[ -n "${C_RESET}" ]] && printf '%s' "${C_RESET}" >&2
}

abort_with_signal() {
  local signal_name=$1
  local exit_code=$2
  trap - EXIT INT TERM
  cleanup
  printf '\n' >&2
  log_err "Interrupted by ${signal_name}. Aborting."
  exit "${exit_code}"
}

trap cleanup EXIT
trap 'abort_with_signal SIGINT 130' INT
trap 'abort_with_signal SIGTERM 143' TERM

declare -ar PACKAGES=(
  # wlogout: PKGBUILD arch=('x86_64') — no aarch64 build available
  # adwaita-qt5 / adwaita-qt6: PKGBUILD arch=('x86_64') — Qt Adwaita theme not yet ARM64-ported
  # adwsteamgtk: appstream validation fails on aarch64 — skip until upstream fixes
  # peaclock: PKGBUILD arch=('x86_64') — no aarch64 build available
  # tray-tui: PKGBUILD arch=('x86_64') — prebuilt x86_64 binary only
  # wifitui-bin: PKGBUILD arch=('x86_64') — prebuilt x86_64 binary only
  "otf-atkinson-hyperlegible-next"
  "python-pywalfox"
  "python-pyquery"
  "hyprshade"
  "hyprshutdown"
  "waypaper"
  # shellcheck-bin: official ARM64 binary released by shellcheck upstream ✓
  "shellcheck-bin"
  "xdg-terminal-exec"
  # spotube: native ARM64 Spotify client (replaces spotify + spicetify on aarch64)
  "spotube"
)

declare -ir TIMEOUT_SEC=5
declare -ir MAX_ATTEMPTS=6

require_command() {
  local cmd=$1
  if ! command -v "${cmd}" &>/dev/null; then
    log_err "Required command not found: ${cmd}"
    exit 1
  fi
}

detect_aur_helper() {
  local helper=''
  if command -v paru &>/dev/null; then
    helper='paru'
  elif command -v yay &>/dev/null; then
    helper='yay'
  else
    log_err "AUR helper (paru/yay) not found. Please install one first."
    exit 1
  fi
  declare -gr AUR_HELPER="${helper}"
}

detect_prompt_capability() {
  local fd=-1
  disable_prompt_capability
  if exec {fd}<>/dev/tty 2>/dev/null; then
    CAN_PROMPT=1
    TTY_FD=${fd}
  fi
}

validate_config() {
  (( TIMEOUT_SEC > 0 )) || { log_err "TIMEOUT_SEC must be > 0."; exit 1; }
  (( MAX_ATTEMPTS > 0 )) || { log_err "MAX_ATTEMPTS must be > 0."; exit 1; }
}

preflight_checks() {
  if (( EUID == 0 )); then
    log_err "This script must not be run as root."
    exit 1
  fi
  require_command pacman
  detect_aur_helper
  detect_prompt_capability
  validate_config
}

aur_full_update()    { "${AUR_HELPER}" -Syu --noconfirm; }
aur_install_auto()   { "${AUR_HELPER}" -S --needed --noconfirm -- "$@"; }
aur_install_manual() { "${AUR_HELPER}" -S --needed -- "$@"; }

is_installed() {
  pacman -T "${1}" &>/dev/null
}

collect_uninstalled_packages() {
  local -n input_ref=$1
  local -n output_ref=$2
  output_ref=()
  (( ${#input_ref[@]} == 0 )) && return 0
  mapfile -t output_ref < <(pacman -T "${input_ref[@]}" 2>/dev/null || true)
}

run_full_update_with_retry() {
  local -i attempt
  for (( attempt = 1; attempt <= MAX_ATTEMPTS; attempt++ )); do
    if aur_full_update; then
      return 0
    fi
    if (( attempt < MAX_ATTEMPTS )); then
      log_warn "System update failed (attempt ${attempt}/${MAX_ATTEMPTS}). Retrying in ${TIMEOUT_SEC}s..."
      sleep "${TIMEOUT_SEC}"
    fi
  done
  log_err "System update failed after ${MAX_ATTEMPTS} attempts."
  return 1
}

prompt_package_action() {
  local pkg=$1
  local -n action_ref=$2
  local user_input=''
  local -i deadline=$((SECONDS + TIMEOUT_SEC))
  local -i remaining=0

  action_ref='retry'

  while true; do
    remaining=$((deadline - SECONDS))
    (( remaining > 0 )) || return 0

    if ! printf '%s  -> %s failed. Manual install [M] or Skip [S]? (Auto-retry in %ss)... %s' \
      "${C_YELLOW}" "${pkg}" "${remaining}" "${C_RESET}" >&"${TTY_FD}"; then
      disable_prompt_capability
      return 0
    fi

    # shellcheck disable=SC2261
    if IFS= read -r -n 1 -s -t "${remaining}" user_input <&"${TTY_FD}"; then
      # shellcheck disable=SC2261
      printf '\n' >&"${TTY_FD}" 2>/dev/null || :
      # shellcheck disable=SC2261
      case "${user_input,,}" in
        m) action_ref='manual'; return 0 ;;
        s) action_ref='skip';   return 0 ;;
        *) printf '%s[INFO]%s Invalid input. Press M or S.\n' "${C_BLUE}" "${C_RESET}" >&"${TTY_FD}" 2>/dev/null || : ;;
      esac
    else
      # shellcheck disable=SC2261
      printf '\n' >&"${TTY_FD}" 2>/dev/null || :
      return 0
    fi
  done
}

print_summary() {
  local -i total_requested=$1
  local -i fail_count=$2
  local -n failed_ref=$3
  local -i success_count=$((total_requested - fail_count))
  local pkg

  printf '\n' >&2
  printf '%s========================================%s\n' "${C_BOLD}" "${C_RESET}" >&2
  log_success "Successful: ${success_count}"

  if (( fail_count > 0 )); then
    log_err "Failed: ${fail_count}"
    for pkg in "${failed_ref[@]}"; do
      printf '   - %s\n' "${pkg}" >&2
    done
    return 1
  fi

  log_success "All packages processed successfully."
  return 0
}

main() {
  preflight_checks

  log_task "Starting AUR Package Installation (Asahi / ARM64)"
  log_info "Using AUR Helper: ${AUR_HELPER}"

  if ! run_full_update_with_retry; then
    return 1
  fi

  local -a to_install=()
  collect_uninstalled_packages PACKAGES to_install

  if (( ${#to_install[@]} == 0 )); then
    log_success "All packages are already installed."
    return 0
  fi

  local -i total_requested=${#to_install[@]}
  log_info "Packages to install: ${total_requested}"

  log_task "Attempting Batch Installation..."

  if aur_install_auto "${to_install[@]}"; then
    local -a no_failures=()
    log_success "Batch installation successful."
    print_summary "${total_requested}" 0 no_failures
    return 0
  fi

  log_warn "Batch installation failed. Switching to granular fallback mode."

  local -a remaining=()
  local -a failed_pkgs=()
  local -i fail_count=0
  local -i attempt
  local pkg action=''

  collect_uninstalled_packages to_install remaining

  if (( ${#remaining[@]} == 0 )); then
    local -a no_failures=()
    log_success "All packages installed during the batch attempt."
    print_summary "${total_requested}" 0 no_failures
    return 0
  fi

  for pkg in "${remaining[@]}"; do
    [[ -n "${pkg}" ]] || continue
    log_task "Processing: ${pkg}"

    for (( attempt = 1; attempt <= MAX_ATTEMPTS; attempt++ )); do
      if aur_install_auto "${pkg}"; then
        log_success "Installed ${pkg}."; break
      fi
      if is_installed "${pkg}"; then
        log_success "${pkg} is installed."; break
      fi

      log_warn "Automatic install failed for ${pkg} (attempt ${attempt}/${MAX_ATTEMPTS})."

      if (( attempt == MAX_ATTEMPTS )); then
        log_err "Max attempts reached for ${pkg}. Skipping."
        failed_pkgs+=("${pkg}")
        (( fail_count++ ))
        break
      fi

      if (( CAN_PROMPT == 0 )); then
        log_info "Non-interactive. Retrying in ${TIMEOUT_SEC}s..."
        sleep "${TIMEOUT_SEC}"
        continue
      fi

      prompt_package_action "${pkg}" action

      case "${action}" in
        manual)
          if aur_install_manual "${pkg}" || is_installed "${pkg}"; then
            log_success "Manual install successful for ${pkg}."; break
          fi
          log_err "Manual install failed for ${pkg}."
          ;;
        skip)
          log_warn "Skipping ${pkg}."
          failed_pkgs+=("${pkg}")
          (( fail_count++ ))
          break
          ;;
        retry) log_info "Timeout. Auto-retrying..." ;;
      esac
    done
  done

  print_summary "${total_requested}" "${fail_count}" failed_pkgs
}

main "$@"
