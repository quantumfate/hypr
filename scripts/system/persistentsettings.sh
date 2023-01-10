#!/usr/bin/env bash

set_monitor(){
   echo "monitor=$1" >> "$SESSION_HYPR_SETTINGS_DIR"/"$SESSION_HYPR_SETTINGS_MONITOR" 
}

set_workspace(){

   echo "workspace=$1" >> "$SESSION_HYPR_SETTINGS_DIR"/"$SESSION_HYPR_SETTINGS_MONITOR" 
}

if [[ "$1" == "--monitor" ]]; then
    shift
	set_monitor "$@"
elif [[ "$1" == "--workspace" ]]; then
    shift
    set_workspace "$@"
else
	echo -e "Available Options : --monitors, --worspace"
fi

exit 0