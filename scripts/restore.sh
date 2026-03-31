#!/usr/bin/env bash
# Restore hook for tmux-resurrect-patch.
# Called via @resurrect-hook-post-restore-all AFTER resurrect recreates panes.
#
# - Claude (local): resumes via `claude --resume <id>`
# - SSH + Claude: reconnects SSH, then resumes Claude on remote
# - Vim: handled by tmux-resurrect natively

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$CURRENT_DIR/helpers.sh"

RESURRECT_DIR="$(get_resurrect_dir)"

# Find the versioned session file matching the save being restored.
# Falls back to the most recent non-empty versioned file, then the
# unversioned file.
_find_session_file() {
    local prefix="$1"  # "claude_sessions" or "ssh_sessions"
    local last_save
    last_save="$(readlink "$RESURRECT_DIR/last" 2>/dev/null)"
    if [[ -n "$last_save" ]]; then
        local timestamp
        timestamp="${last_save#tmux_resurrect_}"
        timestamp="${timestamp%.txt}"
        local versioned="$RESURRECT_DIR/${prefix}_${timestamp}.txt"
        if [[ -s "$versioned" ]]; then
            echo "$versioned"
            return
        fi
    fi
    # Fallback: most recent non-empty versioned file
    local latest
    latest="$(ls -t "$RESURRECT_DIR/${prefix}_"*.txt 2>/dev/null | while read -r f; do
        [[ -s "$f" ]] && echo "$f" && break
    done)"
    if [[ -n "$latest" ]]; then
        echo "$latest"
        return
    fi
    # Final fallback: unversioned file
    echo "$RESURRECT_DIR/${prefix}.txt"
}

CLAUDE_SESSIONS_FILE="$(_find_session_file claude_sessions)"
SSH_SESSIONS_FILE="$(_find_session_file ssh_sessions)"

main() {
    local count=0

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

    # --- Restore SSH sessions ---
    # Resurrect does NOT restore ssh processes (not in @resurrect-processes).
    # We send the ssh command ourselves, wait for connection, then resume Claude.
    if [[ -f "$SSH_SESSIONS_FILE" && -s "$SSH_SESSIONS_FILE" ]]; then
        # First pass: send all SSH commands
        while IFS=$'\t' read -r pane_target ssh_target remote_session_id remote_dir; do
            [[ -z "$pane_target" || "$pane_target" =~ ^# ]] && continue
            [[ -z "$ssh_target" ]] && continue
            tmux has-session -t "${pane_target%%:*}" 2>/dev/null || continue

            tmux send-keys -t "$pane_target" "ssh ${ssh_target}" C-m
        done < "$SSH_SESSIONS_FILE"

        # Wait for SSH connections to establish
        sleep 3

        # Second pass: send Claude resume commands
        while IFS=$'\t' read -r pane_target ssh_target remote_session_id remote_dir; do
            [[ -z "$pane_target" || "$pane_target" =~ ^# ]] && continue
            [[ -z "$remote_session_id" ]] && continue
            tmux has-session -t "${pane_target%%:*}" 2>/dev/null || continue

            local cmd="cd ${remote_dir} && claude --resume ${remote_session_id}"
            tmux send-keys -t "$pane_target" "$cmd" C-m
            count=$((count + 1))
        done < "$SSH_SESSIONS_FILE"
    fi

    [[ $count -gt 0 ]] && display_message "Restored $count Claude session(s)"
}

main
