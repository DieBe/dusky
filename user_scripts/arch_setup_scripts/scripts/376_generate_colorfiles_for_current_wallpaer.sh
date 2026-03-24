#!/usr/bin/env bash
set -euo pipefail

THEME_CTL="${HOME}/user_scripts/theme_matugen/theme_ctl.sh"
WALLPAPER_DEFAULT="${HOME}/Pictures/wallpapers/dusk_default.jpg"
WALLPAPER="${1:-$WALLPAPER_DEFAULT}"

if [[ -x "$THEME_CTL" ]]; then
	"$THEME_CTL" refresh || true
	exit 0
fi

if ! command -v matugen >/dev/null 2>&1; then
	echo "[WARN] matugen not found; skipping colorfile generation." >&2
	exit 0
fi

if [[ ! -f "$WALLPAPER" ]]; then
	echo "[WARN] Wallpaper not found: $WALLPAPER; skipping colorfile generation." >&2
	exit 0
fi

matugen image --mode dark --type scheme-fruit-salad "$WALLPAPER"
