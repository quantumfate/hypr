#!/usr/bin/env bash
# LEO-397: a scene's own declared gaps beat the host profile, a store edit
# reaches the desk with no `hyprctl reload`, and a reload that DOES happen
# redraws already-placed scene windows instead of leaving their geometry
# stale. Builds on 90_live_gaps.sh, which covers host-profile gaps via a
# code edit + reload; this scenario covers the two gaps that left: a bare
# store edit with no reload at all, and Hyprland's reload not relaying out a
# custom Lua layout by itself (verified against the compositor's source: see
# the issue's written evidence).
# No eval.
. "$(dirname "$0")/../lib.sh"

e2e_start
go_workspace grouped
spawn_test_window e2e-probe-a
spawn_test_window e2e-probe-b # tiled strays alongside the grouped block

STORE="$E2E_ROOT/store/hyprfocus.json"

window_xs() {
    clients | jq -c 'map(select(.class | startswith("e2e-probe"))) | sort_by(.at[0]) | map(.at[0])'
}
addr_of() { clients | jq -r --arg c "$1" '.[] | select(.class == $c) | .address'; }

XS_BEFORE=$(window_xs)
e2e_log "before: xs=$XS_BEFORE"

# --- part 1: a bare store edit, no reload -----------------------------------
# The scene's own gaps_in/gaps_out, declared directly on base.scenes.grouped
# (a field host workspace_specs never had), must win over the host profile
# and must reach the desk on the very next recalculate with NO `hyprctl
# reload` — the fix for LEO-397's "declaration edit reaches the desk with no
# restart" acceptance line.
jq '.base.scenes.grouped.gaps_in = 91
    | .base.scenes.grouped.gaps_out = {top: 5, right: 91, bottom: 91, left: 91}' \
    "$STORE" >"$STORE.tmp" && mv "$STORE.tmp" "$STORE"

# Toggle-float a window and back: a real compositor recalculate with nothing
# in the config-watcher's tracked files touched, so any movement proves the
# store edit alone reached the layout.
A=$(addr_of e2e-probe-a)
hc dispatch "hl.dsp.window.float({ window = 'address:$A' })" >/dev/null
hc dispatch "hl.dsp.window.float({ window = 'address:$A' })" >/dev/null

probes_moved() {
    local now
    now=$(window_xs)
    [[ -n $now && $now != "$XS_BEFORE" ]]
}
wait_until 50 probes_moved || e2e_fail "store-only gap edit never reached the desk (no reload): $(window_xs)"
XS_STORE_EDIT=$(window_xs)
e2e_log "after store edit (no reload): xs=$XS_STORE_EDIT"

# --- part 2: a reload must itself redraw the scene --------------------------
# Bump the scene's own gaps again and reload with NO window event in between.
# If reload only re-executes Lua without forcing a recalculate (this issue's
# core regression), the windows would sit exactly where part 1 left them
# instead of moving again for the new gap value.
jq '.base.scenes.grouped.gaps_in = 30
    | .base.scenes.grouped.gaps_out = {top: 5, right: 30, bottom: 30, left: 30}' \
    "$STORE" >"$STORE.tmp" && mv "$STORE.tmp" "$STORE"
hc reload

redrawn() {
    local now
    now=$(window_xs)
    [[ -n $now && $now != "$XS_STORE_EDIT" ]]
}
wait_until 50 redrawn || e2e_fail "reload did not redraw the scene: stuck at $(window_xs)"

e2e_log "after reload (forced redraw): xs=$(window_xs)"
e2e_log "PASS scene gaps + reload redraw"
