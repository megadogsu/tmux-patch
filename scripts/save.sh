#!/usr/bin/env bash
# Save hook for tmux-resurrect-patch.
# Called via @resurrect-hook-post-save-all (no arguments).
# Compatible with bash 3.2 (macOS default) — no associative arrays.

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

    # Use temp files instead of associative arrays (bash 3.2 compat)
    local queried_file="${RESURRECT_DIR}/.queried_targets.$$"
    local remote_cache_dir="${RESURRECT_DIR}/.remote_cache.$$"
    : > "$queried_file"
    mkdir -p "$remote_cache_dir"
    trap 'rm -f "$LOCK_FILE" "$queried_file"; rm -rf "$remote_cache_dir"' EXIT

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
                # Dedup: query each ssh target only once
                local target_key
                target_key=$(echo "$ssh_target" | tr '/@:.' '_')
                local cache_file="$remote_cache_dir/$target_key"

                if ! grep -qxF "$ssh_target" "$queried_file" 2>/dev/null; then
                    echo "$ssh_target" >> "$queried_file"
                    get_remote_claude_sessions "$ssh_target" > "$cache_file" 2>/dev/null
                fi

                if [[ -s "$cache_file" ]]; then
                    local first_line
                    first_line=$(head -1 "$cache_file")
                    # Remove consumed line
                    tail -n +2 "$cache_file" > "${cache_file}.tmp" && mv -f "${cache_file}.tmp" "$cache_file"
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

    local msg=""
    [[ $vim_count -gt 0 ]] && msg="${vim_count} vim"
    [[ $claude_count -gt 0 ]] && msg="${msg:+$msg, }${claude_count} claude"
    [[ $ssh_count -gt 0 ]] && msg="${msg:+$msg, }${ssh_count} ssh"

    if [[ -n "$msg" ]]; then
        display_message "Saved ${msg} session(s)"
    fi
}

main
