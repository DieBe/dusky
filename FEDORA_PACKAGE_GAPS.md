# Fedora Package Gaps Overview

The following Arch/AUR-era packages used by Dusky may be missing from default Fedora repositories.
If a package is unavailable, use COPR or install from source.

| Package | Feature / usage in Dusky |
|---|---|
| hyprshade | Shader and color filtering for Hyprland |
| peaclock | Terminal clock utility used in scripts/UI |
| tray-tui | Tray TUI workflow integration |
| wifitui-bin | Wi-Fi text UI helper |
| papirus-folders-git | Folder icon theming tweaks |

## Notes (Fedora 42+)

- `matugen` is available in Fedora repos (`dnf install matugen`).
- `waypaper` is available in Fedora repos (`dnf install waypaper`).
- `SwayNotificationCenter` is the Fedora package providing the `swaync` command.

## COPR / Alternatives

- `hyprshade`: not currently in Fedora repos and COPR search may yield no projects; install from source if you need it.
- `peaclock`, `tray-tui`, `wifitui-bin`, `papirus-folders-git`: typically need third-party packaging (COPR/Flatpak/source) depending on your preference.

