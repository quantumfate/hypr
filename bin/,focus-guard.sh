#!/usr/bin/env bash
# Firm focus-mode gate for launchers: refuses to START a blocked kind, never
# touches anything already running (a launcher calls this before it execs;
# a running game/browser has already passed the gate and is none of our
# business). Fails OPEN if the shell isn't reachable — a broken IPC socket
# should not lock the desk down.
set -euo pipefail

kind=${1:?usage: ,focus-guard.sh <media|game>}
result=$(qs -c quantumfate ipc call -- focus canLaunch "$kind" 2>/dev/null) || result=yes

if [[ "$result" == yes ]]; then
    exit 0
fi

reason=${result#no: }
notify-send "Blocked" "$reason"
echo "$reason" >&2
exit 1
