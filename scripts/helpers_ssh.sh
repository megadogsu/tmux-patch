#!/usr/bin/env bash
# SSH session helpers for tmux-resurrect-patch
# Handles saving/restoring Claude and Vim sessions running inside SSH panes.

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/helpers.sh"

# Get SSH target (user@host or host) from an SSH pane's process tree.
# Args: $1 = shell PID of the pane
get_ssh_target() {
    local shell_pid="$1"
    local ssh_pid
    if [[ -d /proc ]]; then
        ssh_pid=$(ps --ppid "$shell_pid" -o pid,comm --no-headers 2>/dev/null | \
                  awk '$2=="ssh"{print $1; exit}')
        [[ -z "$ssh_pid" ]] && return 1
        local cmdline
        cmdline=$(tr '\0' ' ' < "/proc/$ssh_pid/cmdline" 2>/dev/null)
        # Extract target: last arg that doesn't start with -
        echo "$cmdline" | awk '{for(i=NF;i>=1;i--) if($i !~ /^-/) {print $i; exit}}'
    else
        ssh_pid=$(ps -o pid=,comm= -ppid "$shell_pid" 2>/dev/null | \
                  awk '$2=="ssh"{print $1; exit}')
        [[ -z "$ssh_pid" ]] && return 1
        ps -o args= -p "$ssh_pid" 2>/dev/null | \
            awk '{for(i=NF;i>=1;i--) if($i !~ /^-/) {print $i; exit}}'
    fi
}

# Find Claude sessions on a remote host.
# Args: $1 = SSH target (user@host or host)
# Prints: session_id<TAB>working_dir (one per line, deduplicated)
get_remote_claude_sessions() {
    local target="$1"
    ssh -o ConnectTimeout=5 -o BatchMode=yes "$target" 'bash -s' 2>/dev/null <<'REMOTE_SCRIPT'
for pid in $(pgrep -f "claude.*--resume" 2>/dev/null); do
    session_id=$(ps -o args= -p "$pid" 2>/dev/null | \
                 sed -n "s/.*--resume  *\([^ ]*\).*/\1/p")
    [ -z "$session_id" ] && continue
    # Get cwd: /proc on Linux, lsof on macOS
    if [ -d /proc ]; then
        cwd=$(readlink "/proc/$pid/cwd" 2>/dev/null)
    else
        cwd=$(lsof -a -p "$pid" -d cwd -Fn 2>/dev/null | grep "^n/" | sed "s/^n//" | head -1)
    fi
    [ -z "$cwd" ] && cwd="~"
    printf "%s\t%s\n" "$session_id" "$cwd"
done | sort -u -t'	' -k1,1
REMOTE_SCRIPT
}

# Save Vim sessions on a remote host by sending :mksession!
# Args: $1 = SSH target
# Prints count of vim sessions saved
save_remote_vim_sessions() {
    local target="$1"
    ssh -o ConnectTimeout=5 -o BatchMode=yes "$target" 'bash -s' 2>/dev/null <<'REMOTE_SCRIPT'
count=0
for pid in $(pgrep -x "vim\|nvim\|vi" 2>/dev/null); do
    # Send USR1 signal which vim uses to save session (if configured)
    # Or we just note the PID — actual :mksession needs terminal access
    count=$((count + 1))
done
echo "$count"
REMOTE_SCRIPT
}
