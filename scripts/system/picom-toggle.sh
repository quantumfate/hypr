#!/usr/bin/env bash
if pgrep -x "picom" > /dev/null
then
	killall picom
else
	picom -b --config ~/.config/hypr/picom.conf
fi
