#!/usr/bin/env bash
# Remove GNOME Keyring components (KDE uses KWallet)
# ==============================================================================
# Script Name: remove_gnome_keyring_use_kwallet.sh
# Description: Removes GNOME Keyring (and any PAM hooks it added) and ensures
#              KDE's KWallet PAM integration packages are installed.
# Target:      /etc/pam.d/login (removal only; no new PAM lines are added)
# ==============================================================================

set -euo pipefail

# --- Configuration ---
TARGET_FILE="/etc/pam.d/login"
BACKUP_DIR="/etc/pam.d"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
BACKUP_FILE="${TARGET_FILE}.bak.${TIMESTAMP}"
REMOVE_PACKAGES=("gnome-keyring" "seahorse")
INSTALL_PACKAGES=("pam-kwallet" "kwalletmanager5")

# --- Formatting ---
BOLD=$'\e[1m'
GREEN=$'\e[32m'
YELLOW=$'\e[33m'
RED=$'\e[31m'
RESET=$'\e[0m'

# --- Helper Functions ---

log_info() {
    printf "${BOLD}${GREEN}[INFO]${RESET} %s\n" "$1"
}

log_warn() {
    printf "${BOLD}${YELLOW}[WARN]${RESET} %s\n" "$1"
}

log_error() {
    printf "${BOLD}${RED}[ERROR]${RESET} %s\n" "$1" >&2
}

# Check if script is run as root, if not, re-execute with sudo
ensure_root() {
    if [[ $EUID -ne 0 ]]; then
        log_warn "Root privileges required. Elevating..."
        exec sudo "$0" "$@"
    fi
}

# --- Main Execution ---

main() {
    # 1. Privilege Check
    ensure_root

    # 2. Ensure KDE wallet integration packages exist (no GNOME keyring).
    log_info "Ensuring KDE wallet packages are installed: ${INSTALL_PACKAGES[*]}..."
    if dnf -y install "${INSTALL_PACKAGES[@]}"; then
        log_info "KWallet packages installed/verified successfully."
    else
        log_error "Failed to install KDE wallet packages via dnf."
        exit 1
    fi

    # 3. Create Backup
    if [[ -f "$TARGET_FILE" ]]; then
        log_info "Backing up existing configuration to $BACKUP_FILE..."
        cp "$TARGET_FILE" "$BACKUP_FILE"
    else
        log_warn "$TARGET_FILE does not exist. Creating a new one."
    fi

    # 4. Non-destructive PAM cleanup (idempotent)
    # We remove pam_gnome_keyring hooks if previously added.
    log_info "Cleaning GNOME Keyring PAM entries (non-destructive): $TARGET_FILE"

    # Ensure target exists
    if [[ ! -f "$TARGET_FILE" ]]; then
        log_error "$TARGET_FILE does not exist; refusing to create a new PAM stack from scratch."
        log_error "Restore the default Fedora file and re-run."
        exit 1
    fi

    local tmp_file
    tmp_file="$(mktemp)"

    # Drop any pam_gnome_keyring lines.
    awk '!/pam_gnome_keyring\.so/' "$TARGET_FILE" > "$tmp_file"

    # Replace atomically
    cp "$tmp_file" "$TARGET_FILE"
    rm -f "$tmp_file"

    log_info "PAM configuration cleaned successfully (non-destructive)."

    # 5. Remove GNOME Keyring packages if present.
    log_info "Removing GNOME Keyring packages if installed: ${REMOVE_PACKAGES[*]}..."
    if dnf -y remove "${REMOVE_PACKAGES[@]}"; then
        log_info "GNOME Keyring removal processed."
    else
        log_warn "dnf remove returned a non-zero status; continuing (packages may already be absent)."
    fi

    printf "${BOLD}Success!${RESET} GNOME Keyring removed/disabled; KDE KWallet packages ensured.\n"
}

main "$@"
