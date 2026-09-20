-- The `deck` scene, registered as a Hyprland layout.
--
-- Thin shell over hypr/scene/deck.lua, mirroring hypr/scene/provider.lua's
-- shape: read the live windows a deck's columns subscribe to, ask the pure
-- function where they go, place the visible ones and dispatch the rest to
-- hold. Nothing here decides geometry or membership — that is deck.lua's
-- job; this module only executes what it reports (docs/deck.md "Why hidden
-- windows are HELD").
local spec_lib = require("hypr.scene.spec")
local deck = require("hypr.scene.deck")
local deck_scroll = require("hypr.scene.deck_scroll")
local scene_provider = require("hypr.scene.provider")
local dock_publish = require("hypr.scene.dock_publish")

local M = {}

local NAME = "deck"

-- Where a deck's non-visible members park. One shared special workspace
-- (docs/deck.md leaves per-scene holding as an open question; a single area
-- is the simpler default and, like hypr/hyprfocus/hold.lua's HELD, is never
-- declared so no mode can ever admit or withdraw it).
local HOLD = "special:deck-hold"

---A gap value as one scalar: already a number, or a sided `Scene.CssGap`
---table's `left` (`deck.lua`'s `opts.gaps_out` is one symmetric number on
---every side, unlike `layout.lua`'s `sides`, which is why this collapses
---rather than passing the table through — see `deck.lua`'s module comment).
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
---profile at load), then the compositor's global config, read live. Every
---rung collapses to one symmetric number via `scalar` — `deck.lua`'s
---`opts.gaps_out` is one number on every side, unlike `layout.lua`'s `sides`
---(see `deck.lua`'s module comment).
---@param scene Scene.Spec
---@return number gaps_in, number gaps_out
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
  local global_out = scalar(raw("general:gaps_out", 0), 0)
  local gaps_in = scalar(scene.gaps_in, scalar(spec_in, global_in))
  local gaps_out = scalar(scene.gaps_out, scalar(spec_out, global_out))
  return gaps_in, gaps_out
end

---Every window anywhere subscribing to `spec`'s columns — not only the ones
---currently tiled on the deck's own workspace, since a held member has
---already left it (docs/deck.md). Membership is class/tag matching, which
---has no notion of "current workspace".
---@param spec Scene.Spec
---@return Scene.Tile[]
---@return Scene.Tile[] tiles
---@return table<string, string> workspace_of live workspace name per address
local function member_tiles(spec)
  local tiles, workspace_of = {}, {}
  for _, w in ipairs(hl.get_windows() or {}) do
    local tile = scene_provider.window_tile(w)
    if deck.column_for(spec, tile) then
      tiles[#tiles + 1] = tile
      local ws = w.workspace
      if tile.address and ws and ws.name then
        workspace_of[tile.address] = ws.name
      end
    end
  end
  return tiles, workspace_of
end

---Every address each deck scene held on its last placement, so a window that
---has just arrived can be told apart from one deliberately scrolled out of
---view.
---@type table<string, table<string, true>>
local seen = {}

---Put the hold workspace away if moving a member there pulled it into view.
---
---Moving a window to a special workspace makes the compositor show that
---special on the monitor, so a held member -- a window the deck means to be
---invisible -- ends up drawn over whatever workspace is active, including one
---belonging to another scene entirely. Deferred by a tick: a dispatch from
---inside the layout pass re-enters `recalculate`.
local function hide_hold_if_shown()
  local shown = false
  for _, monitor in ipairs(hl.get_monitors() or {}) do
    local special = monitor.specialWorkspace or monitor.special_workspace
    local name = special and (special.name or special)
    if name == HOLD then
      shown = true
    end
  end
  if not shown then
    return
  end
  require("hypr.lib.hypr").oneshot(1, function()
    hl.dispatch(hl.dsp.workspace.toggle_special(HOLD:gsub("^special:", "")))
  end)
end

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
end

---The live monitor a deck scene's workspace stands on, for the dock publish.
---@param scene_name string
---@return table?
local function monitor_of(scene_name)
  for _, monitor in ipairs(hl.get_monitors() or hl.monitors or {}) do
    local ws = monitor.activeWorkspace or monitor.active_workspace
    if ws and (ws.name or ws) == scene_name then
      return monitor
    end
  end
  return (hl.get_monitors() or hl.monitors or {})[1]
end

---Publish where this scene's quickshell isles sit, off the boxes just placed.
---@param scene Scene.Spec
---@param scene_name string
---@param tiles Scene.Tile[]
---@param boxes Scene.Box[]
---@param gaps_in number
---@param gaps_out number|Scene.CssGap
local function publish_docks(scene, scene_name, tiles, boxes, gaps_in, gaps_out)
  if not scene.docks then
    return
  end
  local monitor = monitor_of(scene_name)
  if not monitor then
    return
  end
  local top, right, bottom, left = require("hypr.scene.layout").sides(gaps_out)
  dock_publish.publish({
    scene = scene,
    monitor = monitor,
    tiles = tiles,
    boxes = boxes,
    gaps_in = gaps_in or 0,
    gaps_out = { top = top, right = right, bottom = bottom, left = left },
    spec_lib = spec_lib,
  })
end

---Point a column at a window that has just arrived in it.
---
---Without this, a newly-spawned window landed wherever its column's scroll
---already sat, was therefore not that column's visible member, and got parked
---in `HOLD` -- a special workspace, which the compositor then focuses. Opening
---a terminal on a deck workspace threw the desk onto an empty special
---workspace, which is the bug this exists to stop. Opening a window is an
---implicit request to see it, so its column scrolls to it rather than hiding
---it. A window scrolled away by hand is untouched: it is not new.
---@param spec Deck.Spec
---@param scene_name string
---@param tiles Scene.Tile[]
local function scroll_to_arrivals(spec, scene_name, tiles)
  local previous = seen[scene_name]
  -- Record EVERY member, not just the ones on the workspace. Recording only
  -- the on-workspace ones meant a held member never entered the set, so it
  -- read as new on the very next pass -- the column scrolled to it, which
  -- held the other one, which then read as new in turn. The two swapped
  -- places forever and the deck never settled. Membership is the right key:
  -- "new" must mean "this scene has never placed this window", which happens
  -- exactly once per window.
  local current = {}
  for _, tile in ipairs(tiles) do
    if tile.address then
      current[tile.address] = true
    end
  end
  seen[scene_name] = current
  for order, stack in pairs(deck.stacks(spec, tiles)) do
    for index, tile in ipairs(stack) do
      -- An arrival is a member this pass has not seen before that is ALSO
      -- sitting on the deck's own workspace. The workspace test is what makes
      -- the very first pass correct: with no previous set every member looks
      -- new, but a member already parked in `HOLD` is not on the workspace, so
      -- only something that genuinely just opened qualifies. It also keeps a
      -- reload from yanking a column off a position chosen by hand.
      -- Deliberately NOT gated on the window being on the deck's workspace:
      -- the pass that first sees a new window can run while the compositor is
      -- still placing it, and the pass after that it has already been parked
      -- in `HOLD` -- so it would never once qualify. Membership is enough,
      -- since `seen` makes "new" mean "this scene has never placed it".
      local unseen = tile.address and previous and not previous[tile.address]
      if unseen then
        deck_scroll.set(scene_name, order, index)
        break
      end
    end
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
---@param scene Scene.Spec
---@param scene_name string
---@param ctx HL.LayoutContext
function M.place(scene, scene_name, ctx)
  do
    local targets = ctx.targets or {}
    local by_address = {}
    for _, target in ipairs(targets) do
      if target.window and target.window.address then
        by_address[target.window.address] = target
      end
    end

    local gaps_in, gaps_out = gaps(scene)
    local tiles, workspace_of = member_tiles(scene)
    scroll_to_arrivals(scene, scene_name, tiles)
    local boxes, hold = deck.boxes(scene, tiles, ctx.area, {
      gaps_in = gaps_in,
      gaps_out = gaps_out,
      scroll = deck_scroll.get_all(scene_name),
    })
    for _, box in ipairs(boxes) do
      local target = by_address[box.address]
      if target then
        target:place({ x = box.x, y = box.y, w = box.w, h = box.h })
      else
        -- Not tiled here yet (freshly scrolled to, or freshly held
        -- elsewhere): ask it home. The move triggers another
        -- `recalculate`, which is the pass that actually places it — this
        -- one only reports the need, same as `deck.lua`'s own contract.
        hl.dispatch(hl.dsp.window.move({
          window = "address:" .. box.address,
          workspace = "name:" .. scene_name,
          follow = false,
        }))
      end
    end

    for _, address in ipairs(hold) do
      -- Ask the COMPOSITOR where the window is, not this layout's target
      -- list. A window can sit on the deck's workspace while the layout has
      -- not adopted it -- moving one back from `HOLD` leaves it on the
      -- workspace but absent from `ctx.targets` -- and gating on the target
      -- list then skipped its move forever, stranding it as a full-width
      -- overlay over the columns (verified live). A member already in `HOLD`,
      -- or not yet anywhere, still needs no move.
      local at = workspace_of[address]
      if at and at ~= HOLD then
        hl.dispatch(hl.dsp.window.move({
          window = "address:" .. address,
          workspace = HOLD,
          follow = false,
        }))
      end
    end

    hide_hold_if_shown()

    -- Read-only tail, the same one the scene provider runs: a scene's isles
    -- hang off the boxes just placed. It writes to the `geometry` store and
    -- nowhere else -- no place, no dispatch, no recalculate.
    publish_docks(scene, scene_name, tiles, boxes, gaps_in, gaps_out)
  end
end

---Bring a deck scene's windows to where its scroll says they belong, from
---OUTSIDE a layout callback.
---
---`M.place` already computes this, but it runs inside `recalculate`, and a
---window move dispatched from there only lands when a real compositor event
---drove the pass -- a `layoutmsg`-driven recalculate silently drops them
---(verified live: closing a window left its column empty for as long as you
---like, while switching workspace and back fixed it instantly). So an event
---handler calls this instead: it dispatches only the moves, and the
---compositor's own recalculate that each move triggers does the placing.
---@param scene_name string workspace/scene name
function M.reconcile(scene_name)
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
  local tiles, workspace_of = member_tiles(scene)
  local gaps_in, gaps_out = gaps(scene)
  local boxes, hold = deck.boxes(scene, tiles, area, {
    gaps_in = gaps_in,
    gaps_out = gaps_out,
    scroll = deck_scroll.get_all(scene_name),
  })
  -- Whether anything the deck wants shown is currently focused. Read BEFORE
  -- the moves below, because a window arriving does not change focus
  -- (`follow = false`) and so cannot answer this afterwards.
  local active = hl.get_active_window()
  local focus_held = false
  local first_home
  for _, box in ipairs(boxes) do
    if workspace_of[box.address] ~= scene_name then
      first_home = first_home or box.address
      hl.dispatch(hl.dsp.window.move({
        window = "address:" .. box.address,
        workspace = "name:" .. scene_name,
        follow = false,
      }))
    elseif active and active.address == box.address then
      focus_held = true
    end
  end
  -- Closing the focused window leaves focus on nothing, and the member the
  -- deck brings home to replace it arrives unfocused -- `follow = false`, so
  -- that the ordinary swap does not yank focus. The result was a visible
  -- window the keyboard could not reach at all: not focusable, not closable.
  -- So when the deck had to bring something home AND nothing it shows is
  -- focused, focus what arrived. Guarded both ways, this never steals focus
  -- during a normal scroll -- there the replaced member is still focused.
  if first_home and not focus_held then
    require("hypr.lib.hypr").oneshot(1, function()
      hl.dispatch(hl.dsp.focus({ window = "address:" .. first_home }))
    end)
  end
  for _, address in ipairs(hold) do
    local at = workspace_of[address]
    if at and at ~= HOLD then
      hl.dispatch(hl.dsp.window.move({ window = "address:" .. address, workspace = HOLD, follow = false }))
    end
  end
end

---Register with whatever the host declares. Separate from `register` so
---tests can drive the provider with their own scenes.
function M.attach()
  M.register(spec_lib.load)
end

M.HOLD = HOLD

return M
