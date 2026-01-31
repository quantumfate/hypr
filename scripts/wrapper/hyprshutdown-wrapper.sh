#!/usr/bin/env bash

if [[ $1 == "--shutdown" ]]; then
  exec hyprshutdown -t 'Shutting down...' --post-cmd 'shutdown -P 0'
elif [[ $1 == "--reboot" ]]; then
  exec hyprshutdown -t 'Restarting...' --post-cmd 'reboot'
elif [[ $1 == "--logout" ]]; then
  exec hyprshutdown -t 'Logging out...'
else
  exec hyprshutdown "$@"
fi
