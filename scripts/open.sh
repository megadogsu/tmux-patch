#!/usr/bin/env bash
# Meta-aware URL opener for tmux copy-mode.
# Receives selected text via stdin, detects Meta patterns, and opens in browser.
#
# Supported patterns:
#   D12345678  → internalfb.com diff
#   T12345678  → internalfb.com task
#   S12345     → internalfb.com SEV
#   P12345     → internalfb.com paste
#   ME12345    → internalfb.com metric360
#   N12345     → internalfb.com bento notebook
#   URLs       → open directly
#   File paths → open with $EDITOR
#   Other      → Google search

set -euo pipefail

# Read selected text from stdin, trim whitespace
text=$(cat | tr -d '\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

[[ -z "$text" ]] && exit 0

# Platform-specific opener
if [[ "$(uname)" == "Darwin" ]]; then
    OPENER="open"
elif command -v xdg-open &>/dev/null; then
    OPENER="xdg-open"
else
    exit 1
fi

open_url() {
    nohup "$OPENER" "$1" >/dev/null 2>&1 &
}

# --- Meta patterns ---

# Diff: D followed by digits (at least 5)
if [[ "$text" =~ (D[0-9]{5,}) ]]; then
    open_url "https://www.internalfb.com/diff/${BASH_REMATCH[1]}"
    exit 0
fi

# Task: T followed by digits (at least 5)
if [[ "$text" =~ (T[0-9]{5,}) ]]; then
    open_url "https://www.internalfb.com/${BASH_REMATCH[1]}"
    exit 0
fi

# SEV: S followed by digits, or "SEV 12345"
if [[ "$text" =~ SEV[[:space:]]*([0-9]+) ]] || [[ "$text" =~ ^S([0-9]{4,})$ ]]; then
    open_url "https://www.internalfb.com/sevmanager/view/${BASH_REMATCH[1]}"
    exit 0
fi

# Paste: P followed by digits (at least 5)
if [[ "$text" =~ (P[0-9]{5,}) ]]; then
    open_url "https://www.internalfb.com/phabricator/paste/view/${BASH_REMATCH[1]}"
    exit 0
fi

# Metric360: ME followed by digits
if [[ "$text" =~ (ME[0-9]+) ]]; then
    open_url "https://www.internalfb.com/intern/metric360/metric/?metric_id=${BASH_REMATCH[1]}"
    exit 0
fi

# Bento Notebook: N followed by digits (at least 5)
if [[ "$text" =~ ^N([0-9]{5,})$ ]]; then
    open_url "https://www.internalfb.com/intern/anp/view/?id=${BASH_REMATCH[1]}"
    exit 0
fi

# --- URLs ---

# Already a full URL
if [[ "$text" =~ ^https?:// ]]; then
    open_url "$text"
    exit 0
fi

# Bare internalfb.com URL (no scheme)
if [[ "$text" =~ ^(www\.)?internalfb\.com ]]; then
    open_url "https://$text"
    exit 0
fi

# Other bare URLs (domain.tld/path pattern)
if [[ "$text" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]*\.)+[a-zA-Z]{2,}(/|$) ]]; then
    open_url "https://$text"
    exit 0
fi

# --- File paths ---

# Get the pane's current directory from tmux (if available)
pane_dir=$(tmux display-message -p '#{pane_current_path}' 2>/dev/null || echo "")

# Resolve relative paths
if [[ "$text" == /* ]]; then
    filepath="$text"
elif [[ -n "$pane_dir" ]]; then
    filepath="$pane_dir/$text"
else
    filepath="$text"
fi

if [[ -e "$filepath" ]]; then
    open_url "$filepath"
    exit 0
fi

# --- Fallback: Google search ---
encoded=$(printf '%s' "$text" | sed 's/ /+/g')
open_url "https://www.google.com/search?q=$encoded"
