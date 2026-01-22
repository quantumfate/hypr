#!/usr/bin/env bash
APP_NAME=pavucontrol

# Get Volume
get_volume() {
  volume=$(pamixer --get-volume)
  echo "$volume"
}

get_icon() {
  current=$(get_volume)
  if [[ "$current" -eq "0" ]]; then
    echo ""
  elif [[ ("$current" -ge "0") && ("$current" -le "30") ]]; then
    echo ""
  elif [[ ("$current" -ge "30") && ("$current" -le "60") ]]; then
    echo ""
  elif [[ ("$current" -ge "60") && ("$current" -le "100") ]]; then
    echo ""
  fi
}

# Notify
notify_user() {
  notify-send --app-name=$APP_NAME -h string:x-canonical-private-synchronous:sys-notify -u low "$(get_icon)   $(get_volume)%"
}

# Increase Volume
inc_volume() {
  pamixer -i 5 && notify_user
}

# Decrease Volume
dec_volume() {
  pamixer -d 5 && notify_user
}

# Toggle Mute
toggle_mute() {
  if [ "$(pamixer --get-mute)" == "false" ]; then
    pamixer -m && notify-send --app-name=$APP_NAME -h string:x-canonical-private-synchronous:sys-notify -u low -i "" "Volume Switched OFF"
  elif [ "$(pamixer --get-mute)" == "true" ]; then
    pamixer -u && notify-send --app-name=$APP_NAME -h string:x-canonical-private-synchronous:sys-notify -u low -i "$(get_icon)" "Volume Switched ON"
  fi
}

# Toggle Mic
toggle_mic() {
  if [ "$(pamixer --source 66 --get-mute)" == "false" ]; then
    pamixer -m --source 66 && notify-send --app-name=$APP_NAME -h string:x-canonical-private-synchronous:sys-notify -u low -i "" "Microphone Switched OFF"
  elif [ "$(pamixer --source 66 --get-mute)" == "true" ]; then
    pamixer -u --source 66 && notify-send --app-name=$APP_NAME -h string:x-canonical-private-synchronous:sys-notify -u low -i "" "Microphone Switched ON"
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

