#!/usr/bin/env bash
APP_NAME=pavucontrol
SINK="@DEFAULT_AUDIO_SINK@"
SOURCE="@DEFAULT_AUDIO_SOURCE@"
STEP="3%"
LIMIT="1.0"

# Get Volume (0-100 integer)
get_volume() {
    wpctl get-volume "$SINK" | awk '{printf "%d", $2 * 100}'
}

# Mute state: "true" or "false"
get_mute() {
    if wpctl get-volume "$SINK" | grep -q '\[MUTED\]'; then
        echo "true"
    else
        echo "false"
    fi
}

get_mic_mute() {
    if wpctl get-volume "$SOURCE" | grep -q '\[MUTED\]'; then
        echo "true"
    else
        echo "false"
    fi
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
notify_user() {
    notify-send --app-name=$APP_NAME -h string:x-canonical-private-synchronous:sys-notify -u low "$(get_icon)   $(get_volume)%"
}

# Increase Volume
inc_volume() {
    wpctl set-volume -l "$LIMIT" "$SINK" "${STEP}+" && notify_user
}

# Decrease Volume
dec_volume() {
    wpctl set-volume -l "$LIMIT" "$SINK" "${STEP}-" && notify_user
}

# Toggle Mute
toggle_mute() {
    if [ "$(get_mute)" == "false" ]; then
        wpctl set-mute "$SINK" toggle && notify-send --app-name=$APP_NAME -h string:x-canonical-private-synchronous:sys-notify -u low -i "" "Volume Switched OFF"
    elif [ "$(get_mute)" == "true" ]; then
        wpctl set-mute "$SINK" toggle && notify-send --app-name=$APP_NAME -h string:x-canonical-private-synchronous:sys-notify -u low -i "$(get_icon)" "Volume Switched ON"
    fi
}

# Toggle Mic
toggle_mic() {
    if [ "$(get_mic_mute)" == "false" ]; then
        wpctl set-mute "$SOURCE" toggle && notify-send --app-name=$APP_NAME -h string:x-canonical-private-synchronous:sys-notify -u low -i "" "Microphone Switched OFF"
    elif [ "$(get_mic_mute)" == "true" ]; then
        wpctl set-mute "$SOURCE" toggle && notify-send --app-name=$APP_NAME -h string:x-canonical-private-synchronous:sys-notify -u low -i "" "Microphone Switched ON"
    fi
}

# Execute accordingly
if [[ "$1" == "--get" ]]; then
    get_volume
elif [[ "$1" == "--inc" ]]; then
    inc_volume
elif [[ "$1" == "--dec" ]]; then
    dec_volume
elif [[ "$1" == "--toggle" ]]; then
    toggle_mute
elif [[ "$1" == "--toggle-mic" ]]; then
    toggle_mic
else
    get_volume
fi
