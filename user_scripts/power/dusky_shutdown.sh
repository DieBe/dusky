#!/usr/bin/env bash

# Strict mode for robust error handling
set -euo pipefail

# 1. State Management Clean-up
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/omarchy"
if [[ -d "$STATE_DIR" ]]; then
    shopt -s nullglob
    # -f ensures 0 exit code if missing, || : protects against permission errors
    rm -f "$STATE_DIR"/re*-required || :
    shopt -u nullglob
fi

# 2. Reset Workspace (Visually cleaner for next boot, non-fatal)
hyprctl dispatch workspace 1 >/dev/null 2>&1 || :

# 3. Smart Teardown Logic
if [[ -n "${UWSM_ENV_FILE:-}" ]] || systemctl --user is-active --quiet "wayland-wm@*.service" 2>/dev/null; then

    # --- UWSM MANAGED TEARDOWN ---
    # Schedule the systemd poweroff detached from the current user session
    systemd-run --user --timer-property=OnActiveSec=1 -- systemctl poweroff --no-wall >/dev/null 2>&1

    # Cleanly collapse the UWSM session targets (graphical-session.target)
    exec uwsm stop

else

    # --- STANDALONE HYPRLAND TEARDOWN ---
    
    # Map the current process ancestry to prevent self-termination.
    # Reads /proc directly in pure Bash for optimal performance.
    declare -A skip_pids=()
    curr_pid=$$
    while [[ -r "/proc/$curr_pid/status" ]]; do
        skip_pids["$curr_pid"]=1
        ppid=""
        while IFS=$': \t' read -r key value _; do
            if [[ "$key" == "PPid" ]]; then
                ppid="$value"
                break
            fi
        done < "/proc/$curr_pid/status"
        
        # Break if PPID is invalid, or if we reach init (PID 1)
        [[ "$ppid" =~ ^[0-9]+$ ]] && (( ppid > 1 )) || break
        curr_pid="$ppid"
    done

    batch_cmds=""
    
    # Safely capture JSON, avoiding process substitution error masking
    if clients_json=$(hyprctl clients -j 2>/dev/null); then
        if client_rows=$(jq -r '.[] | "\(.pid)\t\(.address)"' <<<"$clients_json" 2>/dev/null); then
            if [[ -n "$client_rows" ]]; then
                while IFS=$'\t' read -r c_pid addr; do
                    # Skip if the window PID is in our script's ancestry tree
                    [[ -n "${skip_pids["$c_pid"]:-}" ]] && continue
                    
                    batch_cmds+="dispatch closewindow address:${addr}; "
                done <<<"$client_rows"
            fi
        fi
    fi

    # Best-effort window closure; script must proceed if IPC fails
    if [[ -n "$batch_cmds" ]]; then
        hyprctl --batch "$batch_cmds" >/dev/null 2>&1 || :
        sleep 1
    fi

    # Execute replaces the bash shell with systemd's poweroff routine
    exec systemctl poweroff --no-wall

fi
