#!/usr/bin/env bash
# LEO-353: a window claimed by one scene's block, opened on another scene's
# workspace, is re-homed there address-targeted — no focus dance, and the
# user's focus does not follow it. `work` (the default mode) admits `loose`
# (claims e2e-tile, strays = "float") and `aside` (claims e2e-aside,
# strays = "slot"); both are the active scenes here. No eval: `work` is
# already applied at boot. Also covers the float-strays case: a window
# claimed by `aside` that opens on `loose`'s workspace must not be caught by
# `loose`'s own stray-float path and must land tiled, not floating, on
# `aside`.
. "$(dirname "$0")/../lib.sh"

e2e_start
go_workspace aside
spawn_test_window e2e-tile

on_loose() { client_of e2e-tile | jq -e '.workspace.name == "loose"' >/dev/null; }
wait_until 50 on_loose || e2e_fail "e2e-tile never moved to loose: $(client_of e2e-tile | jq -c '{workspace}')"

focused_stayed() { hc -j activeworkspace | jq -e '.name == "aside"' >/dev/null; }
focused_stayed || e2e_fail "focus followed the re-homed window: $(hc -j activeworkspace | jq -c .)"

# A window claimed by `aside` that opens on `loose` (a `strays = "float"`
# scene claiming only e2e-tile) must end up tiled on `aside`, not floating.
# `loose`'s own stray-float path must never float it on the way, and
# re-homing must clear a float it inherits either way.
go_workspace loose
spawn_test_window e2e-aside

on_aside() { client_of e2e-aside | jq -e '.workspace.name == "aside"' >/dev/null; }
wait_until 50 on_aside || e2e_fail "e2e-aside never moved to aside: $(client_of e2e-aside | jq -c '{workspace}')"

ended_tiled() { client_of e2e-aside | jq -e '.floating == false' >/dev/null; }
ended_tiled || e2e_fail "e2e-aside is floating on its own scene: $(client_of e2e-aside | jq -c '{floating}')"

e2e_log "PASS collect home"
