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
    timeout 15 ssh -o ConnectTimeout=3 -o BatchMode=yes "$target" 'bash -s' 2>/dev/null <<'REMOTE_SCRIPT'
# Only return Claude sessions running under SSH (not local terminal sessions).
# Uses a single ps call to get all process info, then walks ancestry in-memory.

_resolve_dir_key() {
    local key="${1#-}"
    local full_slash="/$(echo "$key" | tr '-' '/')"
    local test="$full_slash"
    while [ -n "$test" ] && [ "$test" != "/" ]; do
        [ -d "$test" ] && break
        test=$(dirname "$test")
    done
    local prefix="$test"
    local suffix="${full_slash#$prefix}"
    suffix="${suffix#/}"
    [ -z "$suffix" ] && echo "$prefix" && return 0
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

# Snapshot process table: PID<tab>PPID<tab>COMMAND_BASENAME
# Single ps call; awk extracts basename from full path (bash 3.2 compat).
_ps_table=$(mktemp /tmp/ps_table.XXXXXX)
ps -eo pid=,ppid=,args= 2>/dev/null | awk '{
    pid=$1; ppid=$2;
    cmd=$3; gsub(/.*\//, "", cmd);  # basename
    print pid "\t" ppid "\t" cmd
}' > "$_ps_table"
trap 'rm -f "$_ps_table"' EXIT

# Check if a PID has sshd in its ancestry.
_is_ssh_descendant() {
    local cur="$1"
    local depth=0
    while [ -n "$cur" ] && [ "$cur" != "1" ] && [ "$cur" != "0" ] && [ $depth -lt 20 ]; do
        local info
        info=$(awk -F'\t' -v p="$cur" '$1==p {print $2 "\t" $3; exit}' "$_ps_table")
        [ -z "$info" ] && return 1
        local ppid cmd
        ppid=$(echo "$info" | cut -f1)
        cmd=$(echo "$info" | cut -f2)
        case "$cmd" in sshd*) return 0 ;; esac
        cur="$ppid"
        depth=$((depth + 1))
    done
    return 1
}

# Phase 1: Find SSH Claude PIDs (fast — just ps table lookups)
ssh_claude_pids=""
for pid in $(pgrep claude 2>/dev/null); do
    c=$(awk -F'\t' -v p="$pid" '$1==p {print $3; exit}' "$_ps_table")
    [ "$c" = "claude" ] || continue
    _is_ssh_descendant "$pid" || continue
    ssh_claude_pids="$ssh_claude_pids $pid"
done

# Phase 2: Batch lsof for all SSH Claude PIDs at once (one call, not per-PID)
_lsof_table=""
if [ -n "$ssh_claude_pids" ] && command -v lsof >/dev/null 2>&1; then
    pid_csv=$(echo $ssh_claude_pids | tr ' ' ',' | sed 's/^,//')
    _lsof_table=$(lsof -p "$pid_csv" -Fn 2>/dev/null | awk '
        /^p/{pid=substr($0,2)}
        /^n.*\.claude\/projects\/.*\.jsonl/{print pid "\t" substr($0,2)}
    ')
fi

# Phase 3: Extract session IDs and output results
seen=""
for pid in $ssh_claude_pids; do
    session_id=""

    # Method 1: parse --resume <uuid> from command args (instant)
    session_id=$(ps -o args= -p "$pid" 2>/dev/null | \
                 sed -n 's/.*--resume  *\([a-f0-9-][a-f0-9-]*\).*/\1/p')

    # Method 2: batched lsof — check open .jsonl files
    if [ -z "$session_id" ] && [ -n "$_lsof_table" ]; then
        jsonl=$(echo "$_lsof_table" | awk -F'\t' -v p="$pid" '$1==p {print $2; exit}')
        if [ -n "$jsonl" ]; then
            session_id=$(basename "$jsonl" .jsonl)
        fi
    fi

    # Method 3: CLAUDE_LAUNCHER_SESSION_FILE env (Linux /proc only)
    if [ -z "$session_id" ] && [ -d /proc ]; then
        launcher_file=$(tr '\0' '\n' < "/proc/$pid/environ" 2>/dev/null | \
                       sed -n 's/^CLAUDE_LAUNCHER_SESSION_FILE=//p' | head -1)
        if [ -n "$launcher_file" ] && [ -f "$launcher_file" ]; then
            sline=$(grep '^START' "$launcher_file" 2>/dev/null | tail -1)
            [ -n "$sline" ] && session_id=$(echo "$sline" | cut -f2)
        fi
    fi

    # Method 4: use cwd to find most recent session file in matching project dir
    if [ -z "$session_id" ]; then
        cwd_path=$(lsof -p "$pid" -Fn 2>/dev/null | awk '/^fcwd/{getline; print substr($0,2); exit}')
        if [ -n "$cwd_path" ]; then
            dir_key=$(echo "$cwd_path" | tr '/' '-')
            proj_dir="$HOME/.claude/projects/${dir_key}"
            if [ -d "$proj_dir" ]; then
                latest=$(ls -t "$proj_dir"/*.jsonl 2>/dev/null | head -1)
                if [ -n "$latest" ]; then
                    session_id=$(basename "$latest" .jsonl)
                fi
            fi
        fi
    fi

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
rm -f "$_ps_table"
REMOTE_SCRIPT
}
