#!/usr/bin/env bash
# Restore hook for tmux-resurrect-patch.
# Called via @resurrect-hook-post-restore-all (no arguments).
#
# - Claude (local): resumes sessions via `claude --resume <id>`
# - SSH + Claude: re-establishes SSH, then resumes Claude on remote
# - Vim: handled natively by tmux-resurrect via @resurrect-strategy-vim 'session'

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$CURRENT_DIR/helpers.sh"

RESURRECT_DIR="$(get_resurrect_dir)"
CLAUDE_SESSIONS_FILE="$RESURRECT_DIR/claude_sessions.txt"
SSH_SESSIONS_FILE="$RESURRECT_DIR/ssh_sessions.txt"

main() {
    local count=0

    # Give restored shells a moment to initialize
    sleep 1

    # --- Restore local Claude sessions ---
    if [[ -f "$CLAUDE_SESSIONS_FILE" && -s "$CLAUDE_SESSIONS_FILE" ]]; then
        while IFS=$'\t' read -r pane_target session_id launch_dir session_file; do
            [[ -z "$pane_target" || "$pane_target" =~ ^# ]] && continue

            local session_name="${pane_target%%:*}"
            if ! tmux has-session -t "$session_name" 2>/dev/null; then
                continue
            fi

            if [[ -n "$session_file" && ! -f "$session_file" ]]; then
                continue
            fi

            tmux send-keys -t "$pane_target" "cd ${launch_dir} && claude --resume ${session_id}" C-m
            count=$((count + 1))
            sleep 0.2
        done < "$CLAUDE_SESSIONS_FILE"
    fi

    # --- Restore SSH sessions (with optional Claude resume) ---
    local ssh_count=0
    if [[ -f "$SSH_SESSIONS_FILE" && -s "$SSH_SESSIONS_FILE" ]]; then
        while IFS=$'\t' read -r pane_target ssh_target remote_session_id remote_dir; do
            [[ -z "$pane_target" || "$pane_target" =~ ^# ]] && continue

            local session_name="${pane_target%%:*}"
            if ! tmux has-session -t "$session_name" 2>/dev/null; then
                continue
            fi

            # Re-establish SSH connection
            tmux send-keys -t "$pane_target" "ssh ${ssh_target}" C-m
            ssh_count=$((ssh_count + 1))

            # If there's a Claude session to resume on the remote
            if [[ -n "$remote_session_id" ]]; then
                # Wait for SSH to connect
                sleep 2
                local resume_cmd="cd ${remote_dir} && claude --resume ${remote_session_id}"
                tmux send-keys -t "$pane_target" "$resume_cmd" C-m
                count=$((count + 1))
            fi

            sleep 0.3
        done < "$SSH_SESSIONS_FILE"
    fi

    local parts=()
    [[ $count -gt 0 ]] && parts+=("${count} claude")
    [[ $ssh_count -gt 0 ]] && parts+=("${ssh_count} ssh")

    if [[ ${#parts[@]} -gt 0 ]]; then
        local IFS=", "
        display_message "Restored ${parts[*]} session(s)"
    fi
}

main
