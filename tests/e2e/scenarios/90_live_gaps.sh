#!/usr/bin/env bash
# Editing conf/base.lua's gap numbers applies them to the running compositor:
# a reload re-runs hyprland.lua -> conf/host.lua's build, which re-resolves the
# fingerprint profile onto every workspace spec, so the compositor's own
# general gaps and each scene workspace's rule gaps move without a restart.
# This is the regression guard for that chain — LEO-393.
#
# Why the assertions are config-level and not pixel-level: the e2e output is
# a wayland-backend window (640x180 @ scale 2 -> 320x90 logical; the
# `hyprctl keyword monitor` pin in e2e_boot is a no-op on this build, and the
# wayland backend refuses mode/position changes). On a 90-logical-px-tall
# output, slotted widths/heights fall below Hyprland's `misc:size_limits_tiled`
# minimum (20x20), so mapped positions are clamp artifacts, not a clean
# function of the gaps (spiked live with a tracing wrapper over the registered
# provider: boxes 44x6 and -30 tall with the pins). The compositor knobs are
# the exact, scale-independent contract; a coarse "the windows moved" check
# below backs the provider-side reading of those knobs without depending on
# where the clamp lands.
#
# Values are restored afterwards: the working tree may hold deliberate gap
# edits.
# No eval.
. "$(dirname "$0")/../lib.sh"

e2e_start
go_workspace grouped
spawn_test_window e2e-probe-a
spawn_test_window e2e-probe-b # tiled strays: any reload gap change must move them

BASE="$E2E_REPO/conf/base.lua"
BAK="$E2E_ROOT/base.lua.bak"
cp "$BASE" "$BAK"
restore() {
    cp "$BAK" "$BASE"
    e2e_stop
}
trap restore EXIT

gap_css() { hc -j getoption "$1" | jq -r '.css'; }

rule_for() { hc -j workspacerules | jq -c --arg n "$1" 'map(select(.defaultName == $n))[0]'; }

window_xs() {
    clients | jq -c 'map(select(.class | startswith("e2e-probe"))) | sort_by(.at[0]) | map(.at[0])'
}

IN_BEFORE=$(gap_css general:gaps_in)
OUT_BEFORE=$(gap_css general:gaps_out)
RULE_BEFORE=$(rule_for grouped)
XS_BEFORE=$(window_xs)
e2e_log "before: xs=$XS_BEFORE general_in=$IN_BEFORE general_out=$OUT_BEFORE rule=$(echo "$RULE_BEFORE" | jq -c '{gapsIn, gapsOut}')"

# The e2e output's fingerprint is always laptop-solo (no monitor >=3440 wide),
# so the two declarations below are what feed a reload. The target numbers are
# deliberately off the committed ones so a stale read is obviously wrong. The
# primary sed touches both profiles' primary line — laptop-solo is the active
# one; the desk-dual line is restored with the file by the EXIT trap.
sed -i \
    -e '/local default_gaps = /s/{ gaps_in = [0-9]\+, gaps_out = { top = [0-9]\+, right = [0-9]\+, bottom = [0-9]\+, left = [0-9]\+ } }/{ gaps_in = 77, gaps_out = { top = 25, right = 85, bottom = 85, left = 85 } }/' \
    -e '/primary = /s/{ gaps_in = [0-9]\+, gaps_out = { top = [0-9]\+, right = [0-9]\+, bottom = [0-9]\+, left = [0-9]\+ } }/{ gaps_in = 66, gaps_out = { top = 26, right = 86, bottom = 86, left = 86 } }/' \
    "$BASE"
hc reload

# The compositor's own general gaps, all four sides ("extra window space at
# every screen edge").
assert_eq "$(gap_css general:gaps_in)" "77 77 77 77" "general inner gaps live"
assert_eq "$(gap_css general:gaps_out)" "25 85 85 85" "general outer gaps live"

# The scene workspace's own rule gaps, css order top right bottom left.
RULE_AFTER=$(rule_for grouped)
assert_eq "$(echo "$RULE_AFTER" | jq -c '.gapsIn')" \
    "[66,66,66,66]" "scene workspace inner rule gaps live"
assert_eq "$(echo "$RULE_AFTER" | jq -c '.gapsOut')" \
    "[26,86,86,86]" "scene workspace outer rule gaps live"

# The provider-side backstop: the tiled windows must have moved since the
# reload bumped the gaps they are placed from. No exact position: on the
# 90-logical-px-tall e2e output the size-limit clamp corrupts pixel positions
# (see the header), so "changed" is the robust statement.
probes_moved() {
    local now
    now=$(window_xs)
    [[ -n $now && $now != "$XS_BEFORE" ]]
}
wait_until 50 probes_moved || e2e_fail "tiled windows did not move after reload: $(window_xs)"

e2e_log "after: xs=$(window_xs) rule=$(echo "$RULE_AFTER" | jq -c '{gapsIn, gapsOut}')"
e2e_log "PASS live gap updates"
