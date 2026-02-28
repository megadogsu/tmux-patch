#!/usr/bin/env bash
# install.sh — Deploy tmux-patch to ~/.tmux/plugins/tmux-patch
#
# Copies plugin files from this canonical source into the TPM plugins
# directory, stripping the .git folder so the runtime copy is clean.

set -euo pipefail

SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEST_DIR="${HOME}/.tmux/plugins/tmux-patch"

echo "Installing tmux-patch..."
echo "  Source:      $SRC_DIR"
echo "  Destination: $DEST_DIR"

# Remove existing runtime copy (may have stale .git or old files)
if [[ -d "$DEST_DIR" ]]; then
    echo "  Removing old installation..."
    rm -rf "$DEST_DIR"
fi

# Copy everything except .git
mkdir -p "$DEST_DIR"
rsync -a --exclude=".git" --exclude="install.sh" --exclude="uninstall.sh" \
    "$SRC_DIR/" "$DEST_DIR/"

echo "  Installed. Reload tmux config to activate:"
echo "    tmux source-file ~/.tmux.conf"
