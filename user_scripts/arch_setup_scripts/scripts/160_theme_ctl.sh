#!/usr/bin/env bash
set -euo pipefail

THEME_CTL="${HOME}/user_scripts/theme_matugen/theme_ctl.sh"

if [[ ! -x "$THEME_CTL" ]]; then
  echo "theme_ctl not found or not executable: $THEME_CTL" >&2
  exit 1
fi

"$THEME_CTL" refresh
