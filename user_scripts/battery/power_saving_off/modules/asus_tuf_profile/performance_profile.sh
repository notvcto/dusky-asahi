#!/usr/bin/env bash
# Hardware Profile Control
# -----------------------------------------------------------------------------
set -euo pipefail

# 1. Check for ASUS Controller (asusctl)
# If not found, exit silently (success). This makes the script safe for non-ASUS PCs.
if ! command -v asusctl &>/dev/null; then
    exit 0
fi

# 2. Apply Profile (Silently)
# Switch to 'Balanced' or 'Performance'
asusctl profile -P Balanced &>/dev/null || true

# 3. Restore Keyboard Lights (Silently)
asusctl -k low &>/dev/null || true

exit 0
