#!/usr/bin/env bash
# ,wallpaper.sh — pick a wallpaper at random and bind it.
#
# Was ,hyprpaper.sh, and called `hyprctl hyprpaper` directly. Two reasons it
# does not any more: hyprpaper is being replaced by awww (it cannot crossfade),
# and a second writer of the wallpaper would bypass everything ,theme.sh does
# on the way — the blur/desaturate/tint pass that keeps a translucent bar
# legible, the per-palette binding, and the result record.
#
# So this only chooses. ,theme.sh applies.
#
#   ,wallpaper.sh              bind a random wallpaper to the current palette

set -euo pipefail

WALLPAPER_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/hypr/wallpapers"
[ -d "$WALLPAPER_DIR" ] || {
    printf '%s: no wallpaper directory at %s\n' "${0##*/}" "$WALLPAPER_DIR" >&2
    exit 1
}

# Exclude whatever is bound now, so "random" never picks the current one and
# looks like it did nothing.
current=$(,theme.sh status 2>/dev/null | sed -n 's/^wallpaper *//p' || true)

wallpaper=$(find "$WALLPAPER_DIR" -type f \
    \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' \) \
    ! -name "$(basename "${current:-none}")" | shuf -n 1)

[ -n "$wallpaper" ] || {
    printf '%s: no wallpapers found in %s\n' "${0##*/}" "$WALLPAPER_DIR" >&2
    exit 1
}

exec ,theme.sh wallpaper "$wallpaper"
