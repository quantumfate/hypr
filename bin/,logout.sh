#!/usr/bin/env bash
# ,logout.sh — open (or close) the power menu.
#
# The one entry point for wlogout: the bar's power button, `CTRL+SUPER+e`, and
# anything else that wants the menu all spawn this, so the menu's arguments
# live in one place instead of being repeated at every call site. The bar used
# to spawn `~/.config/waybar/scripts/wlogout.sh`, a waybar-era script that no
# longer exists — the button silently did nothing.
#
# Three things it owns:
#
#   * Toggle. wlogout is a one-shot overlay with no toggle of its own, so
#     pressing the key (or the button) again while it is up would stack a
#     second copy on top of the first. Already running means close.
#   * Config. `-l`/`-C` are passed explicitly against this desk's own layout
#     and the stylesheet `,theme.sh apply_wlogout` renders for the active
#     palette. wlogout's own search path would find them anyway; naming them
#     means a missing one is an error we can report rather than a menu that
#     comes up unstyled and unreadable.
#   * Icons. The stylesheet's icon paths are only as good as the last theme
#     apply. If the file is missing entirely, re-render it before opening
#     rather than showing a menu with no styling at all.
#
# Exit codes are wlogout's own; the toggle path exits 0.
set -euo pipefail

CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}"
LAYOUT="$CONFIG/wlogout/layout"
STYLE="$CONFIG/wlogout/style.css"
# Injectable for the tests, the same way ,theme.sh injects its own tools.
WLOGOUT=${LOGOUT_WLOGOUT:-wlogout}
THEME=${LOGOUT_THEME:-"$(dirname "$0")/,theme.sh"}

note() { printf ',logout.sh: %s\n' "$1" >&2; }

command -v "$WLOGOUT" >/dev/null 2>&1 || {
    note "wlogout is not installed"
    exit 127
}

# Already up: this press closes it.
if pgrep -x wlogout >/dev/null 2>&1; then
    pkill -x wlogout || true
    exit 0
fi

[ -f "$LAYOUT" ] || {
    note "no layout at $LAYOUT"
    exit 1
}

# A stylesheet is regenerated per palette; a missing one is recoverable.
if [ ! -f "$STYLE" ] && [ -x "$THEME" ]; then
    note "no stylesheet yet — rendering one from the active palette"
    "$THEME" apply >/dev/null 2>&1 || true
fi

if [ -f "$STYLE" ]; then
    exec "$WLOGOUT" --protocol layer-shell -l "$LAYOUT" -C "$STYLE" "$@"
fi

note "opening unstyled: no stylesheet at $STYLE"
exec "$WLOGOUT" --protocol layer-shell -l "$LAYOUT" "$@"
