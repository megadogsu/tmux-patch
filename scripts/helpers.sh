#!/usr/bin/env bash
# Shared helper functions for tmux-resurrect-patch

get_resurrect_dir() {
    local dir
    dir=$(tmux show-option -gqv @resurrect-dir 2>/dev/null)
    dir="${dir:-$HOME/.tmux/resurrect}"
    dir="${dir/#\~/$HOME}"
    echo "$dir"
}

display_message() {
    tmux display-message "resurrect-patch: $1"
}

# --- Vim helpers ---

# Save vim/nvim sessions by sending :mksession! to panes running vim/nvim.
# Prints the count of vim panes processed.
save_vim_sessions() {
    local count=0

    while IFS=$'\t' read -r pane_target pane_cmd pane_dir; do
        case "$pane_cmd" in
            vim|nvim|vi)
                # Escape to normal mode, then save session file in the pane's cwd
                tmux send-keys -t "$pane_target" Escape
                tmux send-keys -t "$pane_target" ":mksession! Session.vim" C-m
                count=$((count + 1))
                ;;
        esac
    done < <(tmux list-panes -a -F \
        '#{session_name}:#{window_index}.#{pane_index}	#{pane_current_command}	#{pane_current_path}')

    echo "$count"
}

# --- Claude helpers ---

# Get all descendant PIDs of a given PID (recursive)
get_descendant_pids() {
    local pid="$1"
    local children
    children=$(ps -o pid= --ppid "$pid" 2>/dev/null)
    for child in $children; do
        child="${child// /}"
        [[ -z "$child" ]] && continue
        echo "$child"
        get_descendant_pids "$child"
    done
}

# Given a CLAUDE_LAUNCHER_SESSION_FILE path, extract the active session ID,
# session file path, and launch directory.
# Prints "session_id<TAB>session_file_path<TAB>launch_dir" to stdout.
_extract_from_launcher_file() {
    local launcher_file="$1"
    [[ ! -f "$launcher_file" ]] && return 1
    # The last START line contains the current active session
    # Format: START<TAB>session_id<TAB>session_file_path<TAB><TAB>working_dir
    local line
    line=$(grep '^START' "$launcher_file" 2>/dev/null | tail -1)
    [[ -z "$line" ]] && return 1

    local session_id session_file_path launch_dir
    session_id=$(echo "$line" | cut -f2)
    session_file_path=$(echo "$line" | cut -f3)
    launch_dir=$(echo "$line" | cut -f5)
    [[ -z "$session_id" ]] && return 1

    printf '%s\t%s\t%s\n' "$session_id" "$session_file_path" "$launch_dir"
}

# Extract Claude session info from a pane's process tree.
# Prints "session_id<TAB>session_file_path<TAB>launch_dir" to stdout.
#
# Tries three methods:
#   1. Parse bwrap /proc/PID/cmdline for CLAUDE_LAUNCHER_SESSION_FILE (world-readable)
#   2. Read CLAUDE_LAUNCHER_SESSION_FILE from /proc/PID/environ (owner-only)
#   3. Most recently modified session .jsonl matching the pane directory
get_claude_session_info() {
    local shell_pid="$1"
    local pane_dir="$2"

    local all_pids
    all_pids=$(get_descendant_pids "$shell_pid")

    # Method 1: Parse bwrap command line (world-readable /proc/PID/cmdline)
    for pid in $all_pids; do
        [[ -z "$pid" ]] && continue

        local cmdline
        cmdline=$(tr '\0' '\n' < "/proc/$pid/cmdline" 2>/dev/null) || continue
        [[ -z "$cmdline" ]] && continue

        local launcher_file
        launcher_file=$(echo "$cmdline" | grep -A1 '^CLAUDE_LAUNCHER_SESSION_FILE$' | tail -1)

        if [[ -n "$launcher_file" && "$launcher_file" != "CLAUDE_LAUNCHER_SESSION_FILE" ]]; then
            local result
            result=$(_extract_from_launcher_file "$launcher_file")
            if [[ -n "$result" ]]; then
                echo "$result"
                return 0
            fi
        fi
    done

    # Method 2: Read from /proc/PID/environ (may fail inside bwrap)
    for pid in $all_pids; do
        [[ -z "$pid" ]] && continue

        local launcher_file
        launcher_file=$(tr '\0' '\n' < "/proc/$pid/environ" 2>/dev/null | \
                       sed -n 's/^CLAUDE_LAUNCHER_SESSION_FILE=//p' | head -1)

        if [[ -n "$launcher_file" ]]; then
            local result
            result=$(_extract_from_launcher_file "$launcher_file")
            if [[ -n "$result" ]]; then
                echo "$result"
                return 0
            fi
        fi
    done

    # Method 3: Most recently modified session file in matching project dir
    if [[ -n "$pane_dir" ]]; then
        local dir_key
        dir_key=$(echo "$pane_dir" | tr '/' '-')
        local project_dir="$HOME/.claude/projects/${dir_key}"

        if [[ -d "$project_dir" ]]; then
            local latest
            latest=$(ls -t "$project_dir"/*.jsonl 2>/dev/null | head -1)
            if [[ -n "$latest" ]]; then
                local session_id
                session_id=$(basename "$latest" .jsonl)
                printf '%s\t%s\t%s\n' "$session_id" "$latest" "$pane_dir"
                return 0
            fi
        fi
    fi

    return 1
}
