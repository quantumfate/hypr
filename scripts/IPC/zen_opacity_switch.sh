#!/usr/bin/env bash
window_address=$1
window_title=$2

case "$window_title" in
*Crunchyroll* | *YouTube* | *Twitch*)
  hyprctl keyword 'windowrule[opaque-zen-browser]:enable true'
  ;;
*)
  hyprctl keyword 'windowrule[opaque-zen-browser]:enable false'
  ;;
esac
