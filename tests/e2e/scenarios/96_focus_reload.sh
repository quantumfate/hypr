#!/usr/bin/env bash
# LEO-400: a reload must not move focus, and a mode's declared `main` scene
# is only ever the fallback -- session start or a fresh mode entry, never a
# periodic correction while the user works elsewhere.
# NEEDS EVAL (hyprctl eval drives hyprfocus.enter, like 40_mode_roundtrip.sh);
# coordinator-run only.
. "$(dirname "$0")/../lib.sh"

e2e_start

# --- part 1: a reload leaves the desk exactly where it was --------------
# `work`'s declared main is "loose" (tests/e2e/fixtures/hyprfocus.json).
# Focus a DIFFERENT admitted scene first, so a reload that fell back to main
# instead of restoring would be caught.
go_workspace grouped

# A second monitor is deliberately NOT covered here: creating a headless
# output and then `hc reload`ing while it exists reliably crashes this
# Hyprland build (Monitor::CMonitorResources::initFB, verified live and
# reproducible with zero hyprfocus code involved -- `hc output create
# headless HEADLESS-2` followed by a bare `hc reload`, no scene/mode code in
# between). That is a compositor bug, out of this issue's scope; the
# per-monitor restore logic itself is exercised without a compositor in
# tests/hyprfocus_focus_history_spec.lua's `plan_restore` cases.

before=$(hc -j monitors | jq -c 'map({name, ws: .activeWorkspace.name}) | sort_by(.name)')
e2e_log "before reload: $before"

hc reload

# The compositor's own reload-time bookkeeping needs a moment; poll rather
# than assume a fixed delay landed on either side of it.
wait_until 50 sh -c "test \"\$(hyprctl -i '$E2E_SIG' -j monitors | jq -c 'map({name, ws: .activeWorkspace.name}) | sort_by(.name)')\" = '$before'" ||
    e2e_fail "reload moved focus: before=$before after=$(hc -j monitors | jq -c 'map({name, ws: .activeWorkspace.name}) | sort_by(.name)')"
e2e_log "after reload: unchanged"

# --- part 2: a mode entered from scratch lands on its declared main -------
# `gaming`'s declared main is "arena". Round-trip through `work` first (the
# fixture pointer's boot mode) so this is a genuine fresh entry, not a no-op
# re-apply of the mode already running.
hc eval "require('hypr.hyprfocus').enter('work')" >/dev/null || e2e_fail "enter work failed"
wait_until 50 sh -c "jq -e '.mode == \"work\"' '$QF_STORE/focus.json'" >/dev/null || e2e_fail "pointer never named work"
wait_transition_settled || e2e_fail "transition to work never settled"

hc eval "require('hypr.hyprfocus').enter('gaming')" >/dev/null || e2e_fail "enter gaming failed"
wait_until 50 sh -c "jq -e '.mode == \"gaming\"' '$QF_STORE/focus.json'" >/dev/null || e2e_fail "pointer never named gaming"
wait_until 50 sh -c "hyprctl -i '$E2E_SIG' -j activeworkspace | jq -e '.name == \"arena\"'" ||
    e2e_fail "gaming entry never focused its main scene 'arena': $(hc -j activeworkspace | jq -c '{name}')"

e2e_log "PASS focus survives a reload; a fresh mode entry lands on its main scene"
