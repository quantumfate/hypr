#!/usr/bin/env bash
source ~/.zsh/catppuccin-fzf/themes/catppuccin-fzf-macchiato.sh
hyprctl -q dispatch submap alttab
start=$1
filter=${2:-"| select(.class != \"Dofus.x64\")"}
submap=$(cat "$XDG_RUNTIME_DIR/hypr/alttab/submap" 2>/dev/null || echo "reset")

address=$(hyprctl -j clients | jq -r "sort_by(.focusHistoryID) | .[] | select(.workspace.id >= 0) ${filter} | \"\(.address)\t\(.title)\"" |
  fzf --color prompt:green,pointer:green,current-bg:-1,current-fg:green,gutter:-1,border:bright-black,current-hl:red,hl:red \
    --cycle \
    --sync \
    --bind tab:down,shift-tab:up,start:$start,double-click:ignore \
    --wrap \
    --delimiter=$'\t' \
    --with-nth=2 \
    --preview "$XDG_CONFIG_HOME/hypr/scripts/alttab/preview.sh {}" \
    --preview-window=down:80%,border-none \
    --layout=reverse |
  awk -F"\t" '{print $1}')

if [ -n "$address" ]; then
  echo "$address" >$XDG_RUNTIME_DIR/hypr/alttab/address
fi

hyprctl -q dispatch submap $submap
