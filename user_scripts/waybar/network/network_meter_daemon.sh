#!/usr/bin/env bash
set -euo pipefail
export LC_ALL=C

# 1. Load 'sleep' as builtin if available (critical for loop performance)
if [[ -f /usr/lib/bash/sleep ]]; then
    enable -f /usr/lib/bash/sleep sleep 2>/dev/null || true
fi

# 2. Environment Setup
RUNTIME="${XDG_RUNTIME_DIR:-/run/user/${UID:-$(id -u)}}"
STATE_DIR="$RUNTIME/waybar-net"
STATE_FILE="$STATE_DIR/state"
HEARTBEAT_FILE="$STATE_DIR/heartbeat"
PID_FILE="$STATE_DIR/daemon.pid"

mkdir -p "$STATE_DIR"
printf '%s\n' "$$" > "$PID_FILE"

# Cleanup on exit
trap 'rm -rf "$STATE_DIR"' EXIT
trap ':' USR1

# 3. HELPER: Get time in microseconds (Pure Bash)
# handles Bash 5.0+ EPOCHREALTIME or falls back to printf builtin
if [[ -n "${EPOCHREALTIME+x}" ]]; then
    get_time_us() {
        local -n _out=$1
        local s us
        IFS=. read -r s us <<< "$EPOCHREALTIME"
        # Pad microseconds to ensure 6 digits, then strip to 6
        us="${us}000000"
        _out=$(( s * 1000000 + 10#${us:0:6} ))
    }
else
    get_time_us() {
        local -n _out=$1
        # Fallback: printf %(%s)T is a builtin in bash 4.2+
        _out=$(( $(printf '%(%s)T' -1) * 1000000 ))
    }
fi

# 4. HELPER: Interface Detection (ZERO FORK)
# Strategy: Read /proc/net/route directly.
# If the default route interface lacks stats (VPN bug), scan for physical fallback.
find_active_iface() {
    local -n _iface_out=$1
    local iface dest gateway flags refcnt use metric mask mtu window irtt
    
    # Attempt 1: Check Default Route (Destination 00000000)
    while read -r iface dest gateway flags refcnt use metric mask mtu window irtt; do
        if [[ "$dest" == "00000000" ]]; then
            # Verify this interface actually exposes statistics
            if [[ -r "/sys/class/net/$iface/statistics/rx_bytes" ]]; then
                _iface_out="$iface"
                return 0
            fi
        fi
    done < /proc/net/route

    # Attempt 2: Fallback - Find first UP physical interface with stats
    # (Fixes issues where VPN tunnels mask the real interface but offer no stats)
    for state_file in /sys/class/net/*/operstate; do
        [[ -r "$state_file" ]] || continue
        
        local if_name="${state_file%/operstate}"
        if_name="${if_name##*/}"
        
        # Skip loopback
        [[ "$if_name" == "lo" ]] && continue
        
        # Check if interface is UP
        local state
        read -r state < "$state_file" 2>/dev/null || state="unknown"
        [[ "$state" == "up" ]] || continue

        # Check if it has stats
        if [[ -r "/sys/class/net/$if_name/statistics/rx_bytes" ]]; then
            _iface_out="$if_name"
            return 0
        fi
    done

    _iface_out=""
    return 1
}

# 5. HELPER: Format Speed (Pure Bash Math)
format_speed() {
    local -n _unit=$1 _tx=$2 _rx=$3 _class=$4
    local rx_d=$5 tx_d=$6
    # Determine max to choose unit
    local max=$(( rx_d > tx_d ? rx_d : tx_d ))

    # 1 MB = 1048576 bytes
    if (( max >= 1048576 )); then
        # Calculate with 1 decimal place using integer math
        local tx_x10=$(( tx_d * 10 / 1048576 ))
        local rx_x10=$(( rx_d * 10 / 1048576 ))

        (( tx_x10 < 100 )) && _tx="$((tx_x10 / 10)).$((tx_x10 % 10))" || _tx="$((tx_x10 / 10))"
        (( rx_x10 < 100 )) && _rx="$((rx_x10 / 10)).$((rx_x10 % 10))" || _rx="$((rx_x10 / 10))"

        _unit="MB"
        _class="network-mb"
    else
        # KB
        _tx=$(( tx_d / 1024 ))
        _rx=$(( rx_d / 1024 ))
        _unit="KB"
        _class="network-kb"
    fi
}

# 6. HELPER: Heartbeat Check (Optimization)
# Use 'stat' sparingly (every 3rd cycle) to avoid excessive IO
check_heartbeat() {
    local -n _hb_time=$1
    local now=$2
    
    if [[ -f "$HEARTBEAT_FILE" ]]; then
        # stat is an external binary, but we only run it every ~3 seconds
        _hb_time=$(stat -c %Y "$HEARTBEAT_FILE" 2>/dev/null) || _hb_time=$now
    else
        _hb_time=$now
    fi
}

# --- MAIN LOOP ---

rx_prev=0
tx_prev=0
iface=""
current_iface=""
iface_counter=0
hb_counter=2
hb_time=0

# Pre-calculate constants
WRAP_LIMIT=4294967296 # 2^32

while :; do
    printf -v now '%(%s)T' -1

    # A. Watchdog (Heartbeat) - Runs every 3 ticks
    if (( ++hb_counter >= 3 )); then
        hb_counter=0
        check_heartbeat hb_time "$now"
    fi

    # B. Deep Sleep if Waybar is inactive (>10s silence)
    if (( now - hb_time > 10 )); then
        sleep 600 &
        wait $! || true
        hb_counter=10 # Force immediate check on wake
        continue
    fi

    # C. Interface Check - Runs every 5 ticks OR if we lost the interface
    # Re-validates stats existence to catch VPN toggles on the fly
    if (( ++iface_counter >= 5 )) || [[ -z "$iface" ]] || [[ ! -r "/sys/class/net/$iface/statistics/rx_bytes" ]]; then
        iface_counter=0
        find_active_iface current_iface || current_iface=""
    else
        current_iface="$iface"
    fi

    # D. Disconnected State
    if [[ -z "$current_iface" ]]; then
        # Atomic write
        printf '%s\n' "- - - network-disconnected" > "$STATE_FILE.tmp"
        mv -f "$STATE_FILE.tmp" "$STATE_FILE"
        rx_prev=0; tx_prev=0; iface=""
        sleep 3 || true
        continue
    fi

    # E. Connected State - Measure
    get_time_us start_time

    # Reset counters if interface changed
    if [[ "$current_iface" != "$iface" ]]; then
        iface="$current_iface"
        rx_prev=0; tx_prev=0
    fi

    # Read Stats (No Forks)
    # Using 'read' directly from /sys is incredibly fast
    read -r rx_now < "/sys/class/net/$iface/statistics/rx_bytes" 2>/dev/null || rx_now=0
    read -r tx_now < "/sys/class/net/$iface/statistics/tx_bytes" 2>/dev/null || tx_now=0

    # First sample initialization
    if (( rx_prev == 0 && tx_prev == 0 )); then
        rx_prev=$rx_now
        tx_prev=$tx_now
        sleep 1 || true
        continue
    fi

    # F. Calculate Deltas with Overflow Protection
    rx_delta=$(( rx_now - rx_prev ))
    tx_delta=$(( tx_now - tx_prev ))

    # Handle 32-bit integer wrap-around
    if (( rx_delta < 0 )); then rx_delta=$(( rx_delta + WRAP_LIMIT )); fi
    if (( tx_delta < 0 )); then tx_delta=$(( tx_delta + WRAP_LIMIT )); fi
    
    # Sanity check: if still negative (huge jump/reset), clamp to 0
    (( rx_delta < 0 )) && rx_delta=0
    (( tx_delta < 0 )) && tx_delta=0

    rx_prev=$rx_now
    tx_prev=$tx_now

    # G. Format and Write
    format_speed unit tx_fmt rx_fmt class "$rx_delta" "$tx_delta"
    printf '%s %s %s %s\n' "$unit" "$tx_fmt" "$rx_fmt" "$class" > "$STATE_FILE.tmp"
    mv -f "$STATE_FILE.tmp" "$STATE_FILE"

    # H. Precision Sleep
    get_time_us end_time
    sleep_us=$(( 1000000 - (end_time - start_time) ))

    if (( sleep_us <= 0 )); then
        : # Lagging behind, run immediately
    elif (( sleep_us >= 1000000 )); then
        sleep 1 || true
    else
        printf -v sleep_sec "0.%06d" "$sleep_us"
        sleep "$sleep_sec" || true
    fi
done
