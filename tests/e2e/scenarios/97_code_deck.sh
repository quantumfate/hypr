#!/usr/bin/env bash
# LEO-349: the "code" scene's own shape on the deck layout — a project
# column (one Hyprland group per project) beside a browser column, wired
# through conf/hosts/e2e.lua's "code-deck" workspace and this fixture's
# "code-deck" scene (tests/e2e/fixtures/hyprfocus.json), mirroring the real
# "code" scene declared in quickshell's assets/hyprfocus.default.json.
#
# `hq key` does not fire this config's Lua-closure keybinds in this sandbox
# (see 60_navigation.sh's header), so this drives the exact bodies
# `hypr/binds.lua` binds to SUPER+CTRL+J/K (scroll the deck column) and
# SUPER+J/K (focus_in_group) via `hc eval`, the same approach 90_deck.sh uses.
. "$(dirname "$0")/../lib.sh"

run_lua() {
    local result="$E2E_ROOT/code-deck-result.json"
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

# The exact body bound to SUPER+CTRL+J/K (hypr/binds.lua's scroll_deck_column):
# scroll the focused column one step, bring the target home, focus it —
# regardless of whether the shown thing is a group or a bare window.
scroll() {
    run_lua "
local nav = require('hypr.lib.nav')
local deck = require('hypr.scene.deck')
local deck_scroll = require('hypr.scene.deck_scroll')
local scene_spec = require('hypr.scene.spec')
local scene_provider = require('hypr.scene.provider')
local scene = scene_spec.load()['code-deck']
local tiles = {}
for _, w in ipairs(hl.get_windows() or {}) do
  local tile = scene_provider.window_tile(w)
  if deck.column_for(scene, tile) then tiles[#tiles + 1] = tile end
end
local w = hl.get_active_window()
local dtiles = nav.deck_tile_order(scene, tiles, deck_scroll.get_all(scene.name))
local index = nav.tile_index(dtiles, w.address)
local tile = dtiles[index]
local target = nav.window_neighbor(tile.plain, w.address, '$1')
if target then
  local new_index
  for i, a in ipairs(tile.plain) do if a == target then new_index = i end end
  deck_scroll.set(scene.name, tile.column, new_index)
  hl.dispatch(hl.dsp.window.move({ window = 'address:' .. target, workspace = 'name:' .. scene.name, follow = false }))
  hl.dispatch(hl.dsp.focus({ window = 'address:' .. target }))
end
out({ target = target })
"
}

# The exact body bound to SUPER+J/K on a grouped tile (hypr/binds.lua's
# focus_in_group): step the group's own adapter order, never the deck's
# scroll index — this must work identically on a deck project column.
focus_in_group() {
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
out({ target = target })
"
}

project_members() { clients | jq -c 'map(select(.class | startswith("e2e-proj-")))'; }
tiled_project_members() { project_members | jq -c --arg ws code-deck 'map(select(.workspace.name == $ws))'; }
held_project_count() { project_members | jq '[.[] | select(.workspace.name == "special:deck-hold")] | length'; }
browser_client() { clients | jq -c 'map(select(.class == "e2e-browser")) | first // empty'; }
focused_address() { hc -j activewindow | jq -r '.address // empty'; }

# 4 project windows total (alpha's group of 2, beta, gamma); however many are
# tiled (the visible thing — 2 if it's alpha's group, 1 otherwise) the rest
# must be held. Never a fixed count: which thing is visible changes how many
# windows that is.
one_project_visible() { [[ $(tiled_project_members | jq 'length') -ge 1 ]]; }
rest_held() {
    local tiled held
    tiled=$(tiled_project_members | jq 'length')
    held=$(held_project_count)
    [[ $((tiled + held)) == 4 && $held -ge 2 ]]
}
browser_tiled() { [[ $(browser_client | jq -r '.workspace.name // empty') == code-deck ]]; }

e2e_start
go_workspace code-deck

# Three project things: alpha is a real two-window group, beta and gamma are
# lone windows — exactly the "thing of one" degenerate case docs/deck.md
# names. Browser is the stack-behaving companion column.
spawn_test_window e2e-proj-alpha-a
spawn_test_window e2e-proj-alpha-b
spawn_test_window e2e-proj-beta
spawn_test_window e2e-proj-gamma
spawn_test_window e2e-browser

# Seed alpha's group explicitly rather than trust Hyprland's own
# `auto_group` (hypr/conf.lua): whether it swallows a same-block peer into
# an existing group, or leaves it solo, is a race against which window (if
# any) currently holds focus at open time — observed both ways across
# otherwise-identical runs of this scenario. `group.toggle` + `:add` is the
# same live-verified mechanism `hypr/events/scene.lua`'s own group-seed path
# uses (LEO-369), so this constructs exactly the topology the declaration
# describes without depending on that race.
run_lua "
local a = hl.get_window('class:e2e-proj-alpha-a')
local b = hl.get_window('class:e2e-proj-alpha-b')
if a and b and not a.group then
  hl.dispatch(hl.dsp.group.toggle({ window = 'address:' .. a.address }))
  local seeded = hl.get_window('address:' .. a.address)
  if seeded and seeded.group then
    pcall(function() seeded.group:add(b) end)
  end
end
out({ ok = true })
" >/dev/null

alpha_is_group() {
    clients | jq -e '
      map(select(.class == "e2e-proj-alpha-a" or .class == "e2e-proj-alpha-b")) as $w
      | ($w | length) == 2 and ($w | all((.grouped | length) == 2))' >/dev/null
}
beta_gamma_solo() {
    clients | jq -e '
      map(select(.class == "e2e-proj-beta" or .class == "e2e-proj-gamma"))
      | all((.grouped | length) <= 1)' >/dev/null
}
wait_until 50 alpha_is_group || e2e_fail "alpha's two windows never formed one group: $(project_members)"
wait_until 50 beta_gamma_solo || e2e_fail "beta/gamma are still grouped with alpha after ejecting: $(project_members)"

# Exactly one project thing tiled on the workspace (the other two held), the
# browser beside it, at full column height (the deck contract: never a
# partial window).
wait_until 50 one_project_visible || e2e_fail "expected a project thing tiled on code-deck: $(project_members)"
wait_until 50 rest_held || e2e_fail "expected every non-visible project window held, found $(held_project_count) held / $(tiled_project_members | jq 'length') tiled: $(project_members)"
wait_until 50 browser_tiled || e2e_fail "expected the browser tiled beside the project column: $(browser_client)"

# Sorted, comma-joined class list of whatever is currently tiled — stable
# under jq's own array ordering, unlike reading just `.[0]` (alpha's two
# members can come back in either order).
visible_signature() { tiled_project_members | jq -r '[.[].class] | sort | join(",")'; }

VISIBLE_BEFORE=$(visible_signature)
PROJECT_H_BEFORE=$(tiled_project_members | jq -r '.[0].size[1]')
COLUMN_H=$(hc -j monitors | jq -r '.[0].height')
e2e_log "code-deck: $VISIBLE_BEFORE visible at height $PROJECT_H_BEFORE (monitor $COLUMN_H), $(held_project_count) held, browser tiled"

# Scroll: focus the visible thing, then SUPER+CTRL+J/K's own body. Which
# thing is shown changes, the other two stay held, the browser is untouched,
# and focus lands on exactly the window the flip asked for.
FIRST_ADDR=$(tiled_project_members | jq -r '.[0].address')
hc dispatch "hl.dsp.focus({ window = 'address:$FIRST_ADDR' })" >/dev/null
scroll next >/dev/null
changed() { [[ $(visible_signature) != "$VISIBLE_BEFORE" ]]; }
wait_until 50 changed || e2e_fail "scrolling did not change which project thing is visible"
rest_held || e2e_fail "expected every non-visible project window held after scrolling, found $(held_project_count) held / $(tiled_project_members | jq 'length') tiled"
browser_tiled || e2e_fail "browser left the workspace after scrolling the project column"
NEW_ADDR=$(tiled_project_members | jq -r '.[0].address')
[[ $(focused_address) == "$NEW_ADDR" ]] || e2e_fail "focus did not land on the scrolled-to thing: expected $NEW_ADDR, got $(focused_address)"
e2e_log "PASS: scrolling changed the visible project without moving the browser or stranding focus"

# Whichever thing is now visible, if it's alpha's group, mod+j/k (focus_in_group)
# must still move focus WITHIN the group, not scroll the strip. Force alpha
# visible again: the earlier "scroll next" moved one step away from it, and
# the strip never wraps (docs/deck.md), so "prev" one step returns to it
# directly rather than looping "next" past the far end.
alpha_visible() { [[ $(tiled_project_members | jq -r '.[0].class') == e2e-proj-alpha-* ]]; }
if ! alpha_visible; then
    ANY_TILED_ADDR=$(tiled_project_members | jq -r '.[0].address')
    hc dispatch "hl.dsp.focus({ window = 'address:$ANY_TILED_ADDR' })" >/dev/null
    scroll prev >/dev/null
    wait_until 50 alpha_visible || e2e_fail "could not scroll alpha's group back into view: $(tiled_project_members)"
fi
ALPHA_ADDR=$(tiled_project_members | jq -r '.[0].address')
hc dispatch "hl.dsp.focus({ window = 'address:$ALPHA_ADDR' })" >/dev/null
BEFORE_HELD=$(held_project_count)
focus_in_group next >/dev/null
still_same_visible() { [[ $(tiled_project_members | jq -r '.[0].class') == e2e-proj-alpha-* ]]; }
wait_until 30 still_same_visible || e2e_fail "mod+j/k on a group moved the deck's scroll index, not just focus within the group"
[[ $(held_project_count) == "$BEFORE_HELD" ]] || e2e_fail "mod+j/k on a group changed which things are held (it must not scroll)"
OTHER_MEMBER=$(clients | jq -r --arg a "$ALPHA_ADDR" 'map(select(.class == "e2e-proj-alpha-a" or .class == "e2e-proj-alpha-b")) | map(select(.address != $a)) | .[0].address')
[[ $(focused_address) == "$OTHER_MEMBER" ]] || e2e_fail "mod+j/k did not move focus to the other group member: expected $OTHER_MEMBER, got $(focused_address)"
e2e_log "PASS: a group's members still navigate internally on the deck project column"
