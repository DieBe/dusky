#!/usr/bin/env bash
# Fedora KDE Plasma package installation script.
set -euo pipefail

if (( EUID != 0 )); then
  exec sudo --preserve-env=TERM,NO_COLOR -- bash -- "$0" "$@"
fi

command -v dnf >/dev/null 2>&1 || { echo "dnf is required." >&2; exit 1; }

ENABLE_RPMFUSION=0
if [[ ${1:-} == "--enable-rpmfusion" ]]; then
  ENABLE_RPMFUSION=1
  shift
fi

declare -a FAILED_PACKAGES=()
declare -A FAILED_PACKAGES_SEEN=()

record_failed() {
  local item="${1:-}"
  [[ -z "$item" ]] && return 0
  if [[ -z ${FAILED_PACKAGES_SEEN["$item"]+x} ]]; then
    FAILED_PACKAGES+=("$item")
    FAILED_PACKAGES_SEEN["$item"]=1
  fi
}

rpmfusion_enabled() {
  dnf -q repolist --enabled 2>/dev/null | grep -Eq '^(rpmfusion-free|rpmfusion-nonfree)\b'
}

enable_rpmfusion() {
  local fedora_version
  fedora_version="$(rpm -E %fedora)"
  if rpmfusion_enabled; then
    return 0
  fi
  if rpm -q rpmfusion-free-release rpmfusion-nonfree-release >/dev/null 2>&1; then
    return 0
  fi

  dnf -y install \
    "https://download1.rpmfusion.org/free/fedora/rpmfusion-free-release-${fedora_version}.noarch.rpm" \
    "https://download1.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-${fedora_version}.noarch.rpm"
}

RPMFUSION_ENABLED=0
if (( ENABLE_RPMFUSION == 1 )); then
  enable_rpmfusion || record_failed "rpmfusion release packages"
  if rpmfusion_enabled; then
    RPMFUSION_ENABLED=1
  fi
fi

# Auto-detect already-enabled RPM Fusion repos even when not explicitly requested.
if (( RPMFUSION_ENABLED == 0 )); then
  if rpmfusion_enabled; then
    RPMFUSION_ENABLED=1
  fi
fi

# Fedora package name replacements for Arch-era names.
normalize_package_name() {
  case "$1" in
    polkit-kde-agent) printf '%s\n' "polkit-kde" ;;
    swaynotificationcenter|swaync) printf '%s\n' "SwayNotificationCenter" ;;
    canberra-gtk3) printf '%s\n' "libcanberra-gtk3" ;;
    sof-firmware) printf '%s\n' "alsa-sof-firmware" ;;
    iotop) printf '%s\n' "iotop-c" ;;
    xkbcommon-utils) printf '%s\n' "libxkbcommon-utils" ;;
    ffmpeg)
      if (( RPMFUSION_ENABLED == 1 )); then
        printf '%s\n' "ffmpeg"
      else
        printf '%s\n' "ffmpeg-free"
      fi
      ;;
    *) printf '%s\n' "$1" ;;
  esac
}

log_info() { printf '[INFO] %s\n' "$*"; }
log_warn() { printf '[WARN] %s\n' "$*" >&2; }
log_err()  { printf '[ERR]  %s\n' "$*" >&2; }

preflight_ffmpeg_rpmfusion_swap() {
  # If RPM Fusion is enabled, prefer ffmpeg from RPM Fusion. Fedora's ffmpeg-free
  # conflicts with RPM Fusion's ffmpeg packages.
  if (( RPMFUSION_ENABLED != 1 )); then
    return 0
  fi

  if rpm -q ffmpeg >/dev/null 2>&1; then
    return 0
  fi

  if rpm -q ffmpeg-free >/dev/null 2>&1; then
    log_info "RPM Fusion enabled; swapping ffmpeg-free -> ffmpeg (allow erasing) to avoid conflicts..."
    dnf -y swap ffmpeg-free ffmpeg --allowerasing || record_failed "ffmpeg (swap failed)"
  fi
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
    "xkbcli:libxkbcommon-utils"
    "xdg-mime:xdg-utils"
  )
  local req command package fedora_package
  local -a still_missing_commands=()

  for req in "${requirements[@]}"; do
    command="${req%%:*}"
    package="${req#*:}"
    if ! command -v "$command" >/dev/null 2>&1; then
      still_missing_commands+=("$command")
      fedora_package="$(normalize_package_name "$package")"
      record_failed "$fedora_package (required for '$command')"
    fi
  done

  if (( ${#still_missing_commands[@]} > 0 )); then
    printf 'Commands still missing after installation attempt: %s\n' "${still_missing_commands[*]}" >&2
  fi
}

PACKAGES=(
  intel-media-driver mesa-vulkan-drivers mesa-dri-drivers vulkan-loader vulkan-tools
  sof-firmware linux-firmware
  hyprland uwsm xorg-x11-server-Xwayland xdg-desktop-portal-hyprland xdg-desktop-portal-gtk
  libxkbcommon-utils
  polkit xdg-utils socat inotify-tools libnotify file xhost
  qt5-qtwayland qt6-qtwayland gtk3 gtk4 nwg-look qt5ct qt6ct qt6-qtsvg adw-gtk3-theme
  waybar swww hyprlock hypridle hyprsunset hyprpicker swaynotificationcenter rofi-wayland brightnessctl
  pipewire wireplumber pipewire-pulseaudio playerctl bluez bluez-tools blueman bluedevil pavucontrol canberra-gtk3 sox
  btrfs-progs compsize zram-generator udisks2 udiskie dosfstools ntfs-3g xdg-user-dirs usbutils kde-partitionmanager
  unzip zip unrar p7zip cpio file-roller rsync
  dolphin ark kate okular gwenview kcalc kclock
  kwalletmanager5 pam-kwallet plasma-nm kde-connect kdeconnectd
  gvfs gvfs-smb gvfs-mtp gvfs-gphoto2 gvfs-afc ffmpegthumbnailer
  iwd wget2-wget curl openssh-server firewalld vsftpd bmon ethtool httrack wavemon firefox
  kitty foot zsh zsh-syntax-highlighting fastfetch bat fd-find gum tree fzf less ripgrep
  zsh-autosuggestions iperf3 qalculate moreutils
  git git-delta meson cmake clang uv jq bc chafa ccache mold ShellCheck shfmt nano
  ffmpeg mpv satty swayimg librsvg2-tools ImageMagick libheif ffmpegthumbnailer grim slurp wl-clipboard cliphist tesseract-langpack-eng
  btop htop nvtop inxi sysstat sysbench logrotate acpid thermald powertop iotop iftop lshw wev yad fwupd perl
  cava
  matugen
)

# Tools that are frequently missing from Fedora repos; install from source if absent.
SOURCE_TOOLS=(
  starship
  eza
  yazi
  lazygit
  viu
  stylua
  prettier
  hyprshade
)

ensure_dnf_package() {
  local pkg="$1"
  [[ -z "$pkg" ]] && return 0
  if rpm -q "$pkg" >/dev/null 2>&1; then
    return 0
  fi
  dnf -y install "$pkg"
}

ensure_rust_build_deps() {
  ensure_dnf_package rust || return 1
  ensure_dnf_package cargo || return 1
  ensure_dnf_package gcc || return 1
  ensure_dnf_package make || return 1
  ensure_dnf_package pkgconf-pkg-config || return 1
  ensure_dnf_package openssl-devel || return 1
}

cargo_install_locked_root() {
  local crate="$1"
  [[ -z "$crate" ]] && return 1
  mkdir -p /usr/local/bin
  cargo install --locked --root /usr/local "$crate"
}

ensure_go_build_deps() {
  # Fedora's Go package name is 'golang'
  ensure_dnf_package golang
}

go_install_to_usr_local_bin() {
  local module="$1"
  [[ -z "$module" ]] && return 1
  mkdir -p /usr/local/bin
  GOBIN=/usr/local/bin go install "${module}@latest"
}

ensure_node_build_deps() {
  ensure_dnf_package nodejs
  ensure_dnf_package npm
}

npm_install_global() {
  local pkg="$1"
  [[ -z "$pkg" ]] && return 1
  npm install -g "$pkg"
}

ensure_python_pip() {
  ensure_dnf_package python3-pip
}

pip_install_prefix_usr_local() {
  local pkg="$1"
  [[ -z "$pkg" ]] && return 1
  python3 -m pip install --no-input --upgrade --prefix /usr/local --break-system-packages "$pkg"
}

install_source_tool_if_missing() {
  local tool="$1"
  [[ -z "$tool" ]] && return 0

  case "$tool" in
    prettier)
      if command -v prettier >/dev/null 2>&1; then
        return 0
      fi
      log_info "Installing prettier via npm..."
      ensure_node_build_deps || return 1
      npm_install_global prettier
      ;;
    lazygit)
      if command -v lazygit >/dev/null 2>&1; then
        return 0
      fi
      log_info "Installing lazygit from source via go install..."
      ensure_go_build_deps || return 1
      go_install_to_usr_local_bin github.com/jesseduffield/lazygit
      ;;
    hyprshade)
      if command -v hyprshade >/dev/null 2>&1; then
        return 0
      fi
      log_info "Installing hyprshade via pip..."
      ensure_python_pip || return 1
      pip_install_prefix_usr_local hyprshade
      ;;
    starship)
      if command -v starship >/dev/null 2>&1; then
        return 0
      fi
      log_info "Installing starship from source via cargo..."
      ensure_rust_build_deps || return 1
      cargo_install_locked_root starship
      ;;
    eza)
      if command -v eza >/dev/null 2>&1; then
        return 0
      fi
      log_info "Installing eza from source via cargo..."
      ensure_rust_build_deps || return 1
      cargo_install_locked_root eza
      ;;
    viu)
      if command -v viu >/dev/null 2>&1; then
        return 0
      fi
      log_info "Installing viu from source via cargo..."
      ensure_rust_build_deps || return 1
      cargo_install_locked_root viu
      ;;
    stylua)
      if command -v stylua >/dev/null 2>&1; then
        return 0
      fi
      log_info "Installing stylua from source via cargo..."
      ensure_rust_build_deps || return 1
      cargo_install_locked_root stylua
      ;;
    yazi)
      if command -v yazi >/dev/null 2>&1; then
        return 0
      fi
      log_info "Installing yazi from source via cargo (yazi-build)..."
      ensure_rust_build_deps || return 1
      mkdir -p /usr/local/bin
      CARGO_INSTALL_ROOT=/usr/local cargo install --locked --force --root /usr/local yazi-build
      ;;
    *)
      log_warn "No source installer defined for: $tool"
      return 1
      ;;
  esac
}

collect_unavailable_packages_from_log() {
  local log_file="$1"
  local -a missing=()
  local line

  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    missing+=("$line")
  done < <(
    {
      grep -oP 'No match for argument: \K\S+' "$log_file" || true
      grep -oP '^Skipping unavailable packages:\s*\K.*' "$log_file" | tr ' ' '\n' || true
      grep -oP '^No match for arguments:\s*\K.*' "$log_file" | tr ' ' '\n' || true
    } | sed 's/[,:]$//' | sed '/^$/d' | sort -u
  )

  if (( ${#missing[@]} > 0 )); then
    for line in "${missing[@]}"; do
      record_failed "$line"
    done
  fi
}

collect_unavailable_packages_via_repoquery() {
  local -a requested_packages=("$@")
  local -A available=()
  local pkg

  while IFS= read -r pkg; do
    [[ -z "$pkg" ]] && continue
    available["$pkg"]=1
  done < <(dnf -q repoquery --available --qf '%{name}\n' "${requested_packages[@]}" 2>/dev/null || true)

  local -a missing=()
  for pkg in "${requested_packages[@]}"; do
    if rpm -q "$pkg" >/dev/null 2>&1; then
      continue
    fi
    if [[ -z ${available["$pkg"]+x} ]]; then
      missing+=("$pkg")
    fi
  done

  if (( ${#missing[@]} > 0 )); then
    for pkg in "${missing[@]}"; do
      record_failed "$pkg"
    done
  fi
}

bulk_install_packages() {
  local -a requested_packages=("$@")
  local log_file
  log_file="$(mktemp -t dusky-dnf-install.XXXXXX.log)"
  if dnf -y install --skip-unavailable "${requested_packages[@]}" 2>&1 | tee "$log_file"; then
    collect_unavailable_packages_from_log "$log_file"
    collect_unavailable_packages_via_repoquery "${requested_packages[@]}"
    rm -f -- "$log_file"
    return 0
  fi

  collect_unavailable_packages_from_log "$log_file"
  collect_unavailable_packages_via_repoquery "${requested_packages[@]}"
  rm -f -- "$log_file"
  return 1
}

declare -a NORMALIZED_PACKAGES=()
declare -A SEEN_PACKAGES=()
for package in "${PACKAGES[@]}"; do
  fedora_package="$(normalize_package_name "$package")"
  [[ -z "$fedora_package" ]] && continue
  if [[ -z ${SEEN_PACKAGES["$fedora_package"]+x} ]]; then
    NORMALIZED_PACKAGES+=("$fedora_package")
    SEEN_PACKAGES["$fedora_package"]=1
  fi
done

preflight_ffmpeg_rpmfusion_swap

if ! bulk_install_packages "${NORMALIZED_PACKAGES[@]}"; then
  printf 'dnf returned a non-zero status during bulk install; continuing with required-command checks.\n' >&2
fi

# If rpmfusion is enabled and ffmpeg install failed due to conflicts, try a safe swap.
if (( RPMFUSION_ENABLED == 1 )); then
  if ! command -v ffmpeg >/dev/null 2>&1; then
    if rpm -q ffmpeg-free >/dev/null 2>&1; then
      log_info "Attempting ffmpeg-free -> ffmpeg swap (rpmfusion enabled)..."
      dnf -y swap ffmpeg-free ffmpeg --allowerasing || record_failed "ffmpeg (swap failed)"
    fi
  fi
fi

ensure_required_commands

# Install tools that Fedora repos commonly lack.
for tool in "${SOURCE_TOOLS[@]}"; do
  if ! install_source_tool_if_missing "$tool"; then
    record_failed "$tool (source install failed)"
  fi
done

# Final verification: fail hard if any requested source tool is still missing.
for tool in "${SOURCE_TOOLS[@]}"; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    record_failed "$tool (command missing after install)"
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

  # Orchestrator requirement: treat unresolved packages as a hard failure.
  exit 1
fi
