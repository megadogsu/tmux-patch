#!/usr/bin/env bash
# Meta-aware URL opener for tmux copy-mode.
#
# Two modes:
#   1. With selection (stdin has content): opens the selected text
#   2. Without selection (from search highlight): reads the line under
#      the cursor and extracts the Meta pattern or URL at cursor position
#
# Supported patterns:
#   D12345678  → internalfb.com diff
#   T12345678  → internalfb.com task
#   S12345     → internalfb.com SEV
#   P12345     → internalfb.com paste
#   ME12345    → internalfb.com metric360
#   N12345     → internalfb.com bento notebook
#   URLs       → open directly
#   File paths → open in Finder/file manager
#   Other      → Google search

set -euo pipefail

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

# Try to detect and open a Meta pattern or URL from arbitrary text.
# Extracts the first matching pattern from the input.
detect_and_open() {
    local text="$1"

    # Diff: D followed by digits (at least 5)
    if [[ "$text" =~ (D[0-9]{5,}) ]]; then
        open_url "https://www.internalfb.com/diff/${BASH_REMATCH[1]}"
        return 0
    fi

    # Task: T followed by digits (at least 5)
    if [[ "$text" =~ (T[0-9]{5,}) ]]; then
        open_url "https://www.internalfb.com/${BASH_REMATCH[1]}"
        return 0
    fi

    # SEV: "SEV 12345" or S followed by digits (at least 4)
    if [[ "$text" =~ SEV[[:space:]]*([0-9]+) ]] || [[ "$text" =~ (^|[^A-Za-z])S([0-9]{4,})($|[^0-9]) ]]; then
        local num="${BASH_REMATCH[1]:-${BASH_REMATCH[2]}}"
        open_url "https://www.internalfb.com/sevmanager/view/$num"
        return 0
    fi

    # Paste: P followed by digits (at least 5)
    if [[ "$text" =~ (P[0-9]{5,}) ]]; then
        open_url "https://www.internalfb.com/phabricator/paste/view/${BASH_REMATCH[1]}"
        return 0
    fi

    # Metric360: ME followed by digits
    if [[ "$text" =~ (ME[0-9]+) ]]; then
        open_url "https://www.internalfb.com/intern/metric360/metric/?metric_id=${BASH_REMATCH[1]}"
        return 0
    fi

    # Bento Notebook: N followed by digits (at least 5), not part of a word
    if [[ "$text" =~ (^|[^A-Za-z])N([0-9]{5,})($|[^0-9]) ]]; then
        open_url "https://www.internalfb.com/intern/anp/view/?id=${BASH_REMATCH[2]}"
        return 0
    fi

    # Full URL
    if [[ "$text" =~ (https?://[[:alnum:]?=%/_.:,\;~@!#\$\&\(\)\*+/-]+) ]]; then
        open_url "${BASH_REMATCH[1]}"
        return 0
    fi

    # Bare internalfb.com URL
    if [[ "$text" =~ ((www\.)?internalfb\.com[[:alnum:]?=%/_.:,\;~@!#\$\&\(\)\*+/-]*) ]]; then
        open_url "https://${BASH_REMATCH[1]}"
        return 0
    fi

    return 1
}

# --- Read input ---

# Read selected text from stdin (copy-pipe-and-cancel pipes the selection)
text=$(cat | tr -d '\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

# If stdin was empty (no selection), try to read the line under cursor
if [[ -z "$text" ]]; then
    # In copy mode, capture the current cursor line
    cursor_y=$(tmux display-message -p '#{copy_cursor_y}' 2>/dev/null || echo "")
    if [[ -n "$cursor_y" ]]; then
        text=$(tmux capture-pane -p -S "$cursor_y" -E "$cursor_y" 2>/dev/null | head -1)
        text=$(echo "$text" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    fi
fi

[[ -z "$text" ]] && exit 0

# --- Try Meta patterns and URLs first ---
if detect_and_open "$text"; then
    exit 0
fi

# --- File paths ---
pane_dir=$(tmux display-message -p '#{pane_current_path}' 2>/dev/null || echo "")

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
