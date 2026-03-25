#!/usr/bin/env bash

if ! hyprctl workspaces | grep -q special:magic; then
  hyprctl dispatch movetoworkspacesilent special:magic
else
  if [[ "$1" == "--toggle" ]]; then
    # Only toggle, keeps workspace alive
    hyprctl --batch 'dispatch togglespecialworkspace magic'
  else
    # True Minimize
    hyprctl --batch 'dispatch togglespecialworkspace magic;dispatch movetoworkspace +0'
  fi
fi
