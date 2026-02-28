#!/usr/bin/env bash
# Save hook for tmux-resurrect-patch.
# Called via @resurrect-hook-post-save-all (no arguments).
#
# 1. Auto-creates Session.vim in all vim/nvim panes (for @resurrect-strategy-vim)
# 2. Captures Claude Code session IDs for later restore
# 3. Captures SSH pane info (target + remote Claude sessions) for SSH restore

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$CURRENT_DIR/helpers.sh"
source "$CURRENT_DIR/helpers_ssh.sh"

RESURRECT_DIR="$(get_resurrect_dir)"
CLAUDE_SESSIONS_FILE="$RESURRECT_DIR/claude_sessions.txt"
SSH_SESSIONS_FILE="$RESURRECT_DIR/ssh_sessions.txt"

main() {
    mkdir -p "$RESURRECT_DIR"

    local vim_count=0
    local claude_count=0
    local ssh_count=0

    # --- Vim: auto-create Session.vim ---
    vim_count=$(save_vim_sessions)

    # --- Claude + SSH: capture session IDs ---
    : > "$CLAUDE_SESSIONS_FILE"
    : > "$SSH_SESSIONS_FILE"

    # Track SSH targets we've already queried (avoid duplicate remote queries)
    declare -A queried_targets
    declare -A remote_sessions  # target -> "session_id\tdir\n..."

    while IFS=$'\t' read -r pane_target pane_pid pane_cmd pane_dir; do
        if [[ "$pane_cmd" == "claude" ]]; then
            # Local Claude session
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
            # SSH pane — get target and query remote for Claude sessions
            local ssh_target
            ssh_target=$(get_ssh_target "$pane_pid")
            if [[ -n "$ssh_target" ]]; then
                # Query remote only once per target
                if [[ -z "${queried_targets[$ssh_target]}" ]]; then
                    queried_targets[$ssh_target]=1
                    remote_sessions[$ssh_target]=$(get_remote_claude_sessions "$ssh_target")
                fi

                # Pick the next unassigned remote Claude session for this pane
                local remaining="${remote_sessions[$ssh_target]}"
                if [[ -n "$remaining" ]]; then
                    local first_line
                    first_line=$(echo "$remaining" | head -1)
                    # Remove used session from remaining
                    remote_sessions[$ssh_target]=$(echo "$remaining" | tail -n +2)

                    local remote_session_id remote_dir
                    remote_session_id=$(echo "$first_line" | cut -f1)
                    remote_dir=$(echo "$first_line" | cut -f2)

                    # Format: pane_target<TAB>ssh_target<TAB>session_id<TAB>remote_dir
                    printf '%s\t%s\t%s\t%s\n' \
                        "$pane_target" "$ssh_target" "$remote_session_id" "$remote_dir" \
                        >> "$SSH_SESSIONS_FILE"
                    ssh_count=$((ssh_count + 1))
                else
                    # SSH pane but no Claude session found — save SSH target for reconnection
                    printf '%s\t%s\t\t\n' \
                        "$pane_target" "$ssh_target" \
                        >> "$SSH_SESSIONS_FILE"
                    ssh_count=$((ssh_count + 1))
                fi
            fi
        fi
    done < <(tmux list-panes -a -F \
        '#{session_name}:#{window_index}.#{pane_index}	#{pane_pid}	#{pane_current_command}	#{pane_current_path}')

    local parts=()
    [[ $vim_count -gt 0 ]] && parts+=("${vim_count} vim")
    [[ $claude_count -gt 0 ]] && parts+=("${claude_count} claude")
    [[ $ssh_count -gt 0 ]] && parts+=("${ssh_count} ssh")

    if [[ ${#parts[@]} -gt 0 ]]; then
        local IFS=", "
        display_message "Saved ${parts[*]} session(s)"
    fi
}

main
