#!/usr/bin/env bash
# Live: the "bump" — switching workspaces makes the tiles jump vertically and
# the bar ride along.
#
# The suspected mechanism is a RESERVATION FLIP, not an animation. The bar is
# two layer surfaces: a full-screen overlay and a thin reserve strip, and
# exactly one of them holds `exclusiveZone: Theme.barReserved` at a time —
# which one depends on `docked`, i.e. on whether this screen currently has a
# published dock the desk placed. That document is republished per layout pass
# and swept when a monitor's workspace stops declaring docks, so a swap
# between a scene that docks and one that does not hands the reservation from
# one surface to the other. Two surfaces, two commits: the usable area moves
# in between, the tiles move with it, and the isles — which follow the
# published tile geometry — move again after that.
#
# This measures it: tile geometry on a docking scene, before and after a round
# trip through a scene that publishes no docks.
E2E_REAL_BAR=1
. "$(dirname "$0")/../lib.sh"

e2e_start
bar_start WAYLAND-1
go_workspace code-deck
spawn_test_window e2e-proj-alpha-a
spawn_test_window e2e-browser

tile_y() { clients | jq -r '[.[] | select(.class == "e2e-proj-alpha-a") | .at[1]] | first // "none"'; }
docked_ids() { jq -r '[.docks // {} | .[] | to_entries[] | select(.value.state == "docked") | .key] | join(",")' "$QF_STORE/geometry.json" 2>/dev/null || echo ""; }

wait_until 200 sh -c '[ -n "$(jq -r "[.docks // {} | .[] | to_entries[] | select(.value.state == \"docked\")] | length" "$QF_STORE/geometry.json" 2>/dev/null)" ]' || true
sleep 1.5
BEFORE=$(tile_y)
e2e_log "code-deck: tile y=$BEFORE docked=[$(docked_ids)]"

# `loose` declares no docks at all, so this screen's map is swept while it is
# there: the reservation changes hands.
go_workspace loose
sleep 1.2
e2e_log "loose: docked=[$(docked_ids)]"
go_workspace code-deck
sleep 1.5
AFTER=$(tile_y)
e2e_log "code-deck again: tile y=$AFTER docked=[$(docked_ids)]"

[ "$BEFORE" = "$AFTER" ] ||
    e2e_fail "the tile moved across a workspace round trip: y=$BEFORE -> y=$AFTER (the reservation changed hands)"
e2e_log "PASS: a workspace round trip leaves the tiling where it was"
