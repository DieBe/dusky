# Fedora Package Gaps Overview

The following Arch/AUR-era packages used by Dusky may be missing from default Fedora repositories.
If a package is unavailable, use COPR or install from source.

## Automation note

The Fedora installer script attempts to install several common CLI tools from source automatically (via `cargo`, `go`, `npm`, or `pip`) when they are not available in enabled Fedora repos.

| Package | Feature / usage in Dusky |
|---|---|
| hyprshade | Shader and color filtering for Hyprland |
| peaclock | Terminal clock utility used in scripts/UI |
| tray-tui | Tray TUI workflow integration |
| wifitui-bin | Wi-Fi text UI helper |
| papirus-folders-git | Folder icon theming tweaks |
| starship | Shell prompt (CLI) |
| eza | Modern `ls` replacement (CLI) |
| yazi | TUI file manager (CLI) |
| lazygit | TUI git client (CLI) |
| viu | Terminal image viewer (CLI) |
| stylua | Lua formatter (CLI) |
| prettier / nodejs-prettier | JS/TS formatter (CLI) |

## Notes (Fedora 42+)

- `matugen` is available in Fedora repos (`dnf install matugen`).
- `waypaper` is available in Fedora repos (`dnf install waypaper`).
- `SwayNotificationCenter` is the Fedora package providing the `swaync` command.

## COPR / Alternatives

- `hyprshade`: not currently in Fedora repos and COPR search may yield no projects; install from source if you need it.
- `peaclock`, `tray-tui`, `wifitui-bin`, `papirus-folders-git`: typically need third-party packaging (COPR/Flatpak/source) depending on your preference.

### Common CLI tools (often not in Fedora repos)

If these show up in the installer’s “could not be installed” list, it means they are not available in your currently-enabled repos.

- `starship`, `eza`, `yazi`, `lazygit`, `viu`, `stylua`: often installed via COPR or from upstream (many are Rust/Go projects).
	- Rust-based tools can usually be installed via `cargo install <tool> --locked`.
	- Go-based tools can usually be installed via `go install <module>@latest`.
- `prettier`: usually installed via Node (`npm install -g prettier`).

