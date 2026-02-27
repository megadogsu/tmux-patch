#!/usr/bin/env bash
# Save hook for tmux-resurrect-patch.
# Called via @resurrect-hook-post-save-all (no arguments).
#
# 1. Auto-creates Session.vim in all vim/nvim panes (for @resurrect-strategy-vim)
# 2. Captures Claude Code session IDs for later restore

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$CURRENT_DIR/helpers.sh"

RESURRECT_DIR="$(get_resurrect_dir)"
CLAUDE_SESSIONS_FILE="$RESURRECT_DIR/claude_sessions.txt"

main() {
    mkdir -p "$RESURRECT_DIR"

    local vim_count=0
    local claude_count=0

    # --- Vim: auto-create Session.vim ---
    vim_count=$(save_vim_sessions)

    # --- Claude: capture session IDs ---
    : > "$CLAUDE_SESSIONS_FILE"

    while IFS=$'\t' read -r pane_target pane_pid pane_cmd pane_dir; do
        if [[ "$pane_cmd" == "claude" ]]; then
            local info
            info=$(get_claude_session_info "$pane_pid" "$pane_dir")
            if [[ -n "$info" ]]; then
                local session_id session_file launch_dir
                session_id=$(echo "$info" | cut -f1)
                session_file=$(echo "$info" | cut -f2)
                launch_dir=$(echo "$info" | cut -f3)
                # Use launch_dir from launcher file; fall back to pane_dir
                launch_dir="${launch_dir:-$pane_dir}"
                # Format: pane_target<TAB>session_id<TAB>launch_dir<TAB>session_file
                printf '%s\t%s\t%s\t%s\n' \
                    "$pane_target" "$session_id" "$launch_dir" "$session_file" \
                    >> "$CLAUDE_SESSIONS_FILE"
                claude_count=$((claude_count + 1))
            fi
        fi
    done < <(tmux list-panes -a -F \
        '#{session_name}:#{window_index}.#{pane_index}	#{pane_pid}	#{pane_current_command}	#{pane_current_path}')

    local parts=()
    [[ $vim_count -gt 0 ]] && parts+=("${vim_count} vim")
    [[ $claude_count -gt 0 ]] && parts+=("${claude_count} claude")

    if [[ ${#parts[@]} -gt 0 ]]; then
        local IFS=", "
        display_message "Saved ${parts[*]} session(s)"
    fi
}

main
