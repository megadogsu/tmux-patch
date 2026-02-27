#!/usr/bin/env bash
# Restore hook for tmux-resurrect-patch.
# Called via @resurrect-hook-post-restore-all (no arguments).
#
# - Claude: resumes sessions via `claude --resume <id>`
# - Vim: handled natively by tmux-resurrect via @resurrect-strategy-vim 'session'
#   (Session.vim was auto-created by our save hook)

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$CURRENT_DIR/helpers.sh"

RESURRECT_DIR="$(get_resurrect_dir)"
CLAUDE_SESSIONS_FILE="$RESURRECT_DIR/claude_sessions.txt"

main() {
    if [[ ! -f "$CLAUDE_SESSIONS_FILE" || ! -s "$CLAUDE_SESSIONS_FILE" ]]; then
        return 0
    fi

    local count=0

    # Give restored shells a moment to initialize
    sleep 1

    while IFS=$'\t' read -r pane_target session_id launch_dir session_file; do
        [[ -z "$pane_target" || "$pane_target" =~ ^# ]] && continue

        # Verify the tmux session still exists
        local session_name="${pane_target%%:*}"
        if ! tmux has-session -t "$session_name" 2>/dev/null; then
            continue
        fi

        # Verify the Claude session file exists on disk
        if [[ -n "$session_file" && ! -f "$session_file" ]]; then
            continue
        fi

        # cd to the directory where claude was originally launched, then resume
        tmux send-keys -t "$pane_target" "cd ${launch_dir} && claude --resume ${session_id}" C-m
        count=$((count + 1))

        # Brief pause between launches
        sleep 0.2
    done < "$CLAUDE_SESSIONS_FILE"

    if [[ $count -gt 0 ]]; then
        display_message "Restored $count Claude session(s)"
    fi
}

main
