-- The scene, registered as a Hyprland layout.
--
-- A thin shell over hypr/scene/layout.lua: read the targets the compositor
-- offers, ask the pure function where they go, place them. The compositor
-- calls this whenever the workspace changes, which is what answers "re-apply
-- on every event that can change window state" without subscribing to
-- anything and without guessing which events matter.
--
-- Nothing here dispatches, focuses, or sets a timer. That is the whole point:
-- geometry stops depending on which window has focus, and there is no
-- correction to verify because there was no correction.
local spec_lib = require("hypr.scene.spec")
local layout = require("hypr.scene.layout")
local order = require("hypr.scene.order")
local layout_lib = require("hypr.lib.layout")
local dock_publish = require("hypr.scene.dock_publish")

local M = {}

-- Registered under this name; a workspace opts in with `layout = "scene"`.
-- Workspaces that do not are untouched and keep scrolling.
local NAME = "scene"

---A workspace's own gaps, from the resolved host data (`conf/host.lua`'s
---`geometry.resolve()` already filled each spec's per-monitor gaps at load
---time -- see `hypr/lib/geometry.lua`), keyed by scene name == workspace
---`default_name`. nil when the workspace has no spec, or the spec left a
---field unset.
---@param scene_name string?
---@return number? gaps_in, Scene.CssGap? gaps_out
local function host_gaps(scene_name)
  if not scene_name then
    return nil, nil
  end
  local specs = config and config.host and config.host.workspaces and config.host.workspaces.workspace_specs
  for _, spec in ipairs(specs or {}) do
    if spec.default_name == scene_name then
      return spec.gaps_in, spec.gaps_out
    end
  end
  return nil, nil
end

---Live gap values for one scene's workspace, precedence high to low: the
---scene's own declared `gaps_in`/`gaps_out` (LEO-397 -- the user's compromise,
---"a scene's gaps beat the host profile where they differ"), then the host
---workspace-spec gaps, then the compositor's global config (read live, not
---cached, so a reload is picked up on the next recalculate).
---@param scene Scene.Spec? nil for an undeclared workspace
---@return number gaps_in, Scene.CssGap gaps_out
local function gaps(scene)
  local function raw(key, fallback)
    local ok, value = pcall(hl.get_config, key)
    if not ok or value == nil then
      return fallback
    end
    return value
  end
  local host_in, host_out = host_gaps(scene and scene.name)
  local global_in = raw("general:gaps_in", 0)
  -- gaps_in has no directional meaning here (only the space between tiles),
  -- so a sided table (Hyprland marshals gaps this way regardless of whether
  -- the config set them uniformly) collapses to its `top`, same as a uniform
  -- number would read.
  if type(global_in) == "table" then
    global_in = global_in.top or 0
  end
  local gaps_in = (scene and scene.gaps_in) or host_in or tonumber(global_in) or 0
  local gaps_out = (scene and scene.gaps_out) or host_out or raw("general:gaps_out", 0)
  return gaps_in, gaps_out
end

---Whether a scene's workspace sits on the host's primary monitor (LEO-421):
---the lone-tile centring in `layout.lua` only makes sense there, since a
---secondary panel has no ultrawide width to compensate for. Read straight off
---`config.host`, already resolved to real output names by `geometry.resolve`
---at load — no live monitor query needed, unlike `conf/host.lua`'s own
---`monitor_roles`, which exists to publish the map, not to answer one lookup.
---A host with no `primary_monitor`, or a workspace with no spec, or one whose
---spec never set `monitor`, reads as primary: never withholding centring on a
---plain declaration.
---@param scene_name string
---@return boolean
local function is_primary_monitor(scene_name)
  local host = config and config.host
  local primary = host and host.primary_monitor
  if not primary then
    return true
  end
  local specs = host.workspaces and host.workspaces.workspace_specs
  for _, spec in ipairs(specs or {}) do
    if spec.default_name == scene_name then
      return spec.monitor == nil or spec.monitor == primary
    end
  end
  return true
end

---The scene a set of targets belongs to, or nil when the workspace has none.
---Taken from the windows rather than from an active-workspace lookup: a layout
---may be asked to recalculate a workspace the user is not looking at, and
---reading the active one would arrange the wrong desk.
---@param targets HL.LayoutTarget[]
---@param scenes table<string, Scene.Spec>
---@return Scene.Spec?
local function scene_for(targets, scenes)
  for _, target in ipairs(targets) do
    local ws = target.window and target.window.workspace
    if ws and ws.name and scenes[ws.name] then
      return scenes[ws.name]
    end
  end
  return nil
end

---One window (as `hl.get_windows()`/`target.window` reports it) as a
---`Scene.Tile`. A group's identity is its lowest member address: group
---objects are not comparable across reads, and the member set is what "same
---group" means.
---@param w HL.Window
---@return Scene.Tile
local function window_tile(w)
  local key
  if w.group then
    for _, member in
      ipairs(w.group.members and (w.group.members.title and { w.group.members } or w.group.members) or {})
    do
      if member.address and (not key or member.address < key) then
        key = member.address
      end
    end
  end
  -- `focus` (Hyprland's `focusHistoryID`) lets `hypr/lib/nav.lua` pick a
  -- group's current/visible member instead of an arbitrary one (LEO-380).
  return { address = w.address, class = w.class, tags = w.tags, group = key, focus = w.focusHistoryID }
end
-- Exposed so `hypr/binds.lua` can build the same tile list the layout used
-- last, straight from `hl.get_windows()`, for the keyboard-navigation binds
-- (`hypr/lib/nav.lua`) — one tiling rule, not a second one reimplemented at
-- the bind site.
M.window_tile = window_tile

---The tiled (non-floating) windows on one workspace, as `Scene.Tile`s, in
---whatever order `hl.get_windows()` returns them.
---@param window_name string workspace `default_name`
---@return Scene.Tile[]
function M.workspace_tiles(window_name)
  local tiles = {}
  for _, w in ipairs(hl.get_windows() or {}) do
    if not w.floating and w.workspace and w.workspace.name == window_name then
      tiles[#tiles + 1] = window_tile(w)
    end
  end
  return tiles
end

---The tiles a scene arranges, in the order the compositor offered them.
---@param targets HL.LayoutTarget[]
---@return Scene.Tile[], table<string, HL.LayoutTarget>
local function tiles_of(targets)
  local tiles, by_address = {}, {}
  for _, target in ipairs(targets) do
    local w = target.window
    if w and w.address then
      tiles[#tiles + 1] = window_tile(w)
      by_address[w.address] = target
    end
  end
  return tiles, by_address
end

---The monitor a scene's targets stand on, as live geometry. Read from the
---compositor rather than the host data, since a dock is positioned inside its
---own output and needs that output's real size.
---@param targets table[]
---@return table?
local function monitor_of(targets)
  local ws = targets[1] and targets[1].window and targets[1].window.workspace
  local want = ws and ws.monitor and ws.monitor.name
  for _, monitor in ipairs(hl.monitors or {}) do
    if monitor.name == want then
      return monitor
    end
  end
  return (hl.monitors or {})[1]
end

---Publish the scene's resolved docks for the monitor it was just placed on.
---@param scene Scene.Spec
---@param tiles Scene.Tile[]
---@param boxes Scene.Box[]
---@param targets table[]
local function publish_docks(scene, tiles, boxes, targets)
  if not scene.docks then
    return
  end
  local monitor = monitor_of(targets)
  if not monitor then
    return
  end
  local gaps_in, gaps_out = gaps(scene)
  local top, right, bottom, left = layout.sides(gaps_out)
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

---Place `targets` per one recalculate call, against whatever `get_scenes()`
---answers right now -- called fresh every time (window events, and the
---`layout_msg`-forced recalc below), so a declaration edit lands on the next
---call with no reload (LEO-397).
---@param get_scenes fun(): table<string, Scene.Spec>
---@param ctx HL.LayoutRecalcCtx
local function place(get_scenes, ctx)
  local targets = ctx.targets or {}
  if #targets == 0 then
    return
  end

  -- A scene declaring the deck runs its placement here, inside the layout
  -- every workspace already has. On this build a workspace rule's `layout`
  -- resolves builtin layouts only (`master`/`dwindle` take; `scene`, `deck`,
  -- `lua:scene`, `lua:deck` all fall through), so `deck` cannot be selected
  -- per-workspace as its own registered layout -- which is how the engine
  -- ended up computing deck geometry while this layout drew the workspace.
  -- Skipped when the workspace really is on the deck layout already, so a
  -- host that CAN select it is placed once, by the deck provider itself.
  local scene = scene_for(targets, get_scenes())
  if scene and require("hypr.scene.deck").applies(scene) then
    local ws = targets[1] and targets[1].window and targets[1].window.workspace
    local on_deck = ws and layout_lib.bare_layout(ws.tiled_layout) == "deck"
    if ws and ws.name and not on_deck then
      require("hypr.scene.deck_provider").place(scene, ws.name, ctx)
      return
    end
  end
  if not scene then
    -- A workspace set to this layout with no scene declared: lay the windows
    -- out evenly rather than leaving them stacked at the origin. Doing
    -- nothing here would look like the compositor had hung.
    local gaps_in, gaps_out = gaps(nil)
    local top, right, bottom, left = layout.sides(gaps_out)
    local area = ctx.area
    local usable = area.w - left - right - gaps_in * (#targets - 1)
    local width = math.floor(usable / #targets)
    for i, target in ipairs(targets) do
      target:place({
        x = area.x + left + (i - 1) * (width + gaps_in),
        y = area.y + top,
        w = width,
        h = area.h - top - bottom,
      })
    end
    return
  end

  local tiles, by_address = tiles_of(targets)
  local gaps_in, gaps_out = gaps(scene)
  local boxes = layout.boxes(scene, tiles, ctx.area, {
    gaps_in = gaps_in,
    gaps_out = gaps_out,
    solo_frame = scene.solo_frame ~= false,
    is_primary = is_primary_monitor(scene.name),
    override = order.get(scene.name),
  })

  for _, box in ipairs(boxes) do
    local target = by_address[box.address]
    if target then
      target:place({ x = box.x, y = box.y, w = box.w, h = box.h })
    end
  end

  -- Read-only tail: the scene's isles hang off the boxes just placed, so this
  -- is the one pass that knows where they go. It writes to the `geometry`
  -- store and nowhere else -- never a place, never a dispatch, never a
  -- recalculate -- so a dock can't move the tile it docks to.
  publish_docks(scene, tiles, boxes, targets)
end

---@param scenes table<string, Scene.Spec>|fun(): table<string, Scene.Spec>
function M.register(scenes)
  -- `M.attach()` passes a resolver so every recalculate re-reads the live
  -- declaration; tests pass a plain table fixture, read once, which is fine
  -- since they own the whole lifetime of that table.
  local get_scenes = type(scenes) == "function" and scenes or function()
    return scenes
  end
  hl.layout.register(NAME, {
    recalculate = function(ctx)
      place(get_scenes, ctx)
    end,
    -- Exists so `hyprctl dispatch layoutmsg <name> recalc` reaches this
    -- provider: Hyprland's CLuaTiledAlgorithm::layoutMsg only calls its own
    -- unconditional recalculate() afterward when `layout_msg` is a function
    -- (verified in Hyprland's src/config/lua/layout/LuaLayoutProvider.cpp) --
    -- this is the engine's forced-recalc primitive (LEO-397), used below to
    -- redraw scenes after a config reload, which does not do this itself.
    layout_msg = function()
      return true
    end,
  })
end

---Force the currently-focused workspace's scene layout to redraw, with NO
---focus dispatched at all -- not even to the workspace already focused.
---
---LEO-403: the previous version of this function focus-danced across every
---monitor (`hl.dsp.focus` to each in turn, then back) to reach each one's
---`layoutMsg`, fighting the "a reload keeps your focus" rule this repo
---enforces elsewhere (`hypr/hyprfocus/focus_history.lua`). Read from the
---compositor's own source (`hyprland-git` at the commit `docs/live-config.md`
---names) before removing it: `LayoutManager::layoutMsg`
---(`src/layout/LayoutManager.cpp`) hardcodes its target to
---`Desktop::focusState()->monitor()`'s active workspace -- there is no
---workspace- or monitor-scoped variant, and nothing else reaches a custom Lua
---layout's `recalculate` without a real window event
---(`CLuaTiledAlgorithm::newTarget/removeTarget/resizeTarget/
---moveTargetInDirection`, `src/config/lua/layout/LuaLayoutProvider.cpp`, all
---of which either fire from window lifecycle events or require the target to
---be floating). The one C++-internal primitive that recalculates a specific,
---possibly-unfocused monitor, `CLayoutManager::recalculateMonitor`
---(`src/layout/LayoutManager.cpp`), is never exposed to a dispatch or Lua
---binding (grepped `src/config/lua/bindings/` -- absent), so Lua has no way to
---reach it either.
---
---Net: a scene workspace that is not the one currently focused cannot be
---forced to redraw without moving focus there. Every other scene workspace is
---corrected lazily instead -- by `M.recalculate_focused` below, wired to
---`workspace.active`, so it redraws the instant it next becomes the focused
---one (a real focus change the user or another part of the desk already
---made, never one this function causes), and by the ordinary window
---open/close/move/resize events every workspace's own layout algorithm
---already reacts to.
function M.recalculate_focused()
  -- Only when the focused workspace is actually on this layout.
  --
  -- `layoutmsg` is delivered to whichever layout owns the focused monitor's
  -- active workspace (`LayoutManager::layoutMsg` hardcodes that target — see
  -- the doc above), NOT to the layout that sent it. Every workspace without a
  -- rule of its own runs `dwindle`: the shelves, `special:hyprfocus-held`,
  -- and any bare numbered workspace (verified live — `hyprctl workspaces`
  -- reports `tiledLayout: dwindle` for all of them, while the scene ones
  -- report `lua:scene`). So an unguarded `recalc` sent while one of those is
  -- focused — during a mode swap, which shows and hides the holding place,
  -- or right after a window closes on a shelf — lands on `dwindle`, which
  -- implements no such message. Nothing is redrawn and the compositor logs
  -- the miss.
  if not M.focused_is_scene() then
    return
  end
  hl.dispatch(hl.dsp.layout("recalc"))
end

---Whether the focused workspace is laid out by this provider.
---@return boolean
function M.focused_is_scene()
  local ws = hl.get_active_special_workspace() or hl.get_active_workspace()
  return ws ~= nil and layout_lib.bare_layout(ws.tiled_layout) == NAME
end

---Lazy correction for every OTHER scene workspace (LEO-403): wired to
---`workspace.active`, which fires whenever the focused workspace changes for
---any reason this code did not initiate, so calling `recalculate_focused`
---here never dispatches a focus change of its own -- it only reacts to one
---that already happened. `layoutMsg` targets whichever monitor is now
---focused (see `M.recalculate_focused`'s doc), so this redraws exactly the
---workspace that just became visible, picking up any declaration/gaps edit
---that landed while it was off-screen.
local function recalculate_on_arrival()
  if M.focused_is_scene() then
    require("hypr.lib.hypr").oneshot(1, M.recalculate_focused)
  end
end

---Register with whatever the host declares, read live on every recalculate
---(LEO-397), and force the focused scene to redraw once whenever the
---compositor reloads its config -- Hyprland's reload re-executes this whole
---module but calls no layout's recalculate on its own. Every other scene
---workspace corrects itself lazily (LEO-403; see `recalculate_focused`'s doc
---for why no focus-free mechanism reaches it any sooner).
function M.attach()
  M.register(spec_lib.load)
  hl.on("config.reloaded", M.recalculate_focused)
  hl.on("workspace.active", recalculate_on_arrival)
  -- A closing window frees the slot its column was showing; `recalculate`
  -- places whatever falls into it (every deck member already lives on this
  -- workspace, LEO-402), but Hyprland's own close-focus handling can leave
  -- the keyboard on nothing or on a member about to go off-screen. One
  -- deferred pass repairs focus (`deck_provider.reconcile`) and then
  -- redraws; the tick lets the compositor finish removing the window first,
  -- so the pass sees the stack it actually left.
  hl.on("window.close", function(w)
    -- Retire the address first, synchronously: the deferred pass below must
    -- not see a closed window still counted as a member this scene placed.
    require("hypr.scene.deck_provider").forget(w and w.address)
    require("hypr.lib.hypr").oneshot(1, function()
      local ws = hl.get_active_workspace()
      if ws and ws.name then
        require("hypr.scene.deck_provider").reconcile(ws.name)
      end
      M.recalculate_focused()
    end)
  end)
end

return M
