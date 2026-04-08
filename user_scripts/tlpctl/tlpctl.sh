#!/usr/bin/env bash
# ---------------------------------------------------------------------------
#  tlp-cycle — TLP power profile cycler and manager for Arch Linux (Wayland)
#
#  Default action (no arguments): cycle to the next power profile.
#  Explicit subcommands available for direct profile selection, status
#  queries, and Waybar-compatible JSON output.
#
#  Dependencies: tlpctl (tlp-pd), notify-send (libnotify) [optional]
#  Minimum:      Bash 5.1+
# ---------------------------------------------------------------------------

# -- Strict mode -------------------------------------------------------------
set -euo pipefail

# -- Bash version gate -------------------------------------------------------
if (( BASH_VERSINFO[0] < 5 || (BASH_VERSINFO[0] == 5 && BASH_VERSINFO[1] < 1) )); then
    printf 'Fatal: Bash 5.1+ required (found %s)\n' "$BASH_VERSION" >&2
    exit 1
fi

# -- Constants ----------------------------------------------------------------
readonly VERSION='1.2.0'
readonly SCRIPT_NAME="${0##*/}"
readonly -a PROFILES=('power-saver' 'balanced' 'performance')
readonly LOCK_DIR="${XDG_RUNTIME_DIR:-/tmp}/tlp-cycle.lock"

# Track whether this instance owns the lock
_lock_held=0

# Map: profile → Nerd Font icon
# Using explicit Unicode escapes to survive copy-paste and encoding changes.
# Codepoints are from Nerd Fonts v3.x Material Design Icons (nf-md-*).
declare -rA ICON_NERDFONT=(
    [performance]=$'\U000f04c5'    # 󰓅 nf-md-speedometer
    [balanced]=$'\U000f007e'       # 󰖳 nf-md-scale_balance
    [power-saver]=$'\U000f0327'    # 󰌧 nf-md-leaf
    [unknown]='?'
)

# Map: profile → freedesktop icon name for notify-send
declare -rA ICON_NOTIFY=(
    [performance]='battery-full-charged-symbolic'
    [balanced]='battery-good-symbolic'
    [power-saver]='battery-caution-symbolic'
    [unknown]='dialog-warning'
)

# Map: profile → short display label
declare -rA LABEL=(
    [performance]='Perf'
    [balanced]='Bal'
    [power-saver]='Save'
)

# Map: profile → Waybar CSS class
declare -rA CSS_CLASS=(
    [performance]='performance'
    [balanced]='balanced'
    [power-saver]='power-saver'
)

# -- ANSI helpers -------------------------------------------------------------
# stderr colors (used by log_* functions which write to fd 2)
if [[ -t 2 ]]; then
    readonly _R=$'\033[0m' _B=$'\033[1m'
    readonly _RED=$'\033[31m' _GRN=$'\033[32m' _BLU=$'\033[34m' _YLW=$'\033[33m'
else
    readonly _R='' _B='' _RED='' _GRN='' _BLU='' _YLW=''
fi

# stdout colors (used by show_help which writes to fd 1)
if [[ -t 1 ]]; then
    readonly _sR=$'\033[0m' _sB=$'\033[1m'
else
    readonly _sR='' _sB=''
fi

# -- Logging (always to stderr) ----------------------------------------------
log_info()    { printf '%s[INFO]%s  %s\n' "$_BLU" "$_R" "$*" >&2; }
log_ok()      { printf '%s[ OK ]%s  %s\n' "$_GRN" "$_R" "$*" >&2; }
log_warn()    { printf '%s[WARN]%s  %s\n' "$_YLW" "$_R" "$*" >&2; }
log_error()   { printf '%s[ERR ]%s  %s\n' "$_RED" "$_R" "$*" >&2; }

# -- Mutex (directory-based, atomic on all Linux filesystems) -----------------
acquire_lock() {
    if ! mkdir -- "$LOCK_DIR" 2>/dev/null; then
        local lock_pid
        lock_pid=$(<"${LOCK_DIR}/pid" 2>/dev/null) || lock_pid=''
        if [[ -n "$lock_pid" ]] && kill -0 "$lock_pid" 2>/dev/null; then
            log_error "Another instance is running (PID ${lock_pid})."
            exit 1
        fi
        rm -rf -- "$LOCK_DIR"
        mkdir -- "$LOCK_DIR" || { log_error 'Failed to acquire lock.'; exit 1; }
    fi
    printf '%s' "$$" > "${LOCK_DIR}/pid"
    _lock_held=1
}

release_lock() {
    if (( _lock_held )); then
        rm -rf -- "$LOCK_DIR"
        _lock_held=0
    fi
}

# -- Cleanup trap -------------------------------------------------------------
cleanup() { release_lock; }
trap cleanup EXIT

# -- Dependency check ---------------------------------------------------------
assert_deps() {
    if ! command -v tlpctl >/dev/null 2>&1; then
        log_error "'tlpctl' not found in PATH. Install tlp-pd or ensure it is accessible."
        exit 127
    fi
}

# -- Profile validation ------------------------------------------------------
is_valid_profile() {
    local p="$1"
    local known
    for known in "${PROFILES[@]}"; do
        [[ "$p" == "$known" ]] && return 0
    done
    return 1
}

# -- Core: get current profile ------------------------------------------------
get_current_profile() {
    local raw
    if ! raw=$(tlpctl get 2>&1); then
        log_error "tlpctl get failed: ${raw}"
        exit 1
    fi
    # Trim leading/trailing whitespace only (preserve internal characters)
    raw="${raw#"${raw%%[![:space:]]*}"}"
    raw="${raw%"${raw##*[![:space:]]}"}"
    printf '%s' "$raw"
}

# -- Core: set profile -------------------------------------------------------
do_set_profile() {
    local target="$1"
    local current output

    if ! is_valid_profile "$target"; then
        log_error "Unknown profile '${target}'. Valid: ${PROFILES[*]}"
        exit 1
    fi

    current=$(get_current_profile)

    if [[ "$current" == "$target" ]]; then
        log_info "Already on '${target}' — no change."
        return 0
    fi

    log_info "Switching: ${current} → ${target} …"

    if output=$(tlpctl "$target" 2>&1); then
        log_ok "Active profile: ${_B}${target}${_R}"
        send_notification "$target"
    else
        log_error "tlpctl failed: ${output}"
        send_notification_error "$target"
        exit 1
    fi
}

# -- Core: cycle --------------------------------------------------------------
do_cycle() {
    local current next=''
    current=$(get_current_profile)

    if ! is_valid_profile "$current"; then
        log_warn "Current profile '${current}' unrecognised; defaulting to balanced."
        do_set_profile 'balanced'
        return
    fi

    local i count=${#PROFILES[@]}
    for (( i = 0; i < count; i++ )); do
        if [[ "${PROFILES[i]}" == "$current" ]]; then
            next="${PROFILES[$(( (i + 1) % count ))]}"
            break
        fi
    done

    [[ -n "$next" ]] || { log_error 'Internal error: cycle target not resolved.'; exit 1; }
    do_set_profile "$next"
}

# -- Core: reverse cycle -----------------------------------------------------
do_cycle_reverse() {
    local current prev=''
    current=$(get_current_profile)

    if ! is_valid_profile "$current"; then
        log_warn "Current profile '${current}' unrecognised; defaulting to balanced."
        do_set_profile 'balanced'
        return
    fi

    local i count=${#PROFILES[@]}
    for (( i = 0; i < count; i++ )); do
        if [[ "${PROFILES[i]}" == "$current" ]]; then
            prev="${PROFILES[$(( (i - 1 + count) % count ))]}"
            break
        fi
    done

    [[ -n "$prev" ]] || { log_error 'Internal error: reverse-cycle target not resolved.'; exit 1; }
    do_set_profile "$prev"
}

# -- Notification helpers -----------------------------------------------------
send_notification() {
    local profile="$1"
    command -v notify-send >/dev/null 2>&1 || return 0

    local pretty="${profile//-/ }"
    pretty=$(printf '%s' "$pretty" | sed 's/\b\(.\)/\u\1/g')

    local icon="${ICON_NOTIFY[$profile]:-${ICON_NOTIFY[unknown]}}"

    notify-send \
        --app-name='Power Manager' \
        --urgency='normal' \
        --icon="$icon" \
        --hint=string:x-canonical-private-synchronous:power-profile \
        'Power Profile' \
        "Active: ${pretty}" &
    disown
}

send_notification_error() {
    local profile="$1"
    command -v notify-send >/dev/null 2>&1 || return 0

    notify-send \
        --app-name='Power Manager' \
        --urgency='critical' \
        --icon='dialog-error' \
        'Power Profile Error' \
        "Failed to switch to ${profile}" &
    disown
}

# -- Status / Waybar output ---------------------------------------------------
do_status() {
    local fmt="${1:-text}"
    fmt="${fmt#--}"

    local current
    current=$(get_current_profile)

    local nf_icon="${ICON_NERDFONT[$current]:-${ICON_NERDFONT[unknown]}}"
    local label="${LABEL[$current]:-$current}"
    local css="${CSS_CLASS[$current]:-unknown}"

    case "$fmt" in
        json|waybar)
            printf '{"text":"%s %s","alt":"%s","class":"%s","tooltip":"Power profile: %s"}\n' \
                "$nf_icon" "$label" "$current" "$css" "$current"
            ;;
        text|*)
            printf '%s %s\n' "$nf_icon" "$label"
            ;;
    esac
}

# -- Usage / Help -------------------------------------------------------------
show_help() {
    cat <<EOF
${_sB}${SCRIPT_NAME}${_sR} v${VERSION} — TLP power profile cycler for Arch Linux / Wayland

${_sB}USAGE${_sR}
    ${SCRIPT_NAME}                        Cycle to the next profile (default action)
    ${SCRIPT_NAME} cycle                  Cycle forward:  power-saver → balanced → performance → …
    ${SCRIPT_NAME} cycle --reverse        Cycle backward: performance → balanced → power-saver → …
    ${SCRIPT_NAME} set <profile>          Set a specific profile directly
    ${SCRIPT_NAME} get                    Print the current profile name to stdout
    ${SCRIPT_NAME} status [--json]        Print current status (plain text or Waybar JSON)
    ${SCRIPT_NAME} list                   Proxy to 'tlpctl list'
    ${SCRIPT_NAME} --help | -h            Show this help
    ${SCRIPT_NAME} --version | -v         Show version

${_sB}PROFILES${_sR}
    performance     Maximum CPU/GPU throughput, fans unrestricted
    balanced        Platform-default balance of power and efficiency
    power-saver     Aggressive power saving, reduced clocks

${_sB}WAYBAR INTEGRATION${_sR}
    "custom/power": {
        "exec": "${SCRIPT_NAME} status --json",
        "return-type": "json",
        "interval": 5,
        "on-click": "${SCRIPT_NAME} cycle",
        "on-click-right": "${SCRIPT_NAME} cycle --reverse"
    }

${_sB}ENVIRONMENT${_sR}
    XDG_RUNTIME_DIR     Used for the lockfile (defaults to /tmp)

${_sB}EXIT CODES${_sR}
    0       Success
    1       Runtime error (tlpctl failure, invalid input)
    127     Missing dependency (tlpctl not found)
EOF
}

# -- Argument parsing ---------------------------------------------------------
main() {
    assert_deps

    if (( $# == 0 )); then
        acquire_lock
        do_cycle
        return
    fi

    case "$1" in
        cycle|-c|--cycle)
            acquire_lock
            if [[ "${2:-}" == '--reverse' || "${2:-}" == '-r' ]]; then
                do_cycle_reverse
            else
                do_cycle
            fi
            ;;

        set|-s|--set)
            if [[ -z "${2:-}" ]]; then
                log_error "'set' requires a profile name: ${PROFILES[*]}"
                exit 1
            fi
            acquire_lock
            do_set_profile "$2"
            ;;

        performance|balanced|power-saver)
            acquire_lock
            do_set_profile "$1"
            ;;

        get|-g|--get)
            get_current_profile
            printf '\n'
            ;;

        status|bar|--status)
            do_status "${2:-text}"
            ;;

        list|--list)
            tlpctl list
            ;;

        -h|--help|help)
            show_help
            ;;

        -v|--version|version)
            printf '%s %s\n' "$SCRIPT_NAME" "$VERSION"
            ;;

        --)
            shift
            acquire_lock
            do_cycle
            ;;

        -*)
            log_error "Unknown option '${1}'. See '${SCRIPT_NAME} --help'."
            exit 1
            ;;

        *)
            log_error "Unknown command '${1}'. See '${SCRIPT_NAME} --help'."
            exit 1
            ;;
    esac
}

main "$@"
