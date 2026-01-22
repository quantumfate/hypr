#!/usr/bin/env bash
line="$1"

IFS=$'\t' read -r addr _ <<<"$line"
dim=${FZF_PREVIEW_COLUMNS}x${FZF_PREVIEW_LINES}

grim -t png -l 0 -w "$addr" $XDG_RUNTIME_DIR/hypr/alttab/preview.png
chafa --animate false --dither=none -s "$dim" "$XDG_RUNTIME_DIR/hypr/alttab/preview.png"
