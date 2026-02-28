# tmux OSC52 patch for set-clipboard external

## Bug

tmux 3.5a (and likely earlier versions) has a bug in `input.c` where OSC 52
(clipboard setting) sequences from applications are silently dropped when
`set-clipboard` is set to `external`.

The `set-clipboard` option has three values:
- `off` (0): Do not forward OSC 52 sequences
- `external` (1): Forward OSC 52 to the outer terminal only (no paste buffer)
- `on` (2): Forward OSC 52 to the outer terminal and store in paste buffer

The bug is in `input_osc_52()` in `input.c`:

```c
state = options_get_number(global_options, "set-clipboard");
if (state != 2)    // BUG: this skips both "off" (0) AND "external" (1)
    return;
```

This means `external` mode does nothing at all — identical to `off`.

## Fix

Two changes in `input.c`:

1. Change the early return guard from `state != 2` to `state == 0` so that
   both `external` (1) and `on` (2) proceed with OSC 52 processing.

2. Only add to the paste buffer when `state == 2` (`on`), matching the
   documented behavior that `external` does not create paste buffers.

## Additional setup

Terminals that don't advertise the `Ms` terminfo capability (like
rxvt-unicode) also need this in `~/.tmux.conf`:

```
set -ga terminal-features "rxvt-unicode-256color:clipboard"
```

## Applying

```bash
cd /path/to/tmux-3.5a-source
patch -p0 < fix-osc52-set-clipboard-external.patch
make && sudo make install
```
