#!/usr/bin/env bash

APP_NAME=brightnessctl

# Get Volume
get_brightness() {
  echo $(($(brightnessctl g) * 100 / $(brightnessctl m)))
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
  notify-send --app-name=$APP_NAME -h string:x-canonical-private-synchronous:sys-notify -u low "Brightness: $(get_brightness)%"
}

# Increase Volume
inc_brightness() {
  brightnessctl s +10% && notify_user
}

# Decrease Volume
dec_brightness() {
  brightnessctl s 10%- && notify_user
}

# Execute accordingly
if [[ "$1" == "--get" ]]; then
  get_brightness
elif [[ "$1" == "--inc" ]]; then
  inc_brightness
elif [[ "$1" == "--dec" ]]; then
  dec_brightness
else
  get_brightness
fi

