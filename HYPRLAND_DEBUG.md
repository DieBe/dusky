# Hyprland runtime debugging (Dusky)

## Record startup errors (recommended)

From a TTY (Ctrl+Alt+F3) **before** logging into Hyprland, run:

- `bash ~/user_scripts/hypr/record_hypr_startup_logs.sh`

Then log into Hyprland normally. After ~15–30 seconds, stop recording with Ctrl+C.

The script writes a timestamped log to:

- `$XDG_STATE_HOME/dusky/logs/` (usually `~/.local/state/dusky/logs/`)

## Quick “what broke?” snapshots

- User session warnings/errors for current boot:
  - `journalctl --user -b -p warning..alert -o short-precise`

- System warnings/errors for current boot:
  - `journalctl -b -p warning..alert -o short-precise`

## Waybar autostart diagnostics

Waybar autostart is managed by the script in:

- [user_scripts/waybar/waybar_autostart.sh](user_scripts/waybar/waybar_autostart.sh)

It writes a log to:

- `$XDG_STATE_HOME/dusky/waybar_autostart.log` (usually `~/.local/state/dusky/waybar_autostart.log`)

Look for these lines in that log:

- `Env: WAYLAND_DISPLAY=...`
- `Env: HYPRLAND_INSTANCE_SIGNATURE=...`

If `WAYLAND_DISPLAY` is missing at login-time, Waybar may fail to start.

## Notifications: common error cause

If KDE/Plasma notifications are also running, they can conflict with SwayNC (both want `org.freedesktop.Notifications`).

Signs of this in logs:

- `plasmashell: Failed to register Notification service on DBus`
- `dbus-broker: Ignoring duplicate name 'org.freedesktop.Notifications' ...`

If you want SwayNC to be the only notification daemon in Hyprland, stop Plasma services in the Hyprland session (ask Copilot to add a safe Hypr-only autostart stop-list).



journalctl --user -b | grep -i waybar
journalctl --user -b | grep -i matugen