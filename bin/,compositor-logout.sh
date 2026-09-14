#!/bin/bash

set -euo pipefail
VT=${VT:-1}

if [ "$XDG_SESSION_TYPE" = "x11" ]; then
    # X11 logout logic here
    exit 0
fi

# Wayland: schedule VT switch as safety net for NVIDIA
# sudo systemd-run --no-block sh -c "sleep 6 && chvt $VT" // not needed atm
uwsm stop
