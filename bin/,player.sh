#!/usr/bin/env bash
STEP="0.03"

# Get Volume (0-100 integer)
get_volume() {
    playerctl volume 2>/dev/null | awk '{printf "%d", $1 * 100}'
}

get_track() {
    playerctl metadata --format '{{ title }} — {{ artist }}' 2>/dev/null
}

get_icon() {
    current=$(get_volume)
    if [[ "$current" -eq "0" ]]; then
        echo "󰝟 "
    elif [[ ("$current" -ge "0") && ("$current" -le "30") ]]; then
        echo " "
    elif [[ ("$current" -ge "30") && ("$current" -le "60") ]]; then
        echo "  "
    elif [[ ("$current" -ge "60") && ("$current" -le "100") ]]; then
        echo " "
    fi
}

# Notify
notify_volume() {
    ,notify player -u low "$(get_icon)   $(get_volume)% — Player"
}

notify_track() {
    ,notify player -u low "$(get_track)"
}

# Increase Volume
inc_volume() {
    playerctl volume "${STEP}+" && notify_volume
}

# Decrease Volume
dec_volume() {
    playerctl volume "${STEP}-" && notify_volume
}

# Toggle play/pause
play_pause() {
    playerctl play-pause
    status=$(playerctl status 2>/dev/null)
    if [[ "$status" == "Playing" ]]; then
        icon=""
    else
        icon=""
    fi
    ,notify player -u low "$icon  $status" "$(get_track)"
}

# Previous track
prev_track() {
    playerctl previous && sleep 0.1 && ,notify player -u low "  Previous" "$(get_track)"
}

# Next track
next_track() {
    playerctl next && sleep 0.1 && ,notify player -u low "  Next" "$(get_track)"
}

# Execute accordingly
if [[ "$1" == "--get" ]]; then
    get_volume
elif [[ "$1" == "--inc" ]]; then
    inc_volume
elif [[ "$1" == "--dec" ]]; then
    dec_volume
elif [[ "$1" == "--track" ]]; then
    get_track
elif [[ "$1" == "--play-pause" ]]; then
    play_pause
elif [[ "$1" == "--prev" ]]; then
    prev_track
elif [[ "$1" == "--next" ]]; then
    next_track
else
    get_volume
fi
