-- The `deck` scene, registered as a Hyprland layout.
--
-- Thin shell over hypr/scene/deck.lua, mirroring hypr/scene/provider.lua's
-- shape: read the live windows a deck's columns subscribe to, ask the pure
-- function where every member goes (visible or off-screen, LEO-402), and
-- place them all. Nothing here decides geometry or membership — that is
-- deck.lua's job; this module only executes what it reports (docs/deck.md
-- "Why hidden members are placed off-screen").
local spec_lib = require("hypr.scene.spec")
local deck = require("hypr.scene.deck")
local deck_scroll = require("hypr.scene.deck_scroll")
local scene_provider = require("hypr.scene.provider")
local dock_publish = require("hypr.scene.dock_publish")

local M = {}

local NAME = "deck"

---A gap value as one scalar: already a number, or a sided `Scene.CssGap`
---table's `left`. `gaps_in` has no directional meaning (only the space
---between columns), so it alone still collapses this way; `gaps_out` is
---passed through sided (see `gaps` below).
---@param value number|Scene.CssGap?
---@param fallback number
---@return number
local function scalar(value, fallback)
  if type(value) == "table" then
    return value.left or fallback
  end
  return tonumber(value) or fallback
end

---Gap precedence for a deck scene, the same ladder hypr/scene/provider.lua's
---private `gaps` reads (duplicated rather than exported, since neither module
---should reach into the other's internals for two lines of arithmetic): the
---scene's own declared `gaps_in`/`gaps_out` (LEO-397) win, then the host
---workspace-spec gaps (`conf/host.lua` resolves those from the monitor
---profile at load), then the compositor's global config, read live.
---`gaps_out` is returned as whatever shape won the rung -- a deck honours
---each side the way `layout.lua`'s `sides` does (LEO-421), rather than
---collapsing to one number.
---@param scene Scene.Spec
---@return number gaps_in, Scene.CssGap gaps_out
local function gaps(scene)
  local function raw(key, fallback)
    local ok, value = pcall(hl.get_config, key)
    if not ok or value == nil then
      return fallback
    end
    return value
  end
  local spec_in, spec_out
  local specs = config and config.host and config.host.workspaces and config.host.workspaces.workspace_specs
  for _, spec in ipairs(specs or {}) do
    if spec.default_name == scene.name then
      spec_in, spec_out = spec.gaps_in, spec.gaps_out
    end
  end
  local global_in = scalar(raw("general:gaps_in", 0), 0)
  local gaps_in = scalar(scene.gaps_in, scalar(spec_in, global_in))
  local gaps_out = scene.gaps_out or spec_out or raw("general:gaps_out", 0)
  return gaps_in, gaps_out
end

---Every window anywhere subscribing to `spec`'s columns — not only the ones
---currently on the deck's own workspace, since a member may not have been
---claimed home yet. Membership is class/tag matching, which has no notion
---of "current workspace".
---@param spec Scene.Spec
---@return Scene.Tile[] tiles
---@return table<string, string> workspace_of live workspace name per address
---@return table<string, HL.Box> positions live `{x, y}` per address, for
---`deck.live_scroll` (Task A: deriving the visible member across a reload)
local function member_tiles(spec)
  local tiles, workspace_of, positions = {}, {}, {}
  for _, w in ipairs(hl.get_windows() or {}) do
    local tile = scene_provider.window_tile(w)
    if deck.column_for(spec, tile) then
      tiles[#tiles + 1] = tile
      local ws = w.workspace
      if tile.address and ws and ws.name then
        workspace_of[tile.address] = ws.name
      end
      if tile.address and w.at then
        -- Focus rank, not position: every member of a column shares one box
        -- now, so "which one is showing" is the one most recently focused.
        positions[tile.address] = { rank = w.focusHistoryID or w.focus_history_id }
      end
    end
  end
  return tiles, workspace_of, positions
end

---Every address each deck scene held on its last placement, so a window that
---has just arrived can be told apart from one deliberately scrolled out of
---view.
---@type table<string, table<string, true>>
local seen = {}

---What each member's opacity was last set to, keyed by address. A dispatch
---inside the layout pass re-enters `recalculate` (a property change is a
---change), so the pass issues one only when the value actually moves -- and
---even then from outside the pass.
local opacity_state = {}

---Drop a closed window from the membership record.
---
---`seen` is what makes "new" mean "this scene has never placed this window";
---an address the compositor later hands to a different window would otherwise
---read as already-seen and its column would not scroll to it. Called from the
---`window.close` hook, which is the only event that can retire an address.
---@param address string?
function M.forget(address)
  if not address then
    return
  end
  for _, members in pairs(seen) do
    members[address] = nil
  end
  opacity_state[address] = nil
end

---Point a column at a window that has just arrived in it.
---
---Without this, a newly-spawned member landed wherever its column's scroll
---already sat, was therefore not that column's visible member, and got
---moved off-screen the instant it opened. Opening a window is an implicit
---request to see it, so its column scrolls to it rather than hiding it. A
---window scrolled away by hand is untouched: it is not new.
---@param spec Deck.Spec
---@param scene_name string
---@param tiles Scene.Tile[]
local function scroll_to_arrivals(spec, scene_name, tiles)
  local previous = seen[scene_name]
  -- Record EVERY member this scene has ever placed, not just those visible
  -- right now -- else an off-screen member would read as "new" on the very
  -- next pass, get scrolled to, push the previously-visible one off-screen
  -- in turn, and the two would swap forever. Membership is the right key:
  -- "new" must mean "this scene has never placed this window", which
  -- happens exactly once per window.
  local current = {}
  for _, tile in ipairs(tiles) do
    if tile.address then
      current[tile.address] = true
    end
  end
  seen[scene_name] = current
  for order, stack in pairs(deck.stacks(spec, tiles)) do
    for index, tile in ipairs(stack) do
      -- An arrival is a member this pass has not seen before. With no
      -- previous set (the very first pass, including right after a reload)
      -- every member looks new -- `M.live_scroll`'s reload-recovery below
      -- runs first and already fixed the scroll index from live geometry,
      -- so this loop's fallback default (index 1) only ever matters for a
      -- column with no live position to derive from yet.
      local unseen = tile.address and previous and not previous[tile.address]
      if unseen then
        deck_scroll.set(scene_name, order, index)
        break
      end
    end
  end
end

---Re-derive each column's scroll index from live window position and write
---it into `deck_scroll` before this pass reads it back out — the merge that
---makes the visible member survive a reload (Task A; docs/deck.md "Scroll
---survives a reload"). A reload wipes `deck_scroll`'s in-process table, but
---not any window's position, so `deck.live_scroll` recovers the same index
---`M.boxes` last computed. A column with no live position yet (nothing
---placed at all) is left alone -- `scroll_to_arrivals` and `deck.boxes`'s
---own default (index 1) cover that case instead.
---@param spec Deck.Spec
---@param scene_name string
---@param tiles Scene.Tile[]
---@param area Scene.Area
---@param positions table<string, HL.Box>
local function sync_scroll_from_live(spec, scene_name, tiles, area, positions)
  for order, index in pairs(deck.live_scroll(spec, tiles, area, positions)) do
    deck_scroll.set(scene_name, order, index)
  end
end

---Deck-opted scenes only, keyed by workspace name — `deck.applies` is the
---one opt-in check (docs/deck.md), so a scene left on `layout = "scene"`
---(every real scene today) never reaches this provider at all.
---@param scenes table<string, Scene.Spec>
---@return table<string, Scene.Spec>
local function deck_scenes(scenes)
  local out = {}
  for name, scene in pairs(scenes) do
    if deck.applies(scene) then
      out[name] = scene
    end
  end
  return out
end

---@param scenes table<string, Scene.Spec>|fun(): table<string, Scene.Spec>
function M.register(scenes)
  -- Same contract as `hypr/scene/provider.lua`'s register, and for the same
  -- reason (LEO-397): `M.attach()` passes a resolver so every recalculate
  -- re-reads the live declaration. Resolving once at registration froze the
  -- deck set to whatever the store held at config-load -- before it was
  -- readable, that set came up empty, `scene_name` below never matched, and
  -- the deck silently drew nothing on a workspace that declares it. Tests
  -- pass a plain table fixture, read once, which is fine since they own the
  -- whole lifetime of that table.
  local get_scenes = type(scenes) == "function" and scenes or function()
    return scenes
  end
  hl.layout.register(NAME, {
    recalculate = function(ctx)
      local decks = deck_scenes(get_scenes())
      local targets = ctx.targets or {}
      local scene_name
      for _, target in ipairs(targets) do
        local ws = target.window and target.window.workspace
        if ws and ws.name and decks[ws.name] then
          scene_name = ws.name
          break
        end
      end
      if not scene_name then
        return
      end
      M.place(decks[scene_name], scene_name, ctx)
    end,
  })
end

---Place one deck scene's windows into `ctx`.
---
---Exposed rather than kept inside the registered layout because a deck
---workspace cannot actually select this layout on this build: a workspace
---rule's `layout` resolves BUILTIN layouts only (verified live -- `master`
---and `dwindle` take, while `scene`, `deck`, `lua:scene` and `lua:deck` all
---fall through), and only `general:layout` accepts a custom Lua one. So the
---deck runs inside the `scene` layout, which is the one every workspace
---already has, and `hypr/scene/provider.lua` delegates here for a scene
---declaring `layout = "deck"`. The registration above stays for a host that
---can select it directly.
---Show exactly one member per column: raise it, and keep every member hidden
---behind it fully transparent.
---
---Z-order alone is not enough. The members share one box now, so a translucent
---window on top reads every window under it -- the column accumulated shade
---and tint with each hidden member. `opacity 0` takes the hidden ones out of
---the composite entirely.
---
---Both dispatches are deferred by a tick and issued only on a change: raising
---and setting a property each re-enter `recalculate`, and doing either from
---inside the pass is an unbounded recursion, not a redraw.
---@param boxes Scene.Box[]
---@param visible table<integer, string> column order -> address it shows
local function reveal_visible(boxes, visible)
  local shown = {}
  for _, address in pairs(visible) do
    shown[address] = true
  end

  local changed = {}
  for _, box in ipairs(boxes) do
    local want = shown[box.address] and 1 or 0
    if opacity_state[box.address] ~= want then
      opacity_state[box.address] = want
      changed[#changed + 1] = { address = box.address, opacity = want, raise = want == 1 }
    end
  end
  if #changed == 0 then
    return
  end

  require("hypr.lib.hypr").oneshot(1, function()
    for _, item in ipairs(changed) do
      hl.dispatch(hl.dsp.window.set_prop({
        window = "address:" .. item.address,
        prop = "opacity",
        value = item.opacity,
      }))
      if item.raise then
        hl.dispatch(hl.dsp.window.bring_to_top({ window = "address:" .. item.address }))
      end
    end
  end)
end

---@param scene Scene.Spec
---@param scene_name string
---@param ctx HL.LayoutContext
function M.place(scene, scene_name, ctx)
  local targets = ctx.targets or {}
  local by_address = {}
  for _, target in ipairs(targets) do
    if target.window and target.window.address then
      by_address[target.window.address] = target
    end
  end

  local gaps_in, gaps_out = gaps(scene)
  local tiles, _, positions = member_tiles(scene)
  -- Live truth first (Task A: survives a reload), then arrivals -- a window
  -- that opened since the last pass overrides whatever live position it
  -- inherited from wherever it happened to spawn.
  sync_scroll_from_live(scene, scene_name, tiles, ctx.area, positions)
  scroll_to_arrivals(scene, scene_name, tiles)
  local boxes, visible = deck.boxes(scene, tiles, ctx.area, {
    gaps_in = gaps_in,
    gaps_out = gaps_out,
    scroll = deck_scroll.get_all(scene_name),
  })
  reveal_visible(boxes, visible)
  for _, box in ipairs(boxes) do
    local target = by_address[box.address]
    if target then
      target:place({ x = box.x, y = box.y, w = box.w, h = box.h })
    else
      -- Not tiled here yet -- claimed by this column but still sitting
      -- wherever it opened. Ask it home; the move triggers another
      -- `recalculate`, which is the pass that actually places it (visible
      -- or off-screen, per this pass's scroll index) -- this one only
      -- reports the need, same as `deck.lua`'s own contract.
      hl.dispatch(hl.dsp.window.move({
        window = "address:" .. box.address,
        workspace = "name:" .. scene_name,
        follow = false,
      }))
    end
  end

  -- Read-only tail, the same one the scene provider runs: the isles a deck
  -- scene docks hang off the boxes just placed, and nothing here writes
  -- anywhere but the `geometry` store.
  if scene.docks then
    local top, right, bottom, left = require("hypr.scene.layout").sides(gaps_out)
    dock_publish.publish({
      scene = scene,
      monitor = M.monitor_of(scene_name),
      tiles = tiles,
      boxes = boxes,
      gaps_in = gaps_in or 0,
      gaps_out = { top = top, right = right, bottom = bottom, left = left },
      spec_lib = spec_lib,
    })
  end
end

---The live monitor a deck scene's workspace stands on, for the dock publish.
---@param scene_name string
---@return table?
function M.monitor_of(scene_name)
  for _, monitor in ipairs(hl.monitors or {}) do
    local ws = monitor.activeWorkspace
    if ws and ws.name == scene_name then
      return monitor
    end
  end
  return (hl.monitors or {})[1]
end

---Refocus a deck column after its visible member closes and another one
---falls into the now-empty slot, from OUTSIDE a layout callback.
---
---Placement itself needs no such repair post-LEO-402: every member already
---lives on the scene's own workspace (visible or off-screen), so an
---ordinary `recalculate` places all of them every pass with no move to
---dispatch. Focus is the one thing that does not repair itself: Hyprland's
---own close-focus handling can leave the keyboard on nothing, or on a
---member this deck is about to place off-screen, and "what is now visible"
---is `deck.boxes`'s decision, not something this module can read off a
---`window.close` event. Called once after a window closes, from
---`hypr/scene/provider.lua`'s `window.close` handler.
---@param scene_name string workspace/scene name
function M.reconcile(scene_name, closed)
  local scenes = spec_lib.load()
  local scene = scenes and scenes[scene_name]
  if not scene or not deck.applies(scene) then
    return
  end
  local area
  for _, m in ipairs(hl.get_monitors() or {}) do
    local ws = m.active_workspace
    if ws and (ws.name or ws) == scene_name then
      area = { x = m.x, y = m.y, w = m.width, h = m.height }
      break
    end
  end
  if not area then
    return
  end
  local tiles = member_tiles(scene)
  local gaps_in, gaps_out = gaps(scene)
  local _, visible = deck.boxes(scene, tiles, area, {
    gaps_in = gaps_in,
    gaps_out = gaps_out,
    scroll = deck_scroll.get_all(scene_name),
  })

  -- Focus belongs to the column that lost the window, while that column still
  -- has members: a close must not send the keyboard wandering into the
  -- neighbouring column. The closed window's own column is read from its
  -- class, since the window itself is already gone by now.
  local column = closed and closed.class and deck.column_for(scene, { class = closed.class, tags = closed.tags })
  local wanted = column and visible[column.order]
  if not wanted then
    -- No column to prefer (an unknown class, or that column is now empty):
    -- any visible member beats leaving the keyboard on nothing.
    for _, address in pairs(visible) do
      wanted = wanted or address
    end
  end
  if not wanted then
    return
  end

  local shown = {}
  for _, address in pairs(visible) do
    shown[address] = true
  end
  local active = hl.get_active_window()
  if not (active and shown[active.address]) then
    hl.dispatch(hl.dsp.focus({ window = "address:" .. wanted }))
  end
end

---Register with whatever the host declares. Separate from `register` so
---tests can drive the provider with their own scenes.
function M.attach()
  M.register(spec_lib.load)
end

return M
