#!/usr/bin/env bash

CONFIG="$HOME/.config/hypr/wofi/config/config"
STYLE="$HOME/.config/hypr/wofi/src/mocha/style.css"

if [[ ! $(pidof wofi) ]]; then
    wofi --conf "${CONFIG}" --style "${STYLE}"
else
    pkill wofi
fi
