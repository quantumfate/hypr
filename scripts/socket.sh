#!/bin/bash

function handle {
  if [[ ${1:0:12} == "monitoradded" ]]; then
    echo ""
  fi
}

socat - UNIX-CONNECT:/tmp/hypr/"$HYPRLAND_INSTANCE_SIGNATURE"/.socket2.sock | while read line; do handle "$line"; done