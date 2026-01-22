#!/usr/bin/env bash

if [ "$(hyprctl activewindow -j | jq -r ".class")" = "Dofus.x64" ]; then
  "${XDG_CONFIG_HOME}/hypr/scripts/dofusclick.sh" $@
else
  hyprctl dispatch pass address:$(hyprctl activewindow -j | jq -r ".address")
fi
