#!/usr/bin/env bash
# Optional Fedora packages (formerly AUR-focused optional step)
set -euo pipefail

if (( EUID == 0 )); then
  echo "Run this script as a normal user; sudo will be used when required." >&2
  exit 1
fi

command -v dnf >/dev/null 2>&1 || { echo "dnf is required." >&2; exit 1; }

OPTIONAL_PACKAGES=(
  wlogout adwaita-qt5 adwaita-qt6 adw-gtk3-theme
  papirus-icon-theme xdg-terminal-exec
)

sudo dnf -y install "${OPTIONAL_PACKAGES[@]}" || true

echo "If any optional package is unavailable in Fedora repos, see /FEDORA_PACKAGE_GAPS.md"
