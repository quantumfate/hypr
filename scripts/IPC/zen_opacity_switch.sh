#!/usr/bin/env bash
window_address=$1
window_title=$2

case "$window_title" in
*Crunchyroll* | *YouTube* | *Twitch*)
  hyprctl keyword 'windowrule[opaque-default-browser]:enable true'
  hyprctl keyword 'windowrule[opaque-media-browser]:enable true'
  ;;
*)
  hyprctl keyword 'windowrule[opaque-default-browser]:enable false'
  hyprctl keyword 'windowrule[opaque-media-browser]:enable false'
  ;;
esac
