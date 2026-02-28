#!/usr/bin/env bash
# Save hook for tmux-resurrect-patch.
# Called via @resurrect-hook-post-save-all (no arguments).

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$CURRENT_DIR/helpers.sh"
source "$CURRENT_DIR/helpers_ssh.sh"

RESURRECT_DIR="$(get_resurrect_dir)"
CLAUDE_SESSIONS_FILE="$RESURRECT_DIR/claude_sessions.txt"
SSH_SESSIONS_FILE="$RESURRECT_DIR/ssh_sessions.txt"
LOCK_FILE="$RESURRECT_DIR/.save_patch.lock"

main() {
    # Skip if another save is already running (from continuum auto-save)
    if [[ -f "$LOCK_FILE" ]]; then
        local lock_pid
        lock_pid=$(cat "$LOCK_FILE" 2>/dev/null)
        if kill -0 "$lock_pid" 2>/dev/null; then
            return 0
        fi
    fi
    echo $$ > "$LOCK_FILE"
    trap 'rm -f "$LOCK_FILE"' EXIT

    mkdir -p "$RESURRECT_DIR"

    local vim_count=0
    local claude_count=0
    local ssh_count=0

    # --- Vim: auto-create Session.vim (instant) ---
    vim_count=$(save_vim_sessions)

    # --- Collect pane info in one pass ---
    : > "$CLAUDE_SESSIONS_FILE"
    local tmp_ssh="${SSH_SESSIONS_FILE}.tmp.$$"
    : > "$tmp_ssh"

    declare -A queried_targets
    declare -A remote_sessions

    while IFS=$'\t' read -r pane_target pane_pid pane_cmd pane_dir; do
        if [[ "$pane_cmd" == "claude" ]]; then
            local info
            info=$(get_claude_session_info "$pane_pid" "$pane_dir")
            if [[ -n "$info" ]]; then
                local session_id session_file launch_dir
                session_id=$(echo "$info" | cut -f1)
                session_file=$(echo "$info" | cut -f2)
                launch_dir=$(echo "$info" | cut -f3)
                launch_dir="${launch_dir:-$pane_dir}"
                printf '%s\t%s\t%s\t%s\n' \
                    "$pane_target" "$session_id" "$launch_dir" "$session_file" \
                    >> "$CLAUDE_SESSIONS_FILE"
                claude_count=$((claude_count + 1))
            fi
        elif [[ "$pane_cmd" == "ssh" ]]; then
            local ssh_target
            ssh_target=$(get_ssh_target "$pane_pid")
            if [[ -n "$ssh_target" ]]; then
                if [[ -z "${queried_targets[$ssh_target]}" ]]; then
                    queried_targets[$ssh_target]=1
                    remote_sessions[$ssh_target]=$(get_remote_claude_sessions "$ssh_target")
                fi

                local remaining="${remote_sessions[$ssh_target]}"
                if [[ -n "$remaining" ]]; then
                    local first_line
                    first_line=$(echo "$remaining" | head -1)
                    remote_sessions[$ssh_target]=$(echo "$remaining" | tail -n +2)
                    printf '%s\t%s\t%s\n' \
                        "$pane_target" "$ssh_target" "$first_line" \
                        >> "$tmp_ssh"
                else
                    printf '%s\t%s\t\t\n' \
                        "$pane_target" "$ssh_target" \
                        >> "$tmp_ssh"
                fi
                ssh_count=$((ssh_count + 1))
            fi
        fi
    done < <(tmux list-panes -a -F \
        '#{session_name}:#{window_index}.#{pane_index}	#{pane_pid}	#{pane_current_command}	#{pane_current_path}')

    mv -f "$tmp_ssh" "$SSH_SESSIONS_FILE"

    local parts=()
    [[ $vim_count -gt 0 ]] && parts+=("${vim_count} vim")
    [[ $claude_count -gt 0 ]] && parts+=("${claude_count} claude")
    [[ $ssh_count -gt 0 ]] && parts+=("${ssh_count} ssh")

    if [[ ${#parts[@]} -gt 0 ]]; then
        local IFS=", "
    fi
}

main
