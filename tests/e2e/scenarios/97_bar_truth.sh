#!/usr/bin/env bash
# The one scenario that runs the REAL bar instead of the qs stub (LEO-class
# bug class: the bar's displayed state disagreeing with the compositor's
# actual state is invisible to every other scenario by construction, since
# lib.sh replaces qs with a logging stub for them). Opts in via
# E2E_REAL_BAR=1; every other scenario is unaffected.
#
# Skips (exit 0), never fakes a pass, when the sibling quickshell checkout,
# `qs`, `grim` or `compare` (ImageMagick) aren't available, or the real bar
# does not attach here at all.
. "$(dirname "$0")/../lib.sh"

command -v grim >/dev/null && command -v compare >/dev/null || {
    e2e_log "SKIP bar truth: grim/compare (ImageMagick) not available"
    exit 0
}

E2E_REAL_BAR=1
E2E_BIG_MONITOR=1
e2e_start

if ! command -v qs >/dev/null || [[ ! -f "$(bar_qs_path)/shell.qml" ]]; then
    e2e_log "SKIP bar truth: no qs binary or no sibling quickshell checkout at $(bar_qs_path)"
    exit 0
fi
if ! bar_start WAYLAND-1; then
    e2e_log "SKIP bar truth: real bar would not attach to WAYLAND-1 (see $E2E_ROOT/qs.log)"
    exit 0
fi

# Populate: a zero-row bar is just the RowLayout's own spacing, near zero
# width -- one or more real workspace icons render measurably wider than that.
w=$(hc -j layers | jq -r '(.["WAYLAND-1"].levels["2"] // []) | map(select(.namespace == "quickshell-bar")) | first.w // 0') || true
((w > 20)) || e2e_fail "bar rendered with implausible width ${w}px -- no rows populated"
e2e_log "PASS populate: bar width ${w}px on WAYLAND-1"

# Same-monitor switch (the actual bug this scenario exists to catch): work
# mode admits grouped/loose/deck-test on WAYLAND-1 (tests/e2e/fixtures/
# hyprfocus.json); boot lands on "loose" (work's main scene). Hopping to
# "grouped" crosses no monitor -- a bar whose active-row highlight tracks
# only monitor-crossing focus events would render an IDENTICAL bar here.
before="$E2E_ROOT/before.png"
after="$E2E_ROOT/after.png"
bar_shot WAYLAND-1 "$before"
go_workspace grouped
sleep 0.3
bar_shot WAYLAND-1 "$after"
diff=$(bar_diff "$before" "$after")
awk -v d="$diff" 'BEGIN { exit !(d > 5) }' ||
    e2e_fail "bar pixels barely changed on a same-monitor workspace switch (diff=${diff}px) -- the active row did not follow"
e2e_log "PASS same-monitor: bar diff after loose->grouped: ${diff}px"

# Cross-monitor: create HEADLESS-2 (aside is the only secondary-pinned
# scene here) and switch to it. Real pixels of HEADLESS-2's own bar are not
# obtainable in this harness (see tests/e2e/Readme.md "Real bar" -- grim
# fails with "failed to create buffer" against a headless output; confirmed
# live, not a timing race, and unrelated to WLR_RENDERER=pixman, which fixes
# the same error for the real WAYLAND-1 backend output). What real pixels
# CAN still confirm here is that the primary bar keeps rendering correctly
# once a second bar instance exists, alongside the compositor's own truth
# that the switch actually landed on the other output.
if hc output create headless HEADLESS-2 >/dev/null 2>&1 &&
    wait_until 50 sh -c "hyprctl -i '$E2E_SIG' -j monitors | jq -e 'map(.name) | index(\"HEADLESS-2\")'"; then
    hc dispatch "hl.dsp.focus({ workspace = [[name:aside]] })" >/dev/null
    wait_until 50 sh -c "hyprctl -i '$E2E_SIG' -j monitors | jq -e '.[] | select(.name == \"HEADLESS-2\") | .activeWorkspace.name == \"aside\"'" ||
        e2e_fail "compositor truth: HEADLESS-2 never became active on aside"
    wait_until 50 bar_layer_up WAYLAND-1 || e2e_fail "primary bar layer disappeared after HEADLESS-2 attached"
    after_cross="$E2E_ROOT/after-cross.png"
    bar_shot WAYLAND-1 "$after_cross"
    [[ -s $after_cross ]] || e2e_fail "primary bar screenshot empty after the cross-monitor switch"
    e2e_log "PASS cross-monitor: compositor truth confirms HEADLESS-2/aside; primary bar still live and screenshottable"
else
    e2e_log "SKIP cross-monitor leg: cannot create a headless output here"
fi

e2e_log "PASS bar truth"
