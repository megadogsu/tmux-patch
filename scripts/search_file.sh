#!/usr/bin/env bash
# File path search for tmux copy-mode.
# Uses tmux native regex search (ERE) — no flashing, no double-matches.
#
# Matches:
#   1. Paths with file extension: output.txt, build/output.txt, file.tar.gz
#   2. Anchored paths with depth: /a/b, ./a, ../a, ~/a
#   3. Deep relative paths (3+ segments): src/avatar/cli

# ERE pattern (tmux search-backward uses ERE, not BRE)
PATTERN="[[:alnum:]~_./-]*[[:alnum:]_-]+[.][[:alpha:]][[:alnum:]]*([.][[:alpha:]][[:alnum:]]*)*|[~.]?[.]?/[[:alnum:]_.#$%+=@-]+(/[[:alnum:]_.#$%+=@-]+)+|[[:alnum:]_-]+(/[[:alnum:]_.#$%+=@-]+){2,}"

tmux copy-mode
tmux send-keys -X search-backward "$PATTERN" 2>/dev/null || \
    tmux display-message "No file paths found"
