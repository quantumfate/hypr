#!/usr/bin/env bash

APP_NAME="IPC Wrapper"
SCRIPTDIR=${XDG_CONFIG_HOME}/hypr/scripts
IPC_SCRIPTDIR=${SCRIPTDIR}/IPC

handle_based_on_class() {
  # Replacing first occurence of , with ~ because that character will probably
  # never be in a video title - or else splitting may break the logic
  window_address="0x$(cut -d '~' -f1 <<<$(cut -d '>' -f3 <<<"${1/,/\~}"))"
  window_title="$(cut -d '~' -f2 <<<$(cut -d '>' -f3 <<<"${1/,/\~}"))"
  class=$(hyprctl -j clients | jq -r " .[] | select(.address == \"$window_address\") | \"\(.initialClass)\"")

  case "$class" in
  $BROWSER)
    "${IPC_SCRIPTDIR}/zen_opacity_switch.sh" "$window_address" "$window_title"
    ;;
  esac
}

handle() {
  case "$1" in
  windowtitlev2*)
    handle_based_on_class "$1"
    ;;
  esac
}

socat -U - UNIX-CONNECT:$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket2.sock | while read -r line; do handle "$line"; done
