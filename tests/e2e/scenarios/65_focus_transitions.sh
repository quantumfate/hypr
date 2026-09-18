#!/usr/bin/env bash
# LEO-350: exercise the mode transitions the desktop model promises beyond the
# simple work<->gaming round trip 40_mode_roundtrip.sh already covers —
# work -> study -> gaming -> work, a timed mode's expiry falling back to
# `previous`, and the hidden `neutral` recovery mode reached and left again.
# Every step keeps all four test windows reachable and checks which ones sit
# on the shared hold special, matching docs/desktop-model.md's Pointer and
# Scene sections. NEEDS EVAL (hyprctl eval drives hyprfocus.enter/converge);
# coordinator-run only.
. "$(dirname "$0")/../lib.sh"

e2e_start

# One window per fixture scene (tests/e2e/fixtures/hyprfocus.json):
# grouped/loose/aside are common to work and neutral; study drops loose and
# aside; gaming drops loose and aside too but keeps grouped.
go_workspace grouped
spawn_test_window e2e-grp-a
go_workspace loose
spawn_test_window e2e-tile
go_workspace aside
spawn_test_window e2e-aside

enter_mode() {
    hc eval "require('hypr.hyprfocus').enter('$1')" >/dev/null ||
        e2e_fail "enter $1 failed"
    wait_until 50 sh -c "jq -e --arg m '$1' '.mode == \$m' '$QF_STORE/focus.json'" ||
        e2e_fail "pointer never named $1"
    sleep 0.3
}

# Every test window sits on an existing workspace, and the held set on
# special:hyprfocus-held matches exactly what this mode does not admit.
assert_state() {
    local mode=$1 expect_held=$2 known held
    known=$(hc -j workspaces | jq -c 'map(.name)')
    clients | jq -e --argjson ws "$known" \
        'map(select(.class | startswith("e2e-"))) | all(.workspace.name as $n | $ws | index($n))' >/dev/null ||
        e2e_fail "$mode: a window sits on a missing workspace: $(clients | jq -c 'map({class, ws: .workspace.name})')"
    [[ $(clients | jq '[.[] | select(.class | startswith("e2e-"))] | length') == 3 ]] ||
        e2e_fail "$mode: a test window was lost"
    held=$(clients | jq -r 'map(select(.workspace.name == "special:hyprfocus-held")) | map(.class) | sort | join(",")')
    [[ $held == "$expect_held" ]] ||
        e2e_fail "$mode: held set was '$held', expected '$expect_held'"
}

# --- work -> study -> gaming -> work: reachable throughout, held windows
# return exactly when their scene is admitted again ---
enter_mode work
assert_state work ""

enter_mode study
# study's scene set is just 'grouped' (tests/e2e/fixtures/hyprfocus.json):
# loose and aside are withheld, mirroring work -> study withholding `logs`.
assert_state study "e2e-aside,e2e-tile"

enter_mode gaming
# gaming admits arena + grouped; loose/aside remain withheld.
assert_state gaming "e2e-aside,e2e-tile"

enter_mode work
# Back to the scene set that admits all three: nothing left held.
assert_state work ""
e2e_log "PASS work -> study -> gaming -> work"

# --- timed mode expiry falls back to `previous`, never to neutral ---
# Simulate a timed mode entered in the past and already expired: enter()
# writes previous = the mode in effect at that moment (docs/desktop-model.md
# "Pointer"), so entering a timed 'study' over open-ended 'work' records
# previous=work.
hc eval "require('hypr.hyprfocus').enter('study', 'timer', '2000-01-01T00:00:00Z')" >/dev/null ||
    e2e_fail "timed enter study failed"
wait_until 50 sh -c "jq -e '.mode == \"study\" and .previous == \"work\"' '$QF_STORE/focus.json'" ||
    e2e_fail "pointer did not record the timed mode with previous=work: $(cat "$QF_STORE/focus.json")"
# hyprfocus.enter converged on the timed mode itself (it is not expired at
# entry time, only its `until` stamp already is): study's scene set applied,
# so loose/aside are held right now.
assert_state study "e2e-aside,e2e-tile"

# effective_mode reads `until` as already past, so the next convergence tick
# (any of the watcher's subscribed events) must resolve to `previous`
# (work), not to `study` and never to `neutral`.
go_workspace grouped # fires workspace.active, which the watcher listens on
none_held() { hc -j clients | jq -e 'map(select(.workspace.name == "special:hyprfocus-held")) | length == 0' >/dev/null; }
wait_until 50 none_held ||
    e2e_fail "expired timed mode never fell back to previous (work): $(clients | jq -c 'map({class, ws: .workspace.name})')"
assert_state work ""
e2e_log "PASS timed mode expiry falls back to previous, not neutral"

# --- neutral: hidden recovery, reachable and returns cleanly ---
enter_mode neutral
# neutral's scene set (grouped/loose/aside) matches work's here, so nothing
# is held; the check that matters is that the hidden mode is reachable at
# all and the pointer names it, never as a default.
assert_state neutral ""
[[ $(jq -r .mode "$QF_STORE/focus.json") == neutral ]] || e2e_fail "pointer did not record neutral"

enter_mode work
assert_state work ""
# An open-ended entry clears `previous` (docs/desktop-model.md "Pointer"):
# neutral must not linger as a fallback for anything after this.
[[ $(jq -r '.previous // "null"' "$QF_STORE/focus.json") == null ]] ||
    e2e_fail "previous was not cleared by the open-ended entry into work: $(cat "$QF_STORE/focus.json")"
e2e_log "PASS neutral recovery and back"
