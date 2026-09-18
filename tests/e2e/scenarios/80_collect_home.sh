#!/usr/bin/env bash
# LEO-353: a window claimed by one scene's block, opened on another scene's
# workspace, is re-homed there address-targeted — no focus dance, and the
# user's focus does not follow it. `work` (the default mode) admits `loose`
# (claims e2e-tile) and `aside` (claims e2e-aside); both are the active
# scenes here. No eval: `work` is already applied at boot.
. "$(dirname "$0")/../lib.sh"

e2e_start
go_workspace aside
spawn_test_window e2e-tile

on_loose() { client_of e2e-tile | jq -e '.workspace.name == "loose"' >/dev/null; }
wait_until 50 on_loose || e2e_fail "e2e-tile never moved to loose: $(client_of e2e-tile | jq -c '{workspace}')"

focused_stayed() { hc -j activeworkspace | jq -e '.name == "aside"' >/dev/null; }
focused_stayed || e2e_fail "focus followed the re-homed window: $(hc -j activeworkspace | jq -c .)"

e2e_log "PASS collect home"
