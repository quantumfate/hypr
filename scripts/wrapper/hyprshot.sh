#!/usr/bin/env bash

if [[ "$1" == "--region" ]]; then
  hyprshot -m region
elif [[ "$1" == "--output" ]]; then
  hyprshot --mode output --mode $(hyprctl -j monitors | jq -r '.[] | select(.focused) | "\(.name)"')
elif [[ "$1" == "--window" ]]; then
  hyprshot -m window
else
  hyprshot "$@"
fi

