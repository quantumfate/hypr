#!/usr/bin/env bash

set -euo pipefail

CONFIG_DIR="$HOME/.config/hypr"

case "$(hostname)" in
quantum-laptop)
    CONFIG="$CONFIG_DIR/hyprlock-laptop.conf"
    ;;
quantum-desktop)
    CONFIG="$CONFIG_DIR/hyprlock.conf"
    ;;
*)
    echo "lock-session: unknown hostname '$(hostname)'" >&2
    exit 1
    ;;
esac

# Avoid stacking instances
pidof hyprlock || hyprlock --grace 120 -c "$CONFIG"
