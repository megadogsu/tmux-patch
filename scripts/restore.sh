#!/usr/bin/env bash
# Restore hook for tmux-resurrect-patch.
# Called via @resurrect-hook-post-restore-all (no arguments).
#
# - Claude (local): resumes sessions via `claude --resume <id>`
# - SSH + Claude: waits briefly for SSH to connect, then resumes Claude
# - Vim: handled natively by tmux-resurrect via @resurrect-strategy-vim

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$CURRENT_DIR/helpers.sh"

RESURRECT_DIR="$(get_resurrect_dir)"
CLAUDE_SESSIONS_FILE="$RESURRECT_DIR/claude_sessions.txt"
SSH_SESSIONS_FILE="$RESURRECT_DIR/ssh_sessions.txt"

main() {
    local count=0
    local ssh_count=0

    # Give restored shells a moment to initialize
    sleep 1

    # --- Restore local Claude sessions (instant) ---
    if [[ -f "$CLAUDE_SESSIONS_FILE" && -s "$CLAUDE_SESSIONS_FILE" ]]; then
        while IFS=$'\t' read -r pane_target session_id launch_dir session_file; do
            [[ -z "$pane_target" || "$pane_target" =~ ^# ]] && continue
            tmux has-session -t "${pane_target%%:*}" 2>/dev/null || continue
            [[ -n "$session_file" && ! -f "$session_file" ]] && continue

            tmux send-keys -t "$pane_target" "cd ${launch_dir} && claude --resume ${session_id}" C-m
            count=$((count + 1))
            sleep 0.2
        done < "$CLAUDE_SESSIONS_FILE"
    fi

    # --- Restore SSH + Claude sessions ---
    # tmux-resurrect already re-establishes the SSH connection.
    # We wait a fixed 3s for SSH to connect, then send claude --resume.
    if [[ -f "$SSH_SESSIONS_FILE" && -s "$SSH_SESSIONS_FILE" ]]; then
        sleep 3  # single wait for all SSH connections to establish

        while IFS=$'\t' read -r pane_target ssh_target remote_session_id remote_dir; do
            [[ -z "$pane_target" || "$pane_target" =~ ^# ]] && continue
            [[ -z "$remote_session_id" ]] && continue
            tmux has-session -t "${pane_target%%:*}" 2>/dev/null || continue

            tmux send-keys -t "$pane_target" "cd ${remote_dir} && claude --resume ${remote_session_id}" C-m
            count=$((count + 1))
            ssh_count=$((ssh_count + 1))
            sleep 0.2
        done < "$SSH_SESSIONS_FILE"
    fi

    local parts=()
    [[ $count -gt 0 ]] && parts+=("${count} claude")
    [[ $ssh_count -gt 0 ]] && parts+=("(${ssh_count} via ssh)")

    if [[ ${#parts[@]} -gt 0 ]]; then
        local IFS=" "
        display_message "Restored ${parts[*]} session(s)"
    fi
}

main
