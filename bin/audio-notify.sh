#!/usr/bin/env bash
set -euo pipefail

APP_NAME="audio-device"

get_default_sink_id() {
    wpctl status 2>/dev/null |
        LC_ALL=C tr -cd '[:print:]\n' |
        awk '/Sinks:/,/Sources:/' |
        grep '^\s*\*' |
        head -1 |
        sed 's/[^0-9]*//; s/[^0-9].*//'
}

get_description() {
    wpctl inspect "$1" 2>/dev/null |
        awk -F'"' '/node.description/{print $2; exit}'
}

get_label() {
    local id
    id=$(get_default_sink_id)
    if [[ -n "$id" ]]; then
        get_description "$id"
    else
        echo "unknown"
    fi
}

current_label=$(get_label)

pactl subscribe 2>/dev/null | while read -r line; do
    case "$line" in
    *"on sink "*)
        sleep 0.5
        new_label=$(get_label)
        if [[ -n "$new_label" && "$new_label" != "$current_label" ]]; then
            notify-send -i audio-card -t 3000 "$APP_NAME" "Switched to $new_label"
            current_label="$new_label"
        fi
        ;;
    esac
done
