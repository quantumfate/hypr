#!/usr/bin/env bash

# Toggles a submap and updates the shared resource for applications that rely on nesting submaps
toggle=$1
IFS=':' read -r app_name next_submap prev_submap <<<"$2"

if [[ $toggle == "--on" ]]; then
  notify-send --app-name="$app_name" -h string:x-canonical-private-synchronous:sys-notify -u low "Submap $next_submap on"
  hyprctl eval "hl.dsp.submap($next_submap)"
  echo "$next_submap" >"$XDG_RUNTIME_DIR/hypr/alttab/submap"
fi

if [[ $toggle == "--off" ]]; then
  if [[ $prev_submap == "reset" ]]; then
    notify-send --app-name="Hyprland" -h string:x-canonical-private-synchronous:sys-notify -u low "Submap was reset"
  else
    notify-send --app-name="$app_name" -h string:x-canonical-private-synchronous:sys-notify -u low "Submap $prev_submap off"
  fi
  hyprctl -q dispatch submap "$prev_submap"
  echo "$prev_submap" >"$XDG_RUNTIME_DIR/hypr/alttab/submap"
fi
