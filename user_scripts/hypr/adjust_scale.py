#!/usr/bin/env python3
import sys
import os
import subprocess
import json
import tempfile
import re
import time
from pathlib import Path

# --- Immutable Configuration ---
CONFIG_DIR = Path.home() / ".config/hypr/edit_here/source"
CONFIG_FILE = CONFIG_DIR / "monitors.conf"
NOTIFY_TAG = "hypr_scale_adjust"
MIN_LOGICAL_WIDTH = 640
MIN_LOGICAL_HEIGHT = 360

# Standard Wayland fractional/integer scaling steps
SCALE_STEPS = [
    0.5, 0.6, 0.75, 0.8, 0.9, 1.0, 1.0625, 1.1, 1.125, 1.15, 1.2, 1.25,
    1.33, 1.4, 1.5, 1.6, 1.67, 1.75, 1.8, 1.88, 2.0, 2.25, 2.4, 2.5,
    2.67, 2.8, 3.0
]

# --- Runtime State & Logging ---
DEBUG = os.environ.get("DEBUG") == "1"

def log_err(msg: str) -> None: sys.stderr.write(f"\033[0;31m[ERROR]\033[0m {msg}\n")
def log_warn(msg: str) -> None: sys.stderr.write(f"\033[0;33m[WARN]\033[0m {msg}\n")
def log_info(msg: str) -> None: sys.stderr.write(f"\033[0;32m[INFO]\033[0m {msg}\n")
def log_debug(msg: str) -> None:
    if DEBUG: sys.stderr.write(f"\033[0;34m[DEBUG]\033[0m {msg}\n")

def notify(title: str, body: str, urgency: str = "low") -> None:
    """Dispatches a notification safely, ignoring if the daemon is missing."""
    try:
        subprocess.run([
            "notify-send", 
            "-h", f"string:x-canonical-private-synchronous:{NOTIFY_TAG}",
            "-u", urgency, 
            "-t", "2000", 
            title, 
            body
        ], stderr=subprocess.DEVNULL)
    except FileNotFoundError:
        pass

def get_active_monitor(target_override: str | None = None) -> tuple[str, int, int, float]:
    """Retrieves monitor state, respecting environment overrides or window focus."""
    try:
        res = subprocess.run(["hyprctl", "-j", "monitors"], capture_output=True, text=True, check=True)
        monitors = json.loads(res.stdout)
    except subprocess.CalledProcessError:
        log_err("Cannot communicate with Hyprland IPC.")
        sys.exit(1)
    except FileNotFoundError:
        log_err("'hyprctl' binary not found in PATH.")
        sys.exit(1)
    except json.JSONDecodeError:
        log_err("Invalid JSON returned by Hyprland.")
        sys.exit(1)

    if not monitors:
        log_err("No active monitors found.")
        sys.exit(1)

    if target_override:
        target = next((m for m in monitors if m["name"] == target_override), None)
        if not target:
            log_err(f"Target monitor '{target_override}' not found.")
            sys.exit(1)
    else:
        target = next((m for m in monitors if m.get("focused")), monitors[0])
        
    return target["name"], target["width"], target["height"], target["scale"]

def compute_next_scale(current: float, direction: str, phys_w: int, phys_h: int) -> float | None:
    """Calculates the nearest mathematically valid scale strictly enforcing direction."""
    valid_scales: list[float] = []

    for s in SCALE_STEPS:
        lw, lh = phys_w / s, phys_h / s
        if lw < MIN_LOGICAL_WIDTH or lh < MIN_LOGICAL_HEIGHT:
            continue
        if abs(lw - round(lw)) > 0.01 or abs(lh - round(lh)) > 0.01:
            continue
        valid_scales.append(s)

    if not valid_scales:
        valid_scales = [1.0]

    if direction == "+":
        candidates = [s for s in valid_scales if s > current + 0.000001]
        if not candidates: return None
        return min(candidates)
    else:
        candidates = [s for s in valid_scales if s < current - 0.000001]
        if not candidates: return None
        return max(candidates)

def update_config_atomically(monitor_name: str, new_scale: float) -> None:
    """Updates the config via state machine and strict POSIX atomic replacement."""
    if not CONFIG_FILE.exists():
        CONFIG_DIR.mkdir(parents=True, exist_ok=True)
        CONFIG_FILE.touch()

    real_path = CONFIG_FILE.resolve()
    with open(real_path, "r") as f:
        config_text = f.read()

    found = False
    log_debug(f"Updating config: {monitor_name} -> {new_scale:g}")

    # 1. Process V2 Blocks
    def v2_replacer(match: re.Match) -> str:
        nonlocal found
        block = match.group(0)
        if re.search(rf"^\s*output\s*=\s*{re.escape(monitor_name)}\b", block, re.MULTILINE):
            if re.search(r"^\s*scale\s*=.*", block, re.MULTILINE):
                block = re.sub(r"(^\s*scale\s*=).*$", rf"\1 {new_scale:g}", block, flags=re.MULTILINE)
            else:
                block = re.sub(r"(\s*)\}$", rf"\1    scale = {new_scale:g}\n}}", block)
            found = True
        return block
        
    config_text = re.sub(r"monitorv2\s*\{[^}]*\}", v2_replacer, config_text)

    # 2. Process V1 Rules
    if not found:
        def v1_replacer(match: re.Match) -> str:
            nonlocal found
            mon_name = match.group(2).strip()
            
            if mon_name == monitor_name:
                found = True
                remainder = match.group(3)
                comment = ""
                
                # FIX: Dynamically capture the comment and all preceding whitespace to preserve formatting
                c_match = re.search(r'(\s*#.*)', remainder)
                if c_match:
                    comment = c_match.group(1)
                    remainder = remainder[:c_match.start()]
                
                parts = remainder.split(",")
                if len(parts) == 2:
                    if "disable" in parts[1].strip():
                        parts = ["", " preferred", " auto", f" {new_scale:g}"]
                    else:
                        parts.extend([" auto", f" {new_scale:g}"])
                elif len(parts) == 3:
                    parts.append(f" {new_scale:g}")
                elif len(parts) >= 4:
                    parts[3] = f" {new_scale:g}"
                
                return f"{match.group(1)}{match.group(2)}{','.join(parts)}{comment}"
            return match.group(0)

        config_text = re.sub(r"^(\s*monitor\s*=\s*)([^,\n]+)(,.*)$", v1_replacer, config_text, flags=re.MULTILINE)

    # 3. Append entirely new rule
    if not found:
        log_info(f"Appending new entry for: {monitor_name}")
        config_text += f"\nmonitor = {monitor_name}, preferred, auto, {new_scale:g}\n"

    # 4. Strict POSIX Atomic Write
    fd, temp_path = tempfile.mkstemp(dir=real_path.parent, prefix=".monitors.conf.tmp.")
    try:
        with os.fdopen(fd, 'w') as temp_file:
            temp_file.write(config_text)
            
        os.chmod(temp_path, real_path.stat().st_mode)
        os.replace(temp_path, real_path)
    except Exception as e:
        os.remove(temp_path)
        log_err(f"Atomic write failed: {e}")
        sys.exit(1)

def main():
    if len(sys.argv) != 2 or sys.argv[1] not in ("+", "-"):
        sys.stderr.write(f"Usage: {sys.argv[0]} [+|-]\n")
        sys.exit(1)

    direction = sys.argv[1]
    target_override = os.environ.get("HYPR_SCALE_MONITOR")
    
    mon_name, phys_w, phys_h, current_scale = get_active_monitor(target_override)
    new_scale = compute_next_scale(current_scale, direction, phys_w, phys_h)
    
    if new_scale is None:
        log_warn(f"Limit reached: {current_scale:g}")
        notify("Monitor Scale", f"Limit Reached: {current_scale:g}", "normal")
        return

    # Write the target scale to disk
    update_config_atomically(mon_name, new_scale)
    
    log_info(f"Applying scale {new_scale:g} via hyprctl reload")
    subprocess.run(["hyprctl", "reload"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    
    # State Verification: Deterministic polling to prevent async race conditions
    actual_scale = current_scale
    for _ in range(25):  # Poll every 100ms for up to 2.5 seconds
        time.sleep(0.1)
        _, _, _, polled_scale = get_active_monitor(mon_name)
        if abs(polled_scale - current_scale) > 0.000001:
            actual_scale = polled_scale
            break
        actual_scale = polled_scale
    
    # Verify if Wayland accepted the request or clamped it due to hardware limits
    if abs(actual_scale - new_scale) > 0.000001:
        log_warn(f"Hyprland override detected: requested {new_scale:g}, active is {actual_scale:g}")
        update_config_atomically(mon_name, actual_scale)
        notify("Scale Adjusted", f"Requested {new_scale:g}, got {actual_scale:g}")
    else:
        logic_w, logic_h = round(phys_w / new_scale), round(phys_h / new_scale)
        notify(f"Display Scale: {new_scale:g}", f"Monitor: {mon_name}\nLogical: {logic_w}x{logic_h}")

if __name__ == "__main__":
    main()
