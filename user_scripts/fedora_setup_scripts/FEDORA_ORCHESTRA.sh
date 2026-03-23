#!/usr/bin/env bash
set -euo pipefail

SELF_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

# Prefer the orchestrator that lives next to this file (repo-relative),
# but keep backward compatibility with historical $HOME/user_scripts layout.
for candidate in \
	"${SELF_DIR}/../arch_setup_scripts/ORCHESTRA.sh" \
	"${HOME}/user_scripts/arch_setup_scripts/ORCHESTRA.sh"; do
	if [[ -f "$candidate" ]]; then
		exec "$candidate" "$@"
	fi
done

printf 'Error: Could not locate ORCHESTRA.sh. Looked in:\n  - %s\n  - %s\n' \
	"${SELF_DIR}/../arch_setup_scripts/ORCHESTRA.sh" \
	"${HOME}/user_scripts/arch_setup_scripts/ORCHESTRA.sh" >&2
exit 1
