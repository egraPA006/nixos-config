#!/usr/bin/env bash
set -euo pipefail

destination="${1:-$HOME/nixos-config}"
repository="${PINO_GITHUB_REPOSITORY:-https://github.com/egraPA006/nixos-config.git}"
[ ! -e "$destination" ] || { echo "Destination exists: $destination" >&2; exit 1; }
git clone "$repository" "$destination"
