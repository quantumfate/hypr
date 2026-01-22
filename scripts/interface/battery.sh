#!/usr/bin/env bash

############ Variables ############
enable_battery=false
battery_charging=false

####### Check availability ########
for battery in /sys/class/power_supply/*BAT*; do
  if [[ -f "$battery/uevent" ]]; then
    enable_battery=true
    if [[ $(cat /sys/class/power_supply/*/status | head -1) == "Charging" ]]; then
      battery_charging=true
    fi
    break
  fi
done

############# Output #############
if [[ $enable_battery == true ]]; then

  capacity=$(cat /sys/class/power_supply/*/capacity | head -1)

  if [ "$capacity" -eq 100 ]; then
    echo -n "$capacity% "
  elif [ "$capacity" -gt 74 ]; then
    echo -n "$capacity% "
  elif [ "$capacity" -gt 49 ]; then
    echo -n "$capacity% "
  elif [ "$capacity" -gt 24 ]; then
    echo -n "$capacity% "
  else
    echo -n "$capacity% "
  fi

  if [[ $battery_charging == false ]]; then
    echo -n "   remaining"
  else
    echo -n "   charging"
  fi
fi

echo ''
