#!/usr/bin/env bash
# Fedora KDE Plasma package installation script.
set -euo pipefail

if (( EUID != 0 )); then
  exec sudo --preserve-env=TERM,NO_COLOR -- bash -- "$0" "$@"
fi

command -v dnf >/dev/null 2>&1 || { echo "dnf is required." >&2; exit 1; }

# Fedora package name replacements for Arch-era names.
normalize_package_name() {
  case "$1" in
    polkit-kde-agent) printf '%s\n' "polkit-kde" ;;
    swaynotificationcenter) printf '%s\n' "swaync" ;;
    canberra-gtk3) printf '%s\n' "libcanberra-gtk3" ;;
    *) printf '%s\n' "$1" ;;
  esac
}

PACKAGES=(
  intel-media-driver mesa mesa-vulkan-drivers mesa-dri-drivers vulkan-loader vulkan-tools
  sof-firmware linux-firmware
  hyprland uwsm xorg-x11-server-Xwayland xdg-desktop-portal-hyprland xdg-desktop-portal-gtk xhost
  polkit xdg-utils socat inotify-tools libnotify file
  qt5-qtwayland qt6-qtwayland gtk3 gtk4 nwg-look qt5ct qt6ct qt6-qtsvg adw-gtk3-theme
  waybar swww hyprlock hypridle hyprsunset hyprpicker swaynotificationcenter rofi-wayland brightnessctl
  pipewire wireplumber pipewire-pulseaudio playerctl bluez bluez-tools blueman pavucontrol canberra-gtk3 sox
  btrfs-progs compsize zram-generator udisks2 udiskie dosfstools ntfs-3g xdg-user-dirs usbutils gnome-disk-utility
  unzip zip unrar p7zip cpio file-roller rsync
  nemo nemo-extensions file-roller gvfs gvfs-smb gvfs-mtp gvfs-gphoto2 gvfs-afc ffmpegthumbnailer
  network-manager-applet iwd wget curl openssh-server firewalld vsftpd bmon ethtool httrack wavemon firefox
  kitty foot zsh zsh-syntax-highlighting starship fastfetch bat eza fd-find yazi gum tree fzf less ripgrep
  zsh-autosuggestions iperf3 qalculate moreutils
  neovim git git-delta lazygit meson cmake clang uv jq bc viu chafa ccache mold shellcheck shfmt stylua prettier tree-sitter-cli nano
  ffmpeg mpv satty swayimg librsvg2-tools ImageMagick libheif ffmpegthumbnailer grim slurp wl-clipboard cliphist tesseract-langpack-eng
  btop htop nvtop inxi sysstat sysbench logrotate acpid thermald powertop iotop iftop lshw wev gnome-keyring libsecret seahorse yad fwupd perl
  snapshot gnome-text-editor gnome-calculator gnome-clocks zathura zathura-pdf-mupdf cava
  matugen
)

# Install packages one by one so one unavailable package does not block all others.
declare -a FAILED_PACKAGES=()
for package in "${PACKAGES[@]}"; do
  fedora_package="$(normalize_package_name "$package")"
  if ! dnf -y install "$fedora_package"; then
    if [[ "$fedora_package" == "$package" ]]; then
      FAILED_PACKAGES+=("$fedora_package")
      printf 'Failed to install package via dnf: %s\n' "$fedora_package" >&2
    else
      FAILED_PACKAGES+=("$fedora_package (from $package)")
      printf 'Failed to install package via dnf: %s (normalized from %s)\n' "$fedora_package" "$package" >&2
    fi
  fi
done

if (( ${#FAILED_PACKAGES[@]} > 0 )); then
  printf 'Some packages could not be installed with dnf: %s\n' "${FAILED_PACKAGES[*]}" >&2
  SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
  REPO_ROOT="$(cd -- "${SCRIPT_DIR}/../../.." && pwd)"
  GAP_FILE="${REPO_ROOT}/FEDORA_PACKAGE_GAPS.md"
  if [[ -f "$GAP_FILE" ]]; then
    printf 'See %s for Fedora alternatives/COPR guidance.\n' "$GAP_FILE" >&2
  else
    printf 'See FEDORA_PACKAGE_GAPS.md in the Dusky repository for Fedora alternatives/COPR guidance.\n' >&2
  fi
fi
