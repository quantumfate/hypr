#!/usr/bin/env bash
# work -> gaming -> work (with a neutral hop) keeps every window reachable:
# after each apply, every test window is on a workspace that exists and none
# is left parked on the hold special once its scene is admitted again. `work`
# is the boot/resting mode; `neutral` is the hidden recovery mode, still
# reachable but never a default.
# NEEDS EVAL (hyprctl eval drives hyprfocus.enter); coordinator-run only.
. "$(dirname "$0")/../lib.sh"

e2e_start
go_workspace grouped
spawn_test_window e2e-grp-a
go_workspace loose
spawn_test_window e2e-tile
spawn_test_window e2e-stray

enter_mode() {
    hc eval "require('hypr.hyprfocus').enter('$1')" >/dev/null ||
        e2e_fail "enter $1 failed"
    wait_until 50 sh -c "jq -e --arg m '$1' '.mode == \$m' '$QF_STORE/focus.json'" ||
        e2e_fail "pointer never named $1"
    wait_transition_settled || e2e_fail "transition to $1 never settled"
}

# Every test window sits on an existing workspace; held windows only while
# their scene is not in the current mode.
assert_reachable() {
    local mode=$1 known held
    known=$(hc -j workspaces | jq -c 'map(.name)')
    clients | jq -e --argjson ws "$known" \
        'map(select(.class | startswith("e2e-"))) | all(.workspace.name as $n | $ws | index($n))' >/dev/null ||
        e2e_fail "$mode: a window sits on a missing workspace: $(clients | jq -c 'map({class, ws: .workspace.name})')"
    [[ $(clients | jq '[.[] | select(.class | startswith("e2e-"))] | length') == 3 ]] ||
        e2e_fail "$mode: a test window was lost"
    held=$(clients | jq -r 'map(select(.workspace.name == "special:hyprfocus-held")) | map(.class) | join(",")')
    if [[ ($mode == work || $mode == neutral) && -n $held ]]; then
        e2e_fail "$mode: windows still held: $held"
    fi
    if [[ $mode == gaming && $held == *e2e-grp-a* ]]; then
        e2e_fail "gaming: e2e-grp-a held although 'grouped' is admitted"
    fi
}

for mode in work gaming work neutral gaming; do
    enter_mode "$mode"
    assert_reachable "$mode"
done
enter_mode work
assert_reachable work
e2e_log "PASS mode round-trip"
