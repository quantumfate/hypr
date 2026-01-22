#!/usr/bin/env bash
mkdir -p $XDG_RUNTIME_DIR/hypr/alttab
hyprctl -q --batch "keyword animations:enabled false; keyword unbind ALT, TAB ; keyword unbind ALT SHIFT, TAB"

if [ "$(hyprctl activewindow -j | jq -r ".class")" = "Dofus.x64" ]; then
  footclient -a alttab ~/.config/hypr/scripts/alttab/alttab.sh $1 "| select(.class == \"Dofus.x64\" or (.class == \"Ankama Launcher\" and .title == \"overlay\"))" "cra_team"
else
  footclient -a alttab ~/.config/hypr/scripts/alttab/alttab.sh $1
fi

hyprctl --batch -q "dispatch focuswindow address:$(cat $XDG_RUNTIME_DIR/hypr/alttab/address) ; dispatch alterzorder top"
