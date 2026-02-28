#!/usr/bin/env bash
# tmux-patch
#
# Custom tmux patches and plugins:
#
#   1. Resurrect enhancements:
#      - Vim/Neovim: Auto-creates Session.vim on save so the built-in
#        @resurrect-strategy-vim 'session' works reliably.
#      - Claude Code: Saves session IDs on save and resumes them on restore
#        via `claude --resume <id>`.
#
#   2. Meta-aware URL opener (replaces tmux-open):
#      - Detects D/T/S/P/ME/N patterns and opens them on internalfb.com
#      - Opens URLs, file paths, or falls back to Google search
#      - Binds 'o' in copy-mode-vi to open, 'S' to search
#
#   3. Meta-aware URL search (replaces copycat C-u):
#      - Finds standard URLs + Meta asset references (D12345, T12345, etc.)
#      - Uses tmux's native regex search (no Unicode offset bugs)
#      - n/N to cycle through matches, o to open
#
# Requirements:
#   - tmux-resurrect (for resurrect features)
#   - Claude Code CLI (for claude feature)
#
# Important: Do NOT add 'claude' to @resurrect-processes. This plugin
# handles Claude restoration via --resume to preserve conversation context.
#
# Usage:
#   run-shell /path/to/tmux-patch/tmux-patch.tmux

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# =============================================================================
# Resurrect patches
# =============================================================================

# Chain a command onto an existing tmux-resurrect hook without overwriting it
_tmux_patch_chain_hook() {
    local hook_name="$1"
    local new_command="$2"

    local existing
    existing=$(tmux show-option -gqv "$hook_name" 2>/dev/null)

    if [[ -n "$existing" ]]; then
        tmux set-option -g "$hook_name" "${existing} ; ${new_command}"
    else
        tmux set-option -g "$hook_name" "${new_command}"
    fi
}

# Save hook: auto-create vim sessions + capture claude session IDs
_tmux_patch_chain_hook "@resurrect-hook-post-save-all" \
    "$CURRENT_DIR/scripts/save.sh"

# Restore hook: resume claude sessions (vim restore handled by resurrect natively)
_tmux_patch_chain_hook "@resurrect-hook-post-restore-all" \
    "$CURRENT_DIR/scripts/restore.sh"

# =============================================================================
# Meta-aware URL opener (replaces tmux-open)
# =============================================================================

OPEN_SCRIPT="$CURRENT_DIR/scripts/open.sh"

# 'o' in copy-mode-vi: open selected text (Meta patterns, URLs, files)
tmux bind-key -T copy-mode-vi o send-keys -X copy-pipe-and-cancel "$OPEN_SCRIPT"
tmux bind-key -T copy-mode    o send-keys -X copy-pipe-and-cancel "$OPEN_SCRIPT"

# 'S' in copy-mode-vi: Google search selected text
tmux bind-key -T copy-mode-vi S send-keys -X copy-pipe-and-cancel \
    "tr -d '\n' | sed 's/ /+/g' | xargs -I{} open 'https://www.google.com/search?q={}'"
tmux bind-key -T copy-mode    S send-keys -X copy-pipe-and-cancel \
    "tr -d '\n' | sed 's/ /+/g' | xargs -I{} open 'https://www.google.com/search?q={}'"

# =============================================================================
# Meta-aware URL/pattern search (replaces copycat C-u)
# =============================================================================

# Uses tmux's native regex search instead of copycat's awk-based positioning
# which breaks on Unicode characters (⏺, ⎿, etc. from Claude Code output).
# After first match: n = next match, N = previous match, o = open in browser
SEARCH_SCRIPT="$CURRENT_DIR/scripts/search.sh"

tmux bind-key -T prefix C-u run-shell "$SEARCH_SCRIPT"
