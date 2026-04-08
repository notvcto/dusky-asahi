#!/usr/bin/env bash
# Hardware Profile Control (ASUS)
# -----------------------------------------------------------------------------

# Exit early if asusctl not installed
command -v asusctl &>/dev/null || exit 0

# Apply all settings silently
{
    asusctl profile -P Quiet
    asusctl profile -b Quiet  
    asusctl profile -a Quiet
    asusctl -k off
} &>/dev/null

exit 0
