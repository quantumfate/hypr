#!/usr/bin/env bash

set -euo pipefail
APP_NAME=Brightness
has_hyprsunset=false
CACHE_DIR="/tmp/hyprsunset"
CACHE_FILE="$CACHE_DIR/brightness"

mkdir -p "$CACHE_DIR"

if [[ "${XDG_CURRENT_DESKTOP:-}" == "Hyprland" ]] && command -v hyprsunset &>/dev/null; then
    has_hyprsunset=true
fi

get_brightness() {
    if [ "$has_hyprsunset" = true ]; then
        hyprctl hyprsunset gamma | cut -d. -f1
    else
        echo $(($(brightnessctl g) * 100 / $(brightnessctl m)))
    fi
}

get_icon() {
    current=$(get_brightness)
    if [[ "$current" -eq "0" ]]; then
        echo "󰃞 "
    elif [[ ("$current" -ge "0") && ("$current" -le "30") ]]; then
        echo "󰃝 "
    elif [[ ("$current" -ge "30") && ("$current" -le "60") ]]; then
        echo "󰃟 "
    elif [[ ("$current" -ge "60") && ("$current" -le "100") ]]; then
        echo "󰃠 "
    fi
}

save_brightness() {
    get_brightness >"$CACHE_FILE"
}

notify_user() {
    notify-send --app-name="$APP_NAME" -h string:x-canonical-private-synchronous:sys-notify -u low "$(get_icon)   $(get_brightness)%"
}

inc_brightness() {
    if [ "$has_hyprsunset" = true ]; then
        hyprctl hyprsunset gamma +5
    else
        brightnessctl s +5%
    fi
    save_brightness
    notify_user
}

dec_brightness() {
    if [ "$has_hyprsunset" = true ]; then
        hyprctl hyprsunset gamma -5
    else
        brightnessctl s 5%-
    fi
    save_brightness
    notify_user
}

set_brightness() {
    save_brightness
    if [ "$has_hyprsunset" = true ]; then
        hyprctl hyprsunset gamma "$1"
    else
        brightnessctl -s "$1"
    fi
    notify_user
}

restore_brightness() {
    if [ "$has_hyprsunset" = true ]; then
        if [[ -f "$CACHE_FILE" ]]; then
            hyprctl hyprsunset gamma "$(cat "$CACHE_FILE")"
        else
            hyprctl hyprsunset gamma 100
        fi
    else
        brightnessctl -r
    fi
}
case "${1:-}" in
--get) get_brightness ;;
--inc) inc_brightness ;;
--dec) dec_brightness ;;
--set) set_brightness "$2" ;;
--get-with-icon) echo "$(get_brightness)  $(get_icon) " ;;
-r) restore_brightness ;;
-s) save_brightness ;;
*) get_brightness ;;
esac
