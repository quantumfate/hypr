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

---Same fallback-ladder gap read as hypr/scene/provider.lua's private
---`gaps`/`spec_gaps` — duplicated rather than exported, since neither module
---should reach into the other's internals for two lines of arithmetic.
---@param scene_name string
---@return number gaps_in, number gaps_out
local function gaps(scene_name)
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
    if spec.default_name == scene_name then
      spec_in, spec_out = spec.gaps_in, spec.gaps_out
    end
  end
  local gaps_in = scalar(spec_in, scalar(raw("general:gaps_in", 0), 0))
  local gaps_out = scalar(spec_out, scalar(raw("general:gaps_out", 0), 0))
  return gaps_in, gaps_out
end

---Every window anywhere subscribing to `spec`'s columns — not only the ones
---currently tiled on the deck's own workspace, since a held member has
---already left it (docs/deck.md). Membership is class/tag matching, which
---has no notion of "current workspace".
---@param spec Scene.Spec
---@return Scene.Tile[]
local function member_tiles(spec)
  local tiles = {}
  for _, w in ipairs(hl.get_windows() or {}) do
    local tile = scene_provider.window_tile(w)
    if deck.column_for(spec, tile) then
      tiles[#tiles + 1] = tile
    end
  end
  return tiles
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
      local scene = decks[scene_name]

      local by_address = {}
      for _, target in ipairs(targets) do
        if target.window and target.window.address then
          by_address[target.window.address] = target
        end
      end

      local gaps_in, gaps_out = gaps(scene_name)
      local tiles = member_tiles(scene)
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
        -- Only park what is actually still tiled here; a member already in
        -- HOLD (or not yet arrived) needs no move.
        if by_address[address] then
          hl.dispatch(hl.dsp.window.move({
            window = "address:" .. address,
            workspace = HOLD,
            follow = false,
          }))
        end
      end
    end,
  })
end

---Register with whatever the host declares. Separate from `register` so
---tests can drive the provider with their own scenes.
function M.attach()
  M.register(spec_lib.load)
end

M.HOLD = HOLD

return M
