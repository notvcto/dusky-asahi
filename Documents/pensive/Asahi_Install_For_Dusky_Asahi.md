# Asahi Linux + Dusky Asahi Install Guide

Full walkthrough from a stock Mac to a running Dusky Asahi desktop.

---

## Prerequisites

- M1, M2, or M3 Mac (MacBook Air, MacBook Pro, Mac Mini, iMac)
- macOS present on the machine (required to run the Asahi installer)
- At least 30GB free disk space
- Internet connection

---

## Phase 1 — Install Asahi Linux (from macOS)

Open Terminal on macOS and run the Asahi ALARM installer:

```bash
curl https://asahi-alarm.org/installer-bootstrap.sh | sh
```

The installer will:
1. Ask how much space to allocate to Linux
2. Partition the drive without wiping macOS
3. Install Arch Linux ARM (ALARM) to the new partition
4. Set up the Asahi boot chain (iBoot → m1n1 → U-Boot)
5. Prompt you to shut down, then boot into Linux by holding the power button

When prompted for a distribution, select **Arch Linux ARM**.

After the install completes, shut down the Mac. Hold the power button to enter startup options, select the Asahi partition, and follow the first-boot setup (sets hostname, user, etc.).

Log in as `alarm` (default password: `alarm`). Change it immediately:

```bash
passwd
```

---

## Phase 2 — Bootstrap Dusky Asahi

```bash
# Update the base system and install git
pacman -Syu && pacman -S git

# Clone the Dusky Asahi dotfiles as a bare repo
git clone --bare --depth 1 https://github.com/YOUR_USERNAME/dusky-asahi.git ~/dusky

# Check out config files to $HOME
git --git-dir=~/dusky/ --work-tree=$HOME checkout -f

# Run the orchestrator (NOT as root)
~/user_scripts/arch_setup_scripts/ORCHESTRA_ASAHI.sh
```

The orchestrator is **resumable** — if anything fails or you interrupt it, just re-run and it picks up where it left off.

---

## What the orchestrator installs

- Hyprland + UWSM + all Wayland stack components
- Patched Mesa with AGX GPU driver (from the `[asahi-alarm]` overlay repo)
- PipeWire audio with Apple Silicon UCM profiles (`alsa-ucm-conf-asahi`)
- SDDM display manager (Wayland mode — no Xorg on Apple Silicon)
- Full Matugen theming system (wallpaper → system-wide colour scheme)
- Waybar, Rofi, hyprlock, hypridle, swaync
- Nemo file manager, Kitty terminal, Neovim, Firefox
- paru AUR helper (compiled from source, ~20 min on first run)
- BTRFS snapper snapshots with pacman hooks
- All system services (NetworkManager, Bluetooth, power-profiles-daemon, etc.)

Total time: **45–90 minutes** depending on internet speed.

---

## First boot into Hyprland

SDDM will present the login screen. Log in with your `alarm` credentials.

- Press `Ctrl + Shift + Space` to open the **keybinds cheatsheet**
- Press `Super + Space` to open Rofi launcher
- Press `Super + Q` to open a terminal

To set your wallpaper and generate a colour theme:
Open Rofi → Wallpaper → pick an image. Matugen regenerates all colours automatically.

---

## Display scaling (Retina screens)

Hyprland defaults to `auto` scaling, which should detect ~2x on Retina panels.

To set it explicitly, edit `~/.config/hypr/edit_here/source/monitors.conf`:

```
monitor=eDP-1, preferred, auto, 2.0
```

Reload Hyprland with `Super + Shift + R`.

---

## Troubleshooting

**Blank screen after SDDM starts**
SDDM isn't using Wayland mode. Check that `/etc/sddm.conf.d/20-asahi-wayland.conf` contains `DisplayServer=wayland`. Re-run `466_sddm_asahi_wayland.sh` as root if it's missing.

**No audio**
Run `pacman -Q alsa-ucm-conf-asahi`. If missing, run `051_pacman_asahi_repos.sh` first, then `pacman -S alsa-ucm-conf-asahi`.

**Cursor invisible**
Re-run `035_configure_uwsm_gpu_asahi.sh`. It sets `WLR_NO_HARDWARE_CURSORS=1` in `~/.config/uwsm/env.d/gpu`.

**Orchestrator failed mid-run**
Just re-run `ORCHESTRA_ASAHI.sh`. To start completely fresh: `ORCHESTRA_ASAHI.sh --reset`.

---

## Dual boot with macOS

The Asahi installer preserves macOS. To choose which OS to boot:

- Hold the **power button** at startup → startup disk picker appears
- Select **macOS** or **Arch Linux ARM**

If you ever need to restore macOS only (removes Linux):
Use **Apple Configurator 2** on another Mac via DFU mode, or the standard macOS recovery partition.
