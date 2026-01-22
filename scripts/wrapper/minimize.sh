#!/usr/bin/env bash

if [ "$(hyprctl activewindow -j | jq -r ".class")" = "steam" ]; then
  xdotool getactivewindow windowunmap
else
  hyprctl dispatch killactive ""
fi

