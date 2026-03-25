#!/usr/bin/env bash
set -euo pipefail

# collect_prehypr_errors.sh
# Collects Hyprland/Waybar/Matugen-related errors into a timestamped folder.
# Intended usage: run from TTY BEFORE logging into Hyprland, keep it running,
# then Ctrl+C after reproducing the issue.

print_help() {
  cat <<'EOF'
Usage:
  collect_prehypr_errors.sh [--duration SEC] [--filter REGEX] [--out-root DIR] [--no-follow]

What it does:
  - Creates a timestamped diagnostics folder
  - Captures environment + versions + systemd user status
  - Streams `journalctl --user -f` (filtered) while you start Hyprland
  - On exit (Ctrl+C), saves journal snapshots and a deduped error summary

Options:
  --duration SEC   Stop after SEC seconds (default: run until Ctrl+C)
  --filter REGEX   Regex to filter journal lines (default: common Hyprland stack)
  --out-root DIR   Output root dir (default: $XDG_STATE_HOME/dusky/diagnostics)
  --no-follow      Do not follow the journal (only snapshot)
  -h, --help       Show this help

Tip:
  After it finishes, send me:
    - errors_summary.txt
    - journal_follow_filtered.log (or journal_since_start_filtered.log)
EOF
}

DURATION_SEC=""
NO_FOLLOW=0

DEFAULT_FILTER='hypr|uwsm|waybar|matugen|swww|swaync|swayosd|xdg-desktop-portal|pipewire|wireplumber|portal'
FILTER="$DEFAULT_FILTER"

OUT_ROOT_DEFAULT="${XDG_STATE_HOME:-$HOME/.local/state}/dusky/diagnostics"
OUT_ROOT="$OUT_ROOT_DEFAULT"

while (( $# > 0 )); do
  case "$1" in
    --duration)
      DURATION_SEC="${2:-}"; shift 2 ;;
    --filter)
      FILTER="${2:-}"; shift 2 ;;
    --out-root)
      OUT_ROOT="${2:-}"; shift 2 ;;
    --no-follow)
      NO_FOLLOW=1; shift ;;
    -h|--help)
      print_help; exit 0 ;;
    *)
      echo "Unknown arg: $1" >&2
      print_help
      exit 2
      ;;
  esac
done

log() { printf '[%s] %s\n' "$(date -Is 2>/dev/null || date)" "$*" >&2; }
have() { command -v "$1" >/dev/null 2>&1; }

filter_stream() {
  if [[ -z "${FILTER:-}" ]]; then
    cat
    return 0
  fi
  if have rg; then
    rg -i --line-buffered "$FILTER"
  else
    # Busybox/posix fallback
    grep -Eai "$FILTER" || true
  fi
}

stamp="$(date -Is | tr ':+' '__' | tr -d '\n')"
OUT_DIR="${OUT_ROOT%/}/hypr-prelaunch-${stamp}"
mkdir -p -- "$OUT_DIR"

START_TS="$(date -Is 2>/dev/null || date)"
log "Writing diagnostics to: $OUT_DIR"
log "Journal filter regex: ${FILTER:-<none>}"
log "Start timestamp: $START_TS"

# --- Static snapshots (best-effort) ---
{
  echo "START_TS=$START_TS"
  echo "USER=$USER"
  echo "UID=$(id -u)"
  echo "SHELL=${SHELL:-}"
  echo "XDG_SESSION_TYPE=${XDG_SESSION_TYPE:-}"
  echo "XDG_CURRENT_DESKTOP=${XDG_CURRENT_DESKTOP:-}"
  echo "WAYLAND_DISPLAY=${WAYLAND_DISPLAY:-}"
  echo "DISPLAY=${DISPLAY:-}"
  echo "XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR:-}"
  echo "HYPRLAND_INSTANCE_SIGNATURE=${HYPRLAND_INSTANCE_SIGNATURE:-}"
} >"$OUT_DIR/env.txt" 2>/dev/null || true

{
  echo "# uname"
  uname -a 2>/dev/null || true
  echo
  for bin in Hyprland hyprctl waybar matugen uwsm-app swww swww-daemon swaync; do
    if command -v "$bin" >/dev/null 2>&1; then
      echo "# $bin"
      "$bin" --version 2>&1 || "$bin" -V 2>&1 || true
      echo
    fi
  done
} >"$OUT_DIR/versions.txt" 2>&1 || true

if have systemctl; then
  systemctl --user --no-pager --failed >"$OUT_DIR/systemd_user_failed.txt" 2>&1 || true
  systemctl --user --no-pager status >"$OUT_DIR/systemd_user_status.txt" 2>&1 || true
fi

{
  echo "# Key paths (presence + basic listing)"
  paths=(
    "${HOME}/.config/hypr"
    "${HOME}/.config/waybar"
    "${HOME}/.config/matugen/config.toml"
    "${HOME}/.config/matugen/generated"
    "${HOME}/.config/dusky/settings/dusky_theme/state.conf"
    "${HOME}/.config/uwsm/env"
    "${HOME}/.config/uwsm/env-hyprland"
    "${HOME}/Pictures/wallpapers"
    "${HOME}/Pictures/wallpapers/active_theme"
  )

  for p in "${paths[@]}"; do
    echo
    echo "## $p"
    if [[ -e "$p" ]]; then
      ls -la "$p" 2>&1 || true
      if [[ -d "$p" ]]; then
        # Keep it small-ish: only top-level, no recursion.
        find "$p" -maxdepth 1 -type f -printf '%f\n' 2>/dev/null | LC_ALL=C sort | head -n 200 || true
      fi
    else
      echo "MISSING"
    fi
  done
} >"$OUT_DIR/key_paths.txt" 2>&1 || true

if have journalctl; then
  journalctl --user -b -p warning..alert -o short-precise --no-pager >"$OUT_DIR/journal_user_warnings_full.log" 2>&1 || true
  journalctl --user -b -o short-precise --no-pager | filter_stream >"$OUT_DIR/journal_user_filtered_full.log" 2>&1 || true
else
  log "WARNING: journalctl not found; journal capture will be empty."
fi

# Try a matugen run without needing Wayland (best-effort, may be useful).
# We avoid theme_ctl because it depends on swww/swaync and a running session.
if have matugen; then
  {
    echo "# matugen help"
    matugen --help 2>&1 || true
    echo
    echo "# matugen config presence"
    ls -la "${HOME}/.config/matugen" 2>&1 || true
    echo
  } >"$OUT_DIR/matugen_precheck.txt" 2>&1 || true
fi

# --- Follow journal while you reproduce ---
FOLLOW_LOG="$OUT_DIR/journal_follow_filtered.log"
SINCE_LOG="$OUT_DIR/journal_since_start_filtered.log"

finalize() {
  local exit_code=$?
  log "Finalizing (exit code: $exit_code) ..."

  if have journalctl; then
    journalctl --user -b --since "$START_TS" -o short-precise --no-pager | filter_stream >"$SINCE_LOG" 2>&1 || true
    journalctl --user -b --since "$START_TS" -p warning..alert -o short-precise --no-pager >"$OUT_DIR/journal_since_start_warnings.log" 2>&1 || true
  fi

  # Produce a deduped error-ish summary from the filtered logs.
  {
    echo "# Error-like lines (deduped)"
    echo "# Source: journal_follow_filtered.log + journal_since_start_filtered.log"
    echo

    (cat "$FOLLOW_LOG" "$SINCE_LOG" 2>/dev/null || true) \
      | (have rg && rg -i 'error|failed|fatal|panic|warn|warning|critical|traceback|exception' || grep -Eai 'error|failed|fatal|panic|warn|warning|critical|traceback|exception' || true) \
      | sed -E 's/[[:space:]]+/ /g' \
      | sed -E 's/\x1B\[[0-9;]*[mK]//g' \
      | sort \
      | uniq -c \
      | sort -nr
  } >"$OUT_DIR/errors_summary.txt" 2>&1 || true

  # If user services exist, dump their journal slices (often higher-signal than global filters).
  if have journalctl && have systemctl; then
    units=(
      waybar.service
      swww.service
      swaync.service
      hypridle.service
      hyprpaper.service
      xdg-desktop-portal.service
      xdg-desktop-portal-hyprland.service
      uwsm.service
    )

    for u in "${units[@]}"; do
      if systemctl --user cat "$u" >/dev/null 2>&1; then
        journalctl --user -b -u "$u" -o short-precise --no-pager >"$OUT_DIR/journal_unit_${u}.log" 2>&1 || true
      fi
    done
  fi

  log "Done. Key files:" 
  log "  $OUT_DIR/errors_summary.txt"
  log "  $FOLLOW_LOG"
  log "  $SINCE_LOG"
}

trap finalize EXIT

if (( NO_FOLLOW )); then
  log "--no-follow set; skipping live journal follow."
  exit 0
fi

if ! have journalctl; then
  log "ERROR: journalctl is required for follow mode."
  exit 1
fi

log "Now reproduce the problem: log into Hyprland, wait until Waybar should appear." 
log "Press Ctrl+C here when you’re done to finalize the bundle." 

if [[ -n "${DURATION_SEC:-}" ]]; then
  if ! [[ "$DURATION_SEC" =~ ^[0-9]+$ ]]; then
    log "ERROR: --duration must be an integer number of seconds."
    exit 2
  fi
  # `timeout` is optional; if missing, we just sleep+kill ourselves.
  if have timeout; then
    timeout --preserve-status "${DURATION_SEC}s" \
      journalctl --user -b -o short-precise -f --since "$START_TS" \
      | filter_stream \
      | tee -a "$FOLLOW_LOG"
  else
    ( journalctl --user -b -o short-precise -f --since "$START_TS" \
        | filter_stream \
        | tee -a "$FOLLOW_LOG" ) &
    follower_pid=$!
    sleep "$DURATION_SEC" || true
    kill -INT "$follower_pid" 2>/dev/null || true
    wait "$follower_pid" 2>/dev/null || true
  fi
else
  journalctl --user -b -o short-precise -f --since "$START_TS" \
    | filter_stream \
    | tee -a "$FOLLOW_LOG"
fi
