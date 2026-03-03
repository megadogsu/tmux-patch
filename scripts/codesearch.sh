#!/usr/bin/env bash
# Meta code search for tmux copy-mode.
#
# Opens the selected text (or text under cursor) in Meta's code search.
# If the text looks like a file path, searches for that path.
# Otherwise, searches as a general query.
#
# Bound to 'c' in copy-mode-vi.

set -euo pipefail

# Platform-specific opener
if [[ "$(uname)" == "Darwin" ]]; then
    OPENER="open"
elif command -v xdg-open &>/dev/null; then
    OPENER="xdg-open"
else
    exit 1
fi

# --- Read input ---

text=$(cat | tr -d '\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

# If stdin was empty, try the cursor line
if [[ -z "$text" ]]; then
    cursor_y=$(tmux display-message -p '#{copy_cursor_y}' 2>/dev/null || echo "")
    if [[ -n "$cursor_y" ]]; then
        text=$(tmux capture-pane -p -S "$cursor_y" -E "$cursor_y" 2>/dev/null | head -1)
        text=$(echo "$text" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    fi
fi

[[ -z "$text" ]] && exit 0

# URL-encode the query
encoded=$(python3 -c "import urllib.parse; print(urllib.parse.quote('$text'))" 2>/dev/null || \
          printf '%s' "$text" | sed 's/ /%20/g; s/\//%2F/g')

nohup "$OPENER" "https://www.internalfb.com/code/search?q=${encoded}" >/dev/null 2>&1 &
