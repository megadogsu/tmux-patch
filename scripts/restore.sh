#!/usr/bin/env bash
# Restore hook for tmux-resurrect-patch.
# Called via @resurrect-hook-post-restore-all (no arguments).
#
# - Claude (local): resumes sessions via `claude --resume <id>`
# - SSH + Claude: waits for SSH to connect (resurrect already re-SSHs),
#   then resumes Claude on remote
# - Vim: handled natively by tmux-resurrect via @resurrect-strategy-vim 'session'

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$CURRENT_DIR/helpers.sh"

RESURRECT_DIR="$(get_resurrect_dir)"
CLAUDE_SESSIONS_FILE="$RESURRECT_DIR/claude_sessions.txt"
SSH_SESSIONS_FILE="$RESURRECT_DIR/ssh_sessions.txt"

# Wait for a pane to have a shell prompt (SSH connected).
# Checks pane_current_command — once it changes from "ssh" to a shell, SSH is ready.
# Falls back to a simple timeout.
_wait_for_ssh_ready() {
    local pane_target="$1"
    local max_wait=15
    local waited=0
    while [[ $waited -lt $max_wait ]]; do
        # Check if the pane has content that looks like a prompt
        local last_line
        last_line=$(tmux capture-pane -t "$pane_target" -p 2>/dev/null | grep -v '^$' | tail -1)
        if [[ "$last_line" =~ [\$\#\>❯\%] ]]; then
            return 0
        fi
        sleep 1
        waited=$((waited + 1))
    done
    return 1
}

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

    # --- Restore SSH + Claude sessions ---
    # tmux-resurrect already re-establishes the SSH connection (it's in the
    # saved state file as the pane command). We just need to wait for SSH
    # to connect, then resume Claude on the remote.
    local ssh_count=0
    if [[ -f "$SSH_SESSIONS_FILE" && -s "$SSH_SESSIONS_FILE" ]]; then
        while IFS=$'\t' read -r pane_target ssh_target remote_session_id remote_dir; do
            [[ -z "$pane_target" || "$pane_target" =~ ^# ]] && continue

            local session_name="${pane_target%%:*}"
            if ! tmux has-session -t "$session_name" 2>/dev/null; then
                continue
            fi

            # Skip if no Claude session to resume (just an SSH pane)
            if [[ -z "$remote_session_id" ]]; then
                continue
            fi

            # Wait for SSH to connect (resurrect already sent the ssh command)
            if _wait_for_ssh_ready "$pane_target"; then
                tmux send-keys -t "$pane_target" "cd ${remote_dir} && claude --resume ${remote_session_id}" C-m
                count=$((count + 1))
                ssh_count=$((ssh_count + 1))
            fi

            sleep 0.3
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
