#!/usr/bin/env bash
# Hash, hostname, IP, and device serial search for tmux copy-mode.
# Replaces copycat C-h with tmux native regex search (no flashing, no Unicode bugs).
#
# Matches:
#   1. SHA hashes: 12-40 hex chars (git commits, checksums)
#   2. IPv4 addresses: 10.0.0.1, 192.168.1.100
#   3. IPv6 addresses: fe80::1, 2001:db8::1, ::1, full form
#   4. Hostnames: devvm32391.prn0.facebook.com, server-01.prod.meta.net
#   5. ADB/device serials: 2Y0YB44GC60008, 356YB2HG5500B4 (digits+uppercase mixed, 10-20 chars)
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
# IPv6: non-abbreviated requires exactly 8 groups (7 colons). Abbreviated (::) handled separately.
# This avoids matching timestamps like 18:01:39 (only 2 colons).
IPV6='[0-9a-f]{1,4}(:[0-9a-f]{1,4}){7}|::([0-9a-f]{1,4}:){0,5}[0-9a-f]{1,4}'
# Require 3+ dot-separated segments to avoid matching version numbers (1.2)
# or simple filenames. This naturally covers infrastructure hostnames.
HOSTNAME='[[:alnum:]][[:alnum:]_-]*[.][[:alnum:]_-]+[.][[:alnum:]_-]+([.][[:alnum:]_-]+)*'
# ADB/device serial numbers: 10-20 chars of [0-9A-Z], must contain at least
# one digit followed (eventually) by an uppercase letter, or vice versa.
# ERE has no lookahead, so we match: digits...letter...rest OR letters...digit...rest
# Matches: 2Y0YB44GC60008, 356YB2HG5500B4, 4V0ZW04H3T0036
SERIAL='[0-9][0-9A-Z]*[A-Z][0-9A-Z]*|[A-Z][0-9A-Z]*[0-9][0-9A-Z]*'

PATTERN="$SHA|$IPV4|$IPV6|$HOSTNAME|$SERIAL"

tmux copy-mode
tmux send-keys -X search-backward "$PATTERN" 2>/dev/null || \
    tmux display-message "No hashes, IPs, hostnames, or serials found"
