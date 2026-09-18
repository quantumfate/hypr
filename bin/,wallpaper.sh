#!/usr/bin/env bash
# ,wallpaper.sh — a thin wrapper over `,theme.sh wallpaper` for keybinds.
#
# All the logic (sets, shuffling, per-monitor picks, validation) lives in
# ,theme.sh now; this is just the short names a Hyprland bind wants to spawn.
#
#   ,wallpaper.sh              next wallpaper on every monitor, current palette
#   ,wallpaper.sh next|prev|random [palette] [--output NAME]

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

exec "$SCRIPT_DIR/,theme.sh" wallpaper "${1:-next}" "${@:2}"
