#!/usr/bin/env bash
# LEO-412: a claimed launch is recognized wherever the shared profile's pin
# landed it. The fixture pair "claim-dofus"/"claim-browser" mirrors dofus and
# media: the member's spawned companion (e2e-shared) is pinned to
# claim-browser by the e2e host rule, and the engine's claim step stamps the
# claim-dofus slot before home moves it home. Asserts: a spawned companion is
# slotted and re-homed from the pin; a hand-opened e2e-shared window with no
# armed intent stays on claim-browser un-slotted; and the last member leaving
# closes the claimed companion while leaving the hand-opened one alone.
# No eval.
. "$(dirname "$0")/../lib.sh"

e2e_start
go_workspace claim-dofus

shared_claimed() {
    clients | jq -e '.[] | select(.class == "e2e-shared" and .workspace.name == "claim-dofus" and ([.tags[]?] | index("slot:claim-dofus/browser")))' >/dev/null
}

# The member maps -> one companion spawns; the host pin lands it on
# claim-browser, so only the claim + home steps put it back, slotted.
spawn_test_window e2e-claim-member
wait_until 200 shared_claimed || e2e_fail "spawned companion never came home claimed to claim-dofus"

shared_unclaimed_on_browser() {
    clients | jq -e '.[] | select(.class == "e2e-shared" and .workspace.name == "claim-browser") | select(([.tags[]? | select(startswith("slot:"))] | length) == 0)' >/dev/null
}

# A hand-opened window (no armed intent) stays pinned on claim-browser, no slot.
go_workspace claim-browser
spawn_test_window e2e-shared
wait_until 100 shared_unclaimed_on_browser || e2e_fail "hand-open was claimed away from the pin or slotted"

# The last member leaving closes the claimed companion on claim-dofus while the
# hand-open on claim-browser survives.
go_workspace claim-dofus
close_all_members() {
    local a
    for a in $(clients | jq -r '.[] | select(.class == "e2e-claim-member") | .address'); do
        hc dispatch "hl.dsp.window.close({ window = \"address:$a\" })" >/dev/null
    done
    test -z "$(clients | jq -r '.[] | select(.class == "e2e-claim-member") | .address')"
}
wait_until 50 close_all_members || e2e_fail "members outlived closing all of them"
claimed_gone() {
    test -z "$(clients | jq -r '.[] | select(.class == "e2e-shared" and .workspace.name == "claim-dofus")')"
}
wait_until 100 claimed_gone || e2e_fail "claimed companion did not close with the last member"
wait_until 100 shared_unclaimed_on_browser || e2e_fail "hand-opened window was closed with the claimed companion"

e2e_log "PASS launch claim"