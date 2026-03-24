#!/usr/bin/env bash
set -euo pipefail

# Records user-session logs for the current boot into a timestamped file.
# Run this BEFORE logging into Hyprland (e.g. from a TTY), leave it running,
# log in, then stop it with Ctrl+C.

OUT_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/dusky/logs"
mkdir -p -- "$OUT_DIR"

stamp="$(date -Is | tr ':+' '__' | tr -d '\n')"
OUT_FILE="${OUT_DIR}/hypr-startup-${stamp}.log"

FILTER='hypr|uwsm|waybar|swww|swaync|swayosd|xdg-desktop-portal|pipewire|wireplumber|matugen'

echo "Writing: $OUT_FILE" >&2
echo "Filter:  $FILTER" >&2

# Follow user journal; you can remove the rg filter to record everything.
journalctl --user -b -o short-precise -f | rg -i "$FILTER" | tee -a "$OUT_FILE"
