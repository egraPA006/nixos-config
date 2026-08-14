#!/usr/bin/env bash
set -euo pipefail

destination="${1:-$HOME/nixos-config}"
github="${PINO_GITHUB_REPOSITORY:-https://github.com/egraPA006/nixos-config.git}"
mirror="${PINO_GIT_MIRROR:-https://git.egrapa.com/nixos-config.git}"
bundle="${PINO_GIT_BUNDLE:-}"

if [ -e "$destination" ]; then
  echo "Destination already exists: $destination" >&2
  exit 1
fi

for source in "$github" "$mirror"; do
  [ -n "$source" ] || continue
  echo "Trying $source..."
  if git clone "$source" "$destination"; then
    echo "Configuration cloned to $destination"
    exit 0
  fi
done

if [ -z "$bundle" ]; then
  bundle="$(find /run/media /mnt -type f -name 'nixos-config.bundle' -print -quit 2>/dev/null || true)"
fi

if [ -n "$bundle" ] && [ -f "$bundle" ]; then
  echo "Restoring from offline bundle $bundle..."
  git clone "$bundle" "$destination"
  git -C "$destination" remote set-url origin "$github"
  echo "Configuration restored to $destination"
  exit 0
fi

echo "Unable to obtain the NixOS configuration from GitHub, the public mirror, or an external bundle." >&2
echo "Set PINO_GIT_MIRROR or PINO_GIT_BUNDLE and retry." >&2
exit 1
