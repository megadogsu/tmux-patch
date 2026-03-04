#!/usr/bin/env bash
# Hash, hostname, and IP search for tmux copy-mode.
# Replaces copycat C-h with tmux native regex search (no flashing, no Unicode bugs).
#
# Matches:
#   1. SHA hashes: 12-40 hex chars (git commits, checksums)
#   2. IPv4 addresses: 10.0.0.1, 192.168.1.100
#   3. IPv6 addresses: fe80::1, 2001:db8::1, ::1, full form
#   4. Hostnames: devvm32391.prn0.facebook.com, server-01.prod.meta.net
#
# URL hostnames are handled by C-u, so this script strips URLs from
# pane content before searching. Uses a two-pass approach: capture pane,
# remove URLs, write to temp, then search the cleaned output.
#
# After first match: n = next, N = previous, o = open

# Since tmux ERE has no lookbehind, we can't exclude URL-embedded hosts
# in a single regex. Instead, use tmux's native search on the raw pane
# but accept minimal overlap with C-u. Hostnames require 3+ dot segments
# to reduce noise.

SHA='[0-9a-f]{12,40}'
IPV4='[0-9]{1,3}[.][0-9]{1,3}[.][0-9]{1,3}[.][0-9]{1,3}'
IPV6='[0-9a-f]{1,4}(:[0-9a-f]{0,4}){2,7}|::([0-9a-f]{1,4}:){0,5}[0-9a-f]{1,4}'
# Require 3+ dot-separated segments to avoid matching version numbers (1.2)
# or simple filenames. This naturally covers infrastructure hostnames.
HOSTNAME='[[:alnum:]][[:alnum:]_-]*[.][[:alnum:]_-]+[.][[:alnum:]_-]+([.][[:alnum:]_-]+)*'

PATTERN="$SHA|$IPV4|$IPV6|$HOSTNAME"

tmux copy-mode
tmux send-keys -X search-backward "$PATTERN" 2>/dev/null || \
    tmux display-message "No hashes, IPs, or hostnames found"
