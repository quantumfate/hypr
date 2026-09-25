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
#   * Size. wlogout stretches its button grid across whatever output it lands
#     on, so the same menu was a compact panel on the small vertical screen
#     and a wall of buttons across the ultrawide. The grid is a FIXED box
#     here: margins are computed from the focused monitor's logical size so
#     MENU_W x MENU_H of buttons sit centred, whatever the monitor.
#
# Exit codes are wlogout's own; the toggle path exits 0.
set -euo pipefail

# The fixed menu box, in logical pixels: three buttons per row, two rows.
# Small enough for the narrow vertical panel, so no monitor needs a special
# case -- a monitor too small for the box falls back to a zero margin.
MENU_W=${LOGOUT_MENU_W:-600}
MENU_H=${LOGOUT_MENU_H:-320}
MENU_COLUMNS=${LOGOUT_MENU_COLUMNS:-3}

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

# The focused monitor decides the margins, and `-n` keeps the surface on that
# one output instead of spanning the desk. Without a compositor to ask (the
# tests, a bare session) the menu opens with wlogout's own full-width grid
# rather than failing.
geometry=()
if command -v "${LOGOUT_HYPRCTL:-hyprctl}" >/dev/null 2>&1; then
    margins=$("${LOGOUT_HYPRCTL:-hyprctl}" monitors -j 2>/dev/null | MENU_W="$MENU_W" MENU_H="$MENU_H" python3 -c '
import json, os, sys

monitors = json.load(sys.stdin)
if not monitors:
    sys.exit(1)
focused = next((m for m in monitors if m.get("focused")), monitors[0])
# Logical pixels: a scaled output reports its physical mode, but wlogout lays
# out (and takes its margins) in the scaled coordinate space.
scale = focused.get("scale") or 1
width = focused["width"] / scale
height = focused["height"] / scale
side = max(int((width - int(os.environ["MENU_W"])) / 2), 0)
top = max(int((height - int(os.environ["MENU_H"])) / 2), 0)
print(focused.get("id", 0), side, top)
' 2>/dev/null) || margins=""
    if [ -n "$margins" ]; then
        read -r mon side top <<<"$margins"
        geometry=(-n -P "$mon" -b "$MENU_COLUMNS" -L "$side" -R "$side" -T "$top" -B "$top")
    fi
fi

if [ -f "$STYLE" ]; then
    exec "$WLOGOUT" --protocol layer-shell -l "$LAYOUT" -C "$STYLE" "${geometry[@]}" "$@"
fi

note "opening unstyled: no stylesheet at $STYLE"
exec "$WLOGOUT" --protocol layer-shell -l "$LAYOUT" "${geometry[@]}" "$@"
