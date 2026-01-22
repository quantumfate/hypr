#!/usr/bin/env bash

if [ "$(hyprctl activewindow -j | jq -r ".class")" = "Dofus.x64" ]; then
  hyprctl --batch -q "dispatch focuswindow title:Dofus $1 ; dispatch alterzorder top"
else
  hyprctl dispatch pass address:$(hyprctl activewindow -j | jq -r ".address")
fi

