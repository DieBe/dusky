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
    swaynotificationcenter|swaync) printf '%s\n' "SwayNotificationCenter" ;;
    canberra-gtk3) printf '%s\n' "libcanberra-gtk3" ;;
    *) printf '%s\n' "$1" ;;
  esac
}

# Required commands used by active Fedora orchestrator scripts.
ensure_required_commands() {
  local -a requirements=(
    "hyprctl:hyprland"
    "brightnessctl:brightnessctl"
    "notify-send:libnotify"
    "uwsm:uwsm"
    "swww:swww"
    "swww-daemon:swww"
    "matugen:matugen"
    "xdg-mime:xdg-utils"
  )
  local req command package fedora_package
  local -a attempted_commands=()
  local -a still_missing_commands=()

  for req in "${requirements[@]}"; do
    command="${req%%:*}"
    package="${req#*:}"
    if ! command -v "$command" >/dev/null 2>&1; then
      attempted_commands+=("$command")
      fedora_package="$(normalize_package_name "$package")"
      if ! dnf -y install "$fedora_package"; then
        FAILED_PACKAGES+=("$fedora_package (required by command '$command')")
        printf "Failed to install required Fedora package '%s' for command '%s'.\n" "$fedora_package" "$command" >&2
      fi

      if ! command -v "$command" >/dev/null 2>&1; then
        still_missing_commands+=("$command")
      fi
    fi
  done

  if (( ${#attempted_commands[@]} > 0 )); then
    printf 'Attempted to install providers for missing commands: %s\n' "${attempted_commands[*]}" >&2
  fi

  if (( ${#still_missing_commands[@]} > 0 )); then
    printf 'Commands still missing after installation attempt: %s\n' "${still_missing_commands[*]}" >&2
  fi
}

PACKAGES=(
  intel-media-driver mesa mesa-vulkan-drivers mesa-dri-drivers vulkan-loader vulkan-tools
  sof-firmware linux-firmware
  hyprland uwsm xorg-x11-server-Xwayland xdg-desktop-portal-hyprland xdg-desktop-portal-gtk xhost
  polkit xdg-utils socat inotify-tools libnotify file
  qt5-qtwayland qt6-qtwayland gtk3 gtk4 nwg-look qt5ct qt6ct qt6-qtsvg adw-gtk3-theme
  waybar swww hyprlock hypridle hyprsunset hyprpicker swaynotificationcenter rofi-wayland brightnessctl
  pipewire wireplumber pipewire-pulseaudio playerctl bluez bluez-tools blueman bluedevil pavucontrol canberra-gtk3 sox
  btrfs-progs compsize zram-generator udisks2 udiskie dosfstools ntfs-3g xdg-user-dirs usbutils kde-partitionmanager
  unzip zip unrar p7zip cpio file-roller rsync
  dolphin ark kate okular gwenview kcalc kclock
  kwalletmanager5 pam-kwallet plasma-nm kde-connect kdeconnectd
  nemo nemo-extensions file-roller gvfs gvfs-smb gvfs-mtp gvfs-gphoto2 gvfs-afc ffmpegthumbnailer
  network-manager-applet iwd wget curl openssh-server firewalld vsftpd bmon ethtool httrack wavemon firefox
  kitty foot zsh zsh-syntax-highlighting starship fastfetch bat eza fd-find yazi gum tree fzf less ripgrep
  zsh-autosuggestions iperf3 qalculate moreutils
  git git-delta meson cmake clang uv jq bc viu chafa ccache mold shellcheck shfmt prettier nano
  ffmpeg mpv satty swayimg librsvg2-tools ImageMagick libheif ffmpegthumbnailer grim slurp wl-clipboard cliphist tesseract-langpack-eng
  btop htop nvtop inxi sysstat sysbench logrotate acpid thermald powertop iotop iftop lshw wev gnome-keyring libsecret seahorse yad fwupd perl
  zathura zathura-pdf-mupdf cava
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

ensure_required_commands

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
