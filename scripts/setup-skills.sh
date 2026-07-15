#!/usr/bin/env bash
# Install/update the device-automation skills repos the MCP servers read.
set -euo pipefail

install_or_update() {
  local repo="$1" dest="$2"
  if [ -d "$dest/.git" ]; then
    echo "Updating $dest…"
    git -C "$dest" pull --ff-only
  else
    echo "Cloning $repo → $dest…"
    mkdir -p "$(dirname "$dest")"
    git clone --depth 1 "$repo" "$dest"
  fi
}

# iOS: mirroir app-knowledge / obstacle patterns
install_or_update "https://github.com/jfarcand/mirroir-skills" "$HOME/.mirroir-mcp/skills"

# Android: no published androir skills repo yet — placeholder, not an error.
echo "androir: no skills repo published yet — skipping."

echo "Done."
