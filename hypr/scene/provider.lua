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

local M = {}

-- Registered under this name; a workspace opts in with `layout = "scene"`.
-- Workspaces that do not are untouched and keep dwindle, master or scrolling.
local NAME = "scene"

---Live gap values. Read from the compositor rather than cached, so a reload
---that changes them is picked up on the next recalculate without a second
---mechanism to keep in sync.
---@return number gaps_in, number gaps_out
local function gaps()
  local function number(key, fallback)
    local ok, value = pcall(hl.get_config, key)
    if not ok or value == nil then
      return fallback
    end
    -- Hyprland's CSS-style gaps can be a list; the first entry is the one a
    -- single-number layout wants.
    if type(value) == "table" then
      value = value[1]
    end
    return tonumber(value) or fallback
  end
  return number("general:gaps_in", 0), number("general:gaps_out", 0)
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
  return { address = w.address, class = w.class, group = key }
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

---@param scenes table<string, Scene.Spec>
function M.register(scenes)
  hl.layout.register(NAME, {
    recalculate = function(ctx)
      local targets = ctx.targets or {}
      if #targets == 0 then
        return
      end

      local scene = scene_for(targets, scenes)
      if not scene then
        -- A workspace set to this layout with no scene declared: lay the
        -- windows out evenly rather than leaving them stacked at the origin.
        -- Doing nothing here would look like the compositor had hung.
        local gaps_in, gaps_out = gaps()
        local area = ctx.area
        local usable = area.w - gaps_out * 2 - gaps_in * (#targets - 1)
        local width = math.floor(usable / #targets)
        for i, target in ipairs(targets) do
          target:place({
            x = area.x + gaps_out + (i - 1) * (width + gaps_in),
            y = area.y + gaps_out,
            w = width,
            h = area.h - gaps_out * 2,
          })
        end
        return
      end

      local tiles, by_address = tiles_of(targets)
      local gaps_in, gaps_out = gaps()
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
    end,
  })
end

---Register with whatever the host declares. Separate from `register` so tests
---can drive the provider with their own scenes.
function M.attach()
  M.register(spec_lib.load())
end

return M
