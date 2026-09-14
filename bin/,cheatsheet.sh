#!/usr/bin/env bash
# Keybind cheatsheet: parse `hyprctl binds -j` and show in rofi.
# Descriptions come from the `description` field set in the Lua bind layer.
set -euo pipefail

# Only show the bindings of the currently active context: at root the global
# set, inside a submap just that submap's own binds (which-key style). Universal
# binds are deliberately hidden in submaps so the list is only the submap's keys.
# `hyprctl submap` reports "default" at root, else the active submap name.
submap="$(hyprctl submap)"
[[ "$submap" == "default" ]] && submap=""

rows() {
    hyprctl binds -j | jq -r --arg cur "$submap" '
    # modmask -> "SUPER+CTRL+..." (bit flags)
    def mods($m):
      [ {"1":"SHIFT","4":"CTRL","8":"ALT","64":"SUPER"}
        | to_entries[]
        | select((($m / (.key|tonumber)) | floor) % 2 == 1)
        | .value ]
      | join("+");
    .[]
    | select(.description != "")
    | select(.submap == $cur)
    | ( mods(.modmask // 0) | if . == "" then "" else . + "+" end ) as $m
    | "\($m)\(.key)\t\(.description)"
  ' | sort -u
}

formatted="$(rows | column -t -s$'\t')"
prompt="binds${submap:+ · $submap}"

if command -v rofi >/dev/null 2>&1; then
    printf '%s\n' "$formatted" | rofi -dmenu -i -p "$prompt" -no-custom -theme-str 'window {width: 50%;}'
elif command -v wofi >/dev/null 2>&1; then
    printf '%s\n' "$formatted" | wofi --dmenu -p "$prompt"
else
    printf '%s\n' "$formatted"
fi
