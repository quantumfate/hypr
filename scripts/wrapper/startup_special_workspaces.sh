#!/usr/bin/env bash

# Map applications to their window classes, workspace names, and sleep timers
declare -A app_config=(
  ["keepassxc"]="keepassxc:keepassxc:3"
  ["spotify"]="Spotify:spotify:3"
  ["vesktop"]="vesktop:vesktop:12"
  ["proton-pass"]="Proton Pass:proton:12"
  ["proton-mail"]="proton-mail-bridge:proton:12"
)

for app in "${!app_config[@]}"; do
  (
    IFS=':' read -r window_class workspace sleeptimer <<<"${app_config[$app]}"

    # Enable silent workspace rule, disable normal workspace rule
    hyprctl keyword "windowrule[workspace-silent-${workspace}]:enable" true
    hyprctl keyword "windowrule[workspace-${workspace}]:enable" false

    sleep 0.5

    $app &
    app_pid=$!

    # Wait for the app to start and window to be created
    sleep "$sleeptimer"

    # Disable silent workspace rule, enable normal workspace rule
    hyprctl keyword "windowrule[workspace-silent-${workspace}]:enable" false
    hyprctl keyword "windowrule[workspace-${workspace}]:enable" true

  ) &
done
