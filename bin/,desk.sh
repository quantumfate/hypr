#!/usr/bin/env bash
# The monitor-scoped workspace switch, for callers outside the compositor (the
# bar's workspace dots, the workspace switcher). The logic lives in
# hypr/lib/desk.lua; this only carries the request across.
#
#   ,desk.sh switch <monitor> <scene>   show <scene> on <monitor>, keyboard there
#   ,desk.sh send <monitor> <scene>     move the focused window there, following
#
# A scene the active mode does not place on <monitor> is refused: nothing
# moves. (`hyprctl eval` answers only "ok", so the refusal is not reported
# back; a Lua error is, with exit status 1.)
set -euo pipefail

usage() {
    sed -n '2,11p' "$0" | sed 's/^# \{0,1\}//'
    exit 2
}

[[ $# -eq 3 ]] || usage
verb=$1 monitor=$2 scene=$3
case $verb in switch | send) ;; *) usage ;; esac
# Both names are spliced into Lua source: only the characters monitor and
# scene names are made of get through.
for arg in "$monitor" "$scene"; do
    [[ $arg =~ ^[A-Za-z0-9._-]+$ ]] || {
        echo ",desk.sh: refusing name '$arg'" >&2
        exit 2
    }
done

out=$(hyprctl eval "require('hypr.lib.desk').$verb('$monitor', '$scene')" 2>&1) || {
    echo ",desk.sh: $out" >&2
    exit 1
}
