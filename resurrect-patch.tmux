#!/usr/bin/env bash
# tmux-resurrect-patch
#
# Patches tmux-resurrect with additional save/restore capabilities:
#   1. Vim/Neovim: Auto-creates Session.vim on save so the built-in
#      @resurrect-strategy-vim 'session' works reliably.
#   2. Claude Code: Saves session IDs on save and resumes them on restore
#      via `claude --resume <id>`.
#
# Requirements:
#   - tmux-resurrect
#   - Claude Code CLI (for claude feature)
#
# Important: Do NOT add 'claude' to @resurrect-processes. This plugin
# handles Claude restoration via --resume to preserve conversation context.
#
# Usage:
#   run-shell /path/to/tmux-resurrect-patch/resurrect-patch.tmux

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Chain a command onto an existing tmux-resurrect hook without overwriting it
_resurrect_patch_chain_hook() {
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
_resurrect_patch_chain_hook "@resurrect-hook-post-save-all" \
    "$CURRENT_DIR/scripts/save.sh"

# Restore hook: resume claude sessions (vim restore handled by resurrect natively)
_resurrect_patch_chain_hook "@resurrect-hook-post-restore-all" \
    "$CURRENT_DIR/scripts/restore.sh"
