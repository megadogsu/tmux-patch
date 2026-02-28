#!/usr/bin/env bash
# SSH session helpers for tmux-resurrect-patch

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/helpers.sh"

get_ssh_target() {
    local shell_pid="$1"
    local ssh_pid
    if [[ -d /proc ]]; then
        ssh_pid=$(ps --ppid "$shell_pid" -o pid,comm --no-headers 2>/dev/null | \
                  awk '$2=="ssh"{print $1; exit}')
        [[ -z "$ssh_pid" ]] && return 1
        tr '\0' ' ' < "/proc/$ssh_pid/cmdline" 2>/dev/null | \
            awk '{for(i=NF;i>=1;i--) if($i !~ /^-/) {print $i; exit}}'
    else
        ssh_pid=$(ps -o pid=,comm= -ppid "$shell_pid" 2>/dev/null | \
                  awk '$2=="ssh"{print $1; exit}')
        [[ -z "$ssh_pid" ]] && return 1
        ps -o args= -p "$ssh_pid" 2>/dev/null | \
            awk '{for(i=NF;i>=1;i--) if($i !~ /^-/) {print $i; exit}}'
    fi
}

get_remote_claude_sessions() {
    local target="$1"
    timeout 5 ssh -o ConnectTimeout=3 -o BatchMode=yes "$target" 'bash -s' 2>/dev/null <<'REMOTE_SCRIPT'
_resolve_dir_key() {
    local key="${1#-}"
    local full_slash="/$(echo "$key" | tr '-' '/')"

    # Find deepest existing prefix directory
    local test="$full_slash"
    while [ -n "$test" ] && [ "$test" != "/" ]; do
        [ -d "$test" ] && break
        test=$(dirname "$test")
    done
    local prefix="$test"

    # Get remaining path after prefix
    local suffix="${full_slash#$prefix}"
    suffix="${suffix#/}"
    [ -z "$suffix" ] && echo "$prefix" && return 0

    # Split suffix into parts and try merging with hyphens
    local current="$prefix"
    local pending=""
    local IFS='/'
    for part in $suffix; do
        if [ -z "$pending" ]; then
            pending="$part"
        else
            pending="${pending}-${part}"
        fi
        if [ -d "${current}/${pending}" ]; then
            current="${current}/${pending}"
            pending=""
        fi
    done
    [ -n "$pending" ] && current="${current}/${pending}"
    [ -d "$current" ] && echo "$current" || echo "$prefix"
}

seen=""
for pid in $(pgrep -f "claude.*--resume" 2>/dev/null); do
    session_id=$(ps -o args= -p "$pid" 2>/dev/null | \
                 sed -n 's/.*--resume  *\([a-f0-9-]*\).*/\1/p')
    [ -z "$session_id" ] && continue
    echo "$seen" | grep -q "$session_id" && continue
    seen="$seen $session_id"

    cwd="$HOME"
    for proj_dir in "$HOME"/.claude/projects/*/; do
        if [ -f "${proj_dir}${session_id}.jsonl" ]; then
            resolved=$(_resolve_dir_key "$(basename "$proj_dir")")
            [ -n "$resolved" ] && cwd="$resolved"
            break
        fi
    done
    printf "%s\t%s\n" "$session_id" "$cwd"
done
REMOTE_SCRIPT
}
