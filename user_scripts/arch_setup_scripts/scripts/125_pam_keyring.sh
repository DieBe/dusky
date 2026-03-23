#!/usr/bin/env bash
# Installation of Gnome Keyring components
# ==============================================================================
# Script Name: setup_gnome_keyring.sh
# Description: Automates the installation of Gnome Keyring components and 
#              configures PAM for auto-unlocking on login.
#              Designed for Fedora (Hyprland/UWSM ecosystem).
# Target:      /etc/pam.d/login
# ==============================================================================

set -euo pipefail

# --- Configuration ---
TARGET_FILE="/etc/pam.d/login"
BACKUP_DIR="/etc/pam.d"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
BACKUP_FILE="${TARGET_FILE}.bak.${TIMESTAMP}"
PACKAGES=("gnome-keyring" "libsecret" "seahorse")

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

    # 2. Install Packages
    log_info "Installing necessary packages: ${PACKAGES[*]}..."
    if dnf -y install "${PACKAGES[@]}"; then
        log_info "Packages installed/verified successfully."
    else
        log_error "Failed to install packages via dnf."
        exit 1
    fi

    # 3. Create Backup
    if [[ -f "$TARGET_FILE" ]]; then
        log_info "Backing up existing configuration to $BACKUP_FILE..."
        cp "$TARGET_FILE" "$BACKUP_FILE"
    else
        log_warn "$TARGET_FILE does not exist. Creating a new one."
    fi

    # 4. Non-destructive PAM update (idempotent)
    # Fedora KDE systems rely on existing PAM stack; overwriting /etc/pam.d/login
    # is risky and can break logins. We only insert missing pam_gnome_keyring lines.
    log_info "Updating PAM configuration (non-destructive): $TARGET_FILE"

    # Ensure target exists
    if [[ ! -f "$TARGET_FILE" ]]; then
        log_error "$TARGET_FILE does not exist; refusing to create a new PAM stack from scratch."
        log_error "Restore the default Fedora file and re-run."
        exit 1
    fi

    local need_auth=0 need_session=0 need_password=0
    if ! grep -Eq '^[[:space:]]*auth[[:space:]]+.*pam_gnome_keyring\.so' "$TARGET_FILE"; then
        need_auth=1
    fi
    if ! grep -Eq '^[[:space:]]*session[[:space:]]+.*pam_gnome_keyring\.so' "$TARGET_FILE"; then
        need_session=1
    fi
    if ! grep -Eq '^[[:space:]]*password[[:space:]]+.*pam_gnome_keyring\.so' "$TARGET_FILE"; then
        need_password=1
    fi

    if (( need_auth == 0 && need_session == 0 && need_password == 0 )); then
        log_info "pam_gnome_keyring entries already present; nothing to do."
        printf "${BOLD}Success!${RESET} GNOME Keyring PAM entries already configured.\n"
        return 0
    fi

    local tmp_file
    tmp_file="$(mktemp)"

    awk \
        -v need_auth="$need_auth" \
        -v need_session="$need_session" \
        -v need_password="$need_password" \
        '
        BEGIN { done_auth=0; done_session=0; done_password=0 }
        {
            print $0

            if (need_auth == 1 && done_auth == 0 && $0 ~ /^[[:space:]]*auth[[:space:]]+include[[:space:]]+system-local-login/) {
                print "auth       optional      pam_gnome_keyring.so"
                done_auth=1
            }

            if (need_session == 1 && done_session == 0 && $0 ~ /^[[:space:]]*session[[:space:]]+include[[:space:]]+system-local-login/) {
                print "session    optional      pam_gnome_keyring.so auto_start"
                done_session=1
            }

            if (need_password == 1 && done_password == 0 && $0 ~ /^[[:space:]]*password[[:space:]]+include[[:space:]]+system-local-login/) {
                print "password   optional      pam_gnome_keyring.so"
                done_password=1
            }
        }
        END {
            if (need_auth == 1 && done_auth == 0) print "auth       optional      pam_gnome_keyring.so"
            if (need_session == 1 && done_session == 0) print "session    optional      pam_gnome_keyring.so auto_start"
            if (need_password == 1 && done_password == 0) print "password   optional      pam_gnome_keyring.so"
        }
        ' "$TARGET_FILE" > "$tmp_file"

    # Replace atomically
    cp "$tmp_file" "$TARGET_FILE"
    rm -f "$tmp_file"

    log_info "PAM configuration updated successfully (non-destructive)."
    printf "${BOLD}Success!${RESET} GNOME Keyring PAM entries have been added.\n"
    printf "A reboot or re-login is required for the PAM changes to take effect.\n"
}

main "$@"
