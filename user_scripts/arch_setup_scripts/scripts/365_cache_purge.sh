#!/usr/bin/env bash
# ==============================================================================
#  FEDORA CACHE PURGE & OPTIMIZER
# ==============================================================================

# --- 1. Safety & Environment ---
set -o errexit
set -o nounset
set -o pipefail

# --- 2. Visuals (with terminal detection) ---
if [[ -t 1 ]]; then
    readonly R=$'\e[31m'
    readonly G=$'\e[32m'
    readonly Y=$'\e[33m'
    readonly B=$'\e[34m'
    readonly RESET=$'\e[0m'
    readonly BOLD=$'\e[1m'
else
    readonly R=''
    readonly G=''
    readonly Y=''
    readonly B=''
    readonly RESET=''
    readonly BOLD=''
fi

log() { printf "%s::%s %s\n" "$B" "$RESET" "$1"; }

# --- 3. Dynamic Configuration ---
# DNF cache directory (respects /etc/dnf/dnf.conf cachedir if set)
_dnf_cache_dir=""
if [[ -r /etc/dnf/dnf.conf ]]; then
    _dnf_cache_dir="$(awk -F= '/^[[:space:]]*cachedir[[:space:]]*=/ {gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2); print $2; exit}' /etc/dnf/dnf.conf 2>/dev/null || true)"
fi
readonly DNF_CACHE="${_dnf_cache_dir:-/var/cache/dnf}"
unset _dnf_cache_dir

# --- 4. Cleanup Tracking ---
SUDO_KEEPALIVE_PID=""

cleanup() {
    if [[ -n "$SUDO_KEEPALIVE_PID" ]] && kill -0 "$SUDO_KEEPALIVE_PID" 2>/dev/null; then
        kill "$SUDO_KEEPALIVE_PID" 2>/dev/null || true
        wait "$SUDO_KEEPALIVE_PID" 2>/dev/null || true
    fi
}
trap cleanup EXIT

# --- 5. Helper Functions ---

get_dir_size_mb() {
    local target="$1"
    local size

    if [[ ! -d "$target" ]]; then
        echo "0"
        return
    fi

    # Use -r (readable) not -w (writable): du only needs read+execute access.
    # Use '--' to guard against paths starting with a dash.
    if [[ -r "$target" && -x "$target" ]]; then
        size=$(du -sm -- "$target" 2>/dev/null | cut -f1 || true)
    else
        size=$(sudo du -sm -- "$target" 2>/dev/null | cut -f1 || true)
    fi

    if [[ "$size" =~ ^[0-9]+$ ]]; then
        echo "$size"
    else
        echo "0"
    fi
}

# Sum sizes of multiple directories
get_dirs_size_mb() {
    local total=0
    local s
    local dir
    for dir in "$@"; do
        s=$(get_dir_size_mb "$dir")
        total=$((total + s))
    done
    echo "$total"
}

# --- 6. Main Execution ---

main() {
    printf "%sStarting Aggressive Cache Cleanup...%s\n" "$BOLD" "$RESET"

    # Pre-Flight: Validate sudo
    if ! sudo -v; then
        printf "%sError: Sudo authentication failed.%s\n" "$R" "$RESET"
        exit 1
    fi

    # Keep sudo alive in background; disable errexit so a transient
    # sudo -n failure doesn't silently kill the keepalive loop.
    (
        set +o errexit
        while true; do
            sudo -n true 2>/dev/null
            sleep 50
            kill -0 "$$" 2>/dev/null || exit 0
        done
    ) &
    SUDO_KEEPALIVE_PID=$!

    # --- Measure Initial Sizes ---
    log "Measuring current cache usage..."

    local dnf_start
    dnf_start=$(get_dir_size_mb "$DNF_CACHE")
    printf "   %sDNF Cache:%s      %s MB\n" "$BOLD" "$RESET" "$dnf_start"

    local total_start=$dnf_start

    # --- Clean Stuck Partial Downloads ---
    [[ -d "$DNF_CACHE" ]] && sudo find "$DNF_CACHE" -type f -name "*.part" -delete 2>/dev/null || true

    # --- Clean Caches ---
    log "Purging DNF cache (System)..."
    sudo dnf -y clean all >/dev/null 2>&1 || true
    printf "   %s✔ DNF cache cleared.%s\n" "$G" "$RESET"

    # --- Final Report ---
    log "Calculating reclaimed space..."

    local dnf_end
    dnf_end=$(get_dir_size_mb "$DNF_CACHE")

    local total_end=$dnf_end
    local saved=$((total_start - total_end))

    # Clamp to 0 if somehow negative (cache grew between measurements)
    if [[ $saved -lt 0 ]]; then
        saved=0
    fi

    echo ""
    printf "%s========================================%s\n" "$BOLD" "$RESET"
    printf "%s       DISK SPACE RECLAIMED REPORT      %s\n" "$BOLD" "$RESET"
    printf "%s========================================%s\n" "$BOLD" "$RESET"
    printf "%sInitial Usage:%s  %s MB\n" "$BOLD" "$RESET" "$total_start"
    printf "%sFinal Usage:%s    %s MB\n" "$BOLD" "$RESET" "$total_end"
    printf "%s----------------------------------------%s\n" "$BOLD" "$RESET"

    if [[ $saved -gt 0 ]]; then
        printf "%s%sTOTAL CLEARED:%s %s%s MB%s\n" "$G" "$BOLD" "$RESET" "$G" "$saved" "$RESET"
    else
        printf "%s%sTOTAL CLEARED:%s %s0 MB (Already Clean)%s\n" "$Y" "$BOLD" "$RESET" "$Y" "$RESET"
    fi
    printf "%s========================================%s\n" "$BOLD" "$RESET"
}

main
