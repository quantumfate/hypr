#!/usr/bin/env bash
# LEO-380: mod+h/l/j/k navigation across tiles, into/out of a group, onto and
# back from an empty monitor, and j/k wrapping through a group's members.
#
# `hyprctl dispatch sendshortcut` (what `tests/e2e/hq key` wraps) turned out
# not to re-enter this config's own Lua-closure keybinds in this sandbox: a
# baseline sanity check against unrelated, pre-existing binds (SUPER+TAB,
# SUPER+r, SUPER+ALT+X, all confirmed live via `hyprctl -j binds`) had no
# effect either, keyboard-simulated (`wtype`) or dispatched directly, so this
# is an environment gap, not a LEO-380 regression. This scenario instead (a)
# proves the h/l/j/k binds are each registered exactly ONCE, at the modmask
# their description names — the concrete bug this issue's root cause turned
# out to be: `hypr/services/dofus/dofus.lua` registered a SUPER+h/l bind
# before `hypr/binds.lua` ever loads, and Hyprland keeps the first
# registration for a chord (AGENTS.md "Hyprland primitives"), so the old
# bind silently shadowed every mod+h/l press — and (b) exercises the exact
# handler bodies `hypr/binds.lua` registers (same requires, same nav.decide/
# group_adapters calls, same hl.dispatch), via `hc eval`, matching what
# pressing the key would run end to end against the live nested compositor.
. "$(dirname "$0")/../lib.sh"

# Same idea as `tests/e2e/hq lua`, inlined: this scenario manages its own
# ephemeral session (e2e_start), not the persistent `hq up` one, so it cannot
# reuse `hq`'s own state file.
run_lua() {
    local result="$E2E_ROOT/nav-result.json"
    command rm -f -- "$result"
    local wrapped="package.path = package.path .. \";$E2E_REPO/?.lua\"
local json = require(\"hypr.lib.json\")
local function out(tbl)
  local f = assert(io.open(\"$result\", \"w\"))
  f:write(json.encode(tbl))
  f:close()
end
$1"
    hc eval "$wrapped" >/dev/null || e2e_fail "lua snippet failed: $1"
    wait_until 30 test -f "$result" || true
    [[ -f $result ]] && cat "$result" || echo '{}'
}

# The exact body of `hypr/binds.lua`'s `focus_tile(dir)`: gather both
# monitors' state, hand it to `nav.decide` (LEO-380), dispatch the action.
cross() {
    run_lua "
local nav = require('hypr.lib.nav')
local scene_spec = require('hypr.scene.spec')
local scene_provider = require('hypr.scene.provider')
local monitor = hl.get_active_monitor()
local ws_name = (hl.get_active_workspace() or {}).name
local scene = ws_name and scene_spec.load()[ws_name]
local w = hl.get_active_window()
local tiles = scene and nav.tile_order(scene, scene_provider.workspace_tiles(scene.name)) or {}
local monitors = hl.get_monitors() or {}
local ordered = nav.monitor_order(nav.usable_monitors(monitors, nil))
local adjacent = nav.adjacent_monitor(ordered, monitor.name, '$1')
local target
if adjacent then
  local active = adjacent.activeWorkspace
  local other_scene = active and active.name and scene_spec.load()[active.name]
  target = { tiles = other_scene and nav.tile_order(other_scene, scene_provider.workspace_tiles(other_scene.name)) or {} }
end
local action = nav.decide({ monitors = monitors, ignored = nil, focused = monitor.name, tiles = tiles, active = w and w.address, dir = '$1', target = target })
if action.kind == 'window' then
  hl.dispatch(hl.dsp.focus({ window = 'address:' .. action.address }))
elseif action.kind == 'monitor' then
  hl.dispatch(hl.dsp.focus({ monitor = action.name }))
end
out(action)
"
}

# The exact body of `hypr/binds.lua`'s `focus_in_group(w, dir)`.
group_step() {
    run_lua "
local group_adapters = require('hypr.scene.group_adapters')
local grouping = require('hypr.scene.grouping')
local w = hl.get_active_window()
local raw = w.group.members
raw = (raw and raw.title) and { raw } or (raw or {})
local members = {}
for _, m in ipairs(raw) do members[#members + 1] = { address = m.address, title = m.title } end
local order = group_adapters.for_class(w.class).order(members, { group_key = grouping.group_key(w) })
local index
for i, a in ipairs(order) do if a == w.address then index = i end end
local step = '$1' == 'next' and 1 or -1
local target = order[((index - 1 + step) % #order) + 1]
hl.dispatch(hl.dsp.focus({ window = 'address:' .. target }))
out({ address = target })
"
}

focused_address() { hc -j clients | jq -r 'map(select(.focusHistoryID == 0)) | first.address // empty'; }
focused_class() { hc -j clients | jq -r 'map(select(.focusHistoryID == 0)) | first.class // empty'; }
active_monitor() { hc -j monitors | jq -r 'map(select(.focused == true)) | first.name // empty'; }
active_workspace_on() { hc -j monitors | jq -r --arg m "$1" 'map(select(.name == $m)) | first.activeWorkspace.name // empty'; }
group_addresses() { hc -j clients | jq -c '[.[] | select(.class == "e2e-grp-a" or .class == "e2e-grp-b") | .address] | sort'; }
two_grp_a() { hc -j clients | jq -e '[.[] | select(.class == "e2e-grp-a")] | length >= 2' >/dev/null; }
in_one_group() {
    hc -j clients | jq -e '
      map(select(.class == "e2e-grp-a" or .class == "e2e-grp-b")) as $w
      | ($w | length) == 3
        and ($w | all((.grouped | length) == 3))' >/dev/null
}
monitor_focused_is() { [[ $(active_monitor) == "$1" ]]; }

e2e_start
if ! hc output create headless HEADLESS-2 >/dev/null 2>&1 ||
    ! wait_until 50 sh -c "hyprctl -i '$E2E_SIG' -j monitors | jq -e 'map(.name) | index(\"HEADLESS-2\")'"; then
    e2e_log "SKIP navigation: cannot create a headless output here"
    exit 0
fi
# To the right of WAYLAND-1 (pinned 1280x720 by lib.sh), so monitor_order
# sees HEADLESS-2 as the right-hand monitor.
hc keyword monitor "HEADLESS-2,1280x720@60,1280x0,1" >/dev/null

hc eval "require('hypr.hyprfocus').enter('neutral')" >/dev/null || e2e_fail "enter neutral failed"
wait_until 50 sh -c "jq -e '.mode == \"neutral\"' '$QF_STORE/focus.json'" || e2e_fail "pointer never named neutral"

go_workspace grouped
spawn_test_window e2e-grp-a
spawn_test_window e2e-grp-b
# A third member, same block, different window than the first e2e-grp-a.
WAYLAND_DISPLAY=$E2E_WAYLAND setsid foot --app-id e2e-grp-a sh -c "sleep 600 # $E2E_ROOT" >/dev/null 2>&1 &
wait_until 100 two_grp_a || e2e_fail "second e2e-grp-a window never appeared"
wait_until 50 in_one_group || e2e_fail "the three e2e-grp windows never formed one group of 3"

spawn_test_window e2e-tile
GROUP_ADDRS=$(group_addresses)
e2e_log "group members: $GROUP_ADDRS"

# --- the concrete bug: exactly one h/l/j/k bind each, at the description
# this issue's decision names (no shadowing duplicate left registered
# earlier by another module) ---
for key in h l j k; do
    count=$(hc -j binds | jq --arg k "$key" '[.[] | select(.key == $k and .submap == "" and .modmask == 64)] | length')
    [[ $count == 1 ]] || e2e_fail "expected exactly one root SUPER+$key bind, found $count"
done

# --- across tiles: group -> stray tile -> group (opposite key returns) ---
hc dispatch "hl.dsp.focus({ window = 'class:e2e-grp-a' })" >/dev/null
cross right >/dev/null
[[ $(focused_class) == e2e-tile ]] || e2e_fail "crossing right from the group did not land on the stray tile: $(focused_class)"

cross left >/dev/null
[[ $(echo "$GROUP_ADDRS" | jq --arg a "$(focused_address)" 'index($a) != null') == true ]] ||
    e2e_fail "crossing left back from the tile did not return into the group: $(focused_class)"

# --- onto the empty secondary monitor, and back (LEO-372/LEO-380) ---
hc dispatch "hl.dsp.focus({ window = 'class:e2e-tile' })" >/dev/null
cross right >/dev/null
wait_until 50 monitor_focused_is HEADLESS-2 || e2e_fail "crossing right off the last tile never reached HEADLESS-2: $(active_monitor)"
# HEADLESS-2's shown workspace has no scene tiles (whichever one it is —
# `aside`'s placement onto a monitor created mid-session is a hyprfocus
# concern, not this decision's), so `decide` landed on the MONITOR itself
# per the decision comment, not a window — `monitor_focused_is` above is
# the whole check: an empty monitor holds no window to focus instead.

cross left >/dev/null
wait_until 50 monitor_focused_is WAYLAND-1 || e2e_fail "crossing left back from the empty monitor never returned to WAYLAND-1"
[[ $(focused_class) == e2e-tile ]] || e2e_fail "returning did not land back on the stray tile: $(focused_class)"

# --- j/k wrap through the group's 3 members (Dofus-adapter tested in
# tests/group_adapters_spec.lua; the default adapter is exercised live here) ---
hc dispatch "hl.dsp.focus({ window = 'class:e2e-grp-a' })" >/dev/null
a0=$(focused_address)
a1=$(group_step next | jq -r .address)
a2=$(group_step next | jq -r .address)
a3=$(group_step next | jq -r .address)
[[ $a1 != "$a0" && $a2 != "$a0" && $a2 != "$a1" ]] || e2e_fail "next did not visit 3 distinct members: $a0 $a1 $a2"
[[ $a3 == "$a0" ]] || e2e_fail "next the third time did not wrap back to the start: $a3 != $a0"

b1=$(group_step prev | jq -r .address)
[[ $b1 == "$a2" ]] || e2e_fail "prev did not wrap backward to the previous member: $b1 != $a2"

e2e_log "PASS navigation"
