#!/usr/bin/env bash
# A strays = "float" scene floats a window whose class matches no block, and
# leaves a block member tiled. No eval.
. "$(dirname "$0")/../lib.sh"

e2e_start
go_workspace loose
spawn_test_window e2e-tile
spawn_test_window e2e-stray

is_floating() { client_of "$1" | jq -e '.floating == true' >/dev/null; }
wait_until 50 is_floating e2e-stray || e2e_fail "stray e2e-stray did not float: $(client_of e2e-stray)"
assert_eq "$(client_of e2e-tile | jq -r .floating)" false "block member e2e-tile floating"
e2e_log "PASS float strays"
