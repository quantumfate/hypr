#!/usr/bin/env bash

# The case branches below name helpers (iterate_windows.sh, do.sh,
# processFn.sh) that are gone from the desk; only the fall-through passthrough
# runs, so a global chord reaches the game window untouched. Kept until the
# keybind that calls this is retired or rewired to dofus_swap.py.
PIONEERS=("Reminiscer" "Sayer" "Rejecter" "Draintouch" "Traumafactory" "Memoryfracture" "Dissipate" "Miserymaker")

# Resolve --pioneer flag
args=()
for arg in "$@"; do
  if [[ "$arg" == "--pioneer" ]]; then
    args+=("${PIONEERS[@]}")
  else
    args+=("$arg")
  fi
done
set -- "${args[@]}"

if [ "$(hyprctl activewindow -j | jq -r ".class")" = "Dofus.x64" ]; then
  case "$1" in
  --up)
    shift
    "$SCRIPT_DIR/codeberg/quantumfate/dofus-scripts/iterate_windows.sh" --reversed --characters "$@"
    ;;
  --down)
    shift
    "$SCRIPT_DIR/codeberg/quantumfate/dofus-scripts/iterate_windows.sh" --characters "$@"
    ;;
  --press)
    shift
    "$SCRIPT_DIR/codeberg/quantumfate/dofus-scripts/do.sh" --main Miserymaker --characters "$@"
    ;;
  --activate)
    shift
    "$SCRIPT_DIR/codeberg/quantumfate/dofus-scripts/processFn.sh" "${PIONEERS[$1]}"
    ;;

  esac
else
  addr=$(hyprctl activewindow -j | jq -r ".address")
  hyprctl dispatch "hl.dsp.pass({ window = [[address:$addr]] })"
fi
