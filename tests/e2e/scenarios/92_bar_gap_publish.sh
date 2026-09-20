#!/usr/bin/env bash
# The bar's opt-in gap (`bar_follows_scene_gaps`) is the distance from the
# monitor edge to the scene's outermost VISIBLE window, not just the layout's
# own gap: `hypr/lib/geometry.lua`'s `resolved_gaps` folds in the workspace
# rule's `gaps_out` (which the compositor takes out of `ctx.area` before the
# layout runs) plus the rule's `gaps_in` and the window border on every side
# the layout did not leave flush. conf/host.lua publishes that map at build();
# hypr/scene/spec.lua re-publishes it when a scene edit is first re-read.
#
# Asserted as a DELTA across a runtime scene edit with NO reload, so it holds
# whatever the e2e host's profile numbers are: only the scene's declared left
# gap changes, so the published inset must move by exactly that much. A store
# that still held the raw ladder would not move when only the scene gap moved
# relative to the workspace rule's own gaps_out; a publish that only happened
# at build() would not move at all here (no `hyprctl reload` below).
# No eval.
. "$(dirname "$0")/../lib.sh"

e2e_start
go_workspace grouped
spawn_test_window e2e-probe-a

STORE="$E2E_ROOT/store/hyprfocus.json"
GAPS="$E2E_ROOT/store/geometry.json"

published_left() { jq -r '.workspaces.grouped.left // empty' "$GAPS" 2>/dev/null; }

changed_from() {
    local now
    now=$(published_left)
    [[ -n $now && $now != "$1" ]]
}

set_scene_left() {
    jq --argjson v "$1" '.base.scenes.grouped.gaps_out = { top: 12, right: 0, bottom: 64, left: $v }' \
        "$STORE" >"$STORE.tmp" && mv "$STORE.tmp" "$STORE"
}

# A real compositor recalculate with nothing in the config-watcher's tracked
# files touched: a store edit alone must reach both the layout and the
# published map, exactly as 91_scene_gaps_reload.sh proves for the layout.
recalc() {
    local a
    a=$(clients | jq -r '.[] | select(.class == "e2e-probe-a") | .address')
    hc dispatch "hl.dsp.window.float({ window = 'address:$a' })" >/dev/null
    hc dispatch "hl.dsp.window.float({ window = 'address:$a' })" >/dev/null
}

wait_until 50 sh -c "jq -e '.workspaces.grouped.left' '$GAPS' >/dev/null 2>&1" ||
    e2e_fail "conf/host.lua never published workspaces.grouped ($GAPS)"
BUILT=$(published_left)
e2e_log "build(): workspaces.grouped.left=$BUILT"

set_scene_left 120
recalc
wait_until 50 changed_from "$BUILT" ||
    e2e_fail "a scene gap edit never re-published workspaces.grouped (left still $BUILT)"
FIRST=$(published_left)
e2e_log "scene gaps_out.left=120: published left=$FIRST"

# The store mtime is the engine's memoization key; leave the clock between edits.
sleep 1
DELTA=152
set_scene_left $((120 + DELTA))
recalc
wait_until 50 changed_from "$FIRST" ||
    e2e_fail "the second scene gap edit never re-published workspaces.grouped (left still $FIRST)"
SECOND=$(published_left)

assert_eq "$((SECOND - FIRST))" "$DELTA" \
    "published inset did not follow the scene's declared gap (left $FIRST -> $SECOND)"
e2e_log "PASS bar gap publish: left $FIRST -> $SECOND on a +${DELTA} scene gap, no reload"
