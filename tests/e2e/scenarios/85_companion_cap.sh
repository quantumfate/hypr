#!/usr/bin/env bash
# LEO-411: a scene member's companion spawns are capped at the block's
# declared max_spawns. The fixture "spawner" scene mirrors dofus — a group
# member whose spawn class is also its second tile — so each spawned
# companion's own window.open re-converges the scene and the cap fills one
# spawn per convergence. Asserts: the cap fills to exactly max_spawns, a
# burst of member events does not overshoot, a hand-opened excess is neither
# grown nor closed while a member stands, and the last member leaving closes
# every companion. No eval.
. "$(dirname "$0")/../lib.sh"

e2e_start
go_workspace spawner

companion_count() {
    clients | jq '[.[] | select(.class == "e2e-companion")] | length'
}
member_count() {
    clients | jq '[.[] | select(.class == "e2e-member")] | length'
}

spawn_test_window e2e-member

# The first member maps -> one companion spawns; each spawned companion's own
# open re-converges, so the cap fills to exactly 3, one at a time.
at_cap() { test "$(companion_count)" -eq 3; }
wait_until 200 at_cap || e2e_fail "cap never filled to exactly 3: $(companion_count)"

# A burst of repeated events (a second member mapping) must not overshoot:
# the count is derived and the in-flight marker admits one spawn at a time.
spawn_test_window e2e-member
wait_until 50 at_cap || e2e_fail "burst overshot the cap: $(companion_count)"

# A hand-opened extra window takes the count above the cap. Live member
# events while above it (a third member opening) must make the engine neither
# spawn a fifth nor close what it did not spawn.
spawn_test_window e2e-companion
spawn_test_window e2e-member
above_cap() { test "$(companion_count)" -eq 4; }
wait_until 50 above_cap || e2e_fail "hand-opened excess vanished: $(companion_count)"

# The last member leaving closes every companion of the block, whatever the
# cap — including the hand-opened fourth. Closes are retried, addresses
# recomputed each pass, the same way 95_project_group closes (a fresh close
# request can miss while the compositor settles the previous one).
close_all_members() {
    local a
    for a in $(clients | jq -r '.[] | select(.class == "e2e-member") | .address'); do
        hc dispatch "hl.dsp.window.close(\"address:$a\")" >/dev/null
    done
    test "$(member_count)" -eq 0
}
wait_until 50 close_all_members || e2e_fail "members outlived closing all of them: $(member_count)"
all_closed() { test "$(companion_count)" -eq 0; }
wait_until 100 all_closed || e2e_fail "companions did not close with the last member: $(companion_count)"

e2e_log "PASS companion cap"
