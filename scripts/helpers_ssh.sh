#!/usr/bin/env bash
# SSH session helpers for tmux-resurrect-patch

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/helpers.sh"

# Get SSH target from an SSH pane's process tree.
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

# Find Claude sessions on a remote host.
# Gets session IDs and cwds. Uses /proc on Linux, pwdx or ps on macOS.
# Prints: session_id<TAB>working_dir (one per line, deduplicated)
get_remote_claude_sessions() {
    local target="$1"
    timeout 5 ssh -o ConnectTimeout=3 -o BatchMode=yes "$target" 'bash -s' 2>/dev/null <<'REMOTE_SCRIPT'
for pid in $(pgrep -f "claude.*--resume" 2>/dev/null); do
    args=$(ps -o args= -p "$pid" 2>/dev/null)
    session_id=$(echo "$args" | sed -n 's/.*--resume  *\([a-f0-9-]*\).*/\1/p')
    [ -z "$session_id" ] && continue
    # Get cwd — fast methods only
    cwd=""
    if [ -d /proc ]; then
        cwd=$(readlink "/proc/$pid/cwd" 2>/dev/null)
    elif command -v pwdx >/dev/null 2>&1; then
        cwd=$(pwdx "$pid" 2>/dev/null | cut -d: -f2 | tr -d ' ')
    fi
    [ -z "$cwd" ] && cwd="~"
    printf "%s\t%s\n" "$session_id" "$cwd"
done | sort -u -t'	' -k1,1
REMOTE_SCRIPT
}
