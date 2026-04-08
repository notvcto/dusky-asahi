
When connecting an external monitor to a laptop, automatically enable clamshell mode similar to MacBooks:

- Turn off laptop screen
- External monitor becomes primary display
- Switch to performance power profile

This should work when connecting:
- Just a monitor
- Full dock setup (monitor + keyboard + mouse)

**My current setup:**

I have a rudimentary setup that works, used it for a couple of months on a different system but I think it's a very bad way to do it. Here's what I'm currently using:

> **Note:** This is a polling-based solution (checks every 2 seconds) which isn't ideal for battery life. A better approach would use udev rules or acpid event handlers, but this works reliably in practice.

---

## Prerequisites

Before starting, make sure you have these installed:

```bash
# Check if power-profiles-daemon is installed and running
systemctl status power-profiles-daemon

# If not installed, install it (Arch-based):
sudo pacman -S power-profiles-daemon
systemctl enable --now power-profiles-daemon

# Hyprland (you likely already have this)
# acpi tools (for lid state detection)
sudo pacman -S acpi
```

**Find your monitor names:**
```bash
# Run this with your laptop open and external monitor connected
hyprctl monitors

# Look for names like:
# - eDP-1 (internal laptop screen)
# - DP-1, DP-2, HDMI-A-1, etc. (external monitors)
```

**Note down:**
- Your internal monitor name: `_____________`
- Your external monitor name: `_____________`

---

**1. Power Profile Script** (`/usr/local/bin/power-profile-auto.sh`):
```bash
#!/usr/bin/env bash
AC_PATH="/sys/class/power_supply/AC0/online"

set_profile() {
    case "$1" in
        "1") powerprofilesctl set performance ;;
        "0") powerprofilesctl set power-saver ;;
    esac
}

if [[ -f "$AC_PATH" ]]; then
    AC_STATE=$(cat "$AC_PATH")
    set_profile "$AC_STATE"
fi
```

**Commands:**
```bash
sudo nvim /usr/local/bin/power-profile-auto.sh
sudo chmod +x /usr/local/bin/power-profile-auto.sh
```

**Service file** (`/etc/systemd/system/power-profile-auto.service`):
```ini
[Unit]
Description=Set power profile based on AC state at boot
After=multi-user.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/power-profile-auto.sh

[Install]
WantedBy=multi-user.target
```

**Commands:**
```bash
sudo nvim /etc/systemd/system/power-profile-auto.service
sudo systemctl enable power-profile-auto.service
sudo systemctl start power-profile-auto.service
```

**Verify it works:**
```bash
# Check service status
sudo systemctl status power-profile-auto.service

# Check current power profile
powerprofilesctl get

# Test manually by unplugging/plugging AC adapter
# Then check again: powerprofilesctl get
```

---

**2. Clamshell Mode Script** (`~/scripts/clamshell-mode.sh`):
```bash
#!/bin/bash
INTERNAL="eDP-1"  # ⚠️ CHANGE THIS to your internal monitor name
EXTERNAL="DP-1"   # ⚠️ CHANGE THIS to your external monitor name

lid_state=$(awk '{print $2}' /proc/acpi/button/lid/LID/state)

if [[ "$lid_state" == "closed" ]]; then
    hyprctl keyword monitor "$INTERNAL,disable"
    if hyprctl monitors | grep -q "$EXTERNAL"; then
        hyprctl keyword monitor "$EXTERNAL,preferred,auto,1"
    fi
else
    hyprctl keyword monitor "$INTERNAL,preferred,auto,1.6"
    # Note: 1.6 is the scale factor - adjust for your display
fi
```

**Commands:**
```bash
# Create scripts directory if it doesn't exist
mkdir -p ~/scripts

# Create and edit the script
nvim ~/scripts/clamshell-mode.sh
# ⚠️ Remember to update INTERNAL and EXTERNAL monitor names!

chmod +x ~/scripts/clamshell-mode.sh
```

**Test the script manually:**
```bash
# Run it and check if monitors change
~/scripts/clamshell-mode.sh

# Check monitor status
hyprctl monitors
```

---

**3. Polling Service** (`~/.config/systemd/user/clamshell.service`):
```ini
[Unit]
Description=Clamshell mode monitor

[Service]
Type=simple
ExecStart=/bin/bash -c 'while true; do %h/scripts/clamshell-mode.sh; sleep 2; done'
Restart=always

[Install]
WantedBy=default.target
```
> **Note:** `%h` automatically expands to your home directory in systemd, so you don't need to hardcode your username.

**Commands:**
```bash
# Create systemd user directory if it doesn't exist
mkdir -p ~/.config/systemd/user

# Create and edit the service file
nvim ~/.config/systemd/user/clamshell.service

# Reload systemd to recognize the new service
systemctl --user daemon-reload

# Enable and start the service
systemctl --user enable --now clamshell.service
```

**Verify the service:**
```bash
# Check if service is running
systemctl --user status clamshell.service

# View logs if there are issues
journalctl --user -u clamshell.service -f

# Test by opening/closing lid with external monitor connected
```

**Add to Hyprland config** (`~/.config/hypr/autostart.conf` or `~/.config/hypr/hyprland.conf`):
```
exec-once = systemctl --user start clamshell.service
```
> **Note:** This line ensures the service starts when Hyprland launches. If you already enabled the service with `--now`, it's already running, but this ensures it starts on every login.

---

## Troubleshooting

**Service won't start:**
```bash
# Check for errors
journalctl --user -u clamshell.service -n 50

# Common issue: script path wrong
# Make sure ~/scripts/clamshell-mode.sh exists and is executable
ls -la ~/scripts/clamshell-mode.sh
```

**Lid state not detected:**
```bash
# Check if lid state file exists
cat /proc/acpi/button/lid/LID/state

# If file doesn't exist, try finding it:
find /proc/acpi -name "*lid*" 2>/dev/null

# Update the script with correct path if different
```

**Monitors not switching:**
```bash
# Verify monitor names are correct
hyprctl monitors

# Run script manually to see errors
~/scripts/clamshell-mode.sh

# Check Hyprland logs
cat /tmp/hypr/$(ls -t /tmp/hypr/ | head -n 1)/hyprland.log | grep -i monitor
```

**Power profile not changing:**
```bash
# Check if power-profiles-daemon is running
systemctl status power-profiles-daemon

# Check AC state
cat /sys/class/power_supply/AC0/online
# (should be 1 when plugged in, 0 when on battery)

# If AC0 doesn't exist, find your AC adapter:
ls /sys/class/power_supply/
# Update script with correct path (might be AC, ADP0, ADP1, etc.)
```

**Service stops after a while:**
```bash
# Check if service has restart enabled
systemctl --user cat clamshell.service | grep Restart

# Should show: Restart=always
```

---

## Alternative Approaches (Better but More Complex)

While this polling solution works, here are better alternatives:

1. **udev rules** - Trigger on monitor connection/disconnection events
2. **acpid events** - React to lid open/close events directly
3. **Hyprland IPC socket** - Listen to Hyprland events programmatically

These avoid constant polling and are more efficient, but require more setup. The current solution is a good balance of simplicity and functionality.