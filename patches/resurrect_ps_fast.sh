#!/usr/bin/env bash
# Fast replacement for tmux-resurrect ps.sh save command strategy.
# Original: `ps -ao ppid,args | sed | grep ^PID | cut` — scans ALL procs.
# This: single `ps -eo ppid,args` with awk filter — same output, but the
# caller (dump_panes) invokes this per-pane. So we cache the full process
# list in a temp file and reuse it within the same second.

PANE_PID="$1"
[[ -z "$PANE_PID" ]] && exit 0

CACHE="/tmp/.tmux_resurrect_ps_cache"
NOW=$(date +%s)

# Refresh cache if stale (>2s old) or missing
if [[ ! -f "$CACHE" ]] || [[ $(( NOW - $(stat -f %m "$CACHE" 2>/dev/null || stat -c %Y "$CACHE" 2>/dev/null || echo 0) )) -gt 2 ]]; then
    ps -eo ppid,args 2>/dev/null | sed 's/^ *//' > "$CACHE"
fi

grep "^${PANE_PID} " "$CACHE" | cut -d' ' -f2-
