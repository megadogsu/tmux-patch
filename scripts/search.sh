#!/usr/bin/env bash
# Meta-aware URL/pattern search for tmux copy-mode.
# Replaces copycat's C-u with tmux's native regex search (no Unicode offset bugs).
#
# Uses tmux's built-in search-backward which handles multi-byte characters
# correctly. After the first match, use n/N to cycle through results.

set -euo pipefail

# Combined pattern: URLs + Meta asset references
PATTERN='https?://[[:alnum:]?=%/_.:,;~@!#$&()*+/-]+|git@[[:alnum:]._-]+:[[:alnum:]?=%/_.:,;~@!#$&()*+/-]+|[DTP][0-9]{5,}|ME[0-9]+|S[0-9]{4,}|SEV [0-9]+|N[0-9]{5,}'

# Enter copy mode if not already in it
tmux copy-mode

# Use tmux's built-in regex search (handles Unicode correctly)
# search-backward searches upward from cursor, wraps around
tmux send-keys -X search-backward "$PATTERN"
