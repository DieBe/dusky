#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# Script: deploy_dotfiles.sh
# Description: Bootstraps dotfiles using a bare git repository method.
# Safety: This MUST NOT destroy an existing working-tree clone (e.g. ~/dusky).
# -----------------------------------------------------------------------------

# strict mode: exit on error, undefined vars, or pipe failures
set -euo pipefail

# -----------------------------------------------------------------------------
# Constants & Configuration
# -----------------------------------------------------------------------------

# Default upstream (only used if we cannot detect a local fork/origin).
readonly DEFAULT_REPO_URL="https://github.com/dusklinux/dusky"

# Store the *bare* repo away from common working-tree paths.
# Override via env: DUSKY_DOTFILES_DIR.
readonly DEFAULT_DOTFILES_DIR="${HOME}/.local/share/dusky-bare"

readonly GIT_EXEC="/usr/bin/git"

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null || true)"
DETECTED_ORIGIN_URL=""
if [[ -n "${REPO_ROOT:-}" ]]; then
    DETECTED_ORIGIN_URL="$(git -C "$REPO_ROOT" remote get-url origin 2>/dev/null || true)"
fi

# Repo URL resolution order:
#  1) explicit env override
#  2) local repo's origin (fork)
#  3) default upstream
readonly REPO_URL="${DUSKY_REPO_URL:-${DETECTED_ORIGIN_URL:-$DEFAULT_REPO_URL}}"

# Bare repo directory resolution:
#  1) explicit env override
#  2) safe default under ~/.local/share
readonly DOTFILES_DIR="${DUSKY_DOTFILES_DIR:-$DEFAULT_DOTFILES_DIR}"

# ANSI Color Codes for modern, readable output
readonly C_RESET='\033[0m'
readonly C_INFO='\033[1;34m'    # Bold Blue
readonly C_SUCCESS='\033[1;32m' # Bold Green
readonly C_ERROR='\033[1;31m'   # Bold Red
readonly C_WARN='\033[1;33m'    # Bold Yellow

# -----------------------------------------------------------------------------
# Helpers
# -----------------------------------------------------------------------------
log_info() {
    printf "${C_INFO}[INFO]${C_RESET} %s\n" "$1"
}

log_success() {
    printf "${C_SUCCESS}[OK]${C_RESET} %s\n" "$1"
}

log_warn() {
    printf "${C_WARN}[WARN]${C_RESET} %s\n" "$1"
}

log_error() {
    printf "${C_ERROR}[ERROR]${C_RESET} %s\n" "$1" >&2
}

# Cleanup function to be trapped on exit
cleanup() {
    local exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
        log_error "Script failed with exit code $exit_code."
    fi
}
trap cleanup EXIT

# -----------------------------------------------------------------------------
# Main Execution
# -----------------------------------------------------------------------------
main() {
    local force_mode=0

    # Parse arguments
    for arg in "$@"; do
        if [[ "$arg" == "--force" ]] || [[ "$arg" == "-f" ]]; then
            force_mode=1
            break
        fi
    done

    # 1. Pre-flight Checks
    if ! command -v git &> /dev/null; then
        log_error "Git is not installed. Please install it first (Fedora: 'sudo dnf install git')."
        exit 1
    fi

    # Safety: never delete an existing non-bare working tree.
    # This commonly happens when the user has this repo checked out at ~/dusky.
    if [[ -d "$DOTFILES_DIR" ]]; then
        if [[ -d "${DOTFILES_DIR}/.git" || -f "${DOTFILES_DIR}/.git" ]]; then
            log_error "Refusing to use DOTFILES_DIR as a bare repository because it looks like a working tree: $DOTFILES_DIR"
            log_error "Set DUSKY_DOTFILES_DIR to a separate location (e.g. '$DEFAULT_DOTFILES_DIR') and re-run."
            exit 1
        fi

        # Some users historically used ~/dusky as the bare repo dir. If it's not bare, abort.
        if [[ ! -f "${DOTFILES_DIR}/HEAD" ]]; then
            log_error "Refusing to delete $DOTFILES_DIR because it is not a bare repository (missing HEAD)."
            log_error "If this is a working copy, do not run this script against it."
            exit 1
        fi
    fi

    # --- SAFETY INTERLOCK START ---
    if [[ $force_mode -eq 0 ]]; then
        printf "\n"
        printf "${C_WARN}!!! CRITICAL WARNING !!!${C_RESET}\n"
        printf "${C_WARN}This script will FORCE OVERWRITE existing configuration files in %s.${C_RESET}\n" "$HOME"
        printf "${C_WARN}All custom changes will be lost permanently.${C_RESET}\n"
        printf "${C_WARN}NOTE: 'Orchestra' must be rerun after this process completes to finalize setup.${C_RESET}\n"
        printf "\n"
        
        read -r -p "Are you sure you want to proceed? [y/N] " response
        if [[ ! "$response" =~ ^[yY]([eE][sS])?$ ]]; then
            log_info "Operation aborted by user."
            exit 0
        fi
        printf "\n"
    else
        log_warn "Running in autonomous mode (--force). Bypassing safety prompts."
    fi
    # --- SAFETY INTERLOCK END ---

    log_info "Starting dotfiles bootstrap for user: $USER"
    log_info "Repo URL: $REPO_URL"
    log_info "Bare repo dir: $DOTFILES_DIR"

    # Clean up existing directory to ensure a fresh clone
    rm -rf "$DOTFILES_DIR"

    # 2. Clone the Bare Repository
    log_info "Cloning bare repository..."
    if "$GIT_EXEC" clone --bare --depth 1 "$REPO_URL" "$DOTFILES_DIR"; then
        log_success "Repository cloned successfully."
    else
        log_error "Failed to clone repository."
        exit 1
    fi

    # -------------------------------------------------------------------------
    # ITERATIVE BACKUP LOGIC FOR edit_here
    # -------------------------------------------------------------------------
    local edit_target="${HOME}/.config/hypr/edit_here"
    
    if [[ -d "$edit_target" ]]; then
        local counter=1
        local backup_path="${edit_target}.${counter}.bak"

        # Increment counter until an available backup path is found
        while [[ -e "$backup_path" ]]; do
            ((counter++))
            backup_path="${edit_target}.${counter}.bak"
        done

        log_info "Found existing ${edit_target}. Moving to iterative backup..."
        
        # Using mv to rename the directory, achieving a backup and removal in one atomic step
        if mv "$edit_target" "$backup_path"; then
            log_success "Successfully moved and backed up to ${backup_path}"
        else
            log_error "Failed to move/backup ${edit_target}. Proceeding anyway."
        fi
    fi
    # -------------------------------------------------------------------------

    # 3. Checkout Files
    log_info "Checking out configuration files to $HOME..."
    log_info "NOTE: This will overwrite existing files (forced checkout)."

    if "$GIT_EXEC" --git-dir="$DOTFILES_DIR/" --work-tree="$HOME" checkout -f; then
        log_success "Dotfiles checked out successfully."
    else
        log_error "Checkout failed. You may have conflicting files that git cannot overwrite despite -f."
        exit 1
    fi

    # 4. Completion
    log_success "Setup complete. Your Hyprland/UWSM environment is ready."
    log_info "REMINDER: Please rerun Orchestra now."
}

# Invoke main and pass all script arguments to it
main "$@"
