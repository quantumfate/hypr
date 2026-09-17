#!/usr/bin/env bash
# A second, headless output: both outputs stay up, the secondary-pinned scene
# lands on it, and removing it loses no window. Skips (exit 0) when the
# nested compositor cannot create outputs. No eval.
. "$(dirname "$0")/../lib.sh"

monitor_names() { hc -j monitors | jq -c 'map(.name) | sort'; }

e2e_start
if ! hc output create headless HEADLESS-2 >/dev/null 2>&1 ||
    ! wait_until 50 sh -c "hyprctl -i '$E2E_SIG' -j monitors | jq -e 'map(.name) | index(\"HEADLESS-2\")'"; then
    e2e_log "SKIP headless output: cannot create one here"
    exit 0
fi
sleep 1
assert_eq "$(monitor_names)" '["HEADLESS-2","WAYLAND-1"]' "outputs after creating HEADLESS-2"

go_workspace aside
spawn_test_window e2e-aside
on_headless() { hc -j workspaces | jq -e 'map(select(.name == "aside")) | first | .monitor == "HEADLESS-2"' >/dev/null; }
wait_until 50 on_headless || e2e_fail "workspace aside is not on HEADLESS-2: $(hc -j workspaces | jq -c 'map({name, monitor})')"

hc output remove HEADLESS-2 >/dev/null || e2e_fail "could not remove HEADLESS-2"
sleep 1
has_class e2e-aside || e2e_fail "e2e-aside was lost with its monitor"
assert_eq "$(monitor_names)" '["WAYLAND-1"]' "outputs after removing HEADLESS-2"
e2e_log "PASS headless output"
