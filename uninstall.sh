#!/usr/bin/env bash
# uninstall.sh — Remove tmux-patch from ~/.tmux/plugins/tmux-patch
#
# Removes the runtime copy. The canonical source in ~/Workspace/projects
# is untouched.

set -euo pipefail

DEST_DIR="${HOME}/.tmux/plugins/tmux-patch"

if [[ -d "$DEST_DIR" ]]; then
    echo "Removing tmux-patch from $DEST_DIR..."
    rm -rf "$DEST_DIR"
    echo "  Removed. Reload tmux config:"
    echo "    tmux source-file ~/.tmux.conf"
else
    echo "tmux-patch is not installed at $DEST_DIR"
fi
