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

  local scene = scene_for(targets, get_scenes())
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
    override = order.get(scene.name),
  })

  for _, box in ipairs(boxes) do
    local target = by_address[box.address]
    if target then
      target:place({ x = box.x, y = box.y, w = box.w, h = box.h })
    end
  end
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

---Every monitor whose active workspace runs this layout, briefly focused so
---`hyprctl dispatch layoutmsg` (which always targets the focused workspace)
---reaches it, then focus is restored. This is the engine-side fix for "a
---reload does not redraw the scenes themselves" (LEO-397): Hyprland's own
---`config.reloaded` event triggers no relayout for a custom Lua layout --
---confirmed by reading the compositor's source, where only the built-in
---scrolling layout listens for it. Also usable any time a declaration change
---needs to reach already-placed windows without waiting for the next window
---event.
function M.recalculate_all()
  local monitors = hl.get_monitors() or {}
  local focused = hl.get_active_monitor()
  for _, m in ipairs(monitors) do
    local ws = m.activeWorkspace
    if ws and layout_lib.bare_layout(ws.tiled_layout) == NAME then
      hl.dispatch(hl.dsp.focus({ monitor = m.name }))
      hl.dispatch(hl.dsp.layout("recalc"))
    end
  end
  if focused and focused.name then
    hl.dispatch(hl.dsp.focus({ monitor = focused.name }))
  end
end

---Register with whatever the host declares, read live on every recalculate
---(LEO-397), and force every scene workspace to redraw once whenever the
---compositor reloads its config -- Hyprland's reload re-executes this whole
---module but calls no layout's recalculate on its own.
function M.attach()
  M.register(spec_lib.load)
  hl.on("config.reloaded", M.recalculate_all)
end

return M
