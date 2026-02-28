#!/usr/bin/env bash
# Restore hook for tmux-resurrect-patch.
# Called via @resurrect-hook-post-restore-all AFTER resurrect recreates panes.
#
# - Claude (local): resumes via `claude --resume <id>`
# - SSH + Claude: sends `claude --resume` after a brief SSH connect wait
# - Vim: handled by tmux-resurrect natively

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$CURRENT_DIR/helpers.sh"

RESURRECT_DIR="$(get_resurrect_dir)"
CLAUDE_SESSIONS_FILE="$RESURRECT_DIR/claude_sessions.txt"
SSH_SESSIONS_FILE="$RESURRECT_DIR/ssh_sessions.txt"

main() {
    local count=0

    # Brief init wait
    sleep 0.5

    # --- Restore local Claude sessions ---
    if [[ -f "$CLAUDE_SESSIONS_FILE" && -s "$CLAUDE_SESSIONS_FILE" ]]; then
        while IFS=$'\t' read -r pane_target session_id launch_dir session_file; do
            [[ -z "$pane_target" || "$pane_target" =~ ^# ]] && continue
            tmux has-session -t "${pane_target%%:*}" 2>/dev/null || continue

            tmux send-keys -t "$pane_target" "cd ${launch_dir} && claude --resume ${session_id}" C-m
            count=$((count + 1))
        done < "$CLAUDE_SESSIONS_FILE"
    fi

    # --- Restore SSH + Claude sessions ---
    # Resurrect already sent the `ssh <target>` command to recreated panes.
    # We wait briefly for SSH to connect, then send claude --resume.
    if [[ -f "$SSH_SESSIONS_FILE" && -s "$SSH_SESSIONS_FILE" ]]; then
        # Single wait for all SSH connections
        sleep 2

        while IFS=$'\t' read -r pane_target ssh_target remote_session_id remote_dir; do
            [[ -z "$pane_target" || "$pane_target" =~ ^# ]] && continue
            [[ -z "$remote_session_id" ]] && continue
            tmux has-session -t "${pane_target%%:*}" 2>/dev/null || continue

            local cmd="claude --resume ${remote_session_id}"
            [[ "$remote_dir" != "~" && -n "$remote_dir" ]] && cmd="cd ${remote_dir} && ${cmd}"
            tmux send-keys -t "$pane_target" "$cmd" C-m
            count=$((count + 1))
        done < "$SSH_SESSIONS_FILE"
    fi

    [[ $count -gt 0 ]] && display_message "Restored $count Claude session(s)"
}

main
