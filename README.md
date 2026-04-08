# Dusky Asahi — Apple Silicon Port

A port of [Dusky](https://github.com/dusklinux/dusky) to **Apple Silicon Macs** running **Asahi Linux** (Arch Linux ARM / ALARM).

This fork adapts the full Dusky Hyprland desktop environment for M1/M2/M3 hardware — AGX GPU, Apple audio, unified memory, and Asahi's boot chain — while staying as close to the upstream experience as possible.

> **Upstream credit:** All the desktop design, theming architecture, scripts, and features come from [Dusky by dusklinux](https://github.com/dusklinux/dusky). This repo is purely an adaptation layer. If you're on x86, use the original.

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

## Prerequisites

- An **M1, M2, or M3 Mac** (MacBook Air, MacBook Pro, Mac Mini, iMac)
- **macOS** present on the machine to run the Asahi installer
- An internet connection
- ~30GB free space recommended

The Asahi installer uses **BTRFS** by default — this is required for the snapper snapshot scripts at the end of the setup sequence.

---

## Installation

### Phase 1 — Install Asahi Linux

Run the Asahi ALARM installer from macOS:

```bash
curl https://asahi-alarm.org/installer-bootstrap.sh | sh
```

Follow the prompts. When it asks for a distribution, choose **Arch Linux ARM**. The installer will partition your drive, install a minimal ALARM base system, and reboot into Linux.

Log in as `alarm` (password: `alarm`).

---

### Phase 2 — Deploy Dusky Asahi

Install git, clone the dotfiles, and run the orchestrator:

```bash
# 1. Install git (not in ALARM base)
pacman -Syu && pacman -S git

# 2. Clone the Dusky Asahi dotfiles
git clone --bare --depth 1 https://github.com/YOUR_USERNAME/dusky-asahi.git ~/dusky
git --git-dir=~/dusky/ --work-tree=$HOME checkout -f

# 3. Run the orchestrator (as your normal user, NOT root)
~/user_scripts/arch_setup_scripts/ORCHESTRA_ASAHI.sh
```

The orchestrator runs ~90 numbered scripts sequentially. It is **idempotent** — safe to interrupt and re-run. Progress is tracked in `~/Documents/.install_state_asahi`.

Expect **45–90 minutes** on first run. The longest step is compiling `paru` from source (~20 min — it's a Rust project, and the aarch64 ALARM repos don't ship a paru binary).

---

## What the orchestrator does

Setup is split into numbered subscripts in `user_scripts/arch_setup_scripts/scripts/`. Key Asahi-specific scripts:

| Script | What it does |
|---|---|
| `035_configure_uwsm_gpu_asahi.sh` | Detects the AGX DRM node and writes `~/.config/uwsm/env.d/gpu` |
| `051_pacman_asahi_repos.sh` | Adds the `[asahi-alarm]` overlay repo; bootstraps the keyring; ensures sudo and sudoers are present on minimal ALARM |
| `060_package_installation_asahi.sh` | Full ARM64-adapted package install (Hyprland, PipeWire, mesa from asahi-alarm, etc.) |
| `100_paru_packages_asahi.sh` | AUR packages with x86-only entries removed; adds `shellcheck-bin` (official ARM64 binary) |
| `290_system_services_asahi.sh` | Enables system services; `power-profiles-daemon` replaces TLP; `iio-sensor-proxy` for ambient light sensor |
| `466_sddm_asahi_wayland.sh` | Writes `/etc/sddm.conf.d/20-asahi-wayland.conf` — forces SDDM into Wayland mode (no Xorg on Apple Silicon) |

Everything else (Hyprland config, theming, Waybar, Rofi, SDDM theme, PipeWire, snapper, etc.) is identical to upstream Dusky.

---

## Hardware status

Tested in a QEMU aarch64 VM. Real hardware testing pending.

| Feature | Status | Notes |
|---|---|---|
| AGX GPU / Hyprland | Expected ✅ | Requires patched mesa from `[asahi-alarm]` |
| Display output | Expected ✅ | `WLR_NO_HARDWARE_CURSORS=1` set by default |
| Audio (speakers/mic) | Expected ✅ | `alsa-ucm-conf-asahi` UCM profiles installed |
| Bluetooth | Expected ✅ | Asahi kernel has Apple BT controller support |
| WiFi | Expected ✅ | `brcmfmac` + firmware from Asahi installer |
| Touchpad gestures | Likely ✅ | `libinput`; Apple Magic Trackpad may need quirks tuning |
| Battery notifications | Expected ✅ | Detection fixed for `macsmc-battery` naming |
| Ambient light sensor | Expected ✅ | `iio-sensor-proxy` installed and enabled |
| Display scaling | Needs testing | `monitor=,preferred,auto,auto` — Hyprland auto-detects ~2x on Retina |
| Camera (FaceTime HD) | Needs testing | `apple-isp` driver; `cameractrls` and `snapshot` installed |
| Suspend/resume | Needs testing | Default systemd-logind lid behaviour; S2Idle on Apple Silicon |
| GPU-accelerated video encode | Not yet | VA-API encode on AGX not stable upstream |

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

## Keybinds

Press `Ctrl + Shift + Space` to open the keybinds cheatsheet at any time.

Key defaults inherited from Dusky:

| Keybind | Action |
|---|---|
| `Super + Q` | Open terminal (kitty) |
| `Super + E` | File manager (Nemo) |
| `Super + F` | Firefox |
| `Super + Space` | Rofi launcher |
| `Super + Shift + S` | Screenshot / screen capture |
| `Super + L` | Lock screen (hyprlock) |

---

## Troubleshooting

**Blank screen after SDDM starts**
SDDM failed to use the Wayland backend. Check `/etc/sddm.conf.d/20-asahi-wayland.conf` exists and contains `DisplayServer=wayland`. Re-run `466_sddm_asahi_wayland.sh` as root if missing.

**No audio**
Check that `alsa-ucm-conf-asahi` is installed (`pacman -Q alsa-ucm-conf-asahi`). If missing, run `051_pacman_asahi_repos.sh` first (sets up the `[asahi-alarm]` repo), then `pacman -S alsa-ucm-conf-asahi`.

**Cursor invisible in Hyprland**
`WLR_NO_HARDWARE_CURSORS=1` should be set in `~/.config/uwsm/env.d/gpu` by the `035` script. Re-run `035_configure_uwsm_gpu_asahi.sh` if the file is missing.

**Script failed mid-run**
ORCHESTRA_ASAHI is resumable. Just re-run it — completed steps are skipped. To restart from scratch: `ORCHESTRA_ASAHI.sh --reset`.

**paru takes 20+ minutes to build**
Normal on aarch64. The ALARM repos don't ship a paru binary; it compiles from source. M1/M2 real hardware will be significantly faster than QEMU.

---

## Acknowledgments

This is a direct port of **[Dusky](https://github.com/dusklinux/dusky)** by dusklinux. All credit for the desktop design, theming system, Waybar configs, Rofi menus, scripts, and overall architecture belongs to the upstream project. Please star the original repo.

SDDM theme is a modified version of **[SilentSDDM](https://github.com/uiriansan/SilentSDDM)** by @uiriansan.
