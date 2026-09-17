#!/usr/bin/env bash
# A second, headless output: both outputs stay up, the secondary-pinned scene
# lands on it, and removing it loses no window. Skips (exit 0) when the
# nested compositor cannot create outputs. No eval.
. "$(dirname "$0")/../lib.sh"

monitor_names() { hc -j monitors | jq -c 'map(.name) | sort'; }
on_headless() { hc -j workspaces | jq -e 'map(select(.name == "aside")) | first | .monitor == "HEADLESS-2"' >/dev/null; }

e2e_start
if ! hc output create headless HEADLESS-2 >/dev/null 2>&1 ||
    ! wait_until 50 sh -c "hyprctl -i '$E2E_SIG' -j monitors | jq -e 'map(.name) | index(\"HEADLESS-2\")'"; then
    e2e_log "SKIP headless output: cannot create one here"
    exit 0
fi
sleep 1
assert_eq "$(monitor_names)" '["HEADLESS-2","WAYLAND-1"]' "outputs after creating HEADLESS-2"

# The secondary-pinned rule (conf/hosts/e2e.lua: workspace "aside" ->
# monitor "secondary") binds as soon as HEADLESS-2 exists, with no focus
# dispatch needed — verified live, this is unconditional.
wait_until 50 on_headless || e2e_fail "workspace aside is not on HEADLESS-2: $(hc -j workspaces | jq -c 'map({name, monitor})')"

# A headless output has no real pointer/seat, so Hyprland's cursor-based
# focus tracking cannot move onto it here: `hl.dsp.focus({ monitor = ... })`
# sticks for an instant and then reverts to whichever monitor the (virtual,
# but only ever "over" WAYLAND-1) cursor sits on — verified live, reliably,
# not a timing race. go_workspace's activeworkspace wait would therefore
# never pass on this host, so we place the window directly with
# `hl.dsp.window.move`'s `monitor` field instead, which moves a window to a
# specific output without depending on focus-follow at all.
# `window.move`'s monitor field drops the window on HEADLESS-2's *currently
# active* workspace, not "aside" specifically — a plain workspace-focus
# dispatch reliably sets a monitor's own active workspace (unlike global
# cursor focus, verified live above), so it's used here just to steer that,
# not to move input focus.
hc dispatch "hl.dsp.focus({ workspace = [[name:aside]] })" >/dev/null
wait_until 50 sh -c "hyprctl -i '$E2E_SIG' -j monitors | jq -e '.[] | select(.name == \"HEADLESS-2\") | .activeWorkspace.name == \"aside\"'" ||
    e2e_fail "HEADLESS-2's active workspace never became aside: $(hc -j monitors | jq -c 'map({name, activeWorkspace})')"

spawn_test_window e2e-aside
addr=$(client_of e2e-aside | jq -r .address)
hc dispatch "hl.dsp.window.move({ window = 'address:$addr', monitor = 'HEADLESS-2' })" >/dev/null ||
    e2e_fail "could not move e2e-aside to HEADLESS-2"
wait_until 50 sh -c "hyprctl -i '$E2E_SIG' -j clients | jq -e '.[] | select(.class == \"e2e-aside\") | .workspace.name == \"aside\"'" ||
    e2e_fail "e2e-aside did not land on aside/HEADLESS-2: $(hc -j clients | jq -c 'map({class, workspace})')"

hc output remove HEADLESS-2 >/dev/null || e2e_fail "could not remove HEADLESS-2"
sleep 1
has_class e2e-aside || e2e_fail "e2e-aside was lost with its monitor"
assert_eq "$(monitor_names)" '["WAYLAND-1"]' "outputs after removing HEADLESS-2"
e2e_log "PASS headless output"
