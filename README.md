<div align="center">

# Dusky Asahi

**The full Dusky Hyprland desktop, native on Apple Silicon**

[![License: MIT](https://img.shields.io/badge/License-MIT-5c6bc0?style=flat-square)](LICENSE)
[![GitHub Stars](https://img.shields.io/github/stars/notvcto/dusky-asahi?style=flat-square&color=ffd700&label=Stars)](https://github.com/notvcto/dusky-asahi)
[![Apple Silicon](https://img.shields.io/badge/Apple_Silicon-M1%20%7C%20M2%20%7C%20M3-silver?style=flat-square&logo=apple&logoColor=white)](https://asahilinux.org)
[![Arch Linux ARM](https://img.shields.io/badge/Arch_Linux_ARM-aarch64-1793d1?style=flat-square&logo=archlinux&logoColor=white)](https://archlinuxarm.org)
[![Asahi Linux](https://img.shields.io/badge/Asahi_Linux-compatible-f97316?style=flat-square)](https://asahilinux.org)
[![Hyprland](https://img.shields.io/badge/Hyprland-Wayland-58e1ff?style=flat-square)](https://hyprland.org)
[![Upstream: Dusky](https://img.shields.io/badge/upstream-dusklinux%2Fdusky-6e40c9?style=flat-square)](https://github.com/dusklinux/dusky)

<br>

*A port of [Dusky](https://github.com/dusklinux/dusky) to M1 / M2 / M3 Macs running [Asahi Linux](https://asahilinux.org) (Arch Linux ARM). Every feature of the Dusky experience — Matugen theming, Waybar layouts, Rofi menus, the Dusky Control Center, BTRFS snapshots, PipeWire audio — adapted for ARM64 and the Asahi boot chain, with AGX GPU support and Apple audio profiles.*

*If you're on x86, use the [original Dusky](https://github.com/dusklinux/dusky). All credit for the desktop design, theming system, and features belongs there — this repo is purely an adaptation layer.*

</div>

---

---

## What's different from upstream Dusky

| Area | Upstream (x86) | This fork (Asahi) |
|---|---|---|
| GPU detection | PCI vendor ID (Intel/AMD/NVIDIA) | AGX platform device, non-PCI |
| GPU env | `LIBVA_DRIVER_NAME`, etc. | `AQ_DRM_DEVICES`, `WLR_NO_HARDWARE_CURSORS=1` |
| Mesa | Standard mesa | Patched mesa from `[asahi-alarm]` repo (AGX driver) |
| Audio | Standard ALSA/PipeWire | `alsa-ucm-conf-asahi` (Apple UCM profiles) |
| Power | TLP + thermald | `power-profiles-daemon` (Apple platform driver) |
| Boot | systemd-boot or GRUB | iBoot → m1n1 → U-Boot (Asahi chain, untouched) |
| Display manager | SDDM (X11 or Wayland) | SDDM forced to Wayland (no Xorg on Apple Silicon) |
| Kernel headers | `linux-headers` | `linux-asahi-headers` |
| Packages | Full x86 list | ARM64-only packages; x86-only AUR packages removed |
| Conductor | `ORCHESTRA.sh` | `ORCHESTRA_ASAHI.sh` (separate state file) |

---

## ⚠️ Prerequisites & Hardware

### Hardware

- An **M1, M2, or M3 Mac** (MacBook Air, MacBook Pro, Mac Mini, iMac)
- **macOS** present on the machine to run the Asahi installer
- An internet connection
- ~30 GB free space recommended

### Filesystem

> **BTRFS recommended.** When the Asahi installer asks which variant to install, choose the **BTRFS desktop** option. It automatically sets up two subvolumes (`@` for `/` and `@home` for `/home`) — exactly what the snapper snapshot scripts expect.

BTRFS also gives you:

- ZSTD compression to save disk space
- Copy-on-Write to prevent data corruption
- Instant snapshots via snapper

The setup should also work on ext4, but snapshots won't be available.

### GPU

GPU environment is auto-detected by `035_configure_uwsm_gpu_asahi.sh`, which writes `~/.config/uwsm/env.d/gpu`. If detection fails, edit that file manually and set `AQ_DRM_DEVICES` to your DRM node (e.g. `/dev/dri/card0`).

---

## Installation 💿

### Phase 1 — Install Asahi Linux

Run the Asahi ALARM installer from macOS Terminal:

```bash
curl https://asahi-alarm.org/installer-bootstrap.sh | sh
```

When prompted by the installer:

- Choose **Desktop** (not minimal) — installs the full GUI environment
- Choose the **BTRFS variant** — sets up `@` and `@home` subvolumes automatically

Default credentials after first boot:
- User: `alarm` / Password: `alarm`
- Root: `root` / Password: `root`

---

### Phase 2 — Deploy Dusky Asahi

All pacman operations require root. Switch to root first:

```bash
su root
# password: root
```

Initialize the pacman keyring (required on every fresh ALARM install before using pacman):

```bash
pacman-key --init
pacman-key --populate archlinuxarm
```

Install git and clone the dotfiles:

```bash
pacman -Syu git

git clone --bare --depth 1 https://github.com/notvcto/dusky-asahi.git ~/dusky
git --git-dir=~/dusky/ --work-tree=$HOME checkout -f
```

Run the orchestrator as your **normal user** (`alarm`), not root:

```bash
su alarm
~/user_scripts/arch_setup_scripts/ORCHESTRA_ASAHI.sh
```

The orchestrator runs ~90 numbered scripts sequentially. It is **idempotent** — safe to interrupt and re-run. Progress is tracked in `~/Documents/.install_state_asahi`.

Expect **45–90 minutes** on first run. The longest step is compiling `paru` from source (~20 min — it's a Rust project and the aarch64 ALARM repos don't ship a binary).

---

## What the orchestrator does

Setup is split into numbered subscripts in `user_scripts/arch_setup_scripts/scripts/`. Key Asahi-specific scripts:

| Script | What it does |
|---|---|
| `035_configure_uwsm_gpu_asahi.sh` | Detects the AGX DRM node and writes `~/.config/uwsm/env.d/gpu` |
| `051_pacman_asahi_repos.sh` | Adds the `[asahi-alarm]` overlay repo; bootstraps the keyring; ensures sudo and sudoers are present |
| `060_package_installation_asahi.sh` | Full ARM64-adapted package install (Hyprland, PipeWire, mesa from asahi-alarm, etc.) |
| `100_paru_packages_asahi.sh` | AUR packages with x86-only entries removed; adds `shellcheck-bin` (official ARM64 binary) |
| `290_system_services_asahi.sh` | Enables system services; `power-profiles-daemon` replaces TLP; `iio-sensor-proxy` for ambient light |
| `466_sddm_asahi_wayland.sh` | Forces SDDM into Wayland mode — writes `/etc/sddm.conf.d/20-asahi-wayland.conf` |

Everything else (Hyprland config, theming, Waybar, Rofi, SDDM theme, PipeWire, snapper, etc.) is identical to upstream Dusky.

---

## Hardware status

Real hardware testing in progress (M1/M2).

| Feature | Status | Notes |
|---|---|---|
| AGX GPU / Hyprland | ⚙️ Configured | Requires patched mesa from `[asahi-alarm]` |
| Display output | ⚙️ Configured | `WLR_NO_HARDWARE_CURSORS=1` set by default |
| Audio (speakers/mic) | ⚙️ Configured | `alsa-ucm-conf-asahi` UCM profiles installed |
| Bluetooth | ⚙️ Configured | Asahi kernel has Apple BT controller support |
| WiFi | ⚙️ Configured | `brcmfmac` + firmware from Asahi installer |
| Touchpad gestures | ⚙️ Configured | `libinput`; Apple Magic Trackpad may need quirks tuning |
| Battery notifications | ⚙️ Configured | Detection fixed for `macsmc-battery` naming |
| Ambient light sensor | ⚙️ Configured | `iio-sensor-proxy` installed and enabled |
| Display scaling | 🧪 Untested | `monitor=,preferred,auto,auto` — Hyprland auto-detects ~2x on Retina |
| Camera (FaceTime HD) | 🧪 Untested | `apple-isp` driver; `cameractrls` installed |
| Suspend/resume | 🧪 Untested | S2Idle on Apple Silicon; default systemd-logind lid behaviour |
| GPU-accelerated video encode | ❌ Not yet | VA-API encode on AGX not stable upstream |

---

## Overview

### Theming & visuals

- **Matugen** — unified light/dark mode across Hyprland, Waybar, Rofi, GTK, Firefox, and Spicetify, all regenerated from your wallpaper
- Waybar in four layouts: horizontal, vertical, block, circular — pick during setup, toggle from Rofi at any time
- Instant shader switching via Rofi
- Fluid animations — tuned physics and momentum for a liquid feel
- Dusky Control Center — GTK4/Libadwaita GUI for settings and features in one place

### Utilities

- Music recognition — look up what's currently playing
- Circle-to-search via Google Lens
- Local AI inference via Ollama sidebar (terminal-based, resource-efficient)
- Color picker
- Sysbench benchmarking
- Live disk I/O monitoring — useful for tracking copy progress on external drives
- BTRFS compression ratio scanner — see how much space ZSTD is saving

### Audio & input

- Quick audio input/output switching via keybind (e.g. speakers ↔ Bluetooth headphones)
- Mono/stereo audio toggle
- Mechanical keypress sounds, toggleable via keybind or Rofi
- GUI sliders for volume, brightness, and night light intensity (keybind-invokable)
- Speech-to-text: Whisper (CPU)
- Text-to-speech: Kokoro (CPU and GPU)
- Touchpad gestures for volume, brightness, screen lock, Swaync, play/pause, mute

### Hyprland & desktop

- TUI for tuning Hyprland appearance: gaps, shadow color, blur strength, opacity, and more
- Keybind TUI setter with conflict detection — auto-unbinds conflicting entries in `hyprland.conf`
- Dynamic fractional scaling — scale your display with a keybind
- Toggle window transparency, blur, and shadow with a single keybind
- Hypridle TUI configuration
- Switch Swaync notification panel side (left/right)
- Wlogout drawn dynamically to respect your fractional scaling
- Battery notifications with configurable threshold levels
- Toggleable power-saver mode
- USB plug/unplug sounds

### Networking & system

- FTP, Tailscale, OpenSSH auto-setup scripts
- Cloudflare WARP setup, toggleable from Rofi
- VNC setup for iPhone (wired)
- WiFi connect script at `~/user_scripts/network_manager/nmcli_wifi.sh`
- System cleanup — cache purge to reclaim storage
- Drive manager — lock/unlock encrypted drives from the terminal with auto-mount; NTFS metadata fix included
- GitHub bare-repo backup integration — configure `~/.git_dusky_list` with files to back up

### Rofi menus

Emoji · Calculator · Matugen theme switcher · Animation switcher · Power menu · Clipboard · Wallpaper selector · Shader menu · System menu

### Performance

- **Lightweight** — ~900 MB RAM, ~5 GB disk (fully configured)
- **ZSTD & ZRAM** — compression enabled by default; ZRAM roughly triples effective RAM on low-memory machines
- **Native build flags** — AUR helper configured to build with CPU-native optimisations
- **UWSM** — Hyprland session managed via UWSM for a clean, minimal startup

---

## Customising your setup

All user-editable config lives in:

```
~/.config/hypr/edit_here/     ← Hyprland: keybinds, monitor, rules, animations
~/.config/waybar/             ← Waybar layouts and styles
~/.config/uwsm/env.d/gpu      ← GPU environment (written by 035 script)
```

For display scaling on a Retina screen, edit `~/.config/hypr/edit_here/source/monitors.conf`:

```
monitor=eDP-1, preferred, auto, 2.0
```

---

## ⌨️ Keybinds

Press `Ctrl + Shift + Space` to open the keybinds cheatsheet at any time. Commands in the cheatsheet are clickable.

Key defaults inherited from Dusky:

| Keybind | Action |
|---|---|
| `Super + Q` | Open terminal (kitty) |
| `Super + E` | File manager (Nemo) |
| `Super + F` | Firefox |
| `Alt + Space` | Rofi launcher |
| `Super + S` | Screenshot / screen capture |
| `Super + M` | Lock screen (hyprlock) |

---

## 🔧 Troubleshooting

### A script failed mid-run

Scripts are modular — a single failure rarely blocks the rest. The orchestrator is resumable: just re-run `ORCHESTRA_ASAHI.sh` and completed steps are skipped. To identify what failed, check the terminal output and find the subscript by name in `~/user_scripts/arch_setup_scripts/scripts/` — each one can be run individually. To start completely fresh, delete `~/Documents/.install_state_asahi` and re-run.

### Blank screen after SDDM starts

SDDM failed to launch the Wayland backend. Check that `/etc/sddm.conf.d/20-asahi-wayland.conf` exists and contains `DisplayServer=wayland`. If it's missing, re-run `466_sddm_asahi_wayland.sh` as root.

### No audio

Verify `alsa-ucm-conf-asahi` is installed:

```bash
pacman -Q alsa-ucm-conf-asahi
```

If missing, run `051_pacman_asahi_repos.sh` first to set up the `[asahi-alarm]` repo, then install it:

```bash
pacman -S alsa-ucm-conf-asahi
```

### Cursor invisible in Hyprland

`WLR_NO_HARDWARE_CURSORS=1` must be set in `~/.config/uwsm/env.d/gpu`. Re-run `035_configure_uwsm_gpu_asahi.sh` if the file is missing or empty.

### paru takes 20+ minutes to build

Expected on aarch64 — the ALARM repos don't ship a paru binary, so it compiles from source (Rust project). Let it run.

---

## Acknowledgments

This is a direct port of **[Dusky](https://github.com/dusklinux/dusky)** by dusklinux. All credit for the desktop design, theming system, Waybar configs, Rofi menus, scripts, and overall architecture belongs to the upstream project. Please star the original repo.

SDDM theme is a modified version of **[SilentSDDM](https://github.com/uiriansan/SilentSDDM)** by @uiriansan.
