#!/usr/bin/env bash
if [[ "$1" == "--docked" ]]; then
    hyprctl --batch "keyword monitor eDP-1,preferred,7680x360,1 ;  keyword workspace eDP-1,1 ;"
    sleep 0.500
elif [[ "$1" == "--switch" ]]; then
    hyprctl --batch "keyword monitor eDP-1,preferred,5120,1 ; keyword workspace eDP-1,1 ;"
    sleep 0.500
elif [[ "$1" == "--uni" ]]; then
    hyprctl --batch "keyword monitor eDP-1,preferred,300x1440,1 ; keyword workspace eDP-1,1 ; keyword workspace DP-2,2 ; keyword workspace HDMI-A-1,3"
    sleep 0.500
elif [[ "$1" == "--undocked" ]]; then
    hyprctl --batch "keyword monitor eDP-1,preferred,0x0,1 ; keyword workspace eDP-1,1 ; keyword workspace eDP-1,2 ; keyword workspace eDP-1,3 ; keyword workspace eDP-1,4"
    sleep 0.500
    hyprctl --batch "dispatch workspace 2" # Makes sure the next workspace is properly targeted
    hyprctl --batch "dispatch workspace 3 ; dispatch layoutmsg orientationleft"
    hyprctl --batch "dispatch workspace 2" # Makes sure the next workspace is properly targeted
    hyprctl --batch "dispatch workspace 4 ; dispatch layoutmsg orientationleft"
    hyprctl --batch "dispatch workspace 2" # Makes sure the next workspace is properly targeted
else
    echo -e "Available Options : --docked, --undocked, --uni"
fi

exit 0
