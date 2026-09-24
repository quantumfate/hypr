#!/usr/bin/env bash
# A window opening mid-transition must not steal the landing: the bracket's
# catch-all no_focus rule (hypr/lib/transition.lua) keeps it unfocused behind
# the veil, and focus still lands on the mode's declared main scene when the
# transition settles. NEEDS EVAL (hyprctl eval drives hyprfocus.enter);
# coordinator-run only.
. "$(dirname "$0")/../lib.sh"

e2e_start

# Let boot's own bracket settle first: the thief below must open on a
# deterministic workspace (work's main, `loose`), which only exists once the
# boot transition has landed there.
wait_until 60 sh -c "test -f '$QF_STORE/hyprfocus.transition.json' && jq -e '.active == false' '$QF_STORE/hyprfocus.transition.json' >/dev/null" ||
    e2e_fail "boot bracket never settled"

# Enter gaming, then open a window inside GAMING's bracket: the store publish
# (active + mode) happens after the guard rule is raised in begin(), so a
# window mapped once it names gaming is strictly under the guard.
hc eval "require('hypr.hyprfocus').enter('gaming')" >/dev/null &
wait_until 30 sh -c "jq -e '.active == true and .mode == \"gaming\"' '$QF_STORE/hyprfocus.transition.json' >/dev/null" ||
    e2e_fail "gaming's bracket never published"
spawn_test_window e2e-thief

# The transition settles after lead + hold + margin; only then is focus the
# contract's, not mid-bracket.
sleep 6.5

# The settle landed on gaming's declared main scene.
active_ws=$(hc -j monitors | jq -r '.[0].activeWorkspace.name')
[[ $active_ws == arena ]] ||
    e2e_fail "active workspace is '$active_ws', expected arena (gaming's main)"

# The mid-transition window did not follow focus onto the main scene: it is a
# stray gaming does not claim, parked with the other withheld windows.
thief_ws=$(clients | jq -r 'map(select(.class == "e2e-thief"))[0].workspace.name')
[[ $thief_ws == "special:hyprfocus-held" ]] ||
    e2e_fail "the mid-transition window is on '$thief_ws', expected special:hyprfocus-held"

# The guard is withdrawn with the bracket: a window opened NOW takes focus as
# normal again.
spawn_test_window e2e-after
after=$(hc -j activewindow | jq -r '.class')
[[ $after == e2e-after ]] ||
    e2e_fail "a window opened after the settle is '$after', expected e2e-after; the guard outlived the bracket"

echo "67_transition_focus_guard: ok"
