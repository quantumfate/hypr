#!/usr/bin/env bash
# LEO-349: the deck layout wired to the compositor. A sandboxed fixture scene
# (tests/e2e/fixtures/hyprfocus.json's "deck-test", conf/hosts/e2e.lua's
# workspace 4) — the live code/media scenes are deck too, but only the e2e
# host's fixture is a stable, self-contained one to drive here.
#
# `hq key` does not fire this config's Lua-closure keybinds in this sandbox
# (see tests/e2e/scenarios/60_navigation.sh's header), so this drives the
# exact decision `hypr/binds.lua`'s deck branch of `focus_window_in_tile`
# makes via `hc eval`, same approach 60_navigation.sh uses for mod+h/l/j/k.
. "$(dirname "$0")/../lib.sh"

run_lua() {
    local result="$E2E_ROOT/deck-result.json"
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

# The exact body of `hypr/binds.lua`'s deck branch of `focus_window_in_tile`:
# scroll the focused column one step, bring the target home, focus it.
scroll() {
    run_lua "
local nav = require('hypr.lib.nav')
local deck = require('hypr.scene.deck')
local deck_order = require('hypr.scene.deck_order')
local scene_spec = require('hypr.scene.spec')
local scene_provider = require('hypr.scene.provider')
local scene = scene_spec.load()['deck-test']
local tiles = {}
for _, w in ipairs(hl.get_windows() or {}) do
  local tile = scene_provider.window_tile(w)
  if deck.column_for(scene, tile) then tiles[#tiles + 1] = tile end
end
local w = hl.get_active_window()
local dtiles = nav.deck_tile_order(scene, tiles, deck_order.get_all(scene.name))
local index = nav.tile_index(dtiles, w.address)
local tile = dtiles[index]
local target = nav.window_neighbor(tile.plain, w.address, '$1')
if not target and #tile.plain > 1 then
  target = '$1' == 'next' and tile.plain[1] or tile.plain[#tile.plain]
end
if target then
  local new_index
  for i, a in ipairs(tile.plain) do if a == target then new_index = i end end
  deck_order.set_scroll(scene.name, tile.column, new_index)
  hl.dispatch(hl.dsp.window.move({ window = 'address:' .. target, workspace = 'name:' .. scene.name, follow = false }))
  hl.dispatch(hl.dsp.focus({ window = 'address:' .. target }))
end
out({ target = target })
"
}

focused_class() { hc -j clients | jq -r 'map(select(.focusHistoryID == 0)) | first.class // empty'; }
deck_members() { clients | jq -c 'map(select(.class | startswith("e2e-deck")))'; }
visible_deck_class() {
    deck_members | jq -r --arg ws deck-test 'map(select(.workspace.name == $ws)) | first.class // empty'
}
held_count() { deck_members | jq '[.[] | select(.workspace.name == "special:deck-hold")] | length'; }
one_visible() {
    deck_members | jq -e --arg ws deck-test 'map(select(.workspace.name == $ws)) | length == 1' >/dev/null
}
two_held() { [[ $(held_count) == 2 ]]; }

e2e_start
go_workspace deck-test
spawn_test_window e2e-deck-1
spawn_test_window e2e-deck-2
spawn_test_window e2e-deck-3

# Exactly one member visible on the workspace; the other two parked in hold
# (this sandbox's nested output does not settle a final size before this
# scenario's own timeout — deck.lua's own geometry arithmetic is covered by
# tests/scene_deck_spec.lua; what only a live compositor can prove is which
# window is TILED where, which this checks).
wait_until 50 one_visible || e2e_fail "expected exactly one visible deck member on deck-test: $(deck_members)"
wait_until 50 two_held || e2e_fail "expected 2 members held, found $(held_count)"

FIRST=$(visible_deck_class)
e2e_log "deck-test: $FIRST visible, $(held_count) held"

# Flip forward: a different member becomes visible, the shown one holds, and
# focus lands on exactly the window the flip asked for — never a stray jump.
hc dispatch "hl.dsp.focus({ window = 'class:$FIRST' })" >/dev/null
scroll next >/dev/null
changed() { [[ $(visible_deck_class) != "$FIRST" ]]; }
wait_until 50 changed || e2e_fail "flipping did not change the visible member"
SECOND=$(visible_deck_class)
[[ $(held_count) == 2 ]] || e2e_fail "still expected 2 held after flipping, found $(held_count)"
[[ $(focused_class) == "$SECOND" ]] || e2e_fail "focus did not follow the flip: expected $SECOND, got $(focused_class)"

e2e_log "PASS deck"
